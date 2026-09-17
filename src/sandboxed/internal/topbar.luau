if IsServer or IsClient then
	return
end

local UI = require("@internal/editor_ui")

local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme

local root = UI.RootOverlay()

local tokens = UI.tokens

local FLYOUT_HEIGHT = 70
local FLYOUT_GAP = 5
local FLYOUT_BOTTOM_PADDING = 5

local expanded = true
local selectedCategory


local lastTheme = theme

local categoryRecords = {}
local categoryPositions = {}

local topbar
local topbarStroke
local headerSurface
local headerBottomFill
local logoPlate
local flyout
local flyoutStroke
local engineSeparator
local selectedIndicator
local collapseButton
local collapseIcon

local engineButtonLabels = {}
local categoryLabels = {}

local rebuildFlyout
local setExpanded

local function safeAction(callback)
	return function()
		if not callback then
			return
		end

		local ok, message = pcall(callback)

		if not ok then
			warn("Editor command failed: " .. tostring(message))
		end
	end
end

local toolbarCategories = {
	{
		name = "Home",

		buttons = {
			{
				name = "Select",
				icon = "Cursor.svg",
			},

			{
				name = "Move",
				icon = "Move.svg",
			},

			{
				name = "Rotate",
				icon = "Rotate.svg",
			},

			{
				name = "Scale",
				icon = "Size.svg",
			},

			{
				type = "separator",
			},

			{
				name = "Play",
				icon = "Play.svg",
			},

			{
				name = "Stop",
				icon = "Stop.svg",
			},
		},
	},

	{
		name = "Model",

		buttons = {
			{
				name = "Part",
				icon = "Part.svg",
			},

			{
				name = "MeshPart",
				icon = "MeshPart.svg",
			},

			{
				name = "Material",
				icon = "Texture.svg",
			},
		},
	},

	{
		name = "Test",

		buttons = {
			{
				name = "Play",
				icon = "Play.svg",
			},

			{
				name = "Stop",
				icon = "Stop.svg",
			},
		},
	},

	{
		name = "View",

		buttons = {
			{
				name = "Explorer",
				icon = "FolderOpen.svg",
				route = "toggle_explorer",
			},

			{
				name = "Inspector",
				icon = "Property.svg",
				route = "toggle_inspector",
			},

			{
				name = "Output",
				icon = "LogService.svg",
				route = "toggle_output",
			},
		},
	},

	{
		name = "Plugins",
		buttons = {},
	},
}

UI.buttonCategories = {
	{
		name = "Engine",

		buttons = {
			{
				name = "File",
			},

			{
				name = "Game",
			},

			{
				name = "Projects",
			},
		},
	},

	{
		name = "Toolbar",
		buttons = toolbarCategories,
	},
}

selectedCategory = toolbarCategories[1]

local function themeColor(value, fallback)
	if value == nil then
		return fallback
	end

	-- Native StudioThemeService currently exposes theme colors as
	-- plain Luau tables: { R = ..., G = ..., B = ..., A = ... }.
	-- GUI properties require the actual Color3 userdata.
	if typeof(value) == "Color3" then
		return value
	end

	if type(value) == "table" and value.R ~= nil and value.G ~= nil and value.B ~= nil then
		return Color3.new(value.R, value.G, value.B)
	end

	return fallback
end

local function palette()
	return {
		base = themeColor(theme.BaseColor, tokens.color.canvas),

		panel = themeColor(theme.BgColor, tokens.color.panel),

		raised = themeColor(theme.SecondaryColor, tokens.color.panelRaised),

		surface = themeColor(theme.ThirdColor, tokens.color.surface),

		input = themeColor(theme.InputColor, tokens.color.input),

		border = themeColor(theme.InputFocusColor, tokens.color.borderStrong),

		accent = themeColor(theme.AccentColor, tokens.color.accent),

		text = themeColor(theme.TextColor, tokens.color.text),

		subtext = themeColor(theme.SecondaryTextColor, tokens.color.subtext),

		muted = themeColor(theme.TextColorDimmed, tokens.color.muted),
	}
end

local function windowRadius()
	return theme.CornerRadius or tokens.radius.md
end

