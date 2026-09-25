#+build !js
package services

import classes "../classes"
import datatypes "../datatypes"
import sdl3 "../platform"
import vm "../vm"
import kineffi "../bindings"
import "core:math"
import enet "vendor:ENet"

character_translate :: proc(model: ^classes.CharacterModel, dx, dy, dz: f32) {
	if model == nil || model.destroyed {return}
	for part_object in model.children {
		if part_object == nil ||
		   part_object.destroyed ||
		   !classes.Is_A(part_object, "Part") {continue}
		part := cast(^classes.Part)part_object
		part.cframe.x += dx
		part.cframe.y += dy
		part.cframe.z += dz
		part.position = datatypes.Vector3{part.cframe.x, part.cframe.y, part.cframe.z}
	}
}

// character_translate_followers moves every Part of a character model except
// `root` by the given delta. The controller and replication correction paths
// move the root part authoritatively; the remaining parts (such as the visible
// CharacterCollider capsule) must follow the root instead of being translated
// twice.
character_translate_followers :: proc(
	model: ^classes.CharacterModel,
	root: ^classes.Part,
	dx, dy, dz: f32,
) {
	if model == nil || model.destroyed || root == nil {return}
	for part_object in model.children {
		if part_object == nil ||
		   part_object.destroyed ||
		   part_object == &root.object ||
		   !classes.Is_A(part_object, "Part") {continue}
		part := cast(^classes.Part)part_object
		part.cframe.x += dx
		part.cframe.y += dy
		part.cframe.z += dz
		part.position = datatypes.Vector3{part.cframe.x, part.cframe.y, part.cframe.z}
	}
}

character_send_input :: proc(service: ^ReplicatorService) -> bool {
	if service == nil ||
	   service.mode != .Client ||
	   !service.connected ||
	   service.remote == nil {return false}
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
	if players == nil ||
	   players.local_player == nil ||
	   players.local_player.character == nil {return false}
	characters := cast(^CharacterService)Ensure_Service(
		service.data_model.registry,
		"CharacterService",
	)
	if characters == nil {return false}
	characters.input_sequence += 1
	direction := characters.move_direction
	length_squared := direction.x * direction.x + direction.z * direction.z
	if length_squared > 1 {
		scale := 1 / f32(math.sqrt(length_squared))
		direction.x *= scale
		direction.z *= scale
	}
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, characters.input_sequence)
	replication_put_f32(&bytes, direction.x)
	replication_put_f32(&bytes, direction.z)
	append(&bytes, characters.jump_queued ? u8(1) : u8(0))
	if replication_send(service, service.remote, 9, bytes[:], false) {
		root := classes.CharacterModel_Root(players.local_player.character)
		if root != nil {
			append(
				&characters.predictions,
				Character_Prediction {
					sequence = characters.input_sequence,
					position = datatypes.Vector3{root.cframe.x, root.cframe.y, root.cframe.z},
				},
			)
			if len(characters.predictions) > 128 {ordered_remove(&characters.predictions, 0)}
		}
		characters.jump_queued = false
		return true
	}
	return false
}

character_reconcile :: proc(
	service: ^ReplicatorService,
	entity: ^Replication_Entity,
	frame: datatypes.CFrame,
	ack: u32,
) {
	if service == nil ||
	   entity == nil ||
	   entity.object == nil ||
	   entity.object.parent == nil ||
	   !classes.Is_A(entity.object.parent, "CharacterModel") {return}
	model := cast(^classes.CharacterModel)entity.object.parent
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
	if players == nil ||
	   players.local_player == nil ||
	   model != players.local_player.character {return}
	characters := cast(^CharacterService)Ensure_Service(
		service.data_model.registry,
		"CharacterService",
	)
	if characters == nil {return}
	root := cast(^classes.Part)entity.object
	if !characters.authoritative_received {
		character_translate(
			model,
			frame.x - root.cframe.x,
			frame.y - root.cframe.y,
			frame.z - root.cframe.z,
		)
		players.local_player.ground_y = frame.y
		characters.authoritative_received = true
		return
	}
	if ack == 0 || transmute(i32)(ack - characters.last_ack) <= 0 {return}
	characters.last_ack = ack
	predicted: ^Character_Prediction
	for &item in characters.predictions {
		if item.sequence == ack {predicted = &item; break}
	}
	dx, dy, dz: f32
	if predicted != nil {
		dx = frame.x - predicted.position.x
		dy = frame.y - predicted.position.y
		dz = frame.z - predicted.position.z
	} else {
		dx = frame.x - root.cframe.x
		dy = frame.y - root.cframe.y
		dz = frame.z - root.cframe.z
	}
	for len(characters.predictions) > 0 &&
	    transmute(i32)(ack - characters.predictions[0].sequence) >= 0 {
		ordered_remove(&characters.predictions, 0)
	}
	distance_squared := dx * dx + dy * dy + dz * dz
	if distance_squared <= 0.75 * 0.75 {return}
	scale: f32 = 0.15
	if distance_squared >= 8 * 8 {scale = 1}
	dx *= scale
	dy *= scale
	dz *= scale
	character_translate(model, dx, dy, dz)
	for &item in characters.predictions {
		item.position.x += dx
		item.position.y += dy
		item.position.z += dz
	}
}

