package argon

// wire:package name="Argon"

import "core:math"
import "core:strings"
import base_runtime "base:runtime"
import sdl3 "../../platform"

import kineffi "../../bindings"
import renderer "../../renderer"
import vm "../../vm"
import luauh "../../vm/luauh"


DEFAULT_FONT_PATH :: "./src/assets/fonts/Montserrat-Medium.ttf"


Cached_Image :: struct {
	path:      string,
	handle:    ^kineffi.KineSkiaImage,
	lua_ref:   i32,
}

Translation_Layer :: struct {
	name:      string,
	table_ref: i32,
}

Context :: struct {
	renderer: ^renderer.RendererObject,

	width:  i32,
	height: i32,

	mouse_down:     [6]bool,
	mouse_pressed:  [6]bool,
	mouse_released: [6]bool,

	mouse_x:       f32,
	mouse_y:       f32,
	mouse_delta_x: f32,
	mouse_delta_y: f32,
	mouse_wheel:   f32,

	images:       [dynamic]Cached_Image,
	translations: [dynamic]Translation_Layer,

	active_translation: string,

	system_cursors: [11]^sdl3.Cursor,
}


// -----------------------------------------------------------------------------
// Generic helpers
// -----------------------------------------------------------------------------

context_from_upvalue :: proc(L: ^vm.State) -> ^Context {
	return cast(^Context)vm.UpvaluePointer(L)
}

current_surface :: proc(ctx: ^Context) -> ^kineffi.KineSkiaSurface {
	if ctx == nil || ctx.renderer == nil {
		return nil
	}
	return ctx.renderer.SkiaSurface
}

lightuserdata_at :: proc(L: ^vm.State, index: int) -> rawptr {
	if vm.TypeOf(L, index) != .LightUserdata {
		return nil
	}
	return luauh.lua_tolightuserdata(L, i32(index))
}

table_pointer :: proc(
	L: ^vm.State,
	index: int,
	name: string,
) -> rawptr {
	if !vm.IsTable(L, index) {
		return nil
	}

	value_type := vm.GetField(L, index, name)
	defer vm.Pop(L)

	if value_type != .LightUserdata {
		return nil
	}

	return lightuserdata_at(L, -1)
}

table_number :: proc(
	L: ^vm.State,
	index: int,
	name: string,
	default: f32 = 0,
) -> f32 {
	value_type := vm.GetField(L, index, name)
	defer vm.Pop(L)

	if value_type != .Number && value_type != .Integer {
		return default
	}

	return f32(vm.ArgNumber(L, -1))
}

table_boolean :: proc(
	L: ^vm.State,
	index: int,
	name: string,
	default := false,
) -> bool {
	value_type := vm.GetField(L, index, name)
	defer vm.Pop(L)

	if value_type != .Boolean {
		return default
	}

	return vm.ArgBoolean(L, -1)
}

table_string :: proc(
	L: ^vm.State,
	index: int,
	name: string,
	default: string = "",
) -> string {
	value_type := vm.GetField(L, index, name)
	defer vm.Pop(L)

	if value_type != .String {
		return default
	}

	return vm.ArgString(L, -1)
}

table_xy :: proc(
	L: ^vm.State,
	index: int,
) -> (x, y: f32) {
	if !vm.IsTable(L, index) {
		return
	}

	x = table_number(L, index, "X", table_number(L, index, "x", 0))
	y = table_number(L, index, "Y", table_number(L, index, "y", 0))
	return
}

table_color :: proc(
	L: ^vm.State,
	index: int,
	name: string = "Color",
) -> (r, g, b, a: u8) {
	r, g, b, a = 255, 255, 255, 255

	if !vm.IsTable(L, index) {
		return
	}

	if vm.GetField(L, index, name) != .Table {
		vm.Pop(L)
		return
	}
	defer vm.Pop(L)

	r = u8(math.round(
		clamp(table_number(L, -1, "R", 1), 0, 1)*255,
	))
	g = u8(math.round(
		clamp(table_number(L, -1, "G", 1), 0, 1)*255,
	))
	b = u8(math.round(
		clamp(table_number(L, -1, "B", 1), 0, 1)*255,
	))
	a = u8(math.round(
		clamp(table_number(L, -1, "A", 1), 0, 1)*255,
	))
	return
}

push_color_table :: proc(
	L: ^vm.State,
	r, g, b, a: f64,
) {
	vm.NewTable(L, 0, 4)

	vm.PushNumber(L, r)
	vm.SetField(L, -2, "R")

	vm.PushNumber(L, g)
	vm.SetField(L, -2, "G")

	vm.PushNumber(L, b)
	vm.SetField(L, -2, "B")

	vm.PushNumber(L, a)
	vm.SetField(L, -2, "A")
}

push_vector2_table :: proc(
	L: ^vm.State,
	x, y: f32,
) {
	vm.NewTable(L, 0, 2)

	vm.PushNumber(L, f64(x))
	vm.SetField(L, -2, "X")

	vm.PushNumber(L, f64(y))
	vm.SetField(L, -2, "Y")
}

push_rect_table :: proc(
	L: ^vm.State,
	x, y, width, height: f32,
) {
	vm.NewTable(L, 0, 4)

	vm.PushNumber(L, f64(x))
	vm.SetField(L, -2, "x")

	vm.PushNumber(L, f64(y))
	vm.SetField(L, -2, "y")

	vm.PushNumber(L, f64(width))
	vm.SetField(L, -2, "width")

	vm.PushNumber(L, f64(height))
	vm.SetField(L, -2, "height")
}

is_argon_table :: proc(L: ^vm.State, index: int) -> bool {
	if !vm.IsTable(L, index) {
		return false
	}

	value_type := vm.GetField(L, index, "__argon")
	defer vm.Pop(L)

	return value_type == .Boolean && vm.ArgBoolean(L, -1)
}

// Supports both:
//     Argon:Function(...)
// and:
//     Argon.Function(...)
function_offset :: proc(L: ^vm.State) -> int {
	return is_argon_table(L, 1) ? 1 : 0
}

surface_from_argument :: proc(
	L: ^vm.State,
	ctx: ^Context,
	index: int,
) -> ^kineffi.KineSkiaSurface {
	if vm.IsTable(L, index) {
		handle := table_pointer(L, index, "_uihandle")
		if handle != nil {
			return cast(^kineffi.KineSkiaSurface)handle
		}
	}

	// In canary-recode renderer.Window is a lightuserdata RendererObject rather
	// than the original Luau adapter's Window table. Drawing therefore targets
	// the active compositor overlay surface.
	return current_surface(ctx)
}

image_from_argument :: proc(
	L: ^vm.State,
	index: int,
) -> ^kineffi.KineSkiaImage {
	if !vm.IsTable(L, index) {
		return nil
	}
	return cast(^kineffi.KineSkiaImage)table_pointer(L, index, "_handle")
}

shader_from_argument :: proc(
	L: ^vm.State,
	index: int,
) -> ^kineffi.KineSkiaRuntimeShader {
	return cast(^kineffi.KineSkiaRuntimeShader)lightuserdata_at(L, index)
}

