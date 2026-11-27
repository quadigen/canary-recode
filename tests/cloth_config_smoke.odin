package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:time"
import "core:strings"

run :: proc(script_vm: ^vm.VM, source: string) {
	ok, message := vm.Run(script_vm, source, "cloth_config_smoke")
	assert(ok, message)
}

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	defer {vm.Close(&script_vm); engine_runtime.Environment_Destroy(&env)}
	run(&script_vm, `
group = Instance.new("Folder", workspace)
local rail = Instance.new("Part", group)
rail.Name = "Rail"
rail.Anchored = true
rail.CanCollide = false
rail.CFrame = CFrame.new(0, 10, 0)
left = Instance.new("Attachment", rail)
left.Name = "Left"
right = Instance.new("Attachment", rail)
right.Name = "Right"
right.Position = Vector3.new(8, 0, 0)

curtain = Instance.new("Cloth", group)
curtain.Name = "Curtain"
curtain.ClothType = Enum.ClothType.Curtain
assert(curtain.FoldCount == 6 and curtain.FoldDepth == 0.25)
assert(math.abs(curtain.GatherRatio - 0.65) < 1e-5)
curtain.Size = Vector2.new(12, 8)
curtain.SegmentsX = 48
curtain.SegmentsY = 24
curtain.RenderSegmentsX = 96
curtain.RenderSegmentsY = 48
curtain.FoldCount = 8
curtain.FoldDepth = 0.35
curtain.CanCollide = false
curtain.SelfCollision = true
curtain.Attachment0 = left
curtain.Attachment1 = right
assert(curtain:GetVertexCount() == 1225)
assert(not pcall(function() curtain.SegmentsX = 65 end))
assert(not pcall(function() curtain.SolverIterations = 0 end))

sheet = Instance.new("Cloth", group)
sheet.Name = "Sheet"
sheet.ClothType = Enum.ClothType.Custom
sheet.SegmentsX = 24
sheet.SegmentsY = 24
sheet.CanCollide = false
sheet:PinRegion(Vector2.zero, Vector2.new(1, 1), left)
assert(sheet:GetVertexCount() == 625)
assert(sheet:GetPins()[625] == left)
assert(sheet:GetVertexPosition(625) == Vector3.new(6, 6, 0))
sheet:UnpinPoint(Vector2.new(1, 1))
assert(sheet:GetPins()[625] == nil)
sheet:PinRegion(Vector2.zero, Vector2.new(1, 1), left)
assert(sheet:GetPinWeight(625) == 1)

local presets = { Enum.ClothType.Flag, Enum.ClothType.Hammock, Enum.ClothType.Cape }
for _, kind in ipairs(presets) do
    local item = Instance.new("Cloth", group)
    item.ClothType = kind
    assert(item:GetVertexPosition(1))
    if kind == Enum.ClothType.Hammock then
        assert(item:GetVertexPosition(6).Y < item:GetVertexPosition(1).Y)
        assert(item:GetVertexPosition(121).Y == item:GetVertexPosition(11).Y)
    end
    item:Destroy()
end
`)
	workspace := services.Ensure_Service(&env.services, "Workspace")
	physics := cast(^services.Physics)services.Ensure_Service(&env.services, "Physics")
	vm.GetGlobal(script_vm.L, "group")
	group := classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	curtain := cast(^classes.Cloth)classes.Find_First_Child(group, "Curtain")
	sheet := cast(^classes.Cloth)classes.Find_First_Child(group, "Sheet")
	assert(classes.Cloth_Prepare_Surface(curtain, workspace))
	classes.Cloth_Build_Surface(curtain)
	assert(len(curtain.surface_vertices) == 97 * 49 && len(curtain.surface_indices) == 96 * 48 * 6)
	for vertex in curtain.surface_vertices {
		assert(abs(vertex[3]*vertex[3] + vertex[4]*vertex[4] + vertex[5]*vertex[5] - 1) < 0.001)
	}
	for _ in 0..<8 {services.Physics_Step(physics, 1.0/144)}
	start := time.tick_now()
	for _ in 0..<144 {services.Physics_Step(physics, 1.0/144)}
	fmt.printf("Cloth physics and world step averaged %.2f ms at 48x24 and 24x24\n", time.duration_milliseconds(time.tick_since(start)) / 144)
	assert(physics.cloth_workers.worker != nil)
	assert(abs(curtain.particles[1].position.z) > 0.25)
	assert(abs(curtain.particles[1 + 8 * 49].position.z) > 0.07)
	assert(sheet.pinned[624])
	for particle in curtain.particles {
		for value in particle.position {assert(!math.is_nan(value) && !math.is_inf(value))}
	}

	run(&script_vm, `
left.CFrame = CFrame.new(0, 1, 0) * CFrame.Angles(0, math.pi / 2, 0)
sheet:SetPinWeight(601, left, 0.45)
assert(math.abs(sheet:GetPinWeight(601) - 0.45) < 0.001)
`)
	services.Physics_Step(physics, 1.0/60)
	assert(abs(sheet.particles[624].position.z + 6) < 0.001)
	assert(abs(sheet.particles[624].position.y - 7) < 0.001)

	data, write_err := serializer.Serialize(&env.classes, script_vm.L, group)
	assert(serializer.Error_Is_None(write_err), serializer.Error_String(write_err))
	defer delete(data)
	restored, read_err := serializer.Deserialize(&env.classes, script_vm.L, nil, data)
	assert(serializer.Error_Is_None(read_err), serializer.Error_String(read_err))
	restored_curtain := cast(^classes.Cloth)classes.Find_First_Child(restored, "Curtain")
	assert(restored_curtain.cloth_type == .Curtain && restored_curtain.fold_count == 8)
	assert(restored_curtain.segments_x == 48 && restored_curtain.segments_y == 24)
	assert(restored_curtain.render_segments_x == 96 && restored_curtain.self_collision)
	restored_sheet := cast(^classes.Cloth)classes.Find_First_Child(restored, "Sheet")
	restored_left := classes.Find_First_Child(classes.Find_First_Child(restored, "Rail"), "Left")
	assert(restored_sheet.pin_attachments[624] == restored_left)
	assert(restored_sheet.pin_offsets[624] == [3]f32{6, -4, 0})
	assert(abs(restored_sheet.pin_weights[600] - 0.45) < 0.001)

	run(&script_vm, `
local clone = group:Clone()
assert(clone.Sheet:GetPins()[625] == clone.Rail.Left)
sheet:UnpinVertex(625)
local before = sheet:GetVertexPosition(625)
assert(sheet:GetVertexPosition(625) == before)
left:Destroy()
assert(next(sheet:GetPins()) == nil)
sheet.SegmentsX = 48
sheet.SegmentsY = 48
assert(sheet:GetVertexCount() == 2401)
`)
	services.Physics_Step(physics, 1.0/60)
	assert(sheet.initialized && len(sheet.particles) == 2401)

	run(&script_vm, `
workspace.Gravity = 0
overlap = Instance.new("Cloth", workspace)
overlap.ClothType = Enum.ClothType.Custom
overlap.SegmentsX = 2
overlap.SegmentsY = 2
overlap.CanCollide = false
overlap.StretchStiffness = 0
overlap.ShearStiffness = 0
overlap.BendStiffness = 0
overlap.SelfCollision = true
assert(overlap:GetVertexPosition(1))
`)
	vm.GetGlobal(script_vm.L, "overlap")
	overlap := cast(^classes.Cloth)classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	overlap.particles[8].position = overlap.particles[0].position
	services.Physics_Step_Cloth(physics, cast(^services.Workspace)workspace, 1.0/144)
	assert(linalg.length(overlap.particles[8].position - overlap.particles[0].position) >= 0.079)
	test_editor(&script_vm)
	fmt.println("CLOTH_CONFIG_SMOKE_PASSED")
}


