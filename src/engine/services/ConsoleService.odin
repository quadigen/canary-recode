package services


import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import sdl3 "../platform"
import vm "../vm"

ConsoleService_Class := classes.Class_Info {
	name   = "ConsoleService",
	parent = &Service_Class,
}

ConsoleService :: struct {
	using service: Service,
	enabled:       bool,
}

console_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ConsoleService)
	service.service = Service_Init(&ConsoleService_Class, "ConsoleService", data_model)
	return &service.object
}

console_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^ConsoleService)object)
}

console_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^ConsoleService)object
	switch key {
	case "Enabled":
		vm.PushBoolean(L, service.enabled)
	case "SetEnabled":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

console_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "SetEnabled":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "ConsoleService:SetEnabled requires internal privileges"), true
		}
		service := cast(^ConsoleService)object
		service.enabled = vm.ArgBoolean(L, 2)
		return 0, true
	}
	return 0, false
}

Register_ConsoleService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&ConsoleService_Class,
		console_service_construct,
		console_service_destroy,
		creatable = false,
		get = console_service_get,
		namecall = console_service_namecall,
		methods = []string{"SetEnabled"},
	)
}

Console_Handle_Event :: proc(registry: ^Registry, event: sdl3.Event) {
	if registry == nil || registry.mode == .Server || registry.classes.renderer == nil {
		return
	}
	if event.type != .KEY_DOWN || event.key.scancode != .F9 || event.key.repeat {
		return
	}
	descriptor := Find_Service(registry, "ConsoleService")
	if descriptor != nil && descriptor.object != nil {
		service := cast(^ConsoleService)descriptor.object
		service.enabled = !service.enabled
	}
}