font_path_from_argument :: proc(
	L: ^vm.State,
	index: int,
	default: string = "",
) -> string {
	if vm.IsNoneOrNil(L, index) {
		return default
	}

	if vm.IsString(L, index) {
		return vm.ArgString(L, index)
	}

	if vm.IsTable(L, index) {
		path := table_string(L, index, "_path", "")
		if path == "" {
			path = table_string(L, index, "path", "")
		}
		if path == "" {
			path = table_string(L, index, "_handle", "")
		}
		if path != "" {
			return path
		}
	}

	return default
}

set_function :: proc(
	L: ^vm.State,
	name: string,
	function: vm.CFunction,
	ctx: ^Context,
) {
	vm.PushLightUserdata(L, ctx)
	vm.PushFunction(L, name, function, 1)
	vm.SetField(L, -2, name)
}

resolve_asset_path :: proc(path: string) -> (resolved: string, owned: bool) {
	// zembed.AssetPath handled kineasset:// in Canary. The native rewrite does
	// not have zembed, so mirror the common development tree mapping.
	KINE_PREFIX :: "kineasset://"

	if strings.has_prefix(path, KINE_PREFIX) {
		return strings.concatenate({
			"./src/assets/",
			path[len(KINE_PREFIX):],
		}), true
	}

	return path, false
}


// -----------------------------------------------------------------------------
// Colors and vectors
// -----------------------------------------------------------------------------

rgba :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)

	push_color_table(
		L,
		vm.ArgNumber(L, 1+offset)/255,
		vm.ArgNumber(L, 2+offset)/255,
		vm.ArgNumber(L, 3+offset)/255,
		vm.ArgOptionalNumber(L, 4+offset, 1),
	)

	return 1
}

vector3 :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)

	vm.NewTable(L, 0, 3)

	vm.PushNumber(L, vm.ArgNumber(L, 1+offset))
	vm.SetField(L, -2, "X")

	vm.PushNumber(L, vm.ArgNumber(L, 2+offset))
	vm.SetField(L, -2, "Y")

	vm.PushNumber(L, vm.ArgNumber(L, 3+offset))
	vm.SetField(L, -2, "Z")

	return 1
}


// -----------------------------------------------------------------------------
// Images
// -----------------------------------------------------------------------------

find_cached_image :: proc(
	ctx: ^Context,
	path: string,
) -> ^Cached_Image {
	if ctx == nil {
		return nil
	}

	for &entry in ctx.images {
		if entry.path == path {
			return &entry
		}
	}

	return nil
}

push_image_object :: proc(
	L: ^vm.State,
	handle: ^kineffi.KineSkiaImage,
	path: string,
) {
	vm.NewTable(L, 0, 7)

	vm.PushLightUserdata(L, handle)
	vm.SetField(L, -2, "_handle")

	// Canary also held an SDL_Surface in _surface. The native Skia image
	// already owns decoded image state, so there is no parallel SDL surface.
	vm.PushNil(L)
	vm.SetField(L, -2, "_surface")

	vm.PushNumber(
		L,
		f64(kineffi.Kine_Skia_Image_GetWidth(handle)),
	)
	vm.SetField(L, -2, "width")

	vm.PushNumber(
		L,
		f64(kineffi.Kine_Skia_Image_GetHeight(handle)),
	)
	vm.SetField(L, -2, "height")

	// These fields existed on the Canary typedef. Native KineSkiaImage does not
	// expose decoded pixels directly.
	vm.PushNil(L)
	vm.SetField(L, -2, "pixels")

	vm.PushNumber(L, 0)
	vm.SetField(L, -2, "pitch")

	vm.PushString(L, path)
	vm.SetField(L, -2, "_path")
}

create_image_from_path :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	path := vm.ArgString(L, 1+offset)
	resolved, resolved_owned := resolve_asset_path(path)
	if resolved_owned {
		defer delete(resolved)
	}

	if cached := find_cached_image(ctx, resolved); cached != nil {
		if cached.lua_ref > 0 {
			vm.PushRegistryReference(L, cached.lua_ref)
			return 1
		}
	}

	c_path := strings.clone_to_cstring(resolved)
	defer delete(c_path)

	handle := kineffi.Kine_Skia_Image_LoadFromFile(c_path)
	if handle == nil {
		vm.PushNil(L)
		return 1
	}

	push_image_object(L, handle, resolved)

	lua_ref := vm.RetainValue(L)

	append(
		&ctx.images,
		Cached_Image{
			path    = strings.clone(resolved),
			handle  = handle,
			lua_ref = lua_ref,
		},
	)

	return 1
}

create_image_from_memory :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)

	data := vm.ArgString(L, 1+offset)
	if len(data) == 0 {
		vm.PushNil(L)
		return 1
	}

	handle := kineffi.Kine_Skia_Image_LoadFromMemory(
		cast(^u8)raw_data(data),
		uintptr(len(data)),
	)

	if handle == nil {
		vm.PushNil(L)
		return 1
	}

	push_image_object(L, handle, "<memory>")
	return 1
}

draw_image_sized :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	image := image_from_argument(L, 2+offset)
	rect_index := 3+offset

	if surface == nil || image == nil || !vm.IsTable(L, rect_index) {
		return 0
	}

	alpha := clamp(
		f32(vm.ArgOptionalNumber(L, 4+offset, 1)),
		0,
		1,
	)

	kineffi.Kine_Skia_Surface_DrawImageSized(
		surface,
		image,
		table_number(L, rect_index, "x"),
		table_number(L, rect_index, "y"),
		table_number(L, rect_index, "width"),
		table_number(L, rect_index, "height"),
		u8(math.round(alpha*255)),
	)

	return 0
}

draw_image_rect :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	image := image_from_argument(L, 2+offset)
	source_index := 3+offset
	destination_index := 4+offset

	if surface == nil ||
	   image == nil ||
	   !vm.IsTable(L, source_index) ||
	   !vm.IsTable(L, destination_index) {
		return 0
	}

	alpha := clamp(
		f32(vm.ArgOptionalNumber(L, 5+offset, 1)),
		0,
		1,
	)

	kineffi.Kine_Skia_Surface_DrawImageRect(
		surface,
		image,

		table_number(L, source_index, "x"),
		table_number(L, source_index, "y"),
		table_number(L, source_index, "width"),
		table_number(L, source_index, "height"),

		table_number(L, destination_index, "x"),
		table_number(L, destination_index, "y"),
		table_number(L, destination_index, "width"),
		table_number(L, destination_index, "height"),

		u8(math.round(alpha*255)),
	)

	return 0
}

draw_image_outline_sized :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	image := image_from_argument(L, 2+offset)
	rect_index := 3+offset
	color_index := 4+offset

	if surface == nil ||
	   image == nil ||
	   !vm.IsTable(L, rect_index) ||
	   !vm.IsTable(L, color_index) {
		return 0
	}

	r, g, b, a := table_color_direct(L, color_index)

	thickness := f32(vm.ArgNumber(L, 5+offset))
	alpha := clamp(
		f32(vm.ArgOptionalNumber(L, 6+offset, 1)),
		0,
		1,
	)

	kineffi.Kine_Skia_Surface_DrawImageOutlineSized(
		surface,
		image,

		table_number(L, rect_index, "x"),
		table_number(L, rect_index, "y"),
		table_number(L, rect_index, "width"),
		table_number(L, rect_index, "height"),

		thickness,

		r, g, b, a,
		u8(math.round(alpha*255)),
	)

	return 0
}

