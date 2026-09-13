package classes

import sdl3 "../platform"

import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"


ScrollingFrame_Class := Class_Info{
	name   = "ScrollingFrame",
	parent = &GuiObject_Class,
}


ScrollingFrame :: struct {
	using gui_object: GuiObject,

	canvas_position: datatypes.Vector2,
	target_position: datatypes.Vector2,
	canvas_size:     datatypes.UDim2,

	scrolling_enabled: bool,
	scroll_speed:     f32,

	smooth_scrolling: bool,
	smoothness:       f32,

	scrollbar_thickness:    f32,
	scrollbar_color:        datatypes.Color3,
	scrollbar_transparency: f32,
	scrollbar_auto_hide:    bool,
	scrollbar_fade_delay:   f32,
	scrollbar_fade_speed:   f32,
	scrollbar_min_handle:   f32,

	scrollbar_alpha: f32,
	idle_time:       f32,

	max_scroll_x: f32,
	max_scroll_y: f32,

	dragging_vertical:   bool,
	dragging_horizontal: bool,
	drag_mouse_start:    f32,
	drag_canvas_start:   f32,
}


scrolling_frame_dragged: ^ScrollingFrame


ScrollingFrame_Init :: proc() -> ScrollingFrame {
	gui := GuiObject_Init()
	gui.object.class = &ScrollingFrame_Class

	gui.clips_descendants = true
	gui.active = true
	gui.input_sink = true

	return ScrollingFrame{
		gui_object = gui,

		canvas_position = datatypes.Vector2{0, 0},
		target_position = datatypes.Vector2{0, 0},
		canvas_size = datatypes.UDim2{
			X_Scale = 0,
			X_Offset = 0,
			Y_Scale = 0,
			Y_Offset = 0,
		},

		scrolling_enabled = true,
		scroll_speed = 42,

		smooth_scrolling = true,
		smoothness = 18,

		scrollbar_thickness = 6,
		scrollbar_color = datatypes.Color3{R = 0.5, G = 0.5, B = 0.5},
		scrollbar_transparency = 0.2,
		scrollbar_auto_hide = true,
		scrollbar_fade_delay = 0.7,
		scrollbar_fade_speed = 12,
		scrollbar_min_handle = 24,

		scrollbar_alpha = 0,
		idle_time = 999,

		max_scroll_x = 0,
		max_scroll_y = 0,

		dragging_vertical = false,
		dragging_horizontal = false,
	}
}


scrolling_frame_interact :: proc(frame: ^ScrollingFrame) {
	if frame == nil {
		return
	}

	frame.idle_time = 0
}


scrolling_frame_effectively_visible :: proc(frame: ^ScrollingFrame) -> bool {
	if frame == nil {
		return false
	}

	current := &frame.object

	for current != nil {
		if Is_A(current, "GuiObject") {
			gui := cast(^GuiObject)current

			if !gui.visible {
				return false
			}
		}

		if Is_A(current, "ScreenGui") {
			screen := cast(^ScreenGui)current

			if !screen.enabled {
				return false
			}
		}

		current = current.parent
	}

	return true
}


scrolling_frame_depth :: proc(frame: ^ScrollingFrame) -> int {
	if frame == nil {
		return 0
	}

	depth := 0
	current := frame.parent

	for current != nil {
		depth += 1
		current = current.parent
	}

	return depth
}


scrolling_frame_contains_point :: proc(
	frame: ^ScrollingFrame,
	x, y: f32,
) -> bool {
	if frame == nil ||
	   !scrolling_frame_effectively_visible(frame) {
		return false
	}

	position := frame.absolute_position
	size := frame.absolute_size

	return x >= position.X &&
	       y >= position.Y &&
	       x <= position.X + size.X &&
	       y <= position.Y + size.Y
}


