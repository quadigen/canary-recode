-- Run in an empty place to build the slate and ochre terrain preview.
local terrain = game:GetService("Terrain")
local lighting = game:GetService("Lighting")
local camera = workspace.CurrentCamera
local voxel = 0.1875
local stone = Enum.Material.Slate
local mineral = Enum.Material.Sandstone
local oxide = Enum.Material.Ground
local air = Enum.Material.Air

terrain:Clear()
terrain.Raymarching = true
terrain.FlatShading = false
terrain.VoxelSize = voxel
terrain.Decoration = false
terrain:SetMaterialColor(stone, Color3.fromRGB(137, 139, 144))
terrain:SetMaterialColor(mineral, Color3.fromRGB(201, 147, 26))
terrain:SetMaterialColor(oxide, Color3.fromRGB(146, 120, 80))

camera.CameraType = Enum.CameraType.Scriptable
camera.FieldOfView = 38
camera.CFrame = CFrame.lookAt(Vector3.new(9.4, 16.1, 19.9), Vector3.new(-1.1, 0.45, 1.05))
lighting.ClockTime = 14.15
lighting.Brightness = 1.55
lighting.ShadowSoftness = 0.81
lighting.ShadowMapSize = 4096
lighting.DynamicResolution = false
lighting.ExposureCompensation = 0.10
for _, effect in lighting:GetChildren() do
	if effect:IsA("LightingEffect") then
		effect.Enabled = false
	end
end
lighting.Atmosphere.SkyColor = Color3.fromRGB(137, 153, 177)
lighting.Atmosphere.HorizonColor = Color3.fromRGB(210, 215, 221)
lighting.AntiAliasingEffect.Enabled = true
lighting.AntiAliasingEffect.FXAA = true

local function bedHeight(x, z)
	local swell = math.noise(x * 0.06, z * 0.06, 6.8) * 0.82
	local brokenStone = math.noise(x * 0.23, z * 0.23, 1.8) * 0.31
	local patches = math.clamp(0.53 + 1.9 * math.noise(x * 0.14, z * 0.14, 2.4), 0.09, 1)
	local grain = math.noise(x * 0.72, z * 0.72, 4.1) * 0.20 * patches
	local grit = math.noise(x * 1.44, z * 1.44, 8.1) * 0.10 * patches
	return swell + brokenStone + grain + grit
end

local random = Random.new(68471)
local crystals = {}
local function addCrystal(x, z, halfSize, rise, pitch, yaw, roll, isBox)
	local angles = CFrame.Angles(pitch, yaw, roll)
	local _, _, _, xx, xy, xz, yx, yy, yz, zx, zy, zz = angles:GetComponents()
	local hx, hy, hz = halfSize.X, halfSize.Y, halfSize.Z
	table.insert(crystals, {
		x = x, y = bedHeight(x, z) + rise, z = z, isBox = isBox,
		hx = hx, hy = hy, hz = hz,
		invX = 1 / hx, invY = 1 / hy, invZ = 1 / hz,
		planeScale = 1 / math.sqrt(hx ^ -2 + hy ^ -2 + hz ^ -2),
		reach = if isBox then halfSize.Magnitude else math.max(hx, hy, hz),
		xx = xx, xy = xy, xz = xz, yx = yx, yy = yy, yz = yz, zx = zx, zy = zy, zz = zz,
	})
end

-- Leave a clear outline around the exposed foreground crystals.
addCrystal(-3.45, 5.9, Vector3.new(2.05, 2.18, 1.87), 1.29, 0.37, 0.15, -0.29, false)
addCrystal(2.3, 5.75, Vector3.new(0.97, 1.18, 0.88), 0.77, 0.41, -0.38, 0.19, true)
addCrystal(-5.3, 1.5, Vector3.new(1.37, 1.56, 1.23), 0.64, 0.31, 0.21, 0.28, false)
addCrystal(4.85, -3.85, Vector3.new(1.36, 1.60, 1.34), 0.58, -0.21, 0.77, 0.24, false)
local exposedCount = #crystals

