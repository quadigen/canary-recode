local UI = {}

local StudioThemeService = game:GetService("StudioThemeService")

UI.tokens = {
	color = {
		canvas = Color3.new(
			StudioThemeService.SelectedTheme.BaseColor.R,
			StudioThemeService.SelectedTheme.BaseColor.G,
			StudioThemeService.SelectedTheme.BaseColor.B
		),
		panel = Color3.new(
			StudioThemeService.SelectedTheme.BgColor.R,
			StudioThemeService.SelectedTheme.BgColor.G,
			StudioThemeService.SelectedTheme.BgColor.B
		),
		panelRaised = Color3.new(
			StudioThemeService.SelectedTheme.SecondaryColor.R,
			StudioThemeService.SelectedTheme.SecondaryColor.G,
			StudioThemeService.SelectedTheme.SecondaryColor.B
		),
		surface = Color3.new(
			StudioThemeService.SelectedTheme.ThirdColor.R,
			StudioThemeService.SelectedTheme.ThirdColor.G,
			StudioThemeService.SelectedTheme.ThirdColor.B
		),
		surfaceAlt = Color3.new(
			StudioThemeService.SelectedTheme.SecondaryColor.R,
			StudioThemeService.SelectedTheme.SecondaryColor.G,
			StudioThemeService.SelectedTheme.SecondaryColor.B
		),

		rowEven = Color3.new(
			StudioThemeService.SelectedTheme.AlternatingColor1.R,
			StudioThemeService.SelectedTheme.AlternatingColor1.G,
			StudioThemeService.SelectedTheme.AlternatingColor1.B
		),
		rowOdd = Color3.new(
			StudioThemeService.SelectedTheme.AlternatingColor2.R,
			StudioThemeService.SelectedTheme.AlternatingColor2.G,
			StudioThemeService.SelectedTheme.AlternatingColor2.B
		),

		hover = Color3.new(
			StudioThemeService.SelectedTheme.SecondaryColor.R,
			StudioThemeService.SelectedTheme.SecondaryColor.G,
			StudioThemeService.SelectedTheme.SecondaryColor.B
		),
		pressed = Color3.new(
			StudioThemeService.SelectedTheme.ThirdColor.R,
			StudioThemeService.SelectedTheme.ThirdColor.G,
			StudioThemeService.SelectedTheme.ThirdColor.B
		),

		input = Color3.new(
			StudioThemeService.SelectedTheme.InputColor.R,
			StudioThemeService.SelectedTheme.InputColor.G,
			StudioThemeService.SelectedTheme.InputColor.B
		),

		border = Color3.new(
			StudioThemeService.SelectedTheme.SecondaryColor.R,
			StudioThemeService.SelectedTheme.SecondaryColor.G,
			StudioThemeService.SelectedTheme.SecondaryColor.B
		),
		borderStrong = Color3.new(
			StudioThemeService.SelectedTheme.InputFocusColor.R,
			StudioThemeService.SelectedTheme.InputFocusColor.G,
			StudioThemeService.SelectedTheme.InputFocusColor.B
		),

		text = Color3.new(
			StudioThemeService.SelectedTheme.TextColor.R,
			StudioThemeService.SelectedTheme.TextColor.G,
			StudioThemeService.SelectedTheme.TextColor.B
		),
		subtext = Color3.new(
			StudioThemeService.SelectedTheme.SecondaryTextColor.R,
			StudioThemeService.SelectedTheme.SecondaryTextColor.G,
			StudioThemeService.SelectedTheme.SecondaryTextColor.B
		),
		muted = Color3.new(
			StudioThemeService.SelectedTheme.TextColorDimmed.R,
			StudioThemeService.SelectedTheme.TextColorDimmed.G,
			StudioThemeService.SelectedTheme.TextColorDimmed.B
		),

		accent = Color3.new(
			StudioThemeService.SelectedTheme.AccentColor.R,
			StudioThemeService.SelectedTheme.AccentColor.G,
			StudioThemeService.SelectedTheme.AccentColor.B
		),
		accentSoft = Color3.new(
			StudioThemeService.SelectedTheme.SecondaryColor.R,
			StudioThemeService.SelectedTheme.SecondaryColor.G,
			StudioThemeService.SelectedTheme.SecondaryColor.B
		),

		selection = Color3.new(
			StudioThemeService.SelectedTheme.AccentColor.R,
			StudioThemeService.SelectedTheme.AccentColor.G,
			StudioThemeService.SelectedTheme.AccentColor.B
		),
		selectionHover = Color3.new(
			StudioThemeService.SelectedTheme.AccentColor.R,
			StudioThemeService.SelectedTheme.AccentColor.G,
			StudioThemeService.SelectedTheme.AccentColor.B
		),
		focus = Color3.new(
			StudioThemeService.SelectedTheme.InputFocusColor.R,
			StudioThemeService.SelectedTheme.InputFocusColor.G,
			StudioThemeService.SelectedTheme.InputFocusColor.B
		),

		warning = Color3.fromRGB(224, 168, 74),
		error = Color3.fromRGB(231, 91, 91),
		success = Color3.fromRGB(81, 184, 122),
	},
	space = { xs = 3, sm = 5, md = 8, lg = 12 },
	radius = { xs = 3, sm = 4, md = 6 },
	type = { caption = 11, small = 12, body = 13, title = 14 },
}

