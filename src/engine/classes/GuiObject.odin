package classes

import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import signals "../signals"
import vm "../vm"
import "core:fmt"
import sdl3 "vendor:sdl3"

GuiObject_Class := Class_Info {
	name   = "GuiObject",
	parent = &Instance_Class,
}

GuiObject :: struct {
	using object:             Object,
	bg_transparency:          f64,
	bg_color:                 datatypes.Color3,
	active:                   bool,
	border_mode:              enums.BorderMode,
	clips_descendants:        bool,
	gui_state:                enums.GuiState,
	input_sink:               bool,
	position:                 datatypes.UDim2,
	selectable:               bool,
	size:                     datatypes.UDim2,
	visible:                  bool,
	zindex:                   i32,
	anchorpoint:              datatypes.Vector2,
	border_size_pixels:       i32,
	absolute_position:        datatypes.Vector2,
	absolute_size:            datatypes.Vector2,
	input_began:              ^signals.Signal,
	input_changed:            ^signals.Signal,
	input_ended:              ^signals.Signal,
	mouse_enter:              ^signals.Signal,
	mouse_leave:              ^signals.Signal,
	mouse_moved:              ^signals.Signal,
	mouse_wheel_forward:      ^signals.Signal,
	mouse_wheel_backward:     ^signals.Signal,
	mouse_inside:             bool,
	mouse_input_down:         [3]bool,
	layout_order:             i32,
	layout_override_active:   bool,
	layout_override_position: datatypes.Vector2,
	layout_override_size_active: bool,
	layout_override_size:        datatypes.Vector2,
	hovered_gui: ^GuiObject,
	hovered_button: ^GuiButton,
}

GuiObject_Init :: proc() -> GuiObject {
	return GuiObject {
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

GuiObject_ensure_signals :: proc(gui: ^GuiObject) {
	if gui == nil ||
	   gui.object.signal_registry == nil ||
	   gui.object.signal_registry.signal_registry == nil {
		return
	}

	registry := gui.object.signal_registry.signal_registry

	if gui.input_began == nil {
		gui.input_began = signals.Create(registry)
	}

	if gui.input_changed == nil {
		gui.input_changed = signals.Create(registry)
	}

	if gui.input_ended == nil {
		gui.input_ended = signals.Create(registry)
	}

	if gui.mouse_enter == nil {
		gui.mouse_enter = signals.Create(registry)
	}

	if gui.mouse_leave == nil {
		gui.mouse_leave = signals.Create(registry)
	}

	if gui.mouse_moved == nil {
		gui.mouse_moved = signals.Create(registry)
	}

	if gui.mouse_wheel_forward == nil {
		gui.mouse_wheel_forward = signals.Create(registry)
	}

	if gui.mouse_wheel_backward == nil {
		gui.mouse_wheel_backward = signals.Create(registry)
	}
}

GuiObject_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	gui_object := new(GuiObject)
	gui_object^ = GuiObject_Init()
	gui_object.name = "GuiObject"
	return &gui_object.object
}

GuiObject_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	GuiObject_Free_Signals(cast(^GuiObject)object)
	Object_Destroy(object)
	free(cast(^GuiObject)object)
}

GuiObject_Free_Signals :: proc(gui: ^GuiObject) {
	if gui == nil {
		return
	}
	if gui.input_began != nil {
		signals.Destroy(gui.input_began)
		gui.input_began = nil
	}
	if gui.input_changed != nil {
		signals.Destroy(gui.input_changed)
		gui.input_changed = nil
	}
	if gui.input_ended != nil {
		signals.Destroy(gui.input_ended)
		gui.input_ended = nil
	}
	if gui.mouse_enter != nil {
		signals.Destroy(gui.mouse_enter)
		gui.mouse_enter = nil
	}
	if gui.mouse_leave != nil {
		signals.Destroy(gui.mouse_leave)
		gui.mouse_leave = nil
	}
	if gui.mouse_moved != nil {
		signals.Destroy(gui.mouse_moved)
		gui.mouse_moved = nil
	}
	if gui.mouse_wheel_forward != nil {
		signals.Destroy(gui.mouse_wheel_forward)
		gui.mouse_wheel_forward = nil
	}
	if gui.mouse_wheel_backward != nil {
		signals.Destroy(gui.mouse_wheel_backward)
		gui.mouse_wheel_backward = nil
	}
}

