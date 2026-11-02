


package discord_rpc

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:time"

PROTOCOL_VERSION :: 1
MAX_PACKET_SIZE :: 64 * 1024
MAX_PIPES :: 10
HANDSHAKE_TIMEOUT_MS :: 5000
PAYLOAD_TIMEOUT_MS :: 2000

Opcode :: enum u32 {
	Handshake = 0,
	Frame     = 1,
	Close     = 2,
	Ping      = 3,
	Pong      = 4,
}

Error :: enum {
	None,
	Not_Running,
	Not_Connected,
	Invalid_Argument,
	Payload_Too_Large,
	Write_Failed,
	Read_Failed,
	Timeout,
	Connection_Closed,
	Invalid_Response,
	Handshake_Rejected,
}

Activity_Type :: enum {
	Playing   = 0,
	Listening = 2,
	Watching  = 3,
	Competing = 5,
}


Status_Display_Type :: enum {
	Name    = 0,
	State   = 1,
	Details = 2,
}


Timestamps :: struct {
	start: i64,
	end:   i64,
}


Assets :: struct {
	large_image: string,
	large_text:  string,
	small_image: string,
	small_text:  string,
}


Party :: struct {
	id:       string,
	size:     int,
	max_size: int,
}

Secrets :: struct {
	join:     string,
	spectate: string,
	match:    string,
}

Button :: struct {
	label: string,
	url:   string,
}


Activity :: struct {
	type:           Activity_Type,
	status_display: Status_Display_Type,
	details:        string,
	state:          string,
	timestamps:     Timestamps,
	assets:         Assets,
	party:          Party,
	secrets:        Secrets,
	buttons:        []Button,
	instance:       bool,
}


User :: struct {
	id:          string,
	username:    string,
	global_name: string,
}


RPC_Error :: struct {
	code:    int,
	message: string,
}

Client :: struct {
	connected:     bool,
	user:          User,
	last_error:    RPC_Error,
	client_id:     string,
	transport:     Transport,
	nonce_counter: u64,
	allocator:     runtime.Allocator,
}


Read_Status :: enum {
	Ok,
	Timeout,
	Closed,
}

@(private)
Frame_Event :: enum {
	None,
	Ready,
	Error,
}


now_unix :: proc() -> i64 {
	return time.to_unix_seconds(time.now())
}


connect :: proc(c: ^Client, client_id: string, allocator := context.allocator) -> Error {
	if len(client_id) == 0 {
		return .Invalid_Argument
	}
	disconnect(c)
	c.allocator = allocator

	if !transport_open(&c.transport) {
		return .Not_Running
	}
	c.client_id = strings.clone(client_id, allocator)


	{
		b := strings.builder_make(allocator)
		defer strings.builder_destroy(&b)
		o := obj_open(&b)
		obj_int(&o, "v", PROTOCOL_VERSION)
		obj_str(&o, "client_id", client_id)
		obj_close(&o)

		if err := write_packet(c, .Handshake, transmute([]byte)strings.to_string(b));
		   err != .None {
			fail_connect(c)
			return err
		}
	}


	op, payload, err := read_packet(c, HANDSHAKE_TIMEOUT_MS)
	if err != .None {
		fail_connect(c)
		return err
	}
	defer delete(payload, allocator)

	#partial switch op {
	case .Frame:
		if process_frame(c, payload) != .Ready {
			fail_connect(c)
			return .Handshake_Rejected
		}
	case .Close:
		record_error_from_json(c, payload, nested = false)
		fail_connect(c)
		return .Handshake_Rejected
	case:
		fail_connect(c)
		return .Invalid_Response
	}

	c.connected = true
	return .None
}


disconnect :: proc(c: ^Client) {
	transport_close(&c.transport)
	free_client_strings(c)
	c^ = {}
}


set_activity :: proc(c: ^Client, activity: Activity) -> Error {
	a := activity
	return send_activity_command(c, &a)
}


clear_activity :: proc(c: ^Client) -> Error {
	return send_activity_command(c, nil)
}


update :: proc(c: ^Client, timeout_ms := 0) -> Error {
	if !c.connected {
		return .Not_Connected
	}
	timeout := timeout_ms
	for {
		op, payload, err := read_packet(c, timeout)
		if err == .Timeout {
			return .None
		}
		if err != .None {
			c.connected = false
			return err
		}
		timeout = 0

		#partial switch op {
		case .Ping:
			write_packet(c, .Pong, payload)
		case .Frame:
			process_frame(c, payload)
		case .Close:
			record_error_from_json(c, payload, nested = false)
			delete(payload, c.allocator)
			c.connected = false
			return .Connection_Closed
		}
		delete(payload, c.allocator)
	}
}


@(private)
put_u32le :: proc(b: []byte, v: u32) {
	b[0] = byte(v)
	b[1] = byte(v >> 8)
	b[2] = byte(v >> 16)
	b[3] = byte(v >> 24)
}

@(private)
get_u32le :: proc(b: []byte) -> u32 {
	return u32(b[0]) | u32(b[1]) << 8 | u32(b[2]) << 16 | u32(b[3]) << 24
}