scrolling_frame_resolve_canvas :: proc(
	frame: ^ScrollingFrame,
	viewport_width, viewport_height: f32,
) -> (width, height: f32) {
	if frame == nil {
		return viewport_width, viewport_height
	}

	width =
		frame.canvas_size.X_Scale*viewport_width +
		frame.canvas_size.X_Offset

	height =
		frame.canvas_size.Y_Scale*viewport_height +
		frame.canvas_size.Y_Offset

	width = max(width, viewport_width)
	height = max(height, viewport_height)

	return width, height
}


scrolling_frame_update_bounds :: proc(
	frame: ^ScrollingFrame,
	rect: guilib.Rect,
) {
	if frame == nil {
		return
	}

	canvas_width, canvas_height :=
		scrolling_frame_resolve_canvas(
			frame,
			rect.width,
			rect.height,
		)

	frame.max_scroll_x = max(
		canvas_width - rect.width,
		f32(0),
	)

	frame.max_scroll_y = max(
		canvas_height - rect.height,
		f32(0),
	)

	frame.target_position.X = clamp(
		frame.target_position.X,
		f32(0),
		frame.max_scroll_x,
	)

	frame.target_position.Y = clamp(
		frame.target_position.Y,
		f32(0),
		frame.max_scroll_y,
	)

	frame.canvas_position.X = clamp(
		frame.canvas_position.X,
		f32(0),
		frame.max_scroll_x,
	)

	frame.canvas_position.Y = clamp(
		frame.canvas_position.Y,
		f32(0),
		frame.max_scroll_y,
	)
}


scrolling_frame_set_target :: proc(
	frame: ^ScrollingFrame,
	x, y: f32,
) {
	if frame == nil {
		return
	}

	frame.target_position.X = clamp(
		x,
		f32(0),
		frame.max_scroll_x,
	)

	frame.target_position.Y = clamp(
		y,
		f32(0),
		frame.max_scroll_y,
	)

	scrolling_frame_interact(frame)
}


scrolling_frame_update_animation :: proc(
	frame: ^ScrollingFrame,
	rect: guilib.Rect,
	delta_time: f32,
) {
	if frame == nil {
		return
	}

	scrolling_frame_update_bounds(
		frame,
		rect,
	)

	dt := clamp(
		delta_time,
		f32(0),
		f32(0.1),
	)

	if frame.smooth_scrolling {
		t := min(
			dt*max(frame.smoothness, f32(0)),
			f32(1),
		)

		frame.canvas_position.X +=
			(frame.target_position.X -
			 frame.canvas_position.X)*t

		frame.canvas_position.Y +=
			(frame.target_position.Y -
			 frame.canvas_position.Y)*t

		if abs(
			frame.target_position.X -
			frame.canvas_position.X,
		) < 0.01 {
			frame.canvas_position.X =
				frame.target_position.X
		}

		if abs(
			frame.target_position.Y -
			frame.canvas_position.Y,
		) < 0.01 {
			frame.canvas_position.Y =
				frame.target_position.Y
		}
	} else {
		frame.canvas_position =
			frame.target_position
	}

	frame.idle_time += dt

	alpha_target: f32 = 1

	if frame.scrollbar_auto_hide {
		alpha_target = 0

		if frame.dragging_vertical ||
		   frame.dragging_horizontal ||
		   frame.idle_time <
		   frame.scrollbar_fade_delay {
			alpha_target = 1
		}
	}

	alpha_t := min(
		dt*max(frame.scrollbar_fade_speed, f32(0)),
		f32(1),
	)

	frame.scrollbar_alpha +=
		(alpha_target -
		 frame.scrollbar_alpha)*alpha_t

	frame.scrollbar_alpha = clamp(
		frame.scrollbar_alpha,
		f32(0),
		f32(1),
	)
}


