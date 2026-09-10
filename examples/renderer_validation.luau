local camera = workspace.CurrentCamera
local Vector3 = {new = vector.create}
assert(camera and camera:IsA("Camera"))
camera.CFrame = CFrame.new(0, 4, 14) * CFrame.Angles(-0.15, 0, 0)

local function part(name, position, size, color)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored = true
    p.CFrame = CFrame.new(position)
    p.Size = size
    p.Color = color
    p.Parent = workspace
    return p
end

part("Ground", Vector3.new(0, -1, 0), Vector3.new(60, 1, 60), Color3.fromRGB(130, 145, 155))
part("Red", Vector3.new(-4, 1, 0), Vector3.new(2, 3, 2), Color3.fromRGB(235, 55, 40))
part("Green", Vector3.new(0, 1, 0), Vector3.new(2, 3, 2), Color3.fromRGB(50, 200, 75))
part("Blue", Vector3.new(4, 1, 0), Vector3.new(2, 3, 2), Color3.fromRGB(40, 100, 235))
print("Renderer validation: WASD to move, Q/E down/up, hold right mouse to look.")
