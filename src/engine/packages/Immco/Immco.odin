package immco

// wire:package name="Immco"

import "core:math"
import "core:strings"
import base_runtime "base:runtime"
import sdl3 "../../platform"
import "core:fmt"

import kineffi "../../bindings"
import renderer "../../renderer"
import vm "../../vm"
import luauh "../../vm/luauh"

Layout_State :: struct {
    active: bool,
    x, y: f32,
    width, height: f32,
    spacing, padding: f32,
    origin_x: f32,
    prev_x, prev_y: f32,
    prev_width, prev_height: f32,
    has_prev: bool,
}

Context :: struct {
    renderer: ^renderer.RendererObject,

    frame_width:  f32,
    frame_height: f32,

    mouse_x:       f32,
    mouse_y:       f32,
    mouse_down:    bool,
    mouse_clicked: bool,

    layout: Layout_State,
}

// -----------------------------------------------------------------------------
// Generic Luau helpers
// -----------------------------------------------------------------------------

abs_index :: proc(L: ^vm.State, index: int) -> int {
    if index >= 0 {
        return index
    }
    return vm.StackTop(L) + index + 1
}

params_index :: proc(L: ^vm.State) -> int {
    if vm.StackTop(L) >= 2 && vm.IsTable(L, 1) {
        // Allow old colon-style calls: Immco:Text(...), Immco:BeginList(...), etc.
        t := vm.GetField(L, 1, "Rectangle")
        is_module := t == .Function
        vm.Pop(L)
        if is_module {
            return 2
        }
    }
    return 1
}

table_number :: proc(L: ^vm.State, index: int, name: string, default: f32 = 0) -> f32 {
    idx := abs_index(L, index)
    t := vm.GetField(L, idx, name)
    defer vm.Pop(L)

    if t != .Number && t != .Integer {
        return default
    }
    return f32(vm.ArgNumber(L, -1))
}

table_string :: proc(L: ^vm.State, index: int, name: string, default: string = "") -> string {
    idx := abs_index(L, index)
    t := vm.GetField(L, idx, name)
    defer vm.Pop(L)

    if t != .String {
        return default
    }
    return vm.ArgString(L, -1)
}

table_bool :: proc(L: ^vm.State, index: int, name: string, default: bool = false) -> bool {
    idx := abs_index(L, index)
    t := vm.GetField(L, idx, name)
    defer vm.Pop(L)

    if t == .Boolean {
        return vm.ArgBoolean(L, -1)
    }
    if t == .Number || t == .Integer {
        return vm.ArgNumber(L, -1) != 0
    }
    return default
}

component_to_u8 :: proc(value: f32, default: u8) -> u8 {
    v := value
    if v >= 0 && v <= 1 {
        v *= 255
    }
    return u8(math.round(clamp(v, 0, 255)))
}

color_value :: proc(
    L: ^vm.State,
    index: int,
    default_r, default_g, default_b, default_a: u8,
) -> (r, g, b, a: u8) {
    idx := abs_index(L, index)
    r, g, b, a = default_r, default_g, default_b, default_a

    tr := vm.GetField(L, idx, "R")
    if tr == .Number || tr == .Integer {
        r = component_to_u8(f32(vm.ArgNumber(L, -1)), default_r)
    }
    vm.Pop(L)

    tg := vm.GetField(L, idx, "G")
    if tg == .Number || tg == .Integer {
        g = component_to_u8(f32(vm.ArgNumber(L, -1)), default_g)
    }
    vm.Pop(L)

    tb := vm.GetField(L, idx, "B")
    if tb == .Number || tb == .Integer {
        b = component_to_u8(f32(vm.ArgNumber(L, -1)), default_b)
    }
    vm.Pop(L)

    ta := vm.GetField(L, idx, "A")
    if ta == .Number || ta == .Integer {
        a = component_to_u8(f32(vm.ArgNumber(L, -1)), default_a)
    }
    vm.Pop(L)

    return
}

color_field :: proc(
    L: ^vm.State,
    index: int,
    name: string,
    default_r, default_g, default_b, default_a: u8,
) -> (r, g, b, a: u8) {
    idx := abs_index(L, index)
    t := vm.GetField(L, idx, name)
    defer vm.Pop(L)

    if t != .Table && t != .Userdata && t != .Object && t != .Class {
        return default_r, default_g, default_b, default_a
    }
    return color_value(L, -1, default_r, default_g, default_b, default_a)
}

theme_color :: proc(
    L: ^vm.State,
    index: int,
    name: string,
    default_r, default_g, default_b, default_a: u8,
) -> (r, g, b, a: u8) {
    idx := abs_index(L, index)
    t := vm.GetField(L, idx, "theme")
    defer vm.Pop(L)

    if t != .Table && t != .Userdata && t != .Object && t != .Class {
        return default_r, default_g, default_b, default_a
    }
    return color_field(L, -1, name, default_r, default_g, default_b, default_a)
}

resolved_color :: proc(
    L: ^vm.State,
    index: int,
    direct_name, theme_name: string,
    default_r, default_g, default_b, default_a: u8,
) -> (r, g, b, a: u8) {
    idx := abs_index(L, index)

    t := vm.GetField(L, idx, direct_name)
    if t == .Table || t == .Userdata || t == .Object || t == .Class {
        result_r, result_g, result_b, result_a := color_value(
            L, -1,
            default_r, default_g, default_b, default_a,
        )
        vm.Pop(L)
        return result_r, result_g, result_b, result_a
    }
    vm.Pop(L)

    return theme_color(
        L, idx, theme_name,
        default_r, default_g, default_b, default_a,
    )
}

context_from_upvalue :: proc(L: ^vm.State) -> ^Context {
    return cast(^Context)vm.UpvaluePointer(L)
}

surface_from_upvalue :: proc(L: ^vm.State) -> ^kineffi.KineSkiaSurface {
    ctx := context_from_upvalue(L)
    if ctx == nil || ctx.renderer == nil {
        return nil
    }
    return ctx.renderer.SkiaSurface
}

set_function :: proc(L: ^vm.State, name: string, function: vm.CFunction, ctx: ^Context) {
    vm.PushLightUserdata(L, ctx)
    vm.PushFunction(L, name, function, 1)
    vm.SetField(L, -2, name)
}

copy_field :: proc(L: ^vm.State, source_index, destination_index: int, name: string) {
    src_index := abs_index(L, source_index)
    dst_index := abs_index(L, destination_index)

    t := vm.GetField(L, src_index, name)
    if t == .Nil || t == .None {
        vm.Pop(L)
        return
    }
    vm.SetField(L, dst_index, name)
}

set_number_field :: proc(L: ^vm.State, table_index: int, name: string, value: f32) {
    idx := abs_index(L, table_index)
    vm.PushNumber(L, f64(value))
    vm.SetField(L, idx, name)
}

set_bool_field :: proc(L: ^vm.State, table_index: int, name: string, value: bool) {
    idx := abs_index(L, table_index)
    vm.PushBoolean(L, value)
    vm.SetField(L, idx, name)
}

set_string_field :: proc(L: ^vm.State, table_index: int, name, value: string) {
    idx := abs_index(L, table_index)
    vm.PushString(L, value)
    vm.SetField(L, idx, name)
}

call0 :: proc(L: ^vm.State, table_index: int, name: string) {
    idx := abs_index(L, table_index)
    t := vm.GetField(L, idx, name)
    if t != .Function {
        vm.Pop(L)
        return
    }
    ok, err := vm.ProtectedCall(L, 0, 0)
    _ = ok
    _ = err
}

call_bool :: proc(L: ^vm.State, table_index: int, name: string, value: bool) {
    idx := abs_index(L, table_index)
    t := vm.GetField(L, idx, name)
    if t != .Function {
        vm.Pop(L)
        return
    }
    vm.PushBoolean(L, value)
    ok, err := vm.ProtectedCall(L, 1, 0)
    _ = ok
    _ = err
}

call_number :: proc(L: ^vm.State, table_index: int, name: string, value: f32) {
    idx := abs_index(L, table_index)
    t := vm.GetField(L, idx, name)
    if t != .Function {
        vm.Pop(L)
        return
    }
    vm.PushNumber(L, f64(value))
    ok, err := vm.ProtectedCall(L, 1, 0)
    _ = ok
    _ = err
}

call_string :: proc(L: ^vm.State, table_index: int, name, value: string) {
    idx := abs_index(L, table_index)
    t := vm.GetField(L, idx, name)
    if t != .Function {
        vm.Pop(L)
        return
    }
    vm.PushString(L, value)
    ok, err := vm.ProtectedCall(L, 1, 0)
    _ = ok
    _ = err
}

call_value :: proc(L: ^vm.State, table_index: int, name: string, value_index: int) {
    table_idx := abs_index(L, table_index)
    value_idx := abs_index(L, value_index)

    t := vm.GetField(L, table_idx, name)
    if t != .Function {
        vm.Pop(L)
        return
    }
    vm.PushValue(L, value_idx)
    ok, err := vm.ProtectedCall(L, 1, 0)
    _ = ok
    _ = err
}

call_color :: proc(L: ^vm.State, table_index: int, name: string, r, g, b, a: f32) {
    idx := abs_index(L, table_index)
    t := vm.GetField(L, idx, name)
    if t != .Function {
        vm.Pop(L)
        return
    }

    vm.NewTable(L, 0, 4)
    set_number_field(L, -1, "R", r)
    set_number_field(L, -1, "G", g)
    set_number_field(L, -1, "B", b)
    set_number_field(L, -1, "A", a)

    ok, err := vm.ProtectedCall(L, 1, 0)
    _ = ok
    _ = err
}

invoke_rect_callback :: proc(
    L: ^vm.State,
    params: int,
    name: string,
    x, y, width, height: f32,
) {
    params_idx := abs_index(L, params)
    t := vm.GetField(L, params_idx, name)
    if t != .Function {
        vm.Pop(L)
        return
    }

    vm.NewTable(L, 0, 12)
    result := abs_index(L, -1)
    set_number_field(L, result, "x", x)
    set_number_field(L, result, "y", y)
    set_number_field(L, result, "width", width)
    set_number_field(L, result, "height", height)

    copy_field(L, params_idx, result, "renderer")
    copy_field(L, params_idx, result, "theme")
    copy_field(L, params_idx, result, "engine_window")
    copy_field(L, params_idx, result, "window")
    copy_field(L, params_idx, result, "RetainedStorage")

    ok, err := vm.ProtectedCall(L, 1, 0)
    _ = ok
    _ = err
}

// -----------------------------------------------------------------------------
// Drawing helpers
// -----------------------------------------------------------------------------

mouse_in_rect :: proc(ctx: ^Context, x, y, width, height: f32) -> bool {
    if ctx == nil {
        return false
    }
    return ctx.mouse_x >= x && ctx.mouse_x <= x+width &&
           ctx.mouse_y >= y && ctx.mouse_y <= y+height
}