local function buttonRadius()
	return theme.ButtonCornerRadius or tokens.radius.sm
end

local function copyUDim2(value)
	return UDim2.new(value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset)
end

local function applyUpperPaneLayout(name, extraHeight)
	local coordinates = theme[name]

	if not coordinates then
		return
	end

	coordinates.Position = UDim2.new(
		coordinates.Position.X.Scale,
		coordinates.Position.X.Offset,
		coordinates.Position.Y.Scale,
		coordinates.Position.Y.Offset + extraHeight
	)

	coordinates.Size =
		UDim2.new(coordinates.Size.X.Scale, coordinates.Size.X.Offset, coordinates.Size.Y.Scale, coordinates.Size.Y.Offset - extraHeight)
end

local function layoutExtraHeight()
	if not expanded then
		return 0
	end

	return FLYOUT_GAP + FLYOUT_HEIGHT + FLYOUT_BOTTOM_PADDING
end

local function applyWorkspaceLayout()
	local extraHeight = layoutExtraHeight()

	applyUpperPaneLayout("ExplorerCoordinates", extraHeight)

	applyUpperPaneLayout("ViewportCoordinates", extraHeight)

	applyUpperPaneLayout("CodeEditorCoordinates", extraHeight)
end

local function fireRoute(route)
	if not route then
		return
	end

	if UI.StudioSystem then
		UI.StudioSystem:Fire(route)
		return
	end

	local windowName = string.match(route, "^toggle_(.+)$")

	if windowName then
		UI.toggleWindow(windowName)
	end
end

local function baseHeaderHeight()
	local coordinates = theme.TopbarCoordinates

	if not coordinates then
		return 33
	end

	return coordinates.Size.Y.Offset
end

local function expandedTopbarHeight()
	return baseHeaderHeight() + layoutExtraHeight()
end

local function updateTopbarGeometry()
	local coordinates = theme.TopbarCoordinates

	if not coordinates then
		return
	end

	topbar.Position = coordinates.Position

	topbar.Size = UDim2.new(
		coordinates.Size.X.Scale,
		coordinates.Size.X.Offset,
		coordinates.Size.Y.Scale,
		expanded and expandedTopbarHeight() or baseHeaderHeight()
	)

	local headerHeight = baseHeaderHeight()

	headerSurface.Size = UDim2.new(1, 0, 0, headerHeight)

	flyout.Position = UDim2.fromOffset(5, headerHeight + FLYOUT_GAP)

	flyout.Size = UDim2.new(1, -10, 0, FLYOUT_HEIGHT)

	flyout.Visible = expanded
end

local function updateCategoryAppearance()
	local colors = palette()

	for category, record in pairs(categoryRecords) do
		local isSelected = category == selectedCategory

		record.color = isSelected and colors.surface or colors.panel

		record.defaultColor = record.color

		record.hoverColor = colors.raised

		record.defaultHoverColor = colors.raised

		record.pressedColor = colors.input

		record.gui.BackgroundColor3 = record.color
	end

	local position = categoryPositions[selectedCategory]

	if position then
		selectedIndicator.Position = UDim2.fromOffset(position.x + 7, baseHeaderHeight() - 3)

		selectedIndicator.Size = UDim2.fromOffset(math.max(position.width - 14, 8), 2)
	end
end

local function applyTheme()
	local colors = palette()

	topbar.BackgroundColor3 = colors.panel

	headerSurface.BackgroundColor3 = colors.panel

	if headerBottomFill then
		headerBottomFill.BackgroundColor3 = colors.panel
	end

	if logoPlate then
		logoPlate.BackgroundColor3 = colors.surface
	end

	flyout.BackgroundColor3 = colors.surface

	topbarStroke.Color = colors.border

	topbarStroke.Transparency = 0.45

	if flyoutStroke then
		flyoutStroke.Color = colors.border

		flyoutStroke.Transparency = 0.55
	end

	if engineSeparator then
		engineSeparator.BackgroundColor3 = colors.border
	end

	selectedIndicator.BackgroundColor3 = colors.accent

	if collapseButton then
		collapseButton.BackgroundColor3 = colors.panel
	end

	for _, label in ipairs(engineButtonLabels) do
		label.TextColor3 = colors.subtext
	end

	for category, label in pairs(categoryLabels) do
		label.TextColor3 = category == selectedCategory and colors.text or colors.subtext
	end

	updateCategoryAppearance()
