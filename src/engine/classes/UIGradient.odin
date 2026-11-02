package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"
import "core:fmt"
import "core:math"
import "core:strings"

UIGradient_Class := Class_Info {
	name   = "UIGradient",
	parent = &Instance_Class,
}

UIGradient :: struct {
	using object:                   Object,
	color:                          datatypes.ColorSequence,
	rotation:                       f64,
	transparency:                   datatypes.NumberSequence,
	offset:                         datatypes.Vector2,
	enabled:                        bool,
	shader:                         ^kineffi.KineSkiaRuntimeShader,
	color_uniforms, alpha_uniforms: []f32,
	color_count, alpha_count:       int,
	dirty:                          bool,
}

UIGradient_Init :: proc() -> UIGradient {
	return UIGradient {
		object = Object_Init(&UIGradient_Class),
		color = datatypes.ColorSequence_New(datatypes.Color3{1, 1, 1}),
		rotation = 0,
		transparency = datatypes.NumberSequence_New(0),
		offset = datatypes.Vector2{0, 0},
		enabled = true,
		dirty = true,
	}
}

UIGradient_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	gradient := new(UIGradient)
	gradient^ = UIGradient_Init()
	gradient.name = "UIGradient"
	return &gradient.object
}

UIGradient_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	gradient := cast(^UIGradient)object
	if gradient.shader != nil {kineffi.Kine_Skia_RuntimeShader_Destroy(gradient.shader)}
	delete(gradient.color_uniforms)
	delete(gradient.alpha_uniforms)
	datatypes.ColorSequence_Destroy(gradient.color)
	datatypes.NumberSequence_Destroy(gradient.transparency)
	Object_Destroy(object)
	free(gradient)
}

UIGradient_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	gradient := cast(^UIGradient)object
	switch key {
	case "Enabled":
		vm.PushBoolean(L, gradient.enabled)
	case "Color":
		if datatype_registry == nil {return false}
		datatypes.Push_ColorSequence(L, datatype_registry, gradient.color)
	case "Rotation":
		vm.PushNumber(L, gradient.rotation)
	case "Transparency":
		if datatype_registry == nil {return false}
		datatypes.Push_NumberSequence(L, datatype_registry, gradient.transparency)
	case "Offset":
		if datatype_registry == nil {return false}
		datatypes.Push_Vector2(L, datatype_registry, gradient.offset)
	case:
		return false
	}
	return true
}

UIGradient_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	gradient := cast(^UIGradient)object
	switch key {
	case "Enabled":
		gradient.enabled = vm.ArgBoolean(L, value_index)
	case "Color":
		if datatype_registry == nil {return false}
		next := datatypes.Arg_ColorSequence(L, value_index, datatype_registry)
		datatypes.ColorSequence_Destroy(gradient.color)
		gradient.color = datatypes.ColorSequence_Clone(next)
		gradient.dirty = true
	case "Rotation":
		gradient.rotation = vm.ArgNumber(L, value_index)
	case "Transparency":
		if datatype_registry == nil {return false}
		next := datatypes.Arg_NumberSequence(L, value_index, datatype_registry)
		datatypes.NumberSequence_Destroy(gradient.transparency)
		gradient.transparency = datatypes.NumberSequence_Clone(next)
		gradient.dirty = true
	case "Offset":
		if datatype_registry == nil {return false}
		gradient.offset = datatypes.Arg_Vector2(L, value_index, datatype_registry)
	case:
		return false
	}
	return true
}

UIGradient_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UIGradient)source
	dst := cast(^UIGradient)destination
	datatypes.ColorSequence_Destroy(dst.color)
	datatypes.NumberSequence_Destroy(dst.transparency)
	dst.color = datatypes.ColorSequence_Clone(src.color)
	dst.rotation = src.rotation
	dst.transparency = datatypes.NumberSequence_Clone(src.transparency)
	dst.offset = src.offset
	dst.enabled = src.enabled
	dst.dirty = true
}

Register_UIGradient :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UIGradient_Class,
		UIGradient_construct,
		UIGradient_destroy,
		get = UIGradient_get,
		set = UIGradient_set,
		clone = UIGradient_clone,
		properties = []string{"Enabled", "Color", "Rotation", "Transparency", "Offset"},
	)
}

