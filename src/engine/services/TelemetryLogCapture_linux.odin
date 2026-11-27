#+build linux
#+build !js

package services

import "base:runtime"
import "core:sync"
import "core:sys/linux"
import "core:thread"

Telemetry_Stream :: struct {
	read_fd:     linux.Fd,
	write_fd:    linux.Fd,
	original_fd: linux.Fd,
	target_fd:   linux.Fd,
	reader:      ^thread.Thread,
	stop_mu:     sync.Mutex,
	stopping:    bool,
}

telemetry_stdout_stream: Telemetry_Stream
telemetry_stderr_stream: Telemetry_Stream
telemetry_capture_installed: bool
telemetry_capture_mutex: sync.Mutex

telemetry_write_to_fd :: proc(fd: linux.Fd, value: string) {
	if fd < 0 {return}
	data := transmute([]u8)value
	for len(data) > 0 {
		n, err := linux.write(fd, data)
		if err != .NONE || n <= 0 {return}
		data = data[n:]
	}
}

telemetry_read_log_pipe :: proc(user_data: rawptr) {
	context.allocator = runtime.heap_allocator()
	stream := cast(^Telemetry_Stream)user_data
	read_buffer: [4096]u8
	line: [1024]u8
	line_len := 0
	fds := [1]linux.Poll_Fd{{fd = stream.read_fd, events = {.IN}}}
	for {
		sync.mutex_lock(&stream.stop_mu)
		stopping := stream.stopping
		sync.mutex_unlock(&stream.stop_mu)
		if stopping {break}
		ready, poll_err := linux.poll(fds[:], 50)
		if poll_err != .NONE {
			if poll_err == .EINTR {continue}
			break
		}
		if ready == 0 {continue}
		n, err := linux.read(stream.read_fd, read_buffer[:])
		if err != .NONE || n <= 0 {break}
		remaining := read_buffer[:n]
		for len(remaining) > 0 {
			written, write_err := linux.write(stream.original_fd, remaining)
			if write_err != .NONE || written <= 0 {break}
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

telemetry_capture_stream_start :: proc(stream: ^Telemetry_Stream, target_fd: linux.Fd) -> bool {
	stream^ = Telemetry_Stream {
		read_fd     = -1,
		write_fd    = -1,
		original_fd = -1,
		target_fd   = target_fd,
	}
	original, err := linux.dup(target_fd)
	if err != .NONE {return false}
	stream.original_fd = original
	pipe: [2]linux.Fd
	if linux.pipe2(&pipe, {.CLOEXEC}) != .NONE {
		_ = linux.close(original)
		stream.original_fd = -1
		return false
	}
	stream.read_fd = pipe[0]
	stream.write_fd = pipe[1]
	stream.reader = thread.create_and_start_with_data(stream, telemetry_read_log_pipe)
	if stream.reader == nil {
		_ = linux.close(stream.read_fd)
		_ = linux.close(stream.write_fd)
		_ = linux.close(stream.original_fd)
		stream^ = {}
		return false
	}
	if _, swap_err := linux.dup2(stream.write_fd, target_fd); swap_err != .NONE {
		_ = linux.close(stream.write_fd)
		thread.join(stream.reader)
		thread.destroy(stream.reader)
		_ = linux.close(stream.read_fd)
		_ = linux.close(stream.original_fd)
		stream^ = {}
		return false
	}
	return true
}

telemetry_capture_stream_stop :: proc(stream: ^Telemetry_Stream) {
	if stream.original_fd < 0 {return}
	sync.mutex_lock(&stream.stop_mu)
	stream.stopping = true
	sync.mutex_unlock(&stream.stop_mu)
	_, _ = linux.dup2(stream.original_fd, stream.target_fd)
	_ = linux.close(stream.write_fd)
	if stream.reader != nil {
		thread.join(stream.reader)
		thread.destroy(stream.reader)
	}
	_ = linux.close(stream.read_fd)
	_ = linux.close(stream.original_fd)
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
	fd := linux.Fd(1)
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
