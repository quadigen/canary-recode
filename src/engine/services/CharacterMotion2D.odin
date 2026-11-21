package services

import classes "../classes"
import datatypes "../datatypes"
import tracy "../util/odin-tracy"
import "core:math"
import box2d "vendor:box2d"

Character2D_Cast :: struct {
	self:     ^classes.Part2D,
	motion:   [2]f32,
	fraction: f32,
	normal:   [2]f32,
	hit:      bool,
}
character2d_cast_callback :: proc "c" (
	id: box2d.ShapeId,
	point: box2d.Pos,
	normal: box2d.Vec2,
	fraction: f32,
	data: rawptr,
) -> f32 {
	context = tracy.DefaultContext()
	q := cast(^Character2D_Cast)data
	part := cast(^classes.Part2D)box2d.Shape_GetUserData(id)
	if part == nil || part == q.self || part.destroyed || !part.can_collide {return -1}


	if normal[0] * normal[0] + normal[1] * normal[1] < 0.5 ||
	   normal[0] * q.motion[0] + normal[1] * q.motion[1] >= -0.000001 {return -1}
	if !q.hit || fraction < q.fraction {q.hit = true; q.fraction = fraction; q.normal = normal}
	return q.fraction
}
character2d_proxy :: proc(part: ^classes.Part2D, size: [2]f32, angle: f32) -> box2d.ShapeProxy {
	points: [4]box2d.Vec2
	if part.is_ball {
		return box2d.MakeProxy(points[:1], min(size[0], size[1]) * 0.5 / WORLD2D_PIXELS_PER_METER)
	}
	hw, hh := size[0] * 0.5, size[1] * 0.5
	points = {{-hw, -hh}, {hw, -hh}, {hw, hh}, {-hw, hh}}
	rad := angle * (math.PI / 180)
	c, s := math.cos(rad), math.sin(rad)
	for &p in points {p = [2]f32{p[0] * c - p[1] * s, p[0] * s + p[1] * c} / WORLD2D_PIXELS_PER_METER}
	return box2d.MakeProxy(points[:], 0)
}
character2d_classify :: proc(p: ^classes.CharacterController2D, normal: [2]f32) {
	dot := normal[0] * p.up_direction.X + normal[1] * p.up_direction.Y
	limit := math.cos(p.floor_max_angle * (math.PI / 180))
	if dot >=
	   limit {p.on_floor = true} else if dot <= -limit {p.on_ceiling = true} else {p.on_wall = true}
}
character2d_length :: proc(a: [2]f32) -> f32 {return math.sqrt(a[0] * a[0] + a[1] * a[1])}
workspace2d_character_move :: proc(
	owner: rawptr,
	p: ^classes.CharacterController2D,
	dt: f32,
) -> bool {
	ws := cast(^Workspace2D)owner
	if ws == nil ||
	   p == nil ||
	   p.destroyed ||
	   p.anchored ||
	   !box2d.World_IsValid(ws.world) ||
	   dt <= 0 {return false}
	part := &p.part
	body, found := ws.body_map[part]
	if !found || !box2d.Body_IsValid(body.id) {return false}

	active := false
	for parent := part.parent; parent != nil; parent = parent.parent {
		if parent.destroyed {return false}
		if classes.Is_A_Class(parent, &classes.World2D_Class) &&
		   !(cast(^classes.World2D)parent).enabled {return false}
		if classes.Is_A_Class(
			parent,
			&Workspace_Class,
		) {if (cast(^Workspace)parent).dimension != .D2 {return false}; active = true; break}
		if classes.Is_A_Class(parent, &Workspace2D_Class) {active = true; break}
	}
	if !active {return false}
	ctx := classes.Class_Step_Context {
		viewport_width  = ws.width,
		viewport_height = ws.height,
	}
	workspace2d_sync(ws, part, &ctx, 0)
	body, found = ws.body_map[part]
	if !found {return false}
	start := body.center
	center := start
	remaining := part.velocity * dt
	if !world2d_finite(remaining[0]) || !world2d_finite(remaining[1]) {return false}
	collided := false
	proxy := character2d_proxy(part, body.size, body.angle)
	if !part.can_collide {center += remaining} else {
		for _ in 0 ..< p.max_slides {
			len := character2d_length(remaining)
			if len < 0.0001 {break}
			q := Character2D_Cast {
				self     = part,
				motion   = remaining,
				fraction = 1,
			}
			_ = box2d.World_CastShape(
				ws.world,
				center / WORLD2D_PIXELS_PER_METER,
				proxy,
				remaining / WORLD2D_PIXELS_PER_METER,
				box2d.DefaultQueryFilter(),
				character2d_cast_callback,
				&q,
			)
			if !q.hit {center += remaining; break}
			collided = true
			character2d_classify(p, q.normal)

			fraction := max(q.fraction - 0.08 / len, 0)
			center += remaining * fraction
			remaining *= max(1 - q.fraction, 0)
			approach := remaining[0] * q.normal[0] + remaining[1] * q.normal[1]
			if approach < 0 {remaining -= q.normal * approach}
			velocity_into_surface :=
				part.velocity[0] * q.normal[0] + part.velocity[1] * q.normal[1]
			if velocity_into_surface < 0 {part.velocity -= q.normal * velocity_into_surface}
		}

		if !p.on_floor &&
		   part.velocity[0] * p.up_direction.X + part.velocity[1] * p.up_direction.Y <= 0.01 {
			down := [2]f32{-p.up_direction.X, -p.up_direction.Y} * 0.8
			q := Character2D_Cast {
				self     = part,
				motion   = down,
				fraction = 1,
			}
			_ = box2d.World_CastShape(
				ws.world,
				center / WORLD2D_PIXELS_PER_METER,
				proxy,
				down / WORLD2D_PIXELS_PER_METER,
				box2d.DefaultQueryFilter(),
				character2d_cast_callback,
				&q,
			)
			if q.hit {character2d_classify(p, q.normal)}
		}
	}
	classes.Part2D_Move(part, center - start, body.angle)
	p.last_motion = datatypes.Vector2{center[0] - start[0], center[1] - start[1]}
	body.center = center
	ws.body_map[part] = body
	box2d.Body_SetTransform(
		body.id,
		center / WORLD2D_PIXELS_PER_METER,
		box2d.MakeRot(body.angle * (math.PI / 180)),
	)
	part.velocity_dirty = false
	return collided
}
