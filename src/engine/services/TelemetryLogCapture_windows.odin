#+build windows
#+build !js

package services

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:sync"
import win32 "core:sys/windows"
import "core:thread"
import "core:time"

foreign import telemetry_ucrt "system:libucrt.lib"
foreign import telemetry_kernel32 "system:kernel32.lib"

foreign telemetry_ucrt {
	@(link_name = "_open_osfhandle")
	telemetry_ucrt_open_handle :: proc "c" (handle: int, flags: c.int) -> c.int ---
	@(link_name = "_dup")
	telemetry_ucrt_dup :: proc "c" (fd: c.int) -> c.int ---
	@(link_name = "_dup2")
	telemetry_ucrt_dup2 :: proc "c" (source, target: c.int) -> c.int ---
	@(link_name = "_close")
	telemetry_ucrt_close :: proc "c" (fd: c.int) -> c.int ---
	@(link_name = "_write")
	telemetry_ucrt_write :: proc "c" (fd: c.int, data: rawptr, length: c.uint) -> c.int ---
}

foreign telemetry_kernel32 {
	@(link_name = "SetStdHandle")
	telemetry_set_std_handle :: proc "system" (kind: win32.DWORD, handle: win32.HANDLE) -> win32.BOOL ---
}

Telemetry_Stream_Windows :: struct {
	read_handle:     win32.HANDLE,
	write_handle:    win32.HANDLE,
	previous_handle: win32.HANDLE,
	target_fd:       c.int,
	std_kind:        win32.DWORD,
	previous_fd:     c.int,
	saved_os_file:   ^os.File,
	capture_os_file: ^os.File,
	reader:          ^thread.Thread,
	stop_mu:         sync.Mutex,
	stopping:        bool,
	crt_redirected:  bool,
	active:          bool,
}

telemetry_stdout_stream_windows: Telemetry_Stream_Windows
telemetry_stderr_stream_windows: Telemetry_Stream_Windows
telemetry_capture_installed_windows: bool
telemetry_capture_mutex_windows: sync.Mutex

telemetry_win_handle_valid :: proc(handle: win32.HANDLE) -> bool {
	return handle != nil && handle != win32.INVALID_HANDLE
}

telemetry_windows_forward :: proc(stream: ^Telemetry_Stream_Windows, text: []u8) {
	remaining := text
	if telemetry_win_handle_valid(stream.previous_handle) {
		for len(remaining) > 0 {
			written: win32.DWORD
			if !win32.WriteFile(
				   stream.previous_handle,
				   raw_data(remaining),
				   win32.DWORD(len(remaining)),
				   &written,
				   nil,
			   ) ||
			   written == 0 {break}
			remaining = remaining[written:]
		}
		return
	}
	if stream.previous_fd >= 0 {
		for len(remaining) > 0 {
			written := telemetry_ucrt_write(
				stream.previous_fd,
				raw_data(remaining),
				c.uint(len(remaining)),
			)
			if written <= 0 {return}
			remaining = remaining[written:]
		}
	}
}

telemetry_windows_write :: proc(stream: ^Telemetry_Stream_Windows, text: string) {
	telemetry_windows_forward(stream, transmute([]u8)text)
}

