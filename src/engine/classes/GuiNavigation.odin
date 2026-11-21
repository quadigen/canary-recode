package classes

import kineffi "../bindings"
import enums "../enum"
import signals "../signals"
import vm "../vm"

Gui_Selection_Valid :: proc(registry: ^Registry, gui: ^GuiObject) -> bool {
	if registry == nil ||
	   gui == nil ||
	   gui.destroyed ||
	   gui.signal_registry != registry ||
	   !gui.selectable ||
	   !GuiObject_effectively_visible(gui) ||
	   gui.absolute_size.X <= 0 ||
	   gui.absolute_size.Y <= 0 {return false}
	screen := gui_object_containing_screen(gui)
	if screen == nil {return false}
	x := gui.absolute_position.X + gui.absolute_size.X * 0.5
	y := gui.absolute_position.Y + gui.absolute_size.Y * 0.5
	return GuiObject_contains_point(gui, x, y)
}

Gui_Get_Selected :: proc(registry: ^Registry) -> ^GuiObject {
	if registry == nil {return nil}
	if !Gui_Selection_Valid(registry, registry.gui_selected) {
		registry.gui_selected = nil
	}
	return registry.gui_selected
}

Gui_Set_Selected :: proc(registry: ^Registry, gui: ^GuiObject) -> bool {
	if registry == nil {return false}
	if gui != nil &&
	   (gui.destroyed || gui.signal_registry != registry || !gui.selectable) {return false}
	previous := registry.gui_selected
	if previous == gui {return true}
	registry.gui_selected = gui
	L := registry.vm_state.L if registry.vm_state != nil else nil
	if L != nil {
		if previous != nil &&
		   !previous.destroyed &&
		   previous.selection_lost != nil {signals.Fire(L, previous.selection_lost)}
		if registry.gui_selected == gui &&
		   gui != nil &&
		   gui.selection_gained != nil {signals.Fire(L, gui.selection_gained)}
	}
	return true
}

Gui_Select_Within :: proc(registry: ^Registry, root: ^Object) {
	if registry == nil || root == nil || root.destroyed {return}
	pending: [dynamic]^Object
	defer delete(pending)
	append(&pending, root)
	best: ^GuiObject
	best_order := max(int)
	for len(pending) > 0 {
		current := pop(&pending)
		if current == nil || current.destroyed {continue}
		if Is_A(current, "GuiObject") {
			gui := cast(^GuiObject)current
			if Gui_Selection_Valid(registry, gui) {
				order := int(gui.selection_order)
				if best == nil || order < best_order {best = gui; best_order = order}
			}
		}
		for i := len(current.children) - 1; i >= 0; i -= 1 {append(&pending, current.children[i])}
	}
	if best != nil {_ = Gui_Set_Selected(registry, best)}
}

Gui_Navigate :: proc(registry: ^Registry, dx, dy: i32) -> bool {
	if registry == nil || registry.gui_navigation_disabled || (dx == 0 && dy == 0) {return false}
	current := Gui_Get_Selected(registry)
	best: ^GuiObject
	best_score: f32 = 1e30
	for descriptor in registry.classes {
		if descriptor == nil || !Is_Class_A(descriptor.info, &GuiObject_Class) {continue}
		for object in descriptor.instances {
			if object == nil || (current != nil && object == &current.object) {continue}
			gui := cast(^GuiObject)object
			if !Gui_Selection_Valid(registry, gui) {continue}
			cx := gui.absolute_position.X + gui.absolute_size.X * 0.5
			cy := gui.absolute_position.Y + gui.absolute_size.Y * 0.5
			hit := GuiObject_find_topmost(registry, cx, cy)
			if hit != nil && hit != gui {
				ancestor := hit.object.parent
				for ancestor != nil && ancestor != object {ancestor = ancestor.parent}
				if ancestor == nil {continue}
			}
			score: f32
			if current == nil {
				score = cy * 4 + cx
			} else {
				x := cx - (current.absolute_position.X + current.absolute_size.X * 0.5)
				y := cy - (current.absolute_position.Y + current.absolute_size.Y * 0.5)
				forward := x * f32(dx) + y * f32(dy)
				if forward <= 0.5 {continue}
				side := abs(x * f32(dy) - y * f32(dx))
				score = forward + side * 2 + side * side / max(forward, 1)
			}
			if score < best_score {best = gui; best_score = score}
		}
	}
	if best != nil {return Gui_Set_Selected(registry, best)}
	return current != nil
}

Gui_Gamepad_Confirm :: proc(
	registry: ^Registry,
	L: ^vm.State,
	owner: u32,
	input_type: enums.UserInputType,
	down: bool,
) -> bool {
	if registry == nil || L == nil || registry.gui_navigation_disabled {return false}
	if down {
		if registry.gui_gamepad_pressed != nil {return true}
		gui := Gui_Get_Selected(registry)
		if gui == nil {
			_ = Gui_Navigate(registry, 0, 1)
			gui = Gui_Get_Selected(registry)
		}
		if gui == nil {return false}
		registry.gui_gamepad_pressed = gui
		registry.gui_gamepad_owner = owner
		gui_object_fire_input(
			L,
			registry,
			gui.input_began,
			InputObject_Value {
				UserInputType = input_type,
				UserInputState = .Begin,
				KeyCode = .ButtonA,
			},
		)
		return true
	}
	if registry.gui_gamepad_owner != owner {return false}
	gui := registry.gui_gamepad_pressed
	registry.gui_gamepad_pressed = nil
	registry.gui_gamepad_owner = 0
	if gui == nil {return false}
	gui_event_depth += 1
	defer {
		gui_event_depth -= 1
		if gui_event_depth == 0 {clear(&gui_event_invalidated)}
	}
	value := InputObject_Value {
		UserInputType  = input_type,
		UserInputState = .End,
		KeyCode        = .ButtonA,
	}
	gui_object_fire_input(L, registry, gui.input_ended, value)
	if gui_object_event_invalid(gui) ||
	   gui.destroyed ||
	   gui != Gui_Get_Selected(registry) {return true}
	if Is_A_Class(&gui.object, &GuiButton_Class) && gui.active {
		button := cast(^GuiButton)gui
		GuiButton_ensure_signals(button)
		if input := Push_InputObject(L, registry, value); input != nil {
			vm.PushNumber(L, 1)
			signals.Fire(L, button.activated_signal, 2)
			vm.Pop(L, 2)
			Destroy_Hierarchy(&input.object)
		}
	}
	return true
}

Gui_Gamepad_Disconnect :: proc(registry: ^Registry, owner: u32) {
	if registry == nil {return}
	if registry.gui_gamepad_owner == owner {
		registry.gui_gamepad_pressed = nil
		registry.gui_gamepad_owner = 0
	}
}

Gui_Draw_Selection :: proc(registry: ^Registry) {
	gui := Gui_Get_Selected(registry)
	if gui == nil || registry.renderer == nil || registry.renderer.SkiaSurface == nil {return}
	x, y := gui.absolute_position.X, gui.absolute_position.Y
	w, h := gui.absolute_size.X, gui.absolute_size.Y
	surface := registry.renderer.SkiaSurface
	kineffi.Kine_Skia_Surface_DrawRect(surface, x - 2, y - 2, w + 4, h + 4, 0, 0, 0, 220, 4)
	kineffi.Kine_Skia_Surface_DrawRect(surface, x - 2, y - 2, w + 4, h + 4, 120, 190, 255, 255, 2)
}