character_receive_input :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	reader: ^Replication_Reader,
) {
	if service == nil || service.mode != .Server {reader.valid = false; return}
	sequence := replication_read_u32(reader)
	move_x := replication_read_f32(reader)
	move_z := replication_read_f32(reader)
	if reader.offset >= len(reader.data) {reader.valid = false; return}
	jump := reader.data[reader.offset] != 0
	reader.offset += 1
	connection: ^Replication_Peer
	for &candidate in service.peers {
		if candidate.peer == peer {connection = &candidate; break}
	}
	if !reader.valid ||
	   connection == nil ||
	   connection.player == nil ||
	   connection.player.character == nil ||
	   move_x != move_x ||
	   move_z != move_z ||
	   move_x < -1.05 ||
	   move_x > 1.05 ||
	   move_z < -1.05 ||
	   move_z > 1.05 {
		reader.valid = false
		return
	}
	player := connection.player
	if player.input_sequence != 0 && transmute(i32)(sequence - player.input_sequence) <= 0 {return}
	player.input_sequence = sequence
	length_squared := move_x * move_x + move_z * move_z
	if length_squared > 1 {
		scale := 1 / f32(math.sqrt(length_squared))
		move_x *= scale
		move_z *= scale
	}
	player.move_direction = datatypes.Vector3{move_x, 0, move_z}
	if jump {player.jump_queued = true}
}

character_ground_rest_y :: proc(
	service: ^CharacterService,
	root: ^classes.Part,
) -> (rest_y: f32, found: bool) {
	if service == nil ||
	   service.data_model == nil ||
	   root == nil ||
	   root.destroyed {return 0, false}
	workspace := DataModel_Get_Service(service.data_model, "Workspace")
	if workspace == nil {return 0, false}
	physics := cast(^Physics)DataModel_Get_Service(service.data_model, "Physics")
	if physics == nil || !physics.initialized {return 0, false}
	params := datatypes.RaycastParams{}
	params.RespectCanCollide = true
	params.ExcludeFilterSet = true
	append(&params.ExcludeInstances, datatypes.Raycast_Instance_Reference{object = root.object.parent})
	defer delete(params.ExcludeInstances)
	origin := datatypes.Vector3{root.cframe.x, root.cframe.y + 0.1, root.cframe.z}
	direction := datatypes.Vector3{0, -2048, 0}
	result, hit := Physics_Raycast(physics, workspace, origin, direction, &params)
	if !hit {return 0, false}
	return result.Position.y + root.size.y * 0.5, true
}

character_client_authoritative :: proc(
	service: ^ReplicatorService,
	model: ^classes.CharacterModel,
) -> bool {
	if service == nil || service.mode != .Server || model == nil {return false}
	if model.owner_user_id == 0 {return false}
	root := classes.CharacterModel_Root(model)
	entity := root != nil ? replication_entity(service, root) : nil
	if entity == nil || entity.owner_id == 0 || entity.owner_id != model.owner_user_id {return false}
	for connection in service.peers {
		if connection.player != nil &&
		   connection.player.user_id == model.owner_user_id &&
		   connection.player.character == model {
			return true
		}
	}
	return false
}

// The character capsule is resolved with Jolt shape casts instead of sampled
// rays, so the swept volume decides where the character can stand and move.
CHARACTER_SWEEP_ITERATIONS :: 4

