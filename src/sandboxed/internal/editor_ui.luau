local UI = {}

local StudioThemeService = game:GetService("StudioThemeService")
local RunService = game:GetService("RunService")
local shared = { buttons = {}, root = nil, background = nil, windows = {} }

local function tooltipLerp(a, b, t)
	return a + (b - a) * t
end

local function tooltipSmoothTowards(current, target, speed, dt)
	local t = 1 - math.exp(-speed * dt)

	return tooltipLerp(current, target, t)
end

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

function UI.prompt(options)
	options = options or {}

	local colors = UI.tokens.color

	local title = options.title or "Prompt"
	local description = options.description

	local modal = options.modal ~= false
	local dim = options.dim ~= false
	local closable = options.closable ~= false
	local draggable = options.draggable ~= false
	local showHeader = options.showHeader ~= false
	local showFooter = options.showFooter ~= false

	local radius = options.radius or UI.tokens.radius.md
	local padding = options.padding or 12

	local headerHeight = showHeader and (options.headerHeight or (description and 54 or 38)) or 0
	local footerHeight = showFooter and (options.footerHeight or 52) or 0

	local size = options.size or UDim2.fromOffset(440, 260)
	local position = options.position or UDim2.fromScale(0.5, 0.5)
	local anchorPoint = options.anchorPoint or Vector2.new(0.5, 0.5)

	shared.promptSerial = (shared.promptSerial or 0) + 1

	local promptId = shared.promptSerial
	local baseZIndex = options.zIndex or (200000 + promptId * 20)

	local screenGui = UI.create("ScreenGui", {
		Name = options.screenGuiName or ("PromptGui" .. tostring(promptId)),
		RenderOnTop = options.renderOnTop ~= false,
	}, options.parent or game.CoreGui)

	local host = UI.create("Frame", {
		Name = options.name or ("Prompt" .. tostring(promptId)),

		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromScale(1, 1),

		BackgroundTransparency = 1,
		BorderSizePixel = 0,

		Active = false,
		InputSink = false,
		Selectable = false,

		ZIndex = baseZIndex,
	}, screenGui)

	local controller = {
		screenGui = screenGui,

		frame = nil,
		host = host,

		backdrop = nil,

		header = nil,
		contentArea = nil,
		content = nil,
		footer = nil,

		title = nil,
		description = nil,

		buttons = {},
		buttonConfigs = {},

		open = options.startVisible ~= false,
		busy = false,
		destroyed = false,
	}

	local needsBackdrop = modal or dim or options.closeOnBackdrop == true or options.blur ~= nil

	local backdrop = nil

	if needsBackdrop then
		backdrop = UI.create("TextButton", {
			Name = "Backdrop",

			Text = "",

			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),

			BackgroundColor3 = options.dimColor or Color3.new(0, 0, 0),
			BackgroundTransparency = dim and (options.dimTransparency or 0.45) or 1,

			BorderSizePixel = 0,

			Active = modal or options.closeOnBackdrop == true,
			InputSink = modal,
			AutoButtonColor = false,

			ZIndex = baseZIndex,
		}, host)

		controller.backdrop = backdrop

		if options.blur then
			UI.create("UIBackdrop", {
				Enabled = true,

				BlurRadius = options.blur,

				TintColor3 = options.blurTintColor or Color3.new(0, 0, 0),

				TintTransparency = options.blurTintTransparency or 1,
			}, backdrop)
		end

		if options.closeOnBackdrop == true then
			backdrop.MouseButton1Click:Connect(function()
				controller:Close("backdrop")
			end)
		end
	end

	local panel = UI.frame(host, position, size, options.color or colors.panel, radius)

	panel.Name = "PromptPanel"

	panel.AnchorPoint = anchorPoint
	panel.ClipsDescendants = options.clip == true
	panel.ZIndex = baseZIndex + 1

	if options.transparency ~= nil then
		panel.BackgroundTransparency = options.transparency
	end

	controller.frame = panel

	if options.border ~= false then
		controller.border = UI.stroke(
			panel,
			options.borderColor or colors.borderStrong,
			options.borderThickness or 1,
			options.borderTransparency or 0.25
		)
	end

	if options.shadow ~= false then
		controller.shadow = UI.create("UIShadow", {
			BlurRadius = UDim.new(0, options.shadowBlur or 18),

			Offset = UDim2.fromOffset(options.shadowOffsetX or 0, options.shadowOffsetY or 6),

			Spread = UDim2.fromOffset(options.shadowSpread or 0, options.shadowSpread or 0),

			Color3 = options.shadowColor or Color3.new(0, 0, 0),

			Transparency = options.shadowTransparency or 0.45,

			Exponent = options.shadowExponent or 2,

			Enabled = true,
		}, panel)
	end

	if options.glass == true then
		controller.panelBackdrop = UI.create("UIBackdrop", {
			Enabled = true,

			BlurRadius = options.glassBlur or 20,

			TintColor3 = options.glassColor or colors.panel,

			TintTransparency = options.glassTransparency or 0.82,
		}, panel)

		if options.transparency == nil then
			panel.BackgroundTransparency = 0.12
		end
	end

	local header = nil

	if showHeader then
		header = UI.create("TextButton", {
			Name = "Header",

			Text = "",

			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.new(1, 0, 0, headerHeight),

			BackgroundColor3 = options.headerColor or colors.panelRaised,
			BackgroundTransparency = options.headerTransparency or 0,

			BorderSizePixel = 0,

			Active = draggable,
			InputSink = true,
			AutoButtonColor = false,

			ZIndex = baseZIndex + 2,
		}, panel)

		UI.corner(header, radius)

		UI.frame(
			header,
			UDim2.new(0, 0, 1, -radius),
			UDim2.new(1, 0, 0, radius),
			options.headerColor or colors.panelRaised
		)

		controller.header = header

		if options.accent ~= false then
			controller.accent = UI.frame(
				header,
				UDim2.fromOffset(0, options.accentInset or 7),
				UDim2.fromOffset(options.accentWidth or 3, headerHeight - (options.accentInset or 7) * 2),
				options.accentColor or colors.accent,
				1
			)
		end

		local titleX = options.titleX or 12

		if options.icon then
			local iconSize = options.iconSize or 18

			controller.icon = UI.image(
				header,
				options.icon,
				UDim2.fromOffset(titleX, math.floor((headerHeight - iconSize) / 2)),
				UDim2.fromOffset(iconSize, iconSize)
			)

			titleX += iconSize + (options.iconGap or 8)
		end

		local titleHeight = description and 20 or headerHeight

		local titleLabel = UI.label(
			header,
			title,
			description and UDim2.fromOffset(titleX, 7) or UDim2.fromOffset(titleX, 0),
			UDim2.new(1, -(titleX + (closable and 42 or 12)), 0, titleHeight),
			options.titleSize or UI.tokens.type.body,
			options.titleColor or colors.text
		)

		titleLabel.Name = "Title"
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left

		controller.title = titleLabel

		if description then
			local descriptionLabel = UI.label(
				header,
				description,
				UDim2.fromOffset(titleX, 27),
				UDim2.new(1, -(titleX + (closable and 42 or 12)), 0, headerHeight - 30),
				options.descriptionSize or UI.tokens.type.caption,
				options.descriptionColor or colors.muted
			)

			descriptionLabel.Name = "Description"
			descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left

			controller.description = descriptionLabel
		end

		if options.headerSeparator ~= false then
			controller.headerSeparator = UI.separator(
				header,
				UDim2.new(0, 8, 1, -1),
				UDim2.new(1, -16, 0, 1),
				options.separatorColor or colors.border
			)
		end
	end

	if showHeader and closable then
		local closeButton

		if options.closeIcon then
			closeButton = UI.iconButton(
				header,
				options.closeIcon,
				UDim2.new(1, -31, 0.5, -11),
				UDim2.fromOffset(22, 22),
				function()
					controller:Close("close")
				end,
				{
					color = options.closeColor or colors.panelRaised,

					hoverColor = options.closeHoverColor or colors.hover,

					pressedColor = options.closePressedColor or colors.pressed,

					iconSize = options.closeIconSize or 11,

					radius = options.closeRadius or UI.tokens.radius.sm,

					border = false,
				}
			)
		else
			closeButton = UI.button(header, "×", UDim2.new(1, -31, 0.5, -11), UDim2.fromOffset(22, 22), function()
				controller:Close("close")
			end, {
				color = options.closeColor or colors.panelRaised,

				hoverColor = options.closeHoverColor or colors.hover,

				pressedColor = options.closePressedColor or colors.pressed,

				textColor = options.closeTextColor or colors.subtext,

				textSize = options.closeTextSize or 16,

				paddingX = 0,

				radius = options.closeRadius or UI.tokens.radius.sm,

				border = false,
			})
		end

		controller.closeButton = closeButton
	end

	local contentArea = UI.frame(
		panel,
		UDim2.fromOffset(0, headerHeight),
		UDim2.new(1, 0, 1, -(headerHeight + footerHeight)),
		options.contentColor or colors.panel
	)

	contentArea.Name = "ContentArea"

	contentArea.BackgroundTransparency = options.contentTransparency or 0
	contentArea.ClipsDescendants = options.clipContent == true

	controller.contentArea = contentArea

	local contentProperties = {
		Name = "Content",

		Position = UDim2.fromOffset(padding, padding),

		Size = UDim2.new(1, -padding * 2, 1, -padding * 2),

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		ClipsDescendants = options.clipContent == true,

		ZIndex = baseZIndex + 2,
	}

	local content

	if options.scrollable == true then
		contentProperties.CanvasPosition = options.canvasPosition or Vector2.new(0, 0)

		contentProperties.CanvasSize = options.canvasSize or UDim2.new(0, 0, 0, 0)

		contentProperties.ScrollingEnabled = options.scrollingEnabled ~= false

		contentProperties.ScrollBarThickness = options.scrollBarThickness or 5

		contentProperties.ScrollBarImageColor3 = options.scrollBarColor or colors.subtext

		contentProperties.ScrollBarImageTransparency = options.scrollBarTransparency or 0.4

		contentProperties.ScrollBarAutoHide = options.scrollBarAutoHide ~= false

		content = UI.create("ScrollingFrame", contentProperties, contentArea)
	else
		content = UI.create("Frame", contentProperties, contentArea)
	end

	controller.content = content

	local footer = nil
	local buttonGroup = nil

	if showFooter then
		footer = UI.frame(
			panel,
			UDim2.new(0, 0, 1, -footerHeight),
			UDim2.new(1, 0, 0, footerHeight),
			options.footerColor or colors.panelRaised
		)

		footer.Name = "Footer"

		footer.BackgroundTransparency = options.footerTransparency or 0

		controller.footer = footer

		if options.footerSeparator ~= false then
			controller.footerSeparator = UI.separator(
				footer,
				UDim2.fromOffset(8, 0),
				UDim2.new(1, -16, 0, 1),
				options.separatorColor or colors.border
			)
		end

		buttonGroup = UI.frame(footer, UDim2.fromOffset(0, 0), UDim2.fromOffset(0, footerHeight), Color3.new(0, 0, 0))

		buttonGroup.Name = "Buttons"
		buttonGroup.BackgroundTransparency = 1

		controller.buttonGroup = buttonGroup
	end

	local function getButtonColors(config)
		local role = config.role or "secondary"

		if role == "primary" then
			return config.color or colors.accent,
				config.hoverColor or colors.selectionHover,
				config.pressedColor or colors.pressed,
				config.textColor or colors.text,
				config.backgroundTransparency or 0
		elseif role == "danger" then
			return config.color or colors.error,
				config.hoverColor or colors.error,
				config.pressedColor or colors.pressed,
				config.textColor or colors.text,
				config.backgroundTransparency or 0
		elseif role == "ghost" then
			return config.color or colors.panelRaised,
				config.hoverColor or colors.hover,
				config.pressedColor or colors.pressed,
				config.textColor or colors.subtext,
				config.backgroundTransparency or 1
		end

		return config.color or colors.panelRaised,
			config.hoverColor or colors.hover,
			config.pressedColor or colors.pressed,
			config.textColor or colors.subtext,
			config.backgroundTransparency or 0
	end

	local function calculateButtonWidth(config)
		if config.width then
			return config.width
		end

		local text = tostring(config.text or config.label or config.id or "Button")

		return math.max(options.buttonWidth or 82, #text * (options.buttonCharacterWidth or 7) + 28)
	end

	local function renderButtons()
		if not buttonGroup then
			return
		end

		UI.clear(buttonGroup)

		controller.buttons = {}

		local configs = controller.buttonConfigs

		local gap = options.buttonGap or 7
		local totalWidth = 0

		for index, config in ipairs(configs) do
			totalWidth += calculateButtonWidth(config)

			if index > 1 then
				totalWidth += gap
			end
		end

		local alignment = options.buttonAlignment or "right"

		if alignment == "left" then
			buttonGroup.AnchorPoint = Vector2.new(0, 0)

			buttonGroup.Position = UDim2.fromOffset(options.footerPadding or 10, 0)
		elseif alignment == "center" then
			buttonGroup.AnchorPoint = Vector2.new(0.5, 0)

			buttonGroup.Position = UDim2.new(0.5, 0, 0, 0)
		else
			buttonGroup.AnchorPoint = Vector2.new(1, 0)

			buttonGroup.Position = UDim2.new(1, -(options.footerPadding or 10), 0, 0)
		end

		buttonGroup.Size = UDim2.fromOffset(totalWidth, footerHeight)

		local x = 0

		for index, config in ipairs(configs) do
			local id = config.id or config.name or tostring(index)

			local text = config.text or config.label or tostring(id)

			local width = calculateButtonWidth(config)

			local height = config.height or options.buttonHeight or UI.metrics.buttonHeight

			local color, hoverColor, pressedColor, textColor, backgroundTransparency = getButtonColors(config)

			local button
			local label
			local record

			button, label, record = UI.button(
				buttonGroup,
				text,
				UDim2.fromOffset(x, math.floor((footerHeight - height) / 2)),
				UDim2.fromOffset(width, height),
				function()
					if record and not record.enabled then
						return
					end

					local callbackResult = nil

					if config.callback then
						callbackResult = config.callback(controller, config, content)
					end

					local resultValue = id

					if config.value ~= nil then
						resultValue = config.value
					end

					if options.onResult then
						options.onResult(id, resultValue, config, controller, callbackResult)
					end

					if callbackResult ~= false and config.close ~= false then
						controller:Close(id, resultValue)
					end
				end,
				{
					color = color,

					hoverColor = hoverColor,

					pressedColor = pressedColor,

					textColor = textColor,

					textSize = config.textSize or options.buttonTextSize or UI.tokens.type.small,

					radius = config.radius or options.buttonRadius or UI.tokens.radius.sm,

					border = config.border ~= false,

					borderColor = config.borderColor or options.buttonBorderColor or colors.border,

					borderTransparency = config.borderTransparency or options.buttonBorderTransparency or 0,

					paddingX = config.paddingX or options.buttonPaddingX or UI.tokens.space.md,

					icon = config.icon,

					iconSize = config.iconSize or options.buttonIconSize or 14,

					enabled = config.enabled ~= false,
				}
			)

			button.Name = tostring(id)

			button.BackgroundTransparency = backgroundTransparency

			controller.buttons[id] = {
				id = id,

				button = button,
				label = label,
				record = record,

				config = config,

				color = color,
				hoverColor = hoverColor,

				textColor = textColor,

				enabled = config.enabled ~= false,
			}

			x += width + gap
		end
	end

	function controller:IsOpen()
		return self.open and not self.destroyed
	end

	function controller:Open()
		if self.destroyed then
			return false
		end

		if self.open then
			return true
		end

		self.open = true
		self.screenGui.Enabled = true

		if options.onOpen then
			options.onOpen(self)
		end

		return true
	end

	function controller:Close(reason, result)
		if self.destroyed or not self.open then
			return false
		end

		if options.beforeClose then
			local allowed = options.beforeClose(reason, result, self)

			if allowed == false then
				return false
			end
		end

		self.open = false
		self.screenGui.Enabled = false

		if options.onClose then
			options.onClose(reason, result, self)
		end

		if options.destroyOnClose == true then
			self:Destroy()
		end

		return true
	end

	function controller:Destroy()
		if self.destroyed then
			return
		end

		self.destroyed = true
		self.open = false

		self.screenGui:Destroy()
	end

	function controller:SetTitle(text)
		if self.title then
			self.title.Text = tostring(text or "")
		end
	end

	function controller:SetDescription(text)
		if not self.description then
			return
		end

		self.description.Text = tostring(text or "")
	end

	function controller:SetSize(newSize)
		panel.Size = newSize
	end

	function controller:SetPosition(newPosition)
		panel.Position = newPosition
	end

	function controller:SetModal(value)
		modal = value == true

		if backdrop then
			backdrop.Active = modal or options.closeOnBackdrop == true
			backdrop.InputSink = modal
		end
	end

	function controller:GetButton(id)
		return self.buttons[id]
	end

	function controller:SetButtonEnabled(id, enabled)
		local data = self.buttons[id]

		if not data then
			return false
		end

		enabled = enabled == true

		data.enabled = enabled
		data.record.enabled = enabled

		data.button.Active = enabled

		if enabled then
			data.record.color = data.color
			data.record.hoverColor = data.hoverColor

			data.button.BackgroundColor3 = data.color
			data.label.TextColor3 = data.textColor
		else
			data.button.BackgroundColor3 = options.disabledButtonColor or colors.surface

			data.label.TextColor3 = options.disabledTextColor or colors.muted
		end

		return true
	end

	function controller:SetButtons(buttons)
		self.buttonConfigs = buttons or {}

		renderButtons()
	end

	function controller:AddButton(config)
		table.insert(self.buttonConfigs, config)

		renderButtons()

		return self.buttons[config.id or config.name or tostring(#self.buttonConfigs)]
	end

	function controller:SetBusy(value, targetButton, busyText)
		value = value == true

		if self.busy == value then
			return
		end

		self.busy = value

		if value then
			self._busyStates = {}

			for id, data in pairs(self.buttons) do
				self._busyStates[id] = data.enabled

				self:SetButtonEnabled(id, false)
			end

			if targetButton and self.buttons[targetButton] then
				local data = self.buttons[targetButton]

				data._normalText = data.label.Text

				if busyText then
					data.label.Text = busyText
				end
			end
		else
			for id, enabled in pairs(self._busyStates or {}) do
				self:SetButtonEnabled(id, enabled)
			end

			if targetButton and self.buttons[targetButton] then
				local data = self.buttons[targetButton]

				if data._normalText then
					data.label.Text = data._normalText
					data._normalText = nil
				end
			end

			self._busyStates = nil
		end
	end

	----------------------------------------------------------------
	-- Dragging
	----------------------------------------------------------------

	if header and draggable then
		local dragging = false

		local startMouseX = 0
		local startMouseY = 0

		local startPosition = nil

		header.MouseButton1Down:Connect(function(x, y)
			dragging = true

			startMouseX = x
			startMouseY = y

			startPosition = panel.Position

			if options.onDragBegin then
				options.onDragBegin(controller)
			end
		end)

		header.MouseMoved:Connect(function(x, y)
			if not dragging or not startPosition then
				return
			end

			local deltaX = x - startMouseX
			local deltaY = y - startMouseY

			panel.Position = UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset + deltaX,
				startPosition.Y.Scale,
				startPosition.Y.Offset + deltaY
			)

			if options.onDrag then
				options.onDrag(panel.Position, controller)
			end
		end)

		header.MouseButton1Up:Connect(function()
			if not dragging then
				return
			end

			dragging = false

			if options.onDragEnd then
				options.onDragEnd(panel.Position, controller)
			end
		end)
	end

	local initialButtons = options.buttons

	if initialButtons == nil and showFooter then
		initialButtons = {
			{
				id = "ok",
				text = options.defaultButtonText or "OK",
				role = "primary",
			},
		}
	end

	controller.buttonConfigs = initialButtons or {}

	renderButtons()

	if options.build then
		options.build(content, controller)
	end

	if options.onCreated then
		options.onCreated(controller, content)
	end

	screenGui.Enabled = controller.open

	if controller.open and options.onOpen then
		options.onOpen(controller)
	end

	return panel, content, controller
end

function UI.rangeSlider(parent, position, size, minimum, maximum, low, high, callback, options)
	options = options or {}

	local colors = UI.tokens.color

	minimum = minimum or 0
	maximum = maximum or 1

	low = math.clamp(low or minimum, minimum, maximum)
	high = math.clamp(high or maximum, minimum, maximum)

	if low > high then
		low, high = high, low
	end

	local step = options.step or 0
	local dragging = nil

	local container = UI.create("TextButton", {
		Text = "",
		Position = position or UDim2.fromOffset(0, 0),
		Size = size or UDim2.fromOffset(160, UI.metrics.inputHeight),

		BackgroundTransparency = 1,
		BorderSizePixel = 0,

		Active = true,
		InputSink = true,
		AutoButtonColor = false,
	}, parent)

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
		UDim2.fromOffset(0, trackHeight),
		options.fillColor or colors.accent,
		math.floor(trackHeight / 2)
	)

	local knobSize = options.knobSize or 12

	local lowKnob = UI.frame(
		container,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(knobSize, knobSize),
		options.knobColor or colors.text,
		math.floor(knobSize / 2)
	)

	local highKnob = UI.frame(
		container,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(knobSize, knobSize),
		options.knobColor or colors.text,
		math.floor(knobSize / 2)
	)

	UI.stroke(lowKnob, options.knobBorderColor or colors.borderStrong, 1, 0)
	UI.stroke(highKnob, options.knobBorderColor or colors.borderStrong, 1, 0)

	local function alpha(value)
		if maximum == minimum then
			return 0
		end

		return math.clamp((value - minimum) / (maximum - minimum), 0, 1)
	end

	local function redraw()
		local lowAlpha = alpha(low)
		local highAlpha = alpha(high)

		fill.Position = UDim2.new(lowAlpha, 0, 0, 0)
		fill.Size = UDim2.new(math.max(highAlpha - lowAlpha, 0), 0, 1, 0)

		lowKnob.Position = UDim2.new(lowAlpha, -math.floor(knobSize / 2), 0.5, -math.floor(knobSize / 2))

		highKnob.Position = UDim2.new(highAlpha, -math.floor(knobSize / 2), 0.5, -math.floor(knobSize / 2))
	end

	local function valueFromPoint(x)
		local position = track.AbsolutePosition
		local absoluteSize = track.AbsoluteSize

		if not position or not absoluteSize or absoluteSize.X <= 0 then
			return nil
		end

		local a = math.clamp((x - position.X) / absoluteSize.X, 0, 1)
		local value = minimum + (maximum - minimum) * a

		if step > 0 then
			value = math.floor((value - minimum) / step + 0.5) * step + minimum
		end

		return math.clamp(value, minimum, maximum)
	end

	local function chooseKnob(x)
		local value = valueFromPoint(x)

		if value == nil then
			return
		end

		if math.abs(value - low) <= math.abs(value - high) then
			dragging = "low"
		else
			dragging = "high"
		end
	end

	local function updateFromPoint(x, silent)
		local value = valueFromPoint(x)

		if value == nil then
			return
		end

		if dragging == "low" then
			low = math.min(value, high)
		elseif dragging == "high" then
			high = math.max(value, low)
		else
			return
		end

		redraw()

		if not silent and callback then
			callback(low, high)
		end
	end

	container.MouseButton1Down:Connect(function(x)
		chooseKnob(x)

		if options.onBegin then
			options.onBegin()
		end

		updateFromPoint(x)
	end)

	container.MouseMoved:Connect(function(x)
		if dragging then
			updateFromPoint(x)
		end
	end)

	container.MouseButton1Up:Connect(function(x)
		if dragging then
			updateFromPoint(x)
		end

		dragging = nil

		if options.onEnd then
			options.onEnd()
		end
	end)

	local controller = {
		frame = container,
		track = track,
		fill = fill,
		lowKnob = lowKnob,
		highKnob = highKnob,
	}

	function controller:GetValues()
		return low, high
	end

	function controller:SetValues(newLow, newHigh, silent)
		low = math.clamp(newLow, minimum, maximum)
		high = math.clamp(newHigh, minimum, maximum)

		if low > high then
			low, high = high, low
		end

		redraw()

		if not silent and callback then
			callback(low, high)
		end
	end

	function controller:SetRange(newMinimum, newMaximum)
		minimum = newMinimum
		maximum = newMaximum

		low = math.clamp(low, minimum, maximum)
		high = math.clamp(high, minimum, maximum)

		redraw()
	end

	redraw()

	return container, controller
end

function UI.point2D(parent, position, size, minimumX, maximumX, minimumY, maximumY, x, y, callback, options)
	options = options or {}

	local colors = UI.tokens.color

	minimumX = minimumX or -1
	maximumX = maximumX or 1
	minimumY = minimumY or -1
	maximumY = maximumY or 1

	x = math.clamp(x or 0, minimumX, maximumX)
	y = math.clamp(y or 0, minimumY, maximumY)

	local dragging = false

	local pad = UI.create("TextButton", {
		Text = "",
		Position = position,
		Size = size or UDim2.fromOffset(160, 120),

		BackgroundColor3 = options.color or colors.input,
		BorderSizePixel = 0,

		Active = true,
		InputSink = true,
		AutoButtonColor = false,
		ClipsDescendants = true,
	}, parent)

	UI.corner(pad, options.radius or UI.tokens.radius.xs)
	UI.stroke(pad, options.borderColor or colors.border, 1, 0)

	local centerX =
		UI.separator(pad, UDim2.new(0.5, 0, 0, 0), UDim2.new(0, 1, 1, 0), options.gridColor or colors.border)

	centerX.BackgroundTransparency = 0.35

	local centerY =
		UI.separator(pad, UDim2.new(0, 0, 0.5, 0), UDim2.new(1, 0, 0, 1), options.gridColor or colors.border)

	centerY.BackgroundTransparency = 0.35

	local cursorSize = options.cursorSize or 10

	local cursor = UI.frame(
		pad,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(cursorSize, cursorSize),
		options.cursorColor or colors.text,
		math.floor(cursorSize / 2)
	)

	UI.stroke(cursor, options.cursorBorderColor or colors.borderStrong, 1, 0)

	local function normalizedX()
		if maximumX == minimumX then
			return 0
		end

		return math.clamp((x - minimumX) / (maximumX - minimumX), 0, 1)
	end

	local function normalizedY()
		if maximumY == minimumY then
			return 0
		end

		return math.clamp((y - minimumY) / (maximumY - minimumY), 0, 1)
	end

	local function redraw()
		cursor.Position =
			UDim2.new(normalizedX(), -math.floor(cursorSize / 2), normalizedY(), -math.floor(cursorSize / 2))
	end

	local function updateFromPoint(mouseX, mouseY)
		local absolutePosition = pad.AbsolutePosition
		local absoluteSize = pad.AbsoluteSize

		if not absolutePosition or not absoluteSize then
			return
		end

		if absoluteSize.X <= 0 or absoluteSize.Y <= 0 then
			return
		end

		local alphaX = math.clamp((mouseX - absolutePosition.X) / absoluteSize.X, 0, 1)

		local alphaY = math.clamp((mouseY - absolutePosition.Y) / absoluteSize.Y, 0, 1)

		x = minimumX + (maximumX - minimumX) * alphaX
		y = minimumY + (maximumY - minimumY) * alphaY

		redraw()

		if callback then
			callback(x, y)
		end
	end

	pad.MouseButton1Down:Connect(function(mouseX, mouseY)
		dragging = true

		if options.onBegin then
			options.onBegin()
		end

		updateFromPoint(mouseX, mouseY)
	end)

	pad.MouseMoved:Connect(function(mouseX, mouseY)
		if dragging then
			updateFromPoint(mouseX, mouseY)
		end
	end)

	pad.MouseButton1Up:Connect(function(mouseX, mouseY)
		if dragging then
			updateFromPoint(mouseX, mouseY)
		end

		dragging = false

		if options.onEnd then
			options.onEnd()
		end
	end)

	local controller = {
		frame = pad,
		cursor = cursor,
	}

	function controller:GetValue()
		return x, y
	end

	function controller:SetValue(newX, newY, silent)
		x = math.clamp(newX, minimumX, maximumX)
		y = math.clamp(newY, minimumY, maximumY)

		redraw()

		if not silent and callback then
			callback(x, y)
		end
	end

	redraw()

	return pad, controller
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

function UI.toast(text, options)
	options = options or {}

	local colors = UI.tokens.color

	shared.toasts = shared.toasts or {}
	shared.toastSerial = (shared.toastSerial or 0) + 1

	shared.toastMargin = shared.toastMargin or (options.margin or 20)
	shared.toastGap = shared.toastGap or (options.gap or 10)

	local margin = shared.toastMargin
	local gap = shared.toastGap

	if not shared.toastRoot then
		shared.toastRoot = UI.create("ScreenGui", {
			Name = "ToastOverlay",

			DisplayOrder = options.displayOrder or 3000,

			IgnoreGuiInset = true,
			RenderOnTop = true,
		}, options.parent or game.CoreGui)
	end

	local root = shared.toastRoot

	----------------------------------------------------------------
	-- Configuration
	----------------------------------------------------------------

	local kind = options.type or "info"

	local typeConfigs = {
		info = {
			color = colors.accent,
			icon = "i",
		},

		success = {
			color = colors.success,
			icon = "✓",
		},

		warning = {
			color = colors.warning,
			icon = "!",
		},

		error = {
			color = colors.error,
			icon = "×",
		},
	}

	local typeConfig = typeConfigs[kind] or typeConfigs.info

	local accentColor = options.accentColor or typeConfig.color
	local iconCharacter = options.icon or typeConfig.icon

	local title = options.title or tostring(text or "Notification")
	local messagePrefix = options.message or ""

	local details = tostring(options.details or "")

	local hasDetails = details ~= "" or options.buildDetails ~= nil

	local width = options.width or 520

	local headerHeight = options.headerHeight or 52
	local summaryHeight = options.summaryHeight or 40
	local progressHeight = options.progressHeight or 4

	local collapsedHeight = options.height or (headerHeight + summaryHeight + progressHeight)

	local expandedHeight = options.expandedHeight or (collapsedHeight + 120)

	expandedHeight = math.max(expandedHeight, collapsedHeight + 50)

	local duration = options.duration

	if duration == nil then
		duration = 9
	end

	local fadeSpeed = options.fadeSpeed or 14
	local moveSpeed = options.moveSpeed or 16
	local slideDistance = options.slideDistance or 18

	local backgroundTransparency = options.backgroundTransparency or 0
	local borderTransparency = options.borderTransparency or 0.25

	local zIndex = options.zIndex or (150000 + shared.toastSerial * 10)

	----------------------------------------------------------------
	-- Main toast
	----------------------------------------------------------------

	local frame = UI.create("Frame", {
		Name = "Toast" .. tostring(shared.toastSerial),

		AnchorPoint = Vector2.new(0.5, 0),

		Position = UDim2.new(0.5, 0, 0, margin - slideDistance),

		Size = UDim2.fromOffset(width, collapsedHeight),

		BackgroundColor3 = options.backgroundColor or colors.panelRaised,
		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		Active = false,
		InputSink = false,

		ZIndex = zIndex,
	}, root)

	UI.corner(frame, options.radius or UI.tokens.radius.md)

	local border = UI.stroke(frame, options.borderColor or colors.borderStrong, options.borderThickness or 1, 1)

	----------------------------------------------------------------
	-- Shadow
	----------------------------------------------------------------

	local shadow = nil

	if options.shadow ~= false then
		shadow = UI.create("UIShadow", {
			BlurRadius = UDim.new(0, options.shadowBlur or 18),

			Offset = UDim2.fromOffset(0, options.shadowOffset or 6),

			Spread = UDim2.fromOffset(0, 0),

			Color3 = options.shadowColor or Color3.new(0, 0, 0),

			Transparency = 1,

			Exponent = 2,

			Enabled = true,
		}, frame)
	end

	----------------------------------------------------------------
	-- Status icon
	----------------------------------------------------------------

	local iconSize = options.iconSize or 28

	local iconCircle = UI.frame(
		frame,
		UDim2.fromOffset(18, math.floor((headerHeight - iconSize) / 2)),
		UDim2.fromOffset(iconSize, iconSize),
		options.backgroundColor or colors.panelRaised,
		math.floor(iconSize / 2)
	)

	iconCircle.BackgroundTransparency = 1
	iconCircle.ZIndex = zIndex + 2

	local iconStroke = UI.stroke(iconCircle, accentColor, options.iconThickness or 2, 1)

	local iconLabel = UI.label(
		iconCircle,
		iconCharacter,
		UDim2.fromOffset(0, -1),
		UDim2.fromScale(1, 1),
		options.iconTextSize or 17,
		accentColor
	)

	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	iconLabel.TextTransparency = 1
	iconLabel.ZIndex = zIndex + 3

	----------------------------------------------------------------
	-- Title
	----------------------------------------------------------------

	local titleLabel = UI.label(
		frame,
		title,
		UDim2.fromOffset(58, 0),
		UDim2.new(1, -155, 0, headerHeight),
		options.titleSize or 15,
		options.titleColor or colors.text
	)

	titleLabel.Name = "Title"

	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTransparency = 1

	titleLabel.ZIndex = zIndex + 2

	----------------------------------------------------------------
	-- Header separator
	----------------------------------------------------------------

	local headerDivider =
		UI.frame(frame, UDim2.fromOffset(0, headerHeight), UDim2.new(1, 0, 0, 1), options.dividerColor or colors.border)

	headerDivider.BackgroundTransparency = 1
	headerDivider.ZIndex = zIndex + 2

	----------------------------------------------------------------
	-- Summary / timer body
	----------------------------------------------------------------

	local summaryButton = UI.create("TextButton", {
		Name = "Summary",

		Text = "",

		Position = UDim2.fromOffset(0, headerHeight + 1),

		Size = UDim2.new(1, 0, 0, summaryHeight - 1),

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		Active = true,
		InputSink = true,
		AutoButtonColor = false,

		ZIndex = zIndex + 2,
	}, frame)

	local summaryLabel = UI.create("TextLabel", {
		Name = "Message",

		Text = "",

		Position = UDim2.fromOffset(20, 0),

		Size = UDim2.new(1, -40, 1, 0),

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		TextSize = options.textSize or UI.tokens.type.body,

		TextColor3 = options.textColor or colors.subtext,

		TextTransparency = 1,

		TextWrapped = true,

		TextXAlignment = Enum.TextXAlignment.Left,

		ZIndex = zIndex + 3,
	}, summaryButton)

	----------------------------------------------------------------
	-- Details
	----------------------------------------------------------------

	local detailsFrame = UI.create("Frame", {
		Name = "Details",

		Position = UDim2.fromOffset(0, headerHeight + summaryHeight),

		Size = UDim2.new(1, 0, 0, expandedHeight - collapsedHeight),

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		Visible = false,

		ZIndex = zIndex + 2,
	}, frame)

	local detailsDivider =
		UI.frame(detailsFrame, UDim2.fromOffset(16, 0), UDim2.new(1, -32, 0, 1), options.dividerColor or colors.border)

	detailsDivider.BackgroundTransparency = 1
	detailsDivider.ZIndex = zIndex + 2

	local detailsTitle = nil

	if options.detailsTitle then
		detailsTitle = UI.label(
			detailsFrame,
			options.detailsTitle,
			UDim2.fromOffset(20, 12),
			UDim2.new(1, -40, 0, 20),
			options.detailsTitleSize or UI.tokens.type.small,
			options.detailsTitleColor or colors.text
		)

		detailsTitle.TextXAlignment = Enum.TextXAlignment.Left

		detailsTitle.TextTransparency = 1

		detailsTitle.ZIndex = zIndex + 3
	end

	local detailsY = options.detailsTitle and 38 or 12

	local detailsLabel = UI.create("TextLabel", {
		Name = "DetailsText",

		Text = details,

		Position = UDim2.fromOffset(20, detailsY),

		Size = UDim2.new(1, -40, 1, -(detailsY + 12)),

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		TextSize = options.detailsTextSize or UI.tokens.type.small,

		TextColor3 = options.detailsTextColor or colors.subtext,

		TextTransparency = 1,

		TextWrapped = true,

		TextXAlignment = Enum.TextXAlignment.Left,

		ZIndex = zIndex + 3,
	}, detailsFrame)

	----------------------------------------------------------------
	-- Expand button
	----------------------------------------------------------------

	local expandButton = UI.create("TextButton", {
		Name = "Expand",

		Text = options.expandIcon or "⌄",

		Position = UDim2.new(1, -84, 0, 10),

		Size = UDim2.fromOffset(32, 32),

		BorderSizePixel = 0,

		TextColor3 = options.expandColor or colors.subtext,

		TextTransparency = 1,

		TextSize = options.expandTextSize or 22,

		AutoButtonColor = false,

		Active = hasDetails,
		InputSink = hasDetails,

		Visible = hasDetails,

		ZIndex = zIndex + 4,
	}, frame)

	----------------------------------------------------------------
	-- Close button
	----------------------------------------------------------------

	local closeButton = UI.create("TextButton", {
		Name = "Close",

		Text = "×",

		Position = UDim2.new(1, -46, 0, 10),

		Size = UDim2.fromOffset(32, 32),

		BorderSizePixel = 0,

		TextColor3 = options.closeColor or colors.subtext,

		TextTransparency = 1,

		TextSize = options.closeTextSize or 25,

		AutoButtonColor = false,

		Active = options.closable ~= false,
		InputSink = options.closable ~= false,

		Visible = options.closable ~= false,

		ZIndex = zIndex + 4,
	}, frame)

	----------------------------------------------------------------
	-- Progress bar
	----------------------------------------------------------------

	local progressBackground = UI.frame(
		frame,
		UDim2.new(0, 0, 1, -progressHeight),
		UDim2.new(1, 0, 0, progressHeight),
		options.progressBackgroundColor or colors.input
	)

	progressBackground.ZIndex = zIndex + 4
	progressBackground.BackgroundTransparency = 1

	local progress = UI.frame(progressBackground, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), accentColor)

	progress.ZIndex = zIndex + 5
	progress.BackgroundTransparency = 1

	----------------------------------------------------------------
	-- Controller state
	----------------------------------------------------------------

	local controller = {}

	local state = {
		alpha = 0,

		y = margin - slideDistance,
		targetY = margin,

		elapsed = 0,

		timerStopped = false,

		expanded = false,

		closing = false,
		destroyed = false,

		reason = nil,
	}

	local record = {
		frame = frame,
		state = state,
		controller = controller,
	}

	table.insert(shared.toasts, 1, record)

	----------------------------------------------------------------
	-- Stack positioning
	----------------------------------------------------------------

	local function reflowToasts()
		local y = margin

		for _, toast in ipairs(shared.toasts) do
			if not toast.state.destroyed then
				toast.state.targetY = y

				y += toast.frame.Size.Y.Offset + gap
			end
		end
	end

	local function removeToast()
		for index, toast in ipairs(shared.toasts) do
			if toast == record then
				table.remove(shared.toasts, index)

				break
			end
		end

		reflowToasts()
	end

	----------------------------------------------------------------
	-- Summary text
	----------------------------------------------------------------

	local function updateSummary()
		if duration <= 0 then
			if messagePrefix ~= "" then
				summaryLabel.Text = messagePrefix
			else
				summaryLabel.Text = "Click × to close."
			end

			return
		end

		if state.timerStopped then
			if messagePrefix ~= "" then
				summaryLabel.Text = messagePrefix .. " Automatic closing stopped."
			else
				summaryLabel.Text = "Automatic closing stopped."
			end

			return
		end

		local remaining = math.max(duration - state.elapsed, 0)

		local seconds = math.ceil(remaining)

		local timerText =
			string.format("This message will close in %d second%s. Click to stop.", seconds, seconds == 1 and "" or "s")

		if messagePrefix ~= "" then
			summaryLabel.Text = messagePrefix .. " " .. timerText
		else
			summaryLabel.Text = timerText
		end
	end

	----------------------------------------------------------------
	-- Expanded state
	----------------------------------------------------------------

	local function setExpanded(expanded)
		if not hasDetails then
			return false
		end

		expanded = expanded == true

		if state.expanded == expanded then
			return true
		end

		state.expanded = expanded

		if expanded then
			frame.Size = UDim2.fromOffset(width, expandedHeight)

			detailsFrame.Visible = true

			expandButton.Text = options.collapseIcon or "⌃"

			-- Give the user time to actually read the details.
			if options.stopOnExpand ~= false and duration > 0 then
				state.timerStopped = true
			end
		else
			frame.Size = UDim2.fromOffset(width, collapsedHeight)

			detailsFrame.Visible = false

			expandButton.Text = options.expandIcon or "⌄"
		end

		updateSummary()
		reflowToasts()

		if options.onExpand then
			options.onExpand(expanded, controller)
		end

		return true
	end

	----------------------------------------------------------------
	-- Controller
	----------------------------------------------------------------

	local heartbeatConnection = nil

	controller.frame = frame
	controller.detailsFrame = detailsFrame
	controller.summary = summaryLabel
	controller.details = detailsLabel

	function controller:IsOpen()
		return not state.destroyed and not state.closing
	end

	function controller:IsExpanded()
		return state.expanded
	end

	function controller:Expand()
		return setExpanded(true)
	end

	function controller:Collapse()
		return setExpanded(false)
	end

	function controller:Toggle()
		return setExpanded(not state.expanded)
	end

	function controller:StopTimer()
		if state.timerStopped then
			return
		end

		state.timerStopped = true

		updateSummary()

		if options.onStop then
			options.onStop(controller)
		end
	end

	function controller:SetTitle(newTitle)
		title = tostring(newTitle or "")

		titleLabel.Text = title
	end

	function controller:SetMessage(newMessage)
		messagePrefix = tostring(newMessage or "")

		updateSummary()
	end

	function controller:SetDetails(newDetails)
		details = tostring(newDetails or "")

		detailsLabel.Text = details

		hasDetails = details ~= "" or options.buildDetails ~= nil

		expandButton.Visible = hasDetails
		expandButton.Active = hasDetails
		expandButton.InputSink = hasDetails

		if not hasDetails and state.expanded then
			setExpanded(false)
		end
	end

	function controller:SetDuration(seconds)
		duration = math.max(tonumber(seconds) or 0, 0)

		state.elapsed = 0
		state.timerStopped = false

		updateSummary()
	end

	function controller:SetType(newType)
		local config = typeConfigs[newType]

		if not config then
			return false
		end

		kind = newType
		typeConfig = config

		accentColor = config.color

		iconCharacter = config.icon

		iconLabel.Text = iconCharacter
		iconLabel.TextColor3 = accentColor

		iconStroke.Color = accentColor

		progress.BackgroundColor3 = accentColor

		return true
	end

	function controller:Close(reason)
		if state.destroyed or state.closing then
			return false
		end

		state.closing = true

		state.reason = reason or "closed"

		return true
	end

	function controller:Destroy()
		if state.destroyed then
			return
		end

		state.destroyed = true

		if heartbeatConnection then
			heartbeatConnection:Disconnect()
			heartbeatConnection = nil
		end

		removeToast()

		frame:Destroy()
	end

	----------------------------------------------------------------
	-- Buttons
	----------------------------------------------------------------

	summaryButton.MouseButton1Click:Connect(function()
		controller:StopTimer()
	end)

	expandButton.MouseButton1Click:Connect(function()
		controller:Toggle()
	end)

	closeButton.MouseButton1Click:Connect(function()
		controller:Close("close")
	end)

	----------------------------------------------------------------
	-- Custom details content
	----------------------------------------------------------------

	if options.buildDetails then
		options.buildDetails(detailsFrame, controller)
	end

	----------------------------------------------------------------
	-- Initial state
	----------------------------------------------------------------

	updateSummary()
	reflowToasts()

	----------------------------------------------------------------
	-- Animation
	----------------------------------------------------------------

	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if state.destroyed then
			if heartbeatConnection then
				heartbeatConnection:Disconnect()
				heartbeatConnection = nil
			end

			return
		end

		--------------------------------------------------------
		-- Timer
		--------------------------------------------------------

		if not state.closing and not state.timerStopped and duration > 0 then
			state.elapsed += dt

			if state.elapsed >= duration then
				state.elapsed = duration

				controller:Close("timeout")
			end
		end

		updateSummary()

		--------------------------------------------------------
		-- Progress
		--------------------------------------------------------

		local progressAlpha = 0

		if duration > 0 then
			progressAlpha = math.clamp((duration - state.elapsed) / duration, 0, 1)
		end

		progress.Size = UDim2.new(progressAlpha, 0, 1, 0)

		--------------------------------------------------------
		-- Position / fade
		--------------------------------------------------------

		local targetAlpha = state.closing and 0 or 1

		state.alpha = tooltipSmoothTowards(state.alpha, targetAlpha, fadeSpeed, dt)

		state.y = tooltipSmoothTowards(state.y, state.targetY, moveSpeed, dt)

		if math.abs(state.alpha - targetAlpha) < 0.005 then
			state.alpha = targetAlpha
		end

		if math.abs(state.y - state.targetY) < 0.1 then
			state.y = state.targetY
		end

		local slide = (1 - state.alpha) * -slideDistance

		frame.Position = UDim2.new(0.5, 0, 0, state.y + slide)

		--------------------------------------------------------
		-- Fade properties
		--------------------------------------------------------

		frame.BackgroundTransparency = 1 - state.alpha * (1 - backgroundTransparency)

		border.Transparency = 1 - state.alpha * (1 - borderTransparency)

		iconStroke.Transparency = 1 - state.alpha

		iconLabel.TextTransparency = 1 - state.alpha

		titleLabel.TextTransparency = 1 - state.alpha

		summaryLabel.TextTransparency = 1 - state.alpha

		headerDivider.BackgroundTransparency = 1 - state.alpha

		expandButton.TextTransparency = 1 - state.alpha

		closeButton.TextTransparency = 1 - state.alpha

		progressBackground.BackgroundTransparency = 1 - state.alpha

		progress.BackgroundTransparency = 1 - state.alpha

		if state.expanded then
			detailsDivider.BackgroundTransparency = 1 - state.alpha

			detailsLabel.TextTransparency = 1 - state.alpha

			if detailsTitle then
				detailsTitle.TextTransparency = 1 - state.alpha
			end
		end

		if shadow then
			local wantedShadowTransparency = options.shadowTransparency or 0.5

			shadow.Transparency = 1 - state.alpha * (1 - wantedShadowTransparency)
		end

		--------------------------------------------------------
		-- Finished closing
		--------------------------------------------------------

		if state.closing and state.alpha <= 0.001 then
			if heartbeatConnection then
				heartbeatConnection:Disconnect()
				heartbeatConnection = nil
			end

			state.destroyed = true

			removeToast()

			frame:Destroy()

			if options.onClose then
				options.onClose(state.reason, controller)
			end
		end
	end)

	return controller
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

