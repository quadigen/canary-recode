package classes

import sdl3 "../platform"

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

GuiButton_Class := Class_Info{
	name   = "GuiButton",
	parent = &GuiObject_Class,
}

GuiButton :: struct {
	using gui_object: GuiObject,

	auto_button_color: bool,
	modal:             bool,
	selected:          bool,

	hovered: bool,

	mouse1_down: bool,
	mouse2_down: bool,

	activated_signal: ^signals.Signal,
	secondary_activated_signal: ^signals.Signal,

	mouse_button1_click: ^signals.Signal,
	mouse_button1_down:  ^signals.Signal,
	mouse_button1_up:    ^signals.Signal,

	mouse_button2_click: ^signals.Signal,
	mouse_button2_down:  ^signals.Signal,
	mouse_button2_up:    ^signals.Signal,
}

GuiButton_Init :: proc() -> GuiButton {
	gui := GuiObject_Init()

	gui.object.class =
		&GuiButton_Class

	gui.active = true
	gui.selectable = true

	return GuiButton{
		gui_object = gui,

		auto_button_color = true,
		modal = false,
		selected = false,
	}
}

GuiButton_ensure_signals :: proc(
	button: ^GuiButton,
) {
	if button == nil ||
	   button.object.signal_registry == nil ||
	   button.object.signal_registry.signal_registry == nil {
		return
	}

	registry :=
		button.object.signal_registry.signal_registry

	if button.activated_signal == nil {
		button.activated_signal =
			signals.Create(registry)
	}

	if button.secondary_activated_signal == nil {
		button.secondary_activated_signal =
			signals.Create(registry)
	}

	if button.mouse_button1_click == nil {
		button.mouse_button1_click =
			signals.Create(registry)
	}

	if button.mouse_button1_down == nil {
		button.mouse_button1_down =
			signals.Create(registry)
	}

	if button.mouse_button1_up == nil {
		button.mouse_button1_up =
			signals.Create(registry)
	}

	if button.mouse_button2_click == nil {
		button.mouse_button2_click =
			signals.Create(registry)
	}

	if button.mouse_button2_down == nil {
		button.mouse_button2_down =
			signals.Create(registry)
	}

	if button.mouse_button2_up == nil {
		button.mouse_button2_up =
			signals.Create(registry)
	}
}

GuiButton_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	button := new(GuiButton)

	button^ =
		GuiButton_Init()

	button.name =
		"GuiButton"

	return &button.object
}

GuiButton_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	Object_Destroy(
		object,
	)

	free(
		cast(^GuiButton)object,
	)
}

GuiButton_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	button :=
		cast(^GuiButton)object

	switch key {
	case "AutoButtonColor":
		vm.PushBoolean(
			L,
			button.auto_button_color,
		)

	case "Modal":
		vm.PushBoolean(
			L,
			button.modal,
		)

	case "Selected":
		vm.PushBoolean(
			L,
			button.selected,
		)

	case "Activated":
		GuiButton_ensure_signals(button)
		signals.Push(
			L,
			button.activated_signal,
		)

	case "SecondaryActivated":
		GuiButton_ensure_signals(button)
		signals.Push(
			L,
			button.secondary_activated_signal,
		)

	case "MouseButton1Click":
		GuiButton_ensure_signals(button)
		signals.Push(
			L,
			button.mouse_button1_click,
		)

	case "MouseButton1Down":
		GuiButton_ensure_signals(button)
		signals.Push(
			L,
			button.mouse_button1_down,
		)

	case "MouseButton1Up":
		GuiButton_ensure_signals(button)
		signals.Push(
			L,
			button.mouse_button1_up,
		)

	case "MouseButton2Click":
		GuiButton_ensure_signals(button)
		signals.Push(
			L,
			button.mouse_button2_click,
		)

	case "MouseButton2Down":
		GuiButton_ensure_signals(button)
		signals.Push(
			L,
			button.mouse_button2_down,
		)

	case "MouseButton2Up":
		GuiButton_ensure_signals(button)
		signals.Push(
			L,
			button.mouse_button2_up,
		)

	case:
		return GuiObject_get(
			L,
			object,
			datatype_registry,
			enum_registry,
			key,
		)
	}

	return true
}

