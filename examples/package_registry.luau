local Argon = require("@engine/Argon")
local Immco = require("@engine/Immco")

assert(Argon == require("@Argon"), "legacy Argon package alias did not resolve")
assert(Immco == require("@Immco"), "legacy Immco package alias did not resolve")

renderer.Pool.new("2d", function()
	Argon:DrawRectangle({
		X = 24,
		Y = 24,
		Width = 180,
		Height = 72,
		Color = Argon:RGBA(35, 105, 210, 255),
	})

	Immco.Text({
		x = 42,
		y = 65,
		text = "@engine packages",
		TextSize = 18,
		Color = { R = 1, G = 1, B = 1, A = 1 },
	})
end)

print("engine package registry loaded")
