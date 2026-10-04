package main

import "core:fmt"
import "core:math"
import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import datatypes "../src/engine/datatypes"
import enums "../src/engine/enum"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

STEP_DT :: f32(1.0 / 60.0)
VIEWPORT_WIDTH :: i32(800)
VIEWPORT_HEIGHT :: i32(600)

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic(name)
	}
}

expect_close :: proc(actual, expected: f32, message: string) {
	assert(abs(actual - expected) < 1e-3, message)
}

part_origin :: proc(object: ^classes.Object) -> datatypes.Vector3 {
	part := cast(^classes.Part)object
	return datatypes.Vector3{part.cframe.x, part.cframe.y, part.cframe.z}
}

spawn_in_model :: proc(
	registry: ^classes.Registry,
	script_vm: ^vm.VM,
	model: ^classes.Object,
	size: datatypes.Vector3,
	position: datatypes.Vector3,
	name: string,
) -> ^classes.Object {
	object, ok := classes.Push_New(registry, script_vm, "Part")
	assert(ok && object != nil)
	vm.Pop(script_vm.L)
	classes.Set_Name(object, name)
	part := cast(^classes.Part)object
	part.size = size
	part.cframe = datatypes.CFrame_New_XYZ(position.x, position.y, position.z)
	classes.Set_Parent(object, model)
	return object
}

reset_part :: proc(object: ^classes.Object, x, y, z: f32) {
	part := cast(^classes.Part)object
	part.cframe = datatypes.CFrame_New_XYZ(x, y, z)
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	view: renderer.RendererObject
	engine_runtime.Environment_Init(&environment, &script_vm, &view)
	view.HasViewportRect = true
	view.ViewportRect = {0, 0, VIEWPORT_WIDTH, VIEWPORT_HEIGHT}

	run_script(
		&script_vm,
		`
local reflection = game:GetService("ReflectionService")

local handles_class = reflection:GetClass("Handles")
assert(handles_class ~= nil, "Handles must be reflected")
assert(handles_class.Superclass == "PartAdornment", "Handles superclass: " .. tostring(handles_class.Superclass))
assert(reflection:GetClass("ArcHandles") ~= nil, "ArcHandles must be reflected")

local props = {}
for _, property in reflection:GetPropertiesOfClass("Handles") do
	props[property.Name] = true
end
for _, name in ipairs({ "Adornee", "Color3", "Faces", "Style", "Visible", "Snap" }) do
	assert(props[name], "Handles must reflect " .. name)
end

local model = Instance.new("Model")
local child = Instance.new("Part")
child.Parent = model
local part = Instance.new("Part")
local folder = Instance.new("Folder")

local handles = Instance.new("Handles")
assert(handles.Adornee == nil, "Adornee must start nil")
assert(handles.Visible == true, "Handles must start visible")

for _, style in ipairs({ Enum.HandlesStyle.Movement, Enum.HandlesStyle.Rotation, Enum.HandlesStyle.Resize }) do
	handles.Style = style
	assert(handles.Style == style, "Style must round-trip")
end

-- A Model and a BasePart are both valid adornees.
handles.Adornee = model
assert(handles.Adornee == model, "Adornee must round-trip a Model")
handles.Adornee = part
assert(handles.Adornee == part, "Adornee must round-trip a BasePart")

-- Anything else is rejected, and a rejected write must leave the old adornee.
assert(not pcall(function() handles.Adornee = folder end), "a Folder must be rejected")
assert(handles.Adornee == part, "a rejected Adornee must not replace the old one")

handles.Adornee = nil
assert(handles.Adornee == nil, "Adornee must clear to nil")

local arc = Instance.new("ArcHandles")
arc.Adornee = model
assert(arc.Adornee == model, "ArcHandles.Adornee must round-trip a Model")
`,
		"handles_contract",
	)

	// --- geometry ---------------------------------------------------------------
	model, model_ok := classes.Push_New(&environment.classes, &script_vm, "Model")
	assert(model_ok && model != nil)
	vm.Pop(script_vm.L)
	classes.Set_Name(model, "HandlesSmokeModel")

	part_a := spawn_in_model(
		&environment.classes,
		&script_vm,
		model,
		datatypes.Vector3{2, 2, 2},
		datatypes.Vector3{0, 0, 0},
		"PartA",
	)
	part_b := spawn_in_model(
		&environment.classes,
		&script_vm,
		model,
		datatypes.Vector3{2, 2, 2},
		datatypes.Vector3{10, 0, 0},
		"PartB",
	)

	bounds_min, bounds_max, found := classes.Handles_Model_Bounds(model)
	assert(found, "a model with parts must have bounds")
	expect_close(bounds_min.x, -1, "bounds min x")
	expect_close(bounds_max.x, 11, "bounds max x")

	pivot, pivot_ok := classes.Handles_Model_Pivot(model)
	assert(pivot_ok, "a model with parts must have a pivot")
	expect_close(pivot.x, 5, "pivot must sit at the box centre")
	expect_close(pivot.y, 0, "pivot y")
	expect_close(pivot.z, 0, "pivot z")

	// Move: every part translates by the delta.
	classes.Handles_Apply_Model_Axis(model, pivot, kineffi.KINE_GIZMO_AXIS_X, 4, .Movement)
	expect_close(part_origin(part_a).x, 4, "move must translate PartA")
	expect_close(part_origin(part_b).x, 14, "move must translate PartB")

	reset_part(part_a, 0, 0, 0)
	reset_part(part_b, 10, 0, 0)

	// Rotate: 90 degrees about the model's Y axis revolves both parts around the
	// pivot without moving the pivot itself.
	rotate_pivot, _ := classes.Handles_Model_Pivot(model)
	classes.Handles_Apply_Model_Axis(
		model,
		rotate_pivot,
		kineffi.KINE_GIZMO_AXIS_Y,
		f32(math.PI / 2),
		.Rotation,
	)
	expect_close(part_origin(part_a).x, 5, "rotate must orbit PartA in x")
	expect_close(part_origin(part_a).z, 5, "rotate must orbit PartA in z")
	expect_close(part_origin(part_b).x, 5, "rotate must orbit PartB in x")
	expect_close(part_origin(part_b).z, -5, "rotate must orbit PartB in z")

	reset_part(part_a, 0, 0, 0)
	reset_part(part_b, 10, 0, 0)

	// Resize: the model's extent along X grows by the delta, scaling part sizes
	// and their offsets from the pivot together.
	scale_pivot, _ := classes.Handles_Model_Pivot(model)
	classes.Handles_Apply_Model_Axis(model, scale_pivot, kineffi.KINE_GIZMO_AXIS_X, 4, .Resize)
	expect_close((cast(^classes.Part)part_a).size.x, 8.0 / 3.0, "scale must grow PartA size")
	expect_close((cast(^classes.Part)part_b).size.x, 8.0 / 3.0, "scale must grow PartB size")
	expect_close(part_origin(part_a).x, -5.0 / 3.0, "scale must push PartA out")
	expect_close(part_origin(part_b).x, 35.0 / 3.0, "scale must push PartB out")

	// The Render_3D step must stay safe when a Handles adorns a Model even with no
	// Filament context.
	handles_object, handles_ok := classes.Push_New(&environment.classes, &script_vm, "Handles")
	assert(handles_ok && handles_object != nil)
	vm.Pop(script_vm.L)
	handles := cast(^classes.Handles)handles_object
	handles.Adornee = model
	handles.Style = .Movement
	engine_runtime.Environment_Update_Step(&environment, &script_vm, STEP_DT)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("HANDLES_SMOKE_PASSED")
}
