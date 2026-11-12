package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import assetstore "../src/engine/assetstore"
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	defer vm.Close(&script_vm)
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	defer engine_runtime.Environment_Destroy(&environment)
	defer assetstore.Clear()

	run(&script_vm, `
local function block(x)
	local part = Instance.new("Part")
	part.Size = Vector3.new(4, 4, 4)
	part.Position = Vector3.new(x, 0, 0)
	return part
end
local a, b = block(0), block(2)
local union = a:UnionAsync({b})
assert(union:IsA("PartOperation") and union.ClassName == "UnionOperation")
assert(union.Size == Vector3.new(6, 4, 4) and union.Position == Vector3.new(1, 0, 0))
assert(union.Parent == nil and a.Size == Vector3.new(4, 4, 4))
local intersection = a:IntersectAsync({b})
assert(intersection.ClassName == "IntersectOperation" and intersection.Size == Vector3.new(2, 4, 4))
local difference = a:SubtractAsync({b})
assert(difference.Size == Vector3.new(2, 4, 4) and difference.Position == Vector3.new(-1, 0, 0))
local cutter = b:Negate()
assert(cutter.ClassName == "NegateOperation" and not cutter.CanCollide and not cutter.CanQuery)
local withNegation = a:UnionAsync({cutter})
assert(withNegation.Size == difference.Size and withNegation.Position == difference.Position)
assert(not pcall(function() a:IntersectAsync({block(20)}) end))
assert(not pcall(function() a:UnionAsync({false}) end))
assert(string.find(union.MeshId, "^kineasset://"))
union.UsePartColor = false
assert(not union:Clone().UsePartColor)
local wedge = block(1)
wedge.Shape = Enum.PartType.Wedge
assert(a:UnionAsync({wedge}):IsA("UnionOperation"))
local rotated = block(0)
rotated.Size = Vector3.new(8, 4, 4)
rotated.CFrame = CFrame.Angles(0, 0, math.pi / 2)
local copied = rotated:Negate()
assert((copied.Size - rotated.Size).Magnitude < 0.001)
assert((copied.CFrame.RightVector - rotated.CFrame.RightVector).Magnitude < 0.001)
SavedUnion = union
SavedCutter = b
`, "solid_operations")

	vm.GetGlobal(script_vm.L, "SavedUnion")
	solid := classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	data, err := serializer.Serialize(&environment.classes, script_vm.L, solid)
	defer delete(data)
	defer serializer.Error_Delete(&err)
	serializer.Error_Print(err, "solid save: ")
	assert(serializer.Error_Is_None(err))

	assetstore.Clear()
	reloaded, load_err := serializer.Deserialize(&environment.classes, script_vm.L, nil, data)
	defer serializer.Error_Delete(&load_err)
	serializer.Error_Print(load_err, "solid load: ")
	assert(serializer.Error_Is_None(load_err) && reloaded != nil)
	mesh := cast(^classes.MeshPart)reloaded
	bytes, found := assetstore.Resolve_Bytes(mesh.mesh_id)
	assert(found && len(bytes) > 0)
	obj := string(bytes)
	assert(strings.contains(obj, "\nvn 1 0 0\n") &&
	       strings.contains(obj, "\nvn 0 1 0\n") &&
	       strings.contains(obj, "//"), "a box union must keep hard face normals after reload")
	classes.Push_Object(script_vm.L, reloaded)
	vm.SetGlobalFromStack(&script_vm, "ReloadedUnion")
	run(&script_vm, `
assert(ReloadedUnion.ClassName == "UnionOperation" and not ReloadedUnion.UsePartColor)
assert(ReloadedUnion.Size == Vector3.new(6, 4, 4))
local trimmed = ReloadedUnion:SubtractAsync({SavedCutter})
assert(trimmed.Size == Vector3.new(2, 4, 4))
`, "solid_roundtrip")
	test_collision(&script_vm)
	when #config(TEST_CSG_REPLICATION, false) {
		test_replication(&environment, &script_vm)
	}
	if len(os.args) > 1 {test_construct(&environment, &script_vm, os.args[1])}
	fmt.println("PART_OPERATION_SMOKE_PASSED")
}

