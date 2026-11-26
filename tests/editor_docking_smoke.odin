package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	v := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v, nil, .Editor)
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}
	ok, err := vm.RunInternal(
		&v,
		`
local theme = game:GetService("StudioThemeService")
theme:ResetDocking()
local function near(a, b)
    assert(math.abs(a - b) < 0.02, tostring(a) .. " ~= " .. tostring(b))
end
local function right(rect)
    return rect.Position.X.Offset + rect.Size.X.Offset
end
local function bottom(rect)
    return rect.Position.Y.Offset + rect.Size.Y.Offset
end
local initial = theme.SelectedTheme
local viewport = initial.ViewportCoordinates
local explorer = initial.ExplorerCoordinates
local inspector = initial.InspectorCoordinates
local output = initial.OutputCoordinates
local oldWeights = theme:GetDockResizeState()
local gap = explorer.Position.X.Offset - right(viewport)
local oldRight = right(explorer)
local oldBottom = bottom(inspector)
local oldExplorerHeight = explorer.Size.Y.Offset

assert(theme:ResizeDockWindow("Explorer", explorer.Position.X.Offset - 50, explorer.Position.Y.Offset,
    explorer.Size.X.Offset + 50, explorer.Size.Y.Offset, 1))
local current = theme.SelectedTheme
near(current.ExplorerCoordinates.Size.X.Offset, explorer.Size.X.Offset + 50)
near(current.InspectorCoordinates.Size.X.Offset, current.ExplorerCoordinates.Size.X.Offset)
near(current.ViewportCoordinates.Size.X.Offset, viewport.Size.X.Offset - 50)
near(current.OutputCoordinates.Size.X.Offset, current.ViewportCoordinates.Size.X.Offset)
near(current.ExplorerCoordinates.Position.X.Offset - right(current.ViewportCoordinates), gap)
near(right(current.ExplorerCoordinates), oldRight)

explorer = current.ExplorerCoordinates
local verticalGap = current.InspectorCoordinates.Position.Y.Offset - bottom(explorer)
assert(theme:ResizeDockWindow("Explorer", explorer.Position.X.Offset, explorer.Position.Y.Offset,
    explorer.Size.X.Offset, explorer.Size.Y.Offset + 35, 8))
current = theme.SelectedTheme
near(current.ExplorerCoordinates.Size.Y.Offset, oldExplorerHeight + 35)
near(current.InspectorCoordinates.Position.Y.Offset - bottom(current.ExplorerCoordinates), verticalGap)
near(bottom(current.InspectorCoordinates), oldBottom)

output = current.OutputCoordinates
viewport = current.ViewportCoordinates
assert(theme:ResizeDockWindow("Output", output.Position.X.Offset, output.Position.Y.Offset - 25,
    output.Size.X.Offset, output.Size.Y.Offset + 25, 4))
current = theme.SelectedTheme
near(current.OutputCoordinates.Size.Y.Offset, output.Size.Y.Offset + 25)
near(current.ViewportCoordinates.Size.Y.Offset, viewport.Size.Y.Offset - 25)
local saved = theme:GetDockResizeState()
local savedWidth = current.ExplorerCoordinates.Size.X.Offset
local savedHeight = current.OutputCoordinates.Size.Y.Offset
theme:ResetDocking()
theme:SetDockResizeState(saved)
near(theme.SelectedTheme.ExplorerCoordinates.Size.X.Offset, savedWidth)
near(theme.SelectedTheme.OutputCoordinates.Size.Y.Offset, savedHeight)
theme:SetDockResizeState(oldWeights)
near(theme.SelectedTheme.ViewportCoordinates.Size.X.Offset, viewport.Size.X.Offset + 50)
theme:SetDockWindowVisible("Output", false)
assert(theme.SelectedTheme.OutputCoordinates.Size.Y.Offset == 0)
assert(theme.SelectedTheme.ViewportCoordinates.Size.Y.Offset > viewport.Size.Y.Offset)
theme:SetDockWindowVisible("Output", true)

explorer = theme.SelectedTheme.ExplorerCoordinates
assert(theme:ResizeDockWindow("Explorer", explorer.Position.X.Offset, explorer.Position.Y.Offset,
    explorer.Size.X.Offset, explorer.Size.Y.Offset + 100000, 8))
assert(theme.SelectedTheme.InspectorCoordinates.Size.Y.Offset >= 93.99)
assert(not theme:ResizeDockWindow("Explorer", explorer.Position.X.Offset, explorer.Position.Y.Offset,
    explorer.Size.X.Offset + 100, explorer.Size.Y.Offset, 2))
theme:ResetDocking()
local before = theme.SelectedTheme.ViewportCoordinates.Size.Y.Offset
theme:DockWindow("Animation Editor", "BottomCenter")
local selected = theme.SelectedTheme
local animator = selected.DockedWindows["Animation Editor"]
assert(animator and animator.Size.Y.Offset > 0)
assert(selected.ViewportCoordinates.Size.Y.Offset < before)
assert(theme:GetWindowDock("Animation Editor") == "BottomCenter")
local customBefore = theme.SelectedTheme.DockedWindows["Animation Editor"]
assert(theme:ResizeDockWindow("Animation Editor", customBefore.Position.X.Offset, customBefore.Position.Y.Offset - 10,
    customBefore.Size.X.Offset, customBefore.Size.Y.Offset + 10, 4))
near(theme.SelectedTheme.DockedWindows["Animation Editor"].Size.Y.Offset, customBefore.Size.Y.Offset + 10)

theme:DockWindow("Material Tool", "TopLeft")
selected = theme.SelectedTheme
assert(selected.DockedWindows["Material Tool"].Size.X.Offset > 0)
theme:SetDockWindowVisible("Animation Editor", false)
assert(theme.SelectedTheme.DockedWindows["Animation Editor"] == nil)
theme:SetDockWindowVisible("Animation Editor", true)
assert(theme.SelectedTheme.DockedWindows["Animation Editor"] ~= nil)
theme:UndockWindow("Animation Editor")
assert(theme.SelectedTheme.DockedWindows["Animation Editor"] == nil)
assert(theme:GetWindowDock("Animation Editor") == nil)
theme:ResetDocking()
assert(theme.SelectedTheme.DockedWindows["Material Tool"] == nil)
`,
		"editor_docking",
	)
	if !ok {fmt.eprintln(err); delete(err); panic("editor docking failed")}
	fmt.println("EDITOR_DOCKING_SMOKE PASSED")
}
