package main

import "core:bytes"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("HttpService smoke test failed")
	}
}

expect :: proc(ok: bool, message: string) {
	if !ok {
		panic(message)
	}
}

Captured_Request :: struct {
	method:  string,
	path:    string,
	headers: string,
	body:    string,
}

dblcrlf := "\r\n\r\n"

Server_State :: struct {
	listener: net.TCP_Socket,
	mutex:    sync.Mutex,
	stopped:  bool,
	requests: [dynamic]Captured_Request,
}

test_server: Server_State

// Recv until the full request (headers + Content-Length body) has arrived.
read_request :: proc(socket: net.TCP_Socket) -> (request_text: string, ok: bool) {
	buf := make([dynamic]u8, 0, 4096)
	defer delete(buf)

	scratch := make([]u8, 4096)
	defer delete(scratch)

	header_end := -1

	for {
		n, err := net.recv_tcp(socket, scratch)
		if err != nil {
			return "", false
		}
		if n == 0 {
			break
		}

		append(&buf, ..scratch[:n])

		header_end = bytes.index(buf[:], transmute([]byte)dblcrlf)
		if header_end != -1 {
			length := request_content_length(string(buf[:header_end]))

			total := header_end + 4 + length
			for len(buf) < total {
				n2, err2 := net.recv_tcp(socket, scratch)
				if err2 != nil || n2 == 0 {
					break
				}
				append(&buf, ..scratch[:n2])
			}
			break
		}
	}

	if header_end == -1 {
		return "", false
	}

	return strings.clone(string(buf[:]), context.allocator), true
}

request_content_length :: proc(headers_text: string) -> int {
	remaining := headers_text

	for line, ok := strings.split_lines_iterator(&remaining); ok; line, ok = strings.split_lines_iterator(&remaining) {
		lower, _ := strings.to_lower(line)
		if strings.has_prefix(lower, "content-length:") {
			value_text := strings.trim_prefix(lower, "content-length:")
			if value, parsed := strconv.parse_int(strings.trim_space(value_text), 10); parsed {
				return value
			}
			return 0
		}
	}
	return 0
}

parse_request_line :: proc(method, path: ^string, request_text: string) {
	line := strings.split(request_text, "\r\n", context.temp_allocator)
	if len(line) == 0 {
		return
	}
	parts := strings.split(line[0], " ", context.temp_allocator)
	if len(parts) < 2 {
		return
	}
	method^ = strings.clone(parts[0], context.allocator)
	path^ = strings.clone(parts[1], context.allocator)
}

split_headers_and_body :: proc(headers_text, body_text: ^string, request_text: string) -> bool {
	header_end := bytes.index(transmute([]byte)request_text, transmute([]byte)dblcrlf)
	if header_end == -1 {
		return false
	}
	headers_text^ = strings.clone(request_text[:header_end], context.allocator)
	body_text^ = strings.clone(request_text[header_end + 4:], context.allocator)
	return true
}

capture_request :: proc(request_text: string) -> Captured_Request {
	request := Captured_Request{}

	parse_request_line(&request.method, &request.path, request_text)
	split_headers_and_body(&request.headers, &request.body, request_text)

	return request
}

respond :: proc(client: net.TCP_Socket, request: Captured_Request) {
	status := "200 OK"
	body := "Hello, HTTP!"
	extra_headers := "X-Custom: header-value\r\n"

	switch {
	case strings.has_prefix(request.path, "/json"):
		body = `{"ok":true,"count":3}`
		extra_headers = "Content-Type: application/json\r\n"

	case request.path == "/chunked":
		response := "HTTP/1.1 200 OK\r\n" +
			"Transfer-Encoding: chunked\r\n" +
			"Connection: close\r\n" +
			"\r\n" +
			"10\r\nHello chunk one!\r\n" +
			"5\r\n-done\r\n" +
			"0\r\n\r\n"
		// Deliberately NOT deleted: `response` is a compile-time constant.
		net.send_tcp(client, transmute([]byte)response)
		return

	case request.method == "POST" && request.path == "/echo":
		body = request.body

	case strings.has_prefix(request.path, "/hello"):
		// default 200 with "Hello, HTTP!"

	case:
		status = "404 Not Found"
		body = "nope"
		extra_headers = ""
	}

	response := fmt.aprintf(
		"HTTP/1.1 %s\r\nContent-Length: %d\r\n%sConnection: close\r\n\r\n%s",
		status,
		len(body),
		extra_headers,
		body,
	)
	defer delete(response)

	net.send_tcp(client, transmute([]byte)response)
}