telemetry_windows_pipe_reader :: proc(user_data: rawptr) {
	context.allocator = runtime.heap_allocator()
	stream := cast(^Telemetry_Stream_Windows)user_data
	buffer: [4096]u8
	line: [1024]u8
	line_len := 0
	for {
		sync.mutex_lock(&stream.stop_mu)
		stopping := stream.stopping
		sync.mutex_unlock(&stream.stop_mu)
		if stopping {break}
		available: win32.DWORD
		if !win32.PeekNamedPipe(stream.read_handle, nil, 0, nil, &available, nil) {break}
		if available == 0 {
			time.sleep(20 * time.Millisecond)
			continue
		}
		to_read := min(available, win32.DWORD(len(buffer)))
		n: win32.DWORD
		if !win32.ReadFile(stream.read_handle, &buffer[0], to_read, &n, nil) || n == 0 {break}
		telemetry_windows_forward(stream, buffer[:n])
		for ch in buffer[:n] {
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

telemetry_windows_stream_start :: proc(
	stream: ^Telemetry_Stream_Windows,
	fd: c.int,
	kind: win32.DWORD,
) -> bool {
	stream^ = Telemetry_Stream_Windows {
		target_fd   = fd,
		std_kind    = kind,
		previous_fd = -1,
	}
	stream.previous_handle = win32.GetStdHandle(kind)
	stream.saved_os_file = os.stdout
	if fd == 2 {stream.saved_os_file = os.stderr}
	stream.previous_fd = telemetry_ucrt_dup(fd)
	if !win32.CreatePipe(&stream.read_handle, &stream.write_handle, nil, 0) {return false}

	stream.capture_os_file = os.new_file(uintptr(stream.write_handle), "")
	if stream.capture_os_file == nil {
		_ = win32.CloseHandle(stream.read_handle)
		_ = win32.CloseHandle(stream.write_handle)
		stream.write_handle = nil
		stream.read_handle = nil
		if stream.previous_fd >= 0 {_ = telemetry_ucrt_close(stream.previous_fd)}
		stream.previous_fd = -1
		return false
	}

	process := win32.GetCurrentProcess()
	dup_handle: win32.HANDLE
	if win32.DuplicateHandle(
		process,
		stream.write_handle,
		process,
		&dup_handle,
		0,
		false,
		win32.DUPLICATE_SAME_ACCESS,
	) {
		constant_binary_mode: c.int = 0x8000
		crt_pipe_fd := telemetry_ucrt_open_handle(int(uintptr(dup_handle)), constant_binary_mode)
		if crt_pipe_fd >= 0 {
			stream.crt_redirected = telemetry_ucrt_dup2(crt_pipe_fd, fd) == 0
			_ = telemetry_ucrt_close(crt_pipe_fd)
		} else {
			_ = win32.CloseHandle(dup_handle)
		}
	}

	if !telemetry_set_std_handle(kind, stream.write_handle) {
		if stream.crt_redirected {
			if stream.previous_fd >= 0 {
				_ = telemetry_ucrt_dup2(stream.previous_fd, fd)
			} else {
				_ = telemetry_ucrt_close(fd)
			}
		}
		_ = os.close(stream.capture_os_file)
		_ = win32.CloseHandle(stream.read_handle)
		if stream.previous_fd >= 0 {_ = telemetry_ucrt_close(stream.previous_fd)}
		stream^ = {}
		return false
	}
	if fd == 1 {os.stdout = stream.capture_os_file} else {os.stderr = stream.capture_os_file}
	stream.reader = thread.create_and_start_with_data(stream, telemetry_windows_pipe_reader)
	if stream.reader == nil {
		if fd == 1 {os.stdout = stream.saved_os_file} else {os.stderr = stream.saved_os_file}
		_ = telemetry_set_std_handle(kind, stream.previous_handle)
		if stream.crt_redirected {
			if stream.previous_fd >= 0 {
				_ = telemetry_ucrt_dup2(stream.previous_fd, fd)
			} else {
				_ = telemetry_ucrt_close(fd)
			}
		}
		_ = os.close(stream.capture_os_file)
		_ = win32.CloseHandle(stream.read_handle)
		if stream.previous_fd >= 0 {_ = telemetry_ucrt_close(stream.previous_fd)}
		stream^ = {}
		return false
	}
	stream.active = true
	return true
}

telemetry_windows_stream_stop :: proc(stream: ^Telemetry_Stream_Windows) {
	if !stream.active {return}
	sync.mutex_lock(&stream.stop_mu)
	stream.stopping = true
	sync.mutex_unlock(&stream.stop_mu)
	if stream.target_fd ==
	   1 {os.stdout = stream.saved_os_file} else {os.stderr = stream.saved_os_file}
	_ = telemetry_set_std_handle(stream.std_kind, stream.previous_handle)
	if stream.crt_redirected {
		if stream.previous_fd >= 0 {
			_ = telemetry_ucrt_dup2(stream.previous_fd, stream.target_fd)
		} else {
			_ = telemetry_ucrt_close(stream.target_fd)
		}
	}
	_ = os.close(stream.capture_os_file)
	if stream.reader != nil {
		thread.join(stream.reader)
		thread.destroy(stream.reader)
	}
	_ = win32.CloseHandle(stream.read_handle)
	if stream.previous_fd >= 0 {_ = telemetry_ucrt_close(stream.previous_fd)}
	stream^ = {}
}

Telemetry_LogCapture_Install :: proc() {
	sync.mutex_lock(&telemetry_capture_mutex_windows)
	defer sync.mutex_unlock(&telemetry_capture_mutex_windows)
	if telemetry_capture_installed_windows {return}
	if !telemetry_windows_stream_start(
		&telemetry_stdout_stream_windows,
		1,
		win32.STD_OUTPUT_HANDLE,
	) {return}
	if !telemetry_windows_stream_start(
		&telemetry_stderr_stream_windows,
		2,
		win32.STD_ERROR_HANDLE,
	) {
		telemetry_windows_stream_stop(&telemetry_stdout_stream_windows)
		return
	}
	telemetry_capture_installed_windows = true
}

Telemetry_LogCapture_Uninstall :: proc() {
	sync.mutex_lock(&telemetry_capture_mutex_windows)
	defer sync.mutex_unlock(&telemetry_capture_mutex_windows)
	if !telemetry_capture_installed_windows {return}
	telemetry_windows_stream_stop(&telemetry_stdout_stream_windows)
	telemetry_windows_stream_stop(&telemetry_stderr_stream_windows)
	telemetry_capture_installed_windows = false
}

Telemetry_LogService_Output :: proc(tag, message: string) {
	sync.mutex_lock(&telemetry_capture_mutex_windows)
	defer sync.mutex_unlock(&telemetry_capture_mutex_windows)
	if !telemetry_capture_installed_windows {
		if tag == "" {
			fmt.println(message)
		} else if tag == "WARN" || tag == "ERROR" {
			fmt.eprintf("[%s] %s\n", tag, message)
		} else {
			fmt.printf("[%s] %s\n", tag, message)
		}
		return
	}
	stream := &telemetry_stdout_stream_windows
	if tag == "WARN" || tag == "ERROR" {stream = &telemetry_stderr_stream_windows}
	if tag != "" {
		telemetry_windows_write(stream, "[")
		telemetry_windows_write(stream, tag)
		telemetry_windows_write(stream, "] ")
	}
	telemetry_windows_write(stream, message)
	telemetry_windows_write(stream, "\n")
}