local function findContainingWindow(gui)
	local current = gui

	while current do
		for _, window in pairs(shared.windows) do
			if current == window then
				return window
			end
		end

		current = current.Parent
	end

	return nil
end

UI.metrics = {
	windowHeader = 27,
	buttonHeight = 24,
	inputHeight = 24,
	tabHeight = 28,
	toolbarButton = 30,
	treeRow = 20,
	propertyRow = 22,
	sectionRow = 23,
	panelInset = 6,
}

UI.colors = {
	base = UI.tokens.color.canvas,
	panel = UI.tokens.color.panel,
	secondary = UI.tokens.color.panelRaised,
	hover = UI.tokens.color.hover,
	pressed = UI.tokens.color.pressed,
	input = UI.tokens.color.input,
	line = UI.tokens.color.border,
	text = UI.tokens.color.text,
	subtext = UI.tokens.color.subtext,
	muted = UI.tokens.color.muted,
	accent = UI.tokens.color.accent,
	selection = UI.tokens.color.selection,
	warning = UI.tokens.color.warning,
	error = UI.tokens.color.error,
}

local shared = ishared.NativeEditorUI
if not shared then
	shared = { buttons = {}, root = nil, background = nil, inputInstalled = false, windows = {} }
	ishared.NativeEditorUI = shared
end

local function assign(object, properties)
	for key, value in pairs(properties or {}) do
		local ok, message = pcall(function()
			object[key] = value
		end)
		if not ok then
			error(object.ClassName .. "." .. key .. ": " .. tostring(message))
		end
	end
	return object
end

function UI.create(className, properties, parent)
	local object = Instance.new(className)
	assign(object, properties)
	if parent then
		object.Parent = parent
	end
	return object
end

function UI.corner(parent, radius)
	return UI.create("UICorner", { CornerRadius = UDim.new(0, radius or UI.tokens.radius.sm) }, parent)
end

function UI.stroke(parent, color, thickness, transparency)
	return UI.create("UIStroke", {
		Color = color or UI.tokens.color.border,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
	}, parent)
end

function UI.frame(parent, position, size, color, radius)
	local frame = UI.create("Frame", {
		Position = position or UDim2.fromOffset(0, 0),
		Size = size or UDim2.fromOffset(100, 100),
		BackgroundColor3 = color or UI.tokens.color.panel,
		BorderSizePixel = 0,
	}, parent)
	if radius and radius > 0 then
		UI.corner(frame, radius)
	end
	return frame
end

function UI.label(parent, text, position, size, textSize, color)
	return UI.create("TextLabel", {
		Text = tostring(text or ""),
		Position = position or UDim2.fromOffset(0, 0),
		Size = size or UDim2.fromOffset(100, 20),
		BackgroundTransparency = 1,
		TextSize = textSize or UI.tokens.type.body,
		TextColor3 = color or UI.tokens.color.text,
		BorderSizePixel = 0,
	}, parent)
end