test_collision :: proc(script_vm: ^vm.VM) {
	run(script_vm, `
local function block(size, position)
	local part = Instance.new("Part")
	part.Size = size
	part.Position = position
	return part
end

local slab = block(Vector3.new(12, 2, 12), Vector3.new(30, 0, 0))
local cutter = block(Vector3.new(4, 6, 4), slab.Position)
local ring = slab:UnionAsync({cutter:Negate()})
assert(ring.CollisionFidelity == Enum.CollisionFidelity.Default)
ring.Parent = workspace

local function ray(x, z)
	return workspace:Raycast(Vector3.new(x, 5, z), Vector3.new(0, -10, 0))
end
local function checkOpening()
	assert(ray(30, 0) == nil, "the opening should have no collision")
	local wall = ray(34, 0)
	assert(wall and wall.Instance == ring, "the wall should have collision")
	assert(math.abs(wall.Position.Y - 1) < 0.06)
end

checkOpening()
ring.CollisionFidelity = Enum.CollisionFidelity.Hull
assert(ray(30, 0).Instance == ring)
ring.CollisionFidelity = Enum.CollisionFidelity.TriangleMesh
ring.Anchored = false
checkOpening()
ring.Anchored = true
ring.Size = Vector3.new(12, 4, 12)
assert(math.abs(ray(34, 0).Position.Y - 2) < 0.01)
ring.Size = Vector3.new(12, 2, 12)

local probe = block(Vector3.new(1, 1, 1), Vector3.new(30, 0, 0))
probe.Parent = workspace
assert(#workspace:GetPartsInPart(probe) == 0, "a block fits through the opening")
probe.Position = Vector3.new(34, 1, 0)
assert(workspace:GetPartsInPart(probe)[1] == ring, "a block overlaps the wall")
probe:Destroy()
ring:Destroy()
`, "solid_collision_queries")
}

test_construct :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM, path: string) {
	assert(engine_runtime.Load_Map(environment, script_vm, path))
	descriptor := classes.Find_Class(&environment.classes, "UnionOperation")
	count := 0
	for object in descriptor.instances {
		if object.destroyed || object.parent == nil {continue}
		part := cast(^classes.MeshPart)object
		data, found := assetstore.Resolve_Bytes(part.mesh_id)
		assert(found && len(data) > 0 && part.size.x > 0 && part.size.y > 0 && part.size.z > 0)
		count += 1
	}
	assert(count == 25, fmt.tprintf("expected 25 Construct unions, got %d", count))
	run(script_vm, `
local blocks = game:GetService("ReplicatedStorage").Shared.Storage.Blocks
assert(blocks.Motor.Detail:IsA("UnionOperation"))
assert(blocks["Delta Wing"].Union:IsA("UnionOperation"))
assert(blocks.Thruster.Union:IsA("UnionOperation"))
assert(blocks["2-Point L Differential"].Base:IsA("UnionOperation"))
local imported = blocks.Motor.Detail:Clone()
imported.Anchored = true
imported.CollisionFidelity = Enum.CollisionFidelity.Default
imported.Position = Vector3.new(0, 200, 0)
imported.Parent = workspace
local physics = game:GetService("Physics")
workspace:Raycast(Vector3.new(0, 220, 0), Vector3.new(0, -40, 0))
local count = physics.BodyCount
imported:Destroy()
workspace:Raycast(Vector3.new(0, 220, 0), Vector3.new(0, -40, 0))
assert(physics.BodyCount == count - 1, "an imported union should have a Jolt body")
`, "construct_union_catalog")
}

test_replication :: proc(server: ^engine_runtime.Environment, server_vm: ^vm.VM) {
	client_vm := vm.New()
	defer vm.Close(&client_vm)
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&client, &client_vm)
	defer engine_runtime.Environment_Destroy(&client)
	run(server_vm, `
local replication = game:GetService("ReplicatorService")
assert(replication:StartServer("127.0.0.1", 39274))
replication.RelevancyDistance = 10000
workspace.SimulatePhysics = false
`, "solid_server")
	run(&client_vm, `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39274))`, "solid_client")
	for _ in 0 ..< 180 {
		engine_runtime.Environment_Render_Step(server, server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
		time.sleep(2 * time.Millisecond)
	}
	replicator := cast(^services.ReplicatorService)services.Find_Service(&server.services, "ReplicatorService").object
	sent_before := replicator.assets_sent
	run(server_vm, `
local solid = ReloadedUnion:UnionAsync({SavedCutter:Clone()})
local extension = Instance.new("Part")
extension.Position = Vector3.new(4, 0, 0)
extension.Size = Vector3.new(4, 4, 4)
solid = solid:UnionAsync({extension})
solid.Name = "RuntimeUnion"
solid.Parent = workspace
`, "solid_server_create")
	for _ in 0 ..< 180 {
		engine_runtime.Environment_Render_Step(server, server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
		time.sleep(2 * time.Millisecond)
	}
	run(&client_vm, `
local solid = game:GetService("Workspace"):FindFirstChild("RuntimeUnion")
assert(solid and solid.ClassName == "UnionOperation", "union should replicate")
assert(string.find(solid.MeshId, "^kineasset://") and solid.Size == Vector3.new(8, 4, 4))
`, "solid_client_verify")
	assert(replicator.assets_sent == sent_before + 1)
	run(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "solid_client_stop")
	run(server_vm, `game:GetService("ReplicatorService"):Stop()`, "solid_server_stop")
}

run :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(script_vm, source, name)
	defer delete(err)
	if !ok {panic(err)}
}
