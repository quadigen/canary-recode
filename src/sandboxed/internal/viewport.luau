if IsServer or IsClient then
	return
end

local UI = require("@internal/editor_ui")

local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme
local TextService = game:GetService("TextService")
local Selection = game:GetService("Selection")

local colors = UI.colors
local tokens = UI.tokens

local iconRoot = "builtin://icons/"

local panel, content, header =
	UI.window("Viewport", theme.ViewportCoordinates.Position, theme.ViewportCoordinates.Size, "Viewport")

panel.BackgroundTransparency = 1
content.BackgroundTransparency = 1

local chromeHeight = UI.metrics.windowHeader + 1

local root = UI.root()
local rootOverlay = UI.RootOverlay()

local function getViewportPosition()
	return UDim2.new(
		theme.ViewportCoordinates.Position.X.Scale,
		theme.ViewportCoordinates.Position.X.Offset,
		theme.ViewportCoordinates.Position.Y.Scale,
		theme.ViewportCoordinates.Position.Y.Offset + chromeHeight
	)
end

local function getViewportSize()
	return UDim2.new(
		theme.ViewportCoordinates.Size.X.Scale,
		theme.ViewportCoordinates.Size.X.Offset,
		theme.ViewportCoordinates.Size.Y.Scale,
		theme.ViewportCoordinates.Size.Y.Offset - chromeHeight
	)
end

-- Normal viewport UI container.
local viewportRoot = UI.frame(root, getViewportPosition(), getViewportSize(), tokens.color.canvas)

viewportRoot.Name = "ViewportRoot"
viewportRoot.BackgroundTransparency = 1

local viewportOverlay = UI.frame(rootOverlay, getViewportPosition(), getViewportSize(), tokens.color.canvas)

viewportOverlay.Name = "ViewportOverlay"
viewportOverlay.BackgroundTransparency = 1

local activeTool = renderer.Dimension == "2D" and "Select" or "Move"
local snapEnabled = true
local toolButtons = {}

local handles = Instance.new("Handles")
handles.Name = "ViewportHandles"
handles.Parent = workspace

local arcHandles = Instance.new("ArcHandles")
arcHandles.Name = "ViewportArcHandles"
arcHandles.Parent = workspace

local function selectedPart()
	local selected = Selection:Get()
	local object = selected and selected[1]
	if object and (object:IsA("Part") or object:IsA("MeshPart")) then
		return object
	end
	return nil
end

local function updateGizmos()
	local adornee = selectedPart()
	local is3D = renderer.Dimension == "3D"

	handles.Adornee = adornee
	arcHandles.Adornee = adornee
	handles.Visible = is3D and adornee ~= nil and activeTool ~= "Paint" and activeTool ~= "Rotate"
	arcHandles.Visible = is3D and adornee ~= nil and activeTool == "Rotate"

	if activeTool == "Move" then
		handles.Style = Enum.HandlesStyle.Movement
	elseif activeTool == "Size" then
		handles.Style = Enum.HandlesStyle.Resize
	end
end

local playGroup = UI.group(header, UDim2.new(0.5, -30, 0, 2), UDim2.fromOffset(60, 23), {
	color = tokens.color.surfaceAlt,
	radius = tokens.radius.sm,
})

UI.iconButton(playGroup, iconRoot .. "Play.svg", UDim2.fromOffset(1, 1), UDim2.fromOffset(28, 21), function() end, {
	color = tokens.color.surfaceAlt,
	radius = tokens.radius.xs,
	border = false,
	iconSize = 14,
})

UI.separator(playGroup, UDim2.fromOffset(29, 3), UDim2.fromOffset(1, 17))

UI.iconButton(playGroup, iconRoot .. "Stop.svg", UDim2.fromOffset(31, 1), UDim2.fromOffset(28, 21), function() end, {
	color = tokens.color.surfaceAlt,
	radius = tokens.radius.xs,
	border = false,
	iconSize = 14,
})

local toolbar = UI.group(
	viewportOverlay,
	UDim2.fromOffset(renderer.Dimension == "2D" and 22 or 8, 8),
	UDim2.fromOffset(34, (renderer.Dimension == "2D" and 5 or 4) * UI.metrics.toolbarButton + 2),
	{
		color = tokens.color.surface,
		radius = tokens.radius.md,
	}
)

toolbar.Name = "TransformToolbar"

local tools3D = {
	{
		name = "Move",
		icon = "Move.svg",
		tooltip = "Move",
	},
	{
		name = "Size",
		icon = "Size.svg",
		tooltip = "Resize",
	},
	{
		name = "Rotate",
		icon = "Rotate.svg",
		tooltip = "Rotate",
	},
	{
		name = "Paint",
		icon = "ColorEffect.svg",
		tooltip = "Color",
	},
}

