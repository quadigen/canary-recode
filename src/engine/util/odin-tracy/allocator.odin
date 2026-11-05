#+build !js
package tracy

import "base:runtime"
import "core:c"
import "core:mem"
import "core:sync"

@(private="file")
default_allocator_data: ProfiledAllocatorData

// Call once at startup, before any engine callbacks or workers can run.
InitDefaultAllocator :: proc(callstack_size: i32 = TRACY_CALLSTACK) -> mem.Allocator {
	return MakeProfiledAllocator(&default_allocator_data, callstack_size)
}

// Use when a native callback needs a fresh Odin context.
DefaultContext :: proc "contextless" () -> runtime.Context {
	ctx := runtime.default_context()
	when TRACY_ENABLE {
		if default_allocator_data.profiled_allocator.procedure != nil {
			ctx.allocator = default_allocator_data.profiled_allocator
		}
	}
	return ctx
}

ProfiledAllocatorData :: struct {
	backing_allocator:  mem.Allocator,
	profiled_allocator: mem.Allocator,
	callstack_size:     i32,
	mutex:              sync.Mutex,
}

MakeProfiledAllocator :: proc(
	self: ^ProfiledAllocatorData,
	callstack_size: i32 = TRACY_CALLSTACK,
	secure: b32 = true, // @obsolete
	backing_allocator := context.allocator) -> mem.Allocator {

	when !TRACY_ENABLE {
		return backing_allocator
	}

	self.callstack_size = callstack_size
	self.backing_allocator = backing_allocator
	self.profiled_allocator = mem.Allocator{
		data = self,
		procedure = proc(allocator_data: rawptr, mode: mem.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, location := #caller_location) -> ([]byte, mem.Allocator_Error) {
			self := cast(^ProfiledAllocatorData) allocator_data
			if mode == .Free_All {
				return nil, .Mode_Not_Implemented
			}

			// Keep another thread from reporting a reused address before its free.
			sync.mutex_lock(&self.mutex)
			defer sync.mutex_unlock(&self.mutex)
			new_memory, error := self.backing_allocator.procedure(self.backing_allocator.data, mode, size, alignment, old_memory, old_size, location)
			if error == .None {
				switch mode {
				case .Alloc, .Alloc_Non_Zeroed:
					EmitAlloc(new_memory, self.callstack_size)
				case .Free:
					EmitFree(old_memory, self.callstack_size)
				case .Resize, .Resize_Non_Zeroed:
					EmitFree(old_memory, self.callstack_size)
					EmitAlloc(new_memory, self.callstack_size)
				case .Query_Features:
					if features := cast(^mem.Allocator_Mode_Set)old_memory; features != nil {
						features^ -= {.Free_All}
					}
				case .Free_All, .Query_Info:
				}
			}
			return new_memory, error
		},
	}
	return self.profiled_allocator
}

@(private="file")
EmitAlloc :: #force_inline proc(new_memory: []byte, callstack_size: i32) {
	if len(new_memory) == 0 || raw_data(new_memory) == nil { return }
	Alloc(raw_data(new_memory), c.size_t(len(new_memory)), callstack_size)
}

@(private="file")
EmitFree :: #force_inline proc(old_memory: rawptr, callstack_size: i32) {
	if old_memory == nil { return }
	Free(old_memory, callstack_size)
}