@(private)
write_packet :: proc(c: ^Client, op: Opcode, payload: []byte) -> Error {
	if len(payload) > MAX_PACKET_SIZE {
		return .Payload_Too_Large
	}
	buf := make([]byte, 8 + len(payload), c.allocator)
	defer delete(buf, c.allocator)
	put_u32le(buf[0:4], u32(op))
	put_u32le(buf[4:8], u32(len(payload)))
	copy(buf[8:], payload)

	if !transport_write(&c.transport, buf) {
		c.connected = false
		return .Write_Failed
	}
	return .None
}


@(private)
read_exact :: proc(t: ^Transport, buf: []byte, first_timeout_ms: int) -> Error {
	got := 0
	for got < len(buf) {
		timeout := first_timeout_ms if got == 0 else PAYLOAD_TIMEOUT_MS
		n, st := transport_read(t, buf[got:], timeout)
		switch st {
		case .Ok:
			got += n
		case .Timeout:
			return .Timeout if got == 0 else .Read_Failed
		case .Closed:
			return .Connection_Closed
		}
	}
	return .None
}


@(private)
read_packet :: proc(c: ^Client, timeout_ms: int) -> (op: Opcode, payload: []byte, err: Error) {
	header: [8]byte
	if e := read_exact(&c.transport, header[:], timeout_ms); e != .None {
		return op, nil, e
	}
	op = Opcode(get_u32le(header[0:4]))
	length := int(get_u32le(header[4:8]))
	if length > MAX_PACKET_SIZE {
		return op, nil, .Invalid_Response
	}
	if length == 0 {
		return op, nil, .None
	}

	payload = make([]byte, length, c.allocator)
	e := read_exact(&c.transport, payload, PAYLOAD_TIMEOUT_MS)
	if e != .None {
		delete(payload, c.allocator)
		if e == .Timeout {
			e = .Read_Failed
		}
		return op, nil, e
	}
	return op, payload, .None
}


@(private)
fail_connect :: proc(c: ^Client) {
	transport_close(&c.transport)
	c.connected = false
}

@(private)
free_client_strings :: proc(c: ^Client) {
	free_str :: proc(s: string, a: runtime.Allocator) {
		if len(s) > 0 {
			delete(s, a)
		}
	}
	free_str(c.client_id, c.allocator)
	free_str(c.user.id, c.allocator)
	free_str(c.user.username, c.allocator)
	free_str(c.user.global_name, c.allocator)
	free_str(c.last_error.message, c.allocator)
}

@(private)
json_get :: proc(obj: json.Object, key: string) -> json.Value {
	v, _ := obj[key]
	return v
}

@(private)
json_string :: proc(obj: json.Object, key: string) -> string {
	s, _ := json_get(obj, key).(json.String)
	return s
}

@(private)
json_object :: proc(obj: json.Object, key: string) -> json.Object {
	o, _ := json_get(obj, key).(json.Object)
	return o
}

@(private)
json_int :: proc(obj: json.Object, key: string) -> int {
	#partial switch v in json_get(obj, key) {
	case json.Integer:
		return int(v)
	case json.Float:
		return int(v)
	}
	return 0
}

@(private)
set_last_error :: proc(c: ^Client, code: int, message: string) {
	if len(c.last_error.message) > 0 {
		delete(c.last_error.message, c.allocator)
	}
	c.last_error.code = code
	c.last_error.message = strings.clone(message, c.allocator)
}


@(private)
record_error_from_json :: proc(c: ^Client, payload: []byte, nested: bool) {
	if len(payload) == 0 {
		return
	}
	value, jerr := json.parse(payload, parse_integers = true, allocator = c.allocator)
	if jerr != .None {
		return
	}
	defer json.destroy_value(value, c.allocator)
	root, ok := value.(json.Object)
	if !ok {
		return
	}
	src := json_object(root, "data") if nested else root
	set_last_error(c, json_int(src, "code"), json_string(src, "message"))
}

@(private)
process_frame :: proc(c: ^Client, payload: []byte) -> Frame_Event {
	if len(payload) == 0 {
		return .None
	}
	value, jerr := json.parse(payload, parse_integers = true, allocator = c.allocator)
	if jerr != .None {
		return .None
	}
	defer json.destroy_value(value, c.allocator)
	root, ok := value.(json.Object)
	if !ok {
		return .None
	}

	data := json_object(root, "data")
	switch json_string(root, "evt") {
	case "READY":
		user := json_object(data, "user")
		free_user :: proc(c: ^Client) {
			for s in ([?]string{c.user.id, c.user.username, c.user.global_name}) {
				if len(s) > 0 {
					delete(s, c.allocator)
				}
			}
		}
		free_user(c)
		c.user = User {
			id          = strings.clone(json_string(user, "id"), c.allocator),
			username    = strings.clone(json_string(user, "username"), c.allocator),
			global_name = strings.clone(json_string(user, "global_name"), c.allocator),
		}
		return .Ready
	case "ERROR":
		set_last_error(c, json_int(data, "code"), json_string(data, "message"))
		return .Error
	}
	return .None
}


