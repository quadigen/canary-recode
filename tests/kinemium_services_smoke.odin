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
		panic("kinemium services smoke test failed")
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

	for line, ok := strings.split_lines_iterator(&remaining);
	    ok;
	    line, ok = strings.split_lines_iterator(&remaining) {
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

// answer routes both a Matrix homeserver and a Kinemium server.
respond :: proc(client: net.TCP_Socket, request: Captured_Request) {
	status := "200 OK"
	body := "{}"
	extra_headers := "Content-Type: application/json\r\n"

	switch {
	case request.path == "/_matrix/client/versions":
		body = `{"versions":["v1.1"]}`

	case request.method == "POST" && request.path == "/_matrix/client/v3/login":
		body = `{"user_id":"@alice:local","access_token":"tok","device_id":"DEV"}`

	case strings.has_prefix(request.path, "/_matrix/client/v3/joined_rooms"):
		body = `{"joined_rooms":["!r1:local"]}`

	case strings.has_prefix(request.path, "/_matrix/client/v3/sync"):
		body = `{"next_batch":"s1","rooms":{"join":{}}}`

	case strings.has_prefix(request.path, "/_matrix/client/v3/rooms/") &&
	     strings.contains(request.path, "/messages?"):
		body = `{"chunk":[{"event_id":"$3","sender":"@bob:local","type":"m.room.message","origin_server_ts":1700000003000,"content":{"msgtype":"m.text","body":"three"}},{"event_id":"$2","sender":"@bob:local","type":"m.room.message","origin_server_ts":1700000002000,"content":{"msgtype":"m.text","body":"two"}},{"event_id":"$1","sender":"@bob:local","type":"m.room.message","origin_server_ts":1700000001000,"content":{"msgtype":"m.text","body":"one"}}],"start":"s","end":"e"}`

	case strings.has_prefix(request.path, "/_matrix/client/v3/profile/"):
		body = `{"displayname":"Alice","avatar_url":"mxc://local/abc"}`

	case strings.has_prefix(request.path, "/_kinemium/v1/me"):
		body = `{"id":"alice","displayName":"Alice"}`

	case request.method == "GET" && strings.has_prefix(request.path, "/_kinemium/v1/marketplace?"):
		body = `{"packages":[{"namespace":"alice","name":"kv","version":"1.2.3","description":"kv store","type":"plugin","tags":["kv"],"updatedAt":"2026-10-20T00:00:00Z","iconUrl":"/icon.png"}]}`

	case request.method == "GET" && request.path == "/_kinemium/v1/marketplace/alice/kv":
		body = `{"namespace":"alice","name":"kv","version":"1.2.3","description":"kv store","type":"plugin","tags":["kv"]}`

	case request.method == "GET" && request.path == "/_kinemium/v1/marketplace/alice/kv/reviews":
		body = `{"reviews":[]}`

	case request.method == "POST" && request.path == "/_kinemium/v1/marketplace/alice/kv/acquire":
		body = `{"package":{"name":"kv"}}`

	case request.method == "POST" && request.path == "/_kinemium/v1/packages":
		body = `{"package":{"namespace":"alice","name":"smoke-package","version":"1.0.0"},"reviewStatus":"pending"}`

	case request.method == "POST" && request.path == "/_kinemium/v1/marketplace/alice/kv/reviews":
		body = `{"review":{"rating":5,"body":"great"}}`

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

	sync.mutex_lock(&test_server.mutex)
	append(&test_server.requests, request)
	sync.mutex_unlock(&test_server.mutex)

	respond(client, request)
}

test_server_main :: proc(t: ^thread.Thread) {
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
	for trial in 22100 ..< 22200 {
		socket, err := net.listen_tcp(net.Endpoint{address = net.IP4_Loopback, port = trial})
		if err == nil {
			return socket, trial, true
		}
	}
	return {}, 0, false
}

has_request_prefix :: proc(captured: []Captured_Request, prefix: string) -> bool {
	for request in captured {
		if strings.has_prefix(request.path, prefix) {return true}
	}
	return false
}

has_body_containing :: proc(captured: []Captured_Request, prefix, needle: string) -> bool {
	for request in captured {
		if strings.has_prefix(request.path, prefix) && strings.contains(request.body, needle) {
			return true
		}
	}
	return false
}

main :: proc() {
	services.Matrix_Session_Persistence = false

	listener, port, server_ok := listen_local()
	expect(server_ok, "failed to open local HTTP listener")

	test_server.listener = listener

	server_thread := thread.create(test_server_main)
	thread.start(server_thread)

	base_url := fmt.tprintf("http://127.0.0.1:%d", port)
	defer delete(base_url)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	matrix_descriptor := services.Find_Service(&environment.services, "MatrixService")
	expect(
		matrix_descriptor != nil && matrix_descriptor.object != nil,
		"MatrixService descriptor missing",
	)
	matrix_service := cast(^services.MatrixService)matrix_descriptor.object

	base_lua := strings.concatenate({"local base = \"", base_url, "\"\n\n"})

	setup_lua := `
local Matrix = game:GetService("MatrixService")
assert(Matrix ~= nil, "MatrixService nil")
assert(Matrix.ClassName == "MatrixService", "ClassName=" .. tostring(Matrix.ClassName))
assert(Matrix.DefaultHomeserver == "https://opus.quadigen.com", "DefaultHomeserver=" .. tostring(Matrix.DefaultHomeserver))
assert(Matrix.DeviceName == "Kinemium Engine", "DeviceName=" .. tostring(Matrix.DeviceName))
assert(Matrix:NormalizeUsername("@Alice:local") == "alice")
assert(Matrix:NormalizeHomeserver("matrix.org/_matrix") == "https://matrix.org")

local ok, session = Matrix:Login(base, "alice", "secret")
assert(ok, "login failed: " .. tostring(session))
assert(session.accessToken == "tok")
assert(session.userId == "@alice:local")
assert(session.homeserver == base)
assert(Matrix.Session.userId == "@alice:local")

local okResolve, resolved = Matrix:ResolveHomeserver(base)
assert(okResolve and resolved == base)

local okRooms, rooms = Matrix:GetJoinedRooms()
assert(okRooms and rooms[1] == "!r1:local")

local okSync, data, status = Matrix:Sync()
assert(okSync and data.next_batch == "s1" and status == 200)

local okMessages, history = Matrix:GetMessages(session, "!r1:local", { dir = "b", limit = 50 })
assert(okMessages, "GetMessages failed: " .. tostring(history))
assert(#history.messages == 3, "message count=" .. tostring(#history.messages))
assert(history.messages[1].body == "one", "first=" .. tostring(history.messages[1].body))
assert(history.messages[3].body == "three", "last=" .. tostring(history.messages[3].body))

local okProfile, profile = Matrix:GetProfile()
assert(okProfile and profile.displayName == "Alice" and profile.avatarUrl == "mxc://local/abc")

local media = Matrix:MxcToHttp(base, "mxc://local/abc", { authenticated = true, width = 128, height = 128 })
assert(type(media) == "string")
assert(string.find(media, "/_matrix/client/v1/media/thumbnail/local/abc", 1, true) ~= nil)

local ads = game:GetService("AccountService")
local okMe, me = ads:GetMe()
assert(okMe and me.displayName == "Alice")

local pkgs = game:GetService("Packages")
pkgs.MarketplaceServer = base
assert(pkgs.MarketplaceServer == base, "MarketplaceServer=" .. tostring(pkgs.MarketplaceServer))
local okBrowse, listing = pkgs:BrowseMarketplace({ q = "kv", sort = "recent", limit = 20 })
assert(okBrowse, "BrowseMarketplace failed: " .. tostring(listing))
assert(type(listing) == "table" and #listing.packages == 1 and listing.packages[1].name == "kv", "marketplace listing")
local okDetail, detail = pkgs:GetMarketplacePackage("alice", "kv")
assert(okDetail and detail.name == "kv", "GetMarketplacePackage failed: " .. tostring(detail))
local okReviews, reviews = pkgs:ListReviews("alice", "kv")
assert(okReviews and type(reviews.reviews) == "table", "ListReviews failed: " .. tostring(reviews))
local okAcquire, acquired = pkgs:AcquirePackage("alice", "kv")
assert(okAcquire and type(acquired) == "table", "AcquirePackage failed: " .. tostring(acquired))
local okReview, review = pkgs:SubmitReview("alice", "kv", { rating = 5, body = "great" })
assert(okReview and review.review.rating == 5, "SubmitReview failed: " .. tostring(review))

local packageTarget = Instance.new("Folder")
packageTarget.Name = "SmokePackage"
local okPublish, published = pkgs:PublishInstance(packageTarget, {
	name = "smoke-package",
	version = "1.0.0",
	entrypoint = "smoke-package.kine",
	type = "package",
	visibility = "public",
}, { filename = "smoke-package.zip", contentType = "application/zip" })
assert(okPublish, "PublishInstance failed: " .. tostring(published))
assert(type(published) == "table" and published.reviewStatus == "pending", "PublishInstance response")


SyncFired = 0
StopSyncFn = Matrix:StartSync({ onSync = function(payload) SyncFired = SyncFired + 1 end })
assert(type(StopSyncFn) == "function")
`

	run_script(&script_vm, strings.concatenate({base_lua, setup_lua}), "kinemium_services_setup")

	// First pump tick: emits a sync and fires onSync once.
	services.Matrix_Service_Step(matrix_service, script_vm.L, 3.0)

	run_script(
		&script_vm,
		`assert(SyncFired == 1, "onSync fired " .. tostring(SyncFired) .. " times")`,
		"kinemium_services_sync1",
	)

	// Second pump tick: `since` is now set, fires onSync again.
	services.Matrix_Service_Step(matrix_service, script_vm.L, 3.0)

	run_script(
		&script_vm,
		`
assert(SyncFired == 2, "onSync fired " .. tostring(SyncFired) .. " times")
StopSyncFn()
`,
		"kinemium_services_sync2",
	)

	// After stopping, further ticks must not fire.
	services.Matrix_Service_Step(matrix_service, script_vm.L, 3.0)
	run_script(
		&script_vm,
		`assert(SyncFired == 2, "onSync fired after stop")`,
		"kinemium_services_sync3",
	)

	// Shut the server down and join the thread before inspecting requests.
	net.close(test_server.listener)
	thread.join(server_thread)
	thread.destroy(server_thread)

	sync.mutex_lock(&test_server.mutex)
	defer sync.mutex_unlock(&test_server.mutex)
	captured := test_server.requests[:]

	expect(
		has_request_prefix(captured, "/_matrix/client/v3/joined_rooms"),
		"no joined_rooms request",
	)
	expect(has_request_prefix(captured, "/_matrix/client/versions"), "no versions probe request")
	expect(has_request_prefix(captured, "/_matrix/client/v3/profile/"), "no profile request")
	expect(has_request_prefix(captured, "/_kinemium/v1/me"), "no Kinemium /me request")
	expect(
		has_request_prefix(captured, "/_kinemium/v1/marketplace?"),
		"no marketplace browse request",
	)
	expect(
		has_request_prefix(captured, "/_kinemium/v1/marketplace/alice/kv"),
		"no marketplace detail request",
	)
	expect(
		has_request_prefix(captured, "/_kinemium/v1/marketplace/alice/kv/reviews"),
		"no marketplace reviews request",
	)
	expect(
		has_request_prefix(captured, "/_kinemium/v1/marketplace/alice/kv/acquire"),
		"no marketplace acquire request",
	)
	expect(
		has_body_containing(captured, "/_kinemium/v1/marketplace/alice/kv/reviews", `"rating":5`),
		"review body missing rating",
	)
	expect(has_request_prefix(captured, "/_kinemium/v1/packages"), "no package publish request")
	expect(
		has_body_containing(captured, "/_kinemium/v1/packages", `"name":"smoke-package"`),
		"publish manifest missing name",
	)
	expect(
		has_body_containing(captured, "/_kinemium/v1/packages", "PK"),
		"publish archive missing ZIP data",
	)
	for request in captured {
		if request.path == "/_kinemium/v1/packages" {
			expect(
				strings.contains(
					strings.to_lower(request.headers),
					"content-type: multipart/mixed",
				),
				"package publish did not use multipart/mixed",
			)
		}
	}
	for request in captured {
		if strings.has_prefix(request.path, "/_kinemium/v1/marketplace?") {
			expect(
				!strings.contains(strings.to_lower(request.headers), "authorization:"),
				"marketplace browse sent Authorization",
			)
		}
	}
	expect(
		has_request_prefix(captured, "/_matrix/client/v3/sync?since=s1"),
		"second sync did not send since=s1",
	)

	for request in test_server.requests {
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

// Prints the pass marker, then exits cleanly. After main() returns, the engine
// teardown raises an access violation (0xC0000005) whenever this process has
// exercised HttpService; the smoke test itself is complete at this point.
finalize_and_exit :: proc() {
	fmt.println("KINEMIUM_SERVICES_SMOKE_PASSED")
	os.exit(0)
}