scrolling_frame_vertical_bar :: proc(
	frame: ^ScrollingFrame,
) -> (
	track: guilib.Rect,
	handle: guilib.Rect,
	visible: bool,
) {
	if frame == nil ||
	   frame.max_scroll_y <= 0 ||
	   frame.scrollbar_thickness <= 0 {
		return guilib.Rect{},
		       guilib.Rect{},
		       false
	}

	size := frame.absolute_size
	position := frame.absolute_position

	canvas_width, canvas_height :=
		scrolling_frame_resolve_canvas(
			frame,
			size.X,
			size.Y,
		)

	_ = canvas_width

	padding: f32 = 2

	track_height := max(
		size.Y - padding*2,
		f32(0),
	)

	if track_height <= 0 ||
	   canvas_height <= 0 {
		return guilib.Rect{},
		       guilib.Rect{},
		       false
	}

	track = guilib.Rect{
		x = position.X +
		    size.X -
		    frame.scrollbar_thickness -
		    padding,

		y = position.Y + padding,

		width =
			frame.scrollbar_thickness,

		height =
			track_height,
	}

	handle_height := max(
		track_height*
		(size.Y/canvas_height),
		frame.scrollbar_min_handle,
	)

	handle_height = min(
		handle_height,
		track_height,
	)

	travel := max(
		track_height -
		handle_height,
		f32(0),
	)

	ratio: f32 = 0

	if frame.max_scroll_y > 0 {
		ratio =
			frame.canvas_position.Y /
			frame.max_scroll_y
	}

	handle = guilib.Rect{
		x = track.x,
		y = track.y + travel*ratio,
		width = track.width,
		height = handle_height,
	}

	return track, handle, true
}


scrolling_frame_horizontal_bar :: proc(
	frame: ^ScrollingFrame,
) -> (
	track: guilib.Rect,
	handle: guilib.Rect,
	visible: bool,
) {
	if frame == nil ||
	   frame.max_scroll_x <= 0 ||
	   frame.scrollbar_thickness <= 0 {
		return guilib.Rect{},
		       guilib.Rect{},
		       false
	}

	size := frame.absolute_size
	position := frame.absolute_position

	canvas_width, canvas_height :=
		scrolling_frame_resolve_canvas(
			frame,
			size.X,
			size.Y,
		)

	_ = canvas_height

	padding: f32 = 2

	track_width := max(
		size.X - padding*2,
		f32(0),
	)

	if track_width <= 0 ||
	   canvas_width <= 0 {
		return guilib.Rect{},
		       guilib.Rect{},
		       false
	}

	track = guilib.Rect{
		x = position.X + padding,

		y = position.Y +
		    size.Y -
		    frame.scrollbar_thickness -
		    padding,

		width =
			track_width,

		height =
			frame.scrollbar_thickness,
	}

	handle_width := max(
		track_width*
		(size.X/canvas_width),
		frame.scrollbar_min_handle,
	)

	handle_width = min(
		handle_width,
		track_width,
	)

	travel := max(
		track_width -
		handle_width,
		f32(0),
	)

	ratio: f32 = 0

	if frame.max_scroll_x > 0 {
		ratio =
			frame.canvas_position.X /
			frame.max_scroll_x
	}

	handle = guilib.Rect{
		x = track.x + travel*ratio,
		y = track.y,
		width = handle_width,
		height = track.height,
	}

	return track, handle, true
}


scrolling_frame_point_in_rect :: proc(
	rect: guilib.Rect,
	x, y: f32,
) -> bool {
	return x >= rect.x &&
	       y >= rect.y &&
	       x <= rect.x + rect.width &&
	       y <= rect.y + rect.height
}


