#+build js
package platform

import "base:runtime"
import "core:mem"

@(export)
kine_web_alloc :: proc "c" (size, alignment: uintptr) -> rawptr {
	context = runtime.default_context()
	allocator := runtime.default_wasm_allocator()
	result, err := mem.alloc(int(size), int(alignment), allocator)
	if err != nil { return nil }
	return result
}

@(export)
kine_web_free :: proc "c" (value: rawptr) {
	context = runtime.default_context()
	if value == nil { return }
	allocator := runtime.default_wasm_allocator()
	_ = mem.free(value, allocator)
}
