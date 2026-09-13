if IsServer or IsClient then
	return
end

local UI = ishared.EditorUI
local theme = game:GetService("StudioThemeService").SelectedTheme
local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")
local colors = UI.colors
local tokens = UI.tokens

local panel, content =
	UI.window("Explorer", theme.ExplorerCoordinates.Position, theme.ExplorerCoordinates.Size, "Explorer")
panel.Position =
	UDim2.new(panel.Position.X.Scale, panel.Position.X.Offset, panel.Position.Y.Scale, panel.Position.Y.Offset)

local inset = UI.metrics.panelInset
local searchField =
	UI.input(content, "Search Explorer...", UDim2.fromOffset(inset, 6), UDim2.new(1, -42, 0, UI.metrics.inputHeight))
local expanded = {}
local list = UI.create("ScrollingFrame", {
	Position = UDim2.fromOffset(inset, 36),

	Size = UDim2.new(1, -inset * 2, 1, -42),

	BackgroundColor3 = tokens.color.surface,
	BorderSizePixel = 0,

	CanvasPosition = Vector2.new(0, 0),
	CanvasSize = UDim2.new(1, 0, 0, 0),

	ScrollingEnabled = true,

	ScrollSpeed = 38,

	SmoothScrollingEnabled = true,
	ScrollSmoothness = 18,

	ScrollBarThickness = 5,
	ScrollBarImageColor3 = tokens.color.subtext,
	ScrollBarImageTransparency = 0.4,

	ScrollBarAutoHide = true,
	ScrollBarFadeDelay = 0.45,
	ScrollBarFadeSpeed = 12,

	ScrollBarMinimumHandleSize = 24,

	ClipsDescendants = true,

	Active = true,
	InputSink = true,
}, content)

UI.corner(list, tokens.radius.md)

local function selectedObject()
	local selection = Selection:Get()
	return selection and selection[1]
end

UI.iconButton(
	content,
	"builtin://icons/Plus.svg",
	UDim2.new(1, -32, 0, 6),
	UDim2.fromOffset(26, UI.metrics.inputHeight),
	function()
		local parent = selectedObject() or workspace
		local ok, object = pcall(Instance.new, "Part")
		if ok and object then
			object.Name = "Part"
			object.Parent = parent
			expanded[parent] = true
			Selection:Set({ object })
		end
	end,
	{ color = tokens.color.input, iconSize = 14 }
)

local serviceOrder = {
	Workspace = 1,
	Players = 2,
	Lighting = 3,
	ReplicatedFirst = 4,
	ReplicatedStorage = 5,
	ServerScriptService = 6,
	ServerStorage = 7,
	StarterGui = 8,
	StarterPack = 9,
	StarterPlayer = 10,
	Teams = 11,
	SoundService = 12,
}

local function sortedChildren(parent)
	local children = parent:GetChildren()
	table.sort(children, function(a, b)
		local ao = serviceOrder[a.Name] or math.huge
		local bo = serviceOrder[b.Name] or math.huge
		if ao ~= bo then
			return ao < bo
		end
		return a.Name < b.Name
	end)
	return children
end

local function treeHash(parent, depth)
	if depth > 5 then
		return ""
	end
	local pieces = {}
	for _, child in ipairs(sortedChildren(parent)) do
		table.insert(pieces, child.Name .. ":" .. child.ClassName)
		if expanded[child] then
			table.insert(pieces, treeHash(child, depth + 1))
		end
	end
	return table.concat(pieces, "|")
end

local lastHash = ""
local rebuilding = false
local rebuild

local fallbackIcons = {
	ReplicatedFirst = "ReplicatedStorage",
	StarterPack = "Backpack",
	Teams = "Players",
	Chat = "ChatService",
	TextChatService = "ChatService",
	MaterialService = "Texture",
	TestService = "StudioService",
	TaskScheduler = "RunService",
	ExampleService = "StudioService",
}

local function iconPathFor(instance)
	return "builtin://icons/" .. (fallbackIcons[instance.ClassName] or instance.ClassName) .. ".svg"
end

local rowIndex = 0
local function addRow(instance, depth, y)
	local children = sortedChildren(instance)
	local isSelected = selectedObject() == instance
	rowIndex += 1
	local rowColor = rowIndex % 2 == 0 and tokens.color.rowEven or tokens.color.rowOdd
	local row = UI.button(list, "", UDim2.fromOffset(1, y), UDim2.new(1, -2, 0, UI.metrics.treeRow), function()
		Selection:Set({ instance })
		if #children > 0 then
			expanded[instance] = not expanded[instance]
			lastHash = ""
		end
	end, {
		color = isSelected and colors.selection or rowColor,
		hoverColor = isSelected and colors.selection or colors.hover,
		radius = isSelected and tokens.radius.sm or 0,
		border = false,
	})

	local indent = 7 + depth * 16
	if #children > 0 then
		UI.image(
			row,
			"builtin://icons/" .. (expanded[instance] and "ArrowDown.svg" or "ArrowRight.svg"),
			UDim2.fromOffset(indent, 4),
			UDim2.fromOffset(12, 12)
		)
	end
	UI.image(row, iconPathFor(instance), UDim2.fromOffset(indent + 16, 3), UDim2.fromOffset(14, 14))
	UI.label(
		row,
		instance.Name,
		UDim2.fromOffset(indent + 31, 2),
		UDim2.new(1, -(indent + 34), 0, 17),
		tokens.type.small,
		isSelected and tokens.color.text or colors.text
	)
	return y + UI.metrics.treeRow
end

local function walk(parent, depth, y)
	for _, child in ipairs(sortedChildren(parent)) do
		y = addRow(child, depth, y)

		if expanded[child] then
			y = walk(child, depth + 1, y)
		end
	end

	return y
end

rebuild = function()
	if rebuilding then
		return
	end

	rebuilding = true

	local oldCanvasPosition = list.CanvasPosition

	UI.clear(list)

	rowIndex = 0

	local finalY = walk(game, 0, 1)

	list.CanvasSize = UDim2.new(1, 0, 0, finalY + 4)

	list.CanvasPosition = oldCanvasPosition

	rebuilding = false
end

Selection.SelectionChanged:Connect(function()
	lastHash = ""
end)

UserInputService.InputBegan:Connect(function(a0: InputObject, a1: boolean)
	if a0.KeyCode == Enum.KeyCode.Escape then
		Selection:Set({ nil })
	end
end)

renderer.Pool.new("2d", function()
	panel.Size = theme.ExplorerCoordinates.Size
	panel.Position = theme.ExplorerCoordinates.Position
	local selected = selectedObject()
	local hash = treeHash(game, 0) .. "#" .. (selected and selected:GetFullName() or "")
	if hash ~= lastHash then
		lastHash = hash
		rebuild()
	end
end)