end

rebuildFlyout = function()
	UI.clear(flyout)

	local colors = palette()

	local x = 6

	if #selectedCategory.buttons == 0 then
		UI.label(
			flyout,
			"No tools in this category",
			UDim2.fromOffset(12, 24),
			UDim2.new(1, -24, 0, 18),
			tokens.type.small,
			colors.muted
		)

		return
	end

	for _, definition in ipairs(selectedCategory.buttons) do
		if definition.type == "separator" then
			UI.separator(flyout, UDim2.fromOffset(x + 4, 10), UDim2.fromOffset(1, FLYOUT_HEIGHT - 20), colors.border)

			x += 13
		else
			local item = UI.button(
				flyout,
				"",
				UDim2.fromOffset(x, 6),
				UDim2.fromOffset(52, FLYOUT_HEIGHT - 12),
				safeAction(function()
					fireRoute(definition.route)

					if definition.callback then
						definition.callback()
					end
				end),
				{
					color = colors.surface,

					hoverColor = colors.raised,

					pressedColor = colors.input,

					radius = buttonRadius(),

					border = false,
				}
			)

			item.Name = definition.name .. "Tool"

			if definition.icon then
				local iconSize = 22

				UI.image(
					item,
					"builtin://icons/" .. definition.icon,
					UDim2.new(0.5, -math.floor(iconSize / 2), 0, 7),
					UDim2.fromOffset(iconSize, iconSize)
				)
			end

			UI.label(
				item,
				definition.name,
				UDim2.fromOffset(4, 35),
				UDim2.new(1, -8, 0, 16),
				tokens.type.caption,
				colors.subtext
			)

			x += 55
		end
	end
end

setExpanded = function(value)
	expanded = value == true

	updateTopbarGeometry()
	applyWorkspaceLayout()

	if collapseIcon then
		collapseIcon.Image = "builtin://icons/" .. (expanded and "ArrowUp.svg" or "ArrowDown.svg")
	end
end

local initialColors = palette()

topbar =
	UI.frame(root, theme.TopbarCoordinates.Position, theme.TopbarCoordinates.Size, initialColors.panel, windowRadius())

topbar.Name = "Topbar"
topbar.ClipsDescendants = true
topbar.ZIndex = 100

topbarStroke = UI.stroke(topbar, initialColors.border, 1, 0.45)

headerSurface = UI.frame(
	topbar,
	UDim2.fromOffset(0, 0),
	UDim2.new(1, 0, 0, baseHeaderHeight()),
	initialColors.panel,
	windowRadius()
)

headerSurface.Name = "Header"

headerBottomFill = UI.frame(
	headerSurface,
	UDim2.new(0, 0, 1, -windowRadius()),
	UDim2.new(1, 0, 0, windowRadius()),
	initialColors.panel
)

logoPlate =
	UI.frame(headerSurface, UDim2.fromOffset(5, 4), UDim2.fromOffset(25, 25), initialColors.surface, buttonRadius())

logoPlate.Name = "Logo"

UI.image(logoPlate, "builtin://icons/Kinemium.svg", UDim2.fromOffset(2, 2), UDim2.fromOffset(21, 21))

flyout = UI.group(topbar, UDim2.fromOffset(5, baseHeaderHeight() + FLYOUT_GAP), UDim2.new(1, -10, 0, FLYOUT_HEIGHT), {
	color = initialColors.surface,

	radius = windowRadius(),
})

flyout.Name = "ToolbarFlyout"

flyout.ClipsDescendants = true

flyoutStroke = UI.stroke(flyout, initialColors.border, 1, 0.55)

local headerX = 35

local engineButtonRecords = {}

