package debuglog

import "core:fmt"
import "core:strings"

when #config(KINE_ANDROID, false) {
	foreign import liblog "liblog.so"

	@(default_calling_convention = "c")
	foreign liblog {
		__android_log_write :: proc(prio: i32, tag: cstring, text: cstring) -> i32 ---
	}
}

ANDROID_LOG_DEBUG :: 3
ANDROID_LOG_ERROR :: 6

Log :: proc(message: string) {
	when #config(KINE_ANDROID, false) {
		cstr, _ := strings.clone_to_cstring(message, context.temp_allocator)
		_ = __android_log_write(ANDROID_LOG_DEBUG, "KineD", cstr)
	} else {
		fmt.eprintln(message)
	}
}

Log_Error :: proc(message: string) {
	when #config(KINE_ANDROID, false) {
		cstr, _ := strings.clone_to_cstring(message, context.temp_allocator)
		_ = __android_log_write(ANDROID_LOG_ERROR, "KineD", cstr)
	} else {
		fmt.eprintln(message)
	}
}
