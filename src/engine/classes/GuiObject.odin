package classes

import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"

GuiObject_Class := Class_Info{
	name   = "GuiObject",
	parent = &Instance_Class,
}

GuiObject :: struct {
	using object: Object,

	bg_transparency: f64,
	bg_color: datatypes.Color3,
	active: bool,
	border_mode: enums.BorderMode,
	clips_descendants: bool,
	gui_state: enums.GuiState,
	input_sink: bool,
	position: datatypes.UDim2,
	selectable: bool,
	size: datatypes.UDim2,
	visible: bool,
	zindex: i32,
	anchorpoint: datatypes.Vector2,
	border_size_pixels: i32,

	absolute_position: datatypes.Vector2,
	absolute_size: datatypes.Vector2,
}

GuiObject_Init :: proc() -> GuiObject {
	return GuiObject{
		object = Object_Init(&GuiObject_Class),
		position = datatypes.UDim2{0, 0, 0, 0},
		bg_color = datatypes.Color3{R = 1, G = 1, B = 1},
		size = datatypes.UDim2{0, 100, 0, 100},
		anchorpoint = datatypes.Vector2{0, 0},
		active = false,
		selectable = true,
		visible = true,
		zindex = 0,
		border_size_pixels = 0,
		input_sink = false,
		gui_state = enums.GuiState.Idle,
		bg_transparency = 0,
		absolute_position = datatypes.Vector2{0, 0},
		absolute_size = datatypes.Vector2{0, 0},
	}
}

GuiObject_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	gui_object := new(GuiObject)
	gui_object^ = GuiObject_Init()
	gui_object.name = "GuiObject"
	return &gui_object.object
}

GuiObject_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^GuiObject)object)
}

GuiObject_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	gui_object := cast(^GuiObject)object

	switch key {
	case "Active":
		vm.PushBoolean(L, gui_object.active)
	case "BackgroundTransparency":
		vm.PushNumber(L, gui_object.bg_transparency)
	case "ClipsDescendants":
		vm.PushBoolean(L, gui_object.clips_descendants)
	case "InputSink":
		vm.PushBoolean(L, gui_object.input_sink)
	case "Selectable":
		vm.PushBoolean(L, gui_object.selectable)
	case "Visible":
		vm.PushBoolean(L, gui_object.visible)
	case "ZIndex":
		vm.PushNumber(L, f64(gui_object.zindex))
	case "BorderSizePixel":
		vm.PushNumber(L, f64(gui_object.border_size_pixels))
	case "BorderMode":
		if enum_registry == nil { return false }
		_ = enums.Push_Item_By_Value(L, enum_registry, "BorderMode", i64(gui_object.border_mode))
	case "GuiState":
		if enum_registry == nil { return false }
		_ = enums.Push_Item_By_Value(L, enum_registry, "GuiState", i64(gui_object.gui_state))
	case "BackgroundColor3":
		if datatype_registry == nil { return false }
		datatypes.Push_Color3(L, datatype_registry, gui_object.bg_color)
	case "Position":
		if datatype_registry == nil { return false }
		datatypes.Push_UDim2(L, datatype_registry, gui_object.position)
	case "Size":
		if datatype_registry == nil { return false }
		datatypes.Push_UDim2(L, datatype_registry, gui_object.size)
	case "AnchorPoint":
		if datatype_registry == nil { return false }
		datatypes.Push_Vector2(L, datatype_registry, gui_object.anchorpoint)
	case "AbsolutePosition":
		if datatype_registry == nil { return false }
		datatypes.Push_Vector2(L, datatype_registry, gui_object.absolute_position)
	case "AbsoluteSize":
		if datatype_registry == nil { return false }
		datatypes.Push_Vector2(L, datatype_registry, gui_object.absolute_size)
	case:
		return false
	}

	return true
}