GuiObject_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	gui := cast(^GuiObject)object

	switch key {
	case "Active":
		vm.PushBoolean(L, gui.active)

	case "LayoutOrder":
		vm.PushNumber(L, f64(gui.layout_order))

	case "BackgroundTransparency":
		vm.PushNumber(L, gui.bg_transparency)

	case "ClipsDescendants":
		vm.PushBoolean(L, gui.clips_descendants)

	case "InputSink":
		vm.PushBoolean(L, gui.input_sink)

	case "Selectable":
		vm.PushBoolean(L, gui.selectable)

	case "Visible":
		vm.PushBoolean(L, gui.visible)

	case "ZIndex":
		vm.PushNumber(L, f64(gui.zindex))

	case "BorderSizePixel":
		vm.PushNumber(L, f64(gui.border_size_pixels))

	case "BorderMode":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(L, enum_registry, "BorderMode", i64(gui.border_mode))

	case "GuiState":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(L, enum_registry, "GuiState", i64(gui.gui_state))

	case "BackgroundColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(L, datatype_registry, gui.bg_color)

	case "Position":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_UDim2(L, datatype_registry, gui.position)

	case "Size":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_UDim2(L, datatype_registry, gui.size)

	case "AnchorPoint":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Vector2(L, datatype_registry, gui.anchorpoint)

	case "AbsolutePosition":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Vector2(L, datatype_registry, gui.absolute_position)

	case "AbsoluteSize":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Vector2(L, datatype_registry, gui.absolute_size)

	case "InputBegan":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.input_began)

	case "InputChanged":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.input_changed)

	case "InputEnded":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.input_ended)

	case "MouseEnter":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.mouse_enter)

	case "MouseLeave":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.mouse_leave)

	case "MouseMoved":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.mouse_moved)

	case "MouseWheelForward":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.mouse_wheel_forward)

	case "MouseWheelBackward":
		GuiObject_ensure_signals(gui)
		signals.Push(L, gui.mouse_wheel_backward)

	case:
		return false
	}

	return true
}

GuiObject_effectively_visible :: proc(gui: ^GuiObject) -> bool {
	if gui == nil || gui.destroyed || !gui.visible {
		return false
	}

	current := gui.object.parent

	for current != nil {
		if Is_A(current, "GuiObject") {
			parent_gui := cast(^GuiObject)current

			if !parent_gui.visible {
				return false
			}
		}

		if Is_A(current, "ScreenGui") {
			screen_gui := cast(^ScreenGui)current

			if !screen_gui.enabled {
				return false
			}
		}

		current = current.parent
	}

	return true
}

GuiObject_get_absolute_transform :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) -> (
	x, y, width, height: f32,
) {
	if object == nil {
		return 0, 0, f32(ctx.viewport_width), f32(ctx.viewport_height)
	}
	if Is_A(object, "ScreenGui") {
		screen_gui := cast(^ScreenGui)object

		width = screen_gui.size.X
		height = screen_gui.size.Y

		if width <= 0 {
			width = f32(ctx.viewport_width)
		}

		if height <= 0 {
			height = f32(ctx.viewport_height)
		}

		return screen_gui.render_offset.X, screen_gui.render_offset.Y, width, height
	}

	if !Is_A(object, "GuiObject") {
		return GuiObject_get_absolute_transform(object.parent, ctx)
	}

	parent_x, parent_y, parent_width, parent_height := GuiObject_get_absolute_transform(
		object.parent,
		ctx,
	)

	gui := cast(^GuiObject)object

	if gui.layout_override_size_active {
		width = gui.layout_override_size.X
		height = gui.layout_override_size.Y
	} else {
		width = gui.size.X_Scale * parent_width + gui.size.X_Offset
		height = gui.size.Y_Scale * parent_height + gui.size.Y_Offset
	}

	if gui.layout_override_active {
		x = parent_x + gui.layout_override_position.X

		y = parent_y + gui.layout_override_position.Y
	} else {
		x =
			parent_x +
			gui.position.X_Scale * parent_width +
			gui.position.X_Offset -
			gui.anchorpoint.X * width

		y =
			parent_y +
			gui.position.Y_Scale * parent_height +
			gui.position.Y_Offset -
			gui.anchorpoint.Y * height
	}

	if object.parent != nil && Is_A(object.parent, "ScrollingFrame") {
		scrolling := cast(^ScrollingFrame)object.parent
		x -= scrolling.canvas_position.X
		y -= scrolling.canvas_position.Y
	}

	return x, y, width, height
}