CONSOLE_OVERLAY_SOURCE :: `local console = game:GetService("ConsoleService")
local logs = game:GetService("LogService")
local white = Color3.new(1, 1, 1)
local dim = Color3.new(0.72, 0.72, 0.72)
local blue = Color3.new(0.46, 0.75, 1)
local amber = Color3.new(1, 0.72, 0.34)
local red = Color3.new(1, 0.42, 0.42)
local colors = {Log = white, Info = blue, Warn = amber, Error = red}
local names = {Log = "OUTPUT", Info = "INFO", Warn = "WARN", Error = "ERROR"}
local rowHeight = 18
local maxRows = 4000

local function make(class, name, parent)
	local object = Instance.new(class)
	object.Name = name
	object.Archivable = false
	object.CanReplicate = false
	object.Parent = parent
	return object
end

local function label(name, parent, value, size, color)
	local object = make("TextLabel", name, parent)
	object.BackgroundTransparency = 1
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.TextColor3 = color
	object.TextSize = size
	object.RichText = false
	object.Text = value
	return object
end

local function button(name, parent, value)
	local object = make("TextButton", name, parent)
	object.BackgroundTransparency = 1
	object.TextColor3 = dim
	object.TextSize = 12
	object.Text = value
	return object
end

local screen = make("ScreenGui", "ConsoleOverlay", game:GetService("CoreGui"))
screen.Enabled = false
screen.RenderOnTop = true
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.DisplayOrder = 10001

local panel = make("Frame", "Panel", screen)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(780, 480)
panel.BackgroundColor3 = Color3.new(0, 0, 0)
panel.BackgroundTransparency = 0.5
panel.BorderSizePixel = 0
panel.Active = true
make("UIBackdrop", "Blur", panel)
make("UIDragDetector", "Drag", panel)
make("UIScaleDetector", "Drag", panel)

local title = label("Headline", panel, "Console", 21, white)
title.Position = UDim2.fromOffset(10, 4)
title.Size = UDim2.new(1, -60, 0, 30)

local close = button("CloseButton", panel, "Close")
close.Position = UDim2.new(1, -60, 0, 4)
close.Size = UDim2.fromOffset(50, 30)
close.MouseButton1Click:Connect(function()
	console:SetEnabled(false)
end)

local tabs = {"All", "Log", "Info", "Warn", "Error"}
local selected = "All"
local tabButtons = {}
local dirty = true
for i, kind in ipairs(tabs) do
	local tab = button(kind .. "Tab", panel, kind == "Log" and "Output" or kind == "Warn" and "Warnings" or kind == "Error" and "Errors" or kind)
	tab.Position = UDim2.new((i - 1) / #tabs, 0, 0, 36)
	tab.Size = UDim2.new(1 / #tabs, 0, 0, 24)
	tabButtons[kind] = tab
	tab.MouseButton1Click:Connect(function()
		selected = kind
		dirty = true
	end)
end

local search = make("TextBox", "Search", panel)
search.Position = UDim2.fromOffset(10, 64)
search.Size = UDim2.new(1, -78, 0, 28)
search.BackgroundColor3 = Color3.new(0, 0, 0)
search.BackgroundTransparency = 0.35
search.BorderSizePixel = 0
search.TextColor3 = white
search.PlaceholderColor3 = dim
search.TextSize = 13
search.TextXAlignment = Enum.TextXAlignment.Left
search.Text = ""
search.PlaceholderText = "Search logs..."
search.ClearTextOnFocus = false
search.MultiLine = false
search.MaxLength = 256
search.Active = true
search.InputSink = true

local clearSearch = button("ClearSearch", panel, "Clear")
clearSearch.Position = UDim2.new(1, -64, 0, 64)
clearSearch.Size = UDim2.fromOffset(54, 28)
clearSearch.MouseButton1Click:Connect(function()
	search.Text = ""
end)

local body = make("ScrollingFrame", "Logs", panel)
body.Position = UDim2.fromOffset(10, 98)
body.Size = UDim2.new(1, -20, 1, -130)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.ScrollingDirection = Enum.ScrollingDirection.XY
body.CanvasSize = UDim2.fromOffset(0, 0)

local empty = label("Empty", panel, "No logs yet", 13, dim)
empty.Position = UDim2.fromOffset(12, 104)
empty.Size = UDim2.new(1, -24, 0, 24)

local footer = label("Footer", panel, "Read-only   F9 hide", 11, dim)
footer.Position = UDim2.new(0, 10, 1, -26)
footer.Size = UDim2.new(1, -115, 0, 22)

local latest = button("LatestButton", panel, "Follow: On")
latest.Position = UDim2.new(1, -100, 1, -26)
latest.Size = UDim2.fromOffset(90, 22)
local follow = true
local pendingBottom = 0
latest.MouseButton1Click:Connect(function()
	follow = not follow
	latest.Text = follow and "Follow: On" or "Follow: Off"
	if follow then pendingBottom = 2 end
end)

local data = {}
local rows = {}
local canvasWidth = 0
local renderedStart = -1
local renderedCount = -1
local renderedWidth = -1

local function renderRows(force)
	local first = math.max(1, math.floor(body.CanvasPosition.Y / rowHeight) + 1)
	local visible = math.max(1, math.ceil(body.AbsoluteSize.Y / rowHeight) + 2)
	if not force and first == renderedStart and visible == renderedCount and canvasWidth == renderedWidth then return end
	renderedStart, renderedCount, renderedWidth = first, visible, canvasWidth
	for i = 1, math.max(visible, #rows) do
		local index = first + i - 1
		local entry = i <= visible and data[index]
		local row = rows[i]
		if entry then
			if not row then
				row = label("Row" .. i, body, "", 13, white)
				row.Font = Enum.Font.Code
				rows[i] = row
			end
			row.Position = UDim2.fromOffset(0, (index - 1) * rowHeight)
			row.Size = UDim2.fromOffset(canvasWidth, rowHeight)
			row.Text = entry.text
			row.TextColor3 = entry.color
			row.Visible = true
		elseif row then
			row.Visible = false
		end
	end
end

local query = ""

local function refresh()
	local history = logs:GetLogHistory()
	local reverse = {}
	local longest = 0
	local count = 0
	for i = #history, 1, -1 do
		local entry = history[i]
		local kind = entry.type
		local text = tostring(entry.message or "")
		if (selected == "All" or selected == kind) and (query == "" or string.find(string.lower(text), query, 1, true)) then
			count += 1
			local seconds = math.floor(entry.timestamp) % 86400
			local time = string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
			local prefix = string.format("%s  %-6s  ", time, names[kind] or "LOG")
			local lines = {}
			local cursor = 1
			for j = 1, 64 do
				local stop = string.find(text, "\n", cursor, true)
				local line = string.sub(text, cursor, stop and stop - 1 or #text)
				line = string.gsub(line, "\r$", "")
				line = string.gsub(line, "\t", "    ")
				if #line > 4096 then
					local cut = 4096
					while cut > 1 and string.byte(line, cut + 1) >= 128 and string.byte(line, cut + 1) < 192 do cut -= 1 end
					line = string.sub(line, 1, cut) .. " [truncated]"
				end
				lines[#lines + 1] = (j == 1 and prefix or string.rep(" ", #prefix)) .. line
				if not stop then break end
				cursor = stop + 1
				if j == 64 then lines[#lines + 1] = string.rep(" ", #prefix) .. "[additional lines omitted]" end
			end
			for j = #lines, 1, -1 do
				if #reverse >= maxRows then break end
				local line = lines[j]
				reverse[#reverse + 1] = {text = line, color = colors[kind] or white}
				longest = math.max(longest, #line)
			end
		end
	end
	data = table.create(#reverse)
	for i = #reverse, 1, -1 do
		data[#data + 1] = reverse[i]
	end
	canvasWidth = math.max(1, math.floor(body.AbsoluteSize.X - 8), longest * 8 + 8)
	body.CanvasSize = UDim2.fromOffset(canvasWidth, #data * rowHeight + 4)
	empty.Visible = #data == 0
	empty.Text = selected == "All" and query == "" and "No logs yet" or "No matching logs"
	for kind, tab in pairs(tabButtons) do
		tab.TextColor3 = kind == selected and white or colors[kind] or dim
	end
	tabButtons.All.Text = string.format("All %d", logs.MessageCount)
	tabButtons.Log.Text = string.format("Output %d", math.max(0, logs.MessageCount - logs.InfoCount - logs.WarningCount - logs.ErrorCount))
	tabButtons.Info.Text = string.format("Info %d", logs.InfoCount)
	tabButtons.Warn.Text = string.format("Warnings %d", logs.WarningCount)
	tabButtons.Error.Text = string.format("Errors %d", logs.ErrorCount)
	footer.Text = string.format("%d retained   %d matching   UTC   Read-only   F9 hide", #history, count)
	if follow then pendingBottom = 2 end
	renderRows(true)
end

local lastCount, lastGeneration = -1, -1
local lastWidth, lastHeight = 0, 0
local elapsed = 0.2
local searchElapsed = 0
local pendingQuery = ""
while true do
	local enabled = console.Enabled
	if screen.Enabled ~= enabled then
		if not enabled and search:IsFocused() then search:ReleaseFocus(false) end
		screen.Enabled = enabled
		dirty = true
	end
	if enabled then
		local nextQuery = string.lower(search.Text)
		if nextQuery ~= pendingQuery then
			pendingQuery = nextQuery
			searchElapsed = 0
		end
		if pendingQuery ~= query and searchElapsed >= 0.1 then
			query = pendingQuery
			dirty = true
			pendingBottom = 0
			body.CanvasPosition = Vector2.new(0, 0)
		end
		local width = math.max(1, math.min(780, screen.AbsoluteSize.X - 20))
		local height = math.max(1, math.min(480, screen.AbsoluteSize.Y - 20))
		if screen.AbsoluteSize.X > 0 and screen.AbsoluteSize.Y > 0 and (width ~= lastWidth or height ~= lastHeight) then
			panel.Size = UDim2.fromOffset(width, height)
			lastWidth, lastHeight = width, height
			dirty = true
		end
		if elapsed >= 0.2 or dirty then
			local count, generation = logs.MessageCount, logs.HistoryGeneration
			if dirty or count ~= lastCount or generation ~= lastGeneration then
				refresh()
				lastCount, lastGeneration = count, generation
				dirty = false
			end
			elapsed = 0
		end
		if pendingBottom > 0 then
			body.CanvasPosition = Vector2.new(body.CanvasPosition.X, math.max(0, #data * rowHeight + 4 - body.AbsoluteWindowSize.Y))
			pendingBottom -= 1
		end
		renderRows(false)
	end
	local dt = task.wait(enabled and 0 or 0.1)
	elapsed += dt
	searchElapsed += dt
end
`

Register_ConsoleOverlay :: proc(registry: ^Registry, vm_state: ^vm.VM) {
	if registry.classes.renderer == nil || registry.mode == .Server {
		return
	}
	script_object, script_ok := classes.Push_New(registry.classes, vm_state, "Script", false)
	assert(script_ok && script_object != nil)
	defer vm.Pop(vm_state.L)

	classes.Set_Name(script_object, "ConsoleOverlay")
	script_object.archivable = false
	classes.Set_Can_Replicate(script_object, false)
	script := cast(^classes.Script)script_object
	script.run_as_plugin = true
	script.run_context = .Client
	classes.Script_Set_Source(script, CONSOLE_OVERLAY_SOURCE)
	classes.Set_Parent(script_object, &registry.data_model.object)
}
