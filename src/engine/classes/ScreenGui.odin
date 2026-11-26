package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import profiling "../profiling"
import renderer "../renderer"
import tracy "../util/odin-tracy"
import vm "../vm"

ScreenGui_Class := Class_Info {
	name   = "ScreenGui",
	parent = &LayerCollector_Class,
}

ScreenGui :: struct {
	using object:             Object,
	clip_to_device_safe_area: bool,
	displayorder:             f64,
	zindex_behavior:          enums.ZIndexBehavior,
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
		zindex_behavior = .Sibling,
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
	case "ZIndexBehavior":
		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"ZIndexBehavior",
			i64(ScreenGui.zindex_behavior),
		)
	case "ClipToDeviceSafeArea":
		vm.PushBoolean(L, ScreenGui.clip_to_device_safe_area)
	case "SafeAreaCompatibility":
		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"SafeAreaCompatibility",
			i64(ScreenGui.safe_area_compat),
		)
	case "ScreenInsets":
		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"ScreenInsets",
			i64(ScreenGui.screen_insets),
		)
	case "IgnoreGuiInset":
		vm.PushBoolean(L, ScreenGui.ignore_gui_inset)
	case "RenderOnTop":
		vm.PushBoolean(L, ScreenGui.render_on_top)
	case "Size":
		datatypes.Push_Vector2(L, datatype_registry, ScreenGui.size)
	case "AbsoluteSize":
		width, height := gui_layout_last_width, gui_layout_last_height
		if (width <= 0 || height <= 0) && object.signal_registry != nil {
			width, height = renderer.viewport_size(object.signal_registry.renderer)
		}
		ctx := Class_Step_Context {
			viewport_width  = width,
			viewport_height = height,
		}
		_, _, w, h := GuiObject_get_absolute_transform(object, &ctx)
		datatypes.Push_Vector2(L, datatype_registry, {max(0, w), max(0, h)})
	case "AbsolutePosition":
		datatypes.Push_Vector2(L, datatype_registry, ScreenGui.render_offset)

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
	   gui.draw_picture_icon_revision == IconPack_Revision() &&
	   gui.draw_picture_rect == bounds {
		zone := profiling.Begin("GUI Cached Picture", 0x61AFEF)
		kineffi.Kine_Skia_Surface_DrawPicture(surface, gui.draw_picture)
		return
	}
	gui_discard_picture(gui)

	parent_dynamic := ctx.gui_dynamic
	ctx.gui_dynamic = false
	recording :=
		gui.draw_observed &&
		!gui.draw_dynamic &&
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
				gui.draw_picture_icon_revision = IconPack_Revision()
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

	shader_layer :=
		shader_ready && shader.samples_content && UIShader_Apply(shader, ctx, rect, true)
	defer if shader_layer {
		guilib.restore(ctx.renderer.SkiaSurface)
		guilib.restore(ctx.renderer.SkiaSurface)
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

	case Is_A_Class(child, &Sprite2D_Class):
		Sprite2D_render(child, ctx)

	case Is_A_Class(child, &Shape2D_Class):
		Shape2D_render(child, ctx)

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
	children, allocated := gui_children_in_draw_order(object)
	defer if allocated {delete(children)}
	for child in children {
		if ctx.world2d_scene {
			screen_gui_render_world_child(child, ctx)
		} else {
			ScreenGui_RenderChild(child, ctx)
		}
	}
}


screen_gui_render_world_child :: proc(child: ^Object, ctx: ^Class_Step_Context) {
	if child == nil || child.destroyed {return}
	if Is_A_Class(child, &World2D_Class) && !(cast(^World2D)child).enabled {return}
	if Is_A_Class(child, &ScreenGui_Class) || Is_A_Class(child, &SurfaceGui_Class) {return}
	if Is_A_Class(child, &GuiObject_Class) {
		ScreenGui_RenderChild(child, ctx)
		return
	}

	if Is_A_Class(child, &Folder_Class) ||
	   Is_A_Class(child, &World2D_Class) ||
	   Is_A_Class(child, &RigidBody2D_Class) ||
	   Is_A_Class(child, &Model_Class) {
		for descendant in child.children {screen_gui_render_world_child(descendant, ctx)}
	}
}

ScreenGui_RenderChildren_Visible :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
	viewport: guilib.Rect,
) {
	children, allocated := gui_children_in_draw_order(object)
	defer if allocated {delete(children)}
	for child in children {
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


screen_gui_is_editor_ui :: proc(object: ^Object) -> bool {
	for parent := object.parent; parent != nil; parent = parent.parent {
		if parent.name == "CoreGui" {return true}
	}
	return false
}

ScreenGui_Render_After_Editor_2D :: proc(
	registry: ^Registry,
	L: ^vm.State,
	width, height: i32,
	dt: f32,
	cache_gui: bool,
) {
	if registry == nil || registry.renderer == nil || L == nil {return}
	descriptor := Find_Class(registry, "ScreenGui")
	if descriptor == nil {return}
	Sort_ScreenGui_Instances(descriptor)
	ctx := Class_Step_Context {
		L                        = L,
		renderer                 = registry.renderer,
		data_model               = registry.data_model,
		viewport_width           = width,
		viewport_height          = height,
		delta_time               = dt,
		cache_gui                = cache_gui,
		editor_2d_gui_foreground = true,
	}
	for object in descriptor.instances {
		if object != nil && !object.destroyed {ScreenGui_render(object, &ctx)}
	}
}

ScreenGui_render :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	gui := cast(^ScreenGui)object

	if !ScreenGui_Is_Visible(gui) || ctx == nil {
		return
	}

	if gui_object_is_overlay_pass(gui) != ctx.gui_overlay {return}
	if ctx.editor_2d_gui_background && !screen_gui_is_editor_ui(object) {return}
	if ctx.editor_2d_gui_foreground && screen_gui_is_editor_ui(object) {return}

	if ctx.renderer == nil || ctx.renderer.SkiaSurface == nil {return}

	zone := profiling.Begin("GUI Screen Draw", 0x61AFEF)
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

Render_VR_ScreenGuis :: proc(registry: ^Registry, L: ^vm.State, width, height: i32) {
	if registry == nil || L == nil || registry.renderer == nil {return}
	descriptor := Find_Class(registry, "ScreenGui")
	if descriptor == nil {return}
	Sort_ScreenGui_Instances(descriptor)
	ctx := Class_Step_Context {
		L               = L,
		renderer        = registry.renderer,
		data_model      = registry.data_model,
		viewport_width  = width,
		viewport_height = height,
		delta_time      = 0,
		cache_gui       = false,
	}
	overlays := [?]bool{false, true}
	for overlay in overlays {
		ctx.gui_overlay = overlay
		for object in descriptor.instances {
			if object != nil && !object.destroyed {ScreenGui_render(object, &ctx)}
		}
	}
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

	case "ZIndexBehavior":
		if enum_registry == nil {return false}
		screen_gui.zindex_behavior = enums.ZIndexBehavior(
			enums.Arg_Item(L, value_index, enum_registry, "ZIndexBehavior").value,
		)
		Gui_Render_Mark_Dirty()

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
	dst.zindex_behavior = src.zindex_behavior
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
			"ZIndexBehavior",
			"ClipToDeviceSafeArea",
			"SafeAreaCompatibility",
			"ScreenInsets",
			"AutoLocalize",
			"Enabled",
			"IgnoreGuiInset",
			"RenderOnTop",
			"AbsolutePosition",
			"AbsoluteSize",
		},
	)
}
