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

local categories = {
	Name = "Object",
	Parent = "Object",
	Archivable = "Object",
	ClassName = "Object",

	Color = "Appearance",
	Transparency = "Appearance",
	Reflectance = "Appearance",
	Material = "Appearance",

	BackgroundColor3 = "Appearance",
	BackgroundTransparency = "Appearance",
	TextColor3 = "Appearance",
	TextTransparency = "Appearance",
	PlaceholderColor3 = "Appearance",
	CaretColor3 = "Appearance",
	SelectionColor3 = "Appearance",
	SelectionTransparency = "Appearance",
	FocusColor3 = "Appearance",
	Image = "Appearance",
	Visible = "Appearance",
	BorderSizePixel = "Appearance",

	CFrame = "Transform",
	Position = "Transform",
	Size = "Transform",
	Orientation = "Transform",
	AnchorPoint = "Transform",

	Anchored = "Behavior",
	CanCollide = "Behavior",
	CastShadow = "Behavior",
	Active = "Behavior",
	Selectable = "Behavior",
	ClipsDescendants = "Behavior",
	Enabled = "Behavior",
	Playing = "Behavior",
	Looped = "Behavior",
	TextEditable = "Behavior",
	ClearTextOnFocus = "Behavior",
	SelectAllOnFocus = "Behavior",

	Text = "Text",
	PlaceholderText = "Text",
	TextSize = "Text",
	MaxLength = "Text",

	Volume = "Sound",
	Pitch = "Sound",
	SoundId = "Sound",
}

local categoryOrder = {
	Object = 1,
	Transform = 2,
	Appearance = 3,
	Text = 4,
	Behavior = 5,
	Sound = 6,
	Uncategorized = 7,
}

local readonlyProperties = {
	ClassName = true,
	Parent = true,
	AbsolutePosition = true,
	AbsoluteSize = true,
	SelectedText = true,
	CFrame = true,
}

local panel, content =
	UI.window("Inspector", theme.InspectorCoordinates.Position, theme.InspectorCoordinates.Size, "Inspector")

local inset = UI.metrics.panelInset

local searchBox = UI.input(
	content,
	"Search Properties...",
	UDim2.fromOffset(inset, inset),
	UDim2.new(1, -inset * 2, 0, UI.metrics.inputHeight),
	{
		focusColor = tokens.color.focus,
		caretColor = tokens.color.accent,
		selectionColor = tokens.color.selection,
	}
)

