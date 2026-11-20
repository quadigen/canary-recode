local players = game:GetService("Players")
local player = players.LocalPlayer
local parent = player and player:FindFirstChild("PlayerGui") or game:GetService("CoreGui")
local old = parent:FindFirstChild("VRDemo")
if old then
	old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "VRDemo"
gui.RenderOnTop = true
gui.DisplayOrder = 1000
gui.Parent = parent

local label = Instance.new("TextLabel")
label.Name = "Status"
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.Size = UDim2.fromOffset(240, 56)
label.BackgroundColor3 = Color3.fromRGB(24, 30, 42)
label.BackgroundTransparency = 0.25
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextSize = 20
label.Text = "Native Skia VR"
label.Parent = gui

local corner = Instance.new("UICorner", label)
corner.CornerRadius = UDim.new(0, 10)