local function crystalDistance(crystal, x, y, z)
	local dx, dy, dz = x - crystal.x, y - crystal.y, z - crystal.z
	local px = math.abs(dx * crystal.xx + dy * crystal.yx + dz * crystal.zx)
	local py = math.abs(dx * crystal.xy + dy * crystal.yy + dz * crystal.zy)
	local pz = math.abs(dx * crystal.xz + dy * crystal.yz + dz * crystal.zz)
	if crystal.isBox then
		return math.max(px - crystal.hx, py - crystal.hy, pz - crystal.hz)
	end
	return (px * crystal.invX + py * crystal.invY + pz * crystal.invZ - 1) * crystal.planeScale
end

for row = -4, 4 do
	for column = -3, 3 do
		local reach = (row / 4.6) ^ 2 + (column / 3.2) ^ 2
		if reach < 1.22 and random:NextNumber() > 0.08 then
			local x = column * 1.93 - row * 0.43 + random:NextNumber(-0.53, 0.53)
			local z = row * 2.12 + random:NextNumber(-0.63, 0.63)
			local size = random:NextNumber(0.85, 1.47)
			local room = true
			for i = 1, exposedCount do
				local exposed = crystals[i]
				local gap = exposed.reach + size * 0.92 + 0.05
				if (x - exposed.x) ^ 2 + (z - exposed.z) ^ 2 < gap ^ 2 then
					room = false
					break
				end
			end
			if room then
				local halfSize = Vector3.new(size, size * random:NextNumber(0.78, 1.2), size * random:NextNumber(0.83, 1.13))
				addCrystal(x, z, halfSize, size * random:NextNumber(0.14, 0.46),
					random:NextNumber(-0.34, 0.35), random:NextNumber(0, 2 * math.pi),
					random:NextNumber(-0.41, 0.41), false)
			end
		end
	end
end

-- Low crystals overlap in the center of the deposit.
addCrystal(-0.30, -0.40, Vector3.new(1.32, 1.02, 1.70), 0.17, 0.20, 1.37, 0.09, false)
addCrystal(1.08, 0.18, Vector3.new(1.49, 1.07, 1.42), 0.12, -0.16, 0.72, 0.16, false)
addCrystal(0.52, -1.60, Vector3.new(1.56, 0.91, 1.63), 0.06, 0.23, 0.47, -0.21, false)

local function smoothUnion(a, b, radius)
	if radius <= 0 then
		return math.min(a, b)
	end
	local overlap = math.max(radius - math.abs(a - b), 0) / radius
	return math.min(a, b) - 0.25 * radius * overlap ^ 2
end

local minX, maxX = -282, 223
local minY, maxY = -9, 26
local minZ, maxZ = -302, 174
local countX, countY, countZ = maxX - minX, maxY - minY, maxZ - minZ
local materials, occupancies = table.create(countX), table.create(countX)
for ix = 1, countX do
	local x = (minX + ix - 1) * voxel
	materials[ix], occupancies[ix] = table.create(countY), table.create(countY)
	for iy = 1, countY do
		materials[ix][iy], occupancies[ix][iy] = table.create(countZ), table.create(countZ)
	end
	for iz = 1, countZ do
		local z = (minZ + iz - 1) * voxel
		local ground = bedHeight(x, z)
		local nearby = {}
		for _, crystal in crystals do
			local dx, dz = x - crystal.x, z - crystal.z
			local bound = crystal.reach + 1.45
			if dx * dx + dz * dz < bound * bound then
				table.insert(nearby, crystal)
			end
		end
		for iy = 1, countY do
			local y = (minY + iy - 1) * voxel
			local bed = (y - ground) * 0.86
			local deposit = 16
			for _, crystal in nearby do
				deposit = math.min(deposit, crystalDistance(crystal, x, y, z))
			end
			-- Blend the rock into the bed at its foot. The exposed faces keep
			-- their plane equations all the way to the crystal edges.
			local blend = 0.94 * math.clamp((0.48 - bed) / 0.72, 0, 1)
			local density = math.clamp(0.5 - smoothUnion(bed, deposit, blend) / (3.4 * voxel), 0, 1)
			local material = stone
			if density == 0 then
				material = air
			elseif bed > 0.24 and deposit < bed then
				material = mineral
			elseif deposit < bed + 0.25 then
				material = oxide
			end
			occupancies[ix][iy][iz] = density
			materials[ix][iy][iz] = material
		end
	end
end

terrain:WriteVoxels(Region3.new(
	Vector3.new(minX * voxel, minY * voxel, minZ * voxel),
	Vector3.new(maxX * voxel, maxY * voxel, maxZ * voxel)
), voxel, materials, occupancies)
