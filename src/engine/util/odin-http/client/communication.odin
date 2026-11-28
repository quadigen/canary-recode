#+private
package client

import "core:bufio"
import "core:bytes"
import "core:c"
import "core:io"
import "core:log"
import "core:net"
import "core:strconv"
import "core:strings"

import http ".."
import openssl "../openssl"

parse_endpoint :: proc(target: string) -> (url: http.URL, endpoint: net.Endpoint, err: net.Network_Error) {
	url = http.url_parse(target)
	host_or_endpoint := net.parse_hostname_or_endpoint(url.host) or_return

	switch t in host_or_endpoint {
	case net.Endpoint:
		endpoint = t
		return
	case net.Host:
		ep4, ep6 := net.resolve(t.hostname) or_return
		endpoint = ep4 if ep4.address != nil else ep6

		endpoint.port = t.port
		if endpoint.port == 0 {
			endpoint.port = url.scheme == "https" ? 443 : 80
		}
		return
	case:
		unreachable()
	}
}


public_endpoint :: proc(endpoint: net.Endpoint) -> bool {
	switch ip in endpoint.address {
	case net.IP4_Address:
		a, b, c := ip[0], ip[1], ip[2]
		return(
			!(a == 0 ||
				a == 10 ||
				a == 127 ||
				a >= 224 ||
				(a == 169 && b == 254) ||
				(a == 172 && b >= 16 && b <= 31) ||
				(a == 192 && (b == 168 || (b == 0 && (c == 0 || c == 2)))) ||
				(a == 100 && b >= 64 && b <= 127) ||
				(a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100))) ||
				(a == 203 && b == 0 && c == 113)) \
		)
	case net.IP6_Address:
		a, b := u16(ip[0]), u16(ip[1])
		return a >= 0x2000 && a <= 0x3fff && a != 0x2002 && !(a == 0x2001 && (b <= 0x01ff || b == 0x0db8))
	}
	return false
}

format_request :: proc(target: http.URL, request: ^Request, allocator := context.allocator) -> (buf: bytes.Buffer) {

	bytes.buffer_init_allocator(&buf, 0, bytes.buffer_length(&request.body) + 100, allocator)

	http.requestline_write(
		bytes.buffer_to_stream(&buf),
		{method = request.method, target = target, version = http.Version{1, 1}},
	)

	if !http.headers_has_unsafe(request.headers, "content-length") {
		buf_len := bytes.buffer_length(&request.body)
		if buf_len == 0 {
			bytes.buffer_write_string(&buf, "content-length: 0\r\n")
		} else {
			bytes.buffer_write_string(&buf, "content-length: ")


			bytes.buffer_grow(&buf, buf_len + 20)


			unwritten := http._dynamic_unwritten(buf.buf)
			l := len(strconv.write_int(unwritten, i64(buf_len), 10))
			assert(l <= 20)
			http._dynamic_add_len(&buf.buf, l)

			bytes.buffer_write_string(&buf, "\r\n")
		}
	}

	if !http.headers_has_unsafe(request.headers, "accept") {
		bytes.buffer_write_string(&buf, "accept: */*\r\n")
	}

	if !http.headers_has_unsafe(request.headers, "user-agent") {
		bytes.buffer_write_string(&buf, "user-agent: odin-http\r\n")
	}

	if !http.headers_has_unsafe(request.headers, "host") {
		bytes.buffer_write_string(&buf, "host: ")
		bytes.buffer_write_string(&buf, target.host)
		bytes.buffer_write_string(&buf, "\r\n")
	}

	for header, value in request.headers._kv {
		bytes.buffer_write_string(&buf, header)
		bytes.buffer_write_string(&buf, ": ")


		esc_value, was_allocation := strings.replace_all(value, "\n", "\\n", allocator)
		defer if was_allocation {delete(esc_value)}

		bytes.buffer_write_string(&buf, esc_value)
		bytes.buffer_write_string(&buf, "\r\n")
	}

	if len(request.cookies) > 0 {
		bytes.buffer_write_string(&buf, "cookie: ")

		for cookie, i in request.cookies {
			bytes.buffer_write_string(&buf, cookie.name)
			bytes.buffer_write_byte(&buf, '=')
			bytes.buffer_write_string(&buf, cookie.value)

			if i != len(request.cookies) - 1 {
				bytes.buffer_write_string(&buf, "; ")
			}
		}

		bytes.buffer_write_string(&buf, "\r\n")
	}


	bytes.buffer_write_string(&buf, "\r\n")

	bytes.buffer_write(&buf, bytes.buffer_to_bytes(&request.body))
	return
}

SSL_Communication :: struct {
	socket: net.TCP_Socket,
	ssl:    ^openssl.SSL,
	ctx:    ^openssl.SSL_CTX,
}

Communication :: union {
	net.TCP_Socket,
	SSL_Communication,
}