local closeActiveDropdown

local function wireNativeButton(button, record)
	button.MouseEnter:Connect(function()
		if record.enabled then
			button.BackgroundColor3 = record.hoverColor
		end
	end)

	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = record.color
	end)

	button.MouseButton1Down:Connect(function()
		if not record.enabled then
			return
		end

		button.BackgroundColor3 = record.pressedColor
	end)

	button.MouseButton1Up:Connect(function(x, y)
		if not record.enabled then
			button.BackgroundColor3 = record.color

			return
		end

		local point = Vector2.new(x, y)

		button.BackgroundColor3 = pointInside(button, point) and record.hoverColor or record.color
	end)

	button.MouseButton1Click:Connect(function()
		if not record.enabled then
			return
		end

		local active = shared.activeDropdown

		if active and closeActiveDropdown and active.closeOnOutsideClick ~= false then
			local insideButton = button == active.button or button:IsDescendantOf(active.button)

			local insideMenu = active.menu and (button == active.menu or button:IsDescendantOf(active.menu))

			if not insideButton and not insideMenu then
				closeActiveDropdown()
			end
		end

		record.callback()
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

	local button = UI.create("TextButton", {
		Text = "",
		Position = position or UDim2.fromOffset(0, 0),
		Size = size or UDim2.fromOffset(100, UI.metrics.buttonHeight),
		BackgroundColor3 = color,
		BackgroundTransparency = options.bgTransparency,
		BorderSizePixel = 0,
		Active = options.enabled ~= false,
		InputSink = true,
		AutoButtonColor = false,
	}, parent)

	local radius = options.radius or UI.tokens.radius.sm

	if radius and radius > 0 then
		UI.corner(button, radius)
	end

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
			UDim2.fromOffset(6, math.floor((((size and size.Y.Offset) or UI.metrics.buttonHeight) - iconSize) / 2)),
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

	wireNativeButton(button, record)

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

function UI.colorPicker(parent, position, size, initialColor, callback)
	local colors = UI.tokens.color
	local picker = UI.frame(parent, position, size or UDim2.fromOffset(226, 286), colors.panel, UI.tokens.radius.md)
	picker.Name = "ColorPicker"
	picker.ZIndex = 100000
	UI.stroke(picker, colors.borderStrong, 1, 0)

	local title =
		UI.label(picker, "Color", UDim2.fromOffset(10, 7), UDim2.new(1, -20, 0, 18), UI.tokens.type.small, colors.text)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local color = initialColor or Color3.new(1, 1, 1)
	local hue, saturation, value = color:ToHSV()
	local draggingSquare, draggingHue = false, false
	local redraw

	local square = UI.frame(
		picker,
		UDim2.fromOffset(10, 30),
		UDim2.new(1, -20, 0, 142),
		Color3.fromHSV(hue, 1, 1),
		UI.tokens.radius.xs
	)
	square.ClipsDescendants = true
	UI.create("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new(0, 1),
		Rotation = 0,
	}, square)
	UI.create("UIGradient", {
		Color = ColorSequence.new(Color3.new(0, 0, 0)),
		Transparency = NumberSequence.new(1, 0),
		Rotation = 90,
	}, square)
	local squareInput = UI.create("TextButton", {
		Text = "",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		InputSink = true,
	}, square)
	local squareCursor = UI.frame(square, UDim2.fromOffset(0, 0), UDim2.fromOffset(12, 12), Color3.new(1, 1, 1), 6)
	UI.stroke(squareCursor, Color3.new(0, 0, 0), 1, 0)

	local hueBar =
		UI.frame(picker, UDim2.fromOffset(10, 180), UDim2.new(1, -20, 0, 14), colors.input, UI.tokens.radius.xs)
	for index = 0, 23 do
		local segment = UI.frame(
			hueBar,
			UDim2.new(index / 24, 0, 0, 0),
			UDim2.new(1 / 24, 1, 1, 0),
			Color3.fromHSV(index / 24, 1, 1),
			0
		)
		segment.BorderSizePixel = 0
	end
	UI.create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
			ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
		}),
		Rotation = 0,
	}, hueBar)
	local hueInput = UI.create("TextButton", {
		Text = "",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		InputSink = true,
	}, hueBar)
	local hueCursor = UI.frame(hueBar, UDim2.fromOffset(0, -2), UDim2.fromOffset(4, 18), colors.text, 2)

	local hexLabel = UI.label(picker, "HEX", UDim2.fromOffset(10, 208), UDim2.fromOffset(28, 20), 11, colors.subtext)
	hexLabel.TextXAlignment = Enum.TextXAlignment.Left
	local hexInput = UI.input(picker, "#FFFFFF", UDim2.fromOffset(42, 205), UDim2.new(1, -52, 0, 24), {
		text = string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255),
		maxLength = 7,
		textSize = 12,
	})
	local function applyHex()
		local raw = string.gsub(hexInput.Text, "#", "")
		if #raw == 6 then
			local red, green, blue =
				tonumber(string.sub(raw, 1, 2), 16),
				tonumber(string.sub(raw, 3, 4), 16),
				tonumber(string.sub(raw, 5, 6), 16)
			if red and green and blue then
				color = Color3.fromRGB(red, green, blue)
				hue, saturation, value = color:ToHSV()
				redraw()
				if callback then
					callback(color)
				end
			end
		end
	end
	hexInput.FocusLost:Connect(function()
		applyHex()
	end)
	local swatches = UI.frame(picker, UDim2.fromOffset(10, 240), UDim2.new(1, -20, 0, 34), colors.panel, 0)
	local presetColors = {
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(0, 0, 0),
		Color3.fromRGB(231, 76, 60),
		Color3.fromRGB(241, 196, 15),
		Color3.fromRGB(46, 204, 113),
		Color3.fromRGB(52, 152, 219),
		Color3.fromRGB(155, 89, 182),
		Color3.fromRGB(149, 165, 166),
	}

	redraw = function()
		square.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
		squareCursor.Position = UDim2.new(saturation, -6, 1 - value, -6)
		hueCursor.Position = UDim2.new(hue, -2, 0, -2)
		hexInput.Text = string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
	end

	local function updateColor(notify)
		color = Color3.fromHSV(hue, saturation, value)
		redraw()
		if notify and callback then
			callback(color)
		end
	end

	local function setSquareFromPoint(x, y)
		local p, s = square.AbsolutePosition, square.AbsoluteSize
		if not p or not s or s.X <= 0 or s.Y <= 0 then
			return
		end
		saturation = math.clamp((x - p.X) / s.X, 0, 1)
		value = 1 - math.clamp((y - p.Y) / s.Y, 0, 1)
		updateColor(true)
	end

	local function setHueFromPoint(x)
		local p, s = hueBar.AbsolutePosition, hueBar.AbsoluteSize
		if not p or not s or s.X <= 0 then
			return
		end
		hue = math.clamp((x - p.X) / s.X, 0, 1)
		updateColor(true)
	end

	squareInput.MouseButton1Down:Connect(function(x, y)
		draggingSquare = true
		setSquareFromPoint(x, y)
	end)
	squareInput.MouseMoved:Connect(function(x, y)
		if draggingSquare then
			setSquareFromPoint(x, y)
		end
	end)
	squareInput.MouseButton1Up:Connect(function()
		draggingSquare = false
	end)
	hueInput.MouseButton1Down:Connect(function(x)
		draggingHue = true
		setHueFromPoint(x)
	end)
	hueInput.MouseMoved:Connect(function(x)
		if draggingHue then
			setHueFromPoint(x)
		end
	end)
	hueInput.MouseButton1Up:Connect(function()
		draggingHue = false
	end)
	for index, preset in ipairs(presetColors) do
		local swatchButton = UI.create("TextButton", {
			Text = "",
			Position = UDim2.fromOffset((index - 1) * 25, 0),
			Size = UDim2.fromOffset(20, 20),
			BackgroundColor3 = preset,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			InputSink = true,
		}, swatches)
		UI.corner(swatchButton, 2)
		swatchButton.MouseButton1Click:Connect(function()
			color = preset
			hue, saturation, value = color:ToHSV()
			redraw()
			if callback then
				callback(color)
			end
		end)
	end

	local function setZIndex()
		for _, child in ipairs(picker:GetDescendants()) do
			if child:IsA("GuiObject") then
				child.ZIndex = 100001
			end
		end
	end
	setZIndex()
	redraw()

	local controller = { frame = picker }
	function controller:GetColor()
		return color
	end
	function controller:SetColor(nextColor, silent)
		color = nextColor or Color3.new(1, 1, 1)
		hue, saturation, value = color:ToHSV()
		redraw()
		if not silent and callback then
			callback(color)
		end
	end

	picker.Visible = false
	return picker, controller
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
	local radius = options.radius or UI.tokens.radius.md
	local headerHeight = options.headerHeight or UI.metrics.windowHeader

	local tabs = options.tabs or {}
	local hasTabs = #tabs > 0

	local tabHeight = hasTabs and (options.tabHeight or 30) or 0
	local tabPadding = options.tabPadding or 8
	local tabGap = options.tabGap or 4
	local defaultTabWidth = options.tabWidth or 100

	local panel = UI.frame(UI.root(), position, size, colors.panel, radius)

	panel.Name = name
	panel.ClipsDescendants = false

	shared.windows[string.lower(name)] = panel

	if options.backdrop == true then
		UI.create("UIBackdrop", {
			Enabled = true,
			BlurRadius = options.backdropBlur or 16,
			TintColor3 = options.backdropColor or colors.panel,
			TintTransparency = options.backdropTransparency or 0.78,
		}, panel)

		panel.BackgroundTransparency = options.panelTransparency or 0.08
	end

	local border = UI.stroke(
		panel,
		options.borderColor or colors.borderStrong,
		options.borderThickness or 1,
		options.borderTransparency or 0.35
	)

	----------------------------------------------------------------
	-- Header
	----------------------------------------------------------------

	local header = UI.frame(
		panel,
		UDim2.fromOffset(0, 0),
		UDim2.new(1, 0, 0, headerHeight),
		options.headerColor or colors.panelRaised,
		radius
	)

	header.Name = "Header"
	header.ClipsDescendants = true

	UI.frame(header, UDim2.new(0, 0, 1, -radius), UDim2.new(1, 0, 0, radius), options.headerColor or colors.panelRaised)

	local accentWidth = options.accentWidth or 3

	UI.frame(
		header,
		UDim2.fromOffset(0, 6),
		UDim2.fromOffset(accentWidth, headerHeight - 12),
		options.accentColor or colors.accent,
		1
	)

	local titleLabel = UI.label(
		header,
		title or name,
		UDim2.fromOffset(10, 4),
		UDim2.new(1, options.closable and -44 or -20, 0, headerHeight - 7),
		options.titleSize or UI.tokens.type.body,
		options.titleColor or colors.text
	)

	titleLabel.Name = "Title"

	----------------------------------------------------------------
	-- Close button
	----------------------------------------------------------------

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

	UI.frame(header, UDim2.new(0, 8, 1, -1), UDim2.new(1, -16, 0, 1), colors.border)

	----------------------------------------------------------------
	-- Tabs
	----------------------------------------------------------------

	local tabBar = nil
	local tabButtons = {}
	local pages = {}
	local selectedTab = nil

	if hasTabs then
		tabBar = UI.frame(
			panel,
			UDim2.fromOffset(0, headerHeight),
			UDim2.new(1, 0, 0, tabHeight),
			options.tabBarColor or colors.panelRaised
		)

		tabBar.Name = "TabBar"
		tabBar.ClipsDescendants = true

		UI.frame(tabBar, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), colors.border)
	end

	----------------------------------------------------------------
	-- Content root
	----------------------------------------------------------------

	local contentY = headerHeight + tabHeight

	local content = UI.frame(
		panel,
		UDim2.fromOffset(0, contentY),
		UDim2.new(1, 0, 1, -contentY),
		options.contentColor or colors.panel
	)

	content.Name = "Content"
	content.ClipsDescendants = true

	UI.frame(content, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 1), colors.border)

	----------------------------------------------------------------
	-- Tab controller
	----------------------------------------------------------------

	local controller = {}

	local function getTabName(tab)
		if type(tab) == "table" then
			return tab.name or tab.id or tab.text or "Tab"
		end

		return tostring(tab)
	end

	local function getTabText(tab)
		if type(tab) == "table" then
			return tab.text or tab.title or tab.name or tab.id or "Tab"
		end

		return tostring(tab)
	end

	local function updateTabs()
		for tabName, data in pairs(tabButtons) do
			local active = tabName == selectedTab

			if data.record then
				if data.record.SetColor then
					data.record:SetColor(
						active and (options.activeTabColor or colors.surface)
							or (options.inactiveTabColor or colors.panelRaised)
					)
				end
			end

			if data.button then
				data.button.BackgroundColor3 = active and (options.activeTabColor or colors.surface)
					or (options.inactiveTabColor or colors.panelRaised)
			end

			if data.label then
				data.label.TextColor3 = active and (options.activeTabTextColor or colors.text)
					or (options.inactiveTabTextColor or colors.muted)
			end
		end

		for tabName, page in pairs(pages) do
			page.Visible = tabName == selectedTab
		end
	end

	function controller.selectTab(tabName)
		if not pages[tabName] then
			return
		end

		if selectedTab == tabName then
			return
		end

		local previousTab = selectedTab

		selectedTab = tabName

		updateTabs()

		if options.onTabChanged then
			options.onTabChanged(tabName, previousTab, pages[tabName], panel)
		end
	end

	function controller.getSelectedTab()
		return selectedTab
	end

	function controller.getPage(tabName)
		return pages[tabName]
	end

	----------------------------------------------------------------
	-- Create tab pages/buttons
	----------------------------------------------------------------

	if hasTabs then
		local x = tabPadding

		for index, tab in ipairs(tabs) do
			local tabName = getTabName(tab)
			local tabText = getTabText(tab)

			local tabWidth = defaultTabWidth

			if type(tab) == "table" and tab.width then
				tabWidth = tab.width
			end

			local page =
				UI.frame(content, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), options.contentColor or colors.panel)

			page.Name = tabName
			page.Visible = false
			page.ClipsDescendants = true

			pages[tabName] = page

			local button
			local label
			local record

			button, label, record = UI.button(
				tabBar,
				tabText,
				UDim2.fromOffset(x, 3),
				UDim2.fromOffset(tabWidth, tabHeight - 7),
				function()
					controller.selectTab(tabName)
				end,
				{
					color = options.inactiveTabColor or colors.panelRaised,
					hoverColor = options.tabHoverColor or colors.hover,
					pressedColor = options.tabPressedColor or colors.pressed,
					textColor = options.inactiveTabTextColor or colors.textDimmed,
					radius = options.tabRadius or UI.tokens.radius.sm,
					border = false,
				}
			)

			button.Name = tabName .. "Tab"

			tabButtons[tabName] = {
				button = button,
				label = label,
				record = record,
				index = index,
			}

			x += tabWidth + tabGap
		end

		local initialTab = options.selectedTab

		if not initialTab then
			initialTab = getTabName(tabs[1])
		end

		controller.selectTab(initialTab)
	end

	----------------------------------------------------------------
	-- Window clip
	----------------------------------------------------------------

	local clip = UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), colors.panel, radius)

	clip.Name = "WindowClip"
	clip.BackgroundTransparency = 1
	clip.InputSink = false
	clip.Selectable = false

	return panel,
		content,
		header,
		{
			title = titleLabel,
			closeButton = closeButton,
			border = border,
			clip = clip,

			tabBar = tabBar,
			tabs = tabButtons,
			pages = pages,

			selectTab = controller.selectTab,
			getSelectedTab = controller.getSelectedTab,
			getPage = controller.getPage,
		}
