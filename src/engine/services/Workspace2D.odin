package services


import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import platform "../platform"
import renderer "../renderer"
import vm "../vm"
import "core:math"
import "core:slice"
import box2d "vendor:box2d"

Workspace2D_Class := classes.Class_Info {
	name   = "Workspace2D",
	parent = &Service_Class,
}


WORLD2D_PIXELS_PER_METER :: classes.Query2D_PIXELS_PER_METER
WORLD2D_STEP :: f32(1.0 / 60.0)


WORLD2D_MAX_POSITION_PIXELS :: f32(10_000_000)
WORLD2D_MAX_SIZE_PIXELS :: f32(100_000)
WORLD2D_MAX_SPEED_PIXELS :: f32(1_000_000)
WORLD2D_MAX_ANGULAR_SPEED_DEGREES :: f32(100_000)
WORLD2D_MAX_MATERIAL_VALUE :: f32(100_000)
World2D_Body :: struct {
	id:           box2d.BodyId,
	shape:        box2d.ShapeId,
	weld:         box2d.JointId,
	weld_root:    box2d.BodyId,
	group_index:  i32,
	center, size: [2]f32,
	angle:        f32,
	epoch:        u64,
}
Workspace2D :: struct {
	using service: Service,
	body_map:      map[^classes.Part2D]World2D_Body,
	parts:         [dynamic]^classes.Part2D,
	part_groups:   [dynamic]i32,
	group_roots:   [dynamic]^classes.Part2D,
	groups:        [dynamic]^classes.RigidBody2D,
	stale:         [dynamic]^classes.Part2D,
	world:         box2d.WorldId,
	gravity:       [2]f32,
	accumulator:   f32,
	epoch:         u64,
	width, height: i32,
}

Workspace2D_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Workspace2D)
	service.service = Service_Init(&Workspace2D_Class, "Workspace2D", data_model)
	service.gravity = {0, 130}
	service.width, service.height = 1280, 720
	service.body_map = make(map[^classes.Part2D]World2D_Body)
	return &service.object
}

workspace2d_ensure_world :: proc(ws: ^Workspace2D) {
	if box2d.World_IsValid(ws.world) {return}
	def := box2d.DefaultWorldDef()
	def.gravity = ws.gravity / WORLD2D_PIXELS_PER_METER
	def.enableSleep = true
	ws.world = box2d.CreateWorld(def)
}

workspace2d_release :: proc(owner: rawptr, part: ^classes.Part2D) {
	ws := cast(^Workspace2D)owner
	if body, found := ws.body_map[part]; found {
		if box2d.Body_IsValid(body.id) {box2d.DestroyBody(body.id)}
		delete_key(&ws.body_map, part)
	}
	part.physics_owner = nil
	part.physics_release = nil
}

Workspace2D_Clear :: proc(ws: ^Workspace2D) {
	if ws == nil {return}
	for part in ws.body_map {
		part.physics_owner = nil
		part.physics_release = nil
	}
	clear(&ws.body_map)
	clear(&ws.parts)
	clear(&ws.part_groups)
	clear(&ws.group_roots)
	clear(&ws.groups)
	clear(&ws.stale)
	if box2d.World_IsValid(ws.world) {box2d.DestroyWorld(ws.world)}
	ws.world = {}
	ws.accumulator = 0
}

workspace2d_collect :: proc(
	ws: ^Workspace2D,
	parent: ^classes.Object,
	dt: f32,
	group_index: i32 = 0,
) {
	for child in parent.children {
		if child == nil || child.destroyed {continue}
		if classes.Is_A_Class(child, &classes.World2D_Class) &&
		   !(cast(^classes.World2D)child).enabled {continue}
		if classes.Is_A_Class(child, &classes.ScreenGui_Class) ||
		   classes.Is_A_Class(child, &classes.SurfaceGui_Class) {continue}
		classes.Query2D_Set_World(child, ws.world, ws.width, ws.height)
		if classes.Is_A_Class(child, &classes.Sprite2D_Class) {classes.Sprite2D_Update(child, dt)}
		group := group_index

		if classes.Is_A_Class(child, &classes.RigidBody2D_Class) {
			append(&ws.groups, cast(^classes.RigidBody2D)child)
			append(&ws.group_roots, nil)
			group = -i32(len(ws.group_roots))
		}
		if classes.Is_A_Class(child, &classes.Part2D_Class) {
			append(&ws.parts, cast(^classes.Part2D)child)
			append(
				&ws.part_groups,
				0 if classes.Is_A_Class(child, &classes.CharacterController2D_Class) else group,
			)
		}
		workspace2d_collect(ws, child, dt, group)
	}
}

