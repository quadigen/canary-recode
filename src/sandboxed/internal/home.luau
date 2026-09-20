local UI = require("@internal/editor_ui")
local project_manager = require("@internal/projects")
local plugin_marketplace = require("@internal/marketplace")
local credits_page = require("@internal/credits")
local settings_page = require("@internal/settings")

local gui = Instance.new("ScreenGui")
gui.Name = "Home"
gui.Parent = game.CoreGui

local window, _, _, windowControls = UI.window("Projects", UDim2.new(0, 15, 0, 15), UDim2.new(1, -30, 1, -30), "Home", {
	tabs = {
		"Projects",
		"Marketplace",
		"Settings",
		"Credits",
	},
	selectedTab = "Projects",
})

window.Parent = gui

UI.root().Enabled = false
UI.RootOverlay().Enabled = false

project_manager(windowControls.pages.Projects, windowControls, gui)
plugin_marketplace(windowControls.pages.Marketplace, windowControls, gui)
credits_page(windowControls.pages.Credits, windowControls, gui)
settings_page(windowControls.pages.Settings, windowControls, gui)