function UI.image(parent, path, position, size)
	return UI.create("ImageLabel", {
		Image = path,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)
end

function UI.clear(parent, keep)
	for _, child in ipairs(parent:GetChildren()) do
		local decoration = child:IsA("UICorner")
			or child:IsA("UIStroke")
			or child:IsA("UIShadow")
			or child:IsA("UIBackdrop")
		if not decoration and (not keep or not keep[child]) then
			local retained = {}
			for _, item in ipairs(shared.buttons) do
				if item.gui ~= child and not item.gui:IsDescendantOf(child) then
					table.insert(retained, item)
				end
			end
			shared.buttons = retained
			child:Destroy()
		end
	end
end

local function pointInside(gui, point)
	local position, size = gui.AbsolutePosition, gui.AbsoluteSize
	return position
		and size
		and point.X >= position.X
		and point.Y >= position.Y
		and point.X <= position.X + size.X
		and point.Y <= position.Y + size.Y
end
UI.pointInside = pointInside

local function installInput()
	if shared.inputInstalled then
		return
	end
	shared.inputInstalled = true
	local input = game:GetService("UserInputService")
	input.InputBegan:Connect(function(event)
		if event.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local point = Vector2.new(event.Position.X, event.Position.Y)
		for index = #shared.buttons, 1, -1 do
			local item = shared.buttons[index]
			if item.gui and item.gui.Visible and item.enabled and pointInside(item.gui, point) then
				item.gui.BackgroundColor3 = item.pressedColor
				item.callback()
				return
			end
		end
	end)
	input.InputEnded:Connect(function(event)
		if event.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		for _, item in ipairs(shared.buttons) do
			if item.gui then
				item.gui.BackgroundColor3 = item.color
			end
		end
	end)
	input.InputChanged:Connect(function(event)
		if event.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		local point = Vector2.new(event.Position.X, event.Position.Y)
		for _, item in ipairs(shared.buttons) do
			if item.gui then
				item.gui.BackgroundColor3 = item.enabled and pointInside(item.gui, point) and item.hoverColor
					or item.color
			end
		end
	end)
end

function UI.setButtonState(record, state)
	if not record then
		return
	end
	local colors = UI.tokens.color
	if state == "selected" then
		record.color, record.hoverColor = colors.selection, colors.selectionHover
	elseif state == "accent" then
		record.color, record.hoverColor = colors.accentSoft, colors.accent
	else
		record.color, record.hoverColor = record.defaultColor, record.defaultHoverColor
	end
	record.gui.BackgroundColor3 = record.color
end

function UI.button(parent, text, position, size, callback, options)
	options = options or {}
	local colors, padding = UI.tokens.color, options.paddingX or UI.tokens.space.md
	local color = options.color or colors.panelRaised
	local button = UI.frame(parent, position, size, color, options.radius or UI.tokens.radius.sm)

	button.Active, button.InputSink = true, true

	local label = UI.label(
		button,
		text,
		UDim2.fromOffset(padding, options.textY or 3),
		UDim2.new(1, -padding * 2, 1, -(options.textY or 3)),
		options.textSize or UI.tokens.type.small,
		options.textColor or colors.subtext
	)
	if options.icon then
		local iconSize = options.iconSize or 16
		UI.image(
			button,
			options.icon,
			UDim2.fromOffset(6, math.floor((size.Y.Offset - iconSize) / 2)),
			UDim2.fromOffset(iconSize, iconSize)
		)
		label.Position = UDim2.fromOffset(iconSize + 12, options.textY or 3)
	end
	if options.border ~= false then
		UI.stroke(button, options.borderColor or colors.border, 1, options.borderTransparency or 0)
	end
	local record = {
		gui = button,
		callback = callback or function() end,
		color = color,
		defaultColor = color,
		hoverColor = options.hoverColor or colors.hover,
		defaultHoverColor = options.hoverColor or colors.hover,
		pressedColor = options.pressedColor or colors.pressed,
		enabled = options.enabled ~= false,
	}
	table.insert(shared.buttons, record)
	installInput()
	if options.selected then
		UI.setButtonState(record, "selected")
	end
	return button, label, record
end

function UI.iconButton(parent, icon, position, size, callback, options)
	options = options or {}
	local button, _, record = UI.button(parent, "", position, size, callback, options)
	local iconSize = options.iconSize or 16
	UI.image(
		button,
		icon,
		UDim2.new(0.5, -math.floor(iconSize / 2), 0.5, -math.floor(iconSize / 2)),
		UDim2.fromOffset(iconSize, iconSize)
	)
	return button, record
end

function UI.separator(parent, position, size, color)
	return UI.frame(parent, position, size, color or UI.tokens.color.border)
end

function UI.group(parent, position, size, options)
	options = options or {}
	local group = UI.frame(
		parent,
		position,
		size,
		options.color or UI.tokens.color.surface,
		options.radius or UI.tokens.radius.md
	)
	group.ClipsDescendants = true
	return group
end

function UI.tab(parent, text, position, size, selected, callback)
	local colors = UI.tokens.color
	local button, label, record = UI.button(parent, text, position, size, callback, {
		color = selected and colors.surfaceAlt or colors.panel,
		hoverColor = colors.hover,
		textColor = selected and colors.text or colors.subtext,
		textSize = UI.tokens.type.small,
		radius = 0,
		border = false,
		paddingX = UI.tokens.space.md,
	})
	if selected then
		UI.frame(button, UDim2.new(0, 5, 1, -2), UDim2.new(1, -10, 0, 2), colors.accent, 1)
	end
	return button, label, record
end

function UI.window(name, position, size, title, options)
	options = options or {}

	local colors = UI.tokens.color
	local headerHeight = options.headerHeight or UI.metrics.windowHeader

	--
	-- Outer window
	--

	local panel = UI.frame(UI.root(), position, size, colors.panel, options.radius or UI.tokens.radius.md)

	panel.Name = name
	panel.ClipsDescendants = false

	shared.windows[string.lower(name)] = panel

	--
	-- Optional backdrop blur
	--

	if options.backdrop == true then
		UI.create("UIBackdrop", {
			Enabled = true,

			BlurRadius = options.backdropBlur or 16,

			TintColor3 = options.backdropColor or colors.panel,

			TintTransparency = options.backdropTransparency or 0.78,
		}, panel)

		panel.BackgroundTransparency = options.panelTransparency or 0.08
	end

	--
	-- Main border
	--

	local border = UI.stroke(
		panel,
		options.borderColor or colors.borderStrong,
		options.borderThickness or 1,
		options.borderTransparency or 0.35
	)

	--
	-- Header
	--

	local header = UI.frame(
		panel,
		UDim2.fromOffset(0, 0),
		UDim2.new(1, 0, 0, headerHeight),
		options.headerColor or colors.panelRaised,
		options.radius or UI.tokens.radius.md
	)

	header.Name = "Header"
	header.ClipsDescendants = true

	--
	-- Header bottom fill
	--
	-- This covers the lower rounded corners so only the top of
	-- the titlebar looks rounded.
	--

	UI.frame(
		header,
		UDim2.new(0, 0, 1, -(options.radius or UI.tokens.radius.md)),
		UDim2.new(1, 0, 0, options.radius or UI.tokens.radius.md),
		options.headerColor or colors.panelRaised
	)

	--
	-- Accent marker
	--

	local accentWidth = options.accentWidth or 3

	UI.frame(
		header,
		UDim2.fromOffset(0, 6),
		UDim2.fromOffset(accentWidth, headerHeight - 12),
		options.accentColor or colors.accent,
		1
	)

	--
	-- Title
	--

	local titleLabel = UI.label(
		header,
		title or name,
		UDim2.fromOffset(10, 4),
		UDim2.new(1, options.closable and -44 or -20, 0, headerHeight - 7),
		options.titleSize or UI.tokens.type.body,
		options.titleColor or colors.text
	)

	titleLabel.Name = "Title"

	--
	-- Optional close button
	--

	local closeButton = nil

	if options.closable then
		closeButton = UI.iconButton(
			header,
			options.closeIcon or "C:/Users/devco/Documents/canary-recode/src/engine/assets/images/icons/Close.svg",
			UDim2.new(1, -27, 0, 4),
			UDim2.fromOffset(22, 19),
			function()
				if options.onClose then
					options.onClose(panel)
				else
					panel.Visible = false
				end
			end,
			{
				color = colors.panelRaised,

				hoverColor = options.closeHoverColor or colors.hover,

				pressedColor = colors.pressed,

				iconSize = 11,

				radius = UI.tokens.radius.sm,

				border = false,
			}
		)
	end

	--
	-- Header subtle bottom highlight
	--

	UI.frame(header, UDim2.new(0, 8, 1, -1), UDim2.new(1, -16, 0, 1), colors.border)

	--
	-- Content
	--

	local content = UI.frame(
		panel,
		UDim2.fromOffset(0, headerHeight),
		UDim2.new(1, 0, 1, -headerHeight),
		options.contentColor or colors.panel
	)

	content.Name = "Content"
	content.ClipsDescendants = true

	--
	-- Inner top separator
	--

	UI.frame(content, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 1), colors.border)

	--
	-- Keep the outer window rounded while allowing
	-- descendants to be clipped by this inner container.
	--

	local clip = UI.frame(
		panel,
		UDim2.fromOffset(0, 0),
		UDim2.new(1, 0, 1, 0),
		colors.panel,
		options.radius or UI.tokens.radius.md
	)

	clip.Name = "WindowClip"
	clip.BackgroundTransparency = 1
	clip.InputSink = false
	clip.Selectable = false

	--
	-- Return exactly the same first three values as before.
	--
	-- Extra values are optional for callers that want them.
	--

	return panel,
		content,
		header,
		{
			title = titleLabel,
			closeButton = closeButton,
			border = border,
			clip = clip,
		}
