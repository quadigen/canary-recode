package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"

Shape2D_Class := Class_Info {
	name   = "Shape2D",
	parent = &WorldObject2D_Class,
}
Shape2D :: struct {
	using world_object:      WorldObject2D,
	points:                  [dynamic]datatypes.Vector2,
	color:                   datatypes.Color3,
	transparency, thickness: f32,
	closed:                  bool,
}
Shape2D_construct :: proc(r: ^Renderer_Object, dm: rawptr) -> ^Object {
	n := new(Shape2D)
	n.world_object = WorldObject2D_Init(&Shape2D_Class)
	n.name = "Shape2D"
	n.color = {1, 1, 1}
	return &n.object
}
Shape2D_destroy :: proc(o: ^Object, r: ^Renderer_Object) {
	n := cast(^Shape2D)o
	delete(n.points)
	GuiObject_Free_Signals(&n.gui)
	Object_Destroy(o)
	free(n)
}
Shape2D_clone :: proc(src, dst: ^Object) {
	a, b := cast(^Shape2D)src, cast(^Shape2D)dst
	delete(b.points); b.points = nil
	append(&b.points, ..a.points[:])
	b.color, b.transparency, b.thickness, b.closed = a.color, a.transparency, a.thickness, a.closed
}
Shape2D_get :: proc(
	L: ^vm.State,
	o: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
) -> bool {
	n := cast(^Shape2D)o
	switch key {
	case "Points":
		if dr == nil {return false}
		vm.NewTable(L, len(n.points), 0)
		for p, i in n.points {datatypes.Push_Vector2(L, dr, p); vm.RawSetIndex(L, -2, i + 1)}
	case "Color":
		if dr == nil {return false}; datatypes.Push_Color3(L, dr, n.color)
	case "Transparency":
		vm.PushNumber(L, f64(n.transparency))
	case "Thickness":
		vm.PushNumber(L, f64(n.thickness))
	case "Closed":
		vm.PushBoolean(L, n.closed)
	case:
		return GuiObject_get(L, o, dr, er, key)
	}
	return true
}
Shape2D_set :: proc(
	L: ^vm.State,
	o: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	n := cast(^Shape2D)o
	switch key {
	case "Points":
		if dr == nil {return false}
		if !vm.IsTable(
			L,
			index,
		) {_ = vm.RaiseError(L, "Points requires an array of Vector2"); return true}
		count := vm.RawLen(L, index)
		if count > 65536 {_ = vm.RaiseError(L, "Too many points"); return true}
		for i in 1 ..= count {
			_ = vm.RawGetIndex(L, index, i)
			if !vm.IsUserdataType(
				L,
				-1,
				&dr.vector2,
			) {vm.Pop(L, 1); _ = vm.RaiseError(L, "Points requires Vector2 values"); return true}
			p := datatypes.Arg_Vector2(L, -1, dr); vm.Pop(L, 1)
			if !part2d_finite(p.X) ||
			   !part2d_finite(p.Y) {_ = vm.RaiseError(L, "Points must be finite"); return true}
		}
		clear(&n.points)
		for i in 1 ..= count {_ = vm.RawGetIndex(L, index, i); append(&n.points, datatypes.Arg_Vector2(L, -1, dr)); vm.Pop(L, 1)}
	case "Color":
		if dr == nil {return false}
		n.color = datatypes.Arg_Color3(L, index, dr)
	case "Thickness", "Transparency":
		v := f32(vm.ArgNumber(L, index))
		if !part2d_finite(v) {_ = vm.RaiseError(L, "Value must be finite"); return true}
		if key ==
		   "Thickness" {n.thickness = clamp(v, 0, 4096)} else {n.transparency = clamp(v, 0, 1)}
	case "Closed":
		n.closed = vm.ArgBoolean(L, index)
	case:
		return GuiObject_set(L, o, dr, er, key, index)
	}
	gui_invalidate_draw(o); Gui_Render_Mark_Dirty()
	return true
}
Shape2D_render :: proc(o: ^Object, ctx: ^Class_Step_Context) {
	n := cast(^Shape2D)o
	rect, visible := GuiObject_get_rect(o, ctx)
	if !visible {return}
	if len(n.points) >= 2 && n.transparency < 1 && (n.thickness > 0 || len(n.points) >= 3) {
		surface := ctx.renderer.SkiaSurface
		guilib.save(surface)
		guilib.translate(surface, rect.x, rect.y)
		r, g, b := guilib.colorToU8(n.color)
		a := guilib.alphaToU8(n.transparency)
		kineffi.Kine_Skia_Surface_DrawPolygon(
			surface,
			cast(^f32)raw_data(n.points),
			i32(len(n.points)),
			i32(n.closed),
			r,
			g,
			b,
			a,
			n.thickness,
		)
		guilib.restore(surface)
	}
	GuiObject_render(o, ctx)
}
Register_Shape2D :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Shape2D_Class,
		Shape2D_construct,
		Shape2D_destroy,
		get = Shape2D_get,
		set = Shape2D_set,
		clone = Shape2D_clone,
		properties = []string{"Points", "Color", "Transparency", "Thickness", "Closed"},
	)
}
