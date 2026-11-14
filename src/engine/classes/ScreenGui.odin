package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import tracy "../util/odin-tracy"
import vm "../vm"

ScreenGui_Class := Class_Info {
	name   = "ScreenGui",
	parent = &Instance_Class,
}

ScreenGui :: struct {
	using object:             Object,
	clip_to_device_safe_area: bool,
	displayorder:             f64,
	ignore_gui_inset:         bool,
	safe_area_compat:         enums.SafeAreaCompatibility,
	screen_insets:            enums.ScreenInsets,
	enabled:                  bool,
	render_on_top:            bool,
	reset_on_spawn:           bool,
	auto_localize:            bool,
	ignore_cursor_inset:      bool,
	render_offset:            datatypes.Vector2,
	size:                     datatypes.Vector2,
}

ScreenGui_Init :: proc() -> ScreenGui {
	return ScreenGui {
		object = Object_Init(&ScreenGui_Class),
		displayorder = 0,
		clip_to_device_safe_area = true,
		ignore_gui_inset = false,
		safe_area_compat = enums.SafeAreaCompatibility.None,
		screen_insets = enums.ScreenInsets.None,
		enabled = true,
		reset_on_spawn = true,
	}
}

ScreenGui_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	ScreenGui := new(ScreenGui)
	ScreenGui^ = ScreenGui_Init()
	ScreenGui.name = "ScreenGui"
	return &ScreenGui.object
}

ScreenGui_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^ScreenGui)object)
}

ScreenGui_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	ScreenGui := cast(^ScreenGui)object
	switch key {
	case "Enabled":
		vm.PushBoolean(L, ScreenGui.enabled)
	case "ResetOnSpawn":
		vm.PushBoolean(L, ScreenGui.reset_on_spawn)
	case "AutoLocalize":
		vm.PushBoolean(L, ScreenGui.auto_localize)
	case "IgnoreCursorInset":
		vm.PushBoolean(L, ScreenGui.ignore_cursor_inset)
	case "DisplayOrder":
		vm.PushNumber(L, ScreenGui.displayorder)
	case "ClipToDeviceSafeArea":
		vm.PushBoolean(L, ScreenGui.clip_to_device_safe_area)
	case "SafeAreaCompatibility":
		_ = enums.Push_Item_By_Value(L, enum_registry, "SafeAreaCompatibility", i64(ScreenGui.safe_area_compat))
	case "ScreenInsets":
		_ = enums.Push_Item_By_Value(L, enum_registry, "ScreenInsets", i64(ScreenGui.screen_insets))
	case "IgnoreGuiInset":
		vm.PushBoolean(L, ScreenGui.ignore_gui_inset)
	case "RenderOnTop":
		vm.PushBoolean(L, ScreenGui.render_on_top)
	case "Size":
		datatypes.Push_Vector2(L, datatype_registry, ScreenGui.size)

	case "RenderOffset":
		datatypes.Push_Vector2(L, datatype_registry, ScreenGui.render_offset)
	case:
		return false
	}
	return true
}

ScreenGui_RenderChild :: proc(child: ^Object, ctx: ^Class_Step_Context) {
	if !Is_A_Class(child, &GuiObject_Class) || child.destroyed {return}
	if !ctx.cache_gui || ctx.gui_recording {
		screen_gui_draw_child(child, ctx)
		return
	}

	gui := cast(^GuiObject)child
	if !gui.visible {
		screen_gui_draw_child(child, ctx)
		return
	}
	x, y, width, height := GuiObject_get_absolute_transform(child, ctx)
	bounds := [4]f32{x, y, width, height}
	revision := gui.draw_revision
	surface := ctx.renderer.SkiaSurface
	if gui.draw_picture != nil &&
	   gui.draw_picture_revision == revision &&
	   gui.draw_picture_rect == bounds {
		kineffi.Kine_Skia_Surface_DrawPicture(surface, gui.draw_picture)
		return
	}
	gui_discard_picture(gui)

	// First draw live after a change. It discovers animated content and
	// effects that need the destination pixels before we start recording.
	parent_dynamic := ctx.gui_dynamic
	ctx.gui_dynamic = false
	recording := gui.draw_observed && !gui.draw_dynamic &&
		gui.draw_observed_revision == revision &&
		gui.draw_picture_rect == bounds &&
		kineffi.Kine_Skia_Surface_BeginPicture(surface) != 0
	ctx.gui_recording = recording
	screen_gui_draw_child(child, ctx)
	ctx.gui_recording = false
	if recording {
		picture := kineffi.Kine_Skia_Surface_EndPicture(surface)
		if picture != nil {
			kineffi.Kine_Skia_Surface_DrawPicture(surface, picture)
			if !ctx.gui_dynamic && gui.draw_revision == revision {
				gui.draw_picture = picture
				gui.draw_picture_revision = revision
			} else {
				kineffi.Kine_Skia_Picture_Destroy(picture)
			}
		}
	}
	gui.draw_observed = true
	gui.draw_observed_revision = revision
	gui.draw_picture_rect = bounds
	gui.draw_dynamic = ctx.gui_dynamic
	ctx.gui_dynamic = parent_dynamic || ctx.gui_dynamic
}