GuiObject_point_in_rect :: proc(
	x, y: f32,
	position: datatypes.Vector2,
	size: datatypes.Vector2,
) -> bool {
	return(
		x >= position.X &&
		y >= position.Y &&
		x <= position.X + size.X &&
		y <= position.Y + size.Y \
	)
}

GuiObject_accepts_pointer :: proc(gui: ^GuiObject) -> bool {
    if gui == nil {
        return false
    }

    return gui.input_sink || gui.active
}

GuiObject_contains_point :: proc(gui: ^GuiObject, x, y: f32) -> bool {
	if !GuiObject_effectively_visible(gui) {
		return false
	}

	if !GuiObject_point_in_rect(x, y, gui.absolute_position, gui.absolute_size) {
		return false
	}

	current := gui.object.parent

	for current != nil {
		if Is_A(current, "GuiObject") {
			parent_gui := cast(^GuiObject)current

			if parent_gui.clips_descendants &&
			   !GuiObject_point_in_rect(
					   x,
					   y,
					   parent_gui.absolute_position,
					   parent_gui.absolute_size,
				   ) {
				return false
			}
		}

		current = current.parent
	}

	return true
}

gui_object_containing_screen :: proc(gui: ^GuiObject) -> ^ScreenGui {
    if gui == nil {
        return nil
    }

    current := gui.object.parent

    for current != nil {
        if Is_A(current, "ScreenGui") {
            return cast(^ScreenGui)current
        }

        current = current.parent
    }

    return nil
}

gui_object_is_overlay_pass :: proc(screen: ^ScreenGui) -> bool {
    if screen == nil {
        return false
    }

    // Mirrors ScreenGui_render: overlay screens are drawn after every normal
    // screen, either via RenderOnTop or by living directly under StarterGui.
    if screen.render_on_top {
        return true
    }

    return screen.object.parent != nil &&
           screen.object.parent.name == "StarterGui"
}

gui_object_visit_painted_subtree :: proc(
    object: ^Object,
    screen: ^ScreenGui,
    x, y: f32,
    seq: ^int,
    best: ^^GuiObject,
    best_seq: ^int,
) {
    if object == nil {
        return
    }

    for child in object.children {
        if child == nil ||
           child.destroyed {
            continue
        }

        if Is_A(child, "GuiObject") &&
           gui_object_containing_screen(
               cast(^GuiObject)child,
           ) == screen {
            gui := cast(^GuiObject)child

            if gui.visible &&
				GuiObject_effectively_visible(gui) &&
				GuiObject_accepts_pointer(gui) &&
				GuiObject_contains_point(gui, x, y) {
                seq^ += 1

                if seq^ > best_seq^ {
                    best^ = gui
                    best_seq^ = seq^
                }
            }
        }

        gui_object_visit_painted_subtree(
            child,
            screen,
            x, y,
            seq,
            best,
            best_seq,
        )
    }
}

GuiObject_find_topmost :: proc(
    registry: ^Registry,
    x, y: f32,
) -> ^GuiObject {
    if registry == nil {
        return nil
    }

    seq := 0
    best: ^GuiObject
    best_seq := -1

    screen_descriptor := Find_Class(registry, "ScreenGui")

    if screen_descriptor != nil {
        for descriptor in registry.classes {
            for object in descriptor.instances {
                if object == nil ||
                   object.destroyed ||
                   !Is_A(object, "GuiObject") {
                    continue
                }

                gui := cast(^GuiObject)object

                if gui_object_containing_screen(gui) != nil {
                    continue
                }

                if gui.visible &&
					GuiObject_effectively_visible(gui) &&
					GuiObject_accepts_pointer(gui) &&
					GuiObject_contains_point(gui, x, y) {
                    seq += 1

                    if seq > best_seq {
                        best = gui
                        best_seq = seq
                    }
                }
            }
        }
    }

    if screen_descriptor != nil {
        for object in screen_descriptor.instances {
            if object == nil ||
               object.destroyed {
                continue
            }

            screen := cast(^ScreenGui)object

            if !screen.enabled ||
               gui_object_is_overlay_pass(screen) {
                continue
            }

            gui_object_visit_painted_subtree(
                &screen.object,
                screen,
                x, y,
                &seq,
                &best,
                &best_seq,
            )
        }

        for object in screen_descriptor.instances {
            if object == nil ||
               object.destroyed {
                continue
            }

            screen := cast(^ScreenGui)object

            if !screen.enabled ||
               !gui_object_is_overlay_pass(screen) {
                continue
            }

            gui_object_visit_painted_subtree(
                &screen.object,
                screen,
                x, y,
                &seq,
                &best,
                &best_seq,
            )
        }
    }

    return best
}

