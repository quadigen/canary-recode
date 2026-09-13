local Part = Instance.new("Part")
Part.Anchored = true
Part.Size = vector.create(1000, 3, 1000)
Part.Material = Enum.Material.Grass
Part.Parent = workspace

local screenGui = Instance.new("ScreenGui")
screenGui.Parent = game.StarterGui

local mesh = Instance.new("Part")
mesh.Anchored = true
mesh.CFrame = CFrame.new(0, 10, 0)
mesh.Shape = Enum.PartType.Truss
mesh.Parent = workspace