world2d_finite :: proc(n: f32) -> bool {
	return !math.is_nan(n) && !math.is_inf(n)
}

world2d_bounded :: proc(value, max_abs: f32) -> bool {
	return world2d_finite(value) && abs(value) <= max_abs
}

workspace2d_shape :: proc(part: ^classes.Part2D, body: ^World2D_Body) {
	def := box2d.DefaultShapeDef()
	def.density = part.density
	def.material.friction = part.friction
	def.material.restitution = part.elasticity
	if !part.can_collide {def.filter.maskBits = 0}
	def.filter.groupIndex = body.group_index
	def.userData = part
	if part.is_ball {
		circle := box2d.Circle {
			radius = min(body.size[0], body.size[1]) / (2 * WORLD2D_PIXELS_PER_METER),
		}
		body.shape = box2d.CreateCircleShape(body.id, def, circle)
	} else {
		polygon := box2d.MakeBox(
			body.size[0] / (2 * WORLD2D_PIXELS_PER_METER),
			body.size[1] / (2 * WORLD2D_PIXELS_PER_METER),
		)
		body.shape = box2d.CreatePolygonShape(body.id, def, polygon)
	}
	part.shape_dirty = false
}

workspace2d_sync :: proc(
	ws: ^Workspace2D,
	part: ^classes.Part2D,
	ctx: ^classes.Class_Step_Context,
	group_index: i32,
) {
	center, size, angle := classes.Part2D_Resolve_Transform(part, ctx)
	if !world2d_bounded(center[0], WORLD2D_MAX_POSITION_PIXELS) ||
	   !world2d_bounded(center[1], WORLD2D_MAX_POSITION_PIXELS) ||
	   !world2d_bounded(size[0], WORLD2D_MAX_SIZE_PIXELS) ||
	   !world2d_bounded(size[1], WORLD2D_MAX_SIZE_PIXELS) ||
	   !world2d_bounded(angle, f32(1_000_000)) ||
	   min(size[0], size[1]) < 0.1 ||
	   !world2d_bounded(part.density, WORLD2D_MAX_MATERIAL_VALUE) ||
	   !world2d_bounded(part.friction, WORLD2D_MAX_MATERIAL_VALUE) ||
	   !world2d_bounded(part.elasticity, f32(1)) ||
	   !world2d_bounded(part.velocity[0], WORLD2D_MAX_SPEED_PIXELS) ||
	   !world2d_bounded(part.velocity[1], WORLD2D_MAX_SPEED_PIXELS) ||
	   !world2d_bounded(part.angular_velocity, WORLD2D_MAX_ANGULAR_SPEED_DEGREES) {
		if part.physics_owner == ws {workspace2d_release(ws, part)}
		return
	}
	part.absolute_position = {center[0] - size[0] * 0.5, center[1] - size[1] * 0.5}
	part.absolute_size = {size[0], size[1]}
	character := classes.Is_A_Class(&part.object, &classes.CharacterController2D_Class)
	kinematic := character
	body_type :=
		box2d.BodyType.staticBody if part.anchored else (box2d.BodyType.kinematicBody if kinematic else box2d.BodyType.dynamicBody)
	body, exists := ws.body_map[part]
	if !exists {
		if part.physics_owner != nil &&
		   part.physics_release != nil {part.physics_release(part.physics_owner, part)}
		def := box2d.DefaultBodyDef()
		def.type = body_type
		def.position = center / WORLD2D_PIXELS_PER_METER
		def.rotation = box2d.MakeRot(angle * (math.PI / 180))
		if !character {
			def.linearVelocity = part.velocity / WORLD2D_PIXELS_PER_METER
			def.angularVelocity = part.angular_velocity * (math.PI / 180)
		}
		body = {
			id          = box2d.CreateBody(ws.world, def),
			center      = center,
			size        = size,
			angle       = angle,
			group_index = group_index,
		}
		workspace2d_shape(part, &body)
		part.physics_owner = ws
		part.physics_release = workspace2d_release
		if character {(cast(^classes.CharacterController2D)part).move_and_slide = workspace2d_character_move}
	} else {
		if box2d.Body_GetType(body.id) != body_type {
			box2d.Body_SetType(body.id, body_type)
		}
		if body.group_index != group_index {
			body.group_index = group_index
			part.shape_dirty = true
		}
		if body.size != size || part.shape_dirty {
			box2d.DestroyShape(body.shape, true)
			body.size = size
			workspace2d_shape(part, &body)
		}

		if abs(center[0] - body.center[0]) > 0.001 ||
		   abs(center[1] - body.center[1]) > 0.001 ||
		   abs(angle - body.angle) > 0.001 {
			box2d.Body_SetTransform(
				body.id,
				center / WORLD2D_PIXELS_PER_METER,
				box2d.MakeRot(angle * (math.PI / 180)),
			)
			if !part.anchored {box2d.Body_SetAwake(body.id, true)}
		}
	}
	if !part.anchored && !character {
		if part.velocity_dirty {box2d.Body_SetLinearVelocity(body.id, part.velocity / WORLD2D_PIXELS_PER_METER)}
		if part.angular_dirty {box2d.Body_SetAngularVelocity(body.id, part.angular_velocity * (math.PI / 180))}
		part.velocity_dirty, part.angular_dirty = false, false
	}
	body.center, body.angle, body.epoch = center, angle, ws.epoch
	ws.body_map[part] = body
}

