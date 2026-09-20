local UI = require("@internal/editor_ui")

local tokens = UI.tokens
local RunService = game:GetService("RunService")

local function smoothstep(t)
	return t * t * (3 - 2 * t)
end

local function animate(duration, callback, finished)
	local elapsed = 0
	local connection

	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt

		local alpha = math.clamp(elapsed / duration, 0, 1)
		callback(smoothstep(alpha))

		if alpha >= 1 then
			connection:Disconnect()

			if finished then
				finished()
			end
		end
	end)

	return connection
end

local function animatePosition(object, from, to, duration)
	object.Position = from

	return animate(duration or 0.16, function(alpha)
		object.Position = UDim2.new(
			from.X.Scale + (to.X.Scale - from.X.Scale) * alpha,
			from.X.Offset + (to.X.Offset - from.X.Offset) * alpha,
			from.Y.Scale + (to.Y.Scale - from.Y.Scale) * alpha,
			from.Y.Offset + (to.Y.Offset - from.Y.Offset) * alpha
		)
	end)
end

local function animateTransparency(object, from, to, duration)
	object.BackgroundTransparency = from

	return animate(duration or 0.16, function(alpha)
		object.BackgroundTransparency = from + (to - from) * alpha
	end)
end

return function(page, windowControls, gui)
	local SIDEBAR_WIDTH = 210
	local OUTER_PADDING = 12
	local ROW_HEIGHT = 72

	local state = {
		automaticUpdates = true,
		earlyAccess = false,
		language = "English",
		updateChannel = "Stable",

		theme = "Dark",
		compactMode = false,
		animations = true,

		autosave = true,
		confirmDelete = true,

		renderer = "Vulkan",
		vsync = true,
		msaa = "4x",

		scriptDiagnostics = true,
		thirdPartyPlugins = true,
		developerMode = false,
	}

	local categories = {
		{
			name = "General",
			description = "Updates, language, and general Kinemium preferences.",
			sections = {
				{
					title = "Kinemium",
					rows = {
						{
							title = "Version",
							description = "Kinemium Engine development build.",
							control = {
								type = "button",
								text = "Check for updates",
								width = 130,
								callback = function()
									print("Check for updates")
								end,
							},
						},
						{
							title = "Automatic updates",
							description = "Automatically download and install new engine versions.",
							control = {
								type = "switch",
								key = "automaticUpdates",
							},
						},
						{
							title = "Receive early access versions",
							description = "Receive Canary and experimental versions before stable releases.",
							control = {
								type = "switch",
								key = "earlyAccess",
							},
						},
						{
							title = "Language",
							description = "Change the language used throughout the editor.",
							control = {
								type = "dropdown",
								key = "language",
								items = {
									"English",
									"Arabic",
								},
							},
						},
						{
							title = "Help",
							description = "Open Kinemium documentation and support resources.",
							control = {
								type = "button",
								text = "Open",
								width = 78,
								callback = function()
									print("Open documentation")
								end,
							},
						},
					},
				},
				{
					title = "Updates",
					rows = {
						{
							title = "Update channel",
							description = "Choose which Kinemium release channel you want to receive.",
							control = {
								type = "dropdown",
								key = "updateChannel",
								items = {
									"Stable",
									"Canary",
								},
							},
						},
					},
				},
			},
		},

		{
			name = "Appearance",
			description = "Customize how the Kinemium editor looks and feels.",
			sections = {
				{
					title = "Interface",
					rows = {
						{
							title = "Theme",
							description = "Choose the color theme used throughout the editor.",
							control = {
								type = "dropdown",
								key = "theme",
								items = {
									"Dark",
									"Light",
								},
							},
						},
						{
							title = "Compact interface",
							description = "Reduce padding and spacing throughout editor windows.",
							control = {
								type = "switch",
								key = "compactMode",
							},
						},
						{
							title = "Interface animations",
							description = "Animate windows, menus, prompts, and interface transitions.",
							control = {
								type = "switch",
								key = "animations",
							},
						},
					},
				},
			},
		},

		{
			name = "Editor",
			description = "Configure project editing and workflow behavior.",
			sections = {
				{
					title = "Editing",
					rows = {
						{
							title = "Auto save",
							description = "Automatically save changes made to the current project.",
							control = {
								type = "switch",
								key = "autosave",
							},
						},
						{
							title = "Confirm before deleting",
							description = "Ask for confirmation before deleting instances or assets.",
							control = {
								type = "switch",
								key = "confirmDelete",
							},
						},
					},
				},
			},
		},

		{
			name = "Rendering",
			description = "Configure editor and game rendering behavior.",
			sections = {
				{
					title = "Graphics",
					rows = {
						{
							title = "Renderer",
							description = "Graphics backend used by the Kinemium renderer.",
							control = {
								type = "dropdown",
								key = "renderer",
								items = {
									"Vulkan",
									"OpenGL",
								},
							},
						},
						{
							title = "Vertical sync",
							description = "Synchronize rendering with the display refresh rate.",
							control = {
								type = "switch",
								key = "vsync",
							},
						},
						{
							title = "Anti-aliasing",
							description = "Configure multisample anti-aliasing.",
							control = {
								type = "dropdown",
								key = "msaa",
								items = {
									"Off",
									"2x",
									"4x",
									"8x",
								},
							},
						},
					},
				},
			},
		},

		{
			name = "Scripting",
			description = "Configure Luau scripting and diagnostics.",
			sections = {
				{
					title = "Luau",
					rows = {
						{
							title = "Runtime",
							description = "Kinemium games currently execute scripts using Luau.",
							control = {
								type = "button",
								text = "Luau",
								width = 90,
								callback = function() end,
							},
						},
						{
							title = "Script diagnostics",
							description = "Show warnings and diagnostics while editing scripts.",
							control = {
								type = "switch",
								key = "scriptDiagnostics",
							},
						},
					},
				},
			},
		},

		{
			name = "Plugins",
			description = "Manage plugin installation and permissions.",
			sections = {
				{
					title = "Plugin security",
					rows = {
						{
							title = "Third-party plugins",
							description = "Allow plugins installed outside the official marketplace.",
							control = {
								type = "switch",
								key = "thirdPartyPlugins",
							},
						},
						{
							title = "Manage plugins",
							description = "View installed plugins and configure their permissions.",
							control = {
								type = "button",
								text = "Manage",
								width = 90,
								callback = function()
									print("Manage plugins")
								end,
							},
						},
					},
				},
			},
		},

		{
			name = "Advanced",
			description = "Low-level development and debugging options.",
			sections = {
				{
					title = "Developer",
					rows = {
						{
							title = "Developer mode",
							description = "Expose additional debugging and engine development features.",
							control = {
								type = "switch",
								key = "developerMode",
							},
						},
						{
							title = "Reset settings",
							description = "Restore all Kinemium editor settings to their defaults.",
							control = {
								type = "button",
								text = "Reset",
								width = 90,
								callback = function()
									print("Reset settings")
								end,
							},
						},
					},
				},
			},
		},
	}

	local background = UI.frame(page, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), tokens.color.canvas, 0)

	background.Name = "SettingsBackground"
	background.ClipsDescendants = true

	local topGlow =
		UI.frame(background, UDim2.new(0.45, 0, 0, -130), UDim2.new(0.7, 0, 0, 300), tokens.color.accent, 150)

	topGlow.BackgroundTransparency = 0.88

	UI.create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 90,
	}, topGlow)

	local bottomGlow =
		UI.frame(background, UDim2.new(-0.15, 0, 1, -150), UDim2.new(0.65, 0, 0, 300), tokens.color.surfaceAlt, 150)

	bottomGlow.BackgroundTransparency = 0.65

	local shell = UI.card(
		background,
		UDim2.fromOffset(OUTER_PADDING, OUTER_PADDING),
		UDim2.new(1, -(OUTER_PADDING * 2), 1, -(OUTER_PADDING * 2)),
		{
			color = tokens.color.panel,
			radius = 10,

			border = true,
			borderColor = tokens.color.borderStrong,
			borderTransparency = 0.35,

			shadow = true,
			shadowBlur = 18,
			shadowOffset = 5,
			shadowTransparency = 0.55,
		}
	)

	shell.ClipsDescendants = true

	local sidebar = UI.card(shell, UDim2.fromOffset(10, 10), UDim2.new(0, SIDEBAR_WIDTH, 1, -20), {
		color = tokens.color.surfaceAlt,
		radius = 8,

		border = true,
		borderColor = tokens.color.border,
		borderTransparency = 0.25,
	})

	local contentPanel =
		UI.card(shell, UDim2.fromOffset(SIDEBAR_WIDTH + 22, 10), UDim2.new(1, -(SIDEBAR_WIDTH + 32), 1, -20), {
			color = tokens.color.panelRaised,
			radius = 8,

			border = true,
			borderColor = tokens.color.border,
			borderTransparency = 0.25,
		})

	contentPanel.ClipsDescendants = true

	local search = UI.input(sidebar, "Search settings...", UDim2.fromOffset(10, 10), UDim2.new(1, -20, 0, 30), {
		text = "",
		maxLength = 64,

		selectAllOnFocus = true,
		focusColor = tokens.color.accent,

		radius = 6,
	})

	local optionsLabel = UI.label(
		sidebar,
		"Options",
		UDim2.fromOffset(12, 52),
		UDim2.new(1, -24, 0, 18),
		tokens.type.caption,
		tokens.color.muted
	)

	optionsLabel.TextXAlignment = Enum.TextXAlignment.Left

	local header = UI.group(contentPanel, UDim2.fromOffset(8, 8), UDim2.new(1, -16, 0, 72), {
		color = tokens.color.surface,
		radius = 7,
	})

	UI.stroke(header, tokens.color.border, 1, 0.35)

	local headerAccent = UI.frame(header, UDim2.fromOffset(0, 10), UDim2.fromOffset(3, 52), tokens.color.accent, 2)

	local titleLabel =
		UI.label(header, "General", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 24), 17, tokens.color.text)

	titleLabel.TextXAlignment = Enum.TextXAlignment.Left

	local descriptionLabel = UI.label(
		header,
		"",
		UDim2.fromOffset(16, 38),
		UDim2.new(1, -32, 0, 20),
		tokens.type.small,
		tokens.color.subtext
	)

	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left

	local scroller = UI.create("ScrollingFrame", {
		Name = "SettingsScroller",

		Position = UDim2.fromOffset(8, 88),
		Size = UDim2.new(1, -16, 1, -96),

		BackgroundTransparency = 1,
		BorderSizePixel = 0,

		CanvasPosition = Vector2.new(0, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),

		ScrollingEnabled = true,

		ScrollBarThickness = 5,
		ScrollBarImageColor3 = tokens.color.subtext,
		ScrollBarImageTransparency = 0.45,
		ScrollBarAutoHide = true,

		ClipsDescendants = true,
	}, contentPanel)

	local function dropdownItems(values)
		local result = {}

		for _, value in ipairs(values) do
			table.insert(result, {
				value = value,
				label = value,
			})
		end

		return result
	end

	local function createControl(parent, rowY, config)
		if not config then
			return
		end

		if config.type == "switch" then
			UI.switch(parent, UDim2.new(1, -58, 0, rowY + 26), state[config.key], function(value)
				state[config.key] = value
			end, {
				width = 38,
				height = 20,

				enabledColor = tokens.color.accent,
				disabledColor = tokens.color.input,
			})

			return
		end

		if config.type == "dropdown" then
			local items = {}

			for _, value in ipairs(config.items) do
				table.insert(items, {
					value = value,
					label = value,
				})
			end

			local dropdown, _, controller = UI.dropdown(
				parent,
				state[config.key],
				UDim2.new(1, -172, 0, rowY + 21),
				UDim2.fromOffset(152, 28),
				"builtin://global-icons/chevron-down.svg",
				{
					items = items,

					menuWidth = 152,
					maxVisibleItems = 7,

					color = tokens.color.input,
					hoverColor = tokens.color.hover,
					pressedColor = tokens.color.pressed,

					borderColor = tokens.color.border,
					borderTransparency = 0.15,

					backdrop = true,
					backdropBlur = 14,
					backdropTransparency = 0.88,

					onChanged = function(value)
						state[config.key] = value

						if config.onChanged then
							config.onChanged(value)
						end
					end,
				}
			)

			return dropdown, controller
		end

		if config.type == "button" then
			local width = config.width or 100

			UI.button(
				parent,
				config.text,
				UDim2.new(1, -(width + 20), 0, rowY + 21),
				UDim2.fromOffset(width, 28),
				config.callback,
				{
					color = tokens.color.panelRaised,
					hoverColor = tokens.color.hover,
					pressedColor = tokens.color.pressed,

					textColor = tokens.color.text,

					radius = 5,
				}
			)
		end
	end

	local function createSection(parent, section, y)
		local sectionTitle =
			UI.label(parent, section.title, UDim2.fromOffset(4, y), UDim2.new(1, -8, 0, 24), 15, tokens.color.text)

		sectionTitle.TextXAlignment = Enum.TextXAlignment.Left

		y += 31

		local cardHeight = #section.rows * ROW_HEIGHT

		local card = UI.card(parent, UDim2.fromOffset(0, y), UDim2.new(1, -8, 0, cardHeight), {
			color = tokens.color.surface,

			radius = 8,

			border = true,
			borderColor = tokens.color.border,
			borderTransparency = 0.25,

			shadow = true,
			shadowBlur = 6,
			shadowOffset = 2,
			shadowTransparency = 0.75,
		})

		local finalPosition = card.Position

		card.Position =
			UDim2.new(finalPosition.X.Scale, finalPosition.X.Offset, finalPosition.Y.Scale, finalPosition.Y.Offset + 8)

		card.BackgroundTransparency = 1

		animate(0.18, function(alpha)
			card.Position = UDim2.new(
				finalPosition.X.Scale,
				finalPosition.X.Offset,
				finalPosition.Y.Scale,
				finalPosition.Y.Offset + math.floor(8 * (1 - alpha))
			)

			card.BackgroundTransparency = 1 - alpha
		end)

		for index, row in ipairs(section.rows) do
			local rowY = (index - 1) * ROW_HEIGHT

			local title = UI.label(
				card,
				row.title,
				UDim2.fromOffset(18, rowY + 13),
				UDim2.new(1, -210, 0, 20),
				tokens.type.body,
				tokens.color.text
			)

			title.TextXAlignment = Enum.TextXAlignment.Left

			local description = UI.label(
				card,
				row.description,
				UDim2.fromOffset(18, rowY + 36),
				UDim2.new(1, -210, 0, 24),
				tokens.type.small,
				tokens.color.subtext
			)

			description.TextXAlignment = Enum.TextXAlignment.Left
			description.TextYAlignment = Enum.TextYAlignment.Top
			description.TextWrapped = true

			createControl(card, rowY, row.control)

			if index < #section.rows then
				local separator = UI.separator(
					card,
					UDim2.fromOffset(18, rowY + ROW_HEIGHT - 1),
					UDim2.new(1, -36, 0, 1),
					tokens.color.border
				)

				separator.BackgroundTransparency = 0.45
			end
		end

		return y + cardHeight + 28
	end

	local selectedCategory = categories[1]
	local navigation = {}

	local function renderCategory(category)
		selectedCategory = category

		titleLabel.Text = category.name
		descriptionLabel.Text = category.description

		UI.clear(scroller)

		local y = 6

		for _, section in ipairs(category.sections) do
			y = createSection(scroller, section, y)
		end

		scroller.CanvasPosition = Vector2.new(0, 0)
		scroller.CanvasSize = UDim2.new(0, 0, 0, y + 8)

		for _, nav in ipairs(navigation) do
			local selected = nav.category == category

			nav.record.color = selected and tokens.color.surface or tokens.color.surfaceAlt

			nav.record.hoverColor = tokens.color.hover

			nav.button.BackgroundColor3 = nav.record.color
			nav.button.BackgroundTransparency = selected and 0 or 1

			nav.label.TextColor3 = selected and tokens.color.text or tokens.color.subtext

			nav.accent.Visible = selected
		end
	end

	local function layoutNavigation()
		local query = string.lower(search.Text or "")
		local y = 78

		for _, nav in ipairs(navigation) do
			local matches = query == "" or string.find(string.lower(nav.category.name), query, 1, true) ~= nil

			nav.button.Visible = matches

			if matches then
				nav.button.Position = UDim2.fromOffset(8, y)
				y += 36
			end
		end
	end

	for _, category in ipairs(categories) do
		local button, label, record = UI.button(
			sidebar,
			category.name,
			UDim2.fromOffset(8, 0),
			UDim2.new(1, -16, 0, 32),
			function()
				renderCategory(category)
			end,
			{
				color = tokens.color.surfaceAlt,
				hoverColor = tokens.color.hover,
				pressedColor = tokens.color.pressed,

				textColor = tokens.color.subtext,

				radius = 6,
				border = false,

				paddingX = 14,
			}
		)

		button.BackgroundTransparency = 1

		label.TextXAlignment = Enum.TextXAlignment.Left

		local accent = UI.frame(button, UDim2.fromOffset(3, 7), UDim2.fromOffset(3, 18), tokens.color.accent, 2)

		accent.Visible = false

		table.insert(navigation, {
			category = category,

			button = button,
			label = label,
			record = record,

			accent = accent,
		})
	end

	search.FocusLost:Connect(function()
		layoutNavigation()
	end)

	layoutNavigation()
	renderCategory(categories[1])
end