table_color_direct :: proc(
	L: ^vm.State,
	index: int,
) -> (r, g, b, a: u8) {
	r = u8(math.round(clamp(table_number(L, index, "R", 1), 0, 1)*255))
	g = u8(math.round(clamp(table_number(L, index, "G", 1), 0, 1)*255))
	b = u8(math.round(clamp(table_number(L, index, "B", 1), 0, 1)*255))
	a = u8(math.round(clamp(table_number(L, index, "A", 1), 0, 1)*255))
	return
}


// -----------------------------------------------------------------------------
// Primitive drawing
// -----------------------------------------------------------------------------

draw_rectangle :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	rect := 2+offset

	if surface == nil || !vm.IsTable(L, rect) {
		return 0
	}

	r, g, b, a := table_color(L, rect)

	stroke: f32 = 0
	if table_boolean(L, rect, "isOutline") {
		// Matches Canary SkiaAdapter:DrawRect.
		stroke = 2
	}

	kineffi.Kine_Skia_Surface_DrawRect(
		surface,

		table_number(L, rect, "x"),
		table_number(L, rect, "y"),
		table_number(L, rect, "width"),
		table_number(L, rect, "height"),

		r, g, b, a,
		stroke,
	)

	// Canary returns a small interaction helper object. None of the current
	// Kinemium code relies on its Hovered callback, but preserve the object
	// return shape.
	vm.NewTable(L, 0, 0)
	return 1
}

draw_rotated_rectangle :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	rect := 2+offset

	if surface == nil || !vm.IsTable(L, rect) {
		return 0
	}

	r, g, b, a := table_color(L, rect)

	stroke: f32 = 0
	if table_boolean(L, rect, "isOutline") {
		stroke = 2
	}

	kineffi.Kine_Skia_Surface_DrawRotatedRect(
		surface,

		table_number(L, rect, "x"),
		table_number(L, rect, "y"),
		table_number(L, rect, "width"),
		table_number(L, rect, "height"),

		f32(vm.ArgNumber(L, 3+offset)),

		r, g, b, a,
		stroke,
	)

	return 0
}

draw_round_rectangle :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	rect := 2+offset

	if surface == nil || !vm.IsTable(L, rect) {
		return 0
	}

	radius_x := f32(vm.ArgNumber(L, 3+offset))
	radius_y := f32(vm.ArgNumber(L, 4+offset))

	stroke := f32(vm.ArgOptionalNumber(
		L,
		5+offset,
		table_boolean(L, rect, "isOutline") ? 1 : 0,
	))

	r, g, b, a := table_color(L, rect)

	kineffi.Kine_Skia_Surface_DrawRoundRect(
		surface,

		table_number(L, rect, "x"),
		table_number(L, rect, "y"),
		table_number(L, rect, "width"),
		table_number(L, rect, "height"),

		radius_x,
		radius_y,

		r, g, b, a,
		stroke,
	)

	return 0
}

draw_squircle :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	rect := 2+offset

	if surface == nil || !vm.IsTable(L, rect) {
		return 0
	}

	radius := f32(vm.ArgNumber(L, 3+offset))
	exponent := f32(vm.ArgNumber(L, 4+offset))

	stroke := f32(vm.ArgOptionalNumber(
		L,
		5+offset,
		table_boolean(L, rect, "isOutline") ? 1 : 0,
	))

	r, g, b, a := table_color(L, rect)

	kineffi.Kine_Skia_Surface_DrawSquircle(
		surface,

		table_number(L, rect, "x"),
		table_number(L, rect, "y"),
		table_number(L, rect, "width"),
		table_number(L, rect, "height"),

		radius,
		exponent,

		r, g, b, a,
		stroke,
	)

	return 0
}

draw_circle :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	center_index := 2+offset
	radius := f32(vm.ArgNumber(L, 3+offset))
	color_index := 4+offset

	if surface == nil ||
	   !vm.IsTable(L, center_index) ||
	   !vm.IsTable(L, color_index) {
		return 0
	}

	x, y := table_xy(L, center_index)
	r, g, b, a := table_color_direct(L, color_index)

	kineffi.Kine_Skia_Surface_DrawCircle(
		surface,
		x, y,
		radius,
		r, g, b, a,
		f32(vm.ArgOptionalNumber(L, 5+offset, 0)),
	)

	return 0
}

draw_line :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	from_index := 2+offset
	to_index := 3+offset
	color_index := 5+offset

	if surface == nil ||
	   !vm.IsTable(L, from_index) ||
	   !vm.IsTable(L, to_index) ||
	   !vm.IsTable(L, color_index) {
		return 0
	}

	x0, y0 := table_xy(L, from_index)
	x1, y1 := table_xy(L, to_index)
	r, g, b, a := table_color_direct(L, color_index)

	kineffi.Kine_Skia_Surface_DrawLine(
		surface,
		x0, y0,
		x1, y1,
		f32(vm.ArgNumber(L, 4+offset)),
		r, g, b, a,
	)

	return 0
}

draw_polygon :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	points_index := 2+offset
	color_index := 4+offset

	if surface == nil ||
	   !vm.IsTable(L, points_index) ||
	   !vm.IsTable(L, color_index) {
		return 0
	}

	point_count := vm.RawLen(L, points_index)
	if point_count < 2 {
		return 0
	}

	points := make([]f32, point_count*2)
	defer delete(points)

	for i in 0 ..< point_count {
		if vm.RawGetIndex(L, points_index, i+1) != .Table {
			vm.Pop(L)
			return 0
		}

		x, y := table_xy(L, -1)
		vm.Pop(L)

		points[i*2] = x
		points[i*2+1] = y
	}

	r, g, b, a := table_color_direct(L, color_index)

	kineffi.Kine_Skia_Surface_DrawPolygon(
		surface,
		cast(^f32)raw_data(points),
		i32(point_count),
		vm.ArgBoolean(L, 3+offset) ? 1 : 0,
		r, g, b, a,
		f32(vm.ArgOptionalNumber(L, 5+offset, 0)),
	)

	return 0
}

draw_ui_shadow :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	rect := 2+offset
	offset_index := 5+offset

	if surface == nil ||
	   !vm.IsTable(L, rect) ||
	   !vm.IsTable(L, offset_index) {
		return 0
	}

	r, g, b, a := table_color(L, rect)
	offset_x, offset_y := table_xy(L, offset_index)

	kineffi.Kine_Skia_Surface_DrawUIShadow(
		surface,

		table_number(L, rect, "x"),
		table_number(L, rect, "y"),
		table_number(L, rect, "width"),
		table_number(L, rect, "height"),

		f32(vm.ArgNumber(L, 3+offset)),
		f32(vm.ArgNumber(L, 4+offset)),

		offset_x,
		offset_y,

		f32(vm.ArgNumber(L, 6+offset)),
		f32(vm.ArgNumber(L, 7+offset)),

		r, g, b, a,
	)

	return 0
}