local tools2D = {
	{
		name = "Select",
		icon = "Cursor.svg",
		tooltip = "Select",
	},
	{
		name = "Move",
		icon = "Move.svg",
		tooltip = "Move",
	},
	{
		name = "Rotate",
		icon = "Rotate.svg",
		tooltip = "Rotate",
	},
	{
		name = "Size",
		icon = "Size.svg",
		tooltip = "Resize",
	},
	{
		name = "Snap",
		icon = "Snap.svg",
		tooltip = "Toggle Snap",
	},
}

local colorPicker
local colorPickerController

local function selectedColor()
	local object = selectedPart()
	if object and (object:IsA("Part") or object:IsA("MeshPart")) then
		return object.Color
	end
	return Color3.new(1, 1, 1)
end

local function applyColor(color)
	local object = selectedPart()
	if object and (object:IsA("Part") or object:IsA("MeshPart")) then
		object.Color = color
	end
end

colorPicker, colorPickerController =
	UI.colorPicker(viewportOverlay, UDim2.fromOffset(48, 99), UDim2.fromOffset(226, 286), selectedColor(), applyColor)

local function updateTools()
	for name, record in pairs(toolButtons) do
		local active = activeTool == name or (name == "Snap" and snapEnabled)

		UI.setButtonState(record, active and "accent" or "default")
	end
end

for index, definition in ipairs(renderer.Dimension == "2D" and tools2D or tools3D) do
	local current = definition

	local frame, _, record = UI.button(
		toolbar,
		"",
		UDim2.fromOffset(2, 1 + (index - 1) * UI.metrics.toolbarButton),
		UDim2.fromOffset(30, UI.metrics.toolbarButton),
		function()
			if current.name == "Snap" then
				snapEnabled = not snapEnabled
			elseif current.name == "Paint" then
				activeTool = current.name
				colorPickerController:SetColor(selectedColor(), true)
				colorPicker.Visible = not colorPicker.Visible
			else
				activeTool = current.name
				colorPicker.Visible = false
			end

			updateGizmos()
			updateTools()
		end,
		{
			color = tokens.color.surface,
			hoverColor = colors.hover,
			radius = tokens.radius.sm,
			border = false,
		}
	)

	UI.image(frame, iconRoot .. current.icon, UDim2.fromOffset(6, 6), UDim2.fromOffset(18, 18))
	UI.tooltip(frame, current.tooltip, {
		placement = "cursor",
		hoverDelay = 0.35,
	})

	toolButtons[current.name] = record

	if index > 1 then
		UI.separator(toolbar, UDim2.fromOffset(5, (index - 1) * UI.metrics.toolbarButton), UDim2.fromOffset(24, 1))
	end
end

updateTools()

local breadcrumb = UI.group(viewportOverlay, UDim2.new(0, 8, 1, -30), UDim2.new(1, -16, 0, 26), {
	color = tokens.color.surface,
	radius = tokens.radius.sm,
})

breadcrumb.BackgroundTransparency = 1
breadcrumb.Name = "ViewportBreadcrumb"
breadcrumb.Visible = renderer.Dimension == "3D"
breadcrumb.ClipsDescendants = true

local CodeEditor = Instance.new("TextBox")
CodeEditor.Size = UDim2.new(1, 0, 1, 0)
CodeEditor.CodeEditor = true
CodeEditor.Visible = false
CodeEditor.BackgroundTransparency = 0.6
CodeEditor.BackgroundColor3 = Color3.new(0, 0, 0)
CodeEditor.TextColor3 = Color3.new(1, 1, 1)
CodeEditor.Parent = viewportOverlay

local backDrop = Instance.new("UIBackdrop")
backDrop.Parent = CodeEditor

