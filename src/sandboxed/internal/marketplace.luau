local UI = require("@internal/editor_ui")

local Project = game.Project
local Marketplace = game.PluginMarketplace

local colors = UI.colors
local tokens = UI.tokens
local marketplaceLayoutMode = "List"

return function(page, windowControls, gui)
	local BUTTON_SIZE = 28
	local CONTROL_GAP = 6
	local marketplacePlugins = {}
	local marketplacePage = windowControls.pages.Marketplace

	local MARKETPLACE_MARGIN = tokens.space.lg
	local MARKETPLACE_CONTROLS_HEIGHT = 30
	local MARKETPLACE_GAP = 10

	local marketplaceControlsY = MARKETPLACE_MARGIN
	local marketplaceControls = UI.frame(
		marketplacePage,
		UDim2.new(0, MARKETPLACE_MARGIN, 0, marketplaceControlsY),
		UDim2.new(1, -(MARKETPLACE_MARGIN * 2), 0, MARKETPLACE_CONTROLS_HEIGHT),
		tokens.color.surfaceAlt,
		0
	)

	marketplaceControls.BackgroundTransparency = 1
	marketplaceControls.Parent = marketplacePage

	local marketplaceSearch = UI.input(
		marketplaceControls,
		"Search plugins...",
		UDim2.new(0, 0, 0, 0),
		UDim2.new(1, -(BUTTON_SIZE * 2 + CONTROL_GAP * 2), 0, BUTTON_SIZE),
		{
			text = "",
			maxLength = 64,
			selectAllOnFocus = true,
			focusColor = tokens.color.accent,
		}
	)

	local refreshMarketplace = UI.iconButton(
		marketplaceControls,
		"builtin://global-icons/refresh.svg",
		UDim2.new(1, -30, 0, 0),
		UDim2.fromOffset(30, 30),
		function() end,
		{
			bgTransparency = 0,
		}
	)

	local marketplaceListY = marketplaceControlsY + MARKETPLACE_CONTROLS_HEIGHT + MARKETPLACE_GAP

	local marketplaceList = UI.frame(
		marketplacePage,
		UDim2.new(0, MARKETPLACE_MARGIN, 0, marketplaceListY),
		UDim2.new(1, -(MARKETPLACE_MARGIN * 2), 1, -(marketplaceListY + MARKETPLACE_MARGIN)),
		tokens.color.surfaceAlt,
		15
	)

	marketplaceList.ClipsDescendants = true
	marketplaceList.Parent = marketplacePage

	local marketplaceLayout = Instance.new("UIListLayout")
	marketplaceLayout.FillDirection = Enum.FillDirection.Horizontal
	marketplaceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	marketplaceLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	marketplaceLayout.Wraps = true
	marketplaceLayout.MaxItemsPerLine = 4
	marketplaceLayout.Padding = UDim.new(0, 10)
	marketplaceLayout.LinePadding = UDim.new(0, 10)
	marketplaceLayout.PaddingLeft = UDim.new(0, 10)
	marketplaceLayout.PaddingRight = UDim.new(0, 10)
	marketplaceLayout.PaddingTop = UDim.new(0, 10)
	marketplaceLayout.PaddingBottom = UDim.new(0, 10)
	marketplaceLayout.SortOrder = Enum.SortOrder.LayoutOrder
	marketplaceLayout.Parent = marketplaceList

	local function updateMarketplaceLayout()
		if marketplaceLayoutMode == "Grid" then
			marketplaceLayout.FillDirection = Enum.FillDirection.Horizontal
			marketplaceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
			marketplaceLayout.VerticalAlignment = Enum.VerticalAlignment.Top

			marketplaceLayout.Wraps = true
			marketplaceLayout.MaxItemsPerLine = 4
			marketplaceLayout.Padding = UDim.new(0, 10)
			marketplaceLayout.LinePadding = UDim.new(0, 10)
		else
			marketplaceLayout.FillDirection = Enum.FillDirection.Vertical
			marketplaceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			marketplaceLayout.VerticalAlignment = Enum.VerticalAlignment.Top

			marketplaceLayout.Wraps = false
			marketplaceLayout.MaxItemsPerLine = 1
			marketplaceLayout.Padding = UDim.new(0, 8)
			marketplaceLayout.LinePadding = UDim.new(0, 0)
		end
	end

	local function marketplaceListCard(plugin)
		local manifest = plugin.Manifest
		local assets = plugin.Assets
		local imageSource = assets.ThumbnailUrl ~= "" and assets.ThumbnailUrl or assets.IconUrl

		local card = UI.button(marketplaceList, "", UDim2.new(0, 0, 0, 0), UDim2.new(1, -20, 0, 124), function()
			print("Selected plugin:", manifest.Name)
		end, {
			color = tokens.color.surface,
			radius = 18,
			hoverColor = tokens.color.surface,
			pressedColor = tokens.color.surface,
		})

		card.Parent = marketplaceList
		card.ClipsDescendants = true

		local iconFrame = UI.frame(card, UDim2.new(0, 14, 0, 14), UDim2.fromOffset(92, 96), tokens.color.surfaceAlt, 12)

		iconFrame.ClipsDescendants = true
		iconFrame.Parent = card

		local icon = UI.image(iconFrame, imageSource, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))

		icon.Parent = iconFrame

		local contentX = 118

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.new(0, contentX, 0, 14)
		title.Size = UDim2.new(1, -(contentX + 170), 0, 24)
		title.Text = manifest.Name or "Unknown Plugin"
		title.TextColor3 = tokens.color.text
		title.TextSize = 18
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextYAlignment = Enum.TextYAlignment.Center
		title.Parent = card

		local function pill(text, rightOffset, width)
			local tag = Instance.new("TextLabel")
			tag.Name = text
			tag.BackgroundColor3 = tokens.color.surfaceAlt
			tag.Position = UDim2.new(1, -rightOffset - width, 0, 12)
			tag.Size = UDim2.fromOffset(width, 22)
			tag.Text = text
			tag.TextColor3 = tokens.color.text
			tag.TextSize = 11
			tag.TextXAlignment = Enum.TextXAlignment.Center
			tag.TextYAlignment = Enum.TextYAlignment.Center
			tag.Parent = card

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 7)
			corner.Parent = tag
		end

		local right = 14

		pill("COMMUNITY", right, 88)

		right = right + 88 + 6

		pill(string.upper(manifest.License or "MIT"), right, 44)

		right = right + 44 + 6

		local keyword = "PLUGIN"

		if manifest.Keywords and #manifest.Keywords > 0 then
			keyword = string.upper(manifest.Keywords[1])
		end

		pill(keyword, right, math.max(58, #keyword * 7 + 16))

		local description = Instance.new("TextLabel")
		description.Name = "Description"
		description.BackgroundTransparency = 1
		description.Position = UDim2.new(0, contentX, 0, 42)
		description.Size = UDim2.new(1, -(contentX + 16), 0, 38)
		description.Text = manifest.Description or "No description provided."
		description.TextColor3 = tokens.color.text
		description.TextTransparency = 0.12
		description.TextSize = 14
		description.TextWrapped = true
		description.TextXAlignment = Enum.TextXAlignment.Left
		description.TextYAlignment = Enum.TextYAlignment.Top
		description.Parent = card

		local divider = Instance.new("Frame")
		divider.BorderSizePixel = 0
		divider.BackgroundColor3 = tokens.color.surfaceAlt
		divider.BackgroundTransparency = 0.35
		divider.Position = UDim2.new(0, contentX, 1, -36)
		divider.Size = UDim2.new(1, -(contentX + 16), 0, 1)
		divider.Parent = card

		local author = Instance.new("TextLabel")
		author.Name = "Author"
		author.BackgroundTransparency = 1
		author.Position = UDim2.new(0, contentX, 1, -28)
		author.Size = UDim2.new(0, 140, 0, 18)
		author.Text = "by " .. (manifest.Author or "unknown")
		author.TextColor3 = tokens.color.accent
		author.TextSize = 13
		author.TextXAlignment = Enum.TextXAlignment.Left
		author.TextYAlignment = Enum.TextYAlignment.Center
		author.Parent = card

		local stats = Instance.new("TextLabel")
		stats.Name = "Stats"
		stats.BackgroundTransparency = 1
		stats.AnchorPoint = Vector2.new(1, 0)
		stats.Position = UDim2.new(1, -14, 1, -28)
		stats.Size = UDim2.new(0, 220, 0, 18)

		stats.Text = "↓ 0   ♥ 0   " .. string.sub(plugin.UpdatedAt or plugin.GeneratedAt or "", 1, 10)

		stats.TextColor3 = tokens.color.subtext
		stats.TextSize = 12
		stats.TextXAlignment = Enum.TextXAlignment.Right
		stats.TextYAlignment = Enum.TextYAlignment.Center
		stats.Parent = card

		local shadow = Instance.new("UIShadow")
		shadow.BlurRadius = UDim.new(0, 8)
		shadow.Enabled = false
		shadow.Parent = card

		card.MouseEnter:Connect(function()
			shadow.Enabled = true
		end)

		card.MouseLeave:Connect(function()
			shadow.Enabled = false
		end)

		return card
	end

	local function marketplaceGridCard(plugin)
		local manifest = plugin.Manifest
		local assets = plugin.Assets

		local imageSource = assets.ThumbnailUrl ~= "" and assets.ThumbnailUrl or assets.IconUrl

		local CARD_WIDTH = 300
		local CARD_HEIGHT = 236
		local THUMBNAIL_HEIGHT = 154

		local card = UI.button(
			marketplaceList,
			"",
			UDim2.new(0, 0, 0, 0),
			UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
			function()
				print("Selected plugin:", manifest.Name)
			end,
			{
				color = tokens.color.surface,
				radius = 14,
				hoverColor = tokens.color.surface,
				pressedColor = tokens.color.surface,
			}
		)

		card.Parent = marketplaceList
		card.ClipsDescendants = true

		-- Thumbnail

		local thumbnailFrame =
			UI.frame(card, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, THUMBNAIL_HEIGHT), tokens.color.surfaceAlt, 0)

		thumbnailFrame.ClipsDescendants = true
		thumbnailFrame.Parent = card

		local thumbnail = UI.image(thumbnailFrame, imageSource, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))

		thumbnail.Parent = thumbnailFrame

		-- Title

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.new(0, 10, 0, THUMBNAIL_HEIGHT + 9)
		title.Size = UDim2.new(1, -20, 0, 24)
		title.Text = manifest.Name or "Unknown Plugin"
		title.TextColor3 = tokens.color.text
		title.TextSize = 16
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextYAlignment = Enum.TextYAlignment.Center
		title.Parent = card

		-- Author/version

		local metadata = Instance.new("TextLabel")
		metadata.Name = "Metadata"
		metadata.BackgroundTransparency = 1
		metadata.Position = UDim2.new(0, 10, 0, THUMBNAIL_HEIGHT + 34)
		metadata.Size = UDim2.new(1, -20, 0, 18)
		metadata.Text = "by " .. (manifest.Author or "unknown") .. "  •  v" .. (manifest.Version or "?")
		metadata.TextColor3 = tokens.color.subtext
		metadata.TextSize = 12
		metadata.TextXAlignment = Enum.TextXAlignment.Left
		metadata.TextYAlignment = Enum.TextYAlignment.Center
		metadata.Parent = card

		-- Bottom metadata

		local stats = Instance.new("TextLabel")
		stats.Name = "Stats"
		stats.BackgroundTransparency = 1
		stats.Position = UDim2.new(0, 10, 1, -27)
		stats.Size = UDim2.new(1, -20, 0, 18)
		stats.Text = "↓ 0    ♥ 0    " .. string.sub(plugin.UpdatedAt or plugin.GeneratedAt or "", 1, 10)
		stats.TextColor3 = tokens.color.subtext
		stats.TextSize = 12
		stats.TextXAlignment = Enum.TextXAlignment.Left
		stats.TextYAlignment = Enum.TextYAlignment.Center
		stats.Parent = card

		local shadow = Instance.new("UIShadow")
		shadow.BlurRadius = UDim.new(0, 8)
		shadow.Enabled = false
		shadow.Parent = card

		card.MouseEnter:Connect(function()
			shadow.Enabled = true
		end)

		card.MouseLeave:Connect(function()
			shadow.Enabled = false
		end)

		return card
	end

	local function clearMarketplace()
		for _, child in pairs(marketplaceList:GetChildren()) do
			if child ~= marketplaceLayout then
				child:Destroy()
			end
		end
	end

	local function renderMarketplace()
		clearMarketplace()

		updateMarketplaceLayout()

		for _, plugin in pairs(marketplacePlugins) do
			if marketplaceLayoutMode == "Grid" then
				marketplaceGridCard(plugin)
			else
				marketplaceListCard(plugin)
			end
		end
	end

	local function loadMarketplace()
		marketplacePlugins = Marketplace:GetPlugins()

		renderMarketplace()
	end

	local layoutButton

	layoutButton = UI.iconButton(
		marketplaceControls,
		"builtin://global-icons/grid.svg",
		UDim2.new(1, -(BUTTON_SIZE * 2 + CONTROL_GAP), 0, 0),
		UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		function()
			if marketplaceLayoutMode == "List" then
				marketplaceLayoutMode = "Grid"
			else
				marketplaceLayoutMode = "List"
			end

			renderMarketplace()
		end,
		{
			bgTransparency = 0,
		}
	)

	refreshMarketplace.MouseButton1Click:Connect(function()
		loadMarketplace()
	end)

	loadMarketplace()
end