draw_backdrop_blur :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	rect := 2+offset

	if surface == nil || !vm.IsTable(L, rect) {
		return 0
	}

	radius_x := f32(vm.ArgOptionalNumber(L, 4+offset, 0))
	radius_y := f32(vm.ArgOptionalNumber(L, 5+offset, f64(radius_x)))

	tint_r, tint_g, tint_b, tint_a: u8
	if vm.IsTable(L, 6+offset) {
		tint_r, tint_g, tint_b, tint_a =
			table_color_direct(L, 6+offset)
	}

	alpha := u8(math.round(
		clamp(table_number(L, rect, "alpha", 1), 0, 1)*255,
	))

	kineffi.Kine_Skia_Surface_DrawBackdropBlurRect(
		surface,

		table_number(L, rect, "x"),
		table_number(L, rect, "y"),
		table_number(L, rect, "width"),
		table_number(L, rect, "height"),

		radius_x,
		radius_y,
		f32(vm.ArgNumber(L, 3+offset)),

		alpha,

		tint_r,
		tint_g,
		tint_b,
		tint_a,
	)

	return 0
}

draw_backdrop_blur_squircle :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	rect := 2+offset

	if surface == nil || !vm.IsTable(L, rect) {
		return 0
	}

	tint_r, tint_g, tint_b, tint_a: u8
	if vm.IsTable(L, 6+offset) {
		tint_r, tint_g, tint_b, tint_a =
			table_color_direct(L, 6+offset)
	}

	alpha := u8(math.round(
		clamp(table_number(L, rect, "alpha", 1), 0, 1)*255,
	))

	kineffi.Kine_Skia_Surface_DrawBackdropBlurSquircle(
		surface,

		table_number(L, rect, "x"),
		table_number(L, rect, "y"),
		table_number(L, rect, "width"),
		table_number(L, rect, "height"),

		f32(vm.ArgNumber(L, 4+offset)),
		f32(vm.ArgNumber(L, 5+offset)),
		f32(vm.ArgNumber(L, 3+offset)),

		alpha,

		tint_r,
		tint_g,
		tint_b,
		tint_a,
	)

	return 0
}


// -----------------------------------------------------------------------------
// Transform stack / clipping / surfaces
// -----------------------------------------------------------------------------

save :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)
	surface := surface_from_argument(L, ctx, 1+offset)

	if surface != nil {
		kineffi.Kine_Skia_Surface_Save(surface)
	}

	return 0
}

restore :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)
	surface := surface_from_argument(L, ctx, 1+offset)

	if surface != nil {
		kineffi.Kine_Skia_Surface_Restore(surface)
	}

	return 0
}

clip_round_rect :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	rect := 2+offset

	if surface == nil || !vm.IsTable(L, rect) {
		return 0
	}

	radius_x := f32(vm.ArgOptionalNumber(L, 3+offset, 0))
	radius_y := f32(vm.ArgOptionalNumber(
		L,
		4+offset,
		f64(radius_x),
	))

	kineffi.Kine_Skia_Surface_ClipRoundRect(
		surface,

		table_number(L, rect, "x"),
		table_number(L, rect, "y"),
		table_number(L, rect, "width"),
		table_number(L, rect, "height"),

		radius_x,
		radius_y,
	)

	return 0
}

clip_squircle :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	rect := 2+offset

	if surface == nil || !vm.IsTable(L, rect) {
		return 0
	}

	kineffi.Kine_Skia_Surface_ClipSquircle(
		surface,

		table_number(L, rect, "x"),
		table_number(L, rect, "y"),
		table_number(L, rect, "width"),
		table_number(L, rect, "height"),

		f32(vm.ArgNumber(L, 3+offset)),
		f32(vm.ArgNumber(L, 4+offset)),
	)

	return 0
}

clear_2d :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	color_index := 2+offset

	if surface == nil || !vm.IsTable(L, color_index) {
		return 0
	}

	r, g, b, a := table_color_direct(L, color_index)

	kineffi.Kine_Skia_Surface_Clear(
		surface,
		r, g, b, a,
	)

	return 0
}

create_skia_surface :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)

	width := i32(vm.ArgNumber(L, 1+offset))
	height := i32(vm.ArgNumber(L, 2+offset))

	if width <= 0 || height <= 0 {
		vm.PushNil(L)
		return 1
	}

	surface := kineffi.Kine_Skia_Surface_Create(width, height)
	if surface == nil {
		vm.PushNil(L)
		return 1
	}

	vm.NewTable(L, 0, 3)

	vm.PushLightUserdata(L, surface)
	vm.SetField(L, -2, "_uihandle")

	vm.PushNumber(L, f64(width))
	vm.SetField(L, -2, "width")

	vm.PushNumber(L, f64(height))
	vm.SetField(L, -2, "height")

	return 1
}

destroy_skia_surface :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)
	surface_index := 1+offset

	if !vm.IsTable(L, surface_index) {
		return 0
	}

	surface := cast(^kineffi.KineSkiaSurface)table_pointer(
		L,
		surface_index,
		"_uihandle",
	)

	if surface != nil {
		kineffi.Kine_Skia_Surface_Destroy(surface)

		vm.PushNil(L)
		vm.SetField(L, surface_index, "_uihandle")
	}

	return 0
}

get_surface_pixel :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	if surface == nil {
		push_color_table(L, 0, 0, 0, 0)
		return 1
	}

	r, g, b, a: u8

	kineffi.Kine_Skia_Surface_GetPixel(
		surface,
		i32(vm.ArgNumber(L, 2+offset)),
		i32(vm.ArgNumber(L, 3+offset)),
		&r, &g, &b, &a,
	)

	push_color_table(
		L,
		f64(r)/255,
		f64(g)/255,
		f64(b)/255,
		f64(a)/255,
	)

	return 1
}

get_surface_pixels :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)

	if surface == nil {
		vm.PushNil(L)
		vm.PushNumber(L, 0)
		return 2
	}

	kineffi.Kine_Skia_Surface_Flush(surface)

	pixels := kineffi.Kine_Skia_Surface_GetPixels(surface)
	pitch := kineffi.Kine_Skia_Surface_GetRowBytes(surface)

	if pixels == nil {
		vm.PushNil(L)
	} else {
		vm.PushLightUserdata(L, pixels)
	}

	vm.PushNumber(L, f64(pitch))
	return 2
}

draw_pixels :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	pixels := lightuserdata_at(L, 2+offset)
	rect_index := 6+offset

	if surface == nil ||
	   pixels == nil ||
	   !vm.IsTable(L, rect_index) {
		return 0
	}

	kineffi.Kine_Skia_Surface_DrawPixels(
		surface,
		pixels,

		i32(vm.ArgNumber(L, 3+offset)),
		i32(vm.ArgNumber(L, 4+offset)),
		u32(vm.ArgNumber(L, 5+offset)),

		table_number(L, rect_index, "x"),
		table_number(L, rect_index, "y"),
		table_number(L, rect_index, "width"),
		table_number(L, rect_index, "height"),

		vm.ArgOptionalBoolean(L, 7+offset, false) ? 1 : 0,

		u8(math.round(
			clamp(
				f32(vm.ArgOptionalNumber(L, 8+offset, 1)),
				0, 1,
			)*255,
		)),
	)

	return 0
}


