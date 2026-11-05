package main

import classes "../src/engine/classes"
import guilib "../src/engine/gui"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("gui layout smoke setup failed")
	}
}

find_gui :: proc(environment: ^engine_runtime.Environment, name: string) -> ^classes.GuiObject {
	for descriptor in environment.classes.classes {
		if descriptor == nil || descriptor.info == nil {
			continue
		}
		if !classes.Is_Class_A(descriptor.info, &classes.GuiObject_Class) {
			continue
		}
		for object in descriptor.instances {
			if object == nil || object.destroyed {
				continue
			}
			if object.name == name {
				return cast(^classes.GuiObject)object
			}
		}
	}
	return nil
}

find_layout :: proc(
	environment: ^engine_runtime.Environment,
	name: string,
) -> ^classes.UIListLayout {
	for descriptor in environment.classes.classes {
		if descriptor == nil || descriptor.info == nil {
			continue
		}
		if !classes.Is_Class_A(descriptor.info, &classes.UIListLayout_Class) {
			continue
		}
		for object in descriptor.instances {
			if object == nil || object.destroyed {
				continue
			}
			if object.name == name {
				return cast(^classes.UIListLayout)object
			}
		}
	}
	return nil
}

find_grid :: proc(
	environment: ^engine_runtime.Environment,
	name: string,
) -> ^classes.UIGridLayout {
	for descriptor in environment.classes.classes {
		if descriptor == nil || descriptor.info == nil {
			continue
		}
		if !classes.Is_Class_A(descriptor.info, &classes.UIGridLayout_Class) {
			continue
		}
		for object in descriptor.instances {
			if object == nil || object.destroyed {
				continue
			}
			if object.name == name {
				return cast(^classes.UIGridLayout)object
			}
		}
	}
	return nil
}

expect_close :: proc(label: string, got, want: f32) {
	if abs(got - want) > 0.01 {
		fmt.eprintf("FAIL %s: got %v want %v\n", label, got, want)
		panic("gui_layout_smoke failed")
	}
	fmt.printf("ok %-40s -> %v\n", label, got)
}