// A surface is walkable when its outward normal is within `max_slope_angle` of up.
CharacterController_Walkable_Cos :: proc(max_slope_angle: f32) -> f32 {
	return math.cos(math.to_radians(clamp(max_slope_angle, 0, 89.9)))
}

// Sweeps the capsule straight down from `position` and reports where its centre
// would settle on the surface below, plus that surface's outward normal.
CharacterController_Ground_Cast :: proc(
	physics: ^Physics,
	coll: ^classes.CollisionController,
	snap_distance: f32,
	position: datatypes.Vector3,
) -> (rest_y: f32, normal: datatypes.Vector3, hit: bool) {
	rest_y = position.y
	normal = datatypes.Vector3{0, 1, 0}
	if physics == nil || coll == nil || !coll.body_created || coll.shape == nil {return}
	distance := max(snap_distance, 0) + classes.COLLISION_SKIN
	origin := datatypes.Vector3{position.x, position.y + classes.COLLISION_SKIN, position.z}
	contact, contact_normal, _, _, did_hit := physics_character_sweep(
		physics,
		coll,
		origin,
		datatypes.Vector3{0, -distance, 0},
	)
	if !did_hit {return}
	length := datatypes.Vec3_Magnitude(contact_normal)
	if length <= 0.0001 {return}
	normal = datatypes.Vec3_Divide(contact_normal, length)
	rest_y = contact.y
	hit = true
	return
}

// Advances the capsule from `origin` by `displacement`, sliding along surfaces it
// can walk on. Surfaces steeper than `max_slope_angle` only allow movement along
// their level contour, which stops the character from climbing them.
CharacterController_Sweep :: proc(
	physics: ^Physics,
	coll: ^classes.CollisionController,
	origin: datatypes.Vector3,
	displacement: datatypes.Vector3,
	max_slope_angle: f32,
	blocked_body: ^kineffi.JPH_BodyID,
) -> datatypes.Vector3 {
	position := origin
	remaining := displacement
	walkable_cos := CharacterController_Walkable_Cos(max_slope_angle)
	for _ in 0..<CHARACTER_SWEEP_ITERATIONS {
		length := datatypes.Vec3_Magnitude(remaining)
		if length <= 0.0001 {break}
		direction := datatypes.Vec3_Divide(remaining, length)
		_, contact_normal, body_id, fraction, hit := physics_character_sweep(physics, coll, position, remaining)
		if !hit {
			position = datatypes.Vec3_Add(position, remaining)
			break
		}
		normal_length := datatypes.Vec3_Magnitude(contact_normal)
		if normal_length <= 0.0001 {break}
		normal := datatypes.Vec3_Divide(contact_normal, normal_length)
		advance := max(fraction*length - classes.COLLISION_SKIN, 0)
		position = datatypes.Vec3_Add(position, datatypes.Vec3_Multiply(direction, advance))
		remaining = datatypes.Vec3_Multiply(direction, length - advance)
		if normal.y >= walkable_cos {
			// Walkable ground: follow the surface, which carries the character up
			// ramps instead of stopping it.
			into := datatypes.Vec3_Dot(remaining, normal)
			if into < 0 {
				remaining = datatypes.Vec3_Subtract(remaining, datatypes.Vec3_Multiply(normal, into))
			}
		} else if normal.y <= -walkable_cos {
			// Ceiling: keep only the horizontal part of the remaining motion.
			remaining.y = 0
		} else {
			// Too steep to walk: slide only along the level contour of the surface.
			if blocked_body != nil {blocked_body^ = body_id}
			tangent := datatypes.Vec3_Cross(datatypes.Vector3{0, 1, 0}, normal)
			tangent_length := datatypes.Vec3_Magnitude(tangent)
			if tangent_length <= 0.0001 {
				remaining = datatypes.Vector3{}
			} else {
				tangent = datatypes.Vec3_Divide(tangent, tangent_length)
				remaining = datatypes.Vec3_Multiply(tangent, datatypes.Vec3_Dot(remaining, tangent))
			}
		}
	}
	return datatypes.Vec3_Subtract(position, origin)
}

