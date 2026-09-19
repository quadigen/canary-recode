if IsServer or IsClient then
	return
end

local UI = require("@internal/editor_ui")

local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme
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
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,

	CanvasPosition = Vector2.new(0, 0),
	CanvasSize = UDim2.new(1, 0, 0, 0),

	ScrollingEnabled = true,

	VirtualizedScrolling = true,

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

local classIcons = {
	ArcHandles = "Handles",
	Atmosphere = "Atmosphere",
	BlurEffect = "BlurEffect",
	BloomEffect = "BloomEffect",
	BoolValue = "BoolValue",
	Camera = "Camera",
	ColorCorrectionEffect = "ColorCorrectionEffect",
	Decal = "Decal",
	DepthOfFieldEffect = "DepthOfFieldEffect",
	Folder = "Folder",
	Frame = "Frame",
	Handles = "Handles",
	ImageButton = "ImageButton",
	ImageLabel = "ImageLabel",
	MeshPart = "MeshPart",
	Model = "Model",
	ModuleScript = "ModuleScript",
	NumberValue = "NumberValue",
	Part = "Part",
	PointLight = "PointLight",
	ScreenGui = "ScreenGui",
	Script = "Script",
	ScrollingFrame = "ScrollingFrame",
	Sound = "Sound",
	SpotLight = "SpotLight",
	SurfaceLight = "SurfaceLight",
	SyntaxHighlighter = "SyntaxHighlighter",
	TextBox = "TextBox",
	TextButton = "TextButton",
	TextLabel = "TextLabel",
	UIBackdrop = "UIBackdrop",
	UICorner = "UICorner",
	UIGradient = "UIGradient",
	UIShadow = "UIShadow",
	UIStroke = "UIStroke",
}

local creatableClasses = {
	"ArcHandles",
	"Atmosphere",
	"BinaryStringValue",
	"BlurEffect",
	"BloomEffect",
	"BoolValue",
	"BrickColorValue",
	"Camera",
	"CFrameValue",
	"Color3Value",
	"ColorCorrectionEffect",
	"Decal",
	"DepthOfFieldEffect",
	"DoubleConstrainedValue",
	"Folder",
	"Frame",
	"Handles",
	"ImageButton",
	"ImageLabel",
	"IntConstrainedValue",
	"IntValue",
	"MeshPart",
	"Model",
	"ModuleScript",
	"NumberValue",
	"ObjectValue",
	"Part",
	"PointLight",
	"RayValue",
	"ScreenGui",
	"Script",
	"ScrollingFrame",
	"Sound",
	"SpotLight",
	"SSAOEffect",
	"StringValue",
	"SurfaceLight",
	"SunRaysEffect",
	"SyntaxHighlighter",
	"TextBox",
	"TextButton",
	"TextLabel",
	"UIBackdrop",
	"UICorner",
	"UIGradient",
	"UIShadow",
	"UIStroke",
	"Vector3Value",
}

local classItems = {}

for _, className in ipairs(creatableClasses) do
	table.insert(classItems, {
		value = className,
		label = className,
		icon = "builtin://icons/" .. (classIcons[className] or className) .. ".svg",
	})
end

table.sort(classItems, function(a, b)
	return a.label < b.label
end)

local categories = {
	{
		name = "Containers",
		items = {},
	},
	{
		name = "Parts & Models",
		items = {},
	},
	{
		name = "Scripts & Values",
		items = {},
	},
	{
		name = "UI",
		items = {},
	},
	{
		name = "Lighting & Effects",
		items = {},
	},
	{
		name = "Handles",
		items = {},
	},
}

