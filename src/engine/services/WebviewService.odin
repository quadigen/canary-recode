package services
// wire:service

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"


import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

WebviewService_Class := classes.Class_Info {
	name   = "WebviewService",
	parent = &Service_Class,
}


WEBVIEW_CREATE_TIMEOUT :: 15 * time.Second

WebviewService :: struct {
	using service: Service,
	call_count:    i64,
	mutex:         sync.Mutex,
	windows:       [dynamic]^WebviewWindow,
	next_id:       i64,
}


WebviewWindow :: struct {
	service:        ^WebviewService,
	id:             i64,
	mutex:          sync.Mutex,
	webview:        kineffi.Webview,
	thread:         ^thread.Thread,
	alive:          bool,
	finished:       bool,
	stop_requested: bool,
	created:        sync.Sema,
	url:            string,
	title:          string,
}

Webview_Command :: enum u8 {
	Navigate,
	Set_Title,
	Set_Html,
	Eval,
	Terminate,
}


Webview_Command_Request :: struct {
	command:   Webview_Command,
	allocator: mem.Allocator,
	payload:   cstring,
}

WebviewService_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(WebviewService)
	service.service = Service_Init(&WebviewService_Class, "WebviewService", data_model)

	return &service.object
}

WebviewService_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^WebviewService)object
	webview_service_close_all(service)
	classes.Object_Destroy(object)
	free(service)
}

webview_service_open :: proc(
	service: ^WebviewService,
	url, title: string,
) -> (
	^WebviewWindow,
	bool,
) {
	sync.mutex_lock(&service.mutex)
	service.next_id += 1
	id := service.next_id
	sync.mutex_unlock(&service.mutex)

	window := new(WebviewWindow)
	window.service = service
	window.id = id
	window.url = strings.clone(url)
	window.title = strings.clone(title)

	window.thread = thread.create(webview_window_thread_main)
	if window.thread == nil {
		delete(window.url)
		delete(window.title)
		free(window)
		return nil, false
	}
	window.thread.data = window

	sync.mutex_lock(&service.mutex)
	append(&service.windows, window)
	sync.mutex_unlock(&service.mutex)

	thread.start(window.thread)


	if !sync.wait_with_timeout(&window.created, WEBVIEW_CREATE_TIMEOUT) {
		sync.mutex_lock(&window.mutex)
		window.stop_requested = true
		sync.mutex_unlock(&window.mutex)
		webview_window_close(window)
		webview_window_remove(service, window)
		return nil, false
	}

	sync.mutex_lock(&window.mutex)
	ok := window.webview != nil && !window.finished
	sync.mutex_unlock(&window.mutex)

	if !ok {
		webview_window_close(window)
		webview_window_remove(service, window)
		return nil, false
	}
	return window, true
}

webview_window_thread_main :: proc(t: ^thread.Thread) {
	window := cast(^WebviewWindow)t.data
	if window == nil {return}

	webview := kineffi.create(true)

	sync.mutex_lock(&window.mutex)
	window.webview = webview
	stop := window.stop_requested
	if webview != nil {window.alive = true}
	sync.mutex_unlock(&window.mutex)


	sync.sema_post(&window.created)

	if webview == nil {
		fmt.eprintln("[WebviewService] webview_create failed (is the WebView2 runtime installed?)")
		sync.mutex_lock(&window.mutex)
		window.finished = true
		sync.mutex_unlock(&window.mutex)
		return
	}

	if stop {
		kineffi.destroy(webview)
		sync.mutex_lock(&window.mutex)
		window.webview = nil
		window.alive = false
		window.finished = true
		sync.mutex_unlock(&window.mutex)
		return
	}

	if len(window.title) > 0 {
		title := strings.clone_to_cstring(window.title)
		kineffi.set_title(webview, title)
		delete(title)
	}
	if len(window.url) > 0 {
		url := strings.clone_to_cstring(window.url)
		kineffi.navigate(webview, url)
		delete(url)
	}

	kineffi.run(webview)

	sync.mutex_lock(&window.mutex)
	window.webview = nil
	window.alive = false
	window.finished = true
	sync.mutex_unlock(&window.mutex)

	kineffi.destroy(webview)
}

webview_command_callback :: proc "c" (w: kineffi.Webview, arg: rawptr) {
	context = runtime.default_context()

	req := cast(^Webview_Command_Request)arg
	if req == nil {return}

	switch req.command {
	case .Navigate:
		kineffi.navigate(w, req.payload)
	case .Set_Title:
		kineffi.set_title(w, req.payload)
	case .Set_Html:
		kineffi.set_html(w, req.payload)
	case .Eval:
		kineffi.eval(w, req.payload)
	case .Terminate:
		kineffi.terminate(w)
	}

	if req.payload != nil {
		free(cast(rawptr)req.payload, req.allocator)
	}
	free(req, req.allocator)
}

webview_window_dispatch :: proc(
	window: ^WebviewWindow,
	command: Webview_Command,
	payload: string,
) -> bool {
	sync.mutex_lock(&window.mutex)
	webview := window.webview
	alive := window.alive
	sync.mutex_unlock(&window.mutex)
	if webview == nil || !alive {
		return false
	}


	allocator := context.allocator
	req := new(Webview_Command_Request, allocator)
	req.command = command
	req.allocator = allocator
	req.payload = nil
	if len(payload) > 0 {
		req.payload = strings.clone_to_cstring(payload, allocator)
	}

	if kineffi.dispatch(webview, webview_command_callback, req) != .Ok {
		if req.payload != nil {
			free(cast(rawptr)req.payload, allocator)
		}
		free(req, allocator)
		return false
	}
	return true
}


