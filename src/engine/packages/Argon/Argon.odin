package argon

// wire:package name="Argon"

import "core:math"
import "core:strings"
import base_runtime "base:runtime"
import sdl3 "vendor:sdl3"

import kineffi "../../bindings"
import renderer "../../renderer"
import vm "../../vm"

Context :: struct {
	renderer: ^renderer.RendererObject,
	width:    i32,
	height:   i32,
}

table_number :: proc(L: ^vm.State, index: int, name: string, default: f32 = 0) -> f32 {
	type := vm.GetField(L, index, name)
	defer vm.Pop(L)
	if type != .Number && type != .Integer { return default }
	return f32(vm.ArgNumber(L, -1))
}

table_boolean :: proc(L: ^vm.State, index: int, name: string, default := false) -> bool {
	type := vm.GetField(L, index, name)
	defer vm.Pop(L)
	if type != .Boolean { return default }
	return vm.ArgBoolean(L, -1)
}

table_string :: proc(L: ^vm.State, index: int, name: string, default: string = "") -> string {
	type := vm.GetField(L, index, name)
	defer vm.Pop(L)
	if type != .String { return default }
	return vm.ArgString(L, -1)
}

table_color :: proc(L: ^vm.State, index: int, name: string = "Color") -> (r, g, b, a: u8) {
	r, g, b, a = 255, 255, 255, 255
	if vm.GetField(L, index, name) != .Table {
		vm.Pop(L)
		return
	}
	defer vm.Pop(L)
	r = u8(math.round(clamp(table_number(L, -1, "R", 1), 0, 1)*255))
	g = u8(math.round(clamp(table_number(L, -1, "G", 1), 0, 1)*255))
	b = u8(math.round(clamp(table_number(L, -1, "B", 1), 0, 1)*255))
	a = u8(math.round(clamp(table_number(L, -1, "A", 1), 0, 1)*255))
	return
}

function_offset :: proc(L: ^vm.State) -> int {
	return vm.IsTable(L, 1) ? 1 : 0
}

context_from_upvalue :: proc(L: ^vm.State) -> ^Context {
	return cast(^Context)vm.UpvaluePointer(L)
}

surface_from_upvalue :: proc(L: ^vm.State) -> ^kineffi.KineSkiaSurface {
	ctx := context_from_upvalue(L)
	if ctx == nil || ctx.renderer == nil { return nil }
	return ctx.renderer.SkiaSurface
}

set_function :: proc(L: ^vm.State, name: string, function: vm.CFunction, ctx: ^Context) {
	vm.PushLightUserdata(L, ctx)
	vm.PushFunction(L, name, function, 1)
	vm.SetField(L, -2, name)
}

rgba :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	offset := function_offset(L)
	vm.NewTable(L, 0, 4)
	vm.PushNumber(L, vm.ArgNumber(L, 1+offset)/255); vm.SetField(L, -2, "R")
	vm.PushNumber(L, vm.ArgNumber(L, 2+offset)/255); vm.SetField(L, -2, "G")
	vm.PushNumber(L, vm.ArgNumber(L, 3+offset)/255); vm.SetField(L, -2, "B")
	vm.PushNumber(L, vm.ArgOptionalNumber(L, 4+offset, 1)); vm.SetField(L, -2, "A")
	return 1
}

draw_rectangle :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	surface := surface_from_upvalue(L)
	offset := function_offset(L)
	rect := 2+offset
	if surface == nil || !vm.IsTable(L, rect) { return 0 }
	r, g, b, a := table_color(L, rect)
	stroke: f32
	if table_boolean(L, rect, "isOutline") { stroke = 1 }
	kineffi.Kine_Skia_Surface_DrawRect(
		surface,
		table_number(L, rect, "x"), table_number(L, rect, "y"),
		table_number(L, rect, "width"), table_number(L, rect, "height"),
		r, g, b, a, stroke,
	)
	vm.NewTable(L, 0, 0)
	return 1
}

save :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	if surface := surface_from_upvalue(L); surface != nil { kineffi.Kine_Skia_Surface_Save(surface) }
	return 0
}

restore :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	if surface := surface_from_upvalue(L); surface != nil { kineffi.Kine_Skia_Surface_Restore(surface) }
	return 0
}

clip_round_rect :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	surface := surface_from_upvalue(L)
	offset := function_offset(L)
	rect := 2+offset
	if surface == nil || !vm.IsTable(L, rect) { return 0 }
	radius_x := f32(vm.ArgOptionalNumber(L, 3+offset, 0))
	radius_y := f32(vm.ArgOptionalNumber(L, 4+offset, f64(radius_x)))
	kineffi.Kine_Skia_Surface_ClipRoundRect(
		surface,
		table_number(L, rect, "x"), table_number(L, rect, "y"),
		table_number(L, rect, "width"), table_number(L, rect, "height"),
		radius_x, radius_y,
	)
	return 0
}