test_editor :: proc(state: ^vm.VM) {
	// Substitute the external editor viewport while exercising real engine UI classes and pin APIs.
	source := strings.concatenate({
		`
local editorOverlay = Instance.new("Frame")
local currentTool
local viewportMock = {
    GetOverlay = function() return editorOverlay end,
    SetSelectionTool = function(nextTool) currentTool = nextTool end,
    GetSelectionTool = function() return currentTool end,
    IsSceneVisible = function() return true end,
    ViewportToScreenPoint = function(point) return point end,
    ContainsPoint = function() return true end,
}
local require = function(name)
    if name == "@internal/viewport" then
        return viewportMock
    end
    return {
        tokens = { color = { canvas = Color3.fromRGB(25, 30, 38) } },
        create = function(className, props, parent)
            local instance = Instance.new(className)
            for key, value in pairs(props) do instance[key] = value end
            instance.Parent = parent
            return instance
        end,
    }
end
`,
		#load("../src/sandboxed/cloth_editor.luau", string),
		`
local editCloth = Instance.new("Cloth", workspace)
editCloth.ClothType = Enum.ClothType.Custom
local mount = Instance.new("Part", workspace)
local editAttachment = Instance.new("Attachment", mount)
local camera = Instance.new("Camera", workspace)
camera.CFrame = CFrame.new(0, -2, 12)
workspace.CurrentCamera = camera
Selection:Set({ editCloth, editAttachment })
selectionChanged()
assert(panel.Visible and attachment == editAttachment)
setActive(true)
assert(currentTool == tool)
local projected, inView = camera:WorldToViewportPoint(editCloth:GetVertexPosition(1))
assert(inView)
local click = Vector2.new(projected.X, projected.Y)
tool:Pick(click)
assert(vertex == 1)
mode = "Paint"
weightField.Text = "0.5"
radiusField.Text = "2"
tool:Pick(click)
assert(editCloth:GetPins()[1] == editAttachment)
assert(editCloth:GetPinWeight(1) == 0.5)
mode = "Erase"
tool:Pick(click)
assert(editCloth:GetPins()[1] == nil)
setActive(false)
assert(currentTool == nil)
`,
	})
	defer delete(source)
	ok, message := vm.RunInternal(state, source, "cloth_editor_smoke")
	assert(ok, message)
}