end

function UI.toggleWindow(name)
	local window = shared.windows[string.lower(name)]
	if window then
		window.Visible = not window.Visible
	end
end

function UI.input(parent, placeholder, position, size, options)
	options = options or {}

	local field = UI.create("TextBox", {
		Position = position or UDim2.fromOffset(0, 0),
		Size = size or UDim2.fromOffset(100, UI.metrics.inputHeight),

		BackgroundColor3 = options.color or UI.tokens.color.input,
		BorderSizePixel = 0,

		Text = options.text or "",
		PlaceholderText = tostring(placeholder or ""),

		TextSize = options.textSize or UI.tokens.type.small,
		TextColor3 = options.textColor or UI.tokens.color.text,
		PlaceholderColor3 = options.placeholderColor or UI.tokens.color.muted,

		TextTransparency = options.textTransparency or 0,

		TextEditable = options.textEditable ~= false,
		ClearTextOnFocus = options.clearTextOnFocus == true,
		SelectAllOnFocus = options.selectAllOnFocus == true,

		MaxLength = options.maxLength or -1,

		CaretColor3 = options.caretColor or UI.tokens.color.accent,
		SelectionColor3 = options.selectionColor or UI.tokens.color.selection,
		SelectionTransparency = options.selectionTransparency or 0.65,
		FocusColor3 = options.focusColor or UI.tokens.color.focus,

		Active = true,
		InputSink = true,
	}, parent)

	UI.corner(field, options.radius or UI.tokens.radius.sm)

	local stroke = UI.stroke(
		field,
		options.borderColor or UI.tokens.color.border,
		options.strokeThickness or 1,
		options.strokeTransparency or 0
	)

	return field, field, stroke