local list = UI.create("ScrollingFrame", {
	Position = UDim2.fromOffset(inset, inset + UI.metrics.inputHeight + inset),

	Size = UDim2.new(1, -inset * 2, 1, -(inset * 3 + UI.metrics.inputHeight)),

	BackgroundColor3 = tokens.color.surface,
	BackgroundTransparency = 1,
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

local collapsed = {}
local activeEditors = {}

local lastSignature = ""
local rebuilding = false

local BUBBLE_GAP = 7
local CATEGORY_HEADER_HEIGHT = 26
local CATEGORY_PADDING_BOTTOM = 5
local PROPERTY_HEIGHT = UI.metrics.propertyRow
local PROPERTY_SIDE_INSET = 4

local function selectedObject()
	local selected = Selection:Get()
	return selected and selected[1]
end

local function propertyValue(object, property)
	local ok, value = pcall(function()
		return object[property]
	end)

	if ok then
		return value
	end

	return nil
end

local function includeInSignature(propertyName)
	return propertyName ~= "CFrame" and propertyName ~= "Position" and propertyName ~= "Orientation"
end

local function displayValue(value)
	if value == nil then
		return ""
	end

	local text = tostring(value)

	if #text > 25 then
		return string.sub(text, 1, 22) .. "..."
	end

	return text
end

local function propertiesFor(object)
	local names = {
		"Name",
		"ClassName",
		"Parent",
		"Archivable",
	}

	local seen = {
		Name = true,
		ClassName = true,
		Parent = true,
		Archivable = true,
	}

	local ok, reflected = pcall(function()
		return object:GetProperties()
	end)

	if ok and type(reflected) == "table" then
		for _, name in ipairs(reflected) do
			if not seen[name] then
				seen[name] = true
				table.insert(names, name)
			end
		end
	end

	return names
end

local function getSearchQuery()
	return string.lower(searchBox.Text or "")
end

local function propertyMatchesSearch(propertyName, value, query)
	if query == "" then
		return true
	end

	local name = string.lower(propertyName)
	local valueText = string.lower(displayValue(value))
	local datatype = string.lower(typeof(value))

	return string.find(name, query, 1, true) ~= nil
		or string.find(valueText, query, 1, true) ~= nil
		or string.find(datatype, query, 1, true) ~= nil
end

local function watchEditor(field, commit)
	table.insert(activeEditors, {
		field = field,
		commit = commit,
		wasFocused = false,
	})
end

local function updateEditors()
	for _, editor in ipairs(activeEditors) do
		local ok, focused = pcall(function()
			return editor.field:IsFocused()
		end)

		if not ok then
			continue
		end

		if editor.wasFocused and not focused then
			pcall(editor.commit)
		end

		editor.wasFocused = focused
	end
end

local function setProperty(object, propertyName, value)
	local ok = pcall(function()
		object[propertyName] = value
	end)

	if ok then
		lastSignature = ""
	end

	return ok
end

local openEnumDropdown = nil

local function closeEnumDropdown()
	if not openEnumDropdown then
		return
	end

	local popup = openEnumDropdown.popup
	openEnumDropdown = nil

	if popup then
		pcall(function()
			-- Purge any UI.button records owned by the popup before destroying it.
			UI.clear(popup)
			popup:Destroy()
		end)
	end
end

local function updateEnumDropdownPosition()
	local dropdown = openEnumDropdown

	if not dropdown then
		return
	end

	local ok = pcall(function()
		local field = dropdown.field
		local popup = dropdown.popup

		local position = field.AbsolutePosition
		local size = field.AbsoluteSize

		popup.Position = UDim2.fromOffset(position.X, position.Y + size.Y + 2)

		popup.Size = UDim2.fromOffset(math.max(size.X, 110), dropdown.height)
	end)

	if not ok then
		closeEnumDropdown()
	end
end

local function openEnumDropdownFor(field, object, property)
	if openEnumDropdown and openEnumDropdown.field == field then
		closeEnumDropdown()
		return
	end

	closeEnumDropdown()

	local value = property.value
	local enumType = value.EnumType

	if not enumType then
		return
	end

	local ok, items = pcall(function()
		return enumType:GetEnumItems()
	end)

	if not ok or type(items) ~= "table" or #items == 0 then
		return
	end

	local ITEM_HEIGHT = 22
	local MENU_PADDING = 3
	local MAX_VISIBLE_ITEMS = 7

	local visibleItems = math.min(#items, MAX_VISIBLE_ITEMS)

	local menuHeight = visibleItems * ITEM_HEIGHT + MENU_PADDING * 2

	local fieldPosition = field.AbsolutePosition

	local fieldSize = field.AbsoluteSize

	local popup = UI.create("ScrollingFrame", {
		Position = UDim2.fromOffset(fieldPosition.X, fieldPosition.Y + fieldSize.Y + 2),

		Size = UDim2.fromOffset(math.max(fieldSize.X, 110), menuHeight),

		BackgroundColor3 = tokens.color.panelRaised,

		BorderSizePixel = 0,

		CanvasPosition = Vector2.new(0, 0),

		CanvasSize = UDim2.fromOffset(0, #items * ITEM_HEIGHT + MENU_PADDING * 2),

		ScrollingEnabled = #items > MAX_VISIBLE_ITEMS,

		ScrollSpeed = 28,

		SmoothScrollingEnabled = true,
		ScrollSmoothness = 20,

		ScrollBarThickness = 4,

		ScrollBarImageColor3 = tokens.color.subtext,

		ScrollBarImageTransparency = 0.35,

		ScrollBarAutoHide = true,
		ScrollBarFadeDelay = 0.35,
		ScrollBarFadeSpeed = 14,
		ScrollBarMinimumHandleSize = 18,

		ClipsDescendants = true,

		Active = true,
		InputSink = true,

		ZIndex = 10000,
	}, UI.root())

	UI.corner(popup, tokens.radius.sm)

	UI.stroke(popup, tokens.color.borderStrong, 1, 0)

	for index, item in ipairs(items) do
		local selected = item == value

		local button = UI.button(
			popup,
			item.Name,
			UDim2.fromOffset(MENU_PADDING, MENU_PADDING + (index - 1) * ITEM_HEIGHT),
			UDim2.new(1, -MENU_PADDING * 2, 0, ITEM_HEIGHT),
			function()
				setProperty(object, property.name, item)

				closeEnumDropdown()
				lastSignature = ""
			end,
			{
				color = selected and tokens.color.selection or tokens.color.panelRaised,

				hoverColor = selected and tokens.color.selectionHover or tokens.color.hover,

				pressedColor = tokens.color.pressed,

				textColor = selected and tokens.color.text or tokens.color.subtext,

				textSize = tokens.type.caption,

				paddingX = 7,

				textY = 3,

				radius = tokens.radius.xs,

				border = false,
			}
		)

		button.ZIndex = 10001
	end

	openEnumDropdown = {
		field = field,
		popup = popup,
		height = menuHeight,
	}
end

-- Close the floating enum menu when clicking anywhere outside it.
UserInputService.InputBegan:Connect(function(event)
	if not openEnumDropdown then
		return
	end

	if event.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	local point = Vector2.new(event.Position.X, event.Position.Y)

	local dropdown = openEnumDropdown

	local insideField = false
	local insidePopup = false

	pcall(function()
		insideField = UI.pointInside(dropdown.field, point)

		insidePopup = UI.pointInside(dropdown.popup, point)
	end)

	if not insideField and not insidePopup then
		closeEnumDropdown()
	end
end)

local adapters = {}

local function registerAdapter(typeName, adapter)
	adapters[typeName] = adapter
end

local function formatNumber(value)
	if value == nil then
		return ""
	end

	if math.abs(value) < 0.000001 then
		value = 0
	end

	return string.format("%.6g", value)
end

local function valueField(row, text, options)
	options = options or {}

	return UI.input(
		row,
		options.placeholder or "",
		options.position or UDim2.new(0.45, 6, 0, 2),
		options.size or UDim2.new(0.55, -12, 0, 18),
		{
			text = tostring(text or ""),
			textColor = options.textColor or tokens.color.subtext,
			textSize = options.textSize or tokens.type.caption,
			textEditable = options.textEditable ~= false,
			focusColor = options.focusColor or tokens.color.accent,
			caretColor = options.caretColor or tokens.color.accent,
			selectionColor = options.selectionColor or tokens.color.selection,
			maxLength = options.maxLength,
			radius = options.radius or tokens.radius.xs,
		}
	)
end

local function readonlyField(row, value, options)
	options = options or {}

	options.textEditable = false
	options.textColor = options.textColor or tokens.color.muted

	return valueField(row, displayValue(value), options)
end

-- Each scalar has its own TextBox.
-- The component name is a separate label and is not part of TextBox.Text.
local function componentField(row, label, value, index, count, line)
	line = line or 0

	local totalScale = 0.55
	local slotScale = totalScale / count
	local xScale = 0.45 + slotScale * (index - 1)

	local y = 2 + line * PROPERTY_HEIGHT

	local labelWidth = 11

	if #label == 2 then
		labelWidth = 17
	elseif #label >= 3 then
		labelWidth = 23
	end

	UI.label(
		row,
		label,
		UDim2.new(xScale, 5, 0, y + 2),
		UDim2.fromOffset(labelWidth, 14),
		tokens.type.caption,
		tokens.color.muted
	)

	return valueField(row, formatNumber(value), {
		position = UDim2.new(xScale, 7 + labelWidth, 0, y),

		size = UDim2.new(slotScale, -(11 + labelWidth), 0, 18),
	})
end

local function parseComponent(text)
	return tonumber(text)
end

local function parseInteger(text)
	local value = tonumber(text)

	if value == nil or math.floor(value) ~= value then
		return nil
	end

	return value
end

local function watchValueField(field, object, propertyName, parser)
	watchEditor(field, function()
		local value = parser(field.Text)

		if value ~= nil then
			setProperty(object, propertyName, value)
		end
	end)
end

local function watchComponentFields(fields, object, propertyName, builder)
	for _, field in ipairs(fields) do
		watchEditor(field, function()
			local ok, value = pcall(builder)

			if ok and value ~= nil then
				setProperty(object, propertyName, value)
			end
		end)
	end
end

local function readonlyAdapter(height)
	return {
		height = height or PROPERTY_HEIGHT,

		render = function(row, object, property)
			return readonlyField(row, property.value)
		end,
	}
end

registerAdapter("nil", readonlyAdapter())

registerAdapter("string", {
	height = PROPERTY_HEIGHT,

	render = function(row, object, property)
		if readonlyProperties[property.name] then
			return readonlyField(row, property.value)
		end

		local field = valueField(row, property.value)

		watchValueField(field, object, property.name, function(text)
			return text
		end)

		return field
	end,
})

registerAdapter("number", {
	height = PROPERTY_HEIGHT,

	render = function(row, object, property)
		if readonlyProperties[property.name] then
			return readonlyField(row, property.value)
		end

		local field = valueField(row, formatNumber(property.value))

		watchValueField(field, object, property.name, tonumber)

		return field
	end,
})

registerAdapter("boolean", {
	height = PROPERTY_HEIGHT,

	render = function(row, object, property)
		local value = property.value

		if readonlyProperties[property.name] then
			return readonlyField(row, value and "true" or "false")
		end

		local checkbox = UI.button(
			row,
			value and "x" or "",
			UDim2.new(0.45, 7, 0, 3),
			UDim2.fromOffset(16, 16),
			function()
				setProperty(object, property.name, not value)
			end,
			{
				color = value and tokens.color.selection or tokens.color.input,

				hoverColor = value and tokens.color.selectionHover or tokens.color.hover,

				radius = tokens.radius.xs,
				paddingX = 4,
				textY = 0,
				textSize = tokens.type.caption,
				textColor = tokens.color.text,
			}
		)

		UI.label(
			row,
			value and "Enabled" or "Disabled",
			UDim2.new(0.45, 30, 0, 3),
			UDim2.new(0.55, -36, 0, 16),
			tokens.type.caption,
			colors.subtext
		)

		return checkbox
	end,
})

registerAdapter("EnumItem", {
	height = PROPERTY_HEIGHT,

	render = function(row, object, property)
		local value = property.value

		local field

		field = UI.button(row, value.Name, UDim2.new(0.45, 6, 0, 2), UDim2.new(0.55, -12, 0, 18), function()
			openEnumDropdownFor(field, object, property)
		end, {
			color = tokens.color.input,

			hoverColor = tokens.color.hover,

			pressedColor = tokens.color.pressed,

			textColor = tokens.color.subtext,

			textSize = tokens.type.caption,

			paddingX = 7,

			textY = 1,

			radius = tokens.radius.xs,

			border = true,

			borderColor = tokens.color.border,
		})

		UI.image(field, "builtin://icons/ArrowDown.svg", UDim2.new(1, -16, 0.5, -5), UDim2.fromOffset(10, 10))

		return field
	end,
})

registerAdapter("Instance", readonlyAdapter())

registerAdapter("Vector2", {
	height = PROPERTY_HEIGHT,

	render = function(row, object, property)
		if readonlyProperties[property.name] then
			return readonlyField(row, property.value)
		end

		local value = property.value

		local xField = componentField(row, "X", value.X, 1, 2)

		local yField = componentField(row, "Y", value.Y, 2, 2)

		watchComponentFields(
			{
				xField,
				yField,
			},
			object,
			property.name,
			function()
				local x = parseComponent(xField.Text)

				local y = parseComponent(yField.Text)

				if x == nil or y == nil then
					return nil
				end

				return Vector2.new(x, y)
			end
		)

		return xField
	end,
})

local vector3Adapter = {
	height = PROPERTY_HEIGHT,

	render = function(row, object, property)
		if readonlyProperties[property.name] then
			return readonlyField(row, property.value)
		end

		local value = property.value

		local xField = componentField(row, "X", value.X, 1, 3)

		local yField = componentField(row, "Y", value.Y, 2, 3)

		local zField = componentField(row, "Z", value.Z, 3, 3)

		watchComponentFields(
			{
				xField,
				yField,
				zField,
			},
			object,
			property.name,
			function()
				local x = parseComponent(xField.Text)

				local y = parseComponent(yField.Text)

				local z = parseComponent(zField.Text)

				if x == nil or y == nil or z == nil then
					return nil
				end

				return Vector3.new(x, y, z)
			end
		)

		return xField
	end,
}

registerAdapter("Vector3", vector3Adapter)

-- Kinemium uses Luau's native vector value for Vector3 in some paths.
registerAdapter("vector", vector3Adapter)

registerAdapter("UDim", {
	height = PROPERTY_HEIGHT,

	render = function(row, object, property)
		if readonlyProperties[property.name] then
			return readonlyField(row, property.value)
		end

		local value = property.value

		local scaleField = componentField(row, "S", value.Scale, 1, 2)

		local offsetField = componentField(row, "O", value.Offset, 2, 2)

		watchComponentFields(
			{
				scaleField,
				offsetField,
			},
			object,
			property.name,
			function()
				local scale = parseComponent(scaleField.Text)

				local offset = parseComponent(offsetField.Text)

				if scale == nil or offset == nil then
					return nil
				end

				return UDim.new(scale, offset)
			end
		)

		return scaleField
	end,
})

registerAdapter("UDim2", {
	height = PROPERTY_HEIGHT * 2,

	render = function(row, object, property)
		if readonlyProperties[property.name] then
			return readonlyField(row, property.value)
		end

		local value = property.value

		local xs = componentField(row, "XS", value.X.Scale, 1, 2, 0)

		local xo = componentField(row, "XO", value.X.Offset, 2, 2, 0)

		local ys = componentField(row, "YS", value.Y.Scale, 1, 2, 1)

		local yo = componentField(row, "YO", value.Y.Offset, 2, 2, 1)

		watchComponentFields(
			{
				xs,
				xo,
				ys,
				yo,
			},
			object,
			property.name,
			function()
				local xScale = parseComponent(xs.Text)

				local xOffset = parseComponent(xo.Text)

				local yScale = parseComponent(ys.Text)

				local yOffset = parseComponent(yo.Text)

				if xScale == nil or xOffset == nil or yScale == nil or yOffset == nil then
					return nil
				end

				return UDim2.new(xScale, xOffset, yScale, yOffset)
			end
		)

		return xs
	end,
})

registerAdapter("Color3", {
	height = PROPERTY_HEIGHT,

	render = function(row, object, property)
		local value = property.value

		local swatch = UI.frame(row, UDim2.new(0.45, -21, 0, 3), UDim2.fromOffset(16, 16), value, tokens.radius.xs)

		UI.stroke(swatch, tokens.color.borderStrong, 1, 0)

		if readonlyProperties[property.name] then
			return readonlyField(row, string.format("%.3f, %.3f, %.3f", value.R, value.G, value.B))
		end

		local rField = componentField(row, "R", value.R, 1, 3)

		local gField = componentField(row, "G", value.G, 2, 3)

		local bField = componentField(row, "B", value.B, 3, 3)

		watchComponentFields(
			{
				rField,
				gField,
				bField,
			},
			object,
			property.name,
			function()
				local r = parseComponent(rField.Text)

				local g = parseComponent(gField.Text)

				local b = parseComponent(bField.Text)

				if r == nil or g == nil or b == nil then
					return nil
				end

				return Color3.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1))
			end
		)

		return rField
	end,
})

registerAdapter("Quaternion", {
	height = PROPERTY_HEIGHT,

	render = function(row, object, property)
		if readonlyProperties[property.name] then
			return readonlyField(row, property.value)
		end

		local value = property.value

		local x = componentField(row, "X", value.X, 1, 4)

		local y = componentField(row, "Y", value.Y, 2, 4)

		local z = componentField(row, "Z", value.Z, 3, 4)

		local w = componentField(row, "W", value.W, 4, 4)

		watchComponentFields(
			{
				x,
				y,
				z,
				w,
			},
			object,
			property.name,
			function()
				local xv = parseComponent(x.Text)

				local yv = parseComponent(y.Text)

				local zv = parseComponent(z.Text)

				local wv = parseComponent(w.Text)

				if xv == nil or yv == nil or zv == nil or wv == nil then
					return nil
				end

				return Quaternion.new(xv, yv, zv, wv)
			end
		)

		return x
	end,
})

registerAdapter("CFrame", {
	height = PROPERTY_HEIGHT * 4,

	render = function(row, object, property)
		if readonlyProperties[property.name] then
			return readonlyField(row, property.value)
		end

		local value = property.value

		local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()

		local fields = {
			componentField(row, "X", px, 1, 3, 0),

			componentField(row, "Y", py, 2, 3, 0),

			componentField(row, "Z", pz, 3, 3, 0),

			componentField(row, "R00", r00, 1, 3, 1),

			componentField(row, "R01", r01, 2, 3, 1),

			componentField(row, "R02", r02, 3, 3, 1),

			componentField(row, "R10", r10, 1, 3, 2),

			componentField(row, "R11", r11, 2, 3, 2),

			componentField(row, "R12", r12, 3, 3, 2),

			componentField(row, "R20", r20, 1, 3, 3),

			componentField(row, "R21", r21, 2, 3, 3),

			componentField(row, "R22", r22, 3, 3, 3),
		}

		watchComponentFields(fields, object, property.name, function()
			local values = {}

			for index, field in ipairs(fields) do
				values[index] = parseComponent(field.Text)

				if values[index] == nil then
					return nil
				end
			end

			return CFrame.new(
				values[1],
				values[2],
				values[3],
				values[4],
				values[5],
				values[6],
				values[7],
				values[8],
				values[9],
				values[10],
				values[11],
				values[12]
			)
		end)

		return fields[1]
	end,
})

registerAdapter("Vector3int16", {
	height = PROPERTY_HEIGHT,

	render = function(row, object, property)
		if readonlyProperties[property.name] then
			return readonlyField(row, property.value)
		end

		local value = property.value

		local x = componentField(row, "X", value.X, 1, 3)

		local y = componentField(row, "Y", value.Y, 2, 3)

		local z = componentField(row, "Z", value.Z, 3, 3)

		watchComponentFields(
			{
				x,
				y,
				z,
			},
			object,
			property.name,
			function()
				local xv = parseInteger(x.Text)

				local yv = parseInteger(y.Text)

				local zv = parseInteger(z.Text)

				if xv == nil or yv == nil or zv == nil then
					return nil
				end

				if xv < -32768 or xv > 32767 or yv < -32768 or yv > 32767 or zv < -32768 or zv > 32767 then
					return nil
				end

				return Vector3int16.new(xv, yv, zv)
			end
		)

		return x
	end,
})

registerAdapter("NumberRange", {
	height = PROPERTY_HEIGHT,

	render = function(row, object, property)
		if readonlyProperties[property.name] then
			return readonlyField(row, property.value)
		end

		local value = property.value

		local minField = componentField(row, "Min", value.Min, 1, 2)

		local maxField = componentField(row, "Max", value.Max, 2, 2)

		watchComponentFields(
			{
				minField,
				maxField,
			},
			object,
			property.name,
			function()
				local minimum = parseComponent(minField.Text)

				local maximum = parseComponent(maxField.Text)

				if minimum == nil or maximum == nil or minimum > maximum then
					return nil
				end

				return NumberRange.new(minimum, maximum)
			end
		)

		return minField
	end,
})

registerAdapter("Color4", readonlyAdapter())

registerAdapter("CFrameint16", readonlyAdapter())

registerAdapter("Region3", readonlyAdapter())

registerAdapter("Region3int16", readonlyAdapter())

registerAdapter("BrickColor", readonlyAdapter())

registerAdapter("NumberSequence", readonlyAdapter())

registerAdapter("ColorSequence", readonlyAdapter())

registerAdapter("TweenInfo", readonlyAdapter())

registerAdapter("PhysicalProperties", readonlyAdapter())

registerAdapter("Ray", readonlyAdapter())

registerAdapter("Rect", readonlyAdapter())

registerAdapter("Axes", readonlyAdapter())

registerAdapter("Faces", readonlyAdapter())

registerAdapter("DateTime", readonlyAdapter())

registerAdapter("Signal", readonlyAdapter())

registerAdapter("Promise", readonlyAdapter())

registerAdapter("table", readonlyAdapter())

registerAdapter("function", readonlyAdapter())

registerAdapter("thread", readonlyAdapter())

registerAdapter("userdata", readonlyAdapter())

local fallbackAdapter = readonlyAdapter()

local function adapterFor(value)
	local datatype = typeof(value)

	return adapters[datatype] or fallbackAdapter, datatype
end

local function propertyEditorHeight(property)
	local adapter = adapterFor(property.value)

	return adapter.height or PROPERTY_HEIGHT
end

local function renderPropertyAdapter(row, object, property)
	local adapter = adapterFor(property.value)

	return adapter.render(row, object, property)
end

local function createCategoryBubble(parent, object, category, group, y)
	local isCollapsed = collapsed[category] == true

	local propertyCount = #group

	local bubbleHeight = CATEGORY_HEADER_HEIGHT

	if not isCollapsed then
		for _, property in ipairs(group) do
			bubbleHeight += propertyEditorHeight(property)
		end

		bubbleHeight += CATEGORY_PADDING_BOTTOM
	end

	local bubble = UI.group(parent, UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, bubbleHeight), {
		color = tokens.color.panel,
		radius = tokens.radius.md,
	})

	bubble.Name = category .. "Category"

	bubble.ClipsDescendants = true

	UI.stroke(bubble, tokens.color.border, 1, 0)

	local header = UI.button(
		bubble,
		category,
		UDim2.fromOffset(0, 0),
		UDim2.new(1, 0, 0, CATEGORY_HEADER_HEIGHT),
		function()
			collapsed[category] = not collapsed[category]

			lastSignature = ""
		end,
		{
			color = tokens.color.panelRaised,
			hoverColor = tokens.color.hover,
			textSize = tokens.type.small,
			textColor = tokens.color.text,
			textY = 4,
			paddingX = 27,
			radius = tokens.radius.md,
			border = false,
		}
	)

	header.Name = "Header"

	UI.image(
		header,
		"builtin://icons/" .. (isCollapsed and "ArrowRight.svg" or "ArrowDown.svg"),
		UDim2.fromOffset(9, math.floor((CATEGORY_HEADER_HEIGHT - 11) / 2)),
		UDim2.fromOffset(11, 11)
	)

	UI.label(
		header,
		tostring(propertyCount),
		UDim2.new(1, -38, 0, 4),
		UDim2.fromOffset(28, 17),
		tokens.type.caption,
		tokens.color.muted
	)

	if isCollapsed then
		return bubbleHeight
	end

	UI.separator(bubble, UDim2.fromOffset(0, CATEGORY_HEADER_HEIGHT), UDim2.new(1, 0, 0, 1), tokens.color.border)

	local rowY = CATEGORY_HEADER_HEIGHT + 1

	for index, property in ipairs(group) do
		local propertyHeight = propertyEditorHeight(property)

		local rowColor = index % 2 == 0 and tokens.color.rowEven or tokens.color.rowOdd

		local row = UI.frame(
			bubble,
			UDim2.fromOffset(PROPERTY_SIDE_INSET, rowY),
			UDim2.new(1, -PROPERTY_SIDE_INSET * 2, 0, propertyHeight),
			rowColor,
			tokens.radius.xs
		)

		row.Name = property.name

		UI.label(
			row,
			property.name,
			UDim2.fromOffset(7, 3),
			UDim2.new(0.45, -8, 0, 17),
			tokens.type.caption,
			colors.subtext
		)

		UI.separator(
			row,
			UDim2.new(0.45, 0, 0, 3),
			UDim2.new(0, 1, 0, math.max(1, propertyHeight - 6)),
			tokens.color.border
		)

		renderPropertyAdapter(row, object, property)

		rowY += propertyHeight
	end

	return bubbleHeight
end

local function setListCanvasHeight(height)
	list.CanvasSize = UDim2.new(1, 0, 0, math.max(height, list.AbsoluteSize.Y))
end

local function createEmptyMessage(text)
	local empty = UI.group(list, UDim2.fromOffset(0, 0), UDim2.new(1, -8, 0, 44), {
		color = tokens.color.panel,
		radius = tokens.radius.md,
	})

	UI.stroke(empty, tokens.color.border, 1, 0)

	UI.label(empty, text, UDim2.fromOffset(10, 12), UDim2.new(1, -20, 0, 20), tokens.type.small, colors.subtext)

	setListCanvasHeight(48)
end

local function rebuild()
	if rebuilding then
		return
	end

	rebuilding = true

	closeEnumDropdown()

	local oldCanvasPosition = list.CanvasPosition

	activeEditors = {}

	UI.clear(list)

	local object = selectedObject()

	if not object then
		createEmptyMessage("Select an object to inspect.")

		list.CanvasPosition = Vector2.new(oldCanvasPosition.X, 0)

		rebuilding = false
		return
	end

	local searchQuery = getSearchQuery()

	local grouped = {}

	for _, name in ipairs(propertiesFor(object)) do
		local value = propertyValue(object, name)

		if propertyMatchesSearch(name, value, searchQuery) then
			local category = categories[name] or "Uncategorized"

			grouped[category] = grouped[category] or {}

			table.insert(grouped[category], {
				name = name,
				value = value,
				datatype = typeof(value),
			})
		end
	end

	if next(grouped) == nil then
		createEmptyMessage("No matching properties.")

		list.CanvasPosition = Vector2.new(oldCanvasPosition.X, 0)

		rebuilding = false
		return
	end

	local groupNames = {}

	for category in pairs(grouped) do
		table.insert(groupNames, category)
	end

	table.sort(groupNames, function(a, b)
		local aOrder = categoryOrder[a] or 99

		local bOrder = categoryOrder[b] or 99

		if aOrder == bOrder then
			return a < b
		end

		return aOrder < bOrder
	end)

	local y = 1

	for _, category in ipairs(groupNames) do
		local group = grouped[category]

		table.sort(group, function(a, b)
			return a.name < b.name
		end)

		local height = createCategoryBubble(list, object, category, group, y)

		y += height + BUBBLE_GAP
	end

	setListCanvasHeight(y + inset)

	list.CanvasPosition = oldCanvasPosition

	rebuilding = false
end

Selection.SelectionChanged:Connect(function()
	lastSignature = ""
end)

renderer.Pool.new("2d", function()
	panel.Size = theme.InspectorCoordinates.Size

	panel.Position = theme.InspectorCoordinates.Position

	updateEditors()
	updateEnumDropdownPosition()

	local object = selectedObject()

	local searchQuery = getSearchQuery()

	local pieces = {
		object and object:GetFullName() or "none",

		"search=" .. searchQuery,
	}

	if object then
		for _, property in ipairs(propertiesFor(object)) do
			if includeInSignature(property) then
				local value = propertyValue(object, property)
				table.insert(pieces, property .. ":" .. typeof(value) .. "=" .. displayValue(value))
			end
		end
	end

	local signature = table.concat(pieces, "|")

	if signature ~= lastSignature then
		lastSignature = signature

		rebuild()
	end
end)
