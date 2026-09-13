if IsServer or IsClient then
	return
end

local UI = ishared.EditorUI

local theme = game:GetService("StudioThemeService").SelectedTheme
local Selection = game:GetService("Selection")

local colors = UI.colors
local tokens = UI.tokens

local iconRoot = "builtin://icons/"

local panel, content, header =
	UI.window("Viewport", theme.ViewportCoordinates.Position, theme.ViewportCoordinates.Size, "Viewport")

panel.Position =
	UDim2.new(panel.Position.X.Scale, panel.Position.X.Offset, panel.Position.Y.Scale, panel.Position.Y.Offset + 5)

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
		theme.ViewportCoordinates.Position.Y.Offset + 5 + chromeHeight
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

-- Viewport UI that must render above the rest of the editor.
local viewportOverlay = UI.frame(rootOverlay, getViewportPosition(), getViewportSize(), tokens.color.canvas)

viewportOverlay.Name = "ViewportOverlay"
viewportOverlay.BackgroundTransparency = 1

local activeTool = renderer.Dimension == "2D" and "Select" or "Move"
local snapEnabled = true
local toolButtons = {}

-- Normal-root window controls.
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

-- Transform tools need to appear above normal editor UI.
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
	},
	{
		name = "Size",
		icon = "Size.svg",
	},
	{
		name = "Rotate",
		icon = "Rotate.svg",
	},
	{
		name = "Paint",
		icon = "ColorEffect.svg",
	},
}

local tools2D = {
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
		name = "Size",
		icon = "Size.svg",
	},
	{
		name = "Snap",
		icon = "Snap.svg",
	},
}

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
			else
				activeTool = current.name
			end

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

	toolButtons[current.name] = record

	if index > 1 then
		UI.separator(toolbar, UDim2.fromOffset(5, (index - 1) * UI.metrics.toolbarButton), UDim2.fromOffset(24, 1))
	end
end

updateTools()

local breadcrumb = UI.group(viewportOverlay, UDim2.new(0, 8, 1, -34), UDim2.new(1, -16, 0, 26), {
	color = tokens.color.surface,
	radius = tokens.radius.sm,
})

breadcrumb.BackgroundTransparency = 1
breadcrumb.Name = "ViewportBreadcrumb"
breadcrumb.Visible = renderer.Dimension == "3D"
breadcrumb.ClipsDescendants = true

local function rebuildBreadcrumb(path)
	UI.clear(breadcrumb)

	local x = 8
	local items = string.split(path, ".")

	for index, item in ipairs(items) do
		local width = math.max(28, #item * 7)

		local label = UI.label(
			breadcrumb,
			item,
			UDim2.fromOffset(x, 4),
			UDim2.fromOffset(width, 18),
			tokens.type.caption,
			colors.subtext
		)

		local shadow = Instance.new("UIShadow")
		shadow.ShowForText = true
		shadow.Parent = label

		x += width

		if index < #items then
			UI.image(breadcrumb, iconRoot .. "ArrowRight.svg", UDim2.fromOffset(x + 1, 7), UDim2.fromOffset(10, 10))

			x += 15
		end
	end
end

rebuildBreadcrumb("Workspace")

local lastPath = ""

Selection.SelectionChanged:Connect(function()
	lastPath = ""
end)

renderer.Pool.new("2d", function()
	panel.Size = theme.ViewportCoordinates.Size

	panel.Position = UDim2.new(
		theme.ViewportCoordinates.Position.X.Scale,
		theme.ViewportCoordinates.Position.X.Offset,
		theme.ViewportCoordinates.Position.Y.Scale,
		theme.ViewportCoordinates.Position.Y.Offset + 5
	)

	local viewportPosition = getViewportPosition()
	local viewportSize = getViewportSize()

	viewportRoot.Position = viewportPosition
	viewportRoot.Size = viewportSize

	viewportOverlay.Position = viewportPosition
	viewportOverlay.Size = viewportSize

	local absolutePosition = panel.AbsolutePosition
	local absoluteSize = panel.AbsoluteSize

	if absolutePosition and absoluteSize and absoluteSize.X > 0 and absoluteSize.Y > chromeHeight then
		local renderTop = absolutePosition.Y + chromeHeight

		local topbarBottom = UI.shared().topbarBottom or 0

		if topbarBottom >= renderTop then
			renderTop = topbarBottom + 4
		end

		local renderHeight = absolutePosition.Y + absoluteSize.Y - renderTop

		if renderer.Dimension == "3D" then
			renderer:Set3DTexProps(absolutePosition.X, renderTop, absoluteSize.X, renderHeight)
		end

		local overlayInset = math.max(0, renderTop - (absolutePosition.Y + chromeHeight))

		toolbar.Position = UDim2.fromOffset(renderer.Dimension == "2D" and 22 or 8, 8 + overlayInset)

		for _, object in ipairs(game.StarterGui:GetChildren()) do
			if object:IsA("ScreenGui") then
				object.Size = Vector2.new(absoluteSize.X, renderHeight)

				object.RenderOffset = Vector2.new(absolutePosition.X, renderTop)
			end
		end
	end

	local selected = Selection:Get()
	local object = selected and selected[1]

	local path = object and object:GetFullName() or "Workspace"

	if path ~= lastPath then
		lastPath = path
		rebuildBreadcrumb(path)
	end
end)