parse_response :: proc(socket: Communication, allocator := context.allocator) -> (res: Response, err: Error) {
	res._socket = socket

	stream: io.Stream
	switch comm in socket {
	case net.TCP_Socket:
		stream = tcp_stream(comm)
	case SSL_Communication:
		stream = ssl_tcp_stream(comm.ssl)
	}

	stream_reader := io.to_reader(stream)
	scanner: bufio.Scanner
	bufio.scanner_init(&scanner, stream_reader, allocator)
	http.headers_init(&res.headers, allocator)
	defer if err != nil {
		res._body = scanner
		response_destroy(&res)
		res = {}
	}

	if !bufio.scanner_scan(&scanner) {
		err = bufio.scanner_error(&scanner)
		if err == nil {err = Request_Error.Invalid_Response_Header}
		return
	}

	rline_str := bufio.scanner_text(&scanner)
	si := strings.index_byte(rline_str, ' ')
	if si <= 0 {return res, Request_Error.Invalid_Response_HTTP_Version}

	version, ok := http.version_parse(rline_str[:si])
	if !ok {
		err = Request_Error.Invalid_Response_HTTP_Version
		return
	}


	if version.major != 1 {
		err = Request_Error.Invalid_Response_HTTP_Version
		return
	}

	res.status, ok = http.status_from_string(rline_str[si + 1:])
	if !ok {
		err = Request_Error.Invalid_Response_Method
		return
	}

	res.cookies.allocator = allocator
	header_count := 0

	for {
		if !bufio.scanner_scan(&scanner) {
			err = bufio.scanner_error(&scanner)
			if err == nil {err = Request_Error.Invalid_Response_Header}
			return
		}

		header_count += 1
		if header_count > 128 {return res, Request_Error.Invalid_Response_Header}
		line := bufio.scanner_text(&scanner)

		if line == "" {break}

		key, hok := http.header_parse(&res.headers, line, allocator)
		if !hok {
			err = Request_Error.Invalid_Response_Header
			return
		}

		if key == "set-cookie" {
			cookie_str := http.headers_get_unsafe(res.headers, "set-cookie")
			http.headers_delete_unsafe(&res.headers, "set-cookie")
			delete(key, allocator)

			cookie, cok := http.cookie_parse(cookie_str, allocator)
			if !cok {
				err = Request_Error.Invalid_Response_Cookie
				delete(cookie_str, allocator)
				return
			}

			append(&res.cookies, cookie)
		}
	}

	if !http.headers_validate(&res.headers) {
		err = Request_Error.Invalid_Response_Header
		return
	}

	res.headers.readonly = true

	res._body = scanner
	return res, nil
}

ssl_tcp_stream :: proc(sock: ^openssl.SSL) -> (s: io.Stream) {
	s.data = sock
	s.procedure = _ssl_stream_proc
	return s
}

@(private)
_ssl_stream_proc :: proc(
	stream_data: rawptr,
	mode: io.Stream_Mode,
	p: []byte,
	offset: i64,
	whence: io.Seek_From,
) -> (
	n: i64,
	err: io.Error,
) {
	#partial switch mode {
	case .Query:
		return io.query_utility(io.Stream_Mode_Set{.Query, .Read})
	case .Read:
		ssl := cast(^openssl.SSL)stream_data
		ret := openssl.SSL_read(ssl, raw_data(p), c.int(len(p)))
		if ret <= 0 {
			return 0, .Unexpected_EOF
		}

		return i64(ret), nil
	case:
		err = .Empty
	}
	return
}


tcp_stream :: proc(sock: net.TCP_Socket) -> (s: io.Stream) {
	s.data = rawptr(uintptr(sock))
	s.procedure = _socket_stream_proc
	return s
}

@(private)
_socket_stream_proc :: proc(
	stream_data: rawptr,
	mode: io.Stream_Mode,
	p: []byte,
	offset: i64,
	whence: io.Seek_From,
) -> (
	n: i64,
	err: io.Error,
) {
	#partial switch mode {
	case .Query:
		return io.query_utility(io.Stream_Mode_Set{.Query, .Read})
	case .Read:
		sock := net.TCP_Socket(uintptr(stream_data))
		received, recv_err := net.recv_tcp(sock, p)
		n = i64(received)

		#partial switch recv_err {
		case .None:
			err = .None
		case .Network_Unreachable,
		     .Insufficient_Resources,
		     .Invalid_Argument,
		     .Not_Connected,
		     .Connection_Closed,
		     .Timeout,
		     .Would_Block,
		     .Interrupted:
			log.errorf("unexpected error reading tcp: %s", recv_err)
			err = .Unexpected_EOF
		case:
			log.errorf("unexpected error reading tcp: %s", recv_err)
			err = .Unknown
		}
	case nil:
		err = .None
	case:
		assert(false, "recv_tcp only returns TCP_Recv_Error or nil")
	}
	return
}