scrolling_frame_draw_scrollbars :: proc(
	frame: ^ScrollingFrame,
	ctx: ^Class_Step_Context,
) {
	if frame == nil ||
	   ctx == nil ||
	   ctx.renderer == nil ||
	   ctx.renderer.SkiaSurface == nil ||
	   frame.scrollbar_alpha <= 0.001 {
		return
	}

	transparency :=
		1 -
		(1 - frame.scrollbar_transparency)*
		frame.scrollbar_alpha

	_, vertical, vertical_visible :=
		scrolling_frame_vertical_bar(frame)

	if vertical_visible {
		vertical.color =
			frame.scrollbar_color

		vertical.bgTransparency =
			transparency

		radius :=
			min(
				vertical.width,
				vertical.height,
			)*0.5

		guilib.drawRoundedRect(
			ctx.renderer.SkiaSurface,
			vertical,
			radius,
		)
	}

	_, horizontal, horizontal_visible :=
		scrolling_frame_horizontal_bar(frame)

	if horizontal_visible {
		horizontal.color =
			frame.scrollbar_color

		horizontal.bgTransparency =
			transparency

		radius :=
			min(
				horizontal.width,
				horizontal.height,
			)*0.5

		guilib.drawRoundedRect(
			ctx.renderer.SkiaSurface,
			horizontal,
			radius,
		)
	}
}


ScrollingFrame_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	frame := new(ScrollingFrame)
	frame^ = ScrollingFrame_Init()
	frame.name = "ScrollingFrame"

	return &frame.object
}


ScrollingFrame_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	frame := cast(^ScrollingFrame)object

	if scrolling_frame_dragged == frame {
		scrolling_frame_dragged = nil
	}

	Object_Destroy(object)
	free(frame)
}


ScrollingFrame_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	frame := cast(^ScrollingFrame)object

	switch key {
	case "CanvasPosition":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Vector2(
			L,
			datatype_registry,
			frame.canvas_position,
		)

		return true

	case "CanvasSize":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_UDim2(
			L,
			datatype_registry,
			frame.canvas_size,
		)

		return true

	case "ScrollingEnabled":
		vm.PushBoolean(
			L,
			frame.scrolling_enabled,
		)
		return true

	case "ScrollSpeed":
		vm.PushNumber(
			L,
			f64(frame.scroll_speed),
		)
		return true

	case "SmoothScrollingEnabled":
		vm.PushBoolean(
			L,
			frame.smooth_scrolling,
		)
		return true

	case "ScrollSmoothness":
		vm.PushNumber(
			L,
			f64(frame.smoothness),
		)
		return true

	case "ScrollBarThickness":
		vm.PushNumber(
			L,
			f64(frame.scrollbar_thickness),
		)
		return true

	case "ScrollBarImageColor3":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Color3(
			L,
			datatype_registry,
			frame.scrollbar_color,
		)
		return true

	case "ScrollBarImageTransparency":
		vm.PushNumber(
			L,
			f64(
				frame.scrollbar_transparency,
			),
		)
		return true

	case "ScrollBarAutoHide":
		vm.PushBoolean(
			L,
			frame.scrollbar_auto_hide,
		)
		return true

	case "ScrollBarFadeDelay":
		vm.PushNumber(
			L,
			f64(frame.scrollbar_fade_delay),
		)
		return true

	case "ScrollBarFadeSpeed":
		vm.PushNumber(
			L,
			f64(frame.scrollbar_fade_speed),
		)
		return true

	case "ScrollBarMinimumHandleSize":
		vm.PushNumber(
			L,
			f64(frame.scrollbar_min_handle),
		)
		return true
	}

	return GuiObject_get(
		L,
		object,
		datatype_registry,
		enum_registry,
		key,
	)
}