// -----------------------------------------------------------------------------
// Runtime shaders
// -----------------------------------------------------------------------------

create_runtime_shader :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)

	source := vm.ArgString(L, 1+offset)
	c_source := strings.clone_to_cstring(source)
	defer delete(c_source)

	shader := kineffi.Kine_Skia_RuntimeShader_Create(c_source)

	if shader == nil {
		vm.PushNil(L)

		error_message := kineffi.Kine_Skia_RuntimeShader_GetLastError()
		if error_message != nil {
			vm.PushString(L, string(error_message))
		} else {
			vm.PushString(L, "failed to create runtime shader")
		}

		return 2
	}

	vm.PushLightUserdata(L, shader)
	return 1
}

destroy_runtime_shader :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)
	shader := shader_from_argument(L, 1+offset)

	if shader != nil {
		kineffi.Kine_Skia_RuntimeShader_Destroy(shader)
	}

	return 0
}

set_runtime_shader_uniform :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)

	shader := shader_from_argument(L, 1+offset)
	if shader == nil {
		vm.PushBoolean(L, false)
		return 1
	}

	name := vm.ArgString(L, 2+offset)
	values_index := 3+offset

	if !vm.IsTable(L, values_index) {
		vm.PushBoolean(L, false)
		return 1
	}

	count := vm.RawLen(L, values_index)
	if count <= 0 {
		vm.PushBoolean(L, false)
		return 1
	}

	values := make([]f32, count)
	defer delete(values)

	for i in 0 ..< count {
		_ = vm.RawGetIndex(L, values_index, i+1)

		if !vm.IsNumber(L, -1) {
			vm.Pop(L)
			vm.PushBoolean(L, false)
			return 1
		}

		values[i] = f32(vm.ArgNumber(L, -1))
		vm.Pop(L)
	}

	c_name := strings.clone_to_cstring(name)
	defer delete(c_name)

	success := kineffi.Kine_Skia_RuntimeShader_SetUniform(
		shader,
		c_name,
		cast(^f32)raw_data(values),
		i32(count),
	) != 0

	vm.PushBoolean(L, success)
	return 1
}

draw_runtime_shader_rectangle :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	shader := shader_from_argument(L, 2+offset)
	rect_index := 3+offset

	if surface == nil ||
	   shader == nil ||
	   !vm.IsTable(L, rect_index) {
		return 0
	}

	kineffi.Kine_Skia_Surface_DrawRuntimeShaderRect(
		surface,
		shader,

		table_number(L, rect_index, "x"),
		table_number(L, rect_index, "y"),
		table_number(L, rect_index, "width"),
		table_number(L, rect_index, "height"),
	)

	return 0
}


// -----------------------------------------------------------------------------
// Fonts / text / translations
// -----------------------------------------------------------------------------

create_font :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)
	path := vm.ArgOptionalString(L, 1+offset, DEFAULT_FONT_PATH)

	resolved, resolved_owned := resolve_asset_path(path)
	if resolved_owned {
		defer delete(resolved)
	}

	// Match Canary typedefs.Font:
	//     { _handle = path, _path = path }
	vm.NewTable(L, 0, 2)

	vm.PushString(L, resolved)
	vm.SetField(L, -2, "_handle")

	vm.PushString(L, resolved)
	vm.SetField(L, -2, "_path")

	return 1
}

find_translation_layer :: proc(
	ctx: ^Context,
	name: string,
) -> ^Translation_Layer {
	if ctx == nil {
		return nil
	}

	for &layer in ctx.translations {
		if layer.name == name {
			return &layer
		}
	}

	return nil
}

translated_text :: proc(
	L: ^vm.State,
	ctx: ^Context,
	source: string,
) -> (text: string, owned: bool) {
	if ctx == nil || ctx.active_translation == "" {
		return source, false
	}

	layer := find_translation_layer(
		ctx,
		ctx.active_translation,
	)

	if layer == nil || layer.table_ref <= 0 {
		return source, false
	}

	vm.PushRegistryReference(L, layer.table_ref)
	defer vm.Pop(L)

	value_type := vm.GetField(L, -1, source)
	defer vm.Pop(L)

	if value_type != .String {
		return source, false
	}

	return strings.clone(vm.ArgString(L, -1)), true
}

create_translation_layer :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	name := vm.ArgString(L, 1+offset)
	table_index := 2+offset

	if !vm.IsTable(L, table_index) {
		return vm.RaiseError(
			L,
			"CreateTranslationLayer expects a phrase map table",
		)
	}

	layer := find_translation_layer(ctx, name)

	if layer == nil {
		append(
			&ctx.translations,
			Translation_Layer{
				name = strings.clone(name),
			},
		)
		layer = &ctx.translations[len(ctx.translations)-1]
	} else if layer.table_ref > 0 {
		vm.ReleaseValue(L, layer.table_ref)
		layer.table_ref = -1
	}

	vm.PushValue(L, table_index)
	layer.table_ref = vm.RetainValue(L)
	vm.Pop(L)

	if ctx.active_translation != "" {
		delete(ctx.active_translation)
	}
	ctx.active_translation = strings.clone(name)

	return 0
}

set_active_translation_layer :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	name := vm.ArgString(L, 1+offset)

	if ctx.active_translation != "" {
		delete(ctx.active_translation)
	}

	ctx.active_translation = strings.clone(name)
	return 0
}

measure_text :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	text := vm.ArgString(L, 2+offset)
	mapped, mapped_owned := translated_text(L, ctx, text)
	if mapped_owned {
		defer delete(mapped)
	}

	size := f32(vm.ArgNumber(L, 3+offset))
	font := font_path_from_argument(
		L,
		4+offset,
		DEFAULT_FONT_PATH,
	)

	c_text := strings.clone_to_cstring(mapped)
	c_font := strings.clone_to_cstring(font)
	defer delete(c_text)
	defer delete(c_font)

	vm.PushNumber(
		L,
		f64(kineffi.Kine_Skia_Surface_MeasureText(
			c_text,
			size,
			c_font,
		)),
	)

	return 1
}

font_line_height :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)

	size := f32(vm.ArgNumber(L, 1+offset))
	font := font_path_from_argument(
		L,
		2+offset,
		DEFAULT_FONT_PATH,
	)

	c_font := strings.clone_to_cstring(font)
	defer delete(c_font)

	vm.PushNumber(
		L,
		f64(kineffi.Kine_Skia_Surface_GetFontLineHeight(
			size,
			c_font,
		)),
	)

	return 1
}