consume_click :: proc(ctx: ^Context) {
    if ctx != nil {
        ctx.mouse_clicked = false
    }
}

draw_text_raw :: proc(
    surface: ^kineffi.KineSkiaSurface,
    value, font: string,
    x, y, size: f32,
    r, g, b, a: u8,
) {
    if surface == nil {
        return
    }

    c_value := strings.clone_to_cstring(value)
    c_font := strings.clone_to_cstring(font)
    defer delete(c_value)
    defer delete(c_font)

    kineffi.Kine_Skia_Surface_DrawText(
        surface,
        c_value,
        x, y,
        size,
        c_font,
        r, g, b, a,
    )
}

measure_text_raw :: proc(value, font: string, size: f32) -> f32 {
    c_value := strings.clone_to_cstring(value)
    c_font := strings.clone_to_cstring(font)
    defer delete(c_value)
    defer delete(c_font)

    return kineffi.Kine_Skia_Surface_MeasureText(c_value, size, c_font)
}

font_line_height :: proc(font: string, size: f32) -> f32 {
    c_font := strings.clone_to_cstring(font)
    defer delete(c_font)
    return kineffi.Kine_Skia_Surface_GetFontLineHeight(size, c_font)
}

font_ascent :: proc(font: string, size: f32) -> f32 {
    c_font := strings.clone_to_cstring(font)
    defer delete(c_font)
    return kineffi.Kine_Skia_Surface_GetFontAscent(size, c_font)
}

centered_baseline :: proc(y, height: f32, font: string, size: f32) -> f32 {
    line_height := font_line_height(font, size)
    ascent := font_ascent(font, size)
    return y + (height-line_height)*0.5 + ascent
}

draw_panel :: proc(
    surface: ^kineffi.KineSkiaSurface,
    x, y, width, height, radius: f32,
    r, g, b, a: u8,
    stroke_width: f32 = 0,
) {
    if radius > 0 {
        kineffi.Kine_Skia_Surface_DrawRoundRect(
            surface, x, y, width, height,
            radius, radius,
            r, g, b, a,
            stroke_width,
        )
    } else {
        kineffi.Kine_Skia_Surface_DrawRect(
            surface, x, y, width, height,
            r, g, b, a,
            stroke_width,
        )
    }
}

pointer_from_value :: proc(L: ^vm.State, index: int) -> rawptr {
    idx := abs_index(L, index)
    t := vm.TypeOf(L, idx)

    if t == .LightUserdata {
        return luauh.lua_tolightuserdata(L, i32(idx))
    }
    if t == .Userdata {
        native := vm.UserdataValue(L, idx)
        if native != nil {
            return native
        }
        return luauh.lua_touserdata(L, i32(idx))
    }
    return nil
}

image_from_params :: proc(L: ^vm.State, params: int) -> ^kineffi.KineSkiaImage {
    params_idx := abs_index(L, params)

    for field in ([?]string{"Image", "image", "Handle", "handle"}) {
        t := vm.GetField(L, params_idx, field)
        if t == .LightUserdata || t == .Userdata {
            result := cast(^kineffi.KineSkiaImage)pointer_from_value(L, -1)
            vm.Pop(L)
            return result
        }

        if t == .Table {
            table_index := abs_index(L, -1)
            for handle_name in ([?]string{"_handle", "Handle", "handle"}) {
                ht := vm.GetField(L, table_index, handle_name)
                if ht == .LightUserdata || ht == .Userdata {
                    result := cast(^kineffi.KineSkiaImage)pointer_from_value(L, -1)
                    vm.Pop(L, 2)
                    return result
                }
                vm.Pop(L)
            }
        }
        vm.Pop(L)
    }

    return nil
}

// -----------------------------------------------------------------------------
// Primitive components
// -----------------------------------------------------------------------------

rectangle :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    r, g, b, a := resolved_color(L, p, "Color", "BgColor", 255, 255, 255, 255)
    stroke := table_number(L, p, "StrokeWidth", 0)
    if table_bool(L, p, "isOutline", false) && stroke <= 0 {
        stroke = 1
    }

    kineffi.Kine_Skia_Surface_DrawRect(
        surface,
        table_number(L, p, "x"),
        table_number(L, p, "y"),
        table_number(L, p, "width"),
        table_number(L, p, "height"),
        r, g, b, a,
        stroke,
    )
    return 0
}

rounded_rectangle :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    r, g, b, a := resolved_color(L, p, "Color", "BgColor", 255, 255, 255, 255)
    radius := table_number(L, p, "CornerRadius", 6)
    stroke := table_number(L, p, "StrokeWidth", 0)
    if table_bool(L, p, "isOutline", false) && stroke <= 0 {
        stroke = 1
    }

    kineffi.Kine_Skia_Surface_DrawRoundRect(
        surface,
        table_number(L, p, "x"),
        table_number(L, p, "y"),
        table_number(L, p, "width"),
        table_number(L, p, "height"),
        radius, radius,
        r, g, b, a,
        stroke,
    )
    return 0
}

squircle :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    r, g, b, a := resolved_color(L, p, "Color", "BgColor", 255, 255, 255, 255)
    kineffi.Kine_Skia_Surface_DrawSquircle(
        surface,
        table_number(L, p, "x"), table_number(L, p, "y"),
        table_number(L, p, "width"), table_number(L, p, "height"),
        table_number(L, p, "CornerRadius", 8),
        table_number(L, p, "Exponent", 4),
        r, g, b, a,
        table_number(L, p, "StrokeWidth", 0),
    )
    return 0
}

line :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    r, g, b, a := resolved_color(L, p, "Color", "TextColor", 255, 255, 255, 255)
    x0 := table_number(L, p, "x", table_number(L, p, "x0"))
    y0 := table_number(L, p, "y", table_number(L, p, "y0"))
    x1 := table_number(L, p, "x2", table_number(L, p, "x1"))
    y1 := table_number(L, p, "y2", table_number(L, p, "y1"))

    kineffi.Kine_Skia_Surface_DrawLine(
        surface, x0, y0, x1, y1,
        table_number(L, p, "Thickness", table_number(L, p, "StrokeWidth", 1)),
        r, g, b, a,
    )
    return 0
}

circle :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    r, g, b, a := resolved_color(L, p, "Color", "TextColor", 255, 255, 255, 255)
    kineffi.Kine_Skia_Surface_DrawCircle(
        surface,
        table_number(L, p, "x", table_number(L, p, "cx")),
        table_number(L, p, "y", table_number(L, p, "cy")),
        table_number(L, p, "radius", table_number(L, p, "Radius", 4)),
        r, g, b, a,
        table_number(L, p, "StrokeWidth", 0),
    )
    return 0
}

oval :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    r, g, b, a := resolved_color(L, p, "Color", "TextColor", 255, 255, 255, 255)
    kineffi.Kine_Skia_Surface_DrawOval(
        surface,
        table_number(L, p, "x"), table_number(L, p, "y"),
        table_number(L, p, "width"), table_number(L, p, "height"),
        r, g, b, a,
        table_number(L, p, "StrokeWidth", 0),
    )
    return 0
}

arc :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    r, g, b, a := resolved_color(L, p, "Color", "AccentColor", 255, 255, 255, 255)
    use_center: i32 = 0
    if table_bool(L, p, "UseCenter", false) {
        use_center = 1
    }

    kineffi.Kine_Skia_Surface_DrawArc(
        surface,
        table_number(L, p, "x"), table_number(L, p, "y"),
        table_number(L, p, "width"), table_number(L, p, "height"),
        table_number(L, p, "StartAngle", 0),
        table_number(L, p, "SweepAngle", 270),
        use_center,
        r, g, b, a,
        table_number(L, p, "StrokeWidth", 2),
    )
    return 0
}

shadow :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    r, g, b, a := resolved_color(L, p, "Color", "ShadowColor", 0, 0, 0, 110)
    kineffi.Kine_Skia_Surface_DrawUIShadow(
        surface,
        table_number(L, p, "x"), table_number(L, p, "y"),
        table_number(L, p, "width"), table_number(L, p, "height"),
        table_number(L, p, "CornerRadius", 8),
        table_number(L, p, "Exponent", 4),
        table_number(L, p, "OffsetX", 0),
        table_number(L, p, "OffsetY", 3),
        table_number(L, p, "BlurSigma", 8),
        table_number(L, p, "Spread", 1),
        r, g, b, a,
    )
    return 0
}

backdrop_blur :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    r, g, b, a := resolved_color(L, p, "TintColor", "BgColor", 0, 0, 0, 0)
    kineffi.Kine_Skia_Surface_DrawBackdropBlurRect(
        surface,
        table_number(L, p, "x"), table_number(L, p, "y"),
        table_number(L, p, "width"), table_number(L, p, "height"),
        table_number(L, p, "CornerRadius", 8),
        table_number(L, p, "CornerRadius", 8),
        table_number(L, p, "BlurSigma", 12),
        u8(clamp(table_number(L, p, "Alpha", 1)*255, 0, 255)),
        r, g, b, a,
    )
    return 0
}

text :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil {
        return 0
    }

    if vm.IsTable(L, p) {
        value := table_string(L, p, "text", table_string(L, p, "Text", "Text"))
        font := table_string(L, p, "Font", "")
        r, g, b, a := resolved_color(L, p, "Color", "TextColor", 255, 255, 255, 255)
        draw_text_raw(
            surface, value, font,
            table_number(L, p, "x"), table_number(L, p, "y"),
            table_number(L, p, "TextSize", 14),
            r, g, b, a,
        )
        return 0
    }

    // Old immediate form: Immco:Text("Hello", 14, width)
    if vm.TypeOf(L, p) == .String && ctx != nil && ctx.layout.active {
        value := vm.ArgString(L, p)
        size := f32(vm.ArgOptionalNumber(L, p+1, 14))
        width := f32(vm.ArgOptionalNumber(L, p+2, f64(ctx.layout.width)))
        ascent := font_ascent("", size)
        draw_text_raw(surface, value, "", ctx.layout.x, ctx.layout.y+ascent, size, 255, 255, 255, 255)
        ctx.layout.prev_x = ctx.layout.x
        ctx.layout.prev_y = ctx.layout.y
        ctx.layout.prev_width = width
        ctx.layout.prev_height = font_line_height("", size)
        ctx.layout.has_prev = true
        ctx.layout.y += ctx.layout.prev_height + ctx.layout.spacing
    }
    return 0
}