GuiButton_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	button :=
		cast(^GuiButton)object

	switch key {
	case "AutoButtonColor":
		button.auto_button_color =
			vm.ArgBoolean(
				L,
				value_index,
			)

	case "Modal":
		button.modal =
			vm.ArgBoolean(
				L,
				value_index,
			)

	case "Selected":
		button.selected =
			vm.ArgBoolean(
				L,
				value_index,
			)

	case:
		return GuiObject_set(
			L,
			object,
			datatype_registry,
			enum_registry,
			key,
			value_index,
		)
	}

	return true
}

gui_button_apply_state :: proc(
	button: ^GuiButton,
) {
	if button == nil {
		return
	}

	button.hovered =
		button.mouse_inside

	switch {
	case button.mouse1_down ||
	     button.mouse2_down:
		button.gui_state =
			.Press

	case button.hovered:
		button.gui_state =
			.Hover

	case:
		button.gui_state =
			.Idle
	}
}

GuiButton_update :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) -> bool {
	if object == nil ||
	   object.destroyed ||
	   ctx == nil {
		return false
	}

	button :=
		cast(^GuiButton)object

	if !GuiObject_effectively_visible(
		&button.gui_object,
	) {
		button.hovered = false
		button.mouse1_down = false
		button.mouse2_down = false
		button.gui_state = .Idle

		return false
	}

	gui_button_apply_state(
		button,
	)

	return true
}

GuiButton_find_topmost :: proc(
	registry: ^Registry,
	x, y: f32,
) -> ^GuiButton {
	if registry == nil {
		return nil
	}

	best: ^GuiButton
	best_z: i32
	best_depth := 0

	for descriptor in registry.classes {
		for object in descriptor.instances {
			if object == nil ||
			   object.destroyed ||
			   !Is_A(object, "GuiButton") {
				continue
			}

			button :=
				cast(^GuiButton)object

			if !GuiObject_contains_point(
				&button.gui_object,
				x,
				y,
			) {
				continue
			}

			depth :=
				gui_object_depth(
					object,
				)

			if best == nil ||
			   button.zindex > best_z ||
			   (
					button.zindex == best_z &&
					depth >= best_depth
			   ) {
				best = button
				best_z = button.zindex
				best_depth = depth
			}
		}
	}

	return best
}

gui_button_find_pressed :: proc(
	registry: ^Registry,
	left: bool,
) -> ^GuiButton {
	if registry == nil {
		return nil
	}

	for descriptor in registry.classes {
		for object in descriptor.instances {
			if object == nil ||
			   object.destroyed ||
			   !Is_A(object, "GuiButton") {
				continue
			}

			button :=
				cast(^GuiButton)object

			if left && button.mouse1_down {
				return button
			}

			if !left && button.mouse2_down {
				return button
			}
		}
	}

	return nil
}

gui_button_fire_activated :: proc(
	L: ^vm.State,
	registry: ^Registry,
	button: ^GuiButton,
	event: sdl3.MouseButtonEvent,
	left: bool,
) {
	if L == nil ||
	   registry == nil ||
	   button == nil {
		return
	}

	GuiButton_ensure_signals(
		button,
	)

	input_type: enums.UserInputType =
		.MouseButton1

	if !left {
		input_type =
			.MouseButton2
	}

	if Push_InputObject(
		L,
		registry,
		InputObject_Value{
			UserInputType = input_type,
			UserInputState = .End,
			Position = {
				event.x,
				event.y,
				0,
			},
		},
	) == nil {
		return
	}

	if left {
		click_count :=
			max(
				i32(event.clicks),
				1,
			)

		vm.PushNumber(
			L,
			f64(click_count),
		)

		signals.Fire(
			L,
			button.activated_signal,
			2,
		)

		vm.Pop(
			L,
			2,
		)
	} else {
		signals.Fire(
			L,
			button.secondary_activated_signal,
			1,
		)

		vm.Pop(
			L,
		)
	}
}