ScrollingFrame_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	frame := cast(^ScrollingFrame)object

	switch key {
	case "CanvasPosition":
		if datatype_registry == nil {
			return false
		}

		position :=
			datatypes.Arg_Vector2(
				L,
				value_index,
				datatype_registry,
			)

		frame.canvas_position = position
		frame.target_position = position

		frame.canvas_position.X = clamp(
			frame.canvas_position.X,
			f32(0),
			frame.max_scroll_x,
		)

		frame.canvas_position.Y = clamp(
			frame.canvas_position.Y,
			f32(0),
			frame.max_scroll_y,
		)

		frame.target_position =
			frame.canvas_position

		scrolling_frame_interact(frame)
		return true

	case "CanvasSize":
		if datatype_registry == nil {
			return false
		}

		frame.canvas_size =
			datatypes.Arg_UDim2(
				L,
				value_index,
				datatype_registry,
			)

		return true

	case "ScrollingEnabled":
		frame.scrolling_enabled =
			vm.ArgBoolean(
				L,
				value_index,
			)

		if !frame.scrolling_enabled {
			frame.dragging_vertical = false
			frame.dragging_horizontal = false

			if scrolling_frame_dragged == frame {
				scrolling_frame_dragged = nil
			}
		}

		return true

	case "ScrollSpeed":
		frame.scroll_speed =
			max(
				f32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
				f32(0),
			)

		return true

	case "SmoothScrollingEnabled":
		frame.smooth_scrolling =
			vm.ArgBoolean(
				L,
				value_index,
			)

		return true

	case "ScrollSmoothness":
		frame.smoothness =
			max(
				f32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
				f32(0),
			)

		return true

	case "ScrollBarThickness":
		frame.scrollbar_thickness =
			max(
				f32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
				f32(0),
			)

		return true

	case "ScrollBarImageColor3":
		if datatype_registry == nil {
			return false
		}

		frame.scrollbar_color =
			datatypes.Arg_Color3(
				L,
				value_index,
				datatype_registry,
			)

		return true

	case "ScrollBarImageTransparency":
		frame.scrollbar_transparency =
			clamp(
				f32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
				f32(0),
				f32(1),
			)

		return true

	case "ScrollBarAutoHide":
		frame.scrollbar_auto_hide =
			vm.ArgBoolean(
				L,
				value_index,
			)

		return true

	case "ScrollBarFadeDelay":
		frame.scrollbar_fade_delay =
			max(
				f32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
				f32(0),
			)

		return true

	case "ScrollBarFadeSpeed":
		frame.scrollbar_fade_speed =
			max(
				f32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
				f32(0),
			)

		return true

	case "ScrollBarMinimumHandleSize":
		frame.scrollbar_min_handle =
			max(
				f32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
				f32(1),
			)

		return true
	}

	return GuiObject_set(
		L,
		object,
		datatype_registry,
		enum_registry,
		key,
		value_index,
	)
}


ScrollingFrame_render :: proc(
	object: ^Object,
	ctx: ^Class_Step_Context,
) {
	frame := cast(^ScrollingFrame)object

	rect, visible :=
		GuiObject_get_rect(
			object,
			ctx,
		)

	if !visible {
		return
	}

	scrolling_frame_update_animation(
		frame,
		rect,
		ctx.delta_time,
	)

	// GuiObject_render:
	// - updates AbsolutePosition / AbsoluteSize
	// - draws background/corners/shadows
	// - clips descendants because ClipsDescendants=true
	// - renders children
	// - draws UIStroke
	GuiObject_render(
		object,
		ctx,
	)

	scrolling_frame_draw_scrollbars(
		frame,
		ctx,
	)
}


ScrollingFrame_clone :: proc(
	source: ^Object,
	destination: ^Object,
) {
	src := cast(^ScrollingFrame)source
	dst := cast(^ScrollingFrame)destination

	dst.canvas_position = src.canvas_position
	dst.target_position = src.canvas_position
	dst.canvas_size = src.canvas_size

	dst.scrolling_enabled = src.scrolling_enabled
	dst.scroll_speed = src.scroll_speed

	dst.smooth_scrolling = src.smooth_scrolling
	dst.smoothness = src.smoothness

	dst.scrollbar_thickness = src.scrollbar_thickness
	dst.scrollbar_color = src.scrollbar_color
	dst.scrollbar_transparency = src.scrollbar_transparency
	dst.scrollbar_auto_hide = src.scrollbar_auto_hide
	dst.scrollbar_fade_delay = src.scrollbar_fade_delay
	dst.scrollbar_fade_speed = src.scrollbar_fade_speed
	dst.scrollbar_min_handle = src.scrollbar_min_handle

	dst.scrollbar_alpha = 0
	dst.idle_time = 999

	dst.max_scroll_x = 0
	dst.max_scroll_y = 0

	dst.dragging_vertical = false
	dst.dragging_horizontal = false
	dst.drag_mouse_start = 0
	dst.drag_canvas_start = 0
}


