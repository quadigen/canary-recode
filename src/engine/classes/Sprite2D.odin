package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Sprite2D_Class := Class_Info {
	name   = "Sprite2D",
	parent = &ImageLabel_Class,
}
Sprite2D :: struct {
	using label:     ImageLabel,
	frame_grid:      datatypes.Vector2,
	frame:           i32,
	frame_rate:      f32,
	playing, looped: bool,
	elapsed:         f64,
}
Sprite2D_construct :: proc(r: ^Renderer_Object, dm: rawptr) -> ^Object {
	s := new(Sprite2D)
	s.label = ImageLabel_Init()
	s.object.class = &Sprite2D_Class
	s.name = "Sprite2D"
	s.bg_transparency = 1
	s.frame_grid = {1, 1}
	s.frame_rate = 12
	s.looped = true
	return &s.object
}
Sprite2D_destroy :: proc(o: ^Object, r: ^Renderer_Object) {
	s := cast(^Sprite2D)o
	ImageLabel_Unbind_Editable(&s.label)
	ImageLabel_Destroy_Stored_Image(&s.label)
	GuiObject_Free_Signals(&s.gui_object)
	delete(s.owned_image)
	Object_Destroy(o)
	free(s)
}
Sprite2D_get :: proc(
	L: ^vm.State,
	o: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
) -> bool {
	s := cast(^Sprite2D)o
	switch key {
	case "FrameGrid":
		if dr == nil {return false}
		datatypes.Push_Vector2(L, dr, s.frame_grid)
	case "Frame":
		vm.PushNumber(L, f64(s.frame))
	case "FrameRate":
		vm.PushNumber(L, f64(s.frame_rate))
	case "Playing":
		vm.PushBoolean(L, s.playing)
	case "Looped":
		vm.PushBoolean(L, s.looped)
	case "Play", "Stop":
		vm.PushUserdataMethod(L, key)
	case:
		return ImageLabel_get(L, o, dr, er, key)
	}
	return true
}
Sprite2D_set :: proc(
	L: ^vm.State,
	o: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	s := cast(^Sprite2D)o
	switch key {
	case "FrameGrid":
		if dr == nil {return false}
		v := datatypes.Arg_Vector2(L, index, dr)
		if !part2d_finite(v.X) ||
		   !part2d_finite(v.Y) ||
		   v.X < 1 ||
		   v.Y < 1 ||
		   v.X > 256 ||
		   v.Y > 256 {
			_ = vm.RaiseError(L, "FrameGrid must contain 1 to 256 columns and rows")
			return true
		}
		s.frame_grid = {f32(i32(v.X)), f32(i32(v.Y))}
		s.frame = clamp(s.frame, 0, i32(s.frame_grid.X * s.frame_grid.Y) - 1)
	case "Frame":
		v := f32(vm.ArgNumber(L, index))
		if !part2d_finite(v) {_ = vm.RaiseError(L, "Frame must be finite"); return true}
		s.frame = i32(clamp(v, 0, s.frame_grid.X * s.frame_grid.Y - 1))
	case "FrameRate":
		v := f32(vm.ArgNumber(L, index))
		if !part2d_finite(v) {_ = vm.RaiseError(L, "FrameRate must be finite"); return true}
		s.frame_rate = clamp(v, 0, 1000)
	case "Playing":
		s.playing = vm.ArgBoolean(L, index)
	case "Looped":
		s.looped = vm.ArgBoolean(L, index)
	case:
		return ImageLabel_set(L, o, dr, er, key, index)
	}
	gui_invalidate_draw(o)
	Gui_Render_Mark_Dirty()
	return true
}
Sprite2D_clone :: proc(src, dst: ^Object) {
	a, b := cast(^Sprite2D)src, cast(^Sprite2D)dst
	b.frame_grid, b.frame, b.frame_rate, b.playing, b.looped =
		a.frame_grid, a.frame, a.frame_rate, a.playing, a.looped
}
Sprite2D_namecall :: proc(
	L: ^vm.State,
	o: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	s := cast(^Sprite2D)o
	switch method {
	case "Play":
		s.playing = true
	case "Stop":
		s.playing = false; s.frame = 0; s.elapsed = 0; gui_invalidate_draw(o)
		Gui_Render_Mark_Dirty()
	case:
		return 0, false
	}
	return 0, true
}
Sprite2D_Update :: proc(o: ^Object, dt: f32) {
	s := cast(^Sprite2D)o


	if s.animated_source {return}
	if !s.playing || s.frame_rate <= 0 || dt <= 0 || !part2d_finite(dt) {return}
	s.elapsed += f64(min(dt, 0.25)) * f64(s.frame_rate)
	steps := i32(s.elapsed)
	if steps < 1 {return}
	s.elapsed -= f64(steps)
	count := i32(s.frame_grid.X * s.frame_grid.Y)
	next := s.frame + steps
	if s.looped {next %= count} else if next >= count {next = count - 1; s.playing = false; s.elapsed = 0}
	if next != s.frame {s.frame = next; gui_invalidate_draw(o); Gui_Render_Mark_Dirty()}
}
Sprite2D_render :: proc(o: ^Object, ctx: ^Class_Step_Context) {
	s := cast(^Sprite2D)o
	_, visible := GuiObject_get_rect(o, ctx)
	if !visible {return}
	old_offset, old_size := s.image_rect_offset, s.image_rect_size
	defer {s.image_rect_offset = old_offset; s.image_rect_size = old_size}


	if !s.animated_source && s.stored_image != nil && (s.frame_grid.X > 1 || s.frame_grid.Y > 1) {
		cols := i32(s.frame_grid.X)
		width := f32(kineffi.Kine_Skia_Image_GetWidth(s.stored_image)) / s.frame_grid.X
		height := f32(kineffi.Kine_Skia_Image_GetHeight(s.stored_image)) / s.frame_grid.Y
		s.image_rect_offset = {width * f32(s.frame % cols), height * f32(s.frame / cols)}
		s.image_rect_size = {width, height}
	}
	ImageLabel_render(o, ctx)
}
Register_Sprite2D :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Sprite2D_Class,
		Sprite2D_construct,
		Sprite2D_destroy,
		get = Sprite2D_get,
		set = Sprite2D_set,
		namecall = Sprite2D_namecall,
		clone = Sprite2D_clone,
		properties = []string{"FrameGrid", "Frame", "FrameRate", "Playing", "Looped"},
		methods = []string{"Play", "Stop"},
	)
}
