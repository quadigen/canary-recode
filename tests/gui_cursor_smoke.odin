package main

import classes "../src/engine/classes"
import platform "../src/engine/platform"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import sdl "vendor:sdl3"

expect :: proc(env: ^runtime.Environment, x, y: f32, want: platform.SystemCursor) {
	hit := classes.GuiObject_hit_test(&env.classes, x, y)
	got := classes.GuiObject_cursor_for_pointer(&env.classes, hit)
	if got != want {
		fmt.eprintf("cursor at (%v, %v): got %v, want %v\n", x, y, got, want)
		panic("cursor mismatch")
	}
}

motion :: proc(env: ^runtime.Environment, state: ^vm.VM, x, y: f32) {
	event: platform.Event
	event.type = .MOUSE_MOTION
	event.motion.x = x
	event.motion.y = y
	runtime.Environment_SetEvent(env, state, event)
}

main :: proc() {
	assert(platform.Init(platform.INIT_VIDEO | platform.INIT_EVENTS))
	defer platform.Quit()
	window := sdl.CreateWindow("Cursor test", 640, 240, sdl.WINDOW_HIDDEN)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	state := vm.New()
	env: runtime.Environment
	runtime.Environment_Init(&env, &state)
	defer runtime.Environment_Destroy(&env)
	defer vm.Close(&state)

	ok, err := vm.Run(
		&state,
		`
local gui = Instance.new("ScreenGui")
local function place(class, x, parent)
    local item = Instance.new(class)
    item.Size = UDim2.fromOffset(90, 90)
    item.Position = UDim2.fromOffset(x, 0)
    item.Parent = parent or gui
    return item
end
local button = place("TextButton", 0)
local child = place("Frame", 5, button)
child.Active = true
child.Size = UDim2.fromOffset(30, 30)
place("ImageButton", 100)
place("TextBox", 200)
local readOnly = place("TextBox", 300)
readOnly.TextEditable = false
local disabled = place("TextButton", 400)
disabled.Interactable = false
local under = place("TextBox", 500)
local cover = place("Frame", 500)
cover.Active = true
cover.ZIndex = 10
local transparentButton = place("TextButton", 0)
transparentButton.Position = UDim2.fromOffset(0, 110)
transparentButton.BackgroundTransparency = 1
transparentButton.Text = "Still clickable"
local transparentBox = place("TextBox", 100)
transparentBox.Position = UDim2.fromOffset(100, 110)
transparentBox.BackgroundTransparency = 1
local invisible = place("TextButton", 200)
invisible.Position = UDim2.fromOffset(200, 110)
invisible.Visible = false
local container = place("Frame", 300)
container.Position = UDim2.fromOffset(300, 110)
container.BackgroundTransparency = 1
local visibleChild = place("TextButton", 0, container)
visibleChild.BackgroundTransparency = 0
local partial = place("TextButton", 400)
partial.Position = UDim2.fromOffset(400, 110)
partial.BackgroundTransparency = 0.99
local resize = place("Frame", 500)
resize.Position = UDim2.fromOffset(500, 110)
local detector = Instance.new("UIScaleDetector")
detector.Parent = resize
local inner = place("TextButton", 0, resize)
inner.Size = UDim2.fromScale(1, 1)
_G.resize = resize
_G.detector = detector
_G.button = button
`,
		"gui_cursor_smoke",
	)
	if !ok {fmt.eprintln(err); panic("script setup")}
	classes.Update_GUI_Layout(&env.classes, 640, 240)
	expect(&env, 10, 10, .POINTER)
	expect(&env, 50, 50, .POINTER)
	expect(&env, 150, 50, .POINTER)
	expect(&env, 250, 50, .TEXT)
	expect(&env, 350, 50, .TEXT)
	expect(&env, 450, 50, .DEFAULT)
	expect(&env, 550, 50, .DEFAULT)
	expect(&env, 630, 200, .DEFAULT)
	expect(&env, 50, 150, .DEFAULT)
	expect(&env, 150, 150, .DEFAULT)
	expect(&env, 250, 150, .DEFAULT)
	expect(&env, 350, 150, .POINTER)
	expect(&env, 450, 150, .POINTER)
	expect(&env, 501, 111, .NWSE_RESIZE)
	expect(&env, 589, 111, .NESW_RESIZE)
	expect(&env, 501, 199, .NESW_RESIZE)
	expect(&env, 589, 199, .NWSE_RESIZE)
	expect(&env, 545, 111, .NS_RESIZE)
	expect(&env, 545, 199, .NS_RESIZE)
	expect(&env, 501, 155, .EW_RESIZE)
	expect(&env, 589, 155, .EW_RESIZE)
	expect(&env, 545, 155, .POINTER)
	button_down: platform.Event
	button_down.type = .MOUSE_BUTTON_DOWN
	button_down.button.button = platform.BUTTON_LEFT
	button_down.button.x = 589
	button_down.button.y = 155
	runtime.Environment_SetEvent(&env, &state, button_down)
	motion(&env, &state, 629, 155)
	expect(&env, 629, 155, .EW_RESIZE)
	button_up := button_down
	button_up.type = .MOUSE_BUTTON_UP
	button_up.button.x = 629
	runtime.Environment_SetEvent(&env, &state, button_up)
	classes.Update_GUI_Layout(&env.classes, 640, 240)
	ok, err = vm.Run(
		&state,
		`assert(math.abs(_G.resize.Size.X.Offset - 130) < 0.01); _G.detector.Enabled = false`,
		"resize_assert",
	)
	if !ok {fmt.eprintln(err); panic("resize assertion")}
	classes.Update_GUI_Layout(&env.classes, 640, 240)
	expect(&env, 629, 155, .POINTER)
	ok, err = vm.Run(&state, `_G.resize.Visible = false`, "resize_hide")
	if !ok {fmt.eprintln(err); panic("resize hide")}
	classes.Update_GUI_Layout(&env.classes, 640, 240)
	expect(&env, 629, 155, .DEFAULT)
	assert(classes.GuiObject_hit_test(&env.classes, 50, 150).target != nil)
	assert(classes.GuiObject_hit_test(&env.classes, 150, 150).target != nil)

	default_cursor := sdl.GetDefaultCursor()
	assert(default_cursor != nil)
	motion(&env, &state, 50, 50)
	pointer := sdl.GetCursor()
	assert(pointer != nil && pointer != default_cursor)
	motion(&env, &state, 150, 50)
	assert(sdl.GetCursor() == pointer)
	motion(&env, &state, 250, 50)
	assert(sdl.GetCursor() != pointer && sdl.GetCursor() != default_cursor)
	motion(&env, &state, 50, 150)
	assert(sdl.GetCursor() == default_cursor)
	motion(&env, &state, 350, 150)
	assert(sdl.GetCursor() != default_cursor)
	motion(&env, &state, 150, 150)
	assert(sdl.GetCursor() == default_cursor)
	_ = sdl.HideCursor()
	motion(&env, &state, 50, 50)
	assert(!sdl.CursorVisible())
	_ = sdl.ShowCursor()
	motion(&env, &state, 630, 200)
	assert(sdl.GetCursor() == default_cursor)
	motion(&env, &state, 250, 50)
	leave: platform.Event
	leave.type = .WINDOW_MOUSE_LEAVE
	runtime.Environment_SetEvent(&env, &state, leave)
	assert(sdl.GetCursor() == default_cursor)
	fmt.println("GUI_CURSOR_SMOKE_PASSED")
}