font_ascent :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)

	size := f32(vm.ArgNumber(L, 1+offset))
	font := font_path_from_argument(
		L,
		2+offset,
		DEFAULT_FONT_PATH,
	)

	c_font := strings.clone_to_cstring(font)
	defer delete(c_font)

	// Canary returned the native ascent directly. It is normally negative.
	vm.PushNumber(
		L,
		f64(kineffi.Kine_Skia_Surface_GetFontAscent(
			size,
			c_font,
		)),
	)

	return 1
}

draw_text :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	args := 3+offset

	if surface == nil || !vm.IsTable(L, args) {
		return 0
	}

	text := vm.ArgString(L, 2+offset)
	mapped, mapped_owned := translated_text(L, ctx, text)
	if mapped_owned {
		defer delete(mapped)
	}

	font := font_path_from_field(
		L,
		args,
		"Font",
		DEFAULT_FONT_PATH,
	)

	c_text := strings.clone_to_cstring(mapped)
	c_font := strings.clone_to_cstring(font)
	defer delete(c_text)
	defer delete(c_font)

	r, g, b, a := table_color(L, args)

	kineffi.Kine_Skia_Surface_DrawText(
		surface,
		c_text,

		table_number(L, args, "X"),
		table_number(L, args, "Y"),
		table_number(L, args, "TextSize", 14),

		c_font,

		r, g, b, a,
	)

	return 0
}

font_path_from_field :: proc(
	L: ^vm.State,
	table_index: int,
	name: string,
	default: string,
) -> string {
	value_type := vm.GetField(L, table_index, name)
	defer vm.Pop(L)

	if value_type == .String {
		return vm.ArgString(L, -1)
	}

	if value_type == .Table {
		return font_path_from_argument(L, -1, default)
	}

	return default
}

draw_text_shadow :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	surface := surface_from_argument(L, ctx, 1+offset)
	args := 3+offset
	shadow_offset_index := 4+offset
	color_index := 7+offset

	if surface == nil ||
	   !vm.IsTable(L, args) ||
	   !vm.IsTable(L, shadow_offset_index) ||
	   !vm.IsTable(L, color_index) {
		return 0
	}

	text := vm.ArgString(L, 2+offset)
	mapped, mapped_owned := translated_text(L, ctx, text)
	if mapped_owned {
		defer delete(mapped)
	}

	font := font_path_from_field(
		L,
		args,
		"Font",
		DEFAULT_FONT_PATH,
	)

	offset_x, offset_y := table_xy(
		L,
		shadow_offset_index,
	)

	r, g, b, a := table_color_direct(
		L,
		color_index,
	)

	c_text := strings.clone_to_cstring(mapped)
	c_font := strings.clone_to_cstring(font)
	defer delete(c_text)
	defer delete(c_font)

	kineffi.Kine_Skia_Surface_DrawTextShadow(
		surface,
		c_text,

		table_number(L, args, "X"),
		table_number(L, args, "Y"),
		table_number(L, args, "TextSize", 14),

		c_font,

		offset_x,
		offset_y,

		f32(vm.ArgNumber(L, 5+offset)),
		f32(vm.ArgNumber(L, 6+offset)),

		r, g, b, a,
	)

	return 0
}


// -----------------------------------------------------------------------------
// Window / system
// -----------------------------------------------------------------------------

get_window_size :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)

	if ctx == nil {
		vm.PushNil(L)
		vm.PushNil(L)
		return 2
	}

	vm.PushNumber(L, f64(ctx.width))
	vm.PushNumber(L, f64(ctx.height))
	return 2
}

get_render_width :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	vm.PushNumber(L, ctx != nil ? f64(ctx.width) : 0)
	return 1
}

get_render_height :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	vm.PushNumber(L, ctx != nil ? f64(ctx.height) : 0)
	return 1
}

focused_window :: proc() -> ^sdl3.Window {
	window := sdl3.GetKeyboardFocus()
	if window != nil {
		return window
	}
	return sdl3.GetMouseFocus()
}

get_dpi_scale :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	window := focused_window()
	if window == nil {
		vm.PushNumber(L, 1)
		return 1
	}

	vm.PushNumber(
		L,
		f64(sdl3.GetWindowDisplayScale(window)),
	)

	return 1
}

get_system_theme :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	#partial switch sdl3.GetSystemTheme() {
	case .LIGHT:
		vm.PushString(L, "light")
	case .DARK:
		vm.PushString(L, "dark")
	case:
		vm.PushString(L, "unknown")
	}

	return 1
}

is_window_focused :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	vm.PushBoolean(L, sdl3.GetKeyboardFocus() != nil)
	return 1
}


// -----------------------------------------------------------------------------
// Input
// -----------------------------------------------------------------------------

mouse_button_down :: proc(button: int) -> bool {
	buttons := sdl3.GetMouseState(nil, nil)

	switch button {
	case 1:
		return .LEFT in buttons
	case 2:
		return .MIDDLE in buttons
	case 3:
		return .RIGHT in buttons
	case 4:
		return .X1 in buttons
	case 5:
		return .X2 in buttons
	}

	return false
}

get_mouse_position :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	x, y: f32
	_ = sdl3.GetMouseState(&x, &y)

	push_vector2_table(L, x, y)
	return 1
}

mouse_down :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)
	button := int(vm.ArgInteger(L, 1+offset))

	vm.PushBoolean(
		L,
		button >= 1 &&
		button <= 5 &&
		mouse_button_down(button),
	)

	return 1
}

mouse_pressed :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)
	button := int(vm.ArgInteger(L, 1+offset))

	pressed := false
	if ctx != nil && button >= 1 && button <= 5 {
		pressed = ctx.mouse_pressed[button]
	}

	vm.PushBoolean(L, pressed)
	return 1
}

mouse_released :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)
	button := int(vm.ArgInteger(L, 1+offset))

	released := false
	if ctx != nil && button >= 1 && button <= 5 {
		released = ctx.mouse_released[button]
	}

	vm.PushBoolean(L, released)
	return 1
}

get_mouse_delta :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)

	if ctx == nil {
		vm.NewTable(L, 0, 2)
		vm.PushNumber(L, 0)
		vm.SetField(L, -2, "x")
		vm.PushNumber(L, 0)
		vm.SetField(L, -2, "y")
		return 1
	}

	vm.NewTable(L, 0, 2)

	vm.PushNumber(L, f64(ctx.mouse_delta_x))
	vm.SetField(L, -2, "x")

	vm.PushNumber(L, f64(ctx.mouse_delta_y))
	vm.SetField(L, -2, "y")

	return 1
}

get_mouse_wheel_move :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)

	// Package Begin_Frame currently receives no SDL events, so this remains
	// zero until Package_On_Event is added to the package registry.
	vm.PushNumber(
		L,
		ctx != nil ? f64(ctx.mouse_wheel) : 0,
	)

	return 1
}

is_key_down :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)
	key := int(vm.ArgInteger(L, 1+offset))

	count: i32
	state := sdl3.GetKeyboardState(&count)

	down := false

	if state != nil &&
	   key >= 0 &&
	   key < int(count) {
		down = state[key]
	}

	vm.PushBoolean(L, down)
	return 1
}

