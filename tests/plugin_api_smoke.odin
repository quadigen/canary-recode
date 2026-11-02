package main

import engine_runtime "../src/engine/runtime"
import target "../src/engine/target"
import vm "../src/engine/vm"
import "core:fmt"

expect :: proc(ok: bool, message: string) {
	if !ok {
		panic(message)
	}
}

main :: proc() {
	target.set_mode(.Editor)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, nil, .Editor)

	source := `
local info = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	true,
	false,
	320,
	240,
	160,
	120
)
assert(typeof(info) == "DockWidgetPluginGuiInfo")
assert(info.InitialDockState == Enum.InitialDockState.Float)
assert(info.InitialEnabled == true)
assert(info.InitialEnabledShouldOverrideRestore == false)
assert(info.FloatingXSize == 320)
assert(info.FloatingYSize == 240)
assert(info.MinWidth == 160)
assert(info.MinHeight == 120)
assert(tostring(info):find("DockWidgetPluginGuiInfo", 1, true) ~= nil)

-- Both constructors must return the dock Instance itself, not the internal
-- pipe payload table (see the plugin_pipe_send stack-balance fix).
local asyncDock = plugin:CreateDockWidgetPluginGuiAsync("AsyncDock", info)
assert(typeof(asyncDock) == "Instance", "async dock type: " .. typeof(asyncDock))
assert(asyncDock.ClassName == "DockWidgetPluginGui")
assert(asyncDock:IsA("Frame"))
assert(asyncDock.Title == "AsyncDock")

local syncDock = plugin:CreateDockWidgetPluginGui("SyncDock", info)
assert(typeof(syncDock) == "Instance", "sync dock type: " .. typeof(syncDock))
assert(syncDock.ClassName == "DockWidgetPluginGui")

local child = Instance.new("TextButton")
child.Parent = asyncDock
assert(child.Parent == asyncDock)
local children = asyncDock:GetChildren()
assert(#children == 1)

asyncDock.Title = "Renamed Dock"
assert(asyncDock.Title == "Renamed Dock")
asyncDock.Enabled = true
assert(asyncDock.Enabled == true)
asyncDock:Close()
assert(asyncDock.Enabled == false)

local toolbar = plugin:CreateToolbar("SmokeToolbar")
assert(typeof(toolbar) == "Instance", "toolbar type: " .. typeof(toolbar))
assert(toolbar.ClassName == "PluginToolbar")
assert(toolbar.Title == "SmokeToolbar")

local optionalButton = toolbar:CreateButton("optional-button", "Tip", "Script.svg")
assert(optionalButton.ClassName == "PluginToolbarButton")
assert(optionalButton.Text == "optional-button")

local button = toolbar:CreateButton("smoke-button", "Tip", "Script.svg", "Smoke")
assert(typeof(button) == "Instance", "button type: " .. typeof(button))
assert(button.ClassName == "PluginToolbarButton")
assert(button.Text == "Smoke")
assert(button.Enabled == true)
assert(button.Active == false)
button:SetActive(true)
assert(button.Active == true)
button.Text = "Updated"
assert(button.Text == "Updated")

-- Toolbar buttons can be created before the editor connects to Studio.Pipe.
-- The sync call must replay the existing buttons with their toolbar title.
local studio = game:GetService("Studio")
local synced = {}
local syncConnection = studio.Pipe:Connect(function(signal, value)
	if signal == "PluginToolbarButtonAdded" then
		synced[value.Text] = value
	end
end)
plugin:__SyncPluginToolbars()
syncConnection:Disconnect()
assert(synced["Updated"] ~= nil, "sync did not replay the toolbar button")
assert(synced["Updated"].Toolbar == "SmokeToolbar")

local action = plugin:CreatePluginAction("smoke-action", "Action", "Tip", "Script.svg", true)
assert(typeof(action) == "Instance", "action type: " .. typeof(action))
assert(action.ClassName == "PluginAction")
assert(action.ActionId == "smoke-action")
assert(action.Text == "Action")
assert(action.StatusTip == "Tip")
assert(action.Icon == "Script.svg")
assert(action.Enabled == true)
assert(action.Active == false)

local optionalAction = plugin:CreatePluginAction("optional-action", "Optional", "Tip", "Script.svg")
assert(optionalAction.ClassName == "PluginAction")
assert(optionalAction.AllowBinding == false)

local menu = plugin:CreatePluginMenu("smoke-menu", "Menu", "Script.svg")
assert(typeof(menu) == "Instance", "menu type: " .. typeof(menu))
assert(menu.ClassName == "PluginMenu")
assert(menu.Title == "Menu")
menu:AddAction(action)
menu:AddSeparator()
menu:AddMenu(plugin:CreatePluginMenu("smoke-submenu", "Submenu", ""))
assert(menu:ShowAsync() == nil)

-- Numeric ids and omitted optional icon/text arguments are accepted.
local numericMenu = plugin:CreatePluginMenu(math.random(), "Numeric Menu")
assert(numericMenu.ClassName == "PluginMenu")
assert(numericMenu.Title == "Numeric Menu")
numericMenu.Name = "Numeric Menu"
numericMenu:AddNewAction("menu-action-a", "A", "Script.svg")
numericMenu:AddNewAction("menu-action-b", "B")
assert(numericMenu:ShowAsync() == nil)

plugin:Activate()
assert(plugin:IsActivated() == true)
plugin:Deactivate()
assert(plugin:IsActivated() == false)
plugin:Activate(true)
assert(plugin:IsActivated() == true)
plugin:Deactivate()
`

	ok, err := vm.RunInternal(&script_vm, source, "plugin_api_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("plugin API smoke test failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("PLUGIN_API_SMOKE_PASSED")
}