image :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    image_handle := image_from_params(L, p)
    if image_handle == nil {
        return 0
    }

    src_width := f32(kineffi.Kine_Skia_Image_GetWidth(image_handle))
    src_height := f32(kineffi.Kine_Skia_Image_GetHeight(image_handle))
    width := table_number(L, p, "width", src_width)
    height := table_number(L, p, "height", src_height)
    alpha := u8(clamp(table_number(L, p, "Alpha", 1)*255, 0, 255))

    src_x := table_number(L, p, "srcX", 0)
    src_y := table_number(L, p, "srcY", 0)
    src_w := table_number(L, p, "srcWidth", src_width)
    src_h := table_number(L, p, "srcHeight", src_height)

    if src_x == 0 && src_y == 0 && src_w == src_width && src_h == src_height {
        kineffi.Kine_Skia_Surface_DrawImageSized(
            surface, image_handle,
            table_number(L, p, "x"),
            table_number(L, p, "y"),
            width, height,
            alpha,
        )
    } else {
        kineffi.Kine_Skia_Surface_DrawImageRect(
            surface, image_handle,
            src_x, src_y, src_w, src_h,
            table_number(L, p, "x"),
            table_number(L, p, "y"),
            width, height,
            alpha,
        )
    }
    return 0
}

measure_text :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    p := params_index(L)

    if vm.IsTable(L, p) {
        value := table_string(L, p, "text", table_string(L, p, "Text", ""))
        font := table_string(L, p, "Font", "")
        size := table_number(L, p, "TextSize", 14)
        vm.PushNumber(L, f64(measure_text_raw(value, font, size)))
        return 1
    }

    value := vm.ArgOptionalString(L, p, "")
    size := f32(vm.ArgOptionalNumber(L, p+1, 14))
    font := vm.ArgOptionalString(L, p+2, "")
    vm.PushNumber(L, f64(measure_text_raw(value, font, size)))
    return 1
}

get_font_ascent :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    p := params_index(L)
    size := f32(vm.ArgOptionalNumber(L, p, 14))
    font := vm.ArgOptionalString(L, p+1, "")
    vm.PushNumber(L, f64(font_ascent(font, size)))
    return 1
}

get_font_line_height :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    p := params_index(L)
    size := f32(vm.ArgOptionalNumber(L, p, 14))
    font := vm.ArgOptionalString(L, p+1, "")
    vm.PushNumber(L, f64(font_line_height(font, size)))
    return 1
}

load_image :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    p := params_index(L)
    path := vm.ArgOptionalString(L, p, "")
    if path == "" {
        vm.PushNil(L)
        return 1
    }

    c_path := strings.clone_to_cstring(path)
    defer delete(c_path)
    handle := kineffi.Kine_Skia_Image_LoadFromFile(c_path)
    if handle == nil {
        vm.PushNil(L)
    } else {
        vm.PushLightUserdata(L, handle)
    }
    return 1
}

destroy_image :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    p := params_index(L)
    handle := cast(^kineffi.KineSkiaImage)pointer_from_value(L, p)
    if handle != nil {
        kineffi.Kine_Skia_Image_Destroy(handle)
    }
    return 0
}

// -----------------------------------------------------------------------------
// Containers
// -----------------------------------------------------------------------------

widget :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width", 400)
    height := table_number(L, p, "height", 400)
    radius := table_number(L, p, "CornerRadius", 8)
    header_visible := table_bool(L, p, "HeaderVisible", true)
    header_height := table_number(L, p, "HeaderHeight", 30)
    if !header_visible {
        header_height = 0
    }

    bg_r, bg_g, bg_b, bg_a := resolved_color(L, p, "Color", "BgColor", 30, 30, 32, 255)
    header_r, header_g, header_b, header_a := resolved_color(L, p, "HeaderColor", "ThirdColor", 24, 24, 27, 255)
    text_r, text_g, text_b, text_a := resolved_color(L, p, "TextColor", "TextColor", 232, 232, 235, 255)

    if table_bool(L, p, "Shadow", true) {
        sh_r, sh_g, sh_b, sh_a := resolved_color(L, p, "ShadowColor", "ShadowColor", 0, 0, 0, 90)
        kineffi.Kine_Skia_Surface_DrawUIShadow(
            surface, x, y, width, height,
            radius, 4,
            0, 3, 10, 1,
            sh_r, sh_g, sh_b, sh_a,
        )
    }

    draw_panel(surface, x, y, width, height, radius, bg_r, bg_g, bg_b, bg_a)

    if header_visible {
        kineffi.Kine_Skia_Surface_Save(surface)
        kineffi.Kine_Skia_Surface_ClipRoundRect(surface, x, y, width, height, radius, radius)
        kineffi.Kine_Skia_Surface_DrawRect(
            surface, x, y, width, header_height,
            header_r, header_g, header_b, header_a, 0,
        )
        kineffi.Kine_Skia_Surface_Restore(surface)

        title := table_string(L, p, "title", table_string(L, p, "Title", "Immco"))
        font := table_string(L, p, "Font", "")
        size := table_number(L, p, "TitleTextSize", 13)
        draw_text_raw(
            surface, title, font,
            x+10, centered_baseline(y, header_height, font, size), size,
            text_r, text_g, text_b, text_a,
        )
    }

    content_y := y + header_height
    content_height := height - header_height
    invoke_rect_callback(L, p, "callback", x, content_y, width, content_height)
    return 0
}

frame :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width")
    height := table_number(L, p, "height")
    radius := table_number(L, p, "CornerRadius", 0)
    r, g, b, a := resolved_color(L, p, "Color", "BgColor", 35, 35, 38, 255)

    draw_panel(surface, x, y, width, height, radius, r, g, b, a)
    invoke_rect_callback(L, p, "callback", x, y, width, height)
    return 0
}

card :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width")
    height := table_number(L, p, "height")
    radius := table_number(L, p, "CornerRadius", 8)
    r, g, b, a := resolved_color(L, p, "Color", "SecondaryColor", 42, 42, 46, 255)

    if table_bool(L, p, "Shadow", false) {
        kineffi.Kine_Skia_Surface_DrawUIShadow(
            surface, x, y, width, height,
            radius, 4,
            0, 2, 6, 0,
            0, 0, 0, 80,
        )
    }

    draw_panel(surface, x, y, width, height, radius, r, g, b, a)
    invoke_rect_callback(L, p, "callback", x, y, width, height)
    return 0
}

scroller :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width")
    height := table_number(L, p, "height")
    view_height := table_number(L, p, "ViewHeight", height)
    content_width := table_number(L, p, "ContentWidth", width)
    content_height := table_number(L, p, "ContentHeight", view_height)
    scroll_y := clamp(table_number(L, p, "ScrollY", table_number(L, p, "OffsetY", 0)), 0, max(content_height-view_height, 0))

    kineffi.Kine_Skia_Surface_Save(surface)
    kineffi.Kine_Skia_Surface_ClipRect(surface, x, y, width, view_height)

    t := vm.GetField(L, p, "callback")
    if t == .Function {
        vm.NewTable(L, 0, 18)
        result := abs_index(L, -1)
        set_number_field(L, result, "x", x)
        set_number_field(L, result, "y", y-scroll_y)
        set_number_field(L, result, "width", content_width)
        set_number_field(L, result, "height", content_height)
        set_number_field(L, result, "viewportX", x)
        set_number_field(L, result, "viewportY", y)
        set_number_field(L, result, "viewportWidth", width)
        set_number_field(L, result, "viewportHeight", view_height)
        set_number_field(L, result, "scrollY", scroll_y)

        copy_field(L, p, result, "renderer")
        copy_field(L, p, result, "theme")
        copy_field(L, p, result, "engine_window")
        copy_field(L, p, result, "window")
        copy_field(L, p, result, "RetainedStorage")

        ok, err := vm.ProtectedCall(L, 1, 0)
        if !ok {
            fmt.eprintf("Immco callback '%s' failed: %s\n", ok, err)
            delete(err)
        }
    } else {
        vm.Pop(L)
    }

    kineffi.Kine_Skia_Surface_Restore(surface)

    if content_height > view_height && view_height > 0 {
        bar_width := table_number(L, p, "ScrollbarWidth", 4)
        track_height := view_height
        thumb_height := max(18, track_height*(view_height/content_height))
        max_scroll := max(content_height-view_height, 1)
        thumb_y := y + (scroll_y/max_scroll)*(track_height-thumb_height)
        r, g, b, a := resolved_color(L, p, "ThumbColor", "SecondaryTextColor", 125, 125, 135, 180)
        draw_panel(surface, x+width-bar_width, thumb_y, bar_width, thumb_height, bar_width*0.5, r, g, b, a)
    }
    return 0
}

pan_zoom_canvas :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width")
    height := table_number(L, p, "height")
    radius := table_number(L, p, "CornerRadius", 0)
    zoom := max(table_number(L, p, "Zoom", table_number(L, p, "InitialZoom", 1)), 0.01)
    camera_x := table_number(L, p, "CameraX", table_number(L, p, "InitialCameraX", 0))
    camera_y := table_number(L, p, "CameraY", table_number(L, p, "InitialCameraY", 0))

    bg_r, bg_g, bg_b, bg_a := resolved_color(L, p, "BackgroundColor", "ThirdColor", 25, 25, 28, 255)
    grid_r, grid_g, grid_b, grid_a := resolved_color(L, p, "GridColor", "SecondaryColor", 70, 70, 75, 130)
    draw_panel(surface, x, y, width, height, radius, bg_r, bg_g, bg_b, bg_a)

    kineffi.Kine_Skia_Surface_Save(surface)
    if radius > 0 {
        kineffi.Kine_Skia_Surface_ClipRoundRect(surface, x, y, width, height, radius, radius)
    } else {
        kineffi.Kine_Skia_Surface_ClipRect(surface, x, y, width, height)
    }

    if table_bool(L, p, "ShowGrid", true) {
        step := max(table_number(L, p, "GridSize", 32)*zoom, 8)
        raw_x := -camera_x*zoom
        gx := x + (raw_x-f32(math.floor(f64(raw_x/step)))*step)
        for gx < x+width {
            kineffi.Kine_Skia_Surface_DrawLine(surface, gx, y, gx, y+height, 1, grid_r, grid_g, grid_b, grid_a)
            gx += step
        }

        raw_y := -camera_y*zoom
        gy := y + (raw_y-f32(math.floor(f64(raw_y/step)))*step)
        for gy < y+height {
            kineffi.Kine_Skia_Surface_DrawLine(surface, x, gy, x+width, gy, 1, grid_r, grid_g, grid_b, grid_a)
            gy += step
        }
    }

    t := vm.GetField(L, p, "callback")
    if t == .Function {
        vm.NewTable(L, 0, 18)
        result := abs_index(L, -1)
        set_number_field(L, result, "x", x)
        set_number_field(L, result, "y", y)
        set_number_field(L, result, "width", width)
        set_number_field(L, result, "height", height)
        set_number_field(L, result, "cameraX", camera_x)
        set_number_field(L, result, "cameraY", camera_y)
        set_number_field(L, result, "zoom", zoom)
        set_bool_field(L, result, "hovered", mouse_in_rect(context_from_upvalue(L), x, y, width, height))
        copy_field(L, p, result, "renderer")
        copy_field(L, p, result, "theme")
        copy_field(L, p, result, "RetainedStorage")
        ok, err := vm.ProtectedCall(L, 1, 0)
        _ = ok
        _ = err
    } else {
        vm.Pop(L)
    }

    kineffi.Kine_Skia_Surface_Restore(surface)
    return 0
}