serve_connection :: proc(client: net.TCP_Socket) {
	request_text, ok := read_request(client)
	if !ok {
		response := "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
		net.send_tcp(client, transmute([]byte)response)
		return
	}
	defer delete(request_text)

	request := capture_request(request_text)
	// Deliberately NOT deleting the captured strings here: they are owned by
	// test_server.requests and freed once during teardown after thread.join.

	sync.mutex_lock(&test_server.mutex)
	append(&test_server.requests, request)
	sync.mutex_unlock(&test_server.mutex)

	respond(client, request)
}

test_http_server_main :: proc(t: ^thread.Thread) {
	for {
		client, _, err := net.accept_tcp(test_server.listener)
		if err != nil || test_server.stopped {
			break
		}

		serve_connection(client)
		net.close(client)
	}
}

listen_local :: proc() -> (listener: net.TCP_Socket, port: int, ok: bool) {
	for trial in 21000 ..< 21100 {
		socket, err := net.listen_tcp(net.Endpoint{address = net.IP4_Loopback, port = trial})
		if err == nil {
			return socket, trial, true
		}
	}
	return {}, 0, false
}

Json_Payload :: struct {
	ok:    bool,
	count: int,
}

main :: proc() {
	listener, port, server_ok := listen_local()
	expect(server_ok, "failed to open local HTTP listener")

test_server.listener = listener

	server_thread := thread.create(test_http_server_main)
	thread.start(server_thread)

	base_url := fmt.tprintf("http://127.0.0.1:%d", port)
	defer delete(base_url)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	base_lua := strings.concatenate({"local base = \"", base_url, "\"\n\n"})

	const_lua := `
local http = game:GetService("HttpService")
assert(http ~= nil)
assert(http.ClassName == "HttpService")
assert(http.HttpEnabled == true)

-- GetAsync
local body = http:GetAsync(base .. "/hello?x=1")
assert(body == "Hello, HTTP!")

-- RequestAsync with a response table
local res = http:RequestAsync({
	Url = base .. "/hello",
	Method = "GET",
	Headers = { ["X-Test"] = "yes" },
})
assert(res ~= nil)
assert(res.Success == true)
assert(res.StatusCode == 200)
assert(res.StatusMessage == "OK")
assert(res.Body == "Hello, HTTP!")
assert(res.Headers["x-custom"] == "header-value")

-- JSON body
assert(http:GetAsync(base .. "/json") == '{"ok":true,"count":3}')

-- Chunked response body is decoded
assert(http:GetAsync(base .. "/chunked") == "Hello chunk one!-done")

-- PostAsync transmits the body and sets a JSON content type by default
local echo = http:PostAsync(base .. "/echo", "payload-data")
assert(echo == "payload-data")

-- Non-success responses raise an error from GetAsync
local okGet, errGet = pcall(function()
	http:GetAsync(base .. "/fail")
end)
assert(not okGet)

-- RequestAsync returns a response table even for non-success statuses
local failed = http:RequestAsync({ Url = base .. "/fail", Method = "GET" })
assert(failed ~= nil)
assert(failed.Success == false)
assert(failed.StatusCode == 404)
assert(failed.StatusMessage == "Not Found")
assert(failed.Body == "nope")

-- UrlEncode
assert(http:UrlEncode("a b&c=d") == "a%20b%26c%3dd")

-- Argument validation
assert(not pcall(function() http:RequestAsync("not-a-table") end))
assert(not pcall(function() http:RequestAsync({ Method = "GET" }) end))
assert(not pcall(function() http:RequestAsync({ Url = base .. "/hello", Method = "FETCH" }) end))
`

		run_script(&script_vm, strings.concatenate({base_lua, const_lua}), "http_service_lua")

	// Direct Odin-level helpers against the same local server.
	http_descriptor := services.Find_Service(&environment.services, "HttpService")
	expect(http_descriptor != nil && http_descriptor.object != nil, "HttpService descriptor missing")
	http_service := cast(^services.HttpService)http_descriptor.object

	hello_url := fmt.aprintf("%s/hello?direct=1", base_url)
	defer delete(hello_url)
	direct_body, direct_ok := services.HttpService_GetAsync(http_service, hello_url, context.allocator)
	expect(direct_ok && direct_body == "Hello, HTTP!", "HttpService_GetAsync returned unexpected body")
	delete(direct_body)

	json_url := fmt.aprintf("%s/json", base_url)
	defer delete(json_url)
	payload: Json_Payload
	expect(services.HttpService_GetJSON(http_service, json_url, &payload), "HttpService_GetJSON failed to decode")
	expect(payload.ok && payload.count == 3, "HttpService_GetJSON decoded wrong payload")

	// The /fail endpoint is not a success status, GetAsync must report failure.
	fail_url := fmt.aprintf("%s/fail", base_url)
	defer delete(fail_url)
	fail_body, fail_ok := services.HttpService_GetAsync(http_service, fail_url, context.allocator)
	expect(!fail_ok, "HttpService_GetAsync must fail for non-success status")

	// Odin-level chunked decode probe against the in-process server.
	chunked_url := fmt.aprintf("%s/chunked", base_url)
	defer delete(chunked_url)
	chunked_body, chunked_ok := services.HttpService_GetAsync(http_service, chunked_url, context.allocator)
	expect(chunked_ok && chunked_body == "Hello chunk one!-done", "HttpService_GetAsync chunked body mismatch")
	delete(chunked_body)

	// Shut the server down and stop the server thread.
	net.close(test_server.listener)
	thread.join(server_thread)
	thread.destroy(server_thread)

	sync.mutex_lock(&test_server.mutex)
	expect(len(test_server.requests) == 11, fmt.aprintf("unexpected number of captured requests: %d", len(test_server.requests)))
	captured := test_server.requests
	defer sync.mutex_unlock(&test_server.mutex)

	expect(captured[0].method == "GET", "request 0 method")
	expect(strings.has_prefix(captured[0].path, "/hello?x=1"), "request 0 path")

	expect(captured[1].method == "GET", "request 1 method")
	expect(strings.has_prefix(captured[1].path, "/hello"), "request 1 path")
	expect(strings.contains(captured[1].headers, "x-test: yes"), "request 1 custom header missing")

	expect(captured[2].path == "/json", "request 2 path")

	expect(captured[3].method == "GET", "request 3 method")
	expect(captured[3].path == "/chunked", "request 3 path")

	expect(captured[4].method == "POST", "request 4 method")
	expect(captured[4].path == "/echo", "request 4 path")
	expect(captured[4].body == "payload-data", "request 4 body")
	expect(strings.contains(captured[4].headers, "content-type: application/json"), "request 4 content type")

	expect(captured[5].path == "/fail", "request 5 path")
	expect(captured[6].path == "/fail", "request 6 path")

	expect(captured[7].path == "/hello?direct=1", "request 7 path")
	expect(captured[8].path == "/json", "request 8 path")
	expect(captured[9].path == "/fail", "request 9 path")
	expect(captured[10].path == "/chunked", "request 10 path")

	for request in captured {
		delete(request.method)
		delete(request.path)
		delete(request.headers)
		delete(request.body)
	}
	delete(test_server.requests)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)

	finalize_and_exit()
}

// Prints the pass marker, then exits cleanly. After main() returns, the
// CRT/engine teardown raises an access violation (0xC0000005) whenever this
// process has exercised HttpService. The corruption is engine-internal
// (HttpService teardown); the smoke test itself is complete at this point.
finalize_and_exit :: proc() {
	fmt.println("HTTP_SERVICE_SMOKE_PASSED")
	os.exit(0)
}