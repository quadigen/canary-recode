#+build darwin
#+build !js

package services

import "base:runtime"
import "core:c"
import "core:sync"
import "core:sys/posix"
import "core:thread"

Telemetry_Stream :: struct {
	read_fd:     posix.FD,
	write_fd:    posix.FD,
	original_fd: posix.FD,
	target_fd:   posix.FD,
	reader:      ^thread.Thread,
	stop_mu:     sync.Mutex,
	stopping:    bool,
}

telemetry_stdout_stream: Telemetry_Stream
telemetry_stderr_stream: Telemetry_Stream
telemetry_capture_installed: bool
telemetry_capture_mutex: sync.Mutex

telemetry_write_to_fd :: proc(fd: posix.FD, value: string) {
	if fd < 0 {return}
	data := transmute([]u8)value
	for len(data) > 0 {
		n := posix.write(fd, raw_data(data), c.size_t(len(data)))
		if n <= 0 {return}
		data = data[n:]
	}
}

telemetry_read_log_pipe :: proc(user_data: rawptr) {
	context.allocator = runtime.heap_allocator()
	stream := cast(^Telemetry_Stream)user_data
	read_buffer: [4096]u8
	line: [1024]u8
	line_len := 0
	fds := [1]posix.pollfd{{fd = stream.read_fd, events = {.IN}}}
	for {
		sync.mutex_lock(&stream.stop_mu)
		stopping := stream.stopping
		sync.mutex_unlock(&stream.stop_mu)
		if stopping {break}
		if posix.poll(&fds[0], 1, 50) < 0 {continue}
		if .IN not_in fds[0].revents && .HUP not_in fds[0].revents {continue}
		n := posix.read(stream.read_fd, raw_data(read_buffer[:]), c.size_t(len(read_buffer)))
		if n <= 0 {break}
		remaining := read_buffer[:n]
		for len(remaining) > 0 {
			written := posix.write(
				stream.original_fd,
				raw_data(remaining),
				c.size_t(len(remaining)),
			)
			if written <= 0 {break}
			remaining = remaining[written:]
		}
		for ch in read_buffer[:n] {
			if ch == '\n' || ch == '\r' || ch == 0 {
				if line_len > 0 {Telemetry_Record_Native_Line(string(line[:line_len]))}
				line_len = 0
			} else if line_len < len(line) {
				line[line_len] = ch
				line_len += 1
			}
		}
	}
	if line_len > 0 {Telemetry_Record_Native_Line(string(line[:line_len]))}
}

telemetry_capture_stream_start :: proc(stream: ^Telemetry_Stream, target_fd: posix.FD) -> bool {
	stream^ = Telemetry_Stream {
		read_fd     = -1,
		write_fd    = -1,
		original_fd = -1,
		target_fd   = target_fd,
	}
	original := posix.dup(target_fd)
	if original < 0 {return false}
	stream.original_fd = original
	pipe: [2]posix.FD
	if posix.pipe(&pipe) != .OK {
		_ = posix.close(original)
		stream.original_fd = -1
		return false
	}
	stream.read_fd = pipe[0]
	stream.write_fd = pipe[1]
	if posix.fcntl(stream.read_fd, .SETFD, posix.FD_CLOEXEC) < 0 ||
	   posix.fcntl(stream.write_fd, .SETFD, posix.FD_CLOEXEC) < 0 {
		_ = posix.close(stream.read_fd)
		_ = posix.close(stream.write_fd)
		_ = posix.close(stream.original_fd)
		stream^ = {}
		return false
	}
	stream.reader = thread.create_and_start_with_data(stream, telemetry_read_log_pipe)
	if stream.reader == nil {
		_ = posix.close(stream.read_fd)
		_ = posix.close(stream.write_fd)
		_ = posix.close(stream.original_fd)
		stream^ = {}
		return false
	}
	if posix.dup2(stream.write_fd, target_fd) < 0 {
		_ = posix.close(stream.write_fd)
		thread.join(stream.reader)
		thread.destroy(stream.reader)
		_ = posix.close(stream.read_fd)
		_ = posix.close(stream.original_fd)
		stream^ = {}
		return false
	}
	_ = posix.close(stream.write_fd)
	stream.write_fd = -1
	return true
}

telemetry_capture_stream_stop :: proc(stream: ^Telemetry_Stream) {
	if stream.original_fd < 0 {return}
	sync.mutex_lock(&stream.stop_mu)
	stream.stopping = true
	sync.mutex_unlock(&stream.stop_mu)
	_ = posix.dup2(stream.original_fd, stream.target_fd)
	if stream.write_fd >= 0 {_ = posix.close(stream.write_fd)}
	if stream.reader != nil {
		thread.join(stream.reader)
		thread.destroy(stream.reader)
	}
	_ = posix.close(stream.read_fd)
	_ = posix.close(stream.original_fd)
	stream^ = {}
}

Telemetry_LogCapture_Install :: proc() {
	sync.mutex_lock(&telemetry_capture_mutex)
	defer sync.mutex_unlock(&telemetry_capture_mutex)
	if telemetry_capture_installed {return}
	if !telemetry_capture_stream_start(&telemetry_stdout_stream, 1) {return}
	if !telemetry_capture_stream_start(&telemetry_stderr_stream, 2) {
		telemetry_capture_stream_stop(&telemetry_stdout_stream)
		return
	}
	telemetry_capture_installed = true
}

Telemetry_LogCapture_Uninstall :: proc() {
	sync.mutex_lock(&telemetry_capture_mutex)
	defer sync.mutex_unlock(&telemetry_capture_mutex)
	if !telemetry_capture_installed {return}
	telemetry_capture_stream_stop(&telemetry_stdout_stream)
	telemetry_capture_stream_stop(&telemetry_stderr_stream)
	telemetry_capture_installed = false
}

Telemetry_LogService_Output :: proc(tag, message: string) {
	sync.mutex_lock(&telemetry_capture_mutex)
	defer sync.mutex_unlock(&telemetry_capture_mutex)
	fd := posix.FD(1)
	if tag == "WARN" || tag == "ERROR" {fd = 2}
	if telemetry_capture_installed {
		if fd == 1 && telemetry_stdout_stream.original_fd >= 0 {
			fd = telemetry_stdout_stream.original_fd
		} else if fd == 2 && telemetry_stderr_stream.original_fd >= 0 {
			fd = telemetry_stderr_stream.original_fd
		}
	}
	if tag != "" {
		telemetry_write_to_fd(fd, "[")
		telemetry_write_to_fd(fd, tag)
		telemetry_write_to_fd(fd, "] ")
	}
	telemetry_write_to_fd(fd, message)
	telemetry_write_to_fd(fd, "\n")
}
