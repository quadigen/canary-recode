if IsServer or IsClient then
	return
end

local UI = require("@internal/editor_ui")
local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme
local LogService = game:GetService("LogService")
local colors = UI.colors
local tokens = UI.tokens

local panel, content, header = UI.window("Output", theme.OutputCoordinates.Position, theme.OutputCoordinates.Size, "")
panel.Position =
	UDim2.new(panel.Position.X.Scale, panel.Position.X.Offset, panel.Position.Y.Scale, panel.Position.Y.Offset)
UI.tab(header, "Output", UDim2.fromOffset(4, 0), UDim2.fromOffset(64, UI.metrics.windowHeader), true, function() end)
UI.input(header, "Filter output...", UDim2.fromOffset(76, 3), UDim2.new(1, -84, 0, 21))
local logList = UI.group(content, UDim2.fromOffset(5, 5), UDim2.new(1, -10, 1, -10), {
	color = tokens.color.surface,
})

local lastSignature = ""
local function logColor(kind)
	local name = tostring(kind or "")
	if string.find(name, "Error", 1, true) then
		return colors.error
	elseif string.find(name, "Warning", 1, true) or string.find(name, "Warn", 1, true) then
		return colors.warning
	end
	return colors.text
end

local function rebuild(history)
	UI.clear(logList)
	if #history == 0 then
		UI.label(
			logList,
			"No logs yet.",
			UDim2.fromOffset(10, 12),
			UDim2.new(1, -20, 0, 20),
			tokens.type.small,
			colors.subtext
		)
		return
	end

	local start = math.max(1, #history - 18)
	local y = 1
	for index = start, #history do
		local log = history[index]
		local timestamp = log.timestamp and os.date("%H:%M:%S", log.timestamp) or string.format("%08.3f", log.time or 0)
		local row = UI.frame(
			logList,
			UDim2.fromOffset(1, y),
			UDim2.new(1, -2, 0, 19),
			index % 2 == 0 and tokens.color.rowEven or tokens.color.rowOdd
		)
		UI.label(row, timestamp, UDim2.fromOffset(8, 2), UDim2.fromOffset(70, 16), tokens.type.caption, colors.muted)
		UI.separator(row, UDim2.fromOffset(78, 0), UDim2.fromOffset(1, 19))
		UI.label(
			row,
			tostring(log.message or ""),
			UDim2.fromOffset(86, 2),
			UDim2.new(1, -94, 0, 16),
			tokens.type.small,
			logColor(log.messageType or log.kind)
		)
		y += 19
	end
end

renderer.Pool.new("2d", function()
	panel.Size = theme.OutputCoordinates.Size
	panel.Position = UDim2.new(
		theme.OutputCoordinates.Position.X.Scale,
		theme.OutputCoordinates.Position.X.Offset,
		theme.OutputCoordinates.Position.Y.Scale,
		theme.OutputCoordinates.Position.Y.Offset
	)
	local history = LogService:GetLogHistory()
	local pieces = { tostring(#history) }
	for index = math.max(1, #history - 18), #history do
		local log = history[index]
		if log then
			table.insert(pieces, tostring(log.message))
		end
	end
	local signature = table.concat(pieces, "|")
	if signature ~= lastSignature then
		lastSignature = signature
		rebuild(history)
	end
end)