@(private)
send_activity_command :: proc(c: ^Client, a: ^Activity) -> Error {
	if !c.connected {
		return .Not_Connected
	}
	c.nonce_counter += 1

	b := strings.builder_make(c.allocator)
	defer strings.builder_destroy(&b)

	root := obj_open(&b)
	obj_str(&root, "cmd", "SET_ACTIVITY")

	obj_key(&root, "args")
	args := obj_open(&b)
	obj_int(&args, "pid", i64(transport_pid()))
	if a != nil {
		obj_key(&args, "activity")
		write_activity(&b, a)
	}
	obj_close(&args)

	nonce_buf: [32]u8
	nonce := fmt.bprintf(nonce_buf[:], "odin-%d", c.nonce_counter)
	obj_str(&root, "nonce", nonce)
	obj_close(&root)

	return write_packet(c, .Frame, transmute([]byte)strings.to_string(b))
}

@(private)
write_activity :: proc(b: ^strings.Builder, a: ^Activity) {
	o := obj_open(b)
	obj_int(&o, "type", i64(a.type))
	if a.status_display != .Name {
		obj_int(&o, "status_display_type", i64(a.status_display))
	}
	obj_str_opt(&o, "details", a.details)
	obj_str_opt(&o, "state", a.state)

	if a.timestamps.start != 0 || a.timestamps.end != 0 {
		obj_key(&o, "timestamps")
		t := obj_open(b)
		if a.timestamps.start != 0 {obj_int(&t, "start", a.timestamps.start)}
		if a.timestamps.end != 0 {obj_int(&t, "end", a.timestamps.end)}
		obj_close(&t)
	}

	as := a.assets
	if len(as.large_image) + len(as.large_text) + len(as.small_image) + len(as.small_text) > 0 {
		obj_key(&o, "assets")
		t := obj_open(b)
		obj_str_opt(&t, "large_image", as.large_image)
		obj_str_opt(&t, "large_text", as.large_text)
		obj_str_opt(&t, "small_image", as.small_image)
		obj_str_opt(&t, "small_text", as.small_text)
		obj_close(&t)
	}

	if a.party.max_size > 0 {
		obj_key(&o, "party")
		t := obj_open(b)
		obj_str_opt(&t, "id", a.party.id)
		obj_key(&t, "size")
		fmt.sbprintf(b, "[%d,%d]", a.party.size, a.party.max_size)
		obj_close(&t)
	}

	s := a.secrets
	if len(s.join) + len(s.spectate) + len(s.match) > 0 {
		obj_key(&o, "secrets")
		t := obj_open(b)
		obj_str_opt(&t, "join", s.join)
		obj_str_opt(&t, "spectate", s.spectate)
		obj_str_opt(&t, "match", s.match)
		obj_close(&t)
	}

	if len(a.buttons) > 0 {
		obj_key(&o, "buttons")
		strings.write_byte(b, '[')
		for btn, i in a.buttons[:min(len(a.buttons), 2)] {
			if i > 0 {
				strings.write_byte(b, ',')
			}
			t := obj_open(b)
			obj_str(&t, "label", btn.label)
			obj_str(&t, "url", btn.url)
			obj_close(&t)
		}
		strings.write_byte(b, ']')
	}

	if a.instance {
		obj_bool(&o, "instance", true)
	}
	obj_close(&o)
}


@(private)
Obj :: struct {
	b:     ^strings.Builder,
	first: bool,
}

@(private)
obj_open :: proc(b: ^strings.Builder) -> Obj {
	strings.write_byte(b, '{')
	return Obj{b = b, first = true}
}

@(private)
obj_close :: proc(o: ^Obj) {
	strings.write_byte(o.b, '}')
}

@(private)
obj_key :: proc(o: ^Obj, key: string) {
	if !o.first {
		strings.write_byte(o.b, ',')
	}
	o.first = false
	write_json_string(o.b, key)
	strings.write_byte(o.b, ':')
}

@(private)
obj_str :: proc(o: ^Obj, key, val: string) {
	obj_key(o, key)
	write_json_string(o.b, val)
}

@(private)
obj_str_opt :: proc(o: ^Obj, key, val: string) {
	if len(val) > 0 {
		obj_str(o, key, val)
	}
}

@(private)
obj_int :: proc(o: ^Obj, key: string, val: i64) {
	obj_key(o, key)
	fmt.sbprintf(o.b, "%d", val)
}

@(private)
obj_bool :: proc(o: ^Obj, key: string, val: bool) {
	obj_key(o, key)
	strings.write_string(o.b, "true" if val else "false")
}

@(private)
write_json_string :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for i in 0 ..< len(s) {
		ch := s[i]
		switch ch {
		case '"':
			strings.write_string(b, `\"`)
		case '\\':
			strings.write_string(b, `\\`)
		case '\n':
			strings.write_string(b, `\n`)
		case '\r':
			strings.write_string(b, `\r`)
		case '\t':
			strings.write_string(b, `\t`)
		case:
			if ch < 0x20 {
				fmt.sbprintf(b, "\\u%04x", ch)
			} else {
				strings.write_byte(b, ch)
			}
		}
	}
	strings.write_byte(b, '"')
}
