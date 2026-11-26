package main

import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(state: ^vm.VM, source: string) {
	ok, err := vm.Run(state, source, "rich_text")
	assert(ok, err)
}

render :: proc(env: ^runtime.Environment, state: ^vm.VM, surface: ^kineffi.KineSkiaSurface) {
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 255)
	runtime.Environment_Render_2D(env, state, surface, 320, 200, 1.0 / 60)
	runtime.Environment_Render_Overlay(env, state, surface, 320, 200, 1.0 / 60)
	kineffi.Kine_Skia_Surface_Flush(surface)
}

count_colors :: proc(
	surface: ^kineffi.KineSkiaSurface,
	top, bottom: i32,
) -> (
	red, green, blue: int,
) {
	for y in top ..< bottom {
		for x in 0 ..< 320 {
			r, g, b, a: u8
			kineffi.Kine_Skia_Surface_GetPixel(surface, i32(x), y, &r, &g, &b, &a)
			if r > 150 && g < 40 && b < 40 {red += 1}
			if g > 150 && r < 40 && b < 40 {green += 1}
			if b > 150 && r < 40 && g < 40 {blue += 1}
		}
	}
	return
}

main :: proc() {
	state := vm.New()
	view: renderer.RendererObject
	view.Cache2D = true
	env: runtime.Environment
	runtime.Environment_Init(&env, &state, &view)
	defer {vm.Close(&state); runtime.Environment_Destroy(&env)}
	surface := kineffi.Kine_Skia_Surface_Create(320, 200)
	assert(surface != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(surface)

	run(
		&state,
		`
local gui = Instance.new("ScreenGui", game.CoreGui)
label = Instance.new("TextLabel", gui)
label.Size = UDim2.fromOffset(320, 60)
label.BackgroundTransparency = 1
label.TextSize = 28
label.TextColor3 = Color3.new(0, 0, 1)
label.RichText = true
label.TextXAlignment = Enum.TextXAlignment.Left
label.Text = '<font color="#FF0000">help <font color="rgb(0,255,0)">me</font> now</font>!'
button = Instance.new("TextButton", gui)
button.Size = UDim2.fromOffset(320, 60)
button.Position = UDim2.fromOffset(0, 70)
button.BackgroundTransparency = 1
button.TextSize = 28
button.RichText = true
button.Text = '<font color="#00FF00">ping</font>'
assert(label:Clone().RichText and button:Clone().RichText)
`,
	)
	render(&env, &state, surface)
	red, green, blue := count_colors(surface, 0, 60)
	assert(red > 20 && green > 20 && blue > 0, "nested font colors not rendered")
	_, button_green, _ := count_colors(surface, 70, 130)
	assert(button_green > 20, "button rich text not rendered")
	run(
		&state,
		`
richWidth = label.TextBounds.X
label.Text = "help me now!"
label.RichText = false
`,
	)
	render(&env, &state, surface)
	run(
		&state,
		`assert(math.abs(richWidth - label.TextBounds.X) < 2, tostring(richWidth) .. "/" .. tostring(label.TextBounds.X))`,
	)
	run(
		&state,
		`
label.Text = '<font color="#FF0000">help</font>'
label.RichText = true
button.Text = '<font color="#FF0000">ping</font>'
`,
	)
	render(&env, &state, surface)
	red, green, blue = count_colors(surface, 0, 60)
	assert(red > 20 && green == 0 && blue == 0, "rich text update failed")
	button_red, button_green_after, _ := count_colors(surface, 70, 130)
	assert(button_red > 20 && button_green_after == 0, "rich button cache did not update")
	run(&state, `label.RichText = false; button.RichText = false`)
	render(&env, &state, surface)
	red, _, blue = count_colors(surface, 0, 60)
	assert(red == 0 && blue > 20, "disabling rich text did not invalidate cache")
	run(
		&state,
		`
label.RichText = true
label.Text = '<font color="#FF0000" size="36">A</font><br/>B &lt; &amp; &gt;'
local p = Instance.new("GetTextBoundsParams")
p.Text = label.Text
p.RichText = true
p.Size = 28
local rich = game:GetService("TextService"):GetTextBoundsAsync(p)
assert(rich.Y > 50)
`,
	)
	render(&env, &state, surface)
	run(&state, `assert(label.TextBounds.Y > 50)`)
	run(
		&state,
		`
label.Text = '<font face="Roboto" weight="700"><b>A<i>B</i>C</b></font><font face="RobotoMono">D</font><sup>2</sup><sub>3</sub>'
assert(label.ContentText == "ABCD23")
assert(label:Clone().ContentText == "ABCD23")
assert(not pcall(function() label.ContentText = "changed" end))
button.RichText = true
button.Text = '<b><i>Play</i></b>'
assert(button.ContentText == "Play")
label.TextWrapped = false
`,
	)
	render(&env, &state, surface)
	descriptor := classes.Find_Class(&env.classes, "TextLabel")
	label: ^classes.TextLabel
	for object in descriptor.instances {
		if object.parent != nil && len((cast(^classes.TextLabel)object).render_layout.lines) > 0 {
			candidate := cast(^classes.TextLabel)object
			if candidate.rich_text &&
			   len(candidate.render_layout.lines[0].rich_runs) == 6 {label = candidate; break}
		}
	}
	assert(label != nil)
	runs := label.render_layout.lines[0].rich_runs
	assert(runs[0].typeface != label.stored_typeface && runs[0].typeface == runs[2].typeface)
	assert(runs[1].typeface != runs[0].typeface && runs[3].typeface != runs[0].typeface)
	assert(runs[4].shift < 0 && runs[5].shift > 0)
	assert(runs[4].size < runs[0].size && runs[5].size < runs[0].size)

	run(
		&state,
		`
label.TextColor3 = Color3.new(1, 1, 1)
label.Text = '<mark color="#00FF00" transparency="0">A</mark><stroke color="#FF0000" thickness="4" transparency="0">B</stroke>'
`,
	)
	render(&env, &state, surface)
	red, green, blue = count_colors(surface, 0, 60)
	assert(red > 20 && green > 20, "stroke and highlight pixels missing")
	run(
		&state,
		`
label.Text = '<font face="Roboto" weight="700">Bold words</font> <i>italic words</i>'
label.TextWrapped = true
label.Size = UDim2.fromOffset(100, 140)
local p = Instance.new("GetTextBoundsParams")
p.Text = label.Text
p.Font = label.FontFace
p.Size = label.TextSize
p.Width = 100
p.RichText = true
expectedBounds = game:GetService("TextService"):GetTextBoundsAsync(p)
`,
	)
	render(&env, &state, surface)
	run(
		&state,
		`
assert(label.TextBounds.Y > 60)
assert(math.abs(label.TextBounds.X - expectedBounds.X) < 1)
assert(math.abs(label.TextBounds.Y - expectedBounds.Y) < 1)
label.RichText = false
assert(label.ContentText == label.Text)
`,
	)
	fmt.println("RICH_TEXT_SMOKE_PASSED")
}