disable_cursor :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	window := focused_window()
	if window != nil {
		_ = sdl3.SetWindowRelativeMouseMode(
			window,
			true,
		)
	}

	return 0
}

enable_cursor :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	window := focused_window()
	if window != nil {
		_ = sdl3.SetWindowRelativeMouseMode(
			window,
			false,
		)
	}

	return 0
}

show_cursor :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	_ = sdl3.ShowCursor()
	return 0
}

hide_cursor :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	_ = sdl3.HideCursor()
	return 0
}

set_mouse_position :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)

	window := focused_window()
	if window != nil {
		sdl3.WarpMouseInWindow(
			window,
			f32(vm.ArgNumber(L, 1+offset)),
			f32(vm.ArgNumber(L, 2+offset)),
		)
	}

	return 0
}

cursor_type_from_argon :: proc(
	value: int,
) -> sdl3.SystemCursor {
	switch value {
	case 2:
		return .TEXT
	case 3:
		return .CROSSHAIR
	case 4:
		return .POINTER
	case 5:
		return .EW_RESIZE
	case 6:
		return .NS_RESIZE
	case 7:
		return .NWSE_RESIZE
	case 8:
		return .NESW_RESIZE
	case 9:
		return .MOVE
	case 10:
		return .NOT_ALLOWED
	}

	return .DEFAULT
}

set_mouse_cursor :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	ctx := context_from_upvalue(L)
	offset := function_offset(L)

	value := clamp(
		int(vm.ArgInteger(L, 1+offset)),
		0,
		10,
	)

	if ctx == nil {
		return 0
	}

	if ctx.system_cursors[value] == nil {
		ctx.system_cursors[value] =
			sdl3.CreateSystemCursor(
				cursor_type_from_argon(value),
			)
	}

	if ctx.system_cursors[value] != nil {
		_ = sdl3.SetCursor(
			ctx.system_cursors[value],
		)
	}

	return 0
}

start_text_input :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	window := focused_window()
	if window == nil {
		vm.PushBoolean(L, false)
		return 1
	}

	vm.PushBoolean(
		L,
		sdl3.StartTextInput(window),
	)
	return 1
}

stop_text_input :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	window := focused_window()
	if window == nil {
		vm.PushBoolean(L, false)
		return 1
	}

	vm.PushBoolean(
		L,
		sdl3.StopTextInput(window),
	)
	return 1
}


// -----------------------------------------------------------------------------
// Clipboard
// -----------------------------------------------------------------------------

set_clipboard :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	offset := function_offset(L)

	text := vm.ArgString(L, 1+offset)
	c_text := strings.clone_to_cstring(text)
	defer delete(c_text)

	vm.PushBoolean(
		L,
		sdl3.SetClipboardText(c_text),
	)

	return 1
}

get_clipboard :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	value := sdl3.GetClipboardText()

	if value == nil {
		vm.PushString(L, "")
		return 1
	}

	length := int(sdl3.strlen(cast(cstring)value))
	text := strings.string_from_ptr(
		cast(^u8)value,
		length,
	)

	vm.PushString(L, text)
	sdl3.free(cast(rawptr)value)

	return 1
}


// -----------------------------------------------------------------------------
// Installation
// -----------------------------------------------------------------------------

install_key_table :: proc(L: ^vm.State) {
	vm.NewTable(L, 0, 48)

	vm.PushInteger(L, 4);  vm.SetField(L, -2, "A")
	vm.PushInteger(L, 5);  vm.SetField(L, -2, "B")
	vm.PushInteger(L, 6);  vm.SetField(L, -2, "C")
	vm.PushInteger(L, 7);  vm.SetField(L, -2, "D")
	vm.PushInteger(L, 8);  vm.SetField(L, -2, "E")
	vm.PushInteger(L, 9);  vm.SetField(L, -2, "F")
	vm.PushInteger(L, 10); vm.SetField(L, -2, "G")
	vm.PushInteger(L, 11); vm.SetField(L, -2, "H")
	vm.PushInteger(L, 12); vm.SetField(L, -2, "I")
	vm.PushInteger(L, 13); vm.SetField(L, -2, "J")
	vm.PushInteger(L, 14); vm.SetField(L, -2, "K")
	vm.PushInteger(L, 15); vm.SetField(L, -2, "L")
	vm.PushInteger(L, 16); vm.SetField(L, -2, "M")
	vm.PushInteger(L, 17); vm.SetField(L, -2, "N")
	vm.PushInteger(L, 18); vm.SetField(L, -2, "O")
	vm.PushInteger(L, 19); vm.SetField(L, -2, "P")
	vm.PushInteger(L, 20); vm.SetField(L, -2, "Q")
	vm.PushInteger(L, 21); vm.SetField(L, -2, "R")
	vm.PushInteger(L, 22); vm.SetField(L, -2, "S")
	vm.PushInteger(L, 23); vm.SetField(L, -2, "T")
	vm.PushInteger(L, 24); vm.SetField(L, -2, "U")
	vm.PushInteger(L, 25); vm.SetField(L, -2, "V")
	vm.PushInteger(L, 26); vm.SetField(L, -2, "W")
	vm.PushInteger(L, 27); vm.SetField(L, -2, "X")
	vm.PushInteger(L, 28); vm.SetField(L, -2, "Y")
	vm.PushInteger(L, 29); vm.SetField(L, -2, "Z")

	vm.PushInteger(L, 44); vm.SetField(L, -2, "Space")
	vm.PushInteger(L, 40); vm.SetField(L, -2, "Enter")
	vm.PushInteger(L, 41); vm.SetField(L, -2, "Escape")
	vm.PushInteger(L, 42); vm.SetField(L, -2, "Backspace")
	vm.PushInteger(L, 43); vm.SetField(L, -2, "Tab")

	vm.PushInteger(L, 80); vm.SetField(L, -2, "Left")
	vm.PushInteger(L, 79); vm.SetField(L, -2, "Right")
	vm.PushInteger(L, 82); vm.SetField(L, -2, "Up")
	vm.PushInteger(L, 81); vm.SetField(L, -2, "Down")

	vm.PushInteger(L, 225); vm.SetField(L, -2, "LeftShift")
	vm.PushInteger(L, 229); vm.SetField(L, -2, "RightShift")
	vm.PushInteger(L, 224); vm.SetField(L, -2, "LeftCtrl")
	vm.PushInteger(L, 228); vm.SetField(L, -2, "RightCtrl")
	vm.PushInteger(L, 226); vm.SetField(L, -2, "LeftAlt")
	vm.PushInteger(L, 230); vm.SetField(L, -2, "RightAlt")

	vm.PushInteger(L, 57); vm.SetField(L, -2, "CapsLock")
	vm.PushInteger(L, 76); vm.SetField(L, -2, "Delete")
	vm.PushInteger(L, 73); vm.SetField(L, -2, "Insert")
	vm.PushInteger(L, 74); vm.SetField(L, -2, "Home")
	vm.PushInteger(L, 77); vm.SetField(L, -2, "End")
	vm.PushInteger(L, 75); vm.SetField(L, -2, "PageUp")
	vm.PushInteger(L, 78); vm.SetField(L, -2, "PageDown")
}

