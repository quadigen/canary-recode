package main

import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("PlayerGui smoke failed")
	}
}

alpha_at :: proc(surface: ^kineffi.KineSkiaSurface, x, y: i32) -> u8 {
	r, g, b, a: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, x, y, &r, &g, &b, &a)
	return a
}

main :: proc() {
	script_vm := vm.New()
	view: renderer.RendererObject
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &view)
	engine_runtime.Environment_Set_Mode(&environment, .Standalone)
	defer {
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
	}

	run_script(&script_vm, `
local starter = game:GetService("StarterGui")
local hud = Instance.new("ScreenGui", starter)
hud.Name = "Hud"
hud.ResetOnSpawn = false
local frame = Instance.new("Frame", hud)
frame.Name = "Panel"
frame.Size = UDim2.fromOffset(25, 25)
frame.Active = true
local script = Instance.new("LocalScript", hud)
script.Source = [[
	_G.hudRuns = (_G.hudRuns or 0) + 1
	assert(script.Parent.Parent == game:GetService("Players").LocalPlayer.PlayerGui)
]]
local reset = Instance.new("ScreenGui", starter)
reset.Name = "ResetHud"
local skip = Instance.new("ScreenGui", starter)
skip.Name = "Unclonable"
skip.Archivable = false
`, "prepare_starter_gui")

	players := cast(^services.Players)services.Ensure_Service(&environment.services, "Players")
	local_player := services.Players_Add(players, script_vm.L, 1, "Local")
	players.local_player = local_player
	_ = services.Players_Add(players, script_vm.L, 2, "Other")
	run_script(&script_vm, `
local players = game:GetService("Players")
local player = players.LocalPlayer
gui = player.PlayerGui
local other = players.Other.PlayerGui
assert(gui == player:FindFirstChild("PlayerGui") and gui.Parent == player)
assert(gui.Hud ~= game.StarterGui.Hud and gui.Hud ~= other.Hud)
assert(gui.Hud.Panel ~= game.StarterGui.Hud.Panel and gui.Unclonable == nil)
assert(gui.Hud.ResetOnSpawn == false and gui.ResetHud.ResetOnSpawn)
gui.Hud.Panel.Position = UDim2.fromOffset(40, 0)
other.Hud.Panel.Position = UDim2.fromOffset(80, 0)
assert(game.StarterGui.Hud.Panel.Position.X.Offset == 0)
resetBeforeSpawn = gui.ResetHud
`, "verify_independent_clones")
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	run_script(&script_vm, `assert(_G.hudRuns == 1)`, "verify_only_local_script")

	surface := kineffi.Kine_Skia_Surface_Create(120, 50)
	assert(surface != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(surface)
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
	engine_runtime.Environment_Render_Overlay(&environment, &script_vm, surface, 120, 50, 1.0 / 60.0)
	kineffi.Kine_Skia_Surface_Flush(surface)
	assert(alpha_at(surface, 5, 5) == 0, "template GUI rendered")
	assert(alpha_at(surface, 45, 5) == 255, "local PlayerGui did not render")
	assert(alpha_at(surface, 85, 5) == 0, "another player's GUI rendered")
	assert(classes.GuiObject_find_topmost(&environment.classes, 45, 5) != nil)
	assert(classes.GuiObject_find_topmost(&environment.classes, 5, 5) == nil)
	assert(classes.GuiObject_find_topmost(&environment.classes, 85, 5) == nil)

	for _ in 0 ..< 2 {
		character, ok := classes.Push_New(&environment.classes, &script_vm, "CharacterModel", false)
		assert(ok)
		services.Player_Set_Character(local_player, script_vm.L, cast(^classes.CharacterModel)character)
		vm.Pop(script_vm.L)
	}
	run_script(&script_vm, `
assert(gui == game:GetService("Players").LocalPlayer.PlayerGui)
assert(gui.ResetHud ~= resetBeforeSpawn)
assert(gui.Hud.Panel.Position.X.Offset == 40)

local part = Instance.new("Part")
assert(part.CanTouch)
part.CanTouch = false
assert(not part:Clone().CanTouch)
assert(Instance.new("Script"):IsA("BaseScript"))
assert(Instance.new("LocalScript"):IsA("BaseScript"))
assert(not Instance.new("ModuleScript"):IsA("BaseScript"))
`, "verify_respawn_and_building_apis")

	fmt.println("PLAYER_GUI_SMOKE_PASSED")
}