GuiObject_get_absolute_transform :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) -> (x, y, width, height: f32) {
	if object == nil {
		return 0, 0, f32(ctx.viewport_width), f32(ctx.viewport_height)
	}

	if !Is_A(object, "GuiObject") {
		return GuiObject_get_absolute_transform(object.parent, ctx)
	}

	parent_x, parent_y, parent_width, parent_height := GuiObject_get_absolute_transform(object.parent, ctx)
	gui := cast(^GuiObject)object

	width = gui.size.X_Scale*parent_width + gui.size.X_Offset
	height = gui.size.Y_Scale*parent_height + gui.size.Y_Offset
	x = parent_x + gui.position.X_Scale*parent_width + gui.position.X_Offset - gui.anchorpoint.X*width
	y = parent_y + gui.position.Y_Scale*parent_height + gui.position.Y_Offset - gui.anchorpoint.Y*height

	return x, y, width, height
}

GuiObject_get_rect :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) -> (guilib.Rect, bool) {
	gui := cast(^GuiObject)object

	if !gui.visible {
		return guilib.Rect{}, false
	}

	if ctx == nil || ctx.renderer == nil || ctx.renderer.SkiaSurface == nil {
		return guilib.Rect{}, false
	}

	x, y, width, height := GuiObject_get_absolute_transform(object, ctx)

	return guilib.Rect{
		x = x,
		y = y,
		width = width,
		height = height,
		color = gui.bg_color,
		bgTransparency = f32(gui.bg_transparency),
	}, true
}

gui_resolve_udim :: proc(value: datatypes.UDim, basis: f32) -> f32 {
	return value.Scale*basis + value.Offset
}

gui_corner_radius :: proc(corner_object: ^Object, rect: guilib.Rect) -> f32 {
	if corner_object == nil {
		return 0
	}

	corner := cast(^UICorner)corner_object
	short_edge := min(rect.width, rect.height)
	radius := gui_resolve_udim(corner.corner_radius, short_edge)
	return clamp(radius, f32(0), short_edge*0.5)
}

gui_render_children :: proc(
	gui: ^GuiObject,
	object: ^Object,
	ctx: ^Class_Step_Context,
	rect: guilib.Rect,
	corner_radius: f32,
) {
	if !gui.clips_descendants {
		ScreenGui_RenderChildren(object, ctx)
		return
	}

	guilib.save(ctx.renderer.SkiaSurface)
	if corner_radius > 0 {
		guilib.clipRoundedRect(ctx.renderer.SkiaSurface, rect, corner_radius)
	} else {
		guilib.clipRect(ctx.renderer.SkiaSurface, rect)
	}
	ScreenGui_RenderChildren(object, ctx)
	guilib.restore(ctx.renderer.SkiaSurface)
}

GuiObject_render :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) {
	gui := cast(^GuiObject)object

	rect, visible := GuiObject_get_rect(object, ctx)
	if !visible {
		return
	}

	gui.absolute_position = datatypes.Vector2{rect.x, rect.y}
	gui.absolute_size = datatypes.Vector2{rect.width, rect.height}

	corner_object := Find_First_Child_Of_Class(object, "UICorner")
	shadow_object := Find_First_Child_Of_Class(object, "UIShadow")
	backdrop_object := Find_First_Child_Of_Class(object, "UIBackdrop")
	stroke_object := Find_First_Child_Of_Class(object, "UIStroke")

	corner_radius := gui_corner_radius(corner_object, rect)

	if shadow_object != nil {
		shadow := cast(^UIShadow)shadow_object
		if shadow.enabled {
			short_edge := min(rect.width, rect.height)
			offset_x := shadow.offset.X_Scale*rect.width + shadow.offset.X_Offset
			offset_y := shadow.offset.Y_Scale*rect.height + shadow.offset.Y_Offset
			spread_x := shadow.spread.X_Scale*rect.width + shadow.spread.X_Offset
			spread_y := shadow.spread.Y_Scale*rect.height + shadow.spread.Y_Offset

			params := guilib.ShadowParams{
				offsetX = offset_x,
				offsetY = offset_y,
				blurSigma = max(f32(0), gui_resolve_udim(shadow.blur_radius, short_edge)),
				spread = max(f32(0), (spread_x+spread_y)*0.5),
				color = shadow.color,
				alpha = 1-f32(shadow.transparency),
			}

			guilib.drawShadow(
				ctx.renderer.SkiaSurface,
				rect,
				corner_radius,
				f32(shadow.exponent),
				params,
			)
		}
	}

	if backdrop_object != nil {
		backdrop := cast(^UIBackdrop)backdrop_object
		if backdrop.enabled && backdrop.blur_radius > 0 {
			backdrop_rect := rect
			backdrop_rect.color = backdrop.tint_color
			backdrop_rect.bgTransparency = f32(backdrop.tint_transparency)

			guilib.drawBackdropBlur(
				ctx.renderer.SkiaSurface,
				backdrop_rect,
				corner_radius,
				f32(backdrop.blur_radius),
			)
		}
	}

	if gui.bg_transparency < 1 {
		if corner_radius > 0 {
			guilib.drawRoundedRect(ctx.renderer.SkiaSurface, rect, corner_radius)
		} else {
			guilib.drawRect(ctx.renderer.SkiaSurface, rect)
		}
	}

	gui_render_children(gui, object, ctx, rect, corner_radius)

	if stroke_object != nil {
		stroke := cast(^UIStroke)stroke_object
		if stroke.enabled && stroke.thickness > 0 && stroke.transparency < 1 {
			stroke_rect := rect
			stroke_rect.color = stroke.color
			stroke_rect.bgTransparency = f32(stroke.transparency)

			if corner_radius > 0 {
				guilib.drawRoundedRectStroke(
					ctx.renderer.SkiaSurface,
					stroke_rect,
					corner_radius,
					f32(stroke.thickness),
				)
			} else {
				guilib.drawRectStroke(
					ctx.renderer.SkiaSurface,
					stroke_rect,
					f32(stroke.thickness),
				)
			}
		}
	}
}

