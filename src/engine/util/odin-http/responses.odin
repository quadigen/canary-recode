package http

import "core:bytes"
import "core:encoding/json"
import "core:io"
import "core:log"
import "core:nbio"
import "core:path/filepath"
import "core:strings"


respond_html :: proc(r: ^Response, html: string, status: Status = .OK, loc := #caller_location) {
	r.status = status
	headers_set_content_type(&r.headers, mime_to_content_type(Mime_Type.Html))
	body_set(r, html, loc)
	respond(r, loc)
}


respond_plain :: proc(r: ^Response, text: string, status: Status = .OK, loc := #caller_location) {
	r.status = status
	headers_set_content_type(&r.headers, mime_to_content_type(Mime_Type.Plain))
	body_set(r, text, loc)
	respond(r, loc)
}


respond_file :: proc(r: ^Response, path: string, content_type: Maybe(Mime_Type) = nil, loc := #caller_location) {


	assert_has_td(loc)
	assert(!r.sent, "response has already been sent", loc)

	mime := content_type.? or_else mime_from_extension(path)
	content_type := mime_to_content_type(mime)
	headers_set_content_type(&r.headers, content_type)

	nbio.open_poly(path, r, on_open)

	on_open :: proc(op: ^nbio.Operation, r: ^Response) {
		#partial switch op.open.err {
		case .Not_Found:
			log.debugf("respond_file, open %q, no such file or directory", op.open.path)
			respond_with_status(r, .Not_Found)
		case:
			log.warnf("respond_file, open %q error: %i", op.open.path, op.open.err)
			respond_with_status(r, .Not_Found)
		case nil:
			nbio.stat_poly2(op.open.handle, op.open.path, r, on_stat)
		}
	}

	on_stat :: proc(op: ^nbio.Operation, path: string, r: ^Response) {
		#partial switch op.stat.err {
		case:
			log.errorf("respond_file, could not stat %q: %v", path, op.stat.err)
			nbio.close(op.stat.handle)
			respond_with_status(r, .Not_Found)
		case nil:
			assert(op.stat.size < i64(max(int)))

			_response_write_heading(r, int(op.stat.size))

			bytes.buffer_grow(&r._buf, int(op.stat.size))
			buf := _dynamic_unwritten(r._buf.buf)[:op.stat.size]

			nbio.read_poly2(op.stat.handle, 0, buf, path, r, on_read, all = true)
		}
	}

	on_read :: proc(op: ^nbio.Operation, path: string, r: ^Response) {
		nbio.close(op.read.handle)
		#partial switch op.read.err {
		case:
			log.errorf("respond_file, could not read %q: %v", path, op.read.err)
			respond_with_status(r, .Internal_Server_Error)
		case nil:
			_dynamic_add_len(&r._buf.buf, op.read.read)
			respond_with_status(r, .OK)
		}
	}
}


respond_file_content :: proc(
	r: ^Response,
	path: string,
	content: []byte,
	status: Status = .OK,
	loc := #caller_location,
) {
	mime := mime_from_extension(path)
	content_type := mime_to_content_type(mime)

	r.status = status
	headers_set_content_type(&r.headers, content_type)
	body_set(r, content, loc)
	respond(r, loc)
}


respond_dir :: proc(r: ^Response, base, target, request: string, loc := #caller_location) {
	if !strings.has_prefix(request, base) {
		respond(r, Status.Not_Found)
		return
	}


	req_clean, err_req := filepath.clean(request, context.temp_allocator)
	base_clean, err_base := filepath.clean(base, context.temp_allocator)
	if err_req != nil || err_base != nil || !strings.has_prefix(req_clean, base_clean) {
		respond(r, Status.Not_Found)
		return
	}

	file_path, _ := filepath.join(
		[]string{"./", target, strings.trim_prefix(req_clean, base_clean)},
		context.temp_allocator,
	)
	respond_file(r, file_path, loc = loc)
}


respond_json :: proc(
	r: ^Response,
	v: any,
	status: Status = .OK,
	opt: json.Marshal_Options = {},
	loc := #caller_location,
) -> (
	err: json.Marshal_Error,
) {
	opt := opt

	r.status = status
	headers_set_content_type(&r.headers, mime_to_content_type(Mime_Type.Json))


	rw: Response_Writer
	buf: [128]byte
	response_writer_init(&rw, r, buf[:])


	defer io.close(rw.w)

	if err = json.marshal_to_writer(rw.w, v, opt); err != nil {
		headers_set_close(&r.headers)
		response_status(r, .Internal_Server_Error)
	}

	return
}


respond_with_none :: proc(r: ^Response, loc := #caller_location) {
	assert_has_td(loc)

	conn := r._conn
	req := conn.loop.req


	if rline, ok := req.line.(Requestline); ok && req.is_head && conn.server.opts.redirect_head_to_get {
		rline.method = .Head
	}

	response_send(r, conn, loc)
}


respond_with_status :: proc(r: ^Response, status: Status, loc := #caller_location) {
	response_status(r, status)
	respond(r, loc)
}


respond :: proc {
	respond_with_none,
	respond_with_status,
}
