local UI = require("@internal/editor_ui")

local Project = game.Project
local Marketplace = game.PluginMarketplace
local Dialog = game.DialogService

local colors = UI.colors
local tokens = UI.tokens

return function(page, windowControls, gui)
	local BUTTON_SIZE = 28
	local GAP = 6

	local projectsPage = windowControls.pages.Projects

	UI.toast("Changes saved", {
		type = "success",

		message = "",

		detailsTitle = "Save details",

		details = [[
Project: My Game
File: game.kine
Saved 148 instances
Saved 23 scripts
No errors were reported.
]],

		duration = 9,
	})
	local prompt, content, promptController = UI.prompt({
		name = "CreateProject",

		title = "Create Project",
		description = "Configure your new Kinemium project.",

		size = UDim2.fromOffset(480, 410),

		modal = true,
		dim = true,
		dimTransparency = 0.5,
		renderOnTop = true,
		blur = 12,

		glass = true,
		transparency = 0.5,
		glassBlur = 18,

		draggable = false,
		closable = false,
		closeOnBackdrop = false,

		shadow = true,

		buttonAlignment = "right",

		buttons = {
			{
				id = "cancel",
				text = "Cancel",
				role = "secondary",
			},

			{
				id = "create",
				text = "Create",
				role = "primary",

				callback = function(controller)
					controller:SetBusy(true, "create", "Creating...")

					local props = controller:GetProjectProperties()

					if not props.Name then
						controller:Close("No name inputted")
						return
					end

					if not props.Description then
						controller:Close("No Description inputted")
						return
					end

					if not props.Icon then
						controller:Close("No Icon inputted")
						return
					end

					if not props.FolderPath then
						controller:Close("No FolderPath inputted")
						return
					end

					local success = Project:CreateProject(props.Name, props.FolderPath, props.Description, props.Icon)
					if success then
						print("success: created project!")

						if props.FolderPath then
							Project:SetActiveProject(props.FolderPath)
						end

						gui.Enabled = false
						UI.root().Enabled = true
						UI.RootOverlay().Enabled = true
					end
				end,
			},
		},

		build = function(content, controller)
			local LABEL_HEIGHT = 18
			local INPUT_HEIGHT = 28
			local FIELD_GAP = 12
			local BROWSE_BUTTON_SIZE = 28
			local BROWSE_GAP = 6

			local y = 0

			local function addLabel(text)
				local label = UI.label(
					content,
					text,
					UDim2.fromOffset(0, y),
					UDim2.new(1, 0, 0, LABEL_HEIGHT),
					12,
					UI.tokens.color.subtext
				)

				label.TextXAlignment = Enum.TextXAlignment.Left

				y += LABEL_HEIGHT + 4

				return label
			end

			local function addField(labelText, placeholder, defaultValue, maxLength)
				addLabel(labelText)

				local input = UI.input(content, placeholder, UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, INPUT_HEIGHT), {
					text = defaultValue or "",
					maxLength = maxLength or -1,
					selectAllOnFocus = true,
					focusColor = UI.tokens.color.accent,
				})

				y += INPUT_HEIGHT + FIELD_GAP

				return input
			end

			local nameInput = addField("Project Name", "My Project", "New Project", 64)

			local descriptionInput = addField("Description", "A short description of your project", "", 256)

			local iconInput =
				addField("Icon", "builtin://global-icons/project.png", "builtin://global-icons/project.png", 512)

			addLabel("Folder Path")

			local folderRow =
				UI.frame(content, UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, INPUT_HEIGHT), UI.tokens.color.panel, 0)

			folderRow.BackgroundTransparency = 1

			local folderInput = UI.input(
				folderRow,
				"C:/Users/devco/Documents/Kinemium Projects/New Project",
				UDim2.fromOffset(0, 0),
				UDim2.new(1, -(BROWSE_BUTTON_SIZE + BROWSE_GAP), 0, INPUT_HEIGHT),
				{
					text = "",
					maxLength = 1024,
					selectAllOnFocus = true,
					focusColor = UI.tokens.color.accent,
				}
			)

			local folderButton = UI.iconButton(
				folderRow,
				"builtin://global-icons/folder.svg",
				UDim2.new(1, -BROWSE_BUTTON_SIZE, 0, 0),
				UDim2.fromOffset(BROWSE_BUTTON_SIZE, BROWSE_BUTTON_SIZE),
				function()
					local path = Dialog:PickFolder("C:\\")
					if path then
						folderInput.Text = string.gsub(path, [[\]], "/")
					end
				end,
				{
					iconSize = 16,
					bgTransparency = 0,
				}
			)

			y += INPUT_HEIGHT + FIELD_GAP

			controller.fields = {
				name = nameInput,
				description = descriptionInput,
				icon = iconInput,
				folderPath = folderInput,
			}

			controller.folderButton = folderButton

			function controller:SetFolderPath(path)
				folderInput.Text = path or ""
			end

			function controller:GetFolderPath()
				return folderInput.Text
			end

			function controller:GetProjectProperties()
				return {
					Name = nameInput.Text,
					Description = descriptionInput.Text,
					Icon = iconInput.Text,
					FolderPath = folderInput.Text,
				}
			end
		end,

		onResult = function(id, value)
			print("Prompt result:", id, value)
		end,

		onClose = function(reason, result)
			print("Prompt closed:", reason, result)
		end,
	})
	promptController:Close()
	prompt.BackgroundTransparency = 0.12

	local bannerFrame = UI.frame(
		projectsPage,
		UDim2.new(0, tokens.space.lg, 0, tokens.space.lg),
		UDim2.new(1, -(tokens.space.lg * 2), 0, 140),
		Color3.new(0, 0, 0),
		15
	)

	bannerFrame.ClipsDescendants = true
	bannerFrame.Parent = projectsPage

	local banner =
		UI.image(bannerFrame, "builtin://global-icons/banner.png", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))
	banner.Parent = bannerFrame

	local filter = Instance.new("BlurImageFilter")
	filter.BlurRadius = UDim.new(0, 30)
	filter.Parent = banner

	local shadow = Instance.new("UIShadow")
	shadow.Parent = bannerFrame

	local logo = UI.image(
		bannerFrame,
		"builtin://global-icons/KinemiumFull.png",
		UDim2.new(0.01, 0, 0.5, 0),
		UDim2.new(0, 400, 0, 140)
	)

	logo.AnchorPoint = Vector2.new(0, 0.5)
	logo.ZIndex = 10

	-- projects
	local PROJECTS_Y = 140 + tokens.space.lg * 2

	local projectsList = UI.frame(
		projectsPage,
		UDim2.new(0, tokens.space.lg, 0, PROJECTS_Y),
		UDim2.new(1, -(tokens.space.lg * 2), 1, -(PROJECTS_Y + tokens.space.lg)),
		tokens.color.surfaceAlt,
		15
	)

	projectsList.ClipsDescendants = true
	projectsList.Parent = projectsPage

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.Padding = UDim.new(0, 6)
	list.PaddingLeft = UDim.new(0, 10)
	list.PaddingRight = UDim.new(0, 10)
	list.PaddingTop = UDim.new(0, 10)
	list.PaddingBottom = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Wraps = true
	list.LinePadding = UDim.new(0, 8)
	list.MaxItemsPerLine = 5
	list.Parent = projectsList

	local controls =
		UI.frame(projectsList, UDim2.new(0, 0, 0, 0), UDim2.new(1, -20, 0, BUTTON_SIZE), tokens.color.surfaceAlt, 0)

	controls.BackgroundTransparency = 1
	controls.LayoutOrder = 0
	controls.Parent = projectsList

	local deleteProject = UI.iconButton(
		controls,
		"builtin://global-icons/x.svg",
		UDim2.new(1, -BUTTON_SIZE, 0, 0),
		UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		function()
			-- delete selected project
		end,
		{
			bgTransparency = 0,
		}
	)

	local editProject = UI.iconButton(
		controls,
		"builtin://global-icons/pencil.svg",
		UDim2.new(1, -(BUTTON_SIZE * 2 + GAP), 0, 0),
		UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		function()
			-- edit selected project
		end,
		{
			bgTransparency = 0,
		}
	)

	local newProject = UI.iconButton(
		controls,
		"builtin://global-icons/plus.svg",
		UDim2.new(1, -(BUTTON_SIZE * 3 + GAP * 2), 0, 0),
		UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		function()
			promptController:Open()
		end,
		{
			bgTransparency = 0,
		}
	)

	local search = UI.input(
		controls,
		"Search projects...",
		UDim2.new(0, 0, 0, 0),
		UDim2.new(1, -(BUTTON_SIZE * 3 + GAP * 3), 0, BUTTON_SIZE),
		{
			text = "",
			maxLength = 64,
			selectAllOnFocus = true,
			focusColor = tokens.color.accent,
		}
	)

	local projects = Project:GetProjects()

	local function card(parent, iconid, name, descriptiontext, folderPath)
		local card, label, record = UI.button(
			projectsList,
			"Card",
			UDim2.new(0, 0, 0, 0),
			UDim2.new(1, -20, 0, 90),
			function()
				if not folderPath then
					print("did not find " .. folderPath)
					print({ iconid, name, descriptiontext, folderPath })
				else
					Project:SetActiveProject(folderPath)
				end
				gui.Enabled = false

				UI.root().Enabled = true
				UI.RootOverlay().Enabled = true
			end,
			{
				color = tokens.color.surface,
				radius = 15,
				hoverColor = tokens.color.surface,
				pressedColor = tokens.color.surface,
			}
		)
		card.Parent = parent

		local iconFrame = UI.frame(card, UDim2.new(0, 8, 0.5, 0), UDim2.fromOffset(74, 74), tokens.color.surfaceAlt, 8)

		iconFrame.AnchorPoint = Vector2.new(0, 0.5)
		iconFrame.ClipsDescendants = true
		iconFrame.Parent = card

		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(0, 8)
		iconCorner.Parent = iconFrame

		local icon = UI.image(iconFrame, iconid, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))

		icon.Parent = iconFrame

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.new(0, 94, 0, 18)
		title.Size = UDim2.new(1, -110, 0, 24)
		title.Text = name or "Untitled Project"
		title.TextColor3 = tokens.color.text
		title.TextSize = 16
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextYAlignment = Enum.TextYAlignment.Center
		title.Parent = card

		local description = Instance.new("TextLabel")
		description.Name = "Description"
		description.BackgroundTransparency = 1
		description.Position = UDim2.new(0, 94, 0, 44)
		description.Size = UDim2.new(1, -110, 0, 28)
		description.Text = descriptiontext or "Kinemium project"
		description.TextColor3 = tokens.color.subtext
		description.TextSize = 13
		description.TextWrapped = true
		description.TextXAlignment = Enum.TextXAlignment.Left
		description.TextYAlignment = Enum.TextYAlignment.Top
		description.Parent = card

		local projects_shadow = Instance.new("UIShadow")
		projects_shadow.BlurRadius = UDim.new(0, 5)
		projects_shadow.Enabled = false
		projects_shadow.Parent = card

		card.MouseEnter:Connect(function()
			projects_shadow.Enabled = true
		end)

		card.MouseLeave:Connect(function()
			projects_shadow.Enabled = false
		end)
	end

	for _, project in pairs(projects) do
		card(projectsList, project.Icon, project.Name, project.Description, project.Path)
	end
end