// -----------------------------------------------------------------------------
// Controls
// -----------------------------------------------------------------------------

text_button :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width", 100)
    height := table_number(L, p, "height", 32)
    radius := table_number(L, p, "CornerRadius", table_number(L, p, "ButtonCornerRadius", 6))
    disabled := table_bool(L, p, "Disabled", false)
    hovered := !disabled && mouse_in_rect(ctx, x, y, width, height)

    bg_r, bg_g, bg_b, bg_a := resolved_color(L, p, "Color", "SecondaryColor", 48, 48, 52, 255)
    if hovered {
        bg_r, bg_g, bg_b, bg_a = resolved_color(L, p, "HoverColor", "ThirdColor", 58, 58, 63, bg_a)
    }

    if table_bool(L, p, "BgVisible", true) {
        draw_panel(surface, x, y, width, height, radius, bg_r, bg_g, bg_b, bg_a)
    }

    value := table_string(L, p, "text", table_string(L, p, "Text", "Button"))
    font := table_string(L, p, "Font", "")
    size := table_number(L, p, "TextSize", 14)
    tr, tg, tb, ta := resolved_color(L, p, "TextColor", "TextColor", 235, 235, 238, 255)
    text_width := measure_text_raw(value, font, size)
    draw_text_raw(
        surface, value, font,
        x+(width-text_width)*0.5,
        centered_baseline(y, height, font, size),
        size,
        tr, tg, tb, ta,
    )

    if hovered && ctx != nil && ctx.mouse_clicked {
        call0(L, p, "OnClick")
        call0(L, p, "onClick")
        call0(L, p, "callback")
        consume_click(ctx)
        vm.PushBoolean(L, true)
        return 1
    }

    vm.PushBoolean(L, false)
    return 1
}

image_text_button :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width", 120)
    height := table_number(L, p, "height", 32)
    radius := table_number(L, p, "CornerRadius", 6)
    hovered := mouse_in_rect(ctx, x, y, width, height) && !table_bool(L, p, "Disabled", false)

    br, bg, bb, ba := resolved_color(L, p, "Color", "SecondaryColor", 48, 48, 52, 255)
    if hovered {
        br, bg, bb, ba = resolved_color(L, p, "HoverColor", "ThirdColor", 58, 58, 63, ba)
    }
    if table_bool(L, p, "BgVisible", true) {
        draw_panel(surface, x, y, width, height, radius, br, bg, bb, ba)
    }

    image_handle := image_from_params(L, p)
    image_size := table_number(L, p, "ImageSize", min(height-8, 18))
    padding := table_number(L, p, "Padding", 8)
    cursor_x := x+padding
    if image_handle != nil {
        src_w := f32(kineffi.Kine_Skia_Image_GetWidth(image_handle))
        src_h := f32(kineffi.Kine_Skia_Image_GetHeight(image_handle))
        kineffi.Kine_Skia_Surface_DrawImageRect(
            surface, image_handle,
            0, 0, src_w, src_h,
            cursor_x, y+(height-image_size)*0.5,
            image_size, image_size, 255,
        )
        cursor_x += image_size + table_number(L, p, "ImageGap", 6)
    }

    value := table_string(L, p, "text", table_string(L, p, "Text", ""))
    font := table_string(L, p, "Font", "")
    size := table_number(L, p, "TextSize", 14)
    tr, tg, tb, ta := resolved_color(L, p, "TextColor", "TextColor", 235, 235, 238, 255)
    draw_text_raw(surface, value, font, cursor_x, centered_baseline(y, height, font, size), size, tr, tg, tb, ta)

    if hovered && ctx != nil && ctx.mouse_clicked {
        call0(L, p, "OnClick")
        call0(L, p, "onClick")
        call0(L, p, "callback")
        consume_click(ctx)
        vm.PushBoolean(L, true)
        return 1
    }

    vm.PushBoolean(L, false)
    return 1
}

text_input :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        vm.PushString(L, "")
        return 1
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width", 160)
    height := table_number(L, p, "height", 30)
    radius := table_number(L, p, "CornerRadius", 4)
    padding := table_number(L, p, "padding", table_number(L, p, "Padding", 8))
    hovered := mouse_in_rect(ctx, x, y, width, height)
    clicked := hovered && ctx != nil && ctx.mouse_clicked

    br, bg, bb, ba := resolved_color(L, p, "Color", "InputColor", 38, 38, 38, 255)
    if clicked || (hovered && ctx != nil && ctx.mouse_down) {
        br, bg, bb, ba = resolved_color(L, p, "FocusColor", "InputFocusColor", 51, 51, 64, 255)
    }
    draw_panel(surface, x, y, width, height, radius, br, bg, bb, ba)

    value := table_string(L, p, "text", "")
    placeholder := table_string(L, p, "placeholder", table_string(L, p, "Placeholder", ""))
    shown := value
    using_placeholder := false
    if shown == "" {
        shown = placeholder
        using_placeholder = true
    }

    font := table_string(L, p, "Font", "")
    size := table_number(L, p, "TextSize", 14)
    tr, tg, tb, ta := resolved_color(L, p, "TextColor", "InputTextColor", 255, 255, 255, 255)
    if using_placeholder {
        tr, tg, tb, ta = resolved_color(L, p, "PlaceholderColor", "InputPlaceholderColor", 128, 128, 128, 255)
    }

    kineffi.Kine_Skia_Surface_Save(surface)
    kineffi.Kine_Skia_Surface_ClipRect(surface, x+padding, y, max(width-padding*2, 0), height)
    draw_text_raw(surface, shown, font, x+padding, centered_baseline(y, height, font, size), size, tr, tg, tb, ta)
    kineffi.Kine_Skia_Surface_Restore(surface)

    if clicked {
        call0(L, p, "OnFocus")
        consume_click(ctx)
    }

    // Full keyboard editing needs renderer TEXT_INPUT/key forwarding. Until then,
    // keep the old call shape and return the current value unchanged.
    vm.PushString(L, value)
    return 1
}

checkbox :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        vm.PushBoolean(L, false)
        return 1
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    size := table_number(L, p, "Size", min(table_number(L, p, "height", 20), 20))
    checked := table_bool(L, p, "Checked", table_bool(L, p, "Value", false))
    hovered := mouse_in_rect(ctx, x, y, size, size)

    br, bg, bb, ba := resolved_color(L, p, "Color", "InputColor", 42, 42, 46, 255)
    if checked {
        br, bg, bb, ba = resolved_color(L, p, "CheckedColor", "AccentColor", 120, 92, 230, 255)
    }
    draw_panel(surface, x, y, size, size, table_number(L, p, "CornerRadius", 4), br, bg, bb, ba)

    if checked {
        cr, cg, cb, ca := resolved_color(L, p, "CheckColor", "TextColor", 255, 255, 255, 255)
        kineffi.Kine_Skia_Surface_DrawLine(surface, x+size*0.22, y+size*0.52, x+size*0.43, y+size*0.72, 2, cr, cg, cb, ca)
        kineffi.Kine_Skia_Surface_DrawLine(surface, x+size*0.43, y+size*0.72, x+size*0.80, y+size*0.29, 2, cr, cg, cb, ca)
    }

    label := table_string(L, p, "Text", table_string(L, p, "text", ""))
    if label != "" {
        font := table_string(L, p, "Font", "")
        text_size := table_number(L, p, "TextSize", 14)
        tr, tg, tb, ta := resolved_color(L, p, "TextColor", "TextColor", 235, 235, 238, 255)
        draw_text_raw(surface, label, font, x+size+8, centered_baseline(y, size, font, text_size), text_size, tr, tg, tb, ta)
    }

    if hovered && ctx != nil && ctx.mouse_clicked && !table_bool(L, p, "Disabled", false) {
        checked = !checked
        call_bool(L, p, "OnChange", checked)
        call_bool(L, p, "onToggle", checked)
        consume_click(ctx)
    }

    vm.PushBoolean(L, checked)
    return 1
}

switch_control :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        vm.PushBoolean(L, false)
        return 1
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width", 38)
    height := table_number(L, p, "height", 20)
    value := table_bool(L, p, "Value", table_bool(L, p, "Checked", false))
    hovered := mouse_in_rect(ctx, x, y, width, height)

    br, bg, bb, ba := resolved_color(L, p, "Color", "InputColor", 60, 60, 65, 255)
    if value {
        br, bg, bb, ba = resolved_color(L, p, "ActiveColor", "AccentColor", 120, 92, 230, 255)
    }
    draw_panel(surface, x, y, width, height, height*0.5, br, bg, bb, ba)

    knob_radius := max(2, height*0.5-3)
    knob_x := x+height*0.5
    if value {
        knob_x = x+width-height*0.5
    }
    kr, kg, kb, ka := resolved_color(L, p, "KnobColor", "TextColor", 245, 245, 247, 255)
    kineffi.Kine_Skia_Surface_DrawCircle(surface, knob_x, y+height*0.5, knob_radius, kr, kg, kb, ka, 0)

    if hovered && ctx != nil && ctx.mouse_clicked && !table_bool(L, p, "Disabled", false) {
        value = !value
        call_bool(L, p, "OnChange", value)
        call_bool(L, p, "onToggle", value)
        consume_click(ctx)
    }

    vm.PushBoolean(L, value)
    return 1
}

progress_bar :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width", 160)
    height := table_number(L, p, "height", 8)
    min_value := table_number(L, p, "Min", 0)
    max_value := table_number(L, p, "Max", 1)
    value := table_number(L, p, "Value", table_number(L, p, "Progress", 0))
    range := max(max_value-min_value, 0.00001)
    alpha := clamp((value-min_value)/range, 0, 1)

    tr, tg, tb, ta := resolved_color(L, p, "TrackColor", "InputColor", 48, 48, 52, 255)
    fr, fg, fb, fa := resolved_color(L, p, "FillColor", "AccentColor", 120, 92, 230, 255)
    radius := table_number(L, p, "CornerRadius", height*0.5)
    draw_panel(surface, x, y, width, height, radius, tr, tg, tb, ta)
    if alpha > 0 {
        draw_panel(surface, x, y, width*alpha, height, min(radius, width*alpha*0.5), fr, fg, fb, fa)
    }
    return 0
}

