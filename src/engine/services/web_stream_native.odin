#+build !js
package services

import "core:c"
import "core:strings"
import "core:sync"
import curl "vendor:curl"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import tracy "../util/odin-tracy"
import vm "../vm"

WebStreamClient_Class := classes.Class_Info{name = "WebStreamClient", parent = &classes.Instance_Class}

WEB_STREAM_MESSAGE_LIMIT :: 16 * 1024 * 1024
WEB_STREAM_CLIENT_LIMIT :: 32

WebStreamClient :: struct {
	using object: classes.Object,
	service: ^HttpService,
	easy: ^curl.CURL,
	multi: ^curl.CURLM,
	added_to_multi: bool,
	state: enums.WebStreamClientState,
	message: [dynamic]u8,
	outgoing: [dynamic]string,
	outgoing_size, sent: int,
	headers: [dynamic]u8,
	request_headers: ^curl.slist,
	opened, closed, errored, received: ^signals.Signal,
}

web_stream_curl_init: sync.Once
web_stream_curl_ready: bool

web_stream_init_curl :: proc() {
	web_stream_curl_ready = curl.global_init(c.long(curl.GLOBAL_DEFAULT)) == .E_OK
}

web_stream_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	client := new(WebStreamClient)
	client.object = classes.Object_Init(&WebStreamClient_Class, "WebStreamClient")
	return &client.object
}

web_stream_cleanup :: proc(client: ^WebStreamClient) {
	if client.added_to_multi {
		_ = curl.multi_remove_handle(client.multi, client.easy)
		client.added_to_multi = false
	}
	if client.easy != nil {curl.easy_cleanup(client.easy); client.easy = nil}
	if client.multi != nil {_ = curl.multi_cleanup(client.multi); client.multi = nil}
	if client.request_headers != nil {
		curl.slist_free_all(client.request_headers)
		client.request_headers = nil
	}
	delete(client.message)
	client.message = nil
	delete(client.headers)
	client.headers = nil
	for message in client.outgoing {delete(message)}
	delete(client.outgoing)
	client.outgoing = nil
	client.outgoing_size, client.sent = 0, 0
}

web_stream_untrack :: proc(client: ^WebStreamClient) {
	service := client.service
	client.service = nil
	if service == nil {return}
	for current, index in service.web_streams {
		if current == client {ordered_remove(&service.web_streams, index); break}
	}
}

web_stream_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	client := cast(^WebStreamClient)object
	web_stream_untrack(client)
	web_stream_cleanup(client)
	for signal in ([?]^signals.Signal{client.opened, client.closed, client.errored, client.received}) {
		if signal != nil {signals.Destroy(signal)}
	}
	classes.Object_Destroy(object)
	free(client)
}

web_stream_finish :: proc(client: ^WebStreamClient, L: ^vm.State, status: int = 0, error_message := "") {
	if client.state == .Closed || client.state == .Error {return}
	client.state = .Closed if error_message == "" else .Error
	web_stream_untrack(client)
	web_stream_cleanup(client)
	if error_message != "" {
		if client.errored != nil {
			vm.PushInteger(L, i64(status))
			vm.PushString(L, error_message)
			signals.Fire(L, client.errored, 2)
			vm.Pop(L, 2)
		}
	} else if client.closed != nil {
		signals.Fire(L, client.closed)
	}
}

web_stream_get :: proc(L: ^vm.State, object: ^classes.Object, dt: ^datatypes.Registry, en: ^enums.Registry, key: string) -> bool {
	client := cast(^WebStreamClient)object
	slot: ^^signals.Signal
	switch key {
	case "ConnectionState":
		return enums.Push_Item_By_Value(L, en, "WebStreamClientState", i64(client.state))
	case "Close", "Send":
		vm.PushUserdataMethod(L, key)
		return true
	case "Opened": slot = &client.opened
	case "Closed": slot = &client.closed
	case "Error": slot = &client.errored
	case "MessageReceived": slot = &client.received
	case: return false
	}
	if slot^ == nil {slot^ = signals.Create(object.signal_registry.signal_registry)}
	signals.Push(L, slot^)
	return true
}

