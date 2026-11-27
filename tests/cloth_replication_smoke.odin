package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"

run :: proc(script_vm: ^vm.VM, source: string) {
	ok, message := vm.Run(script_vm, source, "cloth_replication_smoke")
	assert(ok, message)
}

cloth_for :: proc(environment: ^engine_runtime.Environment) -> ^classes.Cloth {
	workspace := services.Ensure_Service(&environment.services, "Workspace")
	return cast(^classes.Cloth)classes.Find_First_Child(workspace, "NetCloth")
}

step_until :: proc(
	server, client: ^engine_runtime.Environment,
	server_vm, client_vm: ^vm.VM,
	description: string,
	check: proc(^classes.Cloth) -> bool,
) {
	start := time.tick_now()
	for time.tick_since(start) < 8 * time.Second {
		engine_runtime.Environment_Update_Step(server, server_vm, 1.0 / 60)
		engine_runtime.Environment_Update_Step(client, client_vm, 1.0 / 60)
		engine_runtime.Environment_Render_Step(server, server_vm, 1.0 / 60)
		engine_runtime.Environment_Render_Step(client, client_vm, 1.0 / 60)
		if cloth := cloth_for(client); cloth != nil && check(cloth) {return}
		time.sleep(2 * time.Millisecond)
	}
	environments := [2]^engine_runtime.Environment{server, client}
	for env in environments {
		if cloth := cloth_for(env); cloth != nil {
			fmt.eprintf("%v cloth: grid=%v source=%v snapshot=%v sequence=%v config=%v first=%v pin=%v\n",
				env.mode, cloth.grid, cloth.pose_source, cloth.snapshot_received, cloth.snapshot_tick,
				cloth.snapshot_config, cloth.particles[0].position, cloth.pin_attachments[len(cloth.particles) - 1] != nil)
		}
	}
	panic(description)
}

main :: proc() {
	server_vm, client_vm := vm.New(), vm.New()
	server, client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm, nil, .Server)
	engine_runtime.Environment_Init(&client, &client_vm, nil, .Client)
	defer {
		vm.Close(&client_vm)
		engine_runtime.Environment_Destroy(&client)
		vm.Close(&server_vm)
		engine_runtime.Environment_Destroy(&server)
	}
	run(&server_vm, `
game:GetService("Physics")
local net = game:GetService("ReplicatorService")
assert(net:StartServer("127.0.0.1", 39471))
workspace.SimulatePhysics = true
cloth = Instance.new("Cloth", workspace)
cloth.Name = "NetCloth"
cloth.ClothType = Enum.ClothType.Curtain
cloth.Size = Vector2.new(9, 5)
cloth.SegmentsX = 48
cloth.SegmentsY = 48
cloth.RenderSegmentsX = 64
cloth.CanCollide = false
cloth.SelfCollision = true
cloth.MaterialVariant = "Velvet"
local rail = Instance.new("Part", workspace)
rail.Name = "Rail"
rail.Anchored = true
rail.CanCollide = false
left = Instance.new("Attachment", rail)
left.Name = "Left"
left.Position = Vector3.new(-5, 7, 3)
cloth:PinRegion(Vector2.zero, Vector2.new(1, 1), left)
`)
	run(&client_vm, `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39471))`)
	step_until(&server, &client, &server_vm, &client_vm, "initial cloth configuration and pose", proc(cloth: ^classes.Cloth) -> bool {
		return cloth.snapshot_received && cloth.segments_x == 48 &&
			cloth.pin_attachments[2400] != nil && cloth.particles[0].position.x == -5
	})
	client_net := cast(^services.ReplicatorService)services.Ensure_Service(&client.services, "ReplicatorService")
	assert(client_net.remote_zstd_received > 0)
	run(&client_vm, `
local cloth = workspace.NetCloth
assert(cloth.ClothType == Enum.ClothType.Curtain and cloth.SelfCollision)
assert(cloth.RenderSegmentsX == 64 and cloth.MaterialVariant == "Velvet")
assert(cloth:GetPins()[2401] == workspace.Rail.Left)
assert((cloth:GetVertexPosition(1) - Vector3.new(-5, 7, 3)).Magnitude < 0.001)
`)
	// Move a sleeping, fully pinned sheet. The final reliable keyframe must arrive.
	run(&server_vm, `left.Position = Vector3.new(-3, 9, 4)`)
	step_until(&server, &client, &server_vm, &client_vm, "moving attachment and interpolated pose", proc(cloth: ^classes.Cloth) -> bool {
		return cloth.pose_source == .Replication && cloth.snapshot_duration > 0 &&
			cloth.snapshot_elapsed >= cloth.snapshot_duration &&
			abs(cloth.particles[0].position.x + 3) + abs(cloth.particles[0].position.y - 9) + abs(cloth.particles[0].position.z - 4) < 0.001
	})
	run(&server_vm, `
local rail = Instance.new("Part", workspace)
rail.Name = "MovedRail"
rail.Anchored = true
rail.CanCollide = false
left.Parent = rail
`)
	step_until(&server, &client, &server_vm, &client_vm, "attachment reparent", proc(cloth: ^classes.Cloth) -> bool {
		pin := cloth.pin_attachments[2400]
		return pin != nil && pin.parent != nil && pin.parent.name == "MovedRail"
	})
	run(&server_vm, `
cloth:ClearPins()
cloth.SegmentsX = 24
cloth.SegmentsY = 24
cloth:PinRegion(Vector2.zero, Vector2.new(1, 1), left)
cloth:SetPinWeight(625, left, 0.5)
`)
	step_until(&server, &client, &server_vm, &client_vm, "runtime resize and pin weight", proc(cloth: ^classes.Cloth) -> bool {
		return cloth.snapshot_received && len(cloth.particles) == 625 &&
			cloth.pin_weights[624] == 0.5 && cloth.pin_attachments[624] != nil
	})
	run(&server_vm, `left:Destroy()`)
	step_until(&server, &client, &server_vm, &client_vm, "destroyed attachment", proc(cloth: ^classes.Cloth) -> bool {
		return cloth.snapshot_received && cloth.pin_attachments[624] == nil && cloth.snapshot_tick > 0
	})
	run(&client_vm, `game:GetService("ReplicatorService"):Stop()`)
	run(&server_vm, `game:GetService("ReplicatorService"):Stop()`)
	fmt.println("CLOTH_REPLICATION_SMOKE_PASSED")
}
