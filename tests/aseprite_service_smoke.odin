package main

import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import aseprite "../src/engine/util/aseprite"
import vm "../src/engine/vm"
import "core:fmt"

fixture := [?]u8 {
	33,
	1,
	0,
	0,
	224,
	165,
	2,
	0,
	2,
	0,
	1,
	0,
	32,
	0,
	1,
	0,
	0,
	0,
	100,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	1,
	1,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	121,
	0,
	0,
	0,
	250,
	241,
	3,
	0,
	100,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	28,
	0,
	0,
	0,
	4,
	32,
	1,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	255,
	0,
	0,
	0,
	4,
	0,
	66,
	111,
	100,
	121,
	39,
	0,
	0,
	0,
	24,
	32,
	1,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	1,
	0,
	2,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	4,
	0,
	87,
	97,
	108,
	107,
	38,
	0,
	0,
	0,
	5,
	32,
	0,
	0,
	0,
	0,
	0,
	0,
	255,
	2,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	1,
	0,
	1,
	0,
	120,
	156,
	123,
	169,
	195,
	254,
	31,
	0,
	5,
	57,
	2,
	28,
	40,
	0,
	0,
	0,
	250,
	241,
	1,
	0,
	200,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	24,
	0,
	0,
	0,
	5,
	32,
	0,
	0,
	1,
	0,
	0,
	0,
	255,
	1,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
}

gif_fixture := [?]u8 {
	0x47,
	0x49,
	0x46,
	0x38,
	0x39,
	0x61,
	0x01,
	0x00,
	0x01,
	0x00,
	0x91,
	0x00,
	0x00,
	0xFF,
	0x00,
	0x00,
	0x00,
	0x00,
	0xFF,
	0x00,
	0xFF,
	0x00,
	0xFF,
	0xFF,
	0xFF,
	0x21,
	0xF9,
	0x04,
	0x04,
	0x0A,
	0x00,
	0x00,
	0x00,
	0x2C,
	0x00,
	0x00,
	0x00,
	0x00,
	0x01,
	0x00,
	0x01,
	0x00,
	0x00,
	0x02,
	0x02,
	0x44,
	0x01,
	0x00,
	0x21,
	0xF9,
	0x04,
	0x04,
	0x14,
	0x00,
	0x00,
	0x00,
	0x2C,
	0x00,
	0x00,
	0x00,
	0x00,
	0x01,
	0x00,
	0x01,
	0x00,
	0x00,
	0x02,
	0x02,
	0x4C,
	0x01,
	0x00,
	0x3B,
}