end

local function removeButtonRecords(gui)
	local retained = {}

	for _, item in ipairs(shared.buttons) do
		if item.gui and item.gui ~= gui and not item.gui:IsDescendantOf(gui) then
			table.insert(retained, item)
		end
	end

	shared.buttons = retained
end

local function closeActiveDropdown()
	local active = shared.activeDropdown

	if not active then
		return
	end

	shared.activeDropdown = nil

	if active.menu then
		removeButtonRecords(active.menu)
		active.menu:Destroy()
	end
end

local function installDropdownDismiss()
	if shared.dropdownDismissInstalled then
		return
	end

	shared.dropdownDismissInstalled = true

	local input = game:GetService("UserInputService")

	input.InputBegan:Connect(function(event)
		if event.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		local active = shared.activeDropdown

		if not active then
			return
		end

		local point = Vector2.new(event.Position.X, event.Position.Y)

		if pointInside(active.button, point) then
			return
		end

		if active.menu and pointInside(active.menu, point) then
			return
		end

		closeActiveDropdown()
	end)
end

function UI.dropdown(parent, value, position, size, chevronIcon, options)
	options = options or {}

	local colors = UI.tokens.color

	local currentValue = value
	local items = options.items or {}

	local button
	local label
	local record

	local controller = {}

	button, label, record = UI.button(
		parent,
		tostring(options.format and options.format(value) or value or ""),
		position,
		size or UDim2.fromOffset(140, UI.metrics.inputHeight),

		function()
			if shared.activeDropdown and shared.activeDropdown.controller == controller then
				closeActiveDropdown()
				return
			end

			closeActiveDropdown()

			local absolutePosition = button.AbsolutePosition
			local absoluteSize = button.AbsoluteSize

			if not absolutePosition or not absoluteSize then
				return
			end

			local rowHeight = options.itemHeight or UI.metrics.inputHeight

			local maxVisibleItems = options.maxVisibleItems or 8

			local gap = options.menuGap or 2

			local margin = options.menuMargin or 4

			------------------------------------------------
			-- Find available bounds
			------------------------------------------------

			local containingWindow = findContainingWindow(button)

			local boundsPosition
			local boundsSize

			if containingWindow then
				boundsPosition = containingWindow.AbsolutePosition

				boundsSize = containingWindow.AbsoluteSize
			else
				local root = UI.root()

				boundsPosition = Vector2.new(0, 0)

				boundsSize = Vector2.new(root.AbsoluteSize.X, root.AbsoluteSize.Y)
			end

			if not boundsPosition or not boundsSize then
				return
			end

			local boundsLeft = boundsPosition.X + margin

			local boundsTop = boundsPosition.Y + margin

			local boundsRight = boundsPosition.X + boundsSize.X - margin

			local boundsBottom = boundsPosition.Y + boundsSize.Y - margin

			------------------------------------------------
			-- Horizontal fitting
			------------------------------------------------

			local menuWidth = options.menuWidth or absoluteSize.X

			local maximumWidth = math.max(1, boundsRight - boundsLeft)

			menuWidth = math.min(menuWidth, maximumWidth)

			local menuX = absolutePosition.X

			if menuX + menuWidth > boundsRight then
				menuX = boundsRight - menuWidth
			end

			if menuX < boundsLeft then
				menuX = boundsLeft
			end

			------------------------------------------------
			-- Vertical fitting
			------------------------------------------------

			local buttonTop = absolutePosition.Y

			local buttonBottom = absolutePosition.Y + absoluteSize.Y

			local spaceBelow = boundsBottom - buttonBottom - gap

			local spaceAbove = buttonTop - boundsTop - gap

			local desiredRows = math.min(#items, maxVisibleItems)

			desiredRows = math.max(1, desiredRows)

			local desiredHeight = desiredRows * rowHeight

			local openAbove = false

			-- Prefer below.
			-- If below doesn't fit but above has more
			-- room, flip the dropdown upward.
			if desiredHeight > spaceBelow and spaceAbove > spaceBelow then
				openAbove = true
			end

			local availableSpace = openAbove and spaceAbove or spaceBelow

			local visibleRows = math.floor(availableSpace / rowHeight)

			visibleRows = math.clamp(visibleRows, 1, desiredRows)

			local menuHeight = visibleRows * rowHeight

			------------------------------------------------
			-- Final Y position
			------------------------------------------------

			local menuY

			if openAbove then
				menuY = buttonTop - menuHeight - gap
			else
				menuY = buttonBottom + gap
			end

			-- Final safety clamp
			menuY = math.clamp(menuY, boundsTop, math.max(boundsTop, boundsBottom - menuHeight))

			------------------------------------------------
			-- Menu
			------------------------------------------------

			local menu =
				UI.frame(UI.root(), UDim2.fromOffset(menuX, menuY), UDim2.fromOffset(menuWidth, menuHeight), options.menuColor or colors.panelRaised, options.radius or UI.tokens.radius.sm)

			menu.Name = "DropdownMenu"
			menu.ClipsDescendants = true

			UI.stroke(menu, options.borderColor or colors.borderStrong, 1, options.borderTransparency or 0)

			shared.activeDropdown = {
				button = button,
				menu = menu,
				controller = controller,
			}

			------------------------------------------------
			-- Rows
			------------------------------------------------

			for index, item in ipairs(items) do
				if index > visibleRows then
					break
				end

				local itemValue = item
				local itemText = tostring(item)

				if type(item) == "table" then
					itemValue = item.value

					if itemValue == nil then
						itemValue = item[1]
					end

					itemText = tostring(item.label or item.text or item.name or itemValue or "")
				end

				local selected = itemValue == currentValue

				local row
				local rowLabel

				row, rowLabel = UI.button(menu, itemText, UDim2.fromOffset(0, (index - 1) * rowHeight), UDim2.new(1, 0, 0, rowHeight), function()
					currentValue = itemValue

					label.Text = tostring(options.format and options.format(itemValue) or itemText)

					closeActiveDropdown()

					if options.onChanged then
						options.onChanged(itemValue, index)
					end
				end, {
					color = selected and colors.selection or options.menuColor or colors.panelRaised,

					hoverColor = selected and colors.selectionHover or colors.hover,

					pressedColor = colors.pressed,

					textColor = selected and colors.text or colors.subtext,

					textSize = options.textSize or UI.tokens.type.small,

					radius = 0,
					border = false,

					paddingX = UI.tokens.space.md,
				})
			end
		end,

		{
			color = options.color or colors.input,

			hoverColor = options.hoverColor or colors.hover,

			pressedColor = options.pressedColor or colors.pressed,

			textColor = options.textColor or colors.subtext,

			textSize = options.textSize or UI.tokens.type.small,

			radius = options.radius or UI.tokens.radius.sm,

			border = true,

			borderColor = options.borderColor or colors.border,

			paddingX = options.paddingX or UI.tokens.space.md,
		}
	)

	------------------------------------------------
	-- Chevron
	------------------------------------------------

	if chevronIcon then
		local iconSize = options.chevronSize or 12

		UI.image(button, chevronIcon, UDim2.new(1, -(iconSize + 6), 0.5, -math.floor(iconSize / 2)), UDim2.fromOffset(iconSize, iconSize))

		label.Size = UDim2.new(1, -(iconSize + 18), 1, 0)
	end

	------------------------------------------------
	-- Controller
	------------------------------------------------

	function controller:GetValue()
		return currentValue
	end

	function controller:SetValue(newValue, silent)
		currentValue = newValue

		label.Text = tostring(options.format and options.format(newValue) or newValue or "")

		if not silent and options.onChanged then
			options.onChanged(newValue)
		end
	end

	function controller:SetItems(newItems)
		items = newItems or {}

		if shared.activeDropdown and shared.activeDropdown.controller == controller then
			closeActiveDropdown()
		end
	end

	function controller:Close()
		if shared.activeDropdown and shared.activeDropdown.controller == controller then
			closeActiveDropdown()
		end
	end

	controller.button = button
	controller.label = label
	controller.record = record

	installDropdownDismiss()

	return button, label, controller
end

function UI.checkbox(parent, text, position, checked, callback, options)
	options = options or {}

	local colors = UI.tokens.color
	local value = checked == true

	local container = UI.frame(
		parent,
		position or UDim2.fromOffset(0, 0),
		options.size or UDim2.fromOffset(180, UI.metrics.propertyRow),
		colors.panel
	)

	container.BackgroundTransparency = 1

	local box
	local mark
	local record

	local function redraw()
		box.BackgroundColor3 = value and colors.accent or options.color or colors.input

		mark.Text = value and "✓" or ""
	end

	box, _, record = UI.button(container, "", UDim2.fromOffset(0, 2), UDim2.fromOffset(18, 18), function()
		value = not value
		redraw()

		if callback then
			callback(value)
		end
	end, {
		color = colors.input,
		hoverColor = colors.hover,
		pressedColor = colors.pressed,
		radius = options.radius or UI.tokens.radius.xs,
		borderColor = colors.border,
		paddingX = 0,
	})

	mark = UI.label(
		box,
		"",
		UDim2.fromOffset(0, -1),
		UDim2.new(1, 0, 1, 0),
		options.markSize or 13,
		options.markColor or colors.text
	)

	local textLabel = UI.label(
		container,
		text,
		UDim2.fromOffset(25, 1),
		UDim2.new(1, -25, 1, -1),
		options.textSize or UI.tokens.type.small,
		options.textColor or colors.text
	)

	local controller = {}

	function controller:GetValue()
		return value
	end

	function controller:SetValue(newValue, silent)
		value = newValue == true
		redraw()

		if not silent and callback then
			callback(value)
		end
	end

	controller.frame = container
	controller.box = box
	controller.label = textLabel
	controller.record = record

	redraw()

	return container, controller
end

function UI.switch(parent, position, value, callback, options)
	options = options or {}

	local colors = UI.tokens.color
	local enabled = value == true

	local width = options.width or 34
	local height = options.height or 18
	local knobSize = height - 6

	local track
	local knob
	local record

	local function redraw()
		track.BackgroundColor3 = enabled and options.enabledColor
			or colors.accent
			or options.disabledColor
			or colors.input

		knob.Position = enabled and UDim2.new(1, -(knobSize + 3), 0.5, -math.floor(knobSize / 2))
			or UDim2.new(0, 3, 0.5, -math.floor(knobSize / 2))
	end

	track, _, record = UI.button(parent, "", position, UDim2.fromOffset(width, height), function()
		enabled = not enabled
		redraw()

		if callback then
			callback(enabled)
		end
	end, {
		color = colors.input,
		hoverColor = colors.hover,
		pressedColor = colors.pressed,
		radius = math.floor(height / 2),
		borderColor = colors.border,
		paddingX = 0,
	})

	knob = UI.frame(
		track,
		UDim2.fromOffset(3, 3),
		UDim2.fromOffset(knobSize, knobSize),
		options.knobColor or colors.text,
		math.floor(knobSize / 2)
	)

	local controller = {}

	function controller:GetValue()
		return enabled
	end

	function controller:SetValue(newValue, silent)
		enabled = newValue == true
		redraw()

		if not silent and callback then
			callback(enabled)
		end
	end

	controller.track = track
	controller.knob = knob
	controller.record = record

	redraw()

	return track, controller
end

function UI.slider(parent, position, size, minimum, maximum, value, callback, options)
	options = options or {}

	local colors = UI.tokens.color

	minimum = minimum or 0
	maximum = maximum or 1
	value = math.clamp(value or minimum, minimum, maximum)

	local step = options.step or 0
	local dragging = false

	local container = UI.frame(
		parent,
		position or UDim2.fromOffset(0, 0),
		size or UDim2.fromOffset(160, UI.metrics.inputHeight),
		colors.panel
	)

	container.BackgroundTransparency = 1

	local trackHeight = options.trackHeight or 4

	local track = UI.frame(
		container,
		UDim2.new(0, 0, 0.5, -math.floor(trackHeight / 2)),
		UDim2.new(1, 0, 0, trackHeight),
		options.trackColor or colors.input,
		math.floor(trackHeight / 2)
	)

	local fill = UI.frame(
		track,
		UDim2.fromOffset(0, 0),
		UDim2.new(0, 0, 1, 0),
		options.fillColor or colors.accent,
		math.floor(trackHeight / 2)
	)

	local knobSize = options.knobSize or 12

	local knob = UI.frame(
		container,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(knobSize, knobSize),
		options.knobColor or colors.text,
		math.floor(knobSize / 2)
	)

	UI.stroke(knob, options.knobBorderColor or colors.borderStrong, 1, options.knobBorderTransparency or 0)

	local function alphaFromValue()
		if maximum == minimum then
			return 0
		end

		return math.clamp((value - minimum) / (maximum - minimum), 0, 1)
	end

	local function redraw()
		local alpha = alphaFromValue()

		fill.Size = UDim2.new(alpha, 0, 1, 0)

		knob.Position = UDim2.new(alpha, -math.floor(knobSize / 2), 0.5, -math.floor(knobSize / 2))
	end

	local function setFromPoint(pointX, silent)
		local absolutePosition = track.AbsolutePosition
		local absoluteSize = track.AbsoluteSize

		if not absolutePosition or not absoluteSize or absoluteSize.X <= 0 then
			return
		end

		local alpha = math.clamp((pointX - absolutePosition.X) / absoluteSize.X, 0, 1)

		local newValue = minimum + (maximum - minimum) * alpha

		if step > 0 then
			newValue = math.floor((newValue - minimum) / step + 0.5) * step + minimum
		end

		newValue = math.clamp(newValue, minimum, maximum)

		if newValue == value then
			return
		end

		value = newValue
		redraw()

		if not silent and callback then
			callback(value)
		end
	end

	local input = game:GetService("UserInputService")

	input.InputBegan:Connect(function(event)
		if event.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		local point = Vector2.new(event.Position.X, event.Position.Y)

		if pointInside(container, point) then
			dragging = true
			setFromPoint(point.X)
		end
	end)

	input.InputChanged:Connect(function(event)
		if not dragging then
			return
		end

		if event.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end

		setFromPoint(event.Position.X)
	end)

	input.InputEnded:Connect(function(event)
		if event.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	local controller = {}

	function controller:GetValue()
		return value
	end

	function controller:SetValue(newValue, silent)
		value = math.clamp(newValue, minimum, maximum)

		if step > 0 then
			value = math.floor((value - minimum) / step + 0.5) * step + minimum
		end

		redraw()

		if not silent and callback then
			callback(value)
		end
	end

	function controller:SetRange(newMinimum, newMaximum)
		minimum = newMinimum
		maximum = newMaximum

		value = math.clamp(value, minimum, maximum)

		redraw()
	end

	controller.frame = container
	controller.track = track
	controller.fill = fill
	controller.knob = knob

	redraw()

	return container, controller
end

function UI.progressBar(parent, position, size, value, options)
	options = options or {}

	local colors = UI.tokens.color
	local progress = math.clamp(value or 0, 0, 1)

	local background = UI.frame(
		parent,
		position,
		size or UDim2.fromOffset(160, 6),
		options.color or colors.input,
		options.radius or UI.tokens.radius.xs
	)

	background.ClipsDescendants = true

	local fill = UI.frame(
		background,
		UDim2.fromOffset(0, 0),
		UDim2.new(progress, 0, 1, 0),
		options.fillColor or colors.accent,
		options.radius or UI.tokens.radius.xs
	)

	local controller = {}

	function controller:GetValue()
		return progress
	end

	function controller:SetValue(newValue)
		progress = math.clamp(newValue, 0, 1)
		fill.Size = UDim2.new(progress, 0, 1, 0)
	end

	controller.frame = background
	controller.fill = fill

	return background, controller
end

function UI.sectionHeader(parent, text, position, size, options)
	options = options or {}

	local colors = UI.tokens.color

	local container =
		UI.frame(parent, position, size or UDim2.new(1, 0, 0, UI.metrics.sectionRow), options.color or colors.surface)

	container.BackgroundTransparency = options.transparent and 1 or 0

	local label = UI.label(
		container,
		text,
		UDim2.fromOffset(UI.tokens.space.md, 2),
		UDim2.new(1, -UI.tokens.space.md * 2, 1, -3),
		options.textSize or UI.tokens.type.small,
		options.textColor or colors.text
	)

	if options.separator ~= false then
		UI.separator(
			container,
			UDim2.new(0, UI.tokens.space.sm, 1, -1),
			UDim2.new(1, -UI.tokens.space.sm * 2, 0, 1),
			options.separatorColor or colors.border
		)
	end

	return container, label
end

function UI.badge(parent, text, position, options)
	options = options or {}

	local colors = UI.tokens.color
	local width = options.width or math.max(36, #tostring(text) * 7 + 12)
	local height = options.height or 18

	local frame = UI.frame(
		parent,
		position,
		UDim2.fromOffset(width, height),
		options.color or colors.accentSoft,
		options.radius or math.floor(height / 2)
	)

	local label = UI.label(
		frame,
		text,
		UDim2.fromOffset(4, 0),
		UDim2.new(1, -8, 1, 0),
		options.textSize or UI.tokens.type.caption,
		options.textColor or colors.text
	)

	return frame, label
end

function UI.card(parent, position, size, options)
	options = options or {}

	local colors = UI.tokens.color

	local card =
		UI.frame(parent, position, size, options.color or colors.surface, options.radius or UI.tokens.radius.md)

	if options.border ~= false then
		UI.stroke(
			card,
			options.borderColor or colors.border,
			options.borderThickness or 1,
			options.borderTransparency or 0
		)
	end

	if options.shadow then
		UI.create("UIShadow", {
			BlurRadius = UDim.new(0, options.shadowBlur or 10),
			Offset = UDim2.fromOffset(0, options.shadowOffset or 3),
			Spread = UDim2.fromOffset(0, 0),
			Color3 = options.shadowColor or Color3.fromRGB(0, 0, 0),
			Transparency = options.shadowTransparency or 0.6,
			Exponent = 2,
			Enabled = true,
		}, card)
	end

	return card
end

function UI.root()
	if shared.root then
		return shared.root
	end
	local root = UI.create("ScreenGui", { Name = "Studio", DisplayOrder = 1000, IgnoreGuiInset = true }, game.CoreGui)
	shared.root = root
	shared.background = UI.frame(root, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), UI.tokens.color.canvas)
	shared.background.Name = "EditorBackground"
	return root
end

function UI.RootOverlay()
	local root = UI.create("ScreenGui", { Name = "Overlay", DisplayOrder = 1000, IgnoreGuiInset = true }, game.CoreGui)
	root.RenderOnTop = true
	shared.overlayRoot = root

	return root
end

function UI.shared()
	return shared
end

ishared.EditorUI = UI
return UI
