package main

import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"

main :: proc() {
	source_vm := vm.New()
	source: engine_runtime.Environment
	engine_runtime.Environment_Init(&source, &source_vm)
	defer {vm.Close(&source_vm); engine_runtime.Environment_Destroy(&source)}
	ok, err := vm.Run(&source_vm, `
local p = Instance.new("Part", workspace)
p.Name = "SurfaceSmoke"
local faces = {"TopSurface", "BottomSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface"}
local values = {Enum.SurfaceType.Studs, Enum.SurfaceType.Inlet, Enum.SurfaceType.Glue, Enum.SurfaceType.Universal, Enum.SurfaceType.SmoothNoOutlines, Enum.SurfaceType.Weld}
for i, name in faces do
    assert(p[name] == Enum.SurfaceType.Smooth, name)
    p[name] = values[i]
    assert(p[name] == values[i], name)
end
assert(not pcall(function() p.TopSurface = Enum.Material.Plastic end))
assert(p.TopSurface == Enum.SurfaceType.Studs)
local c = p:Clone()
for i, name in faces do assert(c[name] == values[i], name) end
c.TopSurface = Enum.SurfaceType.Smooth
assert(p.TopSurface == Enum.SurfaceType.Studs)
c:Destroy()
local changed = false
p:GetPropertyChangedSignal("TopSurface"):Connect(function() changed = true end)
p.TopSurface = Enum.SurfaceType.Inlet
assert(changed and p.TopSurface == Enum.SurfaceType.Inlet)
p.TopSurface = Enum.SurfaceType.Studs
`, "surface_properties")
	assert(ok, err)
	path := "/tmp/kinemium-surface-smoke.kine"
	defer os.remove(path)
	failure := serializer.Serialize_To_File(&source.classes, source_vm.L, &source.services.data_model.object, path)
	assert(serializer.Error_Is_None(failure), serializer.Error_String(failure))
	serializer.Error_Delete(&failure)
	client_vm := vm.New()
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&client, &client_vm)
	defer {vm.Close(&client_vm); engine_runtime.Environment_Destroy(&client)}
	assert(engine_runtime.Load_Map(&client, &client_vm, path))
	ok, err = vm.Run(&client_vm, `
local p = workspace.SurfaceSmoke
assert(p.TopSurface == Enum.SurfaceType.Studs)
assert(p.BottomSurface == Enum.SurfaceType.Inlet)
assert(p.FrontSurface == Enum.SurfaceType.Glue)
assert(p.BackSurface == Enum.SurfaceType.Universal)
assert(p.LeftSurface == Enum.SurfaceType.SmoothNoOutlines)
assert(p.RightSurface == Enum.SurfaceType.Weld)
`, "surface_roundtrip")
	assert(ok, err)
	fmt.println("PART_SURFACE_SMOKE_PASSED")
}