CharacterController_Ground_Probe :: proc(
	physics: ^Physics,
	gd: ^classes.GroundDetector,
	coll: ^classes.CollisionController,
	position: datatypes.Vector3,
	max_slope_angle: f32,
) -> (grounded: bool, rest_y: f32, normal: datatypes.Vector3) {
	rest_y = position.y
	normal = datatypes.Vector3{0, 1, 0}
	if gd == nil {return}
	hit_rest, hit_normal, hit := CharacterController_Ground_Cast(physics, coll, gd.snap_distance, position)
	if hit {
		gd.slope_angle = math.to_degrees(math.acos(clamp(hit_normal.y, -1, 1)))
	}
	grounded = hit && hit_normal.y >= CharacterController_Walkable_Cos(max_slope_angle)
	if grounded {
		rest_y = hit_rest
		normal = hit_normal
		gd.rest_y = rest_y
	}
	gd.grounded = grounded
	return
}

CharacterController_Tick :: proc(
	cc: ^classes.CharacterController,
	physics: ^Physics,
	L: ^vm.State,
	dt: f32,
) {
	if cc == nil || cc.destroyed || physics == nil || L == nil || dt <= 0 {return}
	root := classes.CharacterController_Root(cc)
	if root == nil {return}
	cc.step_count += 1
	movement := cast(^classes.MovementController)classes.CharacterController_Find(cc, "MovementController")
	ground := cast(^classes.GroundDetector)classes.CharacterController_Find(cc, "GroundDetector")
	rotation := cast(^classes.RotationController)classes.CharacterController_Find(cc, "RotationController")
	sm := cast(^classes.StateMachine)classes.CharacterController_Find(cc, "StateMachine")
	collision := cast(^classes.CollisionController)classes.CharacterController_Find(cc, "CollisionController")
	if movement != nil {
		movement.walk_speed = cc.walk_speed
		movement.acceleration = 10 * cc.walk_speed
	}
	if sm != nil && sm.state == "Dead" {
		cc.vertical_speed = 0
		return
	}
	humanoid := cast(^classes.Humanoid)classes.Find_Child(cc.object.parent, "Humanoid")
	if humanoid != nil {
		classes.Humanoid_Sync(humanoid, cc, L, dt)
	}
	move_dir, jump := classes.MovementController_Step(movement, dt)
	position := datatypes.Vector3{root.cframe.x, root.cframe.y, root.cframe.z}
	previous_position := position
	if collision != nil {
		Physics_Ensure_Character_Capsule(physics, collision, root, position)
	}
	grounded := false
	ground_normal := datatypes.Vector3{0, 1, 0}
	if ground != nil {
		grounded, _, ground_normal = CharacterController_Ground_Probe(physics, ground, collision, position, cc.max_slope_angle)
	}
	was_grounded := grounded || cc.coyote_time > 0
	if grounded {
		cc.coyote_time = classes.CHARACTER_COYOTE_TIME
	} else if cc.coyote_time > 0 {
		cc.coyote_time -= dt
	}
	jumped := jump && was_grounded
	if jumped {
		cc.vertical_speed = math.sqrt(2 * cc.jump_height * classes.CHARACTER_GRAVITY)
		cc.coyote_time = 0
	}
	cc.vertical_speed -= classes.CHARACTER_GRAVITY * dt
	if collision != nil && collision.body_created && collision.shape != nil {
		// Horizontal motion. On walkable ground the move follows the ground plane,
		// so walking into a ramp climbs it at a constant horizontal speed rather
		// than being stopped at its base.
		move := datatypes.Vector3{move_dir.x * dt, 0, move_dir.z * dt}
		if grounded && ground_normal.y > 0.0001 {
			move.y = -(move.x*ground_normal.x + move.z*ground_normal.z) / ground_normal.y
		}
		// Horizontal sweeps start a skin above the capsule so the surface the
		// character is standing on does not mask obstacles in front of it.
		cast_origin := datatypes.Vector3{position.x, position.y + classes.COLLISION_SKIN, position.z}
		blocked := kineffi.JPH_BODY_ID_INVALID
		applied := CharacterController_Sweep(physics, collision, cast_origin, move, cc.max_slope_angle, &blocked)
		if grounded {
			wanted := math.abs(move.x) + math.abs(move.z)
			gained := math.abs(applied.x) + math.abs(applied.z)
			if gained < wanted - 0.001 {
				elevated := datatypes.Vector3{
					position.x,
					position.y + classes.COLLISION_STEP_HEIGHT + classes.COLLISION_SKIN,
					position.z,
				}
				step_blocked := kineffi.JPH_BODY_ID_INVALID
				step := CharacterController_Sweep(physics, collision, elevated, move, cc.max_slope_angle, &step_blocked)
				if math.abs(step.x) + math.abs(step.z) > gained + 0.001 {
					applied = step
					blocked = step_blocked
					position.y += classes.COLLISION_STEP_HEIGHT
				}
			}
		}
		position = datatypes.Vec3_Add(position, applied)
		if blocked != kineffi.JPH_BODY_ID_INVALID {
			physics_fire_touched(physics, blocked, root)
		}
		// Vertical motion is resolved through the same capsule sweep so the
		// character cannot sink into steep surfaces or tunnel through floors.
		if cc.vertical_speed != 0 {
			vertical := datatypes.Vector3{0, cc.vertical_speed * dt, 0}
			applied_vertical := CharacterController_Sweep(physics, collision, position, vertical, cc.max_slope_angle, nil)
			position = datatypes.Vec3_Add(position, applied_vertical)
			if cc.vertical_speed < 0 && applied_vertical.y > vertical.y + 0.0001 {
				cc.vertical_speed = 0
			}
		}
		// Settle onto the surface below so ramps, steps and early ground contact
		// keep the character grounded instead of leaving it hovering.
		settle_y, settle_normal, settle_hit := CharacterController_Ground_Cast(
			physics,
			collision,
			ground != nil ? ground.snap_distance : 0.6,
			position,
		)
		if settle_hit &&
		   settle_normal.y >= CharacterController_Walkable_Cos(cc.max_slope_angle) &&
		   cc.vertical_speed <= 0 {
			position.y = settle_y
			cc.vertical_speed = 0
			if ground != nil {
				ground.grounded = true
				ground.rest_y = settle_y
				ground.slope_angle = math.to_degrees(math.acos(clamp(settle_normal.y, -1, 1)))
			}
		}
	} else {
		position.x += move_dir.x * dt
		position.z += move_dir.z * dt
		position.y += cc.vertical_speed * dt
	}
	yaw: f32
	_, current_yaw, _ := datatypes.CFrame_ToEulerAnglesYXZ(root.cframe)
	yaw = math.to_degrees(current_yaw)
	if rotation != nil && cc.auto_rotate {
		if move_dir.x != 0 || move_dir.z != 0 {
			classes.RotationController_Set_Target(rotation, move_dir)
		}
		yaw = classes.RotationController_Step(rotation, dt)
	}
	cf := datatypes.CFrame_FromEulerAnglesYXZ(0, math.to_radians(yaw), 0)
	cf.x = position.x
	cf.y = position.y
	cf.z = position.z
	root.cframe = cf
	root.position = datatypes.Vector3{position.x, position.y, position.z}
	if collision != nil {
		Physics_Set_Character_Capsule(physics, collision, datatypes.Vector3{position.x, position.y, position.z}, yaw)
	}
	// Carry the rest of the character (the visible CharacterCollider capsule,
	// accessories, ...) along with the root so it does not stay at the spawn
	// point while the root moves.
	delta := datatypes.Vector3{
		position.x - previous_position.x,
		position.y - previous_position.y,
		position.z - previous_position.z,
	}
	if delta.x != 0 || delta.y != 0 || delta.z != 0 {
		if cc.object.parent != nil && classes.Is_A(cc.object.parent, "CharacterModel") {
			character_translate_followers(
				cast(^classes.CharacterModel)cc.object.parent,
				root,
				delta.x,
				delta.y,
				delta.z,
			)
		}
	}
	if sm != nil {
		next := sm.state
		moving := move_dir.x != 0 || move_dir.z != 0
		switch sm.state {
		case "Idle":
			switch {
			case jumped: next = "Jumping"
			case !was_grounded: next = "Falling"
			case moving: next = "Running"
			}
		case "Running":
			switch {
			case jumped: next = "Jumping"
			case !was_grounded: next = "Falling"
			case !moving: next = "Idle"
			}
		case "Jumping":
			if cc.vertical_speed < 0 && !was_grounded {next = "Falling"}
		case "Falling":
			if was_grounded {next = moving ? "Running" : "Idle"}
		}
		classes.StateMachine_Set_State(sm, L, next)
	}
}