GuiObject_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	gui_object := cast(^GuiObject)object

	switch key {
	case "Active":
		gui_object.active = vm.ArgBoolean(L, value_index)
	case "BackgroundTransparency":
		gui_object.bg_transparency = clamp(vm.ArgNumber(L, value_index), 0.0, 1.0)
	case "ClipsDescendants":
		gui_object.clips_descendants = vm.ArgBoolean(L, value_index)
	case "InputSink":
		gui_object.input_sink = vm.ArgBoolean(L, value_index)
	case "Selectable":
		gui_object.selectable = vm.ArgBoolean(L, value_index)
	case "Visible":
		gui_object.visible = vm.ArgBoolean(L, value_index)
	case "ZIndex":
		gui_object.zindex = i32(vm.ArgNumber(L, value_index))
	case "BorderSizePixel":
		gui_object.border_size_pixels = i32(vm.ArgNumber(L, value_index))
	case "BorderMode":
		if enum_registry == nil { return false }
		gui_object.border_mode = enums.BorderMode(enums.Arg_Item(L, value_index, enum_registry, "BorderMode").value)
	case "BackgroundColor3":
		if datatype_registry == nil { return false }
		gui_object.bg_color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Position":
		if datatype_registry == nil { return false }
		gui_object.position = datatypes.Arg_UDim2(L, value_index, datatype_registry)
	case "Size":
		if datatype_registry == nil { return false }
		gui_object.size = datatypes.Arg_UDim2(L, value_index, datatype_registry)
	case "AnchorPoint":
		if datatype_registry == nil { return false }
		gui_object.anchorpoint = datatypes.Arg_Vector2(L, value_index, datatype_registry)
	case "AbsolutePosition":
		_ = vm.RaiseError(L, "AbsolutePosition cannot be changed")
	case "AbsoluteSize":
		_ = vm.RaiseError(L, "AbsoluteSize cannot be changed")
	case:
		return false
	}

	return true
}

GuiObject_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^GuiObject)source
	dst := cast(^GuiObject)destination

	dst.bg_transparency   = src.bg_transparency
	dst.bg_color          = src.bg_color
	dst.active            = src.active
	dst.border_mode       = src.border_mode
	dst.clips_descendants = src.clips_descendants
	dst.input_sink        = src.input_sink
	dst.position          = src.position
	dst.selectable        = src.selectable
	dst.size              = src.size
	dst.visible           = src.visible
	dst.zindex            = src.zindex
	dst.anchorpoint       = src.anchorpoint
	dst.border_size_pixels = src.border_size_pixels

	// Don't copy:
	// absolute_position / absolute_size
	// They're calculated by layout.
}

Register_GuiObject :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&GuiObject_Class,
		GuiObject_construct,
		GuiObject_destroy,
		get = GuiObject_get,
		set = GuiObject_set,
		clone = GuiObject_clone,
	)
}
