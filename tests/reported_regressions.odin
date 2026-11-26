package main

import native_api "../src/engine/native_api"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	state := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &state)
	defer {
		engine_runtime.Environment_Destroy(&environment)
		vm.Close(&state)
	}

	ok, err := vm.Run(&state, `
local http = game:GetService("HttpService")
local function rejects(value)
	assert(not pcall(http.JSONEncode, http, value))
	assert(http:JSONEncode({1, 2}) == "[1,2]")
end
rejects({0/0})
rejects({math.huge})
rejects({function() end})
local cycle = {}
cycle.self = cycle
rejects(cycle)
rejects({[{}] = 1})
local sparse = http:JSONDecode(http:JSONEncode({[1] = 1, [100] = 2}))
assert(sparse["1"] == 1 and sparse["100"] == 2)
local nested = 1
for i = 1, 64 do nested = {nested} end
local encoded = http:JSONEncode(nested)
assert(http:JSONDecode(encoded) ~= nil)
assert(not pcall(http.JSONEncode, http, {nested}))
assert(not pcall(http.JSONDecode, http, string.rep("[", 65)))
assert(http:JSONDecode('"{[x]}"') == "{[x]}")
local key = "a" .. string.char(0) .. "b"
local roundtrip = http:JSONDecode(http:JSONEncode({[key] = key}))
assert(roundtrip[key] == key)
local guid = http:GenerateGUID()
assert(#guid == 38 and guid:sub(1,1) == "{" and guid:sub(-1) == "}")
assert(#http:GenerateGUID(false) == 36)
assert(tostring(UDim.new(1, 2)) == "{1, 2}")
assert(tostring(UDim2.new(0.5, 10, 1, 0)) == "{0.5, 10}, {1, 0}")
assert(tostring(Ray.new(Vector3.new(1, 2, 3), Vector3.new(4, 5, 6))) == "{1, 2, 3}, {4, 5, 6}")
local folder = Instance.new("Folder")
local child = Instance.new("Folder")
child.Name = key
child.Parent = folder
assert(child.Name == key and folder:FindFirstChild(key) == child)
local log = game:GetService("LogService")
print("A", "B", 1)
warn("A", "B", 1)
local history = log:GetLogHistory()
assert(history[#history - 1].message == "A	B	1")
assert(history[#history].message == "A	B	1")
local mesh = Instance.new("MeshPart")
mesh.MeshId = "example"
assert(not pcall(function() mesh.MeshId = nil end))
assert(mesh.MeshId == "example")
mesh.MeshId = "replacement"
assert(mesh.MeshId == "replacement")
`, "reported_regressions")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("Luau regression failed")
	}

	ctx := &environment.extensions.native_context
	handle := native_api.Kinemium_HandleCreateInstance(ctx, "MeshPart")
	assert(handle != 0)
	assert(native_api.Kinemium_HandleSetDynamicString(ctx, handle, "MeshId", "original"))
	assert(!native_api.Kinemium_HandleSetDynamicNil(ctx, handle, "MeshId"))
	buffer: [32]u8
	assert(native_api.Kinemium_HandleGetDynamicString(ctx, handle, "MeshId", raw_data(buffer[:]), len(buffer)) == 8)
	assert(string(buffer[:8]) == "original")
	assert(native_api.Kinemium_HandleSetDynamicString(ctx, handle, "MeshId", "updated"))
	fmt.println("REPORTED_REGRESSIONS_PASSED")
}
