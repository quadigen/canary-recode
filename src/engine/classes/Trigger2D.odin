package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import tracy "../util/odin-tracy"
import vm "../vm"
import box2d "vendor:box2d"

Query2D_PIXELS_PER_METER :: f32(32)
Trigger2D_Class := Class_Info {
	name   = "Trigger2D",
	parent = &WorldObject2D_Class,
}
Query2D_State :: struct {
	world:         box2d.WorldId,
	width, height: i32,
}
Trigger2D :: struct {
	using world_object:   WorldObject2D,
	query:                Query2D_State,
	enabled, is_ball:     bool,
	touched, touch_ended: ^signals.Signal,
	previous_overlaps:    map[datatypes.UniqueId]i32,
}
Trigger2D_construct :: proc(r: ^Renderer_Object, dm: rawptr) -> ^Object {
	n := new(
		Trigger2D,
	); n.world_object = WorldObject2D_Init(&Trigger2D_Class); n.name = "Trigger2D"; n.size = {0, 100, 0, 100}; n.enabled = true; return &n.object
}
Trigger2D_destroy :: proc(o: ^Object, r: ^Renderer_Object) {
	n := cast(^Trigger2D)o
	if o.signal_registry != nil &&
	   o.signal_registry.vm_state != nil &&
	   o.signal_registry.vm_state.L != nil &&
	   !vm.Is_Closing() {
		for _, ref in n.previous_overlaps {vm.ReleaseValue(o.signal_registry.vm_state.L, ref)}
	}
	delete(n.previous_overlaps)
	signals.Destroy(n.touched); signals.Destroy(n.touch_ended)
	GuiObject_Free_Signals(&n.gui); Object_Destroy(o); free(n)
}
Query2D_Set_World :: proc(o: ^Object, w: box2d.WorldId, width, height: i32) {
	if Is_A_Class(o, &Trigger2D_Class) {(cast(^Trigger2D)o).query = {w, width, height}}

}
query2d_context :: proc(q: Query2D_State) -> Class_Step_Context {
	return Class_Step_Context{viewport_width = q.width, viewport_height = q.height}
}
query2d_active :: proc(o: ^Object, q: Query2D_State) -> bool {
	if o == nil || o.destroyed || !box2d.World_IsValid(q.world) {return false}
	for p := o.parent; p != nil; p = p.parent {
		if p.destroyed {return false}
		if Is_A_Class(p, &World2D_Class) && !(cast(^World2D)p).enabled {return false}
		if Is_A(p, "Workspace") || Is_A(p, "Workspace2D") {return true}
	}
	return false
}
query2d_part :: proc(id: box2d.ShapeId) -> ^Part2D {
	if !box2d.Shape_IsValid(id) {return nil}
	p := cast(^Part2D)box2d.Shape_GetUserData(id)
	if p == nil || p.destroyed {return nil}
	return p
}
query2d_ignored_parent :: proc(o: ^Object) -> ^Object {
	for p := o.parent; p != nil; p = p.parent {if Is_A_Class(p, &Part2D_Class) {return p}}
	return nil
}