workspace2d_sync_welds :: proc(ws: ^Workspace2D) {

	for part, i in ws.parts {
		group := ws.part_groups[i]
		if group == 0 || part not_in ws.body_map {continue}
		index := int(-group - 1)
		root := ws.group_roots[index]
		if root == nil || (part.anchored && !root.anchored) {ws.group_roots[index] = part}
	}
	for part, i in ws.parts {
		body, found := ws.body_map[part]
		if !found {continue}
		group := ws.part_groups[i]
		root: ^classes.Part2D
		if group < 0 {root = ws.group_roots[int(-group - 1)]}
		root_id: box2d.BodyId
		if root != nil &&
		   root != part &&
		   !(root.anchored && part.anchored) {root_id = ws.body_map[root].id}
		if body.weld_root != root_id ||
		   (box2d.Body_IsValid(root_id) && !box2d.Joint_IsValid(body.weld)) {
			if box2d.Joint_IsValid(body.weld) {box2d.DestroyJoint(body.weld)}
			body.weld = {}
			body.weld_root = root_id
			if box2d.Body_IsValid(root_id) {
				def := box2d.DefaultWeldJointDef()
				def.bodyIdA, def.bodyIdB = root_id, body.id
				root_xf := box2d.Body_GetTransform(root_id)
				part_xf := box2d.Body_GetTransform(body.id)
				def.localFrameA = box2d.InvMulTransforms(root_xf, part_xf)
				def.localFrameB = box2d.Transform_identity
				def.collideConnected = false
				body.weld = box2d.CreateWeldJoint(ws.world, def)
			}
			ws.body_map[part] = body
		}
	}
}