for _, definition in ipairs(UI.buttonCategories[1].buttons) do
	local width = #definition.name * 8 + 20

	local _, label, record = UI.button(
		headerSurface,
		definition.name,
		UDim2.fromOffset(headerX, 4),
		UDim2.fromOffset(width, 24),
		safeAction(definition.callback),
		{
			color = initialColors.panel,

			hoverColor = initialColors.raised,

			pressedColor = initialColors.input,

			textColor = initialColors.subtext,

			textSize = tokens.type.small,

			textY = 3,
			paddingX = 8,

			border = false,

			radius = buttonRadius(),
		}
	)

	table.insert(engineButtonRecords, record)

	table.insert(engineButtonLabels, label)

	headerX += width + 2
end

engineSeparator =
	UI.separator(headerSurface, UDim2.fromOffset(headerX + 4, 7), UDim2.fromOffset(1, 18), initialColors.border)

headerX += 12

selectedIndicator = UI.frame(
	headerSurface,
	UDim2.fromOffset(headerX, baseHeaderHeight()),
	UDim2.fromOffset(20, 2),
	initialColors.accent,
	1
)

for _, category in ipairs(toolbarCategories) do
	local current = category

	local width = #current.name * 8 + 22

	categoryPositions[current] = {
		x = headerX,
		width = width,
	}

	local _, label, record = UI.button(
		headerSurface,
		current.name,
		UDim2.fromOffset(headerX, 4),
		UDim2.fromOffset(width, 24),
		function()
			if selectedCategory == current and expanded then
				setExpanded(false)
				return
			end

			selectedCategory = current

			updateCategoryAppearance()
			rebuildFlyout()
			setExpanded(true)
		end,
		{
			color = current == selectedCategory and initialColors.surface or initialColors.panel,

			hoverColor = initialColors.raised,

			pressedColor = initialColors.input,

			textColor = initialColors.text,

			textSize = tokens.type.small,

			textY = 3,
			paddingX = 8,

			border = false,

			radius = buttonRadius(),
		}
	)

	categoryRecords[current] = record

	categoryLabels[current] = label

	headerX += width + 2
end

local collapseSize = 24

local collapseRecord

do
	local button, _, record = UI.button(
		headerSurface,
		"",
		UDim2.new(1, -(collapseSize + 5), 0, 4),
		UDim2.fromOffset(collapseSize, 24),
		function()
			setExpanded(not expanded)
		end,
		{
			color = initialColors.panel,

			hoverColor = initialColors.raised,

			pressedColor = initialColors.input,

			border = false,

			radius = buttonRadius(),
		}
	)

	collapseButton = button

	collapseRecord = record

	collapseIcon =
		UI.image(button, "builtin://icons/ArrowUp.svg", UDim2.new(0.5, -5, 0.5, -5), UDim2.fromOffset(10, 10))
end

local function refreshTheme()
	local selectedTheme = theme

	local themeChanged = selectedTheme ~= lastTheme

	if themeChanged then
		theme = selectedTheme

		lastTheme = selectedTheme

		
	end

	local colors = palette()

	for _, record in ipairs(engineButtonRecords) do
		record.color = colors.panel

		record.defaultColor = colors.panel

		record.hoverColor = colors.raised

		record.defaultHoverColor = colors.raised

		record.pressedColor = colors.input

		record.gui.BackgroundColor3 = colors.panel
	end

	if collapseRecord then
		collapseRecord.color = colors.panel

		collapseRecord.defaultColor = colors.panel

		collapseRecord.hoverColor = colors.raised

		collapseRecord.defaultHoverColor = colors.raised

		collapseRecord.pressedColor = colors.input

		collapseRecord.gui.BackgroundColor3 = colors.panel
	end

	if themeChanged then
		rebuildFlyout()
	end

	applyTheme()
	updateTopbarGeometry()
	applyWorkspaceLayout()
end

UI.EngineTopbar = {
	AddCategory = function(categoryName, buttons)
		if type(categoryName) ~= "string" or type(buttons) ~= "table" then
			return
		end

		local category = {
			name = categoryName,
			buttons = buttons,
		}

		table.insert(toolbarCategories, category)
	end,

	SetExpanded = function(value)
		setExpanded(value)
	end,

	IsExpanded = function()
		return expanded
	end,

	GetConsumedHeight = function()
		return layoutExtraHeight()
	end,
}

rebuildFlyout()
updateCategoryAppearance()
setExpanded(true)
applyTheme()

renderer.Pool.new("2d", function()
	refreshTheme()
end)