expect_object :: proc(label: string, gui: ^classes.GuiObject) {
	if gui == nil {
		fmt.eprintf("FAIL %s: object not found\n", label)
		panic("gui_layout_smoke failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(
		&script_vm,
		`
local screen = Instance.new("ScreenGui")
screen.Name = "LayoutScreen"

local parent = Instance.new("Frame", screen)
parent.Name = "AutoParent"
parent.Position = UDim2.fromOffset(100, 50)
parent.Size = UDim2.fromOffset(10, 10)
parent.AutomaticSize = Enum.AutomaticSize.XY

local padding = Instance.new("UIPadding", parent)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 20)
padding.PaddingTop = UDim.new(0, 5)
padding.PaddingBottom = UDim.new(0, 15)

local a = Instance.new("Frame", parent)
a.Name = "AutoA"
a.Position = UDim2.fromOffset(0, 0)
a.Size = UDim2.fromOffset(100, 40)

local b = Instance.new("Frame", parent)
b.Name = "AutoB"
b.Position = UDim2.fromOffset(30, 60)
b.Size = UDim2.fromOffset(50, 20)
`,
		"gui_layout_auto_padding",
	)

	classes.Update_GUI_Layout(&environment.classes, 800, 600)

	parent := find_gui(&environment, "AutoParent")
	a := find_gui(&environment, "AutoA")
	b := find_gui(&environment, "AutoB")
	expect_object("AutoParent", parent)
	expect_object("AutoA", a)
	expect_object("AutoB", b)

	expect_close("auto parent width", parent.resolved_size.X, 130)
	expect_close("auto parent height", parent.resolved_size.Y, 100)
	expect_close("auto parent content x", parent.content_offset.X, 10)
	expect_close("auto parent content y", parent.content_offset.Y, 5)

	expect_close("child A x", a.absolute_position.X, 110)
	expect_close("child A y", a.absolute_position.Y, 55)
	expect_close("child A width", a.absolute_size.X, 100)
	expect_close("child A height", a.absolute_size.Y, 40)

	expect_close("child B x", b.absolute_position.X, 140)
	expect_close("child B y", b.absolute_position.Y, 115)

	run_script(
		&script_vm,
		`
local frame = Instance.new("Frame")
function refreshLayoutProperties(x)
	frame.Position = UDim2.fromOffset(x, 20)
	frame.Size = UDim2.fromOffset(100, 40)
	frame.ZIndex = 3
	frame.Visible = true
end
function refreshLayoutAppearance()
	frame.BackgroundTransparency = 0.5
end
refreshLayoutProperties(10)
`,
		"gui_layout_property_refresh_setup",
	)
	revision := classes.gui_render_revision
	run_script(&script_vm, "refreshLayoutProperties(10)", "gui_layout_property_refresh_same")
	assert(classes.gui_render_revision == revision, "unchanged properties invalidated GUI layout")
	classes.Update_GUI_Layout(&environment.classes, 800, 600)
	assert(!classes.gui_layout_dirty, "layout did not settle before appearance update")
	revision = classes.gui_render_revision
	run_script(&script_vm, "refreshLayoutAppearance()", "gui_layout_property_refresh_appearance")
	assert(!classes.gui_layout_dirty, "appearance update invalidated GUI layout")
	assert(classes.gui_render_revision > revision, "appearance update did not invalidate rendering")
	revision = classes.gui_render_revision
	run_script(&script_vm, "refreshLayoutProperties(11)", "gui_layout_property_refresh_changed")
	assert(classes.gui_render_revision > revision, "changed position did not invalidate GUI layout")

	run_script(
		&script_vm,
		`
local screen = Instance.new("ScreenGui")
screen.Name = "ClampScreen"

local parent = Instance.new("Frame", screen)
parent.Name = "ClampParent"
parent.Size = UDim2.fromOffset(100, 100)

local padding = Instance.new("UIPadding", parent)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)

local child = Instance.new("Frame", parent)
child.Name = "ClampChild"
child.Size = UDim2.fromOffset(200, 200)
child.AutomaticSize = Enum.AutomaticSize.XY
`,
		"gui_layout_clamp",
	)

	classes.Update_GUI_Layout(&environment.classes, 800, 600)

	clamp_child := find_gui(&environment, "ClampChild")
	expect_object("ClampChild", clamp_child)
	expect_close("clamped child width", clamp_child.resolved_size.X, 80)
	expect_close("clamped child height", clamp_child.resolved_size.Y, 80)

	run_script(
		&script_vm,
		`
local screen = Instance.new("ScreenGui")
screen.Name = "ScrollScreen"

local scroll = Instance.new("ScrollingFrame", screen)
scroll.Name = "AutoScroll"
scroll.Position = UDim2.fromOffset(0, 0)
scroll.Size = UDim2.fromOffset(100, 100)
scroll.CanvasSize = UDim2.fromOffset(300, 200)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
assert(scroll.AutomaticCanvasSize == Enum.AutomaticSize.Y)
assert(math.abs(scroll.AbsoluteCanvasSize.X - 300) < 0.01)

local layout = Instance.new("UIListLayout", scroll)
layout.Padding = UDim.new(0, 5)

for index = 1, 10 do
	local item = Instance.new("Frame", scroll)
	item.Name = "ScrollItem" .. index
	item.Size = UDim2.fromOffset(20, 20)
	item.LayoutOrder = index
end

local copy = scroll:Clone()
assert(copy.AutomaticCanvasSize == Enum.AutomaticSize.Y)
`,
		"gui_layout_scrolling",
	)

	classes.Update_GUI_Layout(&environment.classes, 800, 600)

	scroll := find_gui(&environment, "AutoScroll")
	expect_object("AutoScroll", scroll)
	frame := cast(^classes.ScrollingFrame)scroll
	expect_close("scroll content height", frame.content_size.Y, 245)
	expect_close("scroll canvas x", frame.absolute_size.X, 100)

	rect := guilib.Rect {
		width  = 100,
		height = 100,
	}
	classes.ScrollingFrame_update_animation(frame, rect, 0.016)
	expect_close("scroll max y", frame.max_scroll_y, 145)

	run_script(
		&script_vm,
		`
local screen = Instance.new("ScreenGui")
screen.Name = "ListScreen"

local list_parent = Instance.new("Frame", screen)
list_parent.Name = "ListParent"
list_parent.Position = UDim2.fromOffset(0, 0)
list_parent.Size = UDim2.fromOffset(200, 120)

local list_padding = Instance.new("UIPadding", list_parent)
list_padding.PaddingLeft = UDim.new(0, 10)
list_padding.PaddingRight = UDim.new(0, 10)
list_padding.PaddingTop = UDim.new(0, 10)
list_padding.PaddingBottom = UDim.new(0, 10)

local layout = Instance.new("UIListLayout", list_parent)
layout.Name = "Layout"
layout.Padding = UDim.new(0, 5)
layout.PaddingLeft = UDim.new(0, 10)
layout.PaddingRight = UDim.new(0, 10)
layout.PaddingTop = UDim.new(0, 10)
layout.PaddingBottom = UDim.new(0, 10)
layout.VerticalFlex = Enum.UIFlexAlignment.Fill
layout.HorizontalFlex = Enum.UIFlexAlignment.Fill
layout.ItemLineAlignment = Enum.ItemLineAlignment.Center

for index = 1, 3 do
	local item = Instance.new("Frame", list_parent)
	item.Name = "ListItem" .. index
	item.Size = UDim2.fromOffset(50, 20)
	item.LayoutOrder = index
end

local copy = layout:Clone()
assert(copy.VerticalFlex == Enum.UIFlexAlignment.Fill)
assert(copy.HorizontalFlex == Enum.UIFlexAlignment.Fill)
assert(copy.ItemLineAlignment == Enum.ItemLineAlignment.Center)
`,
		"gui_layout_list",
	)

	classes.Update_GUI_Layout(&environment.classes, 800, 600)

	list_parent := find_gui(&environment, "ListParent")
	expect_object("ListParent", list_parent)
	item_a := find_gui(&environment, "ListItem1")
	item_b := find_gui(&environment, "ListItem2")
	item_c := find_gui(&environment, "ListItem3")
	expect_object("ListItem1", item_a)
	expect_object("ListItem2", item_b)
	expect_object("ListItem3", item_c)

	layout := find_layout(&environment, "Layout")
	if layout == nil {
		panic("gui_layout_smoke: list layout not found")
	}

	expect_close("list content width", layout.absolute_content_size.X, 180)
	expect_close("list content height", layout.absolute_content_size.Y, 100)

	expect_close("list item A x", item_a.absolute_position.X, 20)
	expect_close("list item A y", item_a.absolute_position.Y, 20)
	expect_close("list item A width", item_a.absolute_size.X, 160)
	expect_close("list item A height", item_a.absolute_size.Y, 23.333)
	expect_close("list item B y", item_b.absolute_position.Y, 48.333)
	expect_close("list item C y", item_c.absolute_position.Y, 76.667)

	run_script(
		&script_vm,
		`
local screen = Instance.new("ScreenGui")
screen.Name = "GridScreen"

local grid_parent = Instance.new("Frame", screen)
grid_parent.Name = "GridParent"
grid_parent.Position = UDim2.fromOffset(0, 0)
grid_parent.Size = UDim2.fromOffset(280, 200)

local padding = Instance.new("UIPadding", grid_parent)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)

local grid = Instance.new("UIGridLayout", grid_parent)
grid.Name = "Grid"
grid.CellSize = UDim2.fromOffset(50, 40)
grid.CellPadding = UDim2.fromOffset(5, 5)
grid.FillDirection = Enum.FillDirection.Horizontal

for index = 1, 6 do
	local item = Instance.new("Frame", grid_parent)
	item.Name = "GridItem" .. index
	item.LayoutOrder = index
end
`,
		"gui_layout_grid",
	)

	classes.Update_GUI_Layout(&environment.classes, 800, 600)

	grid := find_grid(&environment, "Grid")
	if grid == nil {
		panic("gui_layout_smoke: grid layout not found")
	}

	expect_close("grid columns", grid.absolute_cell_count.X, 4)
	expect_close("grid rows", grid.absolute_cell_count.Y, 2)
	expect_close("grid content width", grid.absolute_content_size.X, 215)
	expect_close("grid content height", grid.absolute_content_size.Y, 85)

	grid_item_6 := find_gui(&environment, "GridItem6")
	expect_object("GridItem6", grid_item_6)
	expect_close("grid item 6 x", grid_item_6.absolute_position.X, 65)
	expect_close("grid item 6 y", grid_item_6.absolute_position.Y, 55)
	expect_close("grid item 6 width", grid_item_6.absolute_size.X, 50)
	expect_close("grid item 6 height", grid_item_6.absolute_size.Y, 40)

	run_script(
		&script_vm,
		`
local screen = Instance.new("ScreenGui")
screen.Name = "OrderScreen"

local order_parent = Instance.new("Frame", screen)
order_parent.Name = "OrderParent"
order_parent.Position = UDim2.fromOffset(0, 0)
order_parent.Size = UDim2.fromOffset(400, 100)

local order_layout = Instance.new("UIListLayout", order_parent)
order_layout.Name = "OrderLayout"
order_layout.FillDirection = Enum.FillDirection.Horizontal
order_layout.Padding = UDim.new(0, 0)

local order_a = Instance.new("TextButton", order_parent)
order_a.Name = "OrderA"
order_a.Size = UDim2.fromOffset(40, 20)

local order_b = Instance.new("Frame", order_parent)
order_b.Name = "OrderB"
order_b.Size = UDim2.fromOffset(40, 20)

local order_c = Instance.new("TextButton", order_parent)
order_c.Name = "OrderC"
order_c.Size = UDim2.fromOffset(40, 20)

local order_d = Instance.new("Frame", order_parent)
order_d.Name = "OrderD"
order_d.Size = UDim2.fromOffset(40, 20)
`,
		"gui_layout_order",
	)

	classes.Update_GUI_Layout(&environment.classes, 800, 600)

	order_a := find_gui(&environment, "OrderA")
	order_b := find_gui(&environment, "OrderB")
	order_c := find_gui(&environment, "OrderC")
	order_d := find_gui(&environment, "OrderD")
	expect_object("OrderA", order_a)
	expect_object("OrderB", order_b)
	expect_object("OrderC", order_c)
	expect_object("OrderD", order_d)

	expect_close("list order A x", order_a.absolute_position.X, 0)
	expect_close("list order B x", order_b.absolute_position.X, 40)
	expect_close("list order C x", order_c.absolute_position.X, 80)
	expect_close("list order D x", order_d.absolute_position.X, 120)

	run_script(
		&script_vm,
		`
local screen = Instance.new("ScreenGui")
screen.Name = "CallbackScreen"

local parent = Instance.new("Frame", screen)
parent.Name = "CallbackParent"
parent.Position = UDim2.fromOffset(10, 20)
parent.Size = UDim2.fromOffset(100, 100)

local layout = Instance.new("UIListLayout", parent)
layout.Name = "CallbackLayout"
layout.Padding = UDim.new(0, 0)

CALLBACK_COUNT = 0
CALLBACK_LAST_INDEX = nil
CALLBACK_LAST_DELTA = nil
CALLBACK_LAST_CHILD = nil

layout.PositionCallback = function(child, index, defaultPosition, deltaTime)
	CALLBACK_COUNT = CALLBACK_COUNT + 1
	CALLBACK_LAST_INDEX = index
	CALLBACK_LAST_DELTA = deltaTime
	CALLBACK_LAST_CHILD = child
	return Vector2.new(
		defaultPosition.X + index * 3 + deltaTime * 100,
		defaultPosition.Y + index * 7
	)
end

local a = Instance.new("Frame", parent)
a.Name = "CallbackA"
a.Size = UDim2.fromOffset(10, 10)

local b = Instance.new("Frame", parent)
b.Name = "CallbackB"
b.Size = UDim2.fromOffset(10, 10)

CALLBACK_IS_FUNCTION = type(layout.PositionCallback) == "function"
CALLBACK_CLONE_IS_NIL = layout:Clone().PositionCallback == nil
`,
		"gui_layout_position_callback",
	)

	classes.Update_GUI_Layout(&environment.classes, 800, 600, 0.5)

	callback_a := find_gui(&environment, "CallbackA")
	callback_b := find_gui(&environment, "CallbackB")
	expect_object("CallbackA", callback_a)
	expect_object("CallbackB", callback_b)

	expect_close("callback a x", callback_a.absolute_position.X, 63)
	expect_close("callback a y", callback_a.absolute_position.Y, 27)
	expect_close("callback b x", callback_b.absolute_position.X, 66)
	expect_close("callback b y", callback_b.absolute_position.Y, 44)

	run_script(
		&script_vm,
		`
assert(CALLBACK_IS_FUNCTION)
assert(CALLBACK_CLONE_IS_NIL)
assert(CALLBACK_COUNT >= 2)
assert(CALLBACK_LAST_INDEX == 2)
assert(CALLBACK_LAST_DELTA == 0.5)
assert(CALLBACK_LAST_CHILD.Name == "CallbackB")

assert(not pcall(function()
	Instance.new("UIListLayout").PositionCallback = 5
end))

local layout = Instance.new("UIListLayout")
layout.PositionCallback = function() return Vector2.zero end
layout.PositionCallback = nil
assert(layout.PositionCallback == nil)
`,
		"gui_layout_position_callback_assert",
	)

	run_script(
		&script_vm,
		`
local screen = Instance.new("ScreenGui")
screen.Name = "CallbackDisableScreen"

local parent = Instance.new("Frame", screen)
parent.Name = "CallbackDisableParent"
parent.Position = UDim2.fromOffset(10, 20)
parent.Size = UDim2.fromOffset(100, 100)

local layout = Instance.new("UIListLayout", parent)
layout.Name = "CallbackDisableLayout"
layout.Padding = UDim.new(0, 0)
layout.PositionCallback = function(child, index, defaultPosition)
	return Vector2.new(defaultPosition.X + 100, defaultPosition.Y + 100)
end
DISABLE_LAYOUT = layout

local a = Instance.new("Frame", parent)
a.Name = "CallbackDisableA"
a.Size = UDim2.fromOffset(10, 10)
`,
		"gui_layout_position_callback_disable",
	)

	classes.Update_GUI_Layout(&environment.classes, 800, 600, 0.25)

	callback_disable_a := find_gui(&environment, "CallbackDisableA")
	expect_object("CallbackDisableA", callback_disable_a)
	expect_close("callback disable x", callback_disable_a.absolute_position.X, 110)
	expect_close("callback disable y", callback_disable_a.absolute_position.Y, 120)

	run_script(
		&script_vm,
		`
DISABLE_LAYOUT.PositionCallback = nil
assert(DISABLE_LAYOUT.PositionCallback == nil)
`,
		"gui_layout_position_callback_disable_nil",
	)

	classes.Update_GUI_Layout(&environment.classes, 800, 600, 0.25)

	expect_close("callback disabled x", callback_disable_a.absolute_position.X, 10)
	expect_close("callback disabled y", callback_disable_a.absolute_position.Y, 20)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("GUI_LAYOUT_SMOKE_PASSED")
}