Workspace2D_Step :: proc(ws: ^Workspace2D, workspace: ^Workspace, delta_time: f32) {
	if ws == nil || workspace == nil {return}
	workspace2d_ensure_world(ws)
	if ws.data_model != nil && ws.data_model.registry != nil {
		r := ws.data_model.registry.classes.renderer
		width, height := renderer.viewport_size(r)
		if width > 0 && height > 0 {
			if !r.ViewportRect_Host {
				width -= i32(platform.UI_Safe_Left + platform.UI_Safe_Right)
				height -= i32(platform.UI_Safe_Top + platform.UI_Safe_Bottom)
			}
			scale := max(platform.UI_Scale, 0.01)
			ws.width, ws.height = max(i32(f32(width) / scale), 1), max(i32(f32(height) / scale), 1)
		}
	}
	ws.epoch += 1
	clear(&ws.parts)
	clear(&ws.part_groups)
	clear(&ws.group_roots)
	clear(&ws.groups)
	workspace2d_collect(ws, &workspace.object, delta_time)
	workspace2d_collect(ws, &ws.object, delta_time)
	ctx := classes.Class_Step_Context {
		viewport_width  = ws.width,
		viewport_height = ws.height,
	}
	for part, i in ws.parts {workspace2d_sync(ws, part, &ctx, ws.part_groups[i])}
	clear(&ws.stale)
	for part, body in ws.body_map {
		if body.epoch != ws.epoch {append(&ws.stale, part)}
	}
	for part in ws.stale {workspace2d_release(ws, part)}
	workspace2d_sync_welds(ws)
	if !workspace.simulate_physics {
		ws.accumulator = 0
		return
	}
	if !world2d_finite(delta_time) || delta_time <= 0 {return}
	ws.accumulator += min(delta_time, 0.1)
	if ws.accumulator >= WORLD2D_STEP {
		for part in ws.parts {
			body, found := ws.body_map[part]
			if !found {continue}
			if !part.anchored && box2d.Body_GetType(body.id) == .dynamicBody {
				if part.pending_impulse != ([2]f32{}) {
					box2d.Body_ApplyLinearImpulseToCenter(
						body.id,
						part.pending_impulse / WORLD2D_PIXELS_PER_METER,
						true,
					)
				}
				if part.pending_angular_impulse != 0 {
					box2d.Body_ApplyAngularImpulse(
						body.id,
						part.pending_angular_impulse /
						(WORLD2D_PIXELS_PER_METER * WORLD2D_PIXELS_PER_METER),
						true,
					)
				}
			}
			part.pending_impulse, part.pending_angular_impulse = {}, 0
		}
	}
	for ws.accumulator >= WORLD2D_STEP {
		box2d.World_Step(ws.world, WORLD2D_STEP, 4)
		ws.accumulator -= WORLD2D_STEP
	}
	for part in ws.parts {
		body, found := ws.body_map[part]
		if !found ||
		   part.anchored ||
		   classes.Is_A_Class(&part.object, &classes.CharacterController2D_Class) {continue}
		transform := box2d.Body_GetTransform(body.id)
		center := transform.p * WORLD2D_PIXELS_PER_METER
		angle := box2d.Rot_GetAngle(transform.q) * (180 / math.PI)
		old, _, _ := classes.Part2D_Resolve_Transform(part, &ctx)
		classes.Part2D_Move(part, center - old, angle)
		if body.group_index < 0 {
			index := int(-body.group_index - 1)
			if ws.group_roots[index] == part {
				assembly := ws.groups[index]
				if assembly.pivot_set {
					old_cf := datatypes.CFrame_Mul_CFrame(
						datatypes.CFrame_New_Position(
							{f64(body.center[0]), f64(body.center[1]), 0},
						),
						datatypes.CFrame_Angles(0, 0, f64(body.angle) * math.PI / 180),
					)
					new_cf := datatypes.CFrame_Mul_CFrame(
						datatypes.CFrame_New_Position({f64(center[0]), f64(center[1]), 0}),
						datatypes.CFrame_Angles(0, 0, f64(angle) * math.PI / 180),
					)
					assembly.pivot = datatypes.CFrame_Mul_CFrame(
						datatypes.CFrame_Mul_CFrame(new_cf, datatypes.CFrame_Inverse(old_cf)),
						assembly.pivot,
					)
				}
			}
		}
		part.velocity = box2d.Body_GetLinearVelocity(body.id) * WORLD2D_PIXELS_PER_METER
		part.angular_velocity = box2d.Body_GetAngularVelocity(body.id) * (180 / math.PI)
		body.center, body.angle = center, angle
		ws.body_map[part] = body
	}
}

