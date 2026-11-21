package main

import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"

run :: proc(v: ^vm.VM, script: string, name: string) {
	ok, err := vm.Run(v, script, name)
	if !ok {fmt.eprintln(err); delete(err); panic("2D instances smoke failed")}
}
pixel :: proc(s: ^renderer.Skia_Surface, x, y: i32) -> [4]u8 {
	p: [4]u8; kineffi.Kine_Skia_Surface_GetPixel(s, x, y, &p[0], &p[1], &p[2], &p[3]); return p
}
main :: proc() {
	v := vm.New(); r: renderer.RendererObject; e: runtime.Environment
	runtime.Environment_Init(&e, &v, &r)
	s := kineffi.Kine_Skia_Surface_Create(
		320,
		240,
	); assert(s != nil); defer kineffi.Kine_Skia_Surface_Destroy(s)
	png := []u8 {
		137,
		80,
		78,
		71,
		13,
		10,
		26,
		10,
		0,
		0,
		0,
		13,
		73,
		72,
		68,
		82,
		0,
		0,
		0,
		8,
		0,
		0,
		0,
		4,
		8,
		6,
		0,
		0,
		0,
		179,
		205,
		126,
		240,
		0,
		0,
		0,
		19,
		73,
		68,
		65,
		84,
		120,
		156,
		99,
		248,
		207,
		192,
		240,
		31,
		25,
		99,
		129,
		180,
		86,
		0,
		0,
		97,
		4,
		63,
		193,
		125,
		240,
		118,
		91,
		0,
		0,
		0,
		0,
		73,
		69,
		78,
		68,
		174,
		66,
		96,
		130,
	}
	classes.ImageLabel_Register_Runtime_Image("memory://2d-test.png", string(png))
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
	vm.PushBuffer(v.L, gif_fixture[:])
	vm.SetGlobalFromStack(&v, "gifFixture")
	run(
		&v,
		`
workspace.Dimension = Enum.Dimension.D2
world = Instance.new("World2D", workspace)
physics = game:GetService("Workspace2D")
physics.Gravity = Vector2.new(0,0)
local folder = Instance.new("Folder",world)
marker = Instance.new("Attachment2D",folder)
marker.Position = UDim2.fromOffset(40,40)
assert(marker:IsA("GuiObject"))


sprite=Instance.new("Sprite2D",world)
sprite.Image="memory://2d-test.png"
sprite.Size=UDim2.fromOffset(20,20)
sprite.Position=UDim2.fromOffset(30,20)
sprite.FrameGrid=Vector2.new(2,1)
sprite.Frame=1
assert(sprite.IsLoaded)
anim=Instance.new("Sprite2D",world)
anim.Image="memory://2d-test.png"
anim.Size=UDim2.fromOffset(20,20)
anim.Position=UDim2.fromOffset(70,20)
anim.FrameGrid=Vector2.new(2,1)
anim.FrameRate=10
anim:Play()

gifAnimation=game:GetService("AssetService"):CreateImage({Buffer=gifFixture})
assert(gifAnimation:IsA("Image") and gifAnimation.Source~="")
gifSprite=Instance.new("Sprite2D",world)
gifSprite.Name="AnimatedGifSprite"
gifSprite.Image=gifAnimation
gifSprite.Position=UDim2.fromOffset(130,20)
gifSprite.Size=UDim2.fromOffset(20,20)
-- Old sheet settings must not crop or advance the animated asset.
gifSprite.FrameGrid=Vector2.new(2,2)
gifSprite:Play()
assert(gifSprite.IsLoaded and gifSprite.Image==gifAnimation)
local gifClone=gifSprite:Clone()
assert(gifClone.IsLoaded and gifClone.Image==gifAnimation)
gifClone:Destroy()

line=Instance.new("Shape2D",world)
line.Position=UDim2.fromOffset(5,60)
line.Points={Vector2.new(0,0),Vector2.new(30,0)}
line.Thickness=4
line.Color=Color3.new(0,0,1)
assert(#line.Points==2)
local copy=line:Clone()
assert(#copy.Points==2)
copy.Points={Vector2.new(0,0),Vector2.new(30,0),Vector2.new(40,10)}
assert(#copy.Points==3 and #line.Points==2)
copy:Destroy()
poly=Instance.new("Shape2D",world)
poly.Position=UDim2.fromOffset(100,60)
poly.Points={Vector2.new(0,0),Vector2.new(20,0),Vector2.new(0,20)}
poly.Color=Color3.new(1,1,0)
poly.Closed=true

floor=Instance.new("Part2D",world)
floor.Size=UDim2.fromOffset(320,30)
floor.Position=UDim2.fromOffset(0,180)
assert(floor.Anchored and floor:IsA("Part2D"))
wall=Instance.new("Part2D",world)
wall.Position=UDim2.fromOffset(240,100)
wall.Size=UDim2.fromOffset(20,80)
dynamic=Instance.new("Part2D",world)
dynamic.Position=UDim2.fromOffset(260,20)
dynamic.Size=UDim2.fromOffset(16,16)
dynamic.Anchored=false
assert(not dynamic.Anchored)

area=Instance.new("Trigger2D",world)
area.Position=UDim2.fromOffset(10,170)
area.Size=UDim2.fromOffset(40,40)
entered=0
exited=0
area.Touched:Connect(function(body) if body==floor then entered+=1 end end)
area.TouchEnded:Connect(function(body) if body==floor then exited+=1 end end)
player=Instance.new("CharacterController2D",world)
player.Position=UDim2.fromOffset(170,100)
player.Size=UDim2.fromOffset(20,20)
player.BackgroundColor3=Color3.new(0.5,0,0.5)
assert(player:IsA("Part2D"))
for _,name in ipairs({"Node2D","Marker2D","AnimatedSprite2D","Area2D","RayCast2D",
    "StaticBody2D","DynamicBody2D","AnimatableBody2D","CharacterBody2D","Line2D","Polygon2D","WorldObject2D"}) do
    assert(not pcall(Instance.new,name),name)
end
`,
		"nodes_setup",
	)
	kineffi.Kine_Skia_Surface_Clear(s, 0, 0, 0, 0)
	runtime.Environment_Render_2D(&e, &v, s, 320, 240, 0); kineffi.Kine_Skia_Surface_Flush(s)
	assert(pixel(s, 40, 30) == [4]u8{0, 255, 0, 255}, "sprite sheet crop")
	assert(pixel(s, 80, 30) == [4]u8{255, 0, 0, 255}, "animation first frame")
	assert(pixel(s, 15, 60) == [4]u8{0, 0, 255, 255}, "line")
	assert(pixel(s, 105, 65) == [4]u8{255, 255, 0, 255}, "polygon")
	assert(
		pixel(s, 135, 25) == [4]u8{255, 0, 0, 255},
		"Animated GIF first frame not cropped by FrameGrid",
	)
	time.sleep(150 * time.Millisecond)
	kineffi.Kine_Skia_Surface_Clear(s, 0, 0, 0, 0)
	runtime.Environment_Render_2D(&e, &v, s, 320, 240, 0); kineffi.Kine_Skia_Surface_Flush(s)
	assert(pixel(s, 135, 25) == [4]u8{0, 0, 255, 255}, "Animated GIF frame did not advance")
	for _ in 0 ..< 7 {runtime.Environment_Update_Step(&e, &v, 1.0 / 60)}
	run(
		&v,
		`
assert(marker.AbsolutePosition == Vector2.new(40,40),tostring(marker.AbsolutePosition))
assert(physics.BodyCount==4,tostring(physics.BodyCount))
assert(anim.Frame==1,tostring(anim.Frame))
assert(gifSprite.Frame==0,"AnimatedContent must not advance sprite-sheet frames")
assert(#area:GetTouchingParts()==1 and area:GetTouchingParts()[1]==floor)
assert(entered==1,tostring(entered))
area.Enabled=false
assert(#area:GetTouchingParts()==0)
local hit=physics:Raycast(Vector2.new(50,100),Vector2.new(0,150))
assert(hit and hit.Instance==floor and math.abs(hit.Distance-80)<0.2)
player.Velocity=Vector2.new(0,400)
assert(player:Move(0.25))
assert(player.Grounded,tostring(player.Position.Y.Offset))
assert(player.Position.Y.Offset>155 and player.Position.Y.Offset<162,tostring(player.Position.Y.Offset))
assert(math.abs(player.Velocity.Y)<0.01)
player.Velocity=Vector2.new(400,0)
assert(player:Move(0.25))
assert(player.Position.X.Offset>215 and player.Position.X.Offset<222,tostring(player.Position.X.Offset))
anim:Stop()
assert(anim.Frame==0 and not anim.Playing)
camera=Instance.new("Camera2D", world)
camera.Position=UDim2.fromOffset(40,30)
camera.Zoom=2
local hud=Instance.new("ScreenGui")
local dot=Instance.new("Frame",hud)
dot.BackgroundColor3=Color3.new(1,0,1)
dot.Position=UDim2.fromOffset(0,0)
dot.Size=UDim2.fromOffset(6,6)
`,
		"nodes_physics",
	)
	kineffi.Kine_Skia_Surface_Clear(s, 0, 0, 0, 0)
	runtime.Environment_Render_2D(&e, &v, s, 320, 240, 0); kineffi.Kine_Skia_Surface_Flush(s)
	assert(pixel(s, 160, 120) == [4]u8{0, 255, 0, 255}, "camera centers sprite")
	assert(pixel(s, 2, 2) == [4]u8{255, 0, 255, 255}, "camera does not affect HUD")
	run(&v, `
world.Enabled=false
assert(#area:GetTouchingParts()==0)
`, "nodes_disable")
	for _ in 0 ..< 3 {runtime.Environment_Update_Step(&e, &v, 1.0 / 60)}
	run(&v, `assert(physics.BodyCount==0 and exited==1,tostring(exited))`, "nodes_disabled")
	vm.GetGlobal(v.L, "world")
	world := cast(^classes.Object)vm.UserdataValue(v.L, -1)
	vm.Pop(v.L)
	data, save_error := serializer.Serialize(&e.classes, v.L, world)
	if !serializer.Error_Is_None(
		save_error,
	) {fmt.eprintln(serializer.Error_String(save_error)); panic("2D serialize")}
	defer delete(data)
	loaded, load_error := serializer.Deserialize(&e.classes, v.L, nil, data)
	if !serializer.Error_Is_None(
		load_error,
	) {fmt.eprintln(serializer.Error_String(load_error)); panic("2D deserialize")}
	classes.Push_Object(v.L, loaded)
	vm.SetGlobal(v.L, "loaded")
	run(
		&v,
		`
local shapes={}
for _,child in loaded:GetChildren() do if child:IsA("Shape2D") then table.insert(shapes,child) end end
assert(#shapes==2)
assert(#shapes[1].Points==2 and shapes[1].Points[2]==Vector2.new(30,0))
assert(#shapes[2].Points==3 and shapes[2].Points[3]==Vector2.new(0,20))
assert(loaded:FindFirstChildOfClass("Camera2D").Zoom==2)
local spr=loaded:FindFirstChildOfClass("Sprite2D")
assert(spr.FrameGrid==Vector2.new(2,1) and spr.Frame==1 and spr.IsLoaded, spr.Image)
assert(string.find(spr.Image,"kineasset://",1,true)==1, spr.Image)
local restoredGif=loaded:FindFirstChild("AnimatedGifSprite")
assert(restoredGif.IsLoaded and type(restoredGif.Image)=="string")
assert(restoredGif.FrameGrid==Vector2.new(2,2))
restoredGif.Image=gifAnimation
assert(restoredGif.IsLoaded and restoredGif.Image==gifAnimation)
restoredGif.Image=""
assert(not restoredGif.IsLoaded and restoredGif.Image=="")
restoredGif.Image=gifAnimation.Source
assert(restoredGif.IsLoaded and restoredGif.Image==gifAnimation.Source)
loaded:Destroy()
`,
		"nodes_roundtrip",
	)
	vm.Close(&v); runtime.Environment_Destroy(&e)
	fmt.println("INSTANCES2D_SMOKE_PASSED")
}
