package main
import classes "../src/engine/classes"
import datatypes "../src/engine/datatypes"
import rt "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(v: ^vm.VM, script: string) {
	ok, err := vm.Run(v, script, "vehicle_ownership")
	assert(ok, err)
}

main :: proc() {
	v := vm.New()
	env: rt.Environment
	rt.Environment_Init(&env, &v)
	defer {vm.Close(&v); rt.Environment_Destroy(&env)}
	run(&v, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39321))
workspace.Gravity = 0
car = Instance.new("Model", workspace)
car.Name = "Car"
for i, name in ipairs({"Chassis", "Wheel", "Cabin"}) do
	local p = Instance.new("Part", car)
	p.Name = name
	p.Anchored = false
	p.CanCollide = false
	p.CFrame = CFrame.new(i * 4, 8, 0)
end
local axle = Instance.new("HingeConstraint", car.Chassis)
axle.Attachment0 = Instance.new("Attachment", car.Chassis)
axle.Attachment0.Position = Vector3.new(4, 0, 0)
axle.Attachment1 = Instance.new("Attachment", car.Wheel)
local weld = Instance.new("WeldConstraint", car.Chassis)
weld.Part0 = car.Chassis
weld.Part1 = car.Cabin
`)
	rep := cast(^services.ReplicatorService)services.Ensure_Service(&env.services, "ReplicatorService")
	services.replication_sync(rep)
	player_service := cast(^services.Players)services.Ensure_Service(&env.services, "Players")
	character_service := cast(^services.CharacterService)services.Ensure_Service(&env.services, "CharacterService")
	p1 := services.Players_Add(player_service, v.L, 40, "Driver1")
	p2 := services.Players_Add(player_service, v.L, 41, "Driver2")
	assert(services.CharacterService_Load(character_service, p1) != nil)
	assert(services.CharacterService_Load(character_service, p2) != nil)
	root1 := classes.CharacterModel_Root(p1.character)
	root2 := classes.CharacterModel_Root(p2.character)
	root1.cframe.x = 8
	root2.cframe.x = 500
	parts: [dynamic]^services.Replication_Entity
	defer delete(parts)
	peer1 := services.Replication_Peer{player=p1, handshake_complete=true}
	peer2 := services.Replication_Peer{player=p2, handshake_complete=true}
	for entity in rep.entity_list {
		if entity.object == nil {continue}
		peer1.initialized[entity.id] = true
		peer2.initialized[entity.id] = true
		peer2.acked_extra[entity.id] = 1
		if entity.object.parent != nil && entity.object.parent.name == "Car" &&
			classes.Is_A(entity.object, "Part") {
			append(&parts, entity)
		}
	}
	assert(len(parts) == 3)
	append(&rep.peers, peer1, peer2)
	services.replication_auto_ownership_step(rep)
	for entity in parts {assert(entity.owner_id == 0, "wait for all constraints")}
	for entity in rep.entity_list {rep.peers[0].acked_extra[entity.id] = 1}
	rt.Environment_Update_Step(&env, &v, 1.0/60)
	run(&v, `for _, p in car:GetChildren() do p.AssemblyLinearVelocity = Vector3.new(12, 0, 0) end`)
	services.replication_auto_ownership_step(rep)
	for entity in parts {
		assert(entity.owner_id == p1.user_id && entity.pending_linear_velocity.x > 11)
		entity.owned_linear_velocity.x = 23
		entity.owned_angular_velocity.y = 4
	}
	root1.cframe.x = 500
	root2.cframe.x = 8
	services.replication_auto_ownership_step(rep)
	for entity in parts {
		assert(entity.owner_id == p2.user_id && entity.pending_linear_velocity.x == 23)
	}
	// Restore to the server after both drivers leave range.
	root2.cframe.x = 500
	services.replication_auto_ownership_step(rep)
	for entity in parts {
		assert(entity.owner_id == 0 && entity.pending_linear_velocity.x == 23)
	}
	// The receiving simulation starts from the authoritative pose and velocities.
	player_service.local_player = p2
	bytes: [dynamic]u8
	defer delete(bytes)
	services.replication_put_u32(&bytes, p2.user_id)
	for entity, index in parts {
		services.replication_put_u32(&bytes, entity.id)
		append(&bytes, u8(0))
		values := [18]f32{100 + f32(index), 8, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 23, 0, 0, 0, 4, 0}
		for value in values {services.replication_put_f32(&bytes, value)}
	}
	reader := services.Replication_Reader{data=bytes[:], valid=true}
	services.replication_receive_group_ownership(rep, &reader)
	for entity, index in parts {
		assert(entity.owner_id == p2.user_id)
		part := cast(^classes.Part)entity.object
		assert(part.cframe.x == 100 + f32(index))
		assert(entity.pending_angular_velocity == (datatypes.Vector3{0, 4, 0}))
		entity.owned_linear_velocity.x = 23
		entity.owned_angular_velocity.y = 4
		entity.owner_locked = true
	}
	services.replication_reclaim_disconnected_owner(rep, p2.user_id)
	for entity in parts {
		assert(entity.owner_id == 0 && !entity.owner_locked && entity.pending_linear_velocity.x == 23)
	}
	for &peer in rep.peers {services.Replication_Peer_Dispose(&peer)}
	clear(&rep.peers)
	run(&v, `game:GetService("ReplicatorService"):Stop()`)
	fmt.println("VEHICLE_OWNERSHIP_HANDOFF_PASSED")
}