scrolling_frame_find_at_point :: proc(
	registry: ^Registry,
	x, y: f32,
) -> ^ScrollingFrame {
	if registry == nil {
		return nil
	}

	descriptor :=
		Find_Class(
			registry,
			"ScrollingFrame",
		)

	if descriptor == nil {
		return nil
	}

	best: ^ScrollingFrame
	best_z: i32
	best_depth: int
	found := false

	for object in descriptor.instances {
		if object == nil ||
		   object.destroyed {
			continue
		}

		frame :=
			cast(^ScrollingFrame)object

		if !frame.scrolling_enabled ||
		   !scrolling_frame_contains_point(
			   frame,
			   x,
			   y,
		   ) {
			continue
		}

		depth :=
			scrolling_frame_depth(
				frame,
			)

		if !found ||
		   frame.zindex > best_z ||
		   (frame.zindex == best_z &&
		    depth >= best_depth) {
			best = frame
			best_z = frame.zindex
			best_depth = depth
			found = true
		}
	}

	return best
}


ScrollingFrame_Handle_Event :: proc(
	registry: ^Registry,
	event: sdl3.Event,
) {
	if registry == nil {
		return
	}

	#partial switch event.type {
	case .MOUSE_WHEEL:
		frame :=
			scrolling_frame_find_at_point(
				registry,
				event.wheel.mouse_x,
				event.wheel.mouse_y,
			)

		if frame == nil {
			return
		}

		delta_x :=
			event.wheel.x

		delta_y :=
			event.wheel.y

		// SDL reports wheel-up as positive Y.
		// CanvasPosition should decrease when scrolling upward.
		modifiers :=
			sdl3.GetModState()

		shift :=
			.LSHIFT in modifiers ||
			.RSHIFT in modifiers

		if shift &&
		   abs(delta_x) < 0.001 {
			delta_x = delta_y
			delta_y = 0
		}

		scrolling_frame_set_target(
			frame,

			frame.target_position.X -
			delta_x*frame.scroll_speed,

			frame.target_position.Y -
			delta_y*frame.scroll_speed,
		)

	case .MOUSE_BUTTON_DOWN:
		if event.button.button !=
		   sdl3.BUTTON_LEFT {
			return
		}

		frame :=
			scrolling_frame_find_at_point(
				registry,
				event.button.x,
				event.button.y,
			)

		if frame == nil {
			return
		}

		vertical_track,
		vertical_handle,
		vertical_visible :=
			scrolling_frame_vertical_bar(
				frame,
			)

		horizontal_track,
		horizontal_handle,
		horizontal_visible :=
			scrolling_frame_horizontal_bar(
				frame,
			)

		if vertical_visible &&
		   scrolling_frame_point_in_rect(
			   vertical_handle,
			   event.button.x,
			   event.button.y,
		   ) {
			frame.dragging_vertical = true
			frame.dragging_horizontal = false
			frame.drag_mouse_start = event.button.y
			frame.drag_canvas_start =
				frame.canvas_position.Y

			scrolling_frame_dragged = frame
			scrolling_frame_interact(frame)
			return
		}

		if horizontal_visible &&
		   scrolling_frame_point_in_rect(
			   horizontal_handle,
			   event.button.x,
			   event.button.y,
		   ) {
			frame.dragging_horizontal = true
			frame.dragging_vertical = false
			frame.drag_mouse_start = event.button.x
			frame.drag_canvas_start =
				frame.canvas_position.X

			scrolling_frame_dragged = frame
			scrolling_frame_interact(frame)
			return
		}

		// Clicking the scrollbar track pages toward the mouse.
		if vertical_visible &&
		   scrolling_frame_point_in_rect(
			   vertical_track,
			   event.button.x,
			   event.button.y,
		   ) {
			if event.button.y <
			   vertical_handle.y {
				scrolling_frame_set_target(
					frame,
					frame.target_position.X,
					frame.target_position.Y -
					frame.absolute_size.Y,
				)
			} else if event.button.y >
			          vertical_handle.y +
			          vertical_handle.height {
				scrolling_frame_set_target(
					frame,
					frame.target_position.X,
					frame.target_position.Y +
					frame.absolute_size.Y,
				)
			}

			return
		}

		if horizontal_visible &&
		   scrolling_frame_point_in_rect(
			   horizontal_track,
			   event.button.x,
			   event.button.y,
		   ) {
			if event.button.x <
			   horizontal_handle.x {
				scrolling_frame_set_target(
					frame,
					frame.target_position.X -
					frame.absolute_size.X,
					frame.target_position.Y,
				)
			} else if event.button.x >
			          horizontal_handle.x +
			          horizontal_handle.width {
				scrolling_frame_set_target(
					frame,
					frame.target_position.X +
					frame.absolute_size.X,
					frame.target_position.Y,
				)
			}

			return
		}

	case .MOUSE_MOTION:
		frame :=
			scrolling_frame_dragged

		if frame == nil ||
		   !frame.scrolling_enabled {
			return
		}

		if frame.dragging_vertical {
			track,
			handle,
			visible :=
				scrolling_frame_vertical_bar(
					frame,
				)

			if !visible {
				return
			}

			travel :=
				max(
					track.height -
					handle.height,
					f32(0),
				)

			if travel <= 0 {
				return
			}

			mouse_delta :=
				event.motion.y -
				frame.drag_mouse_start

			canvas_delta :=
				mouse_delta /
				travel *
				frame.max_scroll_y

			target_y :=
				clamp(
					frame.drag_canvas_start +
					canvas_delta,
					f32(0),
					frame.max_scroll_y,
				)

			frame.target_position.Y =
				target_y

			// Scrollbar dragging tracks the mouse directly.
			frame.canvas_position.Y =
				target_y

			scrolling_frame_interact(frame)
			return
		}

		if frame.dragging_horizontal {
			track,
			handle,
			visible :=
				scrolling_frame_horizontal_bar(
					frame,
				)

			if !visible {
				return
			}

			travel :=
				max(
					track.width -
					handle.width,
					f32(0),
				)

			if travel <= 0 {
				return
			}

			mouse_delta :=
				event.motion.x -
				frame.drag_mouse_start

			canvas_delta :=
				mouse_delta /
				travel *
				frame.max_scroll_x

			target_x :=
				clamp(
					frame.drag_canvas_start +
					canvas_delta,
					f32(0),
					frame.max_scroll_x,
				)

			frame.target_position.X =
				target_x

			frame.canvas_position.X =
				target_x

			scrolling_frame_interact(frame)
			return
		}

	case .MOUSE_BUTTON_UP:
		if event.button.button !=
		   sdl3.BUTTON_LEFT {
			return
		}

		frame :=
			scrolling_frame_dragged

		if frame == nil {
			return
		}

		frame.dragging_vertical = false
		frame.dragging_horizontal = false

		scrolling_frame_interact(frame)
		scrolling_frame_dragged = nil
	}
}


Register_ScrollingFrame :: proc(
	registry: ^Registry,
) {
	Register_Class(
		registry,
		&ScrollingFrame_Class,
		ScrollingFrame_construct,
		ScrollingFrame_destroy,
		get = ScrollingFrame_get,
		set = ScrollingFrame_set,
		clone = ScrollingFrame_clone,
	)
}
