local Part = Instance.new("Part")
Part.Anchored = true
Part.Size = vector.create(1000, 3, 1000)
Part.Material = Enum.Material.Grass
Part.Parent = workspace

local screenGui = Instance.new("ScreenGui")
screenGui.Parent = game.StarterGui

local frame = Instance.new("Frame")
frame.Parent = screenGui
frame.BackgroundTransparency = 0.5

Instance.new("UIBackdrop").Parent = frame
