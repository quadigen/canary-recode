#+build !js
package main

import packages "../src/engine/packages"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"

main :: proc() {
	v := vm.New()
	env: runtime.Environment
	view: renderer.RendererObject
	runtime.Environment_Init(&env, &v, &view, .Editor)
	defer {
		vm.Close(&v)
		runtime.Environment_Destroy(&env)
	}
	assert(len(os.args) > 1)
	assert(packages.Load_Internal_Modules_From_Directory(&env.packages, os.args[1]))
	ok, err := vm.RunInternal(
		&v,
		`
local service = game:GetService("LuauService")
local definitions = service:GetApiDefinitions()
assert(definitions:find("declare extern type ModuleScript", 1, true))
local function check(source, count)
	local results = service:TypeCheck(source)
	assert(type(results) == "table", "API definitions failed to load")
	local errors = {}
	for _, diagnostic in ipairs(results) do
		if diagnostic.Kind ~= "Lint warning" then
			table.insert(errors, diagnostic.Message)
		end
	end
	assert(#errors == count, ("Expected %d errors, got %d for %s: %s"):format(count, #errors, source, table.concat(errors, "; ")))
end
check([=[local m: ModuleScript = Instance.new("ModuleScript")
local source: string = m.Source
local n: string = m.Name]=], 0)
check([=[local m = Instance.new("ModuleScript")
local source: number = m.Source]=], 1)
check([=[local m: ModuleScript = Instance.new("Part")]=], 1)
check([=[local part = Instance.new("Part2D")
local position: UDim2 = part.Position]=], 0)
check([=[local compute: GPUCompute = Instance.new("GPUCompute")
local body: CharacterPhysicsSolver = Instance.new("CharacterPhysicsSolver")]=], 0)
check([=[local players: Players = game:GetService("Players")
local list: {Player} = players:GetPlayers()]=], 0)
check([=[local players = game:GetService("Players")
local n: number = players:GetPlayers()]=], 1)
check([=[local module: ModuleScript? = workspace:FindFirstChildOfClass("ModuleScript")]=], 0)
check([=[local part: Part = workspace:FindFirstChildOfClass("ModuleScript")]=], 1)
check([=[local v: Vector3 = Vector3.new(1, 2, 3)
local x: number = v.X]=], 0)
check([=[local t: TextBox = Instance.new("TextBox")
local smooth: boolean = t.SmoothCaret]=], 0)
check([=[local storage: ReplicatedStorage = game.ReplicatedStorage
local material: Enum.Material = Enum.Material.SmoothPlastic]=], 0)
check([=[local material: Enum.Material = Enum.PartType.Block]=], 1)
local CodeEditor = require("@internal/code_editor")
local function candidate(source, member, expected)
	local editor = setmetatable({TextBox = {Text = source, CursorPosition = #source + 1}}, CodeEditor)
	local chain = editor:chainAtCursor(true)
	assert(chain, "no completion chain: " .. source)
	for _, entry in ipairs(editor:collectCandidates(chain)) do
		if entry.name == member then
			assert(not expected or entry.detail == expected, member .. " has type " .. tostring(entry.detail))
			return
		end
	end
	error("missing completion " .. member .. " for " .. source)
end
candidate("local m: Module", "ModuleScript")
candidate("local m: ModuleScript\nm.", "Source", "string")
candidate("local m: ModuleScript\nm.", "Name", "string")
candidate("local m = Instance.new('ModuleScript')\nm.", "Source", "string")
candidate("local p = Instance.new('Part2D')\np.", "Position", "UDim2")
candidate("local function f(m: ModuleScript)\n m.", "Source", "string")
candidate("local p = game:GetService('Players')\np.", "LocalPlayer", "Player?")
candidate("local v: Vector3\nv.", "X", "number")
candidate("local t: TextBox\nt.", "SmoothCaret", "boolean")
candidate("local c: GPUCompute\nc:", "GetCapabilities")
print("API completions verified")
`,
		"luau_engine_api_smoke",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("Luau engine API test failed")
	}
	fmt.println("LUAU_ENGINE_API_SMOKE_PASSED")
}