webview_window_close :: proc(window: ^WebviewWindow) {
	if window == nil {return}

	sync.mutex_lock(&window.mutex)
	webview := window.webview
	worker := window.thread


	if webview == nil {
		window.stop_requested = true
	}
	sync.mutex_unlock(&window.mutex)


	if webview != nil {
		webview_window_dispatch(window, .Terminate, "")
	}

	if worker != nil {
		thread.join(worker)
		thread.destroy(worker)
		window.thread = nil
	}
}

webview_window_remove :: proc(service: ^WebviewService, window: ^WebviewWindow) {
	sync.mutex_lock(&service.mutex)
	for w, i in service.windows {
		if w == window {
			unordered_remove(&service.windows, i)
			break
		}
	}
	sync.mutex_unlock(&service.mutex)

	delete(window.url)
	delete(window.title)
	free(window)
}

webview_service_find_window :: proc(service: ^WebviewService, id: i64) -> ^WebviewWindow {
	sync.mutex_lock(&service.mutex)
	defer sync.mutex_unlock(&service.mutex)
	for w in service.windows {
		if w.id == id {
			return w
		}
	}
	return nil
}


webview_service_reap :: proc(service: ^WebviewService) {
	if service == nil {return}

	dead := make([dynamic]^WebviewWindow, 0, 8)
	sync.mutex_lock(&service.mutex)
	for w in service.windows {
		sync.mutex_lock(&w.mutex)
		done := w.finished
		sync.mutex_unlock(&w.mutex)
		if done {
			append(&dead, w)
		}
	}
	sync.mutex_unlock(&service.mutex)

	for w in dead {
		webview_window_close(w)
		webview_window_remove(service, w)
	}
	delete(dead)
}


webview_service_close_all :: proc(service: ^WebviewService) -> int {
	if service == nil {return 0}

	sync.mutex_lock(&service.mutex)
	windows := service.windows
	service.windows = nil
	sync.mutex_unlock(&service.mutex)

	for w in windows {
		webview_window_close(w)
		delete(w.url)
		delete(w.title)
		free(w)
	}
	closed := len(windows)
	delete(windows)
	return closed
}

webview_service_issue :: proc(
	L: ^vm.State,
	service: ^WebviewService,
	command: Webview_Command,
) -> (
	i32,
	bool,
) {
	id := i64(vm.ArgNumber(L, 2))
	payload := vm.ArgOptionalString(L, 3)

	window := webview_service_find_window(service, id)
	if window == nil {
		vm.PushBoolean(L, false)
		return 1, true
	}

	vm.PushBoolean(L, webview_window_dispatch(window, command, payload))
	return 1, true
}

WebviewService_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^WebviewService)object
	switch key {
	case "CallCount":
		vm.PushNumber(L, f64(service.call_count))
	case "Add",
	     "Echo",
	     "MakeColor",
	     "GetService",
	     "Open",
	     "Close",
	     "Destroy",
	     "Navigate",
	     "SetTitle",
	     "SetHtml",
	     "Eval":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

WebviewService_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^WebviewService)object
	switch method {
	case "Add":
		service.call_count += 1
		vm.PushNumber(L, vm.ArgNumber(L, 2) + vm.ArgNumber(L, 3))
		return 1, true
	case "Echo":
		service.call_count += 1
		vm.PushValue(L, 2)
		return 1, true
	case "MakeColor":
		service.call_count += 1
		if datatype_registry == nil {return 0, false}
		datatypes.Push_Color3(
			L,
			datatype_registry,
			datatypes.Color3 {
				f32(vm.ArgNumber(L, 2)),
				f32(vm.ArgNumber(L, 3)),
				f32(vm.ArgNumber(L, 4)),
			},
		)
		return 1, true
	case "GetService":
		classes.Push_Object(L, Service_Get_Service(&service.service, vm.ArgString(L, 2)))
		return 1, true
	case "Open":
		webview_service_reap(service)
		url := vm.ArgString(L, 2)
		title := vm.ArgOptionalString(L, 3)
		window, ok := webview_service_open(service, url, title)
		if !ok {
			return vm.RaiseError(L, "WebviewService: failed to open a webview window"), true
		}
		service.call_count += 1
		vm.PushNumber(L, f64(window.id))
		return 1, true
	case "Close", "Destroy":
		vm.PushNumber(L, f64(webview_service_close(service, L)))
		return 1, true
	case "Navigate":
		return webview_service_issue(L, service, .Navigate)
	case "SetTitle":
		return webview_service_issue(L, service, .Set_Title)
	case "SetHtml":
		return webview_service_issue(L, service, .Set_Html)
	case "Eval":
		return webview_service_issue(L, service, .Eval)
	}
	return 0, false
}


webview_service_close :: proc(service: ^WebviewService, L: ^vm.State) -> int {
	if vm.IsNoneOrNil(L, 2) {
		return webview_service_close_all(service)
	}

	window := webview_service_find_window(service, i64(vm.ArgNumber(L, 2)))
	if window == nil {
		return 0
	}
	webview_window_close(window)
	webview_window_remove(service, window)
	return 1
}

Register_WebviewService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&WebviewService_Class,
		WebviewService_construct,
		WebviewService_destroy,
		creatable = false,
		get = WebviewService_get,
		namecall = WebviewService_namecall,
	)
}
