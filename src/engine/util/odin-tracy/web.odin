#+build js
package tracy

// The Tracy client (wrapper.odin, bindings.odin, allocator.odin) is native
// only, so this file exists purely to keep tracy call sites compiling in the
// browser, where every one of them does nothing.
//
// It has to mirror wrapper.odin's signatures, not just its names. A previous
// version declared `ZoneNC :: proc(name: string, color: u32) {}`, which is
// enough for a bare `tracy.ZoneNC(...)` statement but not for a call site that
// keeps the ZoneCtx in order to emit a zone value: that needs a return value,
// and `ZoneValue` was missing here entirely, so those call sites failed
// `odin check -target:js_wasm32` with "does not return a value and cannot be
// used as a value" / "'ZoneValue' is not declared by 'tracy'". Keep these in
// step with wrapper.odin.

// Stands in for ___tracy_c_zone_context, which only exists on native.
ZoneCtx :: struct {}

// Mirrors wrapper.odin's TRACY_CALLSTACK default. It only exists to keep the
// signatures identical; on this target the depth argument is never read.
CALLSTACK_DEPTH :: 0

@(deferred_out = ZoneEnd) Zone   :: proc(active := true, depth: i32 = CALLSTACK_DEPTH, loc := #caller_location) -> (ctx: ZoneCtx) { return }
@(deferred_out = ZoneEnd) ZoneN  :: proc(name: string, active := true, depth: i32 = CALLSTACK_DEPTH, loc := #caller_location) -> (ctx: ZoneCtx) { return }
@(deferred_out = ZoneEnd) ZoneC  :: proc(color: u32, active := true, depth: i32 = CALLSTACK_DEPTH, loc := #caller_location) -> (ctx: ZoneCtx) { return }
@(deferred_out = ZoneEnd) ZoneNC :: proc(name: string, color: u32, active := true, depth: i32 = CALLSTACK_DEPTH, loc := #caller_location) -> (ctx: ZoneCtx) { return }

ZoneEnd   :: proc(ctx: ZoneCtx) {}
ZoneValue :: proc(ctx: ZoneCtx, value: u64) {}
ZoneText  :: proc(ctx: ZoneCtx, text: string) {}
ZoneName  :: proc(ctx: ZoneCtx, name: string) {}
ZoneColor :: proc(ctx: ZoneCtx, color: u32) {}

FrameMark    :: proc(name: cstring = nil) {}
SetThreadName :: proc(name: cstring) {}