create_font :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	offset := function_offset(L)
	vm.PushString(L, vm.ArgOptionalString(L, 1+offset, ""))
	return 1
}

measure_text :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	offset := function_offset(L)
	text := vm.ArgString(L, 2+offset)
	size := f32(vm.ArgNumber(L, 3+offset))
	font := vm.ArgOptionalString(L, 4+offset, "")
	c_text := strings.clone_to_cstring(text)
	c_font := strings.clone_to_cstring(font)
	defer delete(c_text)
	defer delete(c_font)
	vm.PushNumber(L, f64(kineffi.Kine_Skia_Surface_MeasureText(c_text, size, c_font)))
	return 1
}

font_line_height :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	offset := function_offset(L)
	size := f32(vm.ArgNumber(L, 1+offset))
	font := vm.ArgOptionalString(L, 2+offset, "")
	c_font := strings.clone_to_cstring(font)
	defer delete(c_font)
	vm.PushNumber(L, f64(kineffi.Kine_Skia_Surface_GetFontLineHeight(size, c_font)))
	return 1
}

font_ascent :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	offset := function_offset(L)
	size := f32(vm.ArgNumber(L, 1+offset))
	font := vm.ArgOptionalString(L, 2+offset, "")
	c_font := strings.clone_to_cstring(font)
	defer delete(c_font)
	vm.PushNumber(L, f64(-kineffi.Kine_Skia_Surface_GetFontAscent(size, c_font)))
	return 1
}

draw_text :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	surface := surface_from_upvalue(L)
	offset := function_offset(L)
	args := 3+offset
	if surface == nil || !vm.IsTable(L, args) { return 0 }
	text := vm.ArgString(L, 2+offset)
	font := table_string(L, args, "Font")
	c_text := strings.clone_to_cstring(text)
	c_font := strings.clone_to_cstring(font)
	defer delete(c_text)
	defer delete(c_font)
	r, g, b, a := table_color(L, args)
	kineffi.Kine_Skia_Surface_DrawText(
		surface, c_text,
		table_number(L, args, "X"), table_number(L, args, "Y"),
		table_number(L, args, "TextSize", 14), c_font,
		r, g, b, a,
	)
	return 0
}

get_window_size :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	ctx := context_from_upvalue(L)
	vm.PushNumber(L, f64(ctx.width))
	vm.PushNumber(L, f64(ctx.height))
	return 2
}

get_mouse_position :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	x, y: f32
	_ = sdl3.GetMouseState(&x, &y)
	vm.NewTable(L, 0, 2)
	vm.PushNumber(L, f64(x)); vm.SetField(L, -2, "X")
	vm.PushNumber(L, f64(y)); vm.SetField(L, -2, "Y")
	return 1
}

mouse_down :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	offset := function_offset(L)
	button := vm.ArgInteger(L, 1+offset)
	buttons := sdl3.GetMouseState(nil, nil)
	down := button == 1 && .LEFT in buttons ||
	        button == 2 && .MIDDLE in buttons ||
	        button == 3 && .RIGHT in buttons
	vm.PushBoolean(L, down)
	return 1
}

mouse_edge :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	vm.PushBoolean(L, false)
	return 1
}

Install :: proc(L: ^vm.State, raw_context: rawptr, renderer_object: ^renderer.RendererObject) {
	ctx := cast(^Context)raw_context
	ctx.renderer = renderer_object
	vm.NewTable(L, 0, 18)
	set_function(L, "RGBA", rgba, ctx)
	set_function(L, "DrawRectangle", draw_rectangle, ctx)
	set_function(L, "Save", save, ctx)
	set_function(L, "Restore", restore, ctx)
	set_function(L, "ClipRoundRect", clip_round_rect, ctx)
	set_function(L, "CreateFont", create_font, ctx)
	set_function(L, "MeasureText", measure_text, ctx)
	set_function(L, "GetFontLineHeight", font_line_height, ctx)
	set_function(L, "GetFontAscent", font_ascent, ctx)
	set_function(L, "DrawText", draw_text, ctx)
	set_function(L, "GetWindowPixelSize", get_window_size, ctx)
	set_function(L, "GetMousePosition", get_mouse_position, ctx)
	set_function(L, "IsMouseButtonDown", mouse_down, ctx)
	set_function(L, "IsMouseButtonPressed", mouse_edge, ctx)
	set_function(L, "IsMouseButtonReleased", mouse_edge, ctx)
	vm.NewTable(L, 0, 3)
	vm.PushInteger(L, 1); vm.SetField(L, -2, "Left")
	vm.PushInteger(L, 2); vm.SetField(L, -2, "Middle")
	vm.PushInteger(L, 3); vm.SetField(L, -2, "Right")
	vm.SetField(L, -2, "MouseButton")
}

Begin_Frame :: proc(raw_context: rawptr, width, height: i32) {
	ctx := cast(^Context)raw_context
	if ctx == nil { return }
	ctx.width = width
	ctx.height = height
}