GuiObject_hit_chain :: proc(
    registry: ^Registry,
    x, y: f32,
) -> [dynamic]^GuiObject {
    chain: [dynamic]^GuiObject

    target := GuiObject_find_topmost(registry, x, y)

    if target == nil {
        return chain
    }

    append(&chain, target)

    current := target.object.parent

    for current != nil {
        if Is_A(current, "GuiObject") {
            append(&chain, cast(^GuiObject)current)
        }

        current = current.parent
    }

    return chain
}

GuiObject_in_hit_chain :: proc(
    registry: ^Registry,
    gui: ^GuiObject,
    x, y: f32,
) -> bool {
    if registry == nil || gui == nil {
        return false
    }

    chain := GuiObject_hit_chain(registry, x, y)
    defer delete(chain)

    for candidate in chain {
        if candidate == gui {
            return true
        }
    }

    return false
}

gui_object_mouse_type :: proc(button: u8) -> enums.UserInputType {
	switch button {
	case sdl3.BUTTON_LEFT:
		return .MouseButton1

	case sdl3.BUTTON_RIGHT:
		return .MouseButton2

	case sdl3.BUTTON_MIDDLE:
		return .MouseButton3
	}

	return .None
}

gui_object_mouse_index :: proc(button: u8) -> int {
	switch button {
	case sdl3.BUTTON_LEFT:
		return 0

	case sdl3.BUTTON_RIGHT:
		return 1

	case sdl3.BUTTON_MIDDLE:
		return 2
	}

	return -1
}

gui_object_fire_xy :: proc(L: ^vm.State, signal: ^signals.Signal, x, y: f32) {
	if L == nil || signal == nil {
		return
	}

	vm.PushNumber(L, f64(x))
	vm.PushNumber(L, f64(y))

	signals.Fire(L, signal, 2)

	vm.Pop(L, 2)
}

gui_object_fire_input :: proc(
	L: ^vm.State,
	registry: ^Registry,
	signal: ^signals.Signal,
	value: InputObject_Value,
) {
	if L == nil || registry == nil || signal == nil {
		return
	}

	if Push_InputObject(L, registry, value) == nil {
		return
	}

	signals.Fire(L, signal, 1)

	vm.Pop(L)
}

GuiObject_Handle_Event :: proc(registry: ^Registry, L: ^vm.State, event: sdl3.Event) {
	if registry == nil || L == nil {
		return
	}

	#partial switch event.type {
	case .MOUSE_MOTION:
		x := f32(event.motion.x)
		y := f32(event.motion.y)

		chain := GuiObject_hit_chain(registry, x, y)
		defer delete(chain)

		for descriptor in registry.classes {
			for object in descriptor.instances {
				if object == nil || object.destroyed || !Is_A(object, "GuiObject") {
					continue
				}

				gui := cast(^GuiObject)object

				inside := false

				for candidate in chain {
					if candidate == gui {
						inside = true
						break
					}
				}

				if inside != gui.mouse_inside {
					gui.mouse_inside = inside

					GuiObject_ensure_signals(gui)

					if inside {
						gui_object_fire_xy(L, gui.mouse_enter, x, y)
					} else {
						gui_object_fire_xy(L, gui.mouse_leave, x, y)
					}
				}
			}
		}

		for target in chain {
			if target.destroyed {
				continue
			}

			GuiObject_ensure_signals(target)

			gui_object_fire_xy(L, target.mouse_moved, x, y)

			if target.active {
				gui_object_fire_input(
					L,
					registry,
					target.input_changed,
					InputObject_Value {
						UserInputType = .MouseMovement,
						UserInputState = .Change,
						Position = {event.motion.x, event.motion.y, 0},
						Delta = {event.motion.xrel, event.motion.yrel, 0},
					},
				)
			}
		}

	case .MOUSE_BUTTON_DOWN:
		index := gui_object_mouse_index(event.button.button)

		if index < 0 {
			return
		}

		input_type := gui_object_mouse_type(event.button.button)

		x := f32(event.button.x)
		y := f32(event.button.y)

		object := GuiObject_find_topmost(registry, x, y)

		if object == nil {
			return
		}

		gui := cast(^GuiObject)object

		gui.mouse_input_down[index] = true

		GuiObject_ensure_signals(gui)

		gui_object_fire_input(
			L,
			registry,
			gui.input_began,
			InputObject_Value {
				UserInputType = input_type,
				UserInputState = .Begin,
				Position = {event.button.x, event.button.y, 0},
			},
		)

	case .MOUSE_BUTTON_UP:
		index := gui_object_mouse_index(event.button.button)

		if index < 0 {
			return
		}

		input_type := gui_object_mouse_type(event.button.button)

		for descriptor in registry.classes {
			for object in descriptor.instances {
				if object == nil || object.destroyed || !Is_A(object, "GuiObject") {
					continue
				}

				gui := cast(^GuiObject)object

				if !gui.mouse_input_down[index] {
					continue
				}

				gui.mouse_input_down[index] = false

				GuiObject_ensure_signals(gui)

				gui_object_fire_input(
					L,
					registry,
					gui.input_ended,
					InputObject_Value {
						UserInputType = input_type,
						UserInputState = .End,
						Position = {event.button.x, event.button.y, 0},
					},
				)
			}
		}

	case .MOUSE_WHEEL:
		x := f32(event.wheel.mouse_x)
		y := f32(event.wheel.mouse_y)

		object := GuiObject_find_topmost(registry, x, y)

		if object == nil {
			return
		}

		gui := cast(^GuiObject)object

		GuiObject_ensure_signals(gui)

		gui_object_fire_input(
			L,
			registry,
			gui.input_changed,
			InputObject_Value {
				UserInputType = .MouseWheel,
				UserInputState = .Change,
				Position = {event.wheel.mouse_x, event.wheel.mouse_y, event.wheel.y},
				Delta = {event.wheel.x, 0, event.wheel.y},
			},
		)

		wheel_y := f32(event.wheel.y)

		if event.wheel.direction == .FLIPPED {
			wheel_y = -wheel_y
		}

		if wheel_y > 0 {
			gui_object_fire_xy(L, gui.mouse_wheel_forward, x, y)
		} else if wheel_y < 0 {
			gui_object_fire_xy(L, gui.mouse_wheel_backward, x, y)
		}
	}
}