local function rebuildBreadcrumb(path)
	UI.clear(breadcrumb)

	local x = 8
	local items = string.split(path, ".")

	for index, item in ipairs(items) do
		local textSize = TextService:GetTextSize(
			item,
			tokens.type.caption,
			"builtin://fonts/Montserrat-Regular.ttf",
			Vector2.new(10000, 10000)
		)

		local width = math.max(34, math.ceil(textSize.X) + 4)

		local label = UI.label(
			breadcrumb,
			item,
			UDim2.fromOffset(x, 4),
			UDim2.fromOffset(width, 18),
			tokens.type.caption,
			Color3.new(1, 1, 1)
		)

		local shadow = Instance.new("UIShadow")
		shadow.ShowForText = true
		shadow.BlurRadius = UDim.new(0, 2.5)
		shadow.Offset = UDim2.fromOffset(2, 2)
		shadow.Spread = UDim2.fromOffset(0, 5)
		shadow.Color3 = Color3.fromRGB(0, 0, 0)
		shadow.Transparency = 0.8
		shadow.Parent = label

		x += width + 2

		if index < #items then
			local image =
				UI.image(breadcrumb, iconRoot .. "ArrowRight.svg", UDim2.fromOffset(x + 1, 7), UDim2.fromOffset(10, 10))

			local img_shadow = Instance.new("UIShadow")
			img_shadow.ShowForText = false
			img_shadow.BlurRadius = UDim.new(0, 2.5)
			img_shadow.Offset = UDim2.fromOffset(2, 2)
			img_shadow.Spread = UDim2.fromOffset(0, 5)
			img_shadow.Color3 = Color3.fromRGB(0, 0, 0)
			img_shadow.Transparency = 0.8
			img_shadow.Enabled = true
			img_shadow.Parent = image

			x += 17
		end
	end
end

rebuildBreadcrumb("Workspace.Part")

local lastPath = ""

Selection.SelectionChanged:Connect(function()
	lastPath = ""
	updateGizmos()
end)

updateGizmos()

renderer.Pool.new("2d", function()
	theme = StudioThemeService.SelectedTheme

	local outputWindow = UI.getWindow("Output")
	local outputHidden = outputWindow and not outputWindow.Visible

	local viewportSize = getViewportSize()

	local viewportPosition = getViewportPosition()

	viewportRoot.Position = viewportPosition
	viewportRoot.Size = viewportSize

	viewportOverlay.Position = viewportPosition
	viewportOverlay.Size = viewportSize

	if outputHidden and theme.OutputCoordinates then
		viewportSize = UDim2.new(
			viewportSize.X.Scale,
			viewportSize.X.Offset,
			viewportSize.Y.Scale,
			viewportSize.Y.Offset + theme.OutputCoordinates.Size.Y.Offset
		)
	end

	viewportRoot.Position = getViewportPosition()
	viewportRoot.Size = viewportSize

	viewportOverlay.Position = getViewportPosition()
	viewportOverlay.Size = viewportSize

	panel.Position = theme.ViewportCoordinates.Position
	panel.Size = UDim2.new(
		theme.ViewportCoordinates.Size.X.Scale,
		theme.ViewportCoordinates.Size.X.Offset,
		theme.ViewportCoordinates.Size.Y.Scale,
		theme.ViewportCoordinates.Size.Y.Offset + (outputHidden and theme.OutputCoordinates.Size.Y.Offset or 0)
	)

	local selected = Selection:Get()
	local object = selected and selected[1]

	local path = object and object:GetFullName() or "Workspace"

	if path ~= lastPath then
		lastPath = path
		rebuildBreadcrumb(path)
	end
end)

local lastX = -1
local lastY = -1
local lastWidth = -1
local lastHeight = -1

renderer.Pool.new("2da", function()
	local absolutePosition = viewportRoot.AbsolutePosition
	local absoluteSize = viewportRoot.AbsoluteSize

	local absoluteX = absolutePosition.X
	local absoluteY = absolutePosition.Y
	local absoluteWidth = absoluteSize.X
	local absoluteHeight = absoluteSize.Y

	if absoluteWidth <= 0 or absoluteHeight <= 0 then
		return
	end

	local renderTop = absoluteY
	local topbarBottom = UI.shared().topbarBottom or 0

	if topbarBottom >= renderTop then
		renderTop = topbarBottom + 4
	end

	local renderHeight = absoluteY + absoluteHeight - renderTop

	if renderHeight <= 0 then
		return
	end

	if absoluteX ~= lastX or renderTop ~= lastY or absoluteWidth ~= lastWidth or renderHeight ~= lastHeight then
		lastX = absoluteX
		lastY = renderTop
		lastWidth = absoluteWidth
		lastHeight = renderHeight
	end

	if renderer.Dimension == "3D" then
		if rootOverlay.Enabled then
			renderer:Set3DTexProps(absoluteX, renderTop, absoluteWidth, renderHeight)
		else
			renderer:Set3DTexProps(0, 0, 0, 0)
		end
	end

	local overlayInset = math.max(0, renderTop - absoluteY)

	toolbar.Position = UDim2.fromOffset(renderer.Dimension == "2D" and 22 or 8, 8 + overlayInset)

	for _, object in ipairs(game.StarterGui:GetChildren()) do
		if object:IsA("ScreenGui") then
			object.Size = Vector2.new(absoluteWidth, renderHeight)

			object.RenderOffset = Vector2.new(absoluteX, renderTop)
		end
	end
end)
