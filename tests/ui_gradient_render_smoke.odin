package main
import kineffi "../src/engine/bindings"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
pixel :: proc(s: ^kineffi.KineSkiaSurface, x, y: i32) -> [4]u8 {
	c: [4]u8; kineffi.Kine_Skia_Surface_GetPixel(s, x, y, &c[0], &c[1], &c[2], &c[3]); return c
}
run :: proc(v: ^vm.VM, source: string) {ok, err := vm.RunInternal(v, source, "gradient_regression")
	if !ok {fmt.eprintln(err); panic("script failed")}}
main :: proc() {
	v := vm.New(); env: engine_runtime.Environment; r: renderer.RendererObject
	engine_runtime.Environment_Init(&env, &v, &r)
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}
	run(
		&v,
		`
local screen=Instance.new("ScreenGui")
function frame(x,y,w,h,color,parent)
 local f=Instance.new("Frame",parent or screen);f.Position=UDim2.fromOffset(x,y);f.Size=UDim2.fromOffset(w,h);f.BackgroundColor3=color;return f
end
local white,red,blue=Color3.new(1,1,1),Color3.new(1,0,0),Color3.new(0,0,1)
base=frame(0,0,100,100,white)
g=Instance.new("UIGradient",base);assert(g.Enabled)
g.Color=ColorSequence.new(red,blue);g.Transparency=NumberSequence.new(0,1)
local corner=Instance.new("UICorner",base);corner.CornerRadius=UDim.new(0,20)
local hsv=frame(110,0,100,100,red)
local sat=frame(0,0,100,100,white,hsv)
local s=Instance.new("UIGradient",sat);s.Transparency=NumberSequence.new(0,1)
local val=frame(0,0,100,100,Color3.new(0,0,0),hsv)
local b=Instance.new("UIGradient",val);b.Transparency=NumberSequence.new(1,0);b.Rotation=90
local bar=frame(0,120,210,20,white)
local hue=Instance.new("UIGradient",bar)
hue.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,red),ColorSequenceKeypoint.new(1/6,Color3.new(1,1,0)),ColorSequenceKeypoint.new(2/6,Color3.new(0,1,0)),ColorSequenceKeypoint.new(3/6,Color3.new(0,1,1)),ColorSequenceKeypoint.new(4/6,blue),ColorSequenceKeypoint.new(5/6,Color3.new(1,0,1)),ColorSequenceKeypoint.new(1,red)})
local rotated=frame(220,0,100,100,white)
local rg=Instance.new("UIGradient",rotated);rg.Color=ColorSequence.new(red,blue);rg.Rotation=90;rg.Offset=Vector2.new(0,.25)
local copy=rg:Clone();assert(copy.Enabled and copy.Offset==rg.Offset and copy.Color==rg.Color);copy:Destroy()
`,
	)
	s := kineffi.Kine_Skia_Surface_Create(
		340,
		160,
	); assert(s != nil); defer kineffi.Kine_Skia_Surface_Destroy(s)
	draw :: proc(
		env: ^engine_runtime.Environment,
		v: ^vm.VM,
		s: ^kineffi.KineSkiaSurface,
	) {kineffi.Kine_Skia_Surface_Clear(s, 0, 0, 0, 0); engine_runtime.Environment_Render_2D(
			env,
			v,
			s,
			340,
			160,
			1.0 / 60.0,
		)
		kineffi.Kine_Skia_Surface_Flush(s)}
	draw(&env, &v, s)
	left, middle, right := pixel(s, 5, 50), pixel(s, 50, 50), pixel(s, 94, 50)
	fmt.println("gradient", left, middle, right)
	assert(left[0] > 220 && left[3] > 230 && right[2] > 220 && right[3] < 30)
	assert(
		middle[0] > 110 &&
		middle[0] < 145 &&
		middle[2] > 110 &&
		middle[3] > 110 &&
		middle[3] < 145,
	)
	assert(pixel(s, 0, 0)[3] == 0, "rounded gradient leaked")
	tl, tr, bl, br := pixel(s, 111, 1), pixel(s, 208, 1), pixel(s, 111, 98), pixel(s, 208, 98)
	fmt.println("HSV", tl, tr, bl, br)
	assert(tl[0] > 240 && tl[1] > 235 && tl[2] > 235 && tr[0] > 240 && tr[1] < 12 && tr[2] < 12)
	assert(bl[0] < 8 && bl[1] < 8 && br[0] < 8 && br[1] < 8)
	green := pixel(
		s,
		70,
		130,
	); assert(green[1] > 245 && green[0] < 12 && green[2] < 12, "multi-stop hue bar failed")
	rotation := pixel(
		s,
		270,
		50,
	); assert(rotation[0] > 180 && rotation[2] > 50 && rotation[2] < 80, "rotation or offset failed")
	run(
		&v,
		`g.Enabled=false`,
	); draw(&env, &v, s); assert(pixel(s, 50, 50) == [4]u8{255, 255, 255, 255})
	run(
		&v,
		`g.Enabled=true;g.Transparency=NumberSequence.new(0);g.Color=ColorSequence.new(Color3.new(0,1,0))`,
	)
	draw(&env, &v, s); assert(pixel(s, 50, 50) == [4]u8{0, 255, 0, 255}, "sequence update failed")
	run(
		&v,
		`g.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(1,0,0)),ColorSequenceKeypoint.new(.5,Color3.new(0,1,0)),ColorSequenceKeypoint.new(1,Color3.new(0,0,1))})`,
	)
	draw(&env, &v, s); assert(pixel(s, 50, 50)[1] > 245, "changed stop count failed")
	fmt.println("UI_GRADIENT_RENDER_PASSED")
}