Trigger2D_get :: proc(
	L: ^vm.State,
	o: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
) -> bool {
	n := cast(^Trigger2D)o
	switch key {
	case "Touched", "TouchEnded":
		slot := &n.touched if key == "Touched" else &n.touch_ended
		if slot^ == nil &&
		   o.signal_registry != nil &&
		   o.signal_registry.signal_registry !=
			   nil {slot^ = signals.Create(o.signal_registry.signal_registry)}
		if slot^ == nil {return false}
		signals.Push(L, slot^)
	case "Enabled":
		vm.PushBoolean(L, n.enabled)
	case "IsBall":
		vm.PushBoolean(L, n.is_ball)
	case "GetTouchingParts":
		vm.PushUserdataMethod(L, key)
	case:
		return GuiObject_get(L, o, dr, er, key)
	}
	return true
}
Trigger2D_set :: proc(
	L: ^vm.State,
	o: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	n := cast(^Trigger2D)o
	switch key {
	case "Enabled":
		n.enabled = vm.ArgBoolean(L, index)
	case "IsBall":
		n.is_ball = vm.ArgBoolean(L, index)
	case:
		return GuiObject_set(L, o, dr, er, key, index)
	}
	return true
}
Trigger2D_clone :: proc(src, dst: ^Object) {
	a, b := cast(^Trigger2D)src, cast(^Trigger2D)dst; b.enabled, b.is_ball = a.enabled, a.is_ball
}
Trigger2D_Overlap_Context :: struct {
	results: [dynamic]^Part2D,
	ignore:  ^Object,
}
trigger2d_overlap_callback :: proc "c" (id: box2d.ShapeId, data: rawptr) -> bool {
	context = tracy.DefaultContext()
	q := cast(^Trigger2D_Overlap_Context)data
	p := query2d_part(id)
	if p != nil && &p.object != q.ignore {
		for old in q.results {if old == p {return true}}
		append(&q.results, p)
	}
	return true
}
Trigger2D_Query :: proc(n: ^Trigger2D, results: ^Trigger2D_Overlap_Context) {
	if !n.enabled || !query2d_active(&n.object, n.query) {return}
	ctx := query2d_context(n.query)
	_, _, w, h := GuiObject_get_absolute_transform(&n.object, &ctx)
	if !part2d_finite(w) || !part2d_finite(h) || min(w, h) < 0.1 {return}
	center, angle := WorldObject2D_World_Point(&n.object, &ctx, {w * 0.5, h * 0.5})
	if !part2d_finite(center[0]) || !part2d_finite(center[1]) || !part2d_finite(angle) {return}
	points: [4]box2d.Vec2
	radius: f32
	count := 4
	if n.is_ball {
		count = 1; radius = min(w, h) * 0.5 / Query2D_PIXELS_PER_METER
	} else {
		hw, hh := w * 0.5, h * 0.5
		points = {{-hw, -hh}, {hw, -hh}, {hw, hh}, {-hw, hh}}
		for &p in points {p = world2d_rotate(p, angle) / Query2D_PIXELS_PER_METER}
	}
	proxy := box2d.MakeProxy(points[:count], radius)
	results.ignore = query2d_ignored_parent(&n.object)
	_ = box2d.World_OverlapShape(
		n.query.world,
		center / Query2D_PIXELS_PER_METER,
		proxy,
		box2d.DefaultQueryFilter(),
		trigger2d_overlap_callback,
		results,
	)
}


Trigger2D_Update :: proc(o: ^Object, ctx: ^Class_Step_Context) {
	n := cast(^Trigger2D)o
	L := ctx.L
	if L == nil || vm.Is_Closing() || (n.touched == nil && n.touch_ended == nil) {return}
	results: Trigger2D_Overlap_Context
	defer delete(results.results)
	Trigger2D_Query(n, &results)
	next := make(map[datatypes.UniqueId]i32)
	for part in results.results {
		if !Object_Is_Accessible(L, &part.object) {continue}
		id := part.unique_id
		if ref, found := n.previous_overlaps[id]; found {
			next[id] = ref; delete_key(&n.previous_overlaps, id)
		} else {
			Push_Object(L, &part.object)
			if vm.IsNil(L, -1) {vm.Pop(L, 1); continue}
			next[id] = vm.RetainValue(L)
			if n.touched != nil {signals.Signal_Fire_Deferred(L, n.touched, vm.StackTop(L), 1)}
			vm.Pop(L, 1)
		}
	}
	for _, ref in n.previous_overlaps {
		if n.touch_ended != nil {
			vm.PushRegistryReference(L, ref)
			p := object_from_argument(L, -1)
			if p == nil || p.destroyed {vm.Pop(L, 1); vm.PushNil(L)}
			signals.Signal_Fire_Deferred(L, n.touch_ended, vm.StackTop(L), 1)
			vm.Pop(L, 1)
		}
		vm.ReleaseValue(L, ref)
	}
	delete(n.previous_overlaps)
	n.previous_overlaps = next
}
Trigger2D_namecall :: proc(
	L: ^vm.State,
	o: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "GetTouchingParts" {return 0, false}
	results: Trigger2D_Overlap_Context
	defer delete(results.results)
	Trigger2D_Query(cast(^Trigger2D)o, &results)
	vm.NewTable(L, len(results.results), 0)
	i := 1
	for p in results.results {
		if !Object_Is_Accessible(L, &p.object) {continue}
		Push_Object(L, &p.object)
		vm.RawSetIndex(L, -2, i)
		i += 1
	}
	return 1, true
}
Register_Trigger2D :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Trigger2D_Class,
		Trigger2D_construct,
		Trigger2D_destroy,
		get = Trigger2D_get,
		set = Trigger2D_set,
		namecall = Trigger2D_namecall,
		clone = Trigger2D_clone,
		properties = []string{"Enabled", "IsBall"},
		_step = Trigger2D_Update,
		_step_phase = .Update,
		events = []string{"Touched", "TouchEnded"},
		methods = []string{"GetTouchingParts"},
	)
}