web_stream_namecall :: proc(L: ^vm.State, object: ^classes.Object, dt: ^datatypes.Registry, en: ^enums.Registry, method: string) -> (i32, bool) {
	client := cast(^WebStreamClient)object
	switch method {
	case "Close":
		if client.state == .Open {
			sent: c.size_t
			_ = curl.ws_send(client.easy, nil, 0, &sent, 0, curl.WS_CLOSE)
		}
		web_stream_finish(client, L)
		return 0, true
	case "Send":
		if client.state != .Open {return vm.RaiseError(L, "WebSocket is not open"), true}
		message := vm.ArgString(L, 2)
		if len(message) > WEB_STREAM_MESSAGE_LIMIT - client.outgoing_size || len(client.outgoing) >= 256 {
			return vm.RaiseError(L, "WebSocket send queue is full"), true
		}
		append(&client.outgoing, strings.clone(message))
		client.outgoing_size += len(message)
		return 0, true
	}
	return 0, false
}

web_stream_header :: proc "c" (data: [^]u8, size, count: c.size_t, user_data: rawptr) -> c.size_t {
	context = tracy.DefaultContext()
	client := cast(^WebStreamClient)user_data
	length := size * count
	if length > c.size_t(64 * 1024 - len(client.headers)) {return 0}
	append(&client.headers, ..data[:int(length)])
	return length
}

http_service_create_web_stream :: proc(service: ^HttpService, L: ^vm.State, en: ^enums.Registry) -> i32 {
	if !service.http_enabled || service.object.signal_registry.mode != .Editor {
		return vm.RaiseError(L, "WebSocket clients require HTTP access in the editor")
	}
	kind := enums.Arg_Item(L, 2, en, "WebStreamClientType")
	if kind == nil || enums.WebStreamClientType(kind.value) != .WebSocket {
		return vm.RaiseError(L, "only WebSocket streams are supported")
	}
	if !vm.IsTable(L, 3) {return vm.RaiseError(L, "expected a WebSocket request table")}
	vm.GetField(L, 3, "Url")
	url := vm.ArgString(L, -1)
	if (!strings.has_prefix(url, "ws://") && !strings.has_prefix(url, "wss://")) ||
	   strings.index_byte(url, 0) >= 0 {
		return vm.RaiseError(L, "WebSocket URL must use ws:// or wss://")
	}
	if len(service.web_streams) >= WEB_STREAM_CLIENT_LIMIT {return vm.RaiseError(L, "too many open WebSockets")}
	sync.once_do(&web_stream_curl_init, web_stream_init_curl)
	if !web_stream_curl_ready {return vm.RaiseError(L, "could not initialize WebSockets")}

	c_url := strings.clone_to_cstring(url, context.temp_allocator)
	object, ok := classes.Push_New(service.object.signal_registry, &vm.VM{L = L}, "WebStreamClient", false)
	if !ok {return vm.RaiseError(L, "could not create WebStreamClient")}
	client := cast(^WebStreamClient)object
	client.easy = curl.easy_init()
	client.multi = curl.multi_init()
	if client.easy == nil || client.multi == nil ||
	   curl.easy_setopt(client.easy, .URL, c_url) != .E_OK ||
	   curl.easy_setopt(client.easy, .CONNECT_ONLY, c.long(2)) != .E_OK ||
	   curl.easy_setopt(client.easy, .TIMEOUT_MS, c.long(10000)) != .E_OK ||
	   curl.easy_setopt(client.easy, .NOSIGNAL, c.long(1)) != .E_OK ||
	   curl.easy_setopt(client.easy, .HEADERFUNCTION, web_stream_header) != .E_OK ||
	   curl.easy_setopt(client.easy, .HEADERDATA, rawptr(client)) != .E_OK ||
	   curl.multi_add_handle(client.multi, client.easy) != .OK {
		web_stream_cleanup(client)
		classes.Destroy_Hierarchy(object)
		return vm.RaiseError(L, "could not start WebSocket connection")
	}
	client.added_to_multi = true
	client.service = service
	append(&service.web_streams, client)
	return 1
}