slider :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        vm.PushNumber(L, 0)
        return 1
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width", 160)
    height := table_number(L, p, "height", 20)
    min_value := table_number(L, p, "Min", table_number(L, p, "Minimum", 0))
    max_value := table_number(L, p, "Max", table_number(L, p, "Maximum", 1))
    value := table_number(L, p, "Value", min_value)
    range := max(max_value-min_value, 0.00001)

    if ctx != nil && ctx.mouse_down && mouse_in_rect(ctx, x, y, width, height) && !table_bool(L, p, "Disabled", false) {
        t := clamp((ctx.mouse_x-x)/max(width, 1), 0, 1)
        value = min_value + t*range
        step := table_number(L, p, "Step", 0)
        if step > 0 {
            value = min_value + f32(math.round(f64((value-min_value)/step)))*step
        }
        value = clamp(value, min_value, max_value)
        call_number(L, p, "OnChange", value)
    }

    alpha := clamp((value-min_value)/range, 0, 1)
    track_height := table_number(L, p, "TrackHeight", 4)
    track_y := y+(height-track_height)*0.5
    tr, tg, tb, ta := resolved_color(L, p, "TrackColor", "InputColor", 60, 60, 65, 255)
    fr, fg, fb, fa := resolved_color(L, p, "FillColor", "AccentColor", 120, 92, 230, 255)
    kr, kg, kb, ka := resolved_color(L, p, "KnobColor", "TextColor", 245, 245, 247, 255)

    draw_panel(surface, x, track_y, width, track_height, track_height*0.5, tr, tg, tb, ta)
    if alpha > 0 {
        draw_panel(surface, x, track_y, width*alpha, track_height, track_height*0.5, fr, fg, fb, fa)
    }
    kineffi.Kine_Skia_Surface_DrawCircle(surface, x+width*alpha, y+height*0.5, table_number(L, p, "KnobRadius", 6), kr, kg, kb, ka, 0)

    vm.PushNumber(L, f64(value))
    return 1
}

spinner :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    size := table_number(L, p, "Size", table_number(L, p, "width", 20))
    r, g, b, a := resolved_color(L, p, "Color", "AccentColor", 120, 92, 230, 255)
    kineffi.Kine_Skia_Surface_DrawArc(
        surface, x, y, size, size,
        table_number(L, p, "StartAngle", -70),
        table_number(L, p, "SweepAngle", 285),
        0,
        r, g, b, a,
        table_number(L, p, "Thickness", 2),
    )
    return 0
}

stepper :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        vm.PushNumber(L, 0)
        return 1
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width", 110)
    height := table_number(L, p, "height", 28)
    value := table_number(L, p, "Value", 0)
    step := table_number(L, p, "Step", 1)
    min_value := table_number(L, p, "Min", -1.0e9)
    max_value := table_number(L, p, "Max", 1.0e9)
    button_width := height

    br, bg, bb, ba := resolved_color(L, p, "Color", "InputColor", 42, 42, 46, 255)
    tr, tg, tb, ta := resolved_color(L, p, "TextColor", "TextColor", 235, 235, 238, 255)
    draw_panel(surface, x, y, width, height, table_number(L, p, "CornerRadius", 5), br, bg, bb, ba)

    font := table_string(L, p, "Font", "")
    size := table_number(L, p, "TextSize", 15)
    draw_text_raw(surface, "−", font, x+button_width*0.36, centered_baseline(y, height, font, size), size, tr, tg, tb, ta)
    draw_text_raw(surface, "+", font, x+width-button_width*0.66, centered_baseline(y, height, font, size), size, tr, tg, tb, ta)

    if ctx != nil && ctx.mouse_clicked {
        if mouse_in_rect(ctx, x, y, button_width, height) {
            value = clamp(value-step, min_value, max_value)
            call_number(L, p, "OnChange", value)
            consume_click(ctx)
        } else if mouse_in_rect(ctx, x+width-button_width, y, button_width, height) {
            value = clamp(value+step, min_value, max_value)
            call_number(L, p, "OnChange", value)
            consume_click(ctx)
        }
    }

    vm.PushNumber(L, f64(value))
    return 1
}

// -----------------------------------------------------------------------------
// Arrays / richer components
// -----------------------------------------------------------------------------

item_text :: proc(L: ^vm.State, item_index: int, fallback: string = "") -> string {
    idx := abs_index(L, item_index)
    t := vm.TypeOf(L, idx)
    if t == .String {
        return vm.ArgString(L, idx)
    }
    if t == .Table {
        return table_string(L, idx, "Text", table_string(L, idx, "text", table_string(L, idx, "Value", fallback)))
    }
    return fallback
}

item_disabled :: proc(L: ^vm.State, item_index: int) -> bool {
    if vm.TypeOf(L, item_index) != .Table {
        return false
    }
    return table_bool(L, item_index, "Disabled", table_bool(L, item_index, "disabled", false))
}

dropdown :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        vm.PushString(L, "")
        return 1
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width", 160)
    height := table_number(L, p, "height", 30)
    current := table_string(L, p, "Value", table_string(L, p, "Selected", table_string(L, p, "text", "")))

    br, bg, bb, ba := resolved_color(L, p, "Color", "InputColor", 42, 42, 46, 255)
    tr, tg, tb, ta := resolved_color(L, p, "TextColor", "InputTextColor", 245, 245, 247, 255)
    draw_panel(surface, x, y, width, height, table_number(L, p, "CornerRadius", 5), br, bg, bb, ba)

    font := table_string(L, p, "Font", "")
    size := table_number(L, p, "TextSize", 14)
    draw_text_raw(surface, current, font, x+8, centered_baseline(y, height, font, size), size, tr, tg, tb, ta)
    draw_text_raw(surface, "⌄", font, x+width-18, centered_baseline(y, height, font, size), size, tr, tg, tb, ta)

    if ctx != nil && ctx.mouse_clicked && mouse_in_rect(ctx, x, y, width, height) {
        field_type := vm.GetField(L, p, "Items")
        if field_type != .Table {
            vm.Pop(L)
            field_type = vm.GetField(L, p, "items")
        }

        if field_type == .Table {
            items_index := abs_index(L, -1)
            count := vm.RawLen(L, items_index)
            if count > 0 {
                current_index := 0
                for i in 1..=count {
                    vm.RawGetIndex(L, items_index, i)
                    text_value := item_text(L, -1, "")
                    if text_value == current {
                        current_index = i
                    }
                    vm.Pop(L)
                }

                next_index := current_index+1
                if next_index > count {
                    next_index = 1
                }
                vm.RawGetIndex(L, items_index, next_index)
                current = item_text(L, -1, current)
                vm.Pop(L)
                call_string(L, p, "OnChange", current)
                call_string(L, p, "onSelect", current)
            }
            vm.Pop(L)
        } else {
            vm.Pop(L)
        }
        consume_click(ctx)
    }

    vm.PushString(L, current)
    return 1
}

tabs :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        vm.PushNil(L)
        vm.PushNumber(L, 0)
        vm.PushNumber(L, 0)
        return 3
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    tab_height := table_number(L, p, "TabHeight", table_number(L, p, "height", 32))
    gap := table_number(L, p, "Gap", 2)
    padding_x := table_number(L, p, "PaddingX", 12)
    current := table_string(L, p, "Value", table_string(L, p, "DefaultValue", ""))
    font := table_string(L, p, "Font", "")
    text_size := table_number(L, p, "TextSize", 14)

    field_type := vm.GetField(L, p, "Items")
    if field_type != .Table {
        vm.Pop(L)
        field_type = vm.GetField(L, p, "items")
    }
    if field_type != .Table {
        vm.Pop(L)
        vm.PushString(L, current)
        vm.PushNumber(L, 0)
        vm.PushNumber(L, f64(tab_height))
        return 3
    }

    items := abs_index(L, -1)
    count := vm.RawLen(L, items)
    cursor_x := x

    for i in 1..=count {
        vm.RawGetIndex(L, items, i)
        item := abs_index(L, -1)
        label := item_text(L, item, "")
        item_value := label
        if vm.TypeOf(L, item) == .Table {
            item_value = table_string(L, item, "Value", label)
        }
        if current == "" && i == 1 {
            current = item_value
        }

        width := measure_text_raw(label, font, text_size)+padding_x*2
        selected := item_value == current
        hovered := mouse_in_rect(ctx, cursor_x, y, width, tab_height) && !item_disabled(L, item)

        br, bg, bb, ba := resolved_color(L, p, "BackgroundColor", "ThirdColor", 30, 30, 33, 255)
        if selected {
            br, bg, bb, ba = resolved_color(L, p, "ActiveColor", "SecondaryColor", 50, 50, 55, 255)
        } else if hovered {
            br, bg, bb, ba = resolved_color(L, p, "HoverColor", "SecondaryColor", 44, 44, 49, 255)
        }
        draw_panel(surface, cursor_x, y, width, tab_height, table_number(L, p, "CornerRadius", 5), br, bg, bb, ba)

        tr, tg, tb, ta := resolved_color(L, p, "TextColor", "SecondaryTextColor", 190, 190, 195, 255)
        if selected {
            tr, tg, tb, ta = resolved_color(L, p, "ActiveTextColor", "TextColor", 245, 245, 247, 255)
        }
        draw_text_raw(surface, label, font, cursor_x+padding_x, centered_baseline(y, tab_height, font, text_size), text_size, tr, tg, tb, ta)

        if hovered && ctx != nil && ctx.mouse_clicked {
            current = item_value
            if vm.TypeOf(L, item) == .Table {
                call0(L, item, "OnClick")
                call0(L, item, "callback")
            }
            call_string(L, p, "OnChange", current)
            consume_click(ctx)
        }

        cursor_x += width+gap
        vm.Pop(L)
    }

    vm.Pop(L)
    vm.PushString(L, current)
    vm.PushNumber(L, f64(max(cursor_x-x-gap, 0)))
    vm.PushNumber(L, f64(tab_height))
    return 3
}

