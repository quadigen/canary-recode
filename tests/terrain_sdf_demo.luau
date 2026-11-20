local Terrain = game:GetService("Terrain")
Terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(175, 175, 175))
Terrain.Decoration = false

Terrain:GenerateArea(0, 0, 96, {
	detail = "smooth",
	style = "sdf",
	seed = 12345,
	voxelSize = 2,
	seaLevel = -32,
	baseHeight = 150,
	mountainHeight = 95,
	hillHeight = 22,
	minY = -48,
	maxY = 160,
	scale = 100,
	octaves = 7,
	gain = 0.41,
	lacunarity = 2,
	surfaceAmplitude = 22,
	blendRadius = 6,
	rockSize = 9,
	rockDensity = 0.45,
	material = Enum.Material.Rock,
	caves = false,
	overhangs = true,
})