GuiButton_Handle_Event :: proc(
	registry: ^Registry,
	L: ^vm.State,
	event: sdl3.Event,
) {
	if registry == nil || L == nil {
		return
	}

	#partial switch event.type {
	case .MOUSE_BUTTON_DOWN:
		if event.button.button != sdl3.BUTTON_LEFT &&
		   event.button.button != sdl3.BUTTON_RIGHT {
			return
		}

		x := f32(event.button.x)
		y := f32(event.button.y)

		button :=
			GuiButton_find_topmost(
				registry,
				x,
				y,
			)

		if button == nil {
			return
		}

		GuiButton_ensure_signals(
			button,
		)

		if event.button.button == sdl3.BUTTON_LEFT {
			button.mouse1_down =
				true

			gui_object_fire_xy(
				L,
				button.mouse_button1_down,
				x,
				y,
			)
		} else {
			button.mouse2_down =
				true

			gui_object_fire_xy(
				L,
				button.mouse_button2_down,
				x,
				y,
			)
		}

		gui_button_apply_state(
			button,
		)

	case .MOUSE_BUTTON_UP:
		if event.button.button != sdl3.BUTTON_LEFT &&
		   event.button.button != sdl3.BUTTON_RIGHT {
			return
		}

		left :=
			event.button.button ==
			sdl3.BUTTON_LEFT

		button :=
			gui_button_find_pressed(
				registry,
				left,
			)

		if button == nil {
			return
		}

		x := f32(event.button.x)
		y := f32(event.button.y)

		inside :=
			GuiObject_contains_point(
				&button.gui_object,
				x,
				y,
			)

		GuiButton_ensure_signals(
			button,
		)

		if left {
			button.mouse1_down =
				false

			gui_object_fire_xy(
				L,
				button.mouse_button1_up,
				x,
				y,
			)

			if inside {
				signals.Fire(
					L,
					button.mouse_button1_click,
				)

				if button.active {
					gui_button_fire_activated(
						L,
						registry,
						button,
						event.button,
						true,
					)
				}
			}
		} else {
			button.mouse2_down =
				false

			gui_object_fire_xy(
				L,
				button.mouse_button2_up,
				x,
				y,
			)

			if inside {
				signals.Fire(
					L,
					button.mouse_button2_click,
				)

				if button.active {
					gui_button_fire_activated(
						L,
						registry,
						button,
						event.button,
						false,
					)
				}
			}
		}

		gui_button_apply_state(
			button,
		)
	}
}

GuiButton_render :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) {
	button :=
		cast(^GuiButton)object

	if !GuiButton_update(
		object,
		ctx,
	) {
		return
	}

	original_color :=
		button.bg_color

	if button.auto_button_color {
		#partial switch button.gui_state {
		case .Hover:
			button.bg_color.R =
				clamp(
					button.bg_color.R * 1.08,
					0,
					1,
				)

			button.bg_color.G =
				clamp(
					button.bg_color.G * 1.08,
					0,
					1,
				)

			button.bg_color.B =
				clamp(
					button.bg_color.B * 1.08,
					0,
					1,
				)

		case .Press:
			button.bg_color.R *=
				0.82

			button.bg_color.G *=
				0.82

			button.bg_color.B *=
				0.82
		}
	}

	GuiObject_render(
		object,
		ctx,
	)

	button.bg_color =
		original_color
}

GuiButton_clone :: proc(
	source: ^Object,
	destination: ^Object,
) {
	src :=
		cast(^GuiButton)source

	dst :=
		cast(^GuiButton)destination

	dst.auto_button_color =
		src.auto_button_color

	dst.modal =
		src.modal

	dst.selected =
		src.selected

	dst.hovered =
		false

	dst.mouse1_down =
		false

	dst.mouse2_down =
		false
}

Register_GuiButton :: proc(
	registry: ^Registry,
) {
	Register_Class(
		registry,
		&GuiButton_Class,
		GuiButton_construct,
		GuiButton_destroy,

		creatable = false,

		get = GuiButton_get,
		set = GuiButton_set,
		clone = GuiButton_clone,

		properties = []string{
			"AutoButtonColor",
			"Modal",
			"Selected",
		},
	)
}