Update_GUI_Layout :: proc(registry: ^Registry, width, height: i32) {
	if registry == nil {
		return
	}

	ctx := Class_Step_Context {
		viewport_width  = width,
		viewport_height = height,
	}

	for descriptor in registry.classes {
		for object in descriptor.instances {
			if object == nil || object.destroyed || !Is_A(object, "GuiObject") {
				continue
			}

			gui := cast(^GuiObject)object

			gui.layout_override_active = false
			gui.layout_override_position = {}

			gui.layout_override_size_active = false
			gui.layout_override_size = {}
		}
	}

	for descriptor in registry.classes {
		for object in descriptor.instances {
			if object == nil || object.destroyed {
				continue
			}

			if Is_A(object, "UIListLayout") {
				UIListLayout_Apply(
					cast(^UIListLayout)object,
					registry,
					&ctx,
				)
			} else if Is_A(object, "UIGridLayout") {
				UIGridLayout_Apply(
					cast(^UIGridLayout)object,
					registry,
					&ctx,
				)
			}
		}
	}

	for descriptor in registry.classes {
		for object in descriptor.instances {
			if object == nil || object.destroyed || !Is_A(object, "GuiObject") {
				continue
			}

			x, y, w, h := GuiObject_get_absolute_transform(object, &ctx)

			gui := cast(^GuiObject)object

			gui.absolute_position = {x, y}

			gui.absolute_size = {w, h}
		}
	}
}

GuiObject_get_rect :: proc(object: ^Object, ctx: ^Class_Step_Context) -> (guilib.Rect, bool) {
	gui := cast(^GuiObject)object

	if !gui.visible {
		return guilib.Rect{}, false
	}

	if ctx == nil || ctx.renderer == nil || ctx.renderer.SkiaSurface == nil {
		return guilib.Rect{}, false
	}

	x, y, width, height := GuiObject_get_absolute_transform(object, ctx)

	return guilib.Rect {
			x = x,
			y = y,
			width = width,
			height = height,
			color = gui.bg_color,
			bgTransparency = f32(gui.bg_transparency),
		},
		true
}

gui_resolve_udim :: proc(value: datatypes.UDim, basis: f32) -> f32 {
	return value.Scale * basis + value.Offset
}

gui_corner_radius :: proc(corner_object: ^Object, rect: guilib.Rect) -> f32 {
	if corner_object == nil {
		return 0
	}

	corner := cast(^UICorner)corner_object
	short_edge := min(rect.width, rect.height)
	radius := gui_resolve_udim(corner.corner_radius, short_edge)
	return clamp(radius, f32(0), short_edge * 0.5)
}

