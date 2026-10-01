package main

import "core:fmt"
import "core:strings"
import engine_runtime "../src/engine/runtime"
import renderer "../src/engine/renderer"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "vendor:sdl3"

STEP_DT :: f32(1.0 / 60.0)
VIEWPORT_WIDTH :: i32(800)
VIEWPORT_HEIGHT :: i32(600)

EVENT_NAMES := []string{
	"Button1Down",
	"Button1Up",
	"Button2Down",
	"Button2Up",
	"Idle",
	"KeyDown",
	"KeyUp",
	"Move",
	"WheelBackward",
	"WheelForward",
}

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic(name)
	}
}

run_script_internal :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic(name)
	}
}

expect_script_failure :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if ok {
		delete(err)
		panic("expected this script to be denied, but it ran")
	}
	delete(err)
}

assert_counts :: proc(script_vm: ^vm.VM, expected: string, name: string) {
	source := strings.concatenate({
		"local c = counts\n",
		expected,
		"\nfor _, n in ipairs(eventNames) do c[n] = 0 end",
	})
	defer delete(source)
	run_script(script_vm, source, name)
}

mouse_pointer :: proc(environment: ^engine_runtime.Environment) -> ^services.Mouse {
	descriptor := services.Find_Service(&environment.services, "UserInputService")
	assert(descriptor != nil && descriptor.object != nil)
	mouse := services.User_Input_Service_Mouse(cast(^services.UserInputService)descriptor.object)
	assert(mouse != nil)
	return mouse
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	view: renderer.RendererObject
	engine_runtime.Environment_Init(&environment, &script_vm, &view)

	// The desktop and web frame loops publish the viewport rect before the
	// engine step, and the mouse cannot build a camera ray without it.
	assert(!view.HasViewportRect, "a fresh renderer must start without a viewport rect")

	{
		mouse := mouse_pointer(&environment)
		services.Mouse_Begin_Frame(mouse, script_vm.L, 1.0 / 60.0)
		assert(mouse.view_size_x == 0, "an unset viewport rect must report a zero view size")
		assert(mouse.target == nil, "an unset viewport rect must leave the target nil")
	}

	view.HasViewportRect = true
	view.ViewportRect = {0, 0, VIEWPORT_WIDTH, VIEWPORT_HEIGHT}

	players := cast(^services.Players)services.Ensure_Service(&environment.services, "Players")
	assert(players != nil)
	player := services.Players_Add(players, script_vm.L, 1, "Solo")
	assert(player != nil)
	players.local_player = player

	run_script(&script_vm, `
local player = game:GetService("Players").LocalPlayer
assert(player ~= nil, "no local player")

local workspace = game:GetService("Workspace")
workspace.CurrentCamera.CFrame = CFrame.new(0, 0, 0)

local mouse = player:GetMouse()
assert(mouse ~= nil, "LocalPlayer:GetMouse returned nil")
assert(mouse.ClassName == "Mouse", "wrong ClassName: " .. tostring(mouse.ClassName))
assert(mouse:IsA("Instance"), "Mouse must inherit from Instance")
assert(mouse:IsA("Mouse"), "Mouse must be a Mouse")
assert(player:GetMouse() == mouse, "LocalPlayer:GetMouse is not stable")

local created_ok = pcall(function() return Instance.new("Mouse") end)
assert(not created_ok, "Mouse must not be creatable")

eventNames = {
	"Button1Down", "Button1Up", "Button2Down", "Button2Up", "Idle",
	"KeyDown", "KeyUp", "Move", "WheelBackward", "WheelForward",
}
counts = {}
for _, name in ipairs(eventNames) do
	local signal = mouse[name]
	assert(signal ~= nil, "missing event " .. name)
	counts[name] = 0
	signal:Connect(function(...)
		local argc = select("#", ...)
		if name == "KeyDown" or name == "KeyUp" then
			assert(argc == 1, name .. " must take one argument")
			assert(type((...)) == "string", name .. " must pass a string")
		else
			assert(argc == 0, name .. " must take no arguments")
		end
		counts[name] += 1
	end)
end

mouse.Icon = "rbxasset://cursor/ArrowCursor.png"
assert(mouse.Icon == "rbxasset://cursor/ArrowCursor.png", "Icon round trip failed")
assert(mouse.IconContent ~= nil, "IconContent must follow Icon")
assert(mouse.IconContent == Content.fromUri("rbxasset://cursor/ArrowCursor.png"), "IconContent must mirror the Icon uri")

mouse.IconContent = Content.fromUri("rbxasset://cursor/IBeamCursor.png")
assert(mouse.IconContent == Content.fromUri("rbxasset://cursor/IBeamCursor.png"), "IconContent round trip failed")
assert(mouse.Icon == "rbxasset://cursor/IBeamCursor.png", "Icon must follow IconContent")

mouse.TargetFilter = nil
assert(mouse.TargetFilter == nil, "TargetFilter should start nil")
`, "mouse_setup")

	expect_script_failure(
		&script_vm,
		`return game:GetService("UserInputService"):GetMouse()`,
		"mouse_get_mouse_must_need_internal_access",
	)

	run_script_internal(&script_vm, `
local mouse = game:GetService("UserInputService"):GetMouse()
assert(mouse ~= nil, "internal GetMouse returned nil")
assert(mouse == game:GetService("Players").LocalPlayer:GetMouse(), "the two accessors must share one Mouse")
`, "mouse_get_mouse_internal")

	mouse := mouse_pointer(&environment)

	run_script(&script_vm, `
local mouse = game:GetService("Players").LocalPlayer:GetMouse()
assert(mouse.ViewSizeX == 0 and mouse.ViewSizeY == 0, "no frame has run yet")
assert(mouse.X == 0 and mouse.Y == 0, "the pointer has not moved yet")
assert(mouse.Target == nil and mouse.target == nil, "no target before the first frame")
`, "mouse_initial_state")

	motion: sdl3.Event
	motion.type = .MOUSE_MOTION
	motion.motion.x = 400
	motion.motion.y = 300
	motion.motion.xrel = 10
	motion.motion.yrel = 5
	engine_runtime.Environment_SetEvent(&environment, &script_vm, motion)

	engine_runtime.Environment_Update_Step(&environment, &script_vm, STEP_DT)

	run_script(&script_vm, `
local mouse = game:GetService("Players").LocalPlayer:GetMouse()
assert(counts.Move == 1, "Move did not fire exactly once")
assert(mouse.X == 400 and mouse.Y == 300, "pointer position did not track the event")
assert(mouse.ViewSizeX == 800 and mouse.ViewSizeY == 600, "view size did not come from the viewport")
assert(mouse.UnitRay.Origin == Vector3.zero, "camera is still at the origin")
assert(mouse.UnitRay.Direction == Vector3.new(0, 0, -1), "centre of the viewport must look down -Z")
assert(mouse.Origin.Position == Vector3.zero, "Origin must mirror UnitRay.Origin")
assert(mouse.Target == nil, "nothing is in the workspace yet")
assert(mouse.TargetSurface == Enum.NormalId.Front, "a miss reports the default surface")
`, "mouse_motion")

	run_script(&script_vm, `
local workspace = game:GetService("Workspace")
workspace.CurrentCamera.CFrame = CFrame.new(0, 0, 20)

target = Instance.new("Part", workspace)
target.Name = "Target"
target.Size = Vector3.new(8, 8, 8)
target.CFrame = CFrame.new(0, 0, 0)
target.Anchored = true
target.CanCollide = true
target.CanQuery = true
`, "mouse_scene_setup")

	engine_runtime.Environment_Update_Step(&environment, &script_vm, STEP_DT)

	run_script(&script_vm, `
assert(game:GetService("Physics").BodyCount == 1, "the part must have a physics body")

local direct = game:GetService("Workspace"):Raycast(Vector3.new(0, 0, 20), Vector3.new(0, 0, -1000))
assert(direct ~= nil, "the workspace raycast itself must hit the part")
assert(direct.Instance == target, "the workspace raycast must return the part")
assert(math.abs(direct.Position.Z - 4) < 0.001, "workspace raycast hit position")

local mouse = game:GetService("Players").LocalPlayer:GetMouse()
assert(mouse.UnitRay.Origin == Vector3.new(0, 0, 20), "the ray must start at the camera")
assert(mouse.Target ~= nil, "the ray did not hit the part")
assert(mouse.Target == target, "Target must be the part under the pointer")
assert(mouse.target == target, "the lowercase alias must work")
assert(mouse.TargetSurface == Enum.NormalId.Back, "a +Z surface is Back")
assert(mouse.Hit.Position == Vector3.new(0, 0, 4), "hit position: " .. tostring(mouse.Hit.Position))
assert(mouse.hit == mouse.Hit, "the lowercase alias must work")
assert(mouse.UnitRay.Direction == Vector3.new(0, 0, -1), "the pointer is still centred")
`, "mouse_hit")

	run_script(&script_vm, `
local folder = Instance.new("Folder")
folder.Name = "Filtered"
folder.Parent = target.Parent
target.Parent = folder

local mouse = game:GetService("Players").LocalPlayer:GetMouse()
mouse.TargetFilter = folder
assert(mouse.TargetFilter == folder, "TargetFilter round trip failed")
`, "mouse_target_filter_setup")

	engine_runtime.Environment_Update_Step(&environment, &script_vm, STEP_DT)

	run_script(&script_vm, `
local mouse = game:GetService("Players").LocalPlayer:GetMouse()
assert(mouse.Target == nil, "TargetFilter must exclude descendants")
assert(mouse.Hit.Position == Vector3.new(0, 0, -980), "a filtered miss falls back to the far point: " .. tostring(mouse.Hit.Position))
`, "mouse_target_filter")

	run_script(&script_vm, `
local mouse = game:GetService("Players").LocalPlayer:GetMouse()
mouse.TargetFilter = nil
assert(mouse.TargetFilter == nil, "clearing TargetFilter failed")
`, "mouse_target_filter_clear")

	engine_runtime.Environment_Update_Step(&environment, &script_vm, STEP_DT)

	button_one_down: sdl3.Event
	button_one_down.type = .MOUSE_BUTTON_DOWN
	button_one_down.button.button = sdl3.BUTTON_LEFT
	button_one_down.button.x = 400
	button_one_down.button.y = 300
	engine_runtime.Environment_SetEvent(&environment, &script_vm, button_one_down)

	button_one_up: sdl3.Event
	button_one_up.type = .MOUSE_BUTTON_UP
	button_one_up.button.button = sdl3.BUTTON_LEFT
	button_one_up.button.x = 401
	button_one_up.button.y = 301
	engine_runtime.Environment_SetEvent(&environment, &script_vm, button_one_up)

	button_two_down: sdl3.Event
	button_two_down.type = .MOUSE_BUTTON_DOWN
	button_two_down.button.button = sdl3.BUTTON_RIGHT
	button_two_down.button.x = 402
	button_two_down.button.y = 302
	engine_runtime.Environment_SetEvent(&environment, &script_vm, button_two_down)

	button_two_up: sdl3.Event
	button_two_up.type = .MOUSE_BUTTON_UP
	button_two_up.button.button = sdl3.BUTTON_RIGHT
	button_two_up.button.x = 403
	button_two_up.button.y = 303
	engine_runtime.Environment_SetEvent(&environment, &script_vm, button_two_up)

	assert_counts(&script_vm, `
assert(counts.Button1Down == 1, "Button1Down did not fire")
assert(counts.Button1Up == 1, "Button1Up did not fire")
assert(counts.Button2Down == 1, "Button2Down did not fire")
assert(counts.Button2Up == 1, "Button2Up did not fire")
assert(counts.Move == 1, "buttons must not fire Move")
`, "mouse_buttons")

	run_script(&script_vm, `
local mouse = game:GetService("Players").LocalPlayer:GetMouse()
assert(mouse.X == 403 and mouse.Y == 303, "buttons must move the pointer too")
`, "mouse_button_position")

	wheel_up: sdl3.Event
	wheel_up.type = .MOUSE_WHEEL
	wheel_up.wheel.x = 0
	wheel_up.wheel.y = 1
	wheel_up.wheel.mouse_x = 403
	wheel_up.wheel.mouse_y = 303
	engine_runtime.Environment_SetEvent(&environment, &script_vm, wheel_up)

	wheel_down: sdl3.Event
	wheel_down.type = .MOUSE_WHEEL
	wheel_down.wheel.x = 0
	wheel_down.wheel.y = -1
	wheel_down.wheel.mouse_x = 403
	wheel_down.wheel.mouse_y = 303
	engine_runtime.Environment_SetEvent(&environment, &script_vm, wheel_down)

	assert_counts(&script_vm, `
assert(counts.WheelForward == 1, "WheelForward did not fire")
assert(counts.WheelBackward == 1, "WheelBackward did not fire")
`, "mouse_wheel")

	key_down: sdl3.Event
	key_down.type = .KEY_DOWN
	key_down.key.scancode = .A
	engine_runtime.Environment_SetEvent(&environment, &script_vm, key_down)

	key_up: sdl3.Event
	key_up.type = .KEY_UP
	key_up.key.scancode = .A
	engine_runtime.Environment_SetEvent(&environment, &script_vm, key_up)

	assert_counts(&script_vm, `
assert(counts.KeyDown == 1, "KeyDown did not fire")
assert(counts.KeyUp == 1, "KeyUp did not fire")
`, "mouse_keys")

	run_script(&script_vm, `
seen = {}
game:GetService("Players").LocalPlayer:GetMouse().KeyDown:Connect(function(key) table.insert(seen, key) end)
`, "mouse_key_listener")

	shift_down: sdl3.Event
	shift_down.type = .KEY_DOWN
	shift_down.key.scancode = .LSHIFT
	engine_runtime.Environment_SetEvent(&environment, &script_vm, shift_down)

	run_script(&script_vm, `
assert(seen[1] == "LeftShift", "KeyDown must pass the enum item name: " .. tostring(seen[1]))
`, "mouse_key_name")

	services.Mouse_Begin_Frame(mouse, script_vm.L, 1.5)

	assert_counts(&script_vm, `
assert(counts.Idle == 1, "Idle did not fire after an idle second")
assert(counts.KeyDown == 1, "the second KeyDown did not fire")
assert(counts.Move == 0, "an idle frame must not report Move")
`, "mouse_idle")

	services.Mouse_Begin_Frame(mouse, script_vm.L, 0.25)

	assert_counts(&script_vm, `
assert(counts.Idle == 0, "Idle must not fire again before another second")
`, "mouse_idle_hold")

	services.Mouse_Begin_Frame(mouse, script_vm.L, 1.5)

	assert_counts(&script_vm, `
assert(counts.Idle == 1, "Idle did not fire on the next interval")
`, "mouse_idle_second")

	run_script(&script_vm, `
local reflection = game:GetService("ReflectionService")
local class = reflection:GetClass("Mouse")
assert(class ~= nil, "ReflectionService must know the Mouse class")
assert(class.Name == "Mouse", "wrong reflected name: " .. tostring(class.Name))
assert(class.Superclass == "Instance", "wrong reflected superclass: " .. tostring(class.Superclass))
assert(class.Permits.New == nil, "Mouse must not offer a New permit")

local property_names = {}
for _, property in reflection:GetPropertiesOfClass("Mouse") do
	property_names[property.Name] = true
end
for _, name in ipairs({
	"Hit", "Icon", "IconContent", "Origin", "Target", "TargetFilter",
	"TargetSurface", "UnitRay", "ViewSizeX", "ViewSizeY", "X", "Y",
}) do
	assert(property_names[name], "Mouse must reflect the property " .. name)
end

local event_names = {}
for _, event in reflection:GetEventsOfClass("Mouse") do
	event_names[event.Name] = true
end
for _, name in ipairs({
	"Button1Down", "Button1Up", "Button2Down", "Button2Up", "Idle",
	"KeyDown", "KeyUp", "Move", "WheelBackward", "WheelForward",
}) do
	assert(event_names[name], "Mouse must reflect the event " .. name)
end
`, "mouse_reflection")

	run_script(&script_vm, `
local reflection = game:GetService("ReflectionService")

local function find_method(class_name, method_name)
	for _, method in reflection:GetMethodsOfClass(class_name) do
		if method.Name == method_name then return method end
	end
	return nil
end

local get_mouse = find_method("UserInputService", "GetMouse")
assert(get_mouse ~= nil, "UserInputService must reflect GetMouse")
assert(get_mouse.Permits.Call == nil, "an unprivileged script must not see a Call permit for GetMouse")

local player_mouse = find_method("Player", "GetMouse")
assert(player_mouse ~= nil, "Player must reflect GetMouse")
assert(player_mouse.Permits.Call ~= nil, "Player:GetMouse must be callable without a capability")
`, "mouse_reflection_security")

	run_script_internal(&script_vm, `
local get_mouse
for _, method in game:GetService("ReflectionService"):GetMethodsOfClass("UserInputService") do
	if method.Name == "GetMouse" then get_mouse = method end
end
assert(get_mouse ~= nil, "UserInputService must reflect GetMouse")
assert(get_mouse.Permits.Call ~= nil, "an internal script must see the Call permit for GetMouse")
`, "mouse_reflection_security_internal")

	run_script(&script_vm, `
local mouse = game:GetService("Players").LocalPlayer:GetMouse()
mouse.Icon = ""
assert(mouse.Icon == "", "clearing Icon failed")
assert(mouse.IconContent == Content.fromUri(""), "clearing Icon must clear IconContent")
`, "mouse_icon_clear")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("MOUSE_SMOKE_PASSED")
}