CharacterMotor_Advance :: proc(
	motor: ^classes.CharacterMotor,
	cc: ^classes.CharacterController,
	physics: ^Physics,
	L: ^vm.State,
	dt: f32,
) {
	if motor == nil || cc == nil {return}
	frame_dt := min(dt, motor.max_step)
	motor.accumulator += frame_dt
	step := 1 / motor.steps_per_second
	for motor.accumulator >= step {
		CharacterController_Tick(cc, physics, L, step)
		motor.accumulator -= step
	}
}

CharacterService_Step :: proc(service: ^CharacterService, delta_time: f32) {
	if service == nil || service.data_model == nil || delta_time <= 0 {return}
	replicator := cast(^ReplicatorService)DataModel_Get_Service(
		service.data_model,
		"ReplicatorService",
	)
	if replicator == nil || (replicator.mode != .Server && replicator.mode != .Client) {return}
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
	if players == nil {return}

	if replicator.mode == .Client && !service.scripted_move {
		focused := sdl3.GetKeyboardFocus() != nil
		keys := sdl3.GetKeyboardState(nil)
		workspace := cast(^Workspace)DataModel_Get_Service(service.data_model, "Workspace")
		direction := datatypes.Vector3{}
		if focused && workspace != nil && workspace.current_camera != nil {
			orientation := workspace.current_camera.CFrame
			look := datatypes.CFrame_LookVector(orientation)
			right := datatypes.CFrame_RightVector(orientation)
			if keys[int(sdl3.Scancode.W)] {
				direction.x += look.x
				direction.z += look.z
			}
			if keys[int(sdl3.Scancode.S)] {
				direction.x -= look.x
				direction.z -= look.z
			}
			if keys[int(sdl3.Scancode.D)] {
				direction.x += right.x
				direction.z += right.z
			}
			if keys[int(sdl3.Scancode.A)] {
				direction.x -= right.x
				direction.z -= right.z
			}
			if keys[int(sdl3.Scancode.SPACE)] {
				service.jump_queued = true
				service.local_jump_pending = true
			}
		}
		service.move_direction = direction
	}
	dt := min(delta_time, 0.1)
	for child in players.children {
		if child == nil || child.destroyed || !classes.Is_A(child, "Player") {continue}
		player := cast(^Player)child
		if replicator.mode == .Client {
			if player != players.local_player {continue}
			player.move_direction = service.move_direction
			if service.local_jump_pending {player.jump_queued = true; service.local_jump_pending = false}
		}
		root := classes.CharacterModel_Root(player.character)
		if root == nil {continue}
		if replicator.mode == .Server && character_client_authoritative(replicator, player.character) {
			continue
		}
		when !#config(FORCE_LEGACY_CHARACTERS, false) {
			controller := classes.CharacterController_From_Model(player.character)
			motor := cast(^classes.CharacterMotor)classes.Find_Child(&player.character.object, "CharacterMotor")
			if controller != nil && motor != nil {
				movement := cast(^classes.MovementController)classes.CharacterController_Find(controller, "MovementController")
				if movement != nil {movement.input_direction = player.move_direction}
				if player.jump_queued {
					classes.MovementController_Queue_Jump(movement)
					player.jump_queued = false
				}
				physics := cast(^Physics)DataModel_Get_Service(service.data_model, "Physics")
				L := service.data_model.registry.vm_state.L
				if physics != nil {
					CharacterMotor_Advance(motor, controller, physics, L, dt)
				}
				continue
			}
		}
		ground_y, found := character_ground_rest_y(service, root)
		if found {
			player.ground_y = ground_y
		} else {
			player.ground_y = -1.0e20
		}
		rest_y := player.ground_y
		if player.jump_queued && root.cframe.y <= rest_y + 0.05 {
			player.vertical_speed = player.jump_power
		}
		player.jump_queued = false
		old_y := root.cframe.y
		new_y := old_y + player.vertical_speed * dt
		player.vertical_speed -= 50 * dt
		if found && new_y <= rest_y {new_y = rest_y; player.vertical_speed = 0}
		dx := player.move_direction.x * player.walk_speed * dt
		dy := new_y - old_y
		dz := player.move_direction.z * player.walk_speed * dt
		if dx == 0 && dy == 0 && dz == 0 {continue}
		character_translate(player.character, dx, dy, dz)
	}
}