end

function UI.toggleWindow(name)
	local window = shared.windows[string.lower(name)]

	if window then
		window.Visible = not window.Visible
	end
end

function UI.getWindow(name)
	return shared.windows[string.lower(name)]
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

closeActiveDropdown = function()
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

			local rowHeight = options.itemHeight or UI.metrics.inputHeight

			local maxVisibleItems = options.maxVisibleItems or 8

			local gap = options.menuGap or 2

			local margin = options.menuMargin or 4

			local desiredRows = math.min(#items, maxVisibleItems)
			desiredRows = math.max(1, desiredRows)
			local visibleRows = desiredRows
			local menuWidth = options.menuWidth or 140
			local menuHeight = visibleRows * rowHeight

			local fixedMenuPosition = options.menuPosition
			if type(fixedMenuPosition) == "function" then
				fixedMenuPosition = fixedMenuPosition()
			end

			if fixedMenuPosition then
				local menu = UI.frame(
					UI.RootOverlay(),
					fixedMenuPosition,
					UDim2.fromOffset(menuWidth, menuHeight + 34),
					options.menuColor or colors.panelRaised,
					options.radius or UI.tokens.radius.sm
				)
				if options.backdrop then
					UI.create("UIBackdrop", {
						Enabled = true,
						BlurRadius = options.backdropBlur or 18,
						TintColor3 = options.backdropColor or colors.panelRaised,
						TintTransparency = options.backdropTransparency or 0.85,
					}, menu)
				end

				menu.BackgroundTransparency = options.BackgroundTransparency or 0
				menu.Name = "DropdownMenu"
				menu.ZIndex = options.menuZIndex or 100000
				menu.ClipsDescendants = true
				UI.stroke(menu, options.borderColor or colors.borderStrong, 1, options.borderTransparency or 0)

				local search = UI.input(
					menu,
					options.searchPlaceholder or "Search...",
					UDim2.fromOffset(5, 5),
					UDim2.new(1, -10, 0, 24),
					{ textSize = options.textSize or UI.tokens.type.small }
				)
				search.ZIndex = (options.menuZIndex or 100000) + 1

				local list = UI.create("ScrollingFrame", {
					Position = UDim2.fromOffset(0, 34),
					Size = UDim2.new(1, 0, 1, -34),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					CanvasPosition = Vector2.new(0, 0),
					CanvasSize = UDim2.new(1, 0, 0, 0),
					ScrollingEnabled = true,
					ScrollBarThickness = 5,
					ScrollBarImageColor3 = colors.subtext,
					ScrollBarImageTransparency = 0.4,
					ScrollBarAutoHide = true,
					ClipsDescendants = true,
				}, menu)

				list.ZIndex = (options.menuZIndex or 100000) + 1

				local function itemMatches(item, query)
					if query == "" then
						return true
					end
					local text = tostring(item.label or item.text or item.name or item.value or ""):lower()
					return string.find(text, query, 1, true) ~= nil
				end

				local function renderItems()
					UI.clear(list)
					local query = string.lower(search.Text or "")
					local y = 0
					local visible = 0
					local categories = options.categories
					if categories then
						for _, category in ipairs(categories) do
							local categoryItems = {}
							for _, item in ipairs(category.items or {}) do
								if itemMatches(item, query) then
									table.insert(categoryItems, item)
								end
							end
							if #categoryItems > 0 then
								UI.label(
									list,
									category.name,
									UDim2.fromOffset(10, y + 3),
									UDim2.new(1, -20, 0, rowHeight - 4),
									options.categoryTextSize or 10,
									colors.muted
								)
								y += rowHeight
								for _, item in ipairs(categoryItems) do
									local itemValue = item.value or item[1]
									local itemText = tostring(item.label or item.text or item.name or itemValue or "")
									local shortcut = item.shortcut and ("    " .. item.shortcut) or ""
									local button = UI.button(
										list,
										itemText .. shortcut,
										UDim2.fromOffset(0, y),
										UDim2.new(1, 0, 0, rowHeight),
										function()
											currentValue = itemValue
											label.Text = itemText
											closeActiveDropdown()
											if options.onChanged then
												options.onChanged(itemValue, item)
											end
										end,
										{
											color = colors.panelRaised,
											hoverColor = colors.hover,
											pressedColor = colors.pressed,
											textColor = colors.subtext,
											textSize = options.textSize or UI.tokens.type.small,
											radius = 0,
											border = false,

											paddingX = UI.tokens.space.md,
											icon = item.icon,
											iconSize = options.iconSize or 14,
										}
									)
									button.BackgroundTransparency = options.itemBgTransparency or 0
									y += rowHeight
									visible += 1
								end
							end
						end
					else
						for _, item in ipairs(items) do
							if itemMatches(item, query) then
								local itemValue = item.value or item[1]
								local itemText = tostring(item.label or item.text or item.name or itemValue or "")
								local button = UI.button(
									list,
									itemText,
									UDim2.fromOffset(0, y),
									UDim2.new(1, 0, 0, rowHeight),
									function()
										currentValue = itemValue
										label.Text = itemText
										closeActiveDropdown()
										if options.onChanged then
											options.onChanged(itemValue, item)
										end
									end,
									{
										color = colors.panelRaised,
										hoverColor = colors.hover,
										pressedColor = colors.pressed,
										textColor = colors.subtext,
										textSize = options.textSize or UI.tokens.type.small,
										radius = 0,
										border = false,
										paddingX = UI.tokens.space.md,
										icon = item.icon,
										iconSize = options.iconSize or 14,
									}
								)
								button.BackgroundTransparency = options.itemBgTransparency or 0
								y += rowHeight
								visible += 1
							end
						end
					end
					list.CanvasSize = UDim2.new(1, 0, 0, math.max(y, rowHeight))
				end
				search.FocusLost:Connect(renderItems)
				renderItems()

				shared.activeDropdown = {
					button = button,
					menu = menu,
					controller = controller,
					closeOnOutsideClick = options.closeOnOutsideClick ~= false,
				}
				return
				--[[
				local menu = UI.create("ScrollingFrame", {
					Position = fixedMenuPosition,
					Size = UDim2.fromOffset(menuWidth, menuHeight),
					BackgroundColor3 = options.menuColor or colors.panelRaised,
					BackgroundTransparency = 0,
					BorderSizePixel = 0,
					CanvasPosition = Vector2.new(0, 0),
					CanvasSize = UDim2.new(1, 0, 0, #items * rowHeight),
					ScrollingEnabled = #items > visibleRows,
					ScrollBarThickness = 5,
					ScrollBarImageColor3 = colors.subtext,
					ScrollBarImageTransparency = 0.4,
					ScrollBarAutoHide = true,
					ScrollBarFadeDelay = 0.45,
					ScrollBarFadeSpeed = 12,
					ClipsDescendants = true,
				}, UI.RootOverlay())
				UI.corner(menu, options.radius or UI.tokens.radius.sm)
				menu.Name = "DropdownMenu"
				menu.ZIndex = options.menuZIndex or 100000

				shared.activeDropdown = {
					button = button,
					menu = menu,
					controller = controller,
				}

				for index, item in ipairs(items) do
					local itemValue = item
					local itemText = tostring(item)
					local itemIcon
					if type(item) == "table" then
						itemValue = item.value or item[1]
						itemText = tostring(item.label or item.text or item.name or itemValue or "")
						itemIcon = item.icon
					end
					local row = UI.button(
						menu,
						itemText,
						UDim2.fromOffset(0, (index - 1) * rowHeight),
						UDim2.new(1, 0, 0, rowHeight),
						function()
							currentValue = itemValue
							label.Text = tostring(options.format and options.format(itemValue) or itemText)
							closeActiveDropdown()
							if options.onChanged then options.onChanged(itemValue, index) end
						end,
						{
							color = colors.panelRaised,
							hoverColor = colors.hover,
							pressedColor = colors.pressed,
							textColor = colors.subtext,
							textSize = options.textSize or UI.tokens.type.small,
							radius = 0,
							border = false,
							paddingX = UI.tokens.space.md,
							icon = itemIcon,
							iconSize = options.iconSize or 14,
						}
					)
				end
				return
				]]
			end
			local absolutePosition = button.AbsolutePosition
			local absoluteSize = button.AbsoluteSize

			if not absolutePosition or not absoluteSize then
				return
			end

			local containingWindow = findContainingWindow(button)

			local boundsPosition

			local boundsSize

			boundsPosition = Vector2.new(0, 0)
			boundsSize = Vector2.new(1920, 1080)

			if not boundsPosition or not boundsSize then
				return
			end

			local boundsLeft = boundsPosition.X + margin

			local boundsTop = boundsPosition.Y + margin

			local boundsRight = boundsPosition.X + boundsSize.X - margin

			local boundsBottom = boundsPosition.Y + boundsSize.Y - margin

			menuWidth = options.menuWidth or 140

			local maximumWidth = math.max(1, boundsRight - boundsLeft)

			menuWidth = math.min(menuWidth, maximumWidth)

			local menuX = absolutePosition.X

			if options.menuSide == "left" then
				menuX = absolutePosition.X - menuWidth - gap
			end

			if options.menuSide ~= "left" and menuX + menuWidth > boundsRight then
				menuX = boundsRight - menuWidth
			end

			if options.menuSide ~= "left" and menuX < boundsLeft then
				menuX = boundsLeft
			end

			local buttonTop = absolutePosition.Y

			local buttonBottom = absolutePosition.Y + absoluteSize.Y

			local spaceBelow = boundsBottom - buttonBottom - gap

			local spaceAbove = buttonTop - boundsTop - gap

			local desiredHeight = desiredRows * rowHeight

			local openAbove = false

			if desiredHeight > spaceBelow and spaceAbove > spaceBelow then
				openAbove = true
			end

			local availableSpace = openAbove and spaceAbove or spaceBelow

			visibleRows = math.floor(availableSpace / rowHeight)

			visibleRows = math.clamp(visibleRows, 1, desiredRows)

			local menuHeight = visibleRows * rowHeight

			local menuY

			if openAbove then
				menuY = buttonTop - menuHeight - gap
			else
				menuY = buttonBottom + gap
			end

			menuY = math.clamp(menuY, boundsTop, math.max(boundsTop, boundsBottom - menuHeight))

			local menu = UI.create("ScrollingFrame", {
				Position = UDim2.fromOffset(menuX, menuY),
				Size = UDim2.fromOffset(menuWidth, menuHeight),
				BackgroundColor3 = options.menuColor or colors.panelRaised,
				BackgroundTransparency = 0,
				BorderSizePixel = 0,
				CanvasPosition = Vector2.new(0, 0),
				CanvasSize = UDim2.new(1, 0, 0, #items * rowHeight),
				ScrollingEnabled = #items > visibleRows,
				ScrollBarThickness = 5,
				ScrollBarImageColor3 = colors.subtext,
				ScrollBarImageTransparency = 0.4,
				ScrollBarAutoHide = true,
				ScrollBarFadeDelay = 0.45,
				ScrollBarFadeSpeed = 12,
				ClipsDescendants = true,
			}, UI.root())
			UI.corner(menu, options.radius or UI.tokens.radius.sm)

			menu.Name = "DropdownMenu"
			menu.ZIndex = options.menuZIndex or 100000

			menu.ClipsDescendants = true

			UI.stroke(menu, options.borderColor or colors.borderStrong, 1, options.borderTransparency or 0)

			shared.activeDropdown = {
				button = button,
				menu = menu,
				controller = controller,
				closeOnOutsideClick = options.closeOnOutsideClick ~= false,
			}

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

				row, rowLabel = UI.button(
					menu,
					itemText,
					UDim2.fromOffset(0, (index - 1) * rowHeight),
					UDim2.new(1, 0, 0, rowHeight),
					function()
						currentValue = itemValue

						label.Text = tostring(options.format and options.format(itemValue) or itemText)

						closeActiveDropdown()

						if options.onChanged then
							options.onChanged(itemValue, index)
						end
					end,
					{

						color = selected and colors.selection or options.menuColor or colors.panelRaised,

						hoverColor = selected and colors.selectionHover or colors.hover,

						pressedColor = colors.pressed,

						textColor = selected and colors.text or colors.subtext,

						textSize = options.textSize or UI.tokens.type.small,

						radius = 0,

						border = false,

						paddingX = UI.tokens.space.md,
						icon = type(item) == "table" and item.icon or nil,
						iconSize = options.iconSize or 14,
					}
				)
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

			icon = options.icon,

			iconSize = options.iconSize or 14,
		}
	)

	if chevronIcon then
		local iconSize = options.chevronSize or 12

		UI.image(
			button,
			chevronIcon,
			UDim2.new(1, -(iconSize + 6), 0.5, -math.floor(iconSize / 2)),
			UDim2.fromOffset(iconSize, iconSize)
		)

		label.Size = UDim2.new(1, -(iconSize + 18), 1, 0)
	end

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
	button.BackgroundTransparency = options.BackgroundTransparency or 0
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
		track.BackgroundColor3 = enabled and (options.enabledColor or colors.accent)
			or (options.disabledColor or colors.input)

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

	local container = UI.create("TextButton", {

		Text = "",

		Position = position or UDim2.fromOffset(0, 0),

		Size = size or UDim2.fromOffset(160, UI.metrics.inputHeight),

		BackgroundColor3 = colors.panel,

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		Active = true,

		InputSink = true,

		AutoButtonColor = false,
	}, parent)

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

	container.MouseButton1Down:Connect(function(x)
		dragging = true

		setFromPoint(x)
	end)

	container.MouseMoved:Connect(function(x)
		if not dragging then
			return
		end

		setFromPoint(x)
	end)

	container.MouseButton1Up:Connect(function(x)
		if dragging then
			setFromPoint(x)
		end

		dragging = false
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

	shared.background = UI.create("TextButton", {

		Name = "EditorBackground",

		Text = "",

		Position = UDim2.fromOffset(0, 0),

		Size = UDim2.new(1, 0, 1, 0),

		BackgroundColor3 = UI.tokens.color.canvas,

		BorderSizePixel = 0,

		Active = true,

		InputSink = false,

		AutoButtonColor = false,

		ZIndex = -100000,
	}, root)

	shared.background.MouseButton1Click:Connect(function()
		local active = shared.activeDropdown

		if active and closeActiveDropdown and active.closeOnOutsideClick ~= false then
			closeActiveDropdown()
		end
	end)

	return root
end

function UI.RootOverlay()
	if shared.overlayRoot then
		return shared.overlayRoot
	end

	local root = UI.create("ScreenGui", {

		Name = "Overlay",

		DisplayOrder = 1001,

		IgnoreGuiInset = true,
	}, game.CoreGui)

	root.RenderOnTop = true

	shared.overlayRoot = root

	return root
end

function UI.tooltip(target, text, options)
	options = options or {}

	local colors = UI.tokens.color

	local hoverDelay = options.hoverDelay or 0.4

	local fadeSpeed = options.fadeSpeed or 14

	local riseDistance = options.riseDistance or 6

	local padding = options.padding or 6

	local gap = options.gap or 8

	local screenMargin = options.screenMargin or 4

	local placement = options.placement or "cursor"

	local offset = options.offset or Vector2.new(12, 20)

	local textSize = options.textSize or 12

	local maxWidth = options.maxWidth

	local backgroundTransparency = options.backgroundTransparency or 0

	local borderTransparency = options.borderTransparency or 0

	local textTransparency = options.textTransparency or 0

	local root = UI.RootOverlay()

	local tooltip = UI.create("Frame", {

		Name = "Tooltip",

		Position = UDim2.fromOffset(0, 0),

		Size = UDim2.fromOffset(1, 1),

		BackgroundColor3 = options.backgroundColor or colors.surface,

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		Active = false,

		InputSink = false,

		Selectable = false,

		Visible = false,

		ZIndex = options.zIndex or 100000,
	}, root)

	UI.corner(tooltip, options.cornerRadius or UI.tokens.radius.sm)

	local stroke = UI.stroke(tooltip, options.borderColor or colors.borderStrong, options.borderThickness or 1, 1)

	local label = UI.create("TextLabel", {

		Name = "Text",

		Text = tostring(text or ""),

		Position = UDim2.fromOffset(padding, padding),

		Size = UDim2.fromOffset(1, 1),

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		TextSize = textSize,

		TextColor3 = options.textColor or colors.text,

		TextTransparency = 1,

		TextWrapped = maxWidth ~= nil,

		ZIndex = (options.zIndex or 100000) + 1,
	}, tooltip)

	local state = {

		hovered = false,

		hoverTime = 0,

		alpha = 0,

		anchorMouse = Vector2.new(0, 0),

		mouse = Vector2.new(0, 0),

		destroyed = false,
	}

	local controller = {}

	local function updateSize()
		local bounds = label.TextBounds

		if not bounds then
			return tooltip.AbsoluteSize.X, tooltip.AbsoluteSize.Y
		end

		local contentWidth = math.max(bounds.X, 1)

		local contentHeight = math.max(bounds.Y, textSize)

		if maxWidth then
			contentWidth = math.min(contentWidth, maxWidth)

			label.Size = UDim2.fromOffset(maxWidth, math.max(contentHeight, textSize))

			contentWidth = maxWidth
		else
			label.Size = UDim2.fromOffset(contentWidth, contentHeight)
		end

		local width = contentWidth + padding * 2

		local height = contentHeight + padding * 2

		tooltip.Size = UDim2.fromOffset(width, height)

		return width, height
	end

	local function calculatePosition(width, height)
		local targetPosition = target.AbsolutePosition

		local targetSize = target.AbsoluteSize

		local x
		local y

		if placement == "cursor" then
			local anchor = options.followCursor and state.mouse or state.anchorMouse

			x = anchor.X + offset.X

			y = anchor.Y + offset.Y
		elseif placement == "above" then
			x = targetPosition.X + (targetSize.X - width) / 2

			y = targetPosition.Y - height - gap
		elseif placement == "below" then
			x = targetPosition.X + (targetSize.X - width) / 2

			y = targetPosition.Y + targetSize.Y + gap
		elseif placement == "left" then
			x = targetPosition.X - width - gap

			y = targetPosition.Y + (targetSize.Y - height) / 2
		else
			x = targetPosition.X + targetSize.X + gap

			y = targetPosition.Y + (targetSize.Y - height) / 2
		end

		local rise = (1 - state.alpha) * riseDistance

		if placement == "left" then
			x -= rise
		elseif placement == "right" then
			x += rise
		else
			y -= rise
		end

		local screenSize = root.AbsoluteSize

		if screenSize then
			x = math.clamp(x, screenMargin, math.max(screenMargin, screenSize.X - width - screenMargin))

			y = math.clamp(y, screenMargin, math.max(screenMargin, screenSize.Y - height - screenMargin))
		end

		return x, y
	end

	local function updateTransparency()
		tooltip.BackgroundTransparency = 1 - state.alpha * (1 - backgroundTransparency)

		stroke.Transparency = 1 - state.alpha * (1 - borderTransparency)

		label.TextTransparency = 1 - state.alpha * (1 - textTransparency)
	end

	local enterConnection = target.MouseEnter:Connect(function(x, y)
		state.hovered = true

		state.hoverTime = 0

		state.anchorMouse = Vector2.new(x, y)

		state.mouse = state.anchorMouse
	end)

	local leaveConnection = target.MouseLeave:Connect(function()
		state.hovered = false

		state.hoverTime = 0
	end)

	local moveConnection = target.MouseMoved:Connect(function(x, y)
		state.mouse = Vector2.new(x, y)
	end)

	local heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if state.destroyed then
			return
		end

		if state.hovered then
			state.hoverTime += dt
		else
			state.hoverTime = 0
		end

		local targetAlpha = state.hovered and state.hoverTime >= hoverDelay and 1 or 0

		state.alpha = tooltipSmoothTowards(state.alpha, targetAlpha, fadeSpeed, dt)

		if math.abs(state.alpha - targetAlpha) < 0.01 then
			state.alpha = targetAlpha
		end

		if state.alpha <= 0.001 then
			tooltip.Visible = false

			return
		end

		tooltip.Visible = true

		local width, height = updateSize()

		local x, y = calculatePosition(width, height)

		tooltip.Position = UDim2.fromOffset(x, y)

		updateTransparency()
	end)

	function controller:SetText(newText)
		label.Text = tostring(newText or "")
	end

	function controller:SetPlacement(newPlacement)
		placement = newPlacement or "cursor"
	end

	function controller:Show()
		state.hovered = true

		state.hoverTime = hoverDelay
	end

	function controller:Hide()
		state.hovered = false

		state.hoverTime = 0
	end

	function controller:Destroy()
		if state.destroyed then
			return
		end

		state.destroyed = true

		enterConnection:Disconnect()

		leaveConnection:Disconnect()

		moveConnection:Disconnect()

		heartbeatConnection:Disconnect()

		tooltip:Destroy()
	end

	controller.frame = tooltip

	controller.label = label

	controller.target = target

	return controller
end

function UI.shared()
	return shared
end

return UI
