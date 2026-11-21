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
local before = theme.SelectedTheme.ViewportCoordinates.Size.Y.Offset
theme:DockWindow("Animation Editor", "BottomCenter")
local selected = theme.SelectedTheme
local animator = selected.DockedWindows["Animation Editor"]
assert(animator and animator.Size.Y.Offset > 0)
assert(selected.ViewportCoordinates.Size.Y.Offset < before)
assert(theme:GetWindowDock("Animation Editor") == "BottomCenter")
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