main :: proc() {
	parsed, parse_err := aseprite.load_from_memory(fixture[:])
	assert(parse_err == .None)
	assert(len(parsed.frames) == 2)
	assert(parsed.frames[0].pixels[0] == (aseprite.Color{233, 44, 7, 255}))
	assert(parsed.frames[1].pixels[0].a == 0)
	assert(parsed.frames[1].pixels[1] == (aseprite.Color{233, 44, 7, 255}))
	aseprite.destroy(parsed)

	v := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v)
	vm.PushBuffer(v.L, fixture[:])
	vm.SetGlobalFromStack(&v, "asepriteFixture")
	vm.PushBuffer(v.L, gif_fixture[:])
	vm.SetGlobalFromStack(&v, "gifFixture")
	ok, err := vm.Run(
		&v,
		`
local service = game:GetService("AsepriteService")
local info = service:GetInfo(asepriteFixture)
assert(info.Size.X == 2 and info.Size.Y == 1)
assert(info.FrameCount == 2)
assert(info.Durations[1] == 0.1 and info.Durations[2] == 0.2)
assert(info.Tags[1].Name == "Walk" and info.Tags[1].Direction == "PingPong")
assert(info.Tags[1].FromFrame == 1 and info.Tags[1].ToFrame == 2)
assert(info.Layers[1] == "Body")
local frames, metadata, animated = service:CreateImageLabels(asepriteFixture)
assert(#frames == 2 and metadata.FrameCount == 2)
assert(typeof(animated) == "Animated")
assert(animated == Animated.fromBuffer(asepriteFixture))
assert(animated == service:CreateAnimated(asepriteFixture))
assert(service:GetInfo(animated).FrameCount == 2)
local animatedLabel = Instance.new("ImageLabel", workspace)
animatedLabel.Name = "AnimatedLabelSmoke"
animatedLabel.ImageContent = animated
assert(animatedLabel.IsLoaded and animatedLabel.AnimatedContent == animated)
local clone = animatedLabel:Clone()
assert(clone.IsLoaded and clone.AnimatedContent == animated)
clone:Destroy()
local button = Instance.new("ImageButton")
button.AnimatedContent = animated
assert(button.IsLoaded and button.AnimatedContent == animated)
button:Destroy()
animatedLabel:SetAttribute("Animation", animated)
local gif = Animated.fromBytes(buffer.tostring(gifFixture))
local gifLabel = Instance.new("ImageLabel", workspace)
gifLabel.Name = "AnimatedGifSmoke"
gifLabel.Image = gif
assert(gifLabel.IsLoaded and gifLabel.AnimatedContent == gif)
assert(not pcall(function() Animated.fromBuffer(buffer.create(8)) end))
assert(frames[1]:IsA("ImageLabel") and frames[2]:IsA("ImageLabel"))
assert(frames[1].Parent == nil and frames[1].BackgroundTransparency == 1)
assert(frames[1].Size.X.Offset == 2 and frames[1].Size.Y.Offset == 1)
assert(frames[1].ResampleMode == Enum.ResampleMode.Nearest)
assert(frames[1].Image ~= frames[2].Image)
local asset = game:GetService("AssetService")
for i, frame in frames do
    local image = asset:CreateEditableImageAsync(Content.fromUri(frame.Image))
    local rgba = image:ReadPixelsBuffer(Vector2.new(0, 0), Vector2.new(2, 1))
    local offset = (i-1)*4
    assert(buffer.readu8(rgba, offset) == 233)
    assert(buffer.readu8(rgba, offset+1) == 44)
    assert(buffer.readu8(rgba, offset+2) == 7)
    assert(buffer.readu8(rgba, offset+3) == 255)
    assert(buffer.readu8(rgba, 4-offset+3) == 0)
    image:Destroy()
end
local label, duration = service:CreateImageLabel(buffer.tostring(asepriteFixture), 2)
assert(label.Image == frames[2].Image and duration == 0.2)
assert(not pcall(function() service:CreateImageLabel(asepriteFixture, 3) end))
assert(not pcall(function() service:CreateImageLabel(asepriteFixture, 1.5) end))
assert(not pcall(function() service:GetInfo(buffer.create(128)) end))
assert(not pcall(function() service:GetInfo("/etc/passwd") end))
for _, frame in frames do frame:Destroy() end
label:Destroy()
`,
		"aseprite_service_smoke",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("Aseprite service smoke failed")
	}
	root := classes.Find_First_Child(&env.services.data_model.object, "Workspace")
	gif_label := cast(^classes.ImageLabel)classes.Find_First_Child(root, "AnimatedGifSmoke")
	assert(gif_label != nil && kineffi.Kine_Skia_Image_IsAnimating(gif_label.stored_image) != 0)
	label := cast(^classes.ImageLabel)classes.Find_First_Child(root, "AnimatedLabelSmoke")
	assert(label != nil && label.aseprite_playback != nil)
	assert(label.aseprite_playback.frame == 0)
	surface := kineffi.Kine_Skia_Surface_Create(2, 1)
	assert(surface != nil)
	for i in 0 ..< 3 {
		kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
		kineffi.Kine_Skia_Surface_DrawImageSized(surface, label.stored_image, 0, 0, 2, 1, 255)
		kineffi.Kine_Skia_Surface_Flush(surface)
		r, g, b, a: u8
		kineffi.Kine_Skia_Surface_GetPixel(surface, i32(i % 2), 0, &r, &g, &b, &a)
		assert(r == 233 && g == 44 && b == 7 && a == 255)
		if i == 0 {classes.ImageLabel_Advance_Aseprite(label, 100)}
		if i == 1 {classes.ImageLabel_Advance_Aseprite(label, 200)}
	}
	kineffi.Kine_Skia_Surface_Destroy(surface)
	data, save_err := serializer.Serialize(&env.classes, v.L, &label.object)
	assert(save_err.kind == .None)
	defer delete(data)
	restored, load_err := serializer.Deserialize(&env.classes, v.L, root, data)
	assert(load_err.kind == .None && restored != nil)
	assert((cast(^classes.ImageLabel)restored).aseprite_playback != nil)
	classes.Push_Object(v.L, restored)
	vm.SetGlobalFromStack(&v, "restoredAnimated")
	ok, err = vm.Run(
		&v,
		`assert(typeof(restoredAnimated:GetAttribute("Animation")) == "Animated")
assert(restoredAnimated:GetAttribute("Animation") == restoredAnimated.AnimatedContent)`,
		"animated_roundtrip",
	)
	if !ok {fmt.eprintln(err); panic("animated serializer failed")}
	vm.Close(&v)
	engine_runtime.Environment_Destroy(&env)
	fmt.println("ASEPRITE SERVICE SMOKE PASSED")
}
