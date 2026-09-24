#+build !js
package services

import classes "../classes"
import datatypes "../datatypes"
import sdl3 "../platform"
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
