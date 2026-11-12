package main

import kineffi "../src/engine/bindings"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import sdl3 "../src/engine/platform"
import "core:fmt"

expect_pixel :: proc(surface: ^kineffi.KineSkiaSurface, x, y: i32, red, opaque: bool) {
	r, g, b, a: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, x, y, &r, &g, &b, &a)
	is_red := r == 255 && g == 0 && b == 0
	assert(is_red == red, fmt.tprintf("pixel %d,%d red=%v want %v", x, y, is_red, red))
	assert(
		(a == 255) == opaque,
		fmt.tprintf("pixel %d,%d alpha=%d want opaque=%v", x, y, a, opaque),
	)
}

main :: proc() {
	script_vm := vm.New()
	renderer_object: renderer.RendererObject
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)
	defer {
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
	}


	ok, err := vm.Run(
		&script_vm,
		`
local screen = Instance.new("ScreenGui", game.StarterGui)
screen.Name = "Hud"
screen.Size = Vector2.new(100, 80)
screen.RenderOffset = Vector2.new(40, 30)

group = Instance.new("CanvasGroup", screen)
group.Size = UDim2.fromScale(1, 1)
group.BackgroundTransparency = 1
local frame = Instance.new("Frame", group)
frame.Position = UDim2.fromOffset(-50, -50)
frame.Size = UDim2.fromOffset(300, 300)
frame.BackgroundColor3 = Color3.new(1, 0, 0)
frame.BackgroundTransparency = 0
`,
		"screen_gui_clip_setup",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("ScreenGui clip setup failed")
	}

	surface := kineffi.Kine_Skia_Surface_Create(300, 300)
	if surface == nil {panic("Skia surface creation failed")}
	defer kineffi.Kine_Skia_Surface_Destroy(surface)
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)

	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, 300, 300, 1.0 / 60.0)
	engine_runtime.Environment_Render_Overlay(
		&environment,
		&script_vm,
		surface,
		300,
		300,
		1.0 / 60.0,
	)
	kineffi.Kine_Skia_Surface_Flush(surface)

	expect_pixel(surface, 60, 50, true, true)

	expect_pixel(surface, 30, 50, false, false)
	expect_pixel(surface, 50, 20, false, false)
	expect_pixel(surface, 150, 50, false, false)
	expect_pixel(surface, 50, 120, false, false)
	expect_pixel(surface, 200, 200, false, false)

	ok, err = vm.Run(&script_vm, `
group.GroupTransparency = 0.5
assert(group:Clone().GroupTransparency == 0.5)
assert(group:ContainsPoint(60, 50))
assert(not group:ContainsPoint(30, 50))
assert(group.Frame:ContainsPoint(60, 50))
`, "canvas_group_transparency")
	assert(ok, err)
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
	engine_runtime.Environment_Render_Overlay(&environment, &script_vm, surface, 300, 300, 1.0 / 60.0)
	kineffi.Kine_Skia_Surface_Flush(surface)
	expect_pixel(surface, 60, 50, true, false)
	r, g, b, a: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, 60, 50, &r, &g, &b, &a)
	assert(a == 127 || a == 128)

	ok, err = vm.Run(&script_vm, `
local screen = Instance.new("ScreenGui", game.StarterGui)
local moving = Instance.new("Frame", screen)
local destination = Instance.new("Folder", screen)
local moves = 0
moving.AncestryChanged:Connect(function(child, parent)
	assert(child == moving and parent == destination)
	moves += 1
end)
moving.Parent = destination
assert(moves == 1)
assert(moving.AbsoluteSize.X == 100)
local button = Instance.new("TextButton", screen)
button.Position = UDim2.fromOffset(160, 10)
button.Size = UDim2.fromOffset(100, 40)
button.MouseButton1Click:Connect(function() clickedUnderHover = true end)
local preview = Instance.new("ViewportFrame", screen)
preview.Position, preview.Size = button.Position, button.Size
assert(not preview.InputSink)
local hover = Instance.new("Frame", screen)
hover.Position, hover.Size = button.Position, button.Size
hover.BackgroundTransparency = 1
hover.MouseEnter:Connect(function() enteredPassive = true end)
hover.MouseLeave:Connect(function() leftPassive = true end)
local calls = 0
local changed = hover.Changed:Connect(function()
	calls += 1
	hover.Visible = false
end)
hover.Visible = false
assert(calls == 1)
changed:Disconnect()
hover.Visible = true
`, "passive hover setup")
	assert(ok, err)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, 300, 300, 1.0 / 60.0)
	engine_runtime.Environment_Render_Overlay(&environment, &script_vm, surface, 300, 300, 1.0 / 60.0)
	event: sdl3.Event
	event.type = .MOUSE_MOTION
	event.motion.x, event.motion.y = 180, 20
	engine_runtime.Environment_SetEvent(&environment, &script_vm, event)
	event.type = .MOUSE_BUTTON_DOWN
	event.button.x, event.button.y = 180, 20
	event.button.button = sdl3.BUTTON_LEFT
	engine_runtime.Environment_SetEvent(&environment, &script_vm, event)
	event.type = .MOUSE_BUTTON_UP
	engine_runtime.Environment_SetEvent(&environment, &script_vm, event)
	event.type = .MOUSE_MOTION
	event.motion.x, event.motion.y = 290, 200
	engine_runtime.Environment_SetEvent(&environment, &script_vm, event)
	ok, err = vm.Run(&script_vm, `assert(enteredPassive and leftPassive and clickedUnderHover)`, "passive hover verify")
	assert(ok, err)

	ok, err = vm.Run(&script_vm, `
local part = Instance.new("Part", workspace)
local attachment = Instance.new("Attachment", part)
local cached = {[part] = true, [attachment] = true}
local order = {}
local watcher = workspace.DescendantRemoving:Connect(function(removed)
	assert(removed == attachment or removed == part)
	cached[removed] = nil
end)
part.Destroying:Connect(function()
	assert(part.Parent == workspace and attachment.Parent == part)
	table.insert(order, "destroying")
end)
part.AncestryChanged:Connect(function(child, parent)
	assert(child == part and parent == nil)
	table.insert(order, "removed")
end)
local destroy = part.Destroy
part:Destroy()
part:Destroy()
destroy(part)
part.Destroy(part)
watcher:Disconnect()
assert(next(cached) == nil)
assert(table.concat(order, ",") == "destroying,removed")
assert(part.Parent == nil and attachment.Parent == nil)
assert(not pcall(function() part.Parent = workspace end))
`, "destroyed instance cleanup")
	assert(ok, err)

	ok, err = vm.Run(&script_vm, `
local screen = Instance.new("ScreenGui", game.StarterGui)
label = Instance.new("TextLabel", screen)
button = Instance.new("TextButton", screen)
for _, object in {label, button} do
	object.Size = UDim2.fromOffset(100, 60)
	object.TextSize = 16
	object.Text = "Wide text"
end
local ribbon = Instance.new("ScrollingFrame", screen)
ribbon.Size = UDim2.fromOffset(120, 0)
ribbon.AutomaticSize = Enum.AutomaticSize.Y
local list = Instance.new("UIListLayout", ribbon)
list.FillDirection = Enum.FillDirection.Horizontal
category = Instance.new("TextButton", ribbon)
category.Size = UDim2.fromOffset(0, 0)
category.AutomaticSize = Enum.AutomaticSize.XY
category.Text = "Block"
category.TextSize = 19
local titleArea = Instance.new("Frame", screen)
titleArea.Position = UDim2.fromOffset(145, 190)
titleArea.Size = UDim2.fromOffset(130, 35)
titleArea.BackgroundTransparency = 1
titleArea.ClipsDescendants = true
local title = Instance.new("TextLabel", titleArea)
title.Size = UDim2.fromOffset(16, 35)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.new(1, 1, 1)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Object Menu"
title.TextSize = 19
`, "text_cache_setup")
	assert(ok, err)
	for _ in 0 ..< 2 {
		engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, 300, 300, 1.0 / 60.0)
		engine_runtime.Environment_Render_Overlay(&environment, &script_vm, surface, 300, 300, 1.0 / 60.0)
	}
	ok, err = vm.Run(&script_vm, `
labelWidth = label.TextBounds.X
buttonWidth = button.TextBounds.X
assert(labelWidth > 0 and buttonWidth > 0)
assert(category.AbsoluteSize.Y > 0 and category.Parent.AbsoluteSize.Y >= category.AbsoluteSize.Y,
	tostring(category.AbsoluteSize) .. " inside " .. tostring(category.Parent.AbsoluteSize))
label.Text = "i"
button.Text = "i"
`, "text_cache_update")
	assert(ok, err)
	title_pixels := 0
	for y in 193 ..< 221 {
		for x in 165 ..< 274 {
			kineffi.Kine_Skia_Surface_GetPixel(surface, i32(x), i32(y), &r, &g, &b, &a)
			if r > 150 && g > 150 && b > 150 {title_pixels += 1}
		}
	}
	assert(title_pixels > 30, "single-line title should extend past its own width")
	engine_runtime.Environment_Render_Overlay(&environment, &script_vm, surface, 300, 300, 1.0 / 60.0)
	ok, err = vm.Run(&script_vm, `
assert(label.TextBounds.X > 0 and label.TextBounds.X < labelWidth)
assert(button.TextBounds.X > 0 and button.TextBounds.X < buttonWidth)
`, "text_cache_bounds")
	assert(ok, err)

	svg := "<svg xmlns='http://www.w3.org/2000/svg' width='4' height='4'><rect width='4' height='4' fill='red'/></svg>"
	icon := kineffi.Kine_Skia_Image_LoadFromMemory(raw_data(svg), uintptr(len(svg)))
	assert(icon != nil)
	defer kineffi.Kine_Skia_Image_Destroy(icon)
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
	kineffi.Kine_Skia_Surface_DrawImageSized(surface, icon, 10, 10, 8, 16, 255)
	kineffi.Kine_Skia_Surface_DrawImageSized(surface, icon, 30, 10, 16, 8, 128)
	expect_pixel(surface, 14, 18, true, true)
	expect_pixel(surface, 20, 18, false, false)
	expect_pixel(surface, 35, 14, true, false)

	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
	kineffi.Kine_Skia_Surface_DrawSquircle(surface, 10, 10, 32, 24, 10, 4, 255, 0, 0, 255, 0)
	kineffi.Kine_Skia_Surface_DrawSquircle(surface, 10, 10, 32, 24, 10, 4, 255, 0, 0, 255, 0)
	kineffi.Kine_Skia_Surface_DrawSquircle(surface, 65, 10, 22, 24, 8, 5, 255, 0, 0, 255, 0)
	expect_pixel(surface, 24, 20, true, true)
	expect_pixel(surface, 75, 20, true, true)
	expect_pixel(surface, 50, 20, false, false)

	fmt.println("SCREEN_GUI_CLIP_SMOKE_PASSED")
}