button_group :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        vm.PushNumber(L, 0)
        vm.PushNumber(L, 0)
        return 2
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    item_height := table_number(L, p, "ItemHeight", table_number(L, p, "height", 32))
    padding_x := table_number(L, p, "PaddingX", 12)
    font := table_string(L, p, "Font", "")
    text_size := table_number(L, p, "TextSize", 14)

    t := vm.GetField(L, p, "Items")
    if t != .Table {
        vm.Pop(L)
        vm.PushNumber(L, 0)
        vm.PushNumber(L, f64(item_height))
        return 2
    }

    items := abs_index(L, -1)
    count := vm.RawLen(L, items)
    cursor_x := x
    for i in 1..=count {
        vm.RawGetIndex(L, items, i)
        item := abs_index(L, -1)
        label := item_text(L, item, "")
        width := measure_text_raw(label, font, text_size)+padding_x*2
        if vm.TypeOf(L, item) == .Table {
            width = table_number(L, item, "Width", width)
        }
        disabled := item_disabled(L, item)
        hovered := !disabled && mouse_in_rect(ctx, cursor_x, y, width, item_height)

        br, bg, bb, ba := resolved_color(L, p, "ButtonColor", "BgColor", 40, 40, 44, 255)
        if hovered {
            br, bg, bb, ba = resolved_color(L, p, "HoverColor", "SecondaryColor", 55, 55, 60, 255)
        }
        draw_panel(surface, cursor_x, y, width, item_height, 0, br, bg, bb, ba)

        tr, tg, tb, ta := resolved_color(L, p, "TextColor", "TextColor", 235, 235, 238, 255)
        draw_text_raw(surface, label, font, cursor_x+padding_x, centered_baseline(y, item_height, font, text_size), text_size, tr, tg, tb, ta)

        if hovered && ctx != nil && ctx.mouse_clicked && vm.TypeOf(L, item) == .Table {
            call0(L, item, "OnClick")
            call0(L, item, "callback")
            call_value(L, p, "onSelect", item)
            consume_click(ctx)
        }

        cursor_x += width
        vm.Pop(L)
    }
    vm.Pop(L)

    vm.PushNumber(L, f64(cursor_x-x))
    vm.PushNumber(L, f64(item_height))
    return 2
}

breadcrumb :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        vm.PushNumber(L, 0)
        return 1
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    height := table_number(L, p, "height", 24)
    gap := table_number(L, p, "Gap", 8)
    separator := table_string(L, p, "Separator", "›")
    font := table_string(L, p, "Font", "")
    text_size := table_number(L, p, "TextSize", 14)

    t := vm.GetField(L, p, "Items")
    if t != .Table {
        vm.Pop(L)
        vm.PushNumber(L, 0)
        return 1
    }

    items := abs_index(L, -1)
    count := vm.RawLen(L, items)
    cursor_x := x
    separator_width := measure_text_raw(separator, font, text_size)

    for i in 1..=count {
        vm.RawGetIndex(L, items, i)
        item := abs_index(L, -1)
        label := item_text(L, item, "")
        width := measure_text_raw(label, font, text_size)
        current := i == count
        if vm.TypeOf(L, item) == .Table {
            current = table_bool(L, item, "Current", current)
        }
        hovered := !current && !item_disabled(L, item) && mouse_in_rect(ctx, cursor_x, y, width, height)

        tr, tg, tb, ta := resolved_color(L, p, "LinkColor", "SecondaryTextColor", 170, 170, 180, 255)
        if current {
            tr, tg, tb, ta = resolved_color(L, p, "CurrentColor", "TextColor", 240, 240, 243, 255)
        } else if hovered {
            tr, tg, tb, ta = resolved_color(L, p, "HoverColor", "AccentColor", 140, 115, 240, 255)
        }
        draw_text_raw(surface, label, font, cursor_x, centered_baseline(y, height, font, text_size), text_size, tr, tg, tb, ta)

        if hovered && ctx != nil && ctx.mouse_clicked && vm.TypeOf(L, item) == .Table {
            call0(L, item, "OnClick")
            consume_click(ctx)
        }

        cursor_x += width
        if i < count {
            cursor_x += gap
            sr, sg, sb, sa := resolved_color(L, p, "SeparatorColor", "SecondaryTextColor", 120, 120, 128, 255)
            draw_text_raw(surface, separator, font, cursor_x, centered_baseline(y, height, font, text_size), text_size, sr, sg, sb, sa)
            cursor_x += separator_width+gap
        }
        vm.Pop(L)
    }
    vm.Pop(L)

    vm.PushNumber(L, f64(cursor_x-x))
    return 1
}

context_menu :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) || !table_bool(L, p, "visible", true) {
        return 0
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width", 220)
    item_height := table_number(L, p, "ItemHeight", 26)
    padding := table_number(L, p, "Padding", 4)
    search_enabled := table_bool(L, p, "EnableSearch", false)
    search_height: f32 = 0
    if search_enabled {
        search_height = table_number(L, p, "SearchHeight", 24)+4
    }

    t := vm.GetField(L, p, "items")
    if t != .Table {
        vm.Pop(L)
        t = vm.GetField(L, p, "Items")
    }
    if t != .Table {
        vm.Pop(L)
        return 0
    }

    items := abs_index(L, -1)
    count := vm.RawLen(L, items)
    natural_height := padding*2+search_height+f32(count)*item_height
    max_height := table_number(L, p, "MaxHeight", natural_height)
    height := min(natural_height, max_height)
    radius := table_number(L, p, "CornerRadius", 6)

    if table_bool(L, p, "Shadow", true) {
        sr, sg, sb, sa := resolved_color(L, p, "ShadowColor", "ShadowColor", 0, 0, 0, 110)
        kineffi.Kine_Skia_Surface_DrawUIShadow(surface, x, y, width, height, radius, 4, 0, 3, 9, 1, sr, sg, sb, sa)
    }

    br, bg, bb, ba := resolved_color(L, p, "Color", "SecondaryColor", 38, 38, 42, 255)
    draw_panel(surface, x, y, width, height, radius, br, bg, bb, ba)

    cursor_y := y+padding
    font := table_string(L, p, "Font", "")
    text_size := table_number(L, p, "TextSize", 13)

    if search_enabled {
        input_r, input_g, input_b, input_a := theme_color(L, p, "InputColor", 30, 30, 34, 255)
        search_h := search_height-4
        draw_panel(surface, x+padding, cursor_y, width-padding*2, search_h, 4, input_r, input_g, input_b, input_a)
        pr, pg, pb, pa := theme_color(L, p, "InputPlaceholderColor", 128, 128, 135, 255)
        placeholder := table_string(L, p, "SearchPlaceholder", "Search...")
        draw_text_raw(surface, placeholder, font, x+padding+7, centered_baseline(cursor_y, search_h, font, text_size), text_size, pr, pg, pb, pa)
        cursor_y += search_height
    }

    kineffi.Kine_Skia_Surface_Save(surface)
    kineffi.Kine_Skia_Surface_ClipRoundRect(surface, x, y, width, height, radius, radius)

    for i in 1..=count {
        if cursor_y+item_height > y+height {
            break
        }

        vm.RawGetIndex(L, items, i)
        item := abs_index(L, -1)
        if vm.TypeOf(L, item) != .Table {
            vm.Pop(L)
            cursor_y += item_height
            continue
        }

        separator_item := table_bool(L, item, "separator", false)
        header_item := table_bool(L, item, "header", false)
        disabled := table_bool(L, item, "disabled", false)

        if separator_item {
            sr, sg, sb, sa := resolved_color(L, p, "SeparatorColor", "ThirdColor", 70, 70, 75, 255)
            kineffi.Kine_Skia_Surface_DrawLine(surface, x+8, cursor_y+item_height*0.5, x+width-8, cursor_y+item_height*0.5, 1, sr, sg, sb, sa)
            vm.Pop(L)
            cursor_y += item_height
            continue
        }

        hovered := !disabled && mouse_in_rect(ctx, x+padding, cursor_y, width-padding*2, item_height)
        if hovered {
            hr, hg, hb, ha := resolved_color(L, p, "HoverColor", "ThirdColor", 55, 55, 61, 255)
            draw_panel(surface, x+padding, cursor_y, width-padding*2, item_height, 4, hr, hg, hb, ha)
        }

        label := table_string(L, item, "text", table_string(L, item, "Text", ""))
        tr, tg, tb, ta := resolved_color(L, p, "TextColor", "TextColor", 235, 235, 238, 255)
        if header_item || disabled {
            tr, tg, tb, ta = theme_color(L, p, "SecondaryTextColor", 145, 145, 153, 255)
        }
        if table_bool(L, item, "danger", false) {
            tr, tg, tb, ta = resolved_color(L, p, "DangerColor", "TextColor", 240, 90, 90, 255)
        }

        leading_x := x+padding+8
        kind := table_string(L, item, "kind", "")
        if kind == "checkbox" || kind == "radio" {
            checked := table_bool(L, item, "checked", false)
            if checked {
                kineffi.Kine_Skia_Surface_DrawCircle(surface, leading_x+4, cursor_y+item_height*0.5, 3, tr, tg, tb, ta, 0)
            } else {
                kineffi.Kine_Skia_Surface_DrawCircle(surface, leading_x+4, cursor_y+item_height*0.5, 4, tr, tg, tb, ta, 1)
            }
            leading_x += 16
        }

        draw_text_raw(surface, label, font, leading_x, centered_baseline(cursor_y, item_height, font, text_size), text_size, tr, tg, tb, ta)

        shortcut := table_string(L, item, "shortcut", "")
        if shortcut != "" {
            sw := measure_text_raw(shortcut, font, text_size)
            sr, sg, sb, sa := theme_color(L, p, "SecondaryTextColor", 145, 145, 153, 255)
            draw_text_raw(surface, shortcut, font, x+width-padding-8-sw, centered_baseline(cursor_y, item_height, font, text_size), text_size, sr, sg, sb, sa)
        }

        children_t := vm.GetField(L, item, "children")
        has_children := children_t == .Table && vm.RawLen(L, -1) > 0
        vm.Pop(L)
        if has_children {
            draw_text_raw(surface, "›", font, x+width-padding-16, centered_baseline(cursor_y, item_height, font, text_size), text_size, tr, tg, tb, ta)
        }

        if hovered && ctx != nil && ctx.mouse_clicked {
            if kind == "checkbox" || kind == "radio" {
                new_checked := !table_bool(L, item, "checked", false)
                call_bool(L, item, "onToggle", new_checked)
            }
            call0(L, item, "callback")
            call_value(L, p, "onSelect", item)
            if table_bool(L, p, "CloseOnSelect", true) && !table_bool(L, item, "keepOpen", false) {
                call0(L, p, "onClose")
            }
            consume_click(ctx)
        }

        vm.Pop(L)
        cursor_y += item_height
    }

    kineffi.Kine_Skia_Surface_Restore(surface)
    vm.Pop(L)
    return 0
}