screen_gui_draw_child :: proc(child: ^Object, ctx: ^Class_Step_Context) {
	gui := cast(^GuiObject)child
	previous_transform := ctx.gui_transform

	if gui.visible {
		x, y, width, height := GuiObject_get_absolute_transform(child, ctx)
		ctx.gui_transform = {child, x, y, width, height}
	}
	defer ctx.gui_transform = previous_transform
	shader := UIShader_Find(child)
	rect: guilib.Rect
	shader_ready, transformed: bool
	if shader != nil {
		ctx.gui_dynamic = true
		visible: bool
		rect, visible = GuiObject_get_rect(child, ctx)
		shader_ready = visible && UIShader_Prepare(shader)
		if shader_ready {
			if shader.gui_transform[0] == 0 || shader.gui_transform[1] == 0 {return}
			transformed = UIShader_Push_Transform(shader, ctx.renderer.SkiaSurface, rect)
		}
	}
	defer if transformed {guilib.restore(ctx.renderer.SkiaSurface)}
	rotated := GuiObject_push_rotation(gui, ctx)
	defer if rotated {GuiObject_pop_rotation(ctx)}

	shader_layer := shader_ready && shader.samples_content && UIShader_Apply(shader, ctx, rect, true)
	defer if shader_layer {
		guilib.restore(ctx.renderer.SkiaSurface) // Composite the shaded layer.
		guilib.restore(ctx.renderer.SkiaSurface) // Restore the parent's transform and clip.
	}

	switch {
	case Is_A_Class(child, &ScrollingFrame_Class):
		ScrollingFrame_render(child, ctx)

	case Is_A_Class(child, &TextBox_Class):
		TextBox_render(child, ctx)

	case Is_A_Class(child, &TextLabel_Class):
		TextLabel_render(child, ctx)

	case Is_A_Class(child, &TextButton_Class):
		TextButton_render(child, ctx)

	case Is_A_Class(child, &ImageButton_Class):
		ImageButton_render(child, ctx)

	case Is_A_Class(child, &CanvasGroup_Class):
		CanvasGroup_render(child, ctx)

	case Is_A_Class(child, &Frame_Class):
		Frame_render(child, ctx)

	case Is_A_Class(child, &ImageLabel_Class):
		ImageLabel_render(child, ctx)

	case:
		GuiObject_render(child, ctx)
	}
}

ScreenGui_RenderChildren :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	if len(object.children) == 0 {return}
	tracy.ZoneNC("Render ScreenGui", 0x61AFEF)
	root := ctx.gui_transform.object == nil
	if root {
		x, y, width, height := GuiObject_get_absolute_transform(object, ctx)
		ctx.gui_transform = {object, x, y, width, height}
	}
	defer if root {ctx.gui_transform = {}}
	for child in object.children {
		ScreenGui_RenderChild(child, ctx)
	}
}

ScreenGui_RenderChildren_Visible :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
	viewport: guilib.Rect,
) {
	for child in object.children {
		if !Is_A_Class(child, &GuiObject_Class) {
			continue
		}

		child_rect, child_visible := GuiObject_get_rect(child, ctx)
		if !child_visible {continue}
		shader := UIShader_Find(child)
		if (shader == nil || shader.gui_transform == UI_SHADER_IDENTITY_TRANSFORM) &&
		   (child_rect.x + child_rect.width < viewport.x ||
		   child_rect.x > viewport.x + viewport.width ||
		   child_rect.y + child_rect.height < viewport.y ||
		   child_rect.y > viewport.y + viewport.height) {
			continue
		}

		ScreenGui_RenderChild(child, ctx)
	}
}


ScreenGui_clip_rect :: proc(gui: ^ScreenGui) -> (guilib.Rect, bool) {
	if gui == nil || gui.size.X <= 0 || gui.size.Y <= 0 {
		return {}, false
	}

	return guilib.Rect {
			x = gui.render_offset.X,
			y = gui.render_offset.Y,
			width = gui.size.X,
			height = gui.size.Y,
		},
		true
}

