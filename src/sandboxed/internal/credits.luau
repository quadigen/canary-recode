local UI = require("@internal/editor_ui")

local Project = game.Project

local colors = UI.colors
local tokens = UI.tokens

return function(page, windowControls, gui)
	local creditsPage = page

	local CREDITS_MARGIN = tokens.space.lg
	local CREDIT_ROW_HEIGHT = 56

	local peopleToCredit = {
		{
			Name = "devcell",
			Role = "Creator and lead maintainer",
		},
		{
			Name = "Nicobloxy",
			Role = "Windows Tester & Modeller",
		},
		{
			Name = "Lynxmountain",
			Role = "MacOS tester & Contributor",
		},
		{
			Name = "Abby",
			Role = "Linux tester",
		},
		{
			Name = "Contrastual",
			Role = "Contributor (old repo)",
		},
	}

	local technologies = {
		{
			Name = "Odin",
			Description = "Native engine runtime and systems programming",
		},
		{
			Name = "Luau",
			Description = "Scripting language and game runtime API",
		},
		{
			Name = "SDL3",
			Description = "Windowing, input, and platform integration",
		},
		{
			Name = "Skia",
			Description = "2D rendering and editor user interface",
		},
		{
			Name = "Filament",
			Description = "Physically based 3D rendering",
		},
		{
			Name = "Jolt Physics",
			Description = "3D rigid body physics and collision",
		},
		{
			Name = "Tabler icons",
			Description = "Explorer icons",
		},
		{
			Name = "Manifold",
			Description = "CSG and Unions",
		},
		{
			Name = "MINIAUDIO",
			Description = "Sounds and music",
		},
	}

	local creditsScroll = Instance.new("ScrollingFrame")

	creditsScroll.Name = "CreditsScroll"
	creditsScroll.Position = UDim2.new(0, CREDITS_MARGIN, 0, CREDITS_MARGIN)

	creditsScroll.Size = UDim2.new(1, -(CREDITS_MARGIN * 2), 1, -(CREDITS_MARGIN * 2))

	creditsScroll.BackgroundColor3 = tokens.color.surfaceAlt
	creditsScroll.BorderSizePixel = 0
	creditsScroll.ClipsDescendants = true

	creditsScroll.CanvasPosition = Vector2.new(0, 0)
	creditsScroll.ScrollingEnabled = true
	creditsScroll.ScrollSpeed = 42
	creditsScroll.SmoothScrollingEnabled = true
	creditsScroll.ScrollSmoothness = 18

	creditsScroll.ScrollBarThickness = 6
	creditsScroll.ScrollBarImageColor3 = tokens.color.subtext
	creditsScroll.ScrollBarImageTransparency = 0.35
	creditsScroll.ScrollBarAutoHide = true

	creditsScroll.Parent = creditsPage

	local scrollCorner = Instance.new("UICorner")
	scrollCorner.CornerRadius = UDim.new(0, 15)
	scrollCorner.Parent = creditsScroll

	local creditsLayout = Instance.new("UIListLayout")

	creditsLayout.FillDirection = Enum.FillDirection.Vertical
	creditsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	creditsLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	creditsLayout.Padding = UDim.new(0, 10)

	creditsLayout.PaddingTop = UDim.new(0, 24)
	creditsLayout.PaddingBottom = UDim.new(0, 24)
	creditsLayout.PaddingLeft = UDim.new(0, 22)
	creditsLayout.PaddingRight = UDim.new(0, 22)

	creditsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	creditsLayout.Parent = creditsScroll

	local function sectionTitle(text, order)
		local label = Instance.new("TextLabel")

		label.Name = text
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, -44, 0, 30)

		label.Text = text
		label.TextColor3 = tokens.color.text
		label.TextSize = 17

		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center

		label.LayoutOrder = order
		label.Parent = creditsScroll

		return label
	end

	local function creditRow(name, description, order)
		local row = UI.frame(
			creditsScroll,
			UDim2.new(0, 0, 0, 0),
			UDim2.new(1, -44, 0, CREDIT_ROW_HEIGHT),
			tokens.color.surface,
			10
		)

		row.LayoutOrder = order
		row.Parent = creditsScroll

		local nameLabel = Instance.new("TextLabel")

		nameLabel.Name = "Name"
		nameLabel.BackgroundTransparency = 1

		nameLabel.Position = UDim2.new(0, 14, 0, 7)
		nameLabel.Size = UDim2.new(1, -28, 0, 21)

		nameLabel.Text = name
		nameLabel.TextColor3 = tokens.color.text
		nameLabel.TextSize = 14

		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextYAlignment = Enum.TextYAlignment.Center

		nameLabel.Parent = row

		local descriptionLabel = Instance.new("TextLabel")

		descriptionLabel.Name = "Description"
		descriptionLabel.BackgroundTransparency = 1

		descriptionLabel.Position = UDim2.new(0, 14, 0, 29)
		descriptionLabel.Size = UDim2.new(1, -28, 0, 18)

		descriptionLabel.Text = description
		descriptionLabel.TextColor3 = tokens.color.subtext
		descriptionLabel.TextSize = 12

		descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
		descriptionLabel.TextYAlignment = Enum.TextYAlignment.Center

		descriptionLabel.Parent = row

		return row
	end

	-- Header

	local creditsLogo = UI.image(
		creditsScroll,
		"builtin://global-icons/KinemiumFull.png",
		UDim2.new(0, 0, 0, 0),
		UDim2.fromOffset(320, 120)
	)

	creditsLogo.LayoutOrder = 1
	creditsLogo.Parent = creditsScroll

	local creditsTitle = Instance.new("TextLabel")

	creditsTitle.Name = "Title"
	creditsTitle.BackgroundTransparency = 1
	creditsTitle.Size = UDim2.new(1, -44, 0, 32)

	creditsTitle.Text = "Kinemium Engine"
	creditsTitle.Font = "builtin://fonts/EvenStevens.ttf"
	creditsTitle.TextColor3 = tokens.color.text
	creditsTitle.TextSize = 24

	creditsTitle.TextXAlignment = Enum.TextXAlignment.Center
	creditsTitle.TextYAlignment = Enum.TextYAlignment.Center

	creditsTitle.LayoutOrder = 2
	creditsTitle.Parent = creditsScroll

	local subtitle = Instance.new("TextLabel")

	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, -44, 0, 42)

	subtitle.Text = "A open sandbox game engine made for building standalone games."

	subtitle.TextColor3 = tokens.color.subtext
	subtitle.TextSize = 13
	subtitle.TextWrapped = true

	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	subtitle.TextYAlignment = Enum.TextYAlignment.Center

	subtitle.LayoutOrder = 3
	subtitle.Parent = creditsScroll

	-- People

	sectionTitle("People", 10)

	for index, person in pairs(peopleToCredit) do
		creditRow(person.Name, person.Role, 10 + index)
	end

	-- Technology

	sectionTitle("Core Technology", 100)

	for index, technology in pairs(technologies) do
		creditRow(technology.Name, technology.Description, 100 + index)
	end

	-- Open source

	sectionTitle("Open Source", 200)

	local openSource = Instance.new("TextLabel")

	openSource.BackgroundTransparency = 1
	openSource.Size = UDim2.new(1, -44, 0, 64)

	openSource.Text = "Kinemium is built with open-source software and libraries. "
		.. "Thanks to their maintainers and contributors for making "
		.. "these projects available."

	openSource.TextColor3 = tokens.color.subtext
	openSource.TextSize = 12
	openSource.TextWrapped = true

	openSource.TextXAlignment = Enum.TextXAlignment.Left
	openSource.TextYAlignment = Enum.TextYAlignment.Top

	openSource.LayoutOrder = 201
	openSource.Parent = creditsScroll

	-- Footer

	local footer = Instance.new("TextLabel")

	footer.BackgroundTransparency = 1
	footer.Size = UDim2.new(1, -44, 0, 40)

	footer.Text = "Made with Kinemium"
	footer.TextColor3 = tokens.color.subtext
	footer.TextTransparency = 0.25
	footer.TextSize = 12

	footer.TextXAlignment = Enum.TextXAlignment.Center
	footer.TextYAlignment = Enum.TextYAlignment.Center

	footer.LayoutOrder = 300
	footer.Parent = creditsScroll

	-- Canvas height

	local PEOPLE_HEIGHT = #peopleToCredit * (CREDIT_ROW_HEIGHT + 10)

	local TECHNOLOGY_HEIGHT = #technologies * (CREDIT_ROW_HEIGHT + 10)

	local canvasHeight = 260 + PEOPLE_HEIGHT + TECHNOLOGY_HEIGHT + 220

	creditsScroll.CanvasSize = UDim2.new(0, 0, 0, canvasHeight)
end
