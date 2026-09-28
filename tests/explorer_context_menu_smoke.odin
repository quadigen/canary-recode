package main

import "core:fmt"
import kineffi "../src/engine/bindings"
import engine_runtime "../src/engine/runtime"
import renderer "../src/engine/renderer"
import sandbox "../src/sandboxed"
import vm "../src/engine/vm"
import sdl3 "vendor:sdl3"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	renderer_object: renderer.RendererObject

	sandbox.init(&script_vm, &environment, &renderer_object)
	defer sandbox.shutdown()
	defer vm.Close(&script_vm)

	width: i32 = 800
	height: i32 = 600
	surface := kineffi.Kine_Skia_Surface_Create(width, height)
	assert(surface != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(surface)

	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 255)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, width, height, 1.0 / 60.0)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, width, height, 1.0 / 60.0)

	// Sanity: the Explorer tree is present and has rows to hit.
	rows, rows_err := vm.Run(&script_vm, `
local explorer = game.CoreGui:FindFirstChild("Studio"):FindFirstChild("Explorer")
assert(explorer ~= nil, "Explorer window missing")
local rows = 0
for _, child in ipairs(explorer:GetDescendants()) do
	if child:IsA("TextButton") then
		rows += 1
		local pos = child.AbsolutePosition
		local size = child.AbsoluteSize
		if rows <= 6 then
			print(string.format("ROWPOS %d %.0f %.0f %.0f %.0f %s", rows, pos.X, pos.Y, size.X, size.Y, child.Name))
		end
	end
end
print("ROWS=" .. rows)
assert(rows > 0, "no explorer rows to right-click")

local Selection = game:GetService("Selection")
Selection:Set({})
`, "context_menu_rows")

	if !rows {
		fmt.eprintln(rows_err)
		delete(rows_err)
		panic("explorer rows probe failed")
	}

	// Right-click a visible Explorer row, exactly as a user would.
	// Control: a left click at the same coordinates must select a row.
	leftClick: sdl3.Event
	leftClick.type = .MOUSE_BUTTON_DOWN
	leftClick.button.button = sdl3.BUTTON_LEFT
	leftClick.button.x = 680
	leftClick.button.y = 167
	engine_runtime.Environment_SetEvent(&environment, &script_vm, leftClick)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, width, height, 1.0 / 60.0)

	// Selection happens on button UP via Activated, so send the release too.
	leftUp: sdl3.Event
	leftUp.type = .MOUSE_BUTTON_UP
	leftUp.button.button = sdl3.BUTTON_LEFT
	leftUp.button.x = 680
	leftUp.button.y = 167
	engine_runtime.Environment_SetEvent(&environment, &script_vm, leftUp)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, width, height, 1.0 / 60.0)

	control, control_err := vm.Run(&script_vm, `
local Selection = game:GetService("Selection")
print("SELECTED_AFTER_LEFT_CLICK", #Selection:Get())
assert(#Selection:Get() == 1, "left click control failed")
`, "context_menu_control")

	if !control {
		fmt.eprintln(control_err)
		delete(control_err)
		panic("left click control failed")
	}

	// Reset, then right-click the same spot.
	vm.Run(&script_vm, `game:GetService("Selection"):Set({})`, "context_menu_reset")

	rightClick: sdl3.Event
	rightClick.type = .MOUSE_BUTTON_DOWN
	rightClick.button.button = sdl3.BUTTON_RIGHT
	rightClick.button.x = 680
	rightClick.button.y = 167
	engine_runtime.Environment_SetEvent(&environment, &script_vm, rightClick)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, width, height, 1.0 / 60.0)
	engine_runtime.Environment_Render_Overlay(&environment, &script_vm, surface, width, height, 1.0 / 60.0)

	menu, menu_err := vm.Run(&script_vm, `
// Did the row handler see the right-click at all? It selects on right-click.
local Selection = game:GetService("Selection")
local selected = #Selection:Get()
print("SELECTED_AFTER_RIGHT_CLICK", selected)
assert(selected == 1, "row handler did not run for right-click")
`, "context_menu_handler")

	if !menu {
		fmt.eprintln(menu_err)
		delete(menu_err)
		panic("row handler did not run for right-click")
	}

	items, items_err := vm.Run(&script_vm, `
// Walk every ScreenGui in CoreGui; do not assume the overlay's exact name.
local function scan(root, wanted, total)
	if root == nil then
		return total
	end
	if root:IsA("TextLabel") then
		local text = root.Text
		if wanted[text] ~= nil then
			wanted[text] = true
			total = total + 1
		end
	end
	for _, child in ipairs(root:GetChildren()) do
		total = scan(child, wanted, total)
	end
	return total
end

local wanted = { Rename = false, Duplicate = false, Delete = false, Copy = false, Paste = false }
local total = 0
for _, gui in ipairs(game.CoreGui:GetChildren()) do
	total = scan(gui, wanted, total)
end

for name, found in pairs(wanted) do
	print("ITEM", name, found)
end
print("TOTAL_ITEMS", total)
assert(total == 5, "context menu did not render all 5 items, saw " .. tostring(total))
`, "context_menu_items")

	if !items {
		fmt.eprintln(items_err)
		delete(items_err)
		panic("context menu did not appear on right-click")
	}

	_ = renderer_object
	fmt.println("EXPLORER_CONTEXT_MENU_SMOKE_PASSED")
}