local categoryByClass = {
	Folder = "Containers",
	Model = "Containers",

	Part = "Parts & Models",
	MeshPart = "Parts & Models",
	Decal = "Parts & Models",
	Camera = "Parts & Models",

	Script = "Scripts & Values",
	ModuleScript = "Scripts & Values",
	BinaryStringValue = "Scripts & Values",
	BrickColorValue = "Scripts & Values",
	CFrameValue = "Scripts & Values",
	Color3Value = "Scripts & Values",
	DoubleConstrainedValue = "Scripts & Values",
	IntConstrainedValue = "Scripts & Values",
	IntValue = "Scripts & Values",
	ObjectValue = "Scripts & Values",
	RayValue = "Scripts & Values",
	StringValue = "Scripts & Values",
	Vector3Value = "Scripts & Values",
	NumberValue = "Scripts & Values",

	Frame = "UI",
	ImageButton = "UI",
	ImageLabel = "UI",
	ScreenGui = "UI",
	ScrollingFrame = "UI",
	TextBox = "UI",
	SyntaxHighlighter = "UI",
	TextButton = "UI",
	TextLabel = "UI",
	UIBackdrop = "UI",
	UICorner = "UI",
	UIGradient = "UI",
	UIShadow = "UI",
	UIStroke = "UI",

	Atmosphere = "Lighting & Effects",
	BlurEffect = "Lighting & Effects",
	BloomEffect = "Lighting & Effects",
	ColorCorrectionEffect = "Lighting & Effects",
	DepthOfFieldEffect = "Lighting & Effects",
	SSAOEffect = "Lighting & Effects",
	SunRaysEffect = "Lighting & Effects",
	PointLight = "Lighting & Effects",
	SpotLight = "Lighting & Effects",
	SurfaceLight = "Lighting & Effects",

	Handles = "Handles",
	ArcHandles = "Handles",
}

for _, item in ipairs(classItems) do
	item.shortcut = item.value == "Part" and "Ctrl+P" or nil

	local categoryName = categoryByClass[item.value]

	if categoryName then
		for _, category in ipairs(categories) do
			if category.name == categoryName then
				table.insert(category.items, item)

				break
			end
		end
	end
end

local dropdown = UI.dropdown(content, "", UDim2.new(1, -32, 0, 6), UDim2.fromOffset(26, UI.metrics.inputHeight), nil, {
	items = classItems,
	categories = categories,

	searchPlaceholder = "Search classes...",

	icon = "builtin://icons/Plus.svg",
	iconSize = 14,
	backdrop = true,

	color = tokens.color.input,
	hoverColor = tokens.color.hover,
	closeOnOutsideClick = false,
	menuWidth = 190,
	menuSide = "left",
	itemBgTransparency = 1,
	BackgroundTransparency = 0.5,
	menuPosition = function()
		local coordinates = theme.ExplorerCoordinates

		return UDim2.new(
			coordinates.Position.X.Scale,
			coordinates.Position.X.Offset - 196,
			coordinates.Position.Y.Scale,
			coordinates.Position.Y.Offset + 5 + UI.metrics.windowHeader + 6
		)
	end,

	maxVisibleItems = 10,
	itemHeight = UI.metrics.inputHeight,

	onChanged = function(className)
		local parent = selectedObject() or workspace

		local ok, object = pcall(Instance.new, className)

		if not ok or not object then
			return
		end

		object.Name = className
		object.Parent = parent

		expanded[parent] = true

		Selection:Set({
			object,
		})
	end,
})

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

local function treeHash(parent)
	local pieces = {}

	for _, child in ipairs(sortedChildren(parent)) do
		table.insert(pieces, child.Name .. ":" .. child.ClassName)

		if expanded[child] then
			table.insert(pieces, treeHash(child))
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
		Selection:Set({
			instance,
		})

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

	row.BackgroundTransparency = isSelected and 0 or 0.12

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

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape then
		Selection:Set({})
		return
	end

	if input.KeyCode == Enum.KeyCode.D then
		local ctrlDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

		if ctrlDown then
			local selected = selectedObject()

			if selected then
				local clone = selected:Clone()

				if clone then
					clone.Parent = selected.Parent

					Selection:Set({
						clone,
					})

					lastHash = ""
				end
			end
		end
	end
end)

rebuild()

renderer.Pool.new("2d", function()
	panel.Size = theme.ExplorerCoordinates.Size
	panel.Position = theme.ExplorerCoordinates.Position

	local selected = selectedObject()

	local hash = treeHash(game) .. "#" .. (selected and selected:GetFullName() or "")

	if hash ~= lastHash then
		lastHash = hash
		rebuild()
	end
end)
