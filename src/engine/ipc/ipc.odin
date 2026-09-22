package ipc

import "core:os"

MAGIC_0 :: u8('K')
MAGIC_1 :: u8('I')
MAGIC_2 :: u8('P')
MAGIC_3 :: u8('C')

PROTOCOL_VERSION :: u16(1)

HEADER_SIZE      :: 12
MAX_MESSAGE_SIZE :: 16 * 1024 * 1024


Error_Kind :: enum {
	None,

	Closed,
	Invalid_Header,
	Version_Mismatch,
	Message_Too_Large,

	Read_Failed,
	Write_Failed,
	Pipe_Failed,
	Spawn_Failed,
}


Error :: struct {
	kind:     Error_Kind,
	os_error: os.Error,
}


Message :: struct {
	kind:    u16,
	payload: []u8,
}


Channel :: struct {
	read:  ^os.File,
	write: ^os.File,

	owns_read:  bool,
	owns_write: bool,
}


is_ok :: proc(err: Error) -> bool {
	return err.kind == .None
}


make_error :: proc(kind: Error_Kind, err: os.Error = nil) -> Error {
	return Error{
		kind     = kind,
		os_error = err,
	}
}


put_u16_le :: proc(dst: []u8, offset: int, value: u16) {
	dst[offset + 0] = u8(value)
	dst[offset + 1] = u8(value >> 8)
}


put_u32_le :: proc(dst: []u8, offset: int, value: u32) {
	dst[offset + 0] = u8(value)
	dst[offset + 1] = u8(value >> 8)
	dst[offset + 2] = u8(value >> 16)
	dst[offset + 3] = u8(value >> 24)
}


get_u16_le :: proc(src: []u8, offset: int) -> u16 {
	return u16(src[offset + 0]) |
	       u16(src[offset + 1]) << 8
}


get_u32_le :: proc(src: []u8, offset: int) -> u32 {
	return u32(src[offset + 0]) |
	       u32(src[offset + 1]) << 8 |
	       u32(src[offset + 2]) << 16 |
	       u32(src[offset + 3]) << 24
}


write_all :: proc(file: ^os.File, data: []u8) -> Error {
	offset := 0

	for offset < len(data) {
		n, err := os.write(file, data[offset:])
		if err != nil {
			return make_error(.Write_Failed, err)
		}

		if n <= 0 {
			return make_error(.Closed)
		}

		offset += n
	}

	return {}
}


read_exact :: proc(file: ^os.File, data: []u8) -> Error {
	offset := 0

	for offset < len(data) {
		n, err := os.read(file, data[offset:])
		if err != nil {
			return make_error(.Read_Failed, err)
		}

		if n <= 0 {
			return make_error(.Closed)
		}

		offset += n
	}

	return {}
}


send :: proc(channel: ^Channel, kind: u16, payload: []u8) -> Error {
	if channel == nil || channel.write == nil {
		return make_error(.Closed)
	}

	if len(payload) > MAX_MESSAGE_SIZE {
		return make_error(.Message_Too_Large)
	}

	header: [HEADER_SIZE]u8

	header[0] = MAGIC_0
	header[1] = MAGIC_1
	header[2] = MAGIC_2
	header[3] = MAGIC_3

	put_u16_le(header[:], 4, PROTOCOL_VERSION)
	put_u16_le(header[:], 6, kind)
	put_u32_le(header[:], 8, u32(len(payload)))

	err := write_all(channel.write, header[:])
	if !is_ok(err) {
		return err
	}

	if len(payload) > 0 {
		err = write_all(channel.write, payload)
		if !is_ok(err) {
			return err
		}
	}

	return {}
}


send_string :: proc(channel: ^Channel, kind: u16, payload: string) -> Error {
	return send(channel, kind, transmute([]u8)payload)
}


receive :: proc(channel: ^Channel) -> (Message, Error) {
	message: Message

	if channel == nil || channel.read == nil {
		return message, make_error(.Closed)
	}

	header: [HEADER_SIZE]u8

	err := read_exact(channel.read, header[:])
	if !is_ok(err) {
		return message, err
	}

	if header[0] != MAGIC_0 ||
	   header[1] != MAGIC_1 ||
	   header[2] != MAGIC_2 ||
	   header[3] != MAGIC_3 {
		return message, make_error(.Invalid_Header)
	}

	version := get_u16_le(header[:], 4)

	if version != PROTOCOL_VERSION {
		return message, make_error(.Version_Mismatch)
	}

	kind := get_u16_le(header[:], 6)
	size := get_u32_le(header[:], 8)

	if size > MAX_MESSAGE_SIZE {
		return message, make_error(.Message_Too_Large)
	}

	message.kind = kind

	if size == 0 {
		return message, {}
	}

	message.payload = make([]u8, int(size))

	err = read_exact(channel.read, message.payload)
	if !is_ok(err) {
		delete(message.payload)
		message.payload = nil

		return message, err
	}

	return message, {}
}


destroy_message :: proc(message: ^Message) {
	if message == nil {
		return
	}

	if message.payload != nil {
		delete(message.payload)
		message.payload = nil
	}
}


has_message :: proc(channel: ^Channel) -> (bool, Error) {
	if channel == nil || channel.read == nil {
		return false, make_error(.Closed)
	}

	has_data, err := os.pipe_has_data(channel.read)
	if err != nil {
		return false, make_error(.Read_Failed, err)
	}

	return has_data, {}
}


close :: proc(channel: ^Channel) {
	if channel == nil {
		return
	}

	if channel.owns_read && channel.read != nil {
		_ = os.close(channel.read)
	}

	if channel.owns_write &&
	   channel.write != nil &&
	   channel.write != channel.read {
		_ = os.close(channel.write)
	}

	channel.read = nil
	channel.write = nil
}


from_stdio :: proc() -> Channel {
	return Channel{
		read       = os.stdin,
		write      = os.stdout,
		owns_read  = false,
		owns_write = false,
	}
}


spawn :: proc(
	command: []string,
	working_dir := "",
) -> (
	process: os.Process,
	channel: Channel,
	err: Error,
) {
	child_read, parent_write, pipe_err := os.pipe()
	if pipe_err != nil {
		err = make_error(.Pipe_Failed, pipe_err)
		return
	}

	parent_read, child_write, pipe_err2 := os.pipe()
	if pipe_err2 != nil {
		_ = os.close(child_read)
		_ = os.close(parent_write)

		err = make_error(.Pipe_Failed, pipe_err2)
		return
	}

	desc := os.Process_Desc{
		command     = command,
		working_dir = working_dir,

		stdin  = child_read,
		stdout = child_write,

		// Keep normal diagnostic output available.
		stderr = os.stderr,
	}

	process2, process_err := os.process_start(desc)

	_ = os.close(child_read)
	_ = os.close(child_write)

	if process_err != nil {
		_ = os.close(parent_read)
		_ = os.close(parent_write)

		err = make_error(.Spawn_Failed, process_err)
		return
	}

	channel = Channel{
		read       = parent_read,
		write      = parent_write,
		owns_read  = true,
		owns_write = true,
	}

	return
}