tooltip :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    hover_t := vm.GetField(L, p, "HoverRect")
    if hover_t != .Table {
        vm.Pop(L)
        return 0
    }
    hover := abs_index(L, -1)
    hx := table_number(L, hover, "x")
    hy := table_number(L, hover, "y")
    hw := table_number(L, hover, "width")
    hh := table_number(L, hover, "height")
    is_hovered := mouse_in_rect(ctx, hx, hy, hw, hh)
    vm.Pop(L)
    if !is_hovered {
        return 0
    }

    value := table_string(L, p, "Text", table_string(L, p, "text", ""))
    font := table_string(L, p, "Font", "")
    text_size := table_number(L, p, "TextSize", 12)
    padding := table_number(L, p, "Padding", 6)
    text_width := min(measure_text_raw(value, font, text_size), table_number(L, p, "MaxWidth", 260))
    width := text_width+padding*2
    height := font_line_height(font, text_size)+padding*2
    gap := table_number(L, p, "Gap", 6)
    x := hx
    y := hy+hh+gap

    placement := table_string(L, p, "Placement", "below")
    if placement == "above" {
        y = hy-height-gap
    } else if placement == "right" {
        x = hx+hw+gap
        y = hy
    } else if placement == "left" {
        x = hx-width-gap
        y = hy
    }

    t := vm.GetField(L, p, "Offset")
    if t == .Table {
        x += table_number(L, -1, "x", table_number(L, -1, "X", 0))
        y += table_number(L, -1, "y", table_number(L, -1, "Y", 0))
    }
    vm.Pop(L)

    br, bg, bb, ba := resolved_color(L, p, "Color", "SecondaryColor", 38, 38, 42, 245)
    tr, tg, tb, ta := resolved_color(L, p, "TextColor", "TextColor", 245, 245, 247, 255)
    radius := table_number(L, p, "CornerRadius", 6)
    kineffi.Kine_Skia_Surface_DrawUIShadow(surface, x, y, width, height, radius, 4, 0, 2, 6, 0, 0, 0, 0, 100)
    draw_panel(surface, x, y, width, height, radius, br, bg, bb, ba)
    draw_text_raw(surface, value, font, x+padding, y+padding+font_ascent(font, text_size), text_size, tr, tg, tb, ta)
    return 0
}

color_picker :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width", 180)
    height := table_number(L, p, "height", width)
    strips: int = 32
    strip_width := width/f32(strips)

    kineffi.Kine_Skia_Surface_Save(surface)
    radius := table_number(L, p, "CornerRadius", 6)
    kineffi.Kine_Skia_Surface_ClipRoundRect(surface, x, y, width, height, radius, radius)
    for i in 0..<strips {
        t := f32(i)/f32(max(strips-1, 1))
        r := u8(t*255)
        g := u8((1-t)*255)
        b := u8(190)
        kineffi.Kine_Skia_Surface_DrawRect(surface, x+f32(i)*strip_width, y, strip_width+1, height, r, g, b, 255, 0)
    }
    // Darken towards the bottom to make this useful as a quick picker surface.
    for i in 0..<16 {
        alpha := u8(f32(i)/15.0*180)
        strip_h := height/16
        kineffi.Kine_Skia_Surface_DrawRect(surface, x, y+f32(i)*strip_h, width, strip_h+1, 0, 0, 0, alpha, 0)
    }
    kineffi.Kine_Skia_Surface_Restore(surface)

    if ctx != nil && ctx.mouse_clicked && mouse_in_rect(ctx, x, y, width, height) {
        nx := clamp((ctx.mouse_x-x)/max(width, 1), 0, 1)
        ny := clamp((ctx.mouse_y-y)/max(height, 1), 0, 1)
        cr := nx
        cg := 1-nx
        cb := f32(190.0/255.0)
        brightness := 1-ny*0.72
        cr *= brightness
        cg *= brightness
        cb *= brightness
        call_color(L, p, "OnChange", cr, cg, cb, 1)
        call_color(L, p, "onChanged", cr, cg, cb, 1)
        consume_click(ctx)
    }
    return 0
}

project_card :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width", 260)
    height := table_number(L, p, "height", 80)
    br, bg, bb, ba := resolved_color(L, p, "Color", "SecondaryColor", 40, 40, 44, 255)
    draw_panel(surface, x, y, width, height, table_number(L, p, "CornerRadius", 8), br, bg, bb, ba)

    title := table_string(L, p, "Title", table_string(L, p, "Name", table_string(L, p, "title", "Project")))
    description := table_string(L, p, "Description", table_string(L, p, "description", ""))
    font := table_string(L, p, "Font", "")
    tr, tg, tb, ta := resolved_color(L, p, "TextColor", "TextColor", 242, 242, 245, 255)
    sr, sg, sb, sa := resolved_color(L, p, "SecondaryTextColor", "SecondaryTextColor", 160, 160, 168, 255)
    draw_text_raw(surface, title, font, x+12, y+14+font_ascent(font, 15), 15, tr, tg, tb, ta)
    if description != "" {
        draw_text_raw(surface, description, font, x+12, y+40+font_ascent(font, 12), 12, sr, sg, sb, sa)
    }

    if ctx != nil && ctx.mouse_clicked && mouse_in_rect(ctx, x, y, width, height) {
        call0(L, p, "OnClick")
        call0(L, p, "callback")
        consume_click(ctx)
    }
    return 0
}

graph :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width", 260)
    height := table_number(L, p, "height", 120)
    br, bg, bb, ba := resolved_color(L, p, "Color", "ThirdColor", 25, 25, 28, 255)
    lr, lg, lb, la := resolved_color(L, p, "LineColor", "AccentColor", 130, 100, 240, 255)
    draw_panel(surface, x, y, width, height, table_number(L, p, "CornerRadius", 5), br, bg, bb, ba)

    t := vm.GetField(L, p, "data")
    if t != .Table {
        vm.Pop(L)
        t = vm.GetField(L, p, "Data")
    }
    if t != .Table {
        vm.Pop(L)
        return 0
    }

    data := abs_index(L, -1)
    count := vm.RawLen(L, data)
    if count < 2 {
        vm.Pop(L)
        return 0
    }

    min_v: f32 = 1.0e30
    max_v: f32 = -1.0e30
    for i in 1..=count {
        item_t := vm.RawGetIndex(L, data, i)
        value: f32 = 0
        if item_t == .Number || item_t == .Integer {
            value = f32(vm.ArgNumber(L, -1))
        } else if item_t == .Table {
            value = table_number(L, -1, "Y", table_number(L, -1, "y", table_number(L, -1, "Value", 0)))
        }
        min_v = min(min_v, value)
        max_v = max(max_v, value)
        vm.Pop(L)
    }
    if max_v-min_v < 0.00001 {
        max_v = min_v+1
    }

    previous_x: f32 = 0
    previous_y: f32 = 0
    for i in 1..=count {
        item_t := vm.RawGetIndex(L, data, i)
        value: f32 = 0
        if item_t == .Number || item_t == .Integer {
            value = f32(vm.ArgNumber(L, -1))
        } else if item_t == .Table {
            value = table_number(L, -1, "Y", table_number(L, -1, "y", table_number(L, -1, "Value", 0)))
        }
        px := x+f32(i-1)/f32(count-1)*width
        py := y+height-(value-min_v)/(max_v-min_v)*height
        if i > 1 {
            kineffi.Kine_Skia_Surface_DrawLine(surface, previous_x, previous_y, px, py, table_number(L, p, "Thickness", 2), lr, lg, lb, la)
        }
        previous_x, previous_y = px, py
        vm.Pop(L)
    }
    vm.Pop(L)
    return 0
}

poll :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    p := params_index(L)
    if surface == nil || !vm.IsTable(L, p) {
        return 0
    }

    x := table_number(L, p, "x")
    y := table_number(L, p, "y")
    width := table_number(L, p, "width", 280)
    height := table_number(L, p, "height", 300)
    br, bg, bb, ba := resolved_color(L, p, "Color", "SecondaryColor", 38, 38, 42, 255)
    draw_panel(surface, x, y, width, height, table_number(L, p, "CornerRadius", 8), br, bg, bb, ba)

    question := table_string(L, p, "Question", table_string(L, p, "Title", "Poll"))
    font := table_string(L, p, "Font", "")
    tr, tg, tb, ta := resolved_color(L, p, "TextColor", "TextColor", 240, 240, 243, 255)
    draw_text_raw(surface, question, font, x+12, y+12+font_ascent(font, 15), 15, tr, tg, tb, ta)

    t := vm.GetField(L, p, "Options")
    if t != .Table {
        vm.Pop(L)
        t = vm.GetField(L, p, "options")
    }
    if t != .Table {
        vm.Pop(L)
        return 0
    }

    options := abs_index(L, -1)
    count := vm.RawLen(L, options)
    row_y := y+44
    row_height := table_number(L, p, "ItemHeight", 32)
    for i in 1..=count {
        if row_y+row_height > y+height-8 {
            break
        }
        vm.RawGetIndex(L, options, i)
        option := abs_index(L, -1)
        label := item_text(L, option, "Option")
        hovered := mouse_in_rect(ctx, x+10, row_y, width-20, row_height)
        rr, rg, rb, ra := theme_color(L, p, "ThirdColor", 48, 48, 53, 255)
        if hovered {
            rr, rg, rb, ra = theme_color(L, p, "InputFocusColor", 58, 58, 66, 255)
        }
        draw_panel(surface, x+10, row_y, width-20, row_height, 5, rr, rg, rb, ra)
        draw_text_raw(surface, label, font, x+18, centered_baseline(row_y, row_height, font, 13), 13, tr, tg, tb, ta)

        if hovered && ctx != nil && ctx.mouse_clicked {
            if vm.TypeOf(L, option) == .Table {
                call0(L, option, "OnClick")
                call0(L, option, "callback")
            }
            call_value(L, p, "OnSelect", option)
            consume_click(ctx)
        }
        vm.Pop(L)
        row_y += row_height+6
    }
    vm.Pop(L)
    return 0
}

prompt :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    p := params_index(L)
    ctx := context_from_upvalue(L)
    if surface == nil || ctx == nil || !vm.IsTable(L, p) || !table_bool(L, p, "visible", true) {
        return 0
    }

    width := table_number(L, p, "width", 360)
    height := table_number(L, p, "height", 150)
    x := table_number(L, p, "x", max((ctx.frame_width-width)*0.5, 0))
    y := table_number(L, p, "y", max((ctx.frame_height-height)*0.5, 0))
    radius := table_number(L, p, "CornerRadius", 8)

    br, bg, bb, ba := resolved_color(L, p, "Color", "SecondaryColor", 38, 38, 42, 255)
    kineffi.Kine_Skia_Surface_DrawUIShadow(surface, x, y, width, height, radius, 4, 0, 4, 12, 1, 0, 0, 0, 120)
    draw_panel(surface, x, y, width, height, radius, br, bg, bb, ba)

    title := table_string(L, p, "Title", table_string(L, p, "title", "Prompt"))
    message := table_string(L, p, "Message", table_string(L, p, "Text", ""))
    font := table_string(L, p, "Font", "")
    tr, tg, tb, ta := resolved_color(L, p, "TextColor", "TextColor", 245, 245, 247, 255)
    sr, sg, sb, sa := theme_color(L, p, "SecondaryTextColor", 170, 170, 178, 255)
    draw_text_raw(surface, title, font, x+14, y+14+font_ascent(font, 16), 16, tr, tg, tb, ta)
    if message != "" {
        draw_text_raw(surface, message, font, x+14, y+46+font_ascent(font, 13), 13, sr, sg, sb, sa)
    }

    invoke_rect_callback(L, p, "callback", x+14, y+72, width-28, max(height-86, 0))
    return 0
}