workspace2d_render_roots :: proc(
	parent, legacy: ^classes.Object,
	ctx: ^classes.Class_Step_Context,
) {
	roots: [dynamic]^classes.Object
	defer delete(roots)
	workspace2d_find_roots(parent, &roots)
	if legacy != nil {workspace2d_find_roots(legacy, &roots)}
	slice.stable_sort_by(roots[:], proc(a, b: ^classes.Object) -> bool {
		return (cast(^classes.GuiObject)a).zindex < (cast(^classes.GuiObject)b).zindex
	})
	ctx.world2d_scene = true
	for child in roots {classes.ScreenGui_RenderChild(child, ctx)}
}
workspace2d_find_camera :: proc(parent: ^classes.Object, camera: ^^classes.Camera2D) {
	for child in parent.children {
		if child == nil || child.destroyed {continue}
		if classes.Is_A_Class(child, &classes.World2D_Class) &&
		   !(cast(^classes.World2D)child).enabled {continue}
		if classes.Is_A_Class(child, &classes.ScreenGui_Class) ||
		   classes.Is_A_Class(child, &classes.SurfaceGui_Class) {continue}
		if classes.Is_A_Class(child, &classes.Camera2D_Class) {
			candidate := cast(^classes.Camera2D)child

			if candidate.enabled &&
			   (camera^ == nil ||
					   (candidate.editor_scene_helper && !camera^.editor_scene_helper)) {
				camera^ = candidate
			}
		}
		workspace2d_find_camera(child, camera)
	}
}
workspace2d_find_roots :: proc(parent: ^classes.Object, roots: ^[dynamic]^classes.Object) {
	for child in parent.children {
		if child == nil || child.destroyed {continue}
		if classes.Is_A_Class(child, &classes.World2D_Class) &&
		   !(cast(^classes.World2D)child).enabled {continue}
		if classes.Is_A_Class(child, &classes.ScreenGui_Class) ||
		   classes.Is_A_Class(child, &classes.SurfaceGui_Class) {continue}
		if classes.Is_A_Class(child, &classes.WorldObject2D_Class) ||
		   classes.Is_A_Class(child, &classes.Sprite2D_Class) {
			append(roots, child)
		} else if !classes.Is_A_Class(child, &classes.GuiObject_Class) {
			workspace2d_find_roots(child, roots)
		}
	}
}

Render_2D :: proc(
	registry: ^Registry,
	L: ^vm.State,
	r: ^classes.Renderer_Object,
	width, height: i32,
	dt: f32,
) {
	if registry == nil || r == nil || r.SkiaSurface == nil {return}
	w := Find_Service(registry, "Workspace")
	d := Find_Service(registry, "Workspace2D")
	if w == nil || w.object == nil {return}
	ws := cast(^Workspace)w.object
	r.RenderFilament = ws.dimension == .D3 && ws.enable_3d
	if ws.dimension != .D2 {return}
	viewport := guilib.Rect {
		width  = f32(width),
		height = f32(height),
	}
	if r.ViewportRect_Host {
		if !r.HasViewportRect {return}
		scale := max(platform.UI_Scale, 0.01)
		rect := r.ViewportRect
		viewport = {
			x      = (f32(rect[0]) - platform.UI_Safe_Left) / scale,
			y      = (f32(rect[1]) - platform.UI_Safe_Top) / scale,
			width  = f32(rect[2]) / scale,
			height = f32(rect[3]) / scale,
		}
	}
	if viewport.width < 1 || viewport.height < 1 {return}
	ctx := classes.Class_Step_Context {
		L               = L,
		renderer        = r,
		data_model      = registry.data_model,
		delta_time      = dt,
		viewport_width  = i32(viewport.width),
		viewport_height = i32(viewport.height),
	}
	world_object := d.object if d != nil else nil
	if world_object != nil {
		world := cast(^Workspace2D)world_object
		world.width, world.height = ctx.viewport_width, ctx.viewport_height
	}
	guilib.save(r.SkiaSurface)
	defer guilib.restore(r.SkiaSurface)
	guilib.clipRect(r.SkiaSurface, viewport)
	guilib.translate(r.SkiaSurface, viewport.x, viewport.y)
	camera: ^classes.Camera2D
	workspace2d_find_camera(&ws.object, &camera)
	if world_object != nil {workspace2d_find_camera(world_object, &camera)}
	if camera != nil {classes.Camera2D_Apply(camera, &ctx)}
	workspace2d_render_roots(&ws.object, world_object, &ctx)
}