gui_render_children :: proc(
	gui: ^GuiObject,
	object: ^Object,
	ctx: ^Class_Step_Context,
	rect: guilib.Rect,
	corner_radius: f32,
) {
	scrolling_frame_virtualized := false
	if Is_A(object, "ScrollingFrame") {
		scrolling_frame_virtualized = (cast(^ScrollingFrame)object).virtualized_scrolling
	}

	if !gui.clips_descendants {
		if scrolling_frame_virtualized {
			ScreenGui_RenderChildren_Visible(object, ctx, rect)
		} else {
			ScreenGui_RenderChildren(object, ctx)
		}
		return
	}

	guilib.save(ctx.renderer.SkiaSurface)
	if corner_radius > 0 {
		guilib.clipRoundedRect(ctx.renderer.SkiaSurface, rect, corner_radius)
	} else {
		guilib.clipRect(ctx.renderer.SkiaSurface, rect)
	}
	if scrolling_frame_virtualized {
		ScreenGui_RenderChildren_Visible(object, ctx, rect)
	} else {
		ScreenGui_RenderChildren(object, ctx)
	}
	guilib.restore(ctx.renderer.SkiaSurface)
}

GuiObject_render :: proc(object: ^Object, ctx: ^Class_Step_Context, skip_shadow: bool = false) {
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
			offset_x := shadow.offset.X_Scale * rect.width + shadow.offset.X_Offset
			offset_y := shadow.offset.Y_Scale * rect.height + shadow.offset.Y_Offset
			spread_x := shadow.spread.X_Scale * rect.width + shadow.spread.X_Offset
			spread_y := shadow.spread.Y_Scale * rect.height + shadow.spread.Y_Offset

			params := guilib.ShadowParams {
				offsetX   = offset_x,
				offsetY   = offset_y,
				blurSigma = max(f32(0), gui_resolve_udim(shadow.blur_radius, short_edge)),
				spread    = max(f32(0), (spread_x + spread_y) * 0.5),
				color     = shadow.color,
				alpha     = 1 - f32(shadow.transparency),
			}

			if shadow.showfortext != true && !skip_shadow {
				guilib.drawShadow(
					ctx.renderer.SkiaSurface,
					rect,
					corner_radius,
					f32(shadow.exponent),
					params,
				)
			}
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
				guilib.drawRectStroke(ctx.renderer.SkiaSurface, stroke_rect, f32(stroke.thickness))
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
	case "LayoutOrder":
		gui_object.layout_order = i32(vm.ArgNumber(L, value_index))
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
		if enum_registry == nil {return false}
		gui_object.border_mode = enums.BorderMode(
			enums.Arg_Item(L, value_index, enum_registry, "BorderMode").value,
		)
	case "BackgroundColor3":
		if datatype_registry == nil {return false}
		gui_object.bg_color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Position":
		if datatype_registry == nil {return false}
		gui_object.position = datatypes.Arg_UDim2(L, value_index, datatype_registry)
	case "Size":
		if datatype_registry == nil {return false}
		gui_object.size = datatypes.Arg_UDim2(L, value_index, datatype_registry)
	case "AnchorPoint":
		if datatype_registry == nil {return false}
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

	dst.bg_transparency = src.bg_transparency
	dst.bg_color = src.bg_color
	dst.active = src.active
	dst.border_mode = src.border_mode
	dst.clips_descendants = src.clips_descendants
	dst.input_sink = src.input_sink
	dst.position = src.position
	dst.selectable = src.selectable
	dst.size = src.size
	dst.visible = src.visible
	dst.zindex = src.zindex
	dst.anchorpoint = src.anchorpoint
	dst.border_size_pixels = src.border_size_pixels
	dst.layout_order = src.layout_order

	dst.layout_override_active = false
	dst.layout_override_position = {}
	dst.layout_override_size_active = false
	dst.layout_override_size = {}
	dst.mouse_inside = false
	dst.mouse_input_down = [3]bool{}
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
		properties = []string {
			"BorderSizePixel",
			"Selectable",
			"Active",
			"GuiState",
			"ClipsDescendants",
			"Position",
			"AbsolutePosition",
			"Size",
			"BackgroundColor3",
			"BorderMode",
			"AnchorPoint",
			"ZIndex",
			"LayoutOrder",
			"InputSink",
			"AbsoluteSize",
			"Visible",
			"BackgroundTransparency",
		},
	)
}