// -----------------------------------------------------------------------------
// Immediate-layout compatibility
// -----------------------------------------------------------------------------

begin_list :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    ctx := context_from_upvalue(L)
    if ctx == nil {
        return 0
    }

    p := params_index(L)
    x, y, width, height: f32 = 0, 0, ctx.frame_width, ctx.frame_height
    spacing: f32 = 4
    padding: f32 = 10

    if vm.IsTable(L, p) {
        x = table_number(L, p, "x", 0)
        y = table_number(L, p, "y", 0)
        width = table_number(L, p, "width", ctx.frame_width)
        height = table_number(L, p, "height", ctx.frame_height)
        spacing = table_number(L, p, "spacing", table_number(L, p, "Spacing", 4))
        padding = table_number(L, p, "padding", table_number(L, p, "Padding", 10))
    }

    ctx.layout = Layout_State{
        active = true,
        x = x+padding,
        y = y+padding,
        width = max(width-padding*2, 0),
        height = max(height-padding*2, 0),
        spacing = spacing,
        padding = padding,
        origin_x = x+padding,
    }
    return 0
}

end_list :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    ctx := context_from_upvalue(L)
    if ctx != nil {
        ctx.layout.active = false
    }
    return 0
}

get_position :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    ctx := context_from_upvalue(L)
    if ctx == nil || !ctx.layout.active {
        vm.PushNumber(L, 0)
        vm.PushNumber(L, 0)
        return 2
    }
    vm.PushNumber(L, f64(ctx.layout.x))
    vm.PushNumber(L, f64(ctx.layout.y))
    return 2
}

get_available_width :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    ctx := context_from_upvalue(L)
    if ctx == nil || !ctx.layout.active {
        vm.PushNumber(L, 0)
        return 1
    }
    used := max(ctx.layout.x-ctx.layout.origin_x, 0)
    vm.PushNumber(L, f64(max(ctx.layout.width-used, 0)))
    return 1
}

advance :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    ctx := context_from_upvalue(L)
    if ctx == nil || !ctx.layout.active {
        return 0
    }
    p := params_index(L)
    height := f32(vm.ArgOptionalNumber(L, p, 0))
    width := f32(vm.ArgOptionalNumber(L, p+1, f64(ctx.layout.width)))
    ctx.layout.prev_x = ctx.layout.x
    ctx.layout.prev_y = ctx.layout.y
    ctx.layout.prev_width = width
    ctx.layout.prev_height = height
    ctx.layout.has_prev = true
    ctx.layout.y += height+ctx.layout.spacing
    return 0
}

same_line :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    ctx := context_from_upvalue(L)
    if ctx == nil || !ctx.layout.active || !ctx.layout.has_prev {
        return 0
    }
    p := params_index(L)
    spacing := f32(vm.ArgOptionalNumber(L, p, f64(ctx.layout.spacing)))
    ctx.layout.x = ctx.layout.prev_x+ctx.layout.prev_width+spacing
    ctx.layout.y = ctx.layout.prev_y
    return 0
}

new_line :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    ctx := context_from_upvalue(L)
    if ctx == nil || !ctx.layout.active {
        return 0
    }
    p := params_index(L)
    extra := f32(vm.ArgOptionalNumber(L, p, 0))
    if ctx.layout.has_prev {
        ctx.layout.y = ctx.layout.prev_y+ctx.layout.prev_height+ctx.layout.spacing+extra
    } else {
        ctx.layout.y += extra
    }
    ctx.layout.x = ctx.layout.origin_x
    return 0
}

spacing :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    ctx := context_from_upvalue(L)
    if ctx == nil || !ctx.layout.active {
        return 0
    }
    p := params_index(L)
    ctx.layout.y += f32(vm.ArgOptionalNumber(L, p, f64(ctx.layout.spacing)))
    return 0
}

dummy :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    ctx := context_from_upvalue(L)
    if ctx == nil || !ctx.layout.active {
        return 0
    }
    p := params_index(L)
    width := f32(vm.ArgOptionalNumber(L, p, 0))
    height := f32(vm.ArgOptionalNumber(L, p+1, 0))
    ctx.layout.prev_x = ctx.layout.x
    ctx.layout.prev_y = ctx.layout.y
    ctx.layout.prev_width = width
    ctx.layout.prev_height = height
    ctx.layout.has_prev = true
    ctx.layout.y += height+ctx.layout.spacing
    return 0
}

indent :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    ctx := context_from_upvalue(L)
    if ctx == nil || !ctx.layout.active {
        return 0
    }
    p := params_index(L)
    amount := f32(vm.ArgOptionalNumber(L, p, 16))
    ctx.layout.origin_x += amount
    ctx.layout.x += amount
    ctx.layout.width = max(ctx.layout.width-amount, 0)
    return 0
}

unindent :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    ctx := context_from_upvalue(L)
    if ctx == nil || !ctx.layout.active {
        return 0
    }
    p := params_index(L)
    amount := f32(vm.ArgOptionalNumber(L, p, 16))
    ctx.layout.origin_x -= amount
    ctx.layout.x = max(ctx.layout.origin_x, 0)
    ctx.layout.width += amount
    return 0
}

separator :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    surface := surface_from_upvalue(L)
    ctx := context_from_upvalue(L)
    if surface == nil || ctx == nil || !ctx.layout.active {
        return 0
    }

    kineffi.Kine_Skia_Surface_DrawLine(
        surface,
        ctx.layout.origin_x, ctx.layout.y,
        ctx.layout.origin_x+ctx.layout.width, ctx.layout.y,
        1,
        75, 75, 82, 255,
    )
    ctx.layout.prev_x = ctx.layout.origin_x
    ctx.layout.prev_y = ctx.layout.y
    ctx.layout.prev_width = ctx.layout.width
    ctx.layout.prev_height = 1
    ctx.layout.has_prev = true
    ctx.layout.y += 1+ctx.layout.spacing
    return 0
}

// -----------------------------------------------------------------------------
// Install / frame lifecycle
// -----------------------------------------------------------------------------

Install :: proc(L: ^vm.State, raw_context: rawptr, renderer_object: ^renderer.RendererObject) {
    ctx := cast(^Context)raw_context
    ctx.renderer = renderer_object

    vm.NewTable(L, 0, 64)

    // Drawing primitives
    set_function(L, "Rectangle", rectangle, ctx)
    set_function(L, "RoundedRectangle", rounded_rectangle, ctx)
    set_function(L, "Squircle", squircle, ctx)
    set_function(L, "Line", line, ctx)
    set_function(L, "Circle", circle, ctx)
    set_function(L, "Oval", oval, ctx)
    set_function(L, "Arc", arc, ctx)
    set_function(L, "Shadow", shadow, ctx)
    set_function(L, "BackdropBlur", backdrop_blur, ctx)
    set_function(L, "Text", text, ctx)
    set_function(L, "Label", text, ctx)
    set_function(L, "TextLabel", text, ctx)
    set_function(L, "Image", image, ctx)

    // Metrics / assets
    set_function(L, "MeasureText", measure_text, ctx)
    set_function(L, "GetFontAscent", get_font_ascent, ctx)
    set_function(L, "GetFontLineHeight", get_font_line_height, ctx)
    set_function(L, "LoadImage", load_image, ctx)
    set_function(L, "CreateImageFromPath", load_image, ctx)
    set_function(L, "DestroyImage", destroy_image, ctx)

    // Containers
    set_function(L, "Widget", widget, ctx)
    set_function(L, "Frame", frame, ctx)
    set_function(L, "EngineUIContainer", frame, ctx)
    set_function(L, "Card", card, ctx)
    set_function(L, "Scroller", scroller, ctx)
    set_function(L, "PanZoomCanvas", pan_zoom_canvas, ctx)

    // Buttons / inputs
    set_function(L, "TextButton", text_button, ctx)
    set_function(L, "Button", text_button, ctx)
    set_function(L, "ImageTextButton", image_text_button, ctx)
    set_function(L, "TextInput", text_input, ctx)
    set_function(L, "TextBox", text_input, ctx)
    set_function(L, "Input", text_input, ctx)
    set_function(L, "Checkbox", checkbox, ctx)
    set_function(L, "CheckBox", checkbox, ctx)
    set_function(L, "Switch", switch_control, ctx)
    set_function(L, "Toggle", switch_control, ctx)
    set_function(L, "Slider", slider, ctx)
    set_function(L, "ProgressBar", progress_bar, ctx)
    set_function(L, "Spinner", spinner, ctx)
    set_function(L, "Stepper", stepper, ctx)
    set_function(L, "Dropdown", dropdown, ctx)
    set_function(L, "ComboBox", dropdown, ctx)

    // Richer compatibility components
    set_function(L, "Tabs", tabs, ctx)
    set_function(L, "TabBar", tabs, ctx)
    set_function(L, "ButtonGroup", button_group, ctx)
    set_function(L, "Breadcrumb", breadcrumb, ctx)
    set_function(L, "ContextMenu", context_menu, ctx)
    set_function(L, "Tooltip", tooltip, ctx)
    set_function(L, "ColorPicker", color_picker, ctx)
    set_function(L, "ProjectCard", project_card, ctx)
    set_function(L, "Graph", graph, ctx)
    set_function(L, "Poll", poll, ctx)
    set_function(L, "Prompt", prompt, ctx)
    set_function(L, "Modal", prompt, ctx)

    // Old immediate-layout API
    set_function(L, "BeginList", begin_list, ctx)
    set_function(L, "EndList", end_list, ctx)
    set_function(L, "GetPosition", get_position, ctx)
    set_function(L, "GetAvailableWidth", get_available_width, ctx)
    set_function(L, "Advance", advance, ctx)
    set_function(L, "SameLine", same_line, ctx)
    set_function(L, "NewLine", new_line, ctx)
    set_function(L, "Spacing", spacing, ctx)
    set_function(L, "Dummy", dummy, ctx)
    set_function(L, "Indent", indent, ctx)
    set_function(L, "Unindent", unindent, ctx)
    set_function(L, "Separator", separator, ctx)
}

Begin_Frame :: proc(raw_context: rawptr, width, height: i32) {
    ctx := cast(^Context)raw_context
    if ctx == nil {
        return
    }

    ctx.frame_width = f32(width)
    ctx.frame_height = f32(height)
    ctx.layout.active = false

    mouse_x, mouse_y: f32
    buttons := sdl3.GetMouseState(&mouse_x, &mouse_y)
    left_down := sdl3.MouseButtonFlag.LEFT in buttons

    ctx.mouse_x = mouse_x
    ctx.mouse_y = mouse_y
    ctx.mouse_clicked = left_down && !ctx.mouse_down
    ctx.mouse_down = left_down
}
