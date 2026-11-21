package classes

import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"
import "core:math"


WorldObject2D_Class := Class_Info {
	name   = "WorldObject2D",
	parent = &GuiObject_Class,
}
Attachment2D_Class := Class_Info {
	name   = "Attachment2D",
	parent = &WorldObject2D_Class,
}
Camera2D_Class := Class_Info {
	name   = "Camera2D",
	parent = &WorldObject2D_Class,
}

WorldObject2D :: struct {
	using gui: GuiObject,
}
Attachment2D :: struct {
	using world_object: WorldObject2D,
}
Camera2D :: struct {
	using world_object: WorldObject2D,
	enabled:            bool,
	zoom:               f32,
}

WorldObject2D_Init :: proc(info: ^Class_Info) -> WorldObject2D {
	gui := GuiObject_Init()
	gui.object.class = info
	gui.bg_transparency = 1
	gui.size = {}
	return WorldObject2D{gui = gui}
}
WorldObject2D_construct :: proc(r: ^Renderer_Object, dm: rawptr) -> ^Object {
	n := new(WorldObject2D)
	n^ = WorldObject2D_Init(&WorldObject2D_Class)
	n.name = "WorldObject2D"
	return &n.object
}
Attachment2D_construct :: proc(r: ^Renderer_Object, dm: rawptr) -> ^Object {
	n := new(Attachment2D)
	n.world_object = WorldObject2D_Init(&Attachment2D_Class)
	n.name = "Attachment2D"
	return &n.object
}
Camera2D_construct :: proc(r: ^Renderer_Object, dm: rawptr) -> ^Object {
	n := new(Camera2D)
	n.world_object = WorldObject2D_Init(&Camera2D_Class)
	n.name = "Camera2D"
	n.enabled = true
	n.zoom = 1
	return &n.object
}
WorldObject2D_destroy :: proc(o: ^Object, r: ^Renderer_Object) {
	GuiObject_Free_Signals(cast(^GuiObject)o); Object_Destroy(o); free(cast(^WorldObject2D)o)
}
Attachment2D_destroy :: proc(o: ^Object, r: ^Renderer_Object) {
	GuiObject_Free_Signals(cast(^GuiObject)o); Object_Destroy(o); free(cast(^Attachment2D)o)
}
Camera2D_destroy :: proc(o: ^Object, r: ^Renderer_Object) {
	GuiObject_Free_Signals(cast(^GuiObject)o); Object_Destroy(o); free(cast(^Camera2D)o)
}
world2d_rotate :: proc(p: [2]f32, degrees: f32) -> [2]f32 {
	r := degrees * (math.PI / 180)
	c, s := math.cos(r), math.sin(r)
	return {p[0] * c - p[1] * s, p[0] * s + p[1] * c}
}

WorldObject2D_World_Point :: proc(
	o: ^Object,
	ctx: ^Class_Step_Context,
	local: [2]f32,
) -> (
	point: [2]f32,
	angle: f32,
) {
	x, y, _, _ := GuiObject_get_absolute_transform(o, ctx)
	point = {x + local[0], y + local[1]}
	for p := o; p != nil; p = p.parent {
		if !Is_A_Class(p, &GuiObject_Class) {continue}
		g := cast(^GuiObject)p
		rotation := f32(g.rotation)
		if rotation == 0 {continue}
		px, py, w, h := GuiObject_get_absolute_transform(p, ctx)
		center := [2]f32{px + w * 0.5, py + h * 0.5}
		point = center + world2d_rotate(point - center, rotation)
		angle += rotation
	}
	return
}
Camera2D_get :: proc(
	L: ^vm.State,
	o: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
) -> bool {
	n := cast(^Camera2D)o
	switch key {
	case "Enabled":
		vm.PushBoolean(L, n.enabled)
	case "Zoom":
		vm.PushNumber(L, f64(n.zoom))
	case:
		return GuiObject_get(L, o, dr, er, key)
	}
	return true
}
Camera2D_set :: proc(
	L: ^vm.State,
	o: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	n := cast(^Camera2D)o
	switch key {
	case "Enabled":
		n.enabled = vm.ArgBoolean(L, index)
	case "Zoom":
		v := f32(vm.ArgNumber(L, index))
		if !part2d_finite(v) ||
		   v <= 0 {_ = vm.RaiseError(L, "Camera2D.Zoom must be positive and finite"); return true}
		n.zoom = clamp(v, 0.01, 100)
	case:
		return GuiObject_set(L, o, dr, er, key, index)
	}
	Gui_Render_Mark_Dirty()
	return true
}
Camera2D_clone :: proc(src, dst: ^Object) {
	a, b := cast(^Camera2D)src, cast(^Camera2D)dst
	b.enabled, b.zoom = a.enabled, a.zoom
}
Camera2D_Apply :: proc(n: ^Camera2D, ctx: ^Class_Step_Context) {
	point, rotation := WorldObject2D_World_Point(&n.object, ctx, {})
	if !part2d_finite(point[0]) || !part2d_finite(point[1]) || !part2d_finite(rotation) {return}
	surface := ctx.renderer.SkiaSurface
	guilib.translate(surface, f32(ctx.viewport_width) * 0.5, f32(ctx.viewport_height) * 0.5)
	guilib.scale(surface, n.zoom, n.zoom)
	guilib.rotate(surface, -rotation)
	guilib.translate(surface, -point[0], -point[1])
}
Register_WorldObject2D :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&WorldObject2D_Class,
		WorldObject2D_construct,
		WorldObject2D_destroy,
		creatable = false,
		get = GuiObject_get,
		set = GuiObject_set,
	)
}
Register_Attachment2D :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Attachment2D_Class,
		Attachment2D_construct,
		Attachment2D_destroy,
		get = GuiObject_get,
		set = GuiObject_set,
	)
}
Register_Camera2D :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Camera2D_Class,
		Camera2D_construct,
		Camera2D_destroy,
		get = Camera2D_get,
		set = Camera2D_set,
		clone = Camera2D_clone,
		properties = []string{"Enabled", "Zoom"},
	)
}