Workspace2D_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
) -> bool {
	ws := cast(^Workspace2D)object
	switch key {
	case "Raycast":
		vm.PushUserdataMethod(L, key)
	case "Gravity":
		if dr == nil {return false}
		datatypes.Push_Vector2(L, dr, {ws.gravity[0], ws.gravity[1]})
	case "ViewportSize":
		if dr == nil {return false}
		datatypes.Push_Vector2(L, dr, {f32(ws.width), f32(ws.height)})
	case "BodyCount":
		vm.PushNumber(L, f64(len(ws.body_map)))
	case:
		return false
	}
	return true
}
Workspace2D_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	ws := cast(^Workspace2D)object
	if key != "Gravity" || dr == nil {return false}
	g := datatypes.Arg_Vector2(L, index, dr)
	if !world2d_finite(g.X) ||
	   !world2d_finite(g.Y) {_ = vm.RaiseError(L, "Gravity must be finite"); return true}
	ws.gravity = {g.X, g.Y}
	if box2d.World_IsValid(
		ws.world,
	) {box2d.World_SetGravity(ws.world, ws.gravity / WORLD2D_PIXELS_PER_METER)}
	return true
}

Workspace2D_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "Raycast" || dr == nil {return 0, false}
	ws := cast(^Workspace2D)object
	origin := datatypes.Arg_Vector2(L, 2, dr)
	direction := datatypes.Arg_Vector2(L, 3, dr)
	if !world2d_finite(origin.X) ||
	   !world2d_finite(origin.Y) ||
	   !world2d_finite(direction.X) ||
	   !world2d_finite(direction.Y) {
		return vm.RaiseError(L, "Raycast origin and direction must be finite"), true
	}
	if !box2d.World_IsValid(ws.world) || (direction.X == 0 && direction.Y == 0) {
		vm.PushNil(L)
		return 1, true
	}
	hit := box2d.World_CastRayClosest(
		ws.world,
		[2]f32{origin.X, origin.Y} / WORLD2D_PIXELS_PER_METER,
		[2]f32{direction.X, direction.Y} / WORLD2D_PIXELS_PER_METER,
		box2d.DefaultQueryFilter(),
	)
	if !hit.hit {vm.PushNil(L); return 1, true}
	part := cast(^classes.Part2D)box2d.Shape_GetUserData(hit.shapeId)
	if part == nil || part.destroyed {vm.PushNil(L); return 1, true}
	vm.NewTable(L, 0, 4)
	classes.Push_Object(L, &part.object)
	vm.SetField(L, -2, "Instance")
	datatypes.Push_Vector2(
		L,
		dr,
		{hit.point[0] * WORLD2D_PIXELS_PER_METER, hit.point[1] * WORLD2D_PIXELS_PER_METER},
	)
	vm.SetField(L, -2, "Position")
	datatypes.Push_Vector2(L, dr, {hit.normal[0], hit.normal[1]})
	vm.SetField(L, -2, "Normal")
	vm.PushNumber(L, f64(datatypes.Vec2_Magnitude(direction) * hit.fraction))
	vm.SetField(L, -2, "Distance")
	vm.SetReadOnly(L, -1)
	return 1, true
}

Workspace2D_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	ws := cast(^Workspace2D)object
	Workspace2D_Clear(ws)
	delete(ws.body_map)
	delete(ws.parts)
	delete(ws.part_groups)
	delete(ws.group_roots)
	delete(ws.groups)
	delete(ws.stale)
	classes.Object_Destroy(object)
	free(ws)
}

Register_Workspace2D_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Workspace2D_Class,
		Workspace2D_construct,
		Workspace2D_destroy,
		creatable = false,
		get = Workspace2D_get,
		set = Workspace2D_set,
		namecall = Workspace2D_namecall,
		methods = []string{"Raycast"},
		properties = []string{"Gravity", "BodyCount", "ViewportSize"},
	)
}