install_mouse_button_table :: proc(L: ^vm.State) {
	vm.NewTable(L, 0, 5)

	vm.PushInteger(L, 1)
	vm.SetField(L, -2, "Left")

	vm.PushInteger(L, 2)
	vm.SetField(L, -2, "Middle")

	vm.PushInteger(L, 3)
	vm.SetField(L, -2, "Right")

	vm.PushInteger(L, 4)
	vm.SetField(L, -2, "X1")

	vm.PushInteger(L, 5)
	vm.SetField(L, -2, "X2")
}

Install :: proc(
	L: ^vm.State,
	raw_context: rawptr,
	renderer_object: ^renderer.RendererObject,
) {
	ctx := cast(^Context)raw_context
	ctx.renderer = renderer_object

	vm.NewTable(L, 0, 64)

	// Used only to distinguish Argon:Foo(...) from Argon.Foo(...).
	vm.PushBoolean(L, true)
	vm.SetField(L, -2, "__argon")

	set_function(L, "RGBA", rgba, ctx)
	set_function(L, "Vector3", vector3, ctx)

	// Images.
	set_function(L, "CreateImageFromPath", create_image_from_path, ctx)
	set_function(L, "CreateImageFromMemory", create_image_from_memory, ctx)
	set_function(L, "DrawImageSized", draw_image_sized, ctx)
	set_function(L, "DrawImageRect", draw_image_rect, ctx)
	set_function(L, "DrawImageOutlineSized", draw_image_outline_sized, ctx)
	set_function(L, "DrawPixels", draw_pixels, ctx)

	// Shapes.
	set_function(L, "DrawRectangle", draw_rectangle, ctx)
	set_function(L, "DrawRotatedRectangle", draw_rotated_rectangle, ctx)
	set_function(L, "DrawRoundRectangle", draw_round_rectangle, ctx)
	set_function(L, "DrawSquircle", draw_squircle, ctx)
	set_function(L, "DrawCircle", draw_circle, ctx)
	set_function(L, "DrawLine", draw_line, ctx)
	set_function(L, "DrawPolygon", draw_polygon, ctx)
	set_function(L, "DrawUIShadow", draw_ui_shadow, ctx)
	set_function(L, "DrawBackdropBlur", draw_backdrop_blur, ctx)
	set_function(
		L,
		"DrawBackdropBlurSquircle",
		draw_backdrop_blur_squircle,
		ctx,
	)

	// Surface stack / clipping.
	set_function(L, "Save", save, ctx)
	set_function(L, "Restore", restore, ctx)
	set_function(L, "ClipRoundRect", clip_round_rect, ctx)
	set_function(L, "ClipSquircle", clip_squircle, ctx)
	set_function(L, "Clear2D", clear_2d, ctx)
	set_function(L, "CreateSkiaSurface", create_skia_surface, ctx)
	set_function(L, "InitSkiaSurface", create_skia_surface, ctx)
	set_function(L, "DestroySkiaSurface", destroy_skia_surface, ctx)
	set_function(L, "GetSurfacePixel", get_surface_pixel, ctx)
	set_function(L, "GetSurfacePixels", get_surface_pixels, ctx)

	// Runtime SkSL.
	set_function(L, "CreateRuntimeShader", create_runtime_shader, ctx)
	set_function(L, "DestroyRuntimeShader", destroy_runtime_shader, ctx)
	set_function(
		L,
		"SetRuntimeShaderUniform",
		set_runtime_shader_uniform,
		ctx,
	)
	set_function(
		L,
		"DrawRuntimeShaderRectangle",
		draw_runtime_shader_rectangle,
		ctx,
	)

	// Text.
	set_function(L, "CreateFont", create_font, ctx)
	set_function(L, "MeasureText", measure_text, ctx)
	set_function(L, "GetFontLineHeight", font_line_height, ctx)
	set_function(L, "GetFontAscent", font_ascent, ctx)
	set_function(L, "DrawText", draw_text, ctx)
	set_function(L, "DrawTextShadow", draw_text_shadow, ctx)

	// Translation.
	set_function(
		L,
		"CreateTranslationLayer",
		create_translation_layer,
		ctx,
	)
	set_function(
		L,
		"SetActiveTranslationLayer",
		set_active_translation_layer,
		ctx,
	)

	// Window/system.
	set_function(L, "GetWindowPixelSize", get_window_size, ctx)
	set_function(L, "GetRenderWidth", get_render_width, ctx)
	set_function(L, "GetRenderHeight", get_render_height, ctx)
	set_function(L, "GetDPIScale", get_dpi_scale, ctx)
	set_function(L, "GetSystemTheme", get_system_theme, ctx)
	set_function(L, "IsWindowFocused", is_window_focused, ctx)

	// Input.
	set_function(L, "GetMousePosition", get_mouse_position, ctx)
	set_function(L, "GetMouseDelta", get_mouse_delta, ctx)
	set_function(L, "GetMouseWheelMove", get_mouse_wheel_move, ctx)
	set_function(L, "IsMouseButtonDown", mouse_down, ctx)
	set_function(L, "IsMouseButtonPressed", mouse_pressed, ctx)
	set_function(L, "IsMouseButtonReleased", mouse_released, ctx)
	set_function(L, "IsKeyDown", is_key_down, ctx)
	set_function(L, "DisableCursor", disable_cursor, ctx)
	set_function(L, "EnableCursor", enable_cursor, ctx)
	set_function(L, "ShowCursor", show_cursor, ctx)
	set_function(L, "HideCursor", hide_cursor, ctx)
	set_function(L, "SetMouseCursor", set_mouse_cursor, ctx)
	set_function(L, "SetMousePosition", set_mouse_position, ctx)
	set_function(L, "StartTextInput", start_text_input, ctx)
	set_function(L, "StopTextInput", stop_text_input, ctx)

	// Clipboard.
	set_function(L, "SetClipboard", set_clipboard, ctx)
	set_function(L, "GetClipboard", get_clipboard, ctx)

	install_mouse_button_table(L)
	vm.SetField(L, -2, "MouseButton")

	install_key_table(L)
	vm.SetField(L, -2, "Key")
}


// -----------------------------------------------------------------------------
// Per-frame state
// -----------------------------------------------------------------------------

Begin_Frame :: proc(
	raw_context: rawptr,
	width, height: i32,
) {
	ctx := cast(^Context)raw_context
	if ctx == nil {
		return
	}

	ctx.width = width
	ctx.height = height

	x, y: f32
	_ = sdl3.GetMouseState(&x, &y)

	ctx.mouse_delta_x = x - ctx.mouse_x
	ctx.mouse_delta_y = y - ctx.mouse_y
	ctx.mouse_x = x
	ctx.mouse_y = y

	ctx.mouse_wheel = 0

	for button in 1 ..= 5 {
		was_down := ctx.mouse_down[button]
		is_down := mouse_button_down(button)

		ctx.mouse_pressed[button] =
			is_down && !was_down

		ctx.mouse_released[button] =
			!is_down && was_down

		ctx.mouse_down[button] = is_down
	}
}
