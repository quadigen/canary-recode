local gui = Instance.new("ScreenGui", game:GetService("CoreGui"))
gui.RenderOnTop = true
local service = game:GetService("GuiService")
for i = 1, 3 do
	local button = Instance.new("TextButton", gui)
	button.Position = UDim2.fromOffset(100, 100 + i * 64)
	button.Size = UDim2.fromOffset(220, 52)
	button.Text = "Option " .. i
	button.Selectable = true
	button.Activated:Connect(function()
		print("Activated", i)
	end)
end
service.GuiNavigationEnabled = true