web_stream_step_connect :: proc(client: ^WebStreamClient, L: ^vm.State) {
	running: c.int
	if curl.multi_perform(client.multi, &running) != .OK {
		web_stream_finish(client, L, 0, "WebSocket handshake failed")
		return
	}
	queued: c.int
	result := curl.multi_info_read(client.multi, &queued)
	if result == nil || result.msg != .DONE {return}
	status: c.long
	_ = curl.easy_getinfo(client.easy, .RESPONSE_CODE, &status)
	if result.data.result != .E_OK {
		web_stream_finish(client, L, int(status), string(curl.easy_strerror(result.data.result)))
		return
	}
	client.state = .Open
	if client.opened != nil {
		vm.PushInteger(L, i64(status))
		vm.PushBytes(L, client.headers[:])
		signals.Fire(L, client.opened, 2)
		vm.Pop(L, 2)
	}
	delete(client.headers)
	client.headers = nil
}

web_stream_step_open :: proc(client: ^WebStreamClient, L: ^vm.State) {
	if len(client.outgoing) > 0 {
		message := client.outgoing[0]
		remaining := message[client.sent:]
		sent: c.size_t
		result := curl.ws_send(client.easy, raw_data(remaining), c.size_t(len(remaining)), &sent, 0, curl.WS_TEXT)
		if result != .E_OK && result != .E_AGAIN {
			web_stream_finish(client, L, 0, string(curl.easy_strerror(result)))
			return
		}
		client.sent += int(sent)
		if result == .E_OK && client.sent == len(message) {
			client.outgoing_size -= len(message)
			client.sent = 0
			delete(message)
			ordered_remove(&client.outgoing, 0)
		}
	}
	buffer: [16 * 1024]u8
	for _ in 0 ..< 32 {
		count: c.size_t
		frame: ^curl.ws_frame
		result := curl.ws_recv(client.easy, &buffer, len(buffer), &count, &frame)
		if result == .E_AGAIN {break}
		if result == .E_GOT_NOTHING || (result == .E_OK && .CLOSE in frame.flags) {
			web_stream_finish(client, L)
			break
		}
		if result != .E_OK {
			web_stream_finish(client, L, 0, string(curl.easy_strerror(result)))
			break
		}
		if (.TEXT not_in frame.flags) && (.BINARY not_in frame.flags) && (.CONT not_in frame.flags) {continue}
		if int(count) > WEB_STREAM_MESSAGE_LIMIT - len(client.message) {
			web_stream_finish(client, L, 0, "WebSocket message exceeds the receive limit")
			break
		}
		append(&client.message, ..buffer[:int(count)])
		if frame.bytesleft == 0 && .CONT not_in frame.flags {
			if client.received != nil {
				vm.PushBytes(L, client.message[:])
				signals.Fire(L, client.received, 1)
				vm.Pop(L)
			}
			clear(&client.message)
			if client.state != .Open || client.destroyed {break}
		}
	}
}

http_service_step_web_streams :: proc(service: ^HttpService, L: ^vm.State) {
	if len(service.web_streams) == 0 {return}
	// Callbacks may close the active socket or create a new socket.
	clients: [WEB_STREAM_CLIENT_LIMIT]^WebStreamClient
	count := copy(clients[:], service.web_streams[:])
	for client in clients[:count] {
		if client.destroyed || client.service != service {continue}
		switch client.state {
		case .Connecting: web_stream_step_connect(client, L)
		case .Open: web_stream_step_open(client, L)
		case .Error, .Closed:
		}
	}
}

register_web_stream_client :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry, &WebStreamClient_Class, web_stream_construct, web_stream_destroy,
		creatable = false,
		get = web_stream_get,
		namecall = web_stream_namecall,
		methods = []string{"Close", "Send"},
		events = []string{"Opened", "Closed", "Error", "MessageReceived"},
	)
}