ScreenGui_render :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	gui := cast(^ScreenGui)object

	if !ScreenGui_Is_Visible(gui) || ctx == nil {
		return
	}

	if gui_object_is_overlay_pass(gui) != ctx.gui_overlay {return}

	if ctx.renderer == nil || ctx.renderer.SkiaSurface == nil {return}

	clip, clipped := ScreenGui_clip_rect(gui)
	if clipped {
		guilib.save(ctx.renderer.SkiaSurface)
		guilib.clipRect(ctx.renderer.SkiaSurface, clip)
		ScreenGui_RenderChildren(object, ctx)
		guilib.restore(ctx.renderer.SkiaSurface)
		return
	}

	ScreenGui_RenderChildren(object, ctx)
}

ScreenGui_Is_Visible :: proc(gui: ^ScreenGui) -> bool {
	if gui == nil || gui.destroyed || !gui.enabled {return false}
	registry := gui.signal_registry
	return(
		registry == nil ||
		registry.screen_gui_can_display == nil ||
		registry.screen_gui_can_display(&gui.object, registry.data_model) \
	)
}

ScreenGui_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	screen_gui := cast(^ScreenGui)object

	switch key {
	case "Enabled":
		enabled := vm.ArgBoolean(L, value_index)
		if screen_gui.enabled != enabled {
			screen_gui.enabled = enabled
			Gui_Render_Mark_Dirty()
		}

	case "ResetOnSpawn":
		screen_gui.reset_on_spawn = vm.ArgBoolean(L, value_index)

	case "AutoLocalize":
		screen_gui.auto_localize = vm.ArgBoolean(L, value_index)

	case "IgnoreCursorInset":
		screen_gui.ignore_cursor_inset = vm.ArgBoolean(L, value_index)

	case "DisplayOrder":
		order := vm.ArgNumber(L, value_index)
		if screen_gui.displayorder != order {
			screen_gui.displayorder = order
			Gui_Render_Mark_Dirty()
		}

	case "ClipToDeviceSafeArea":
		screen_gui.clip_to_device_safe_area = vm.ArgBoolean(L, value_index)

	case "Size":
		size := datatypes.Arg_Vector2(L, value_index, datatype_registry)
		if screen_gui.size != size {
			screen_gui.size = size
			Gui_Layout_Mark_Dirty()
		}

	case "RenderOffset":
		offset := datatypes.Arg_Vector2(L, value_index, datatype_registry)
		if screen_gui.render_offset != offset {
			screen_gui.render_offset = offset
			Gui_Layout_Mark_Transform_Dirty()
		}

	case "IgnoreGuiInset":
		screen_gui.ignore_gui_inset = vm.ArgBoolean(L, value_index)

	case "RenderOnTop":
		render_on_top := vm.ArgBoolean(L, value_index)
		if screen_gui.render_on_top != render_on_top {
			screen_gui.render_on_top = render_on_top
			Gui_Render_Mark_Dirty()
		}

	case "SafeAreaCompatibility":
		if enum_registry == nil {
			return false
		}

		screen_gui.safe_area_compat = enums.SafeAreaCompatibility(
			enums.Arg_Item(L, value_index, enum_registry, "SafeAreaCompatibility").value,
		)

	case "ScreenInsets":
		if enum_registry == nil {
			return false
		}

		screen_gui.screen_insets = enums.ScreenInsets(
			enums.Arg_Item(L, value_index, enum_registry, "ScreenInsets").value,
		)

	case:
		return false
	}

	return true
}

ScreenGui_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^ScreenGui)source
	dst := cast(^ScreenGui)destination

	dst.clip_to_device_safe_area = src.clip_to_device_safe_area
	dst.displayorder = src.displayorder
	dst.ignore_gui_inset = src.ignore_gui_inset
	dst.safe_area_compat = src.safe_area_compat
	dst.screen_insets = src.screen_insets
	dst.enabled = src.enabled
	dst.render_on_top = src.render_on_top
	dst.reset_on_spawn = src.reset_on_spawn
	dst.auto_localize = src.auto_localize
	dst.ignore_cursor_inset = src.ignore_cursor_inset
	dst.render_offset = src.render_offset
	dst.size = src.size
}

Register_ScreenGui :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&ScreenGui_Class,
		ScreenGui_construct,
		ScreenGui_destroy,
		get = ScreenGui_get,
		set = ScreenGui_set,
		clone = ScreenGui_clone,
		_step = ScreenGui_render,
		properties = []string {
			"ResetOnSpawn",
			"DisplayOrder",
			"ClipToDeviceSafeArea",
			"SafeAreaCompatibility",
			"ScreenInsets",
			"AutoLocalize",
			"Enabled",
			"IgnoreGuiInset",
			"RenderOnTop",
		},
	)
}
