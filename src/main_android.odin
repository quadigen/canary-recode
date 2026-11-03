#+build linux:android
package main

import "base:intrinsics"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"
import "core:thread"

import debuglog "./engine/debuglog"

foreign _ {
	@(link_name = "__$startup_runtime")
	odin_startup_runtime :: proc "odin" () ---
}

@(export, link_name = "Kine_AndroidMain")
android_main :: proc "c" (argc: i32, argv: ^^u8) -> i32 {
	context = runtime.default_context()
	odin_startup_runtime()
	android_install_args(argc, argv)
	redirect_stdio_to_logcat()
	setup_android_home_dirs()
	context.assertion_failure_proc = android_assert_failure_proc
	main()
	return 0
}

foreign import loglib "liblog.so"

foreign loglib {
	@(link_name = "__android_log_write")
	android_log_write :: proc(priority: c.int, tag, text: cstring) -> c.int ---
}

foreign import sdl "libSDL3.so"

foreign sdl {
	@(link_name = "SDL_GetAndroidCachePath")
	sdl_get_android_cache_path :: proc() -> cstring ---
	@(link_name = "SDL_GetAndroidInternalStoragePath")
	sdl_get_android_internal_storage_path :: proc() -> cstring ---
}

setup_android_home_dirs :: proc() {
	cache_path := sdl_get_android_cache_path()
	data_path := sdl_get_android_internal_storage_path()

	if cache_path == nil && data_path == nil {
		android_log_write(5, "KineStdErr", cstring("KineStdEnv SDL storage paths unavailable"))
		return
	}

	home := data_path
	if home == nil {
		home = cache_path
	}


	if home != nil && posix.setenv("HOME", home, true) == .OK {
		android_log_write(5, "KineStdErr", cstring("KineStdEnv HOME set"))
	}
	if cache_path != nil && posix.setenv("XDG_CACHE_HOME", cache_path, true) == .OK {
		android_log_write(5, "KineStdErr", cstring("KineStdEnv XDG_CACHE_HOME set"))
	}
	if data_path != nil && posix.setenv("XDG_DATA_HOME", data_path, true) == .OK {
		android_log_write(5, "KineStdErr", cstring("KineStdEnv XDG_DATA_HOME set"))
	}


	if cache_path != nil && posix.setenv("TMPDIR", cache_path, true) == .OK {
		android_log_write(5, "KineStdErr", cstring("KineStdEnv TMPDIR set"))
	}
}


android_install_args :: proc(argc: i32, argv: ^^u8) {
	if argc <= 0 || argv == nil {
		return
	}
	args := make([]string, int(argc), context.allocator)


	argv_values := cast([^]^u8)argv
	for index in 0 ..< len(args) {
		value := argv_values[index]
		if value == nil {
			args[index] = ""
			continue
		}
		args[index] = strings.clone_from_cstring(cast(cstring)value, context.allocator)
	}
	os.args = args
}

stdio_pipe: [2]posix.FD
stderr_line_buffer: [4096]byte

emit_stdio_line :: proc(line: []byte) {
	if len(line) == 0 {return}
	chunk := line
	if len(chunk) > len(stderr_line_buffer) {
		chunk = chunk[:len(stderr_line_buffer)]
	}
	copy(stderr_line_buffer[:], chunk)
	stderr_line_buffer[len(chunk)] = 0

	android_log_write(5, "KineStdErr", cstring(&stderr_line_buffer[0]))
}

forward_stdio_reader :: proc(t: ^thread.Thread) {
	read_buffer: [1024]byte
	line: [4096]byte
	line_len := 0

	for {
		n := posix.read(stdio_pipe[0], raw_data(read_buffer[:]), c.size_t(len(read_buffer)))
		if n <= 0 {break}

		for i in 0 ..< int(n) {
			switch read_buffer[i] {
			case '\n', '\r', 0:
				emit_stdio_line(line[:line_len])
				line_len = 0
			case:
				if line_len < len(line) {
					line[line_len] = read_buffer[i]
					line_len += 1
				}
			}
		}
	}
}

redirect_stdio_to_logcat :: proc() {
	fds: [2]posix.FD
	if posix.pipe(&fds) != .OK {
		return
	}
	stdio_pipe = fds

	reader := thread.create(forward_stdio_reader)
	if reader == nil {
		_ = posix.close(fds[0])
		_ = posix.close(fds[1])
		return
	}
	thread.start(reader)


	_ = posix.dup2(fds[1], 1)
	_ = posix.dup2(fds[1], 2)
}

android_assert_failure_proc :: proc(
	prefix, message: string,
	loc: runtime.Source_Code_Location,
) -> ! {
	debuglog.Log(
		fmt.tprintf(
			"runtime %s: %s (%s:%d in %s)",
			prefix,
			message,
			loc.file_path,
			loc.line,
			loc.procedure,
		),
	)
	intrinsics.trap()
}
