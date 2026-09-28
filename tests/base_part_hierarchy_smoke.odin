// BasePart is the abstract parent of every solid-geometry class, and
// `IsA("BasePart")` is the filter almost every part-oriented script uses. The
// class chain used to go straight from Instance to Part, so the check matched
// nothing and silently selected zero objects.
package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("base part hierarchy smoke failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(
		&script_vm,
		`
local model = Instance.new("Model")
model.Name = "Map"
model.Parent = workspace

local part = Instance.new("Part", model)
part.Name = "Platform"
part.Anchored = true

local mesh = Instance.new("MeshPart", model)
mesh.Name = "Rock"
mesh.Anchored = true

local folder = Instance.new("Folder", model)
folder.Name = "Decor"

-- The traversal itself always worked; it is the filter that matched nothing.
assert(#model:GetDescendants() == 3, "GetDescendants lost a child")
assert(#model:GetChildren() == 3, "GetChildren lost a child")

-- The actual regression: IsA("BasePart").
assert(part:IsA("BasePart"), "a Part is not a BasePart")
assert(mesh:IsA("BasePart"), "a MeshPart is not a BasePart")
assert(not folder:IsA("BasePart"), "a Folder is not a BasePart")
assert(not workspace:IsA("BasePart"), "Workspace is not a BasePart")

-- The rest of the chain must be undisturbed by the new link.
assert(part:IsA("Part") and part:IsA("Instance"), "Part chain broke")
assert(mesh:IsA("MeshPart") and mesh:IsA("Part"), "MeshPart chain broke")
assert(not part:IsA("MeshPart"), "Part must not match MeshPart")
assert(not part:IsA("Service"), "Part must not match Service")

-- BasePart is abstract, so it cannot be instantiated directly.
assert(not pcall(function() return Instance.new("BasePart") end), "BasePart should not be creatable")

-- And the idiom from the report now selects what it should.
local parts = {}
for _, object in model:GetDescendants() do
    if object:IsA("BasePart") and object.Anchored then
        table.insert(parts, object)
    end
end
assert(#parts == 2, "IsA(BasePart) and Anchored matched " .. #parts .. " objects, expected 2")
assert(parts[1] == part or parts[2] == part, "the anchored Part was not selected")
assert(parts[1] == mesh or parts[2] == mesh, "the anchored MeshPart was not selected")

-- Unanchoring through the selected object has to actually take effect.
parts[1].Anchored = false
assert(parts[1].Anchored == false, "Anchored = false did not apply")
`,
		"base_part_hierarchy",
	)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("BASE_PART_HIERARCHY_SMOKE_PASSED")
}