ui_gradient_prepare :: proc(gradient: ^UIGradient) -> bool {
	cc, ac := len(gradient.color.Keypoints), len(gradient.transparency.Keypoints)
	if cc < 2 || ac < 2 {return false}
	if gradient.shader == nil || cc != gradient.color_count || ac != gradient.alpha_count {
		if gradient.shader != nil {kineffi.Kine_Skia_RuntimeShader_Destroy(gradient.shader)}
		source := strings.clone_to_cstring(
			fmt.tprintf(
				`
uniform float4 colors[%d];
uniform float2 alphas[%d];
uniform float4 axis;
uniform float4 base;
half4 main(float2 p) {{
    float t = clamp(0.5 + dot(p-axis.xy, axis.zw), 0.0, 1.0);
    float3 color = colors[0].yzw;
    for (int i=1; i<%d; ++i) {{
        float f = clamp((t-colors[i-1].x)/max(colors[i].x-colors[i-1].x,0.000001),0.0,1.0);
        color = mix(color,colors[i].yzw,f);
    }}
    float opacity = alphas[0].y;
    for (int i=1; i<%d; ++i) {{
        float f = clamp((t-alphas[i-1].x)/max(alphas[i].x-alphas[i-1].x,0.000001),0.0,1.0);
        opacity = mix(opacity,alphas[i].y,f);
    }}
    float alpha = clamp(opacity*base.a,0.0,1.0);
    return half4(color*base.rgb*alpha,alpha);
}}`,
				cc,
				ac,
				cc,
				ac,
			),
		)
		defer delete(source)
		gradient.shader = kineffi.Kine_Skia_RuntimeShader_Create(source)
		if gradient.shader == nil {
			fmt.eprintln("UIGradient shader:", kineffi.Kine_Skia_RuntimeShader_GetLastError())
			return false
		}
		delete(gradient.color_uniforms)
		delete(gradient.alpha_uniforms)
		gradient.color_uniforms = make([]f32, cc * 4)
		gradient.alpha_uniforms = make([]f32, ac * 2)
		gradient.color_count, gradient.alpha_count = cc, ac
		gradient.dirty = true
	}
	if gradient.dirty {
		for key, i in gradient.color.Keypoints {
			gradient.color_uniforms[i * 4 + 0] = key.Time
			gradient.color_uniforms[i * 4 + 1] = f32(key.Value.R)
			gradient.color_uniforms[i * 4 + 2] = f32(key.Value.G)
			gradient.color_uniforms[i * 4 + 3] = f32(key.Value.B)
		}
		for key, i in gradient.transparency.Keypoints {
			gradient.alpha_uniforms[i * 2 + 0] = key.Time
			gradient.alpha_uniforms[i * 2 + 1] = clamp(1 - key.Value, 0, 1)
		}
		_ = kineffi.Kine_Skia_RuntimeShader_SetUniform(
			gradient.shader,
			"colors",
			raw_data(gradient.color_uniforms),
			i32(len(gradient.color_uniforms)),
		)
		_ = kineffi.Kine_Skia_RuntimeShader_SetUniform(
			gradient.shader,
			"alphas",
			raw_data(gradient.alpha_uniforms),
			i32(len(gradient.alpha_uniforms)),
		)
		gradient.dirty = false
	}
	return true
}

UIGradient_Draw_Background :: proc(
	gui: ^GuiObject,
	ctx: ^Class_Step_Context,
	rect: guilib.Rect,
	shape: Gui_Shape,
) -> bool {
	gradient: ^UIGradient
	for child in gui.children {
		if !child.destroyed &&
		   Is_A_Class(child, &UIGradient_Class) &&
		   (cast(^UIGradient)child).enabled {
			gradient = cast(^UIGradient)child
			break
		}
	}
	if gradient == nil ||
	   rect.width <= 0 ||
	   rect.height <= 0 ||
	   !ui_gradient_prepare(gradient) {return false}
	angle := math.to_radians(gradient.rotation)
	dx, dy := f32(math.cos(angle)), f32(math.sin(angle))
	span := max(math.abs(dx) * rect.width + math.abs(dy) * rect.height, f32(0.0001))
	axis := [4]f32 {
		rect.x + rect.width * (0.5 + f32(gradient.offset.X)),
		rect.y + rect.height * (0.5 + f32(gradient.offset.Y)),
		dx / span,
		dy / span,
	}
	base := [4]f32 {
		f32(gui.bg_color.R),
		f32(gui.bg_color.G),
		f32(gui.bg_color.B),
		1 - f32(gui.bg_transparency),
	}
	_ = kineffi.Kine_Skia_RuntimeShader_SetUniform(gradient.shader, "axis", &axis[0], 4)
	_ = kineffi.Kine_Skia_RuntimeShader_SetUniform(gradient.shader, "base", &base[0], 4)
	surface := ctx.renderer.SkiaSurface
	guilib.save(surface)
	switch shape.kind {
	case .Squircle:
		guilib.clipSquircleCorners(
			surface,
			rect,
			shape.tl,
			shape.tr,
			shape.br,
			shape.bl,
			shape.exponent,
		)
	case .Round:
		guilib.clipRoundedRect(surface, rect, shape.radius)
	case .None:
		guilib.clipRect(surface, rect)
	}
	kineffi.Kine_Skia_Surface_DrawRuntimeShaderRect(
		surface,
		gradient.shader,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
	)
	guilib.restore(surface)
	return true
}
