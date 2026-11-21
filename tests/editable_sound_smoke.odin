package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	state := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &state)
	source := `
local assets = game:GetService("AssetService")
local audio = assets:CreateEditableSound({SampleRate=16000, Channels=2, FrameCount=4})
assert(audio.SampleRate == 16000 and audio.Channels == 2 and audio.FrameCount == 4)
assert(audio.TimeLength == 4/16000)
local samples = buffer.create(32)
buffer.writef32(samples, 0, 0.5)
buffer.writef32(samples, 4, -0.25)
audio:WriteSamplesBuffer(0, 4, samples)
assert(audio:GetSample(0, 0) == 0.5 and audio:GetSample(0, 1) == -0.25)
assert(buffer.readf32(audio:ReadSamplesBuffer(0, 1), 4) == -0.25)
audio:SetSample(3, 1, 0.75)
audio:Resize(8)
assert(audio.FrameCount == 8 and audio:GetSample(3, 1) == 0.75 and audio:GetSample(7, 0) == 0)
assert(not pcall(function() audio:SetSample(0, 0, 0/0) end))
assert(not pcall(function() audio:WriteSamplesBuffer(7, 2, samples) end))
assert(not pcall(function() assets:CreateEditableSound({Channels=3}) end))
local invalid = buffer.create(8)
buffer.writef32(invalid, 0, 1)
buffer.writef32(invalid, 4, 2)
assert(not pcall(function() audio:WriteSamplesBuffer(0, 1, invalid) end))
assert(audio:GetSample(0,0) == 0.5)
local clone = audio:Clone()
clone:Clear()
assert(clone:GetSample(0, 0) == 0 and audio:GetSample(0, 0) == 0.5)
local content = Content.fromObject(audio)
assert(content.IsObject and content.GetObject == audio)
local player = Instance.new("Sound")
player.EditableSound = audio
assert(player.EditableSound == audio and player.AudioContent == content)
player.Volume = 0
audio:Resize(16000)
player:Play()
assert(player.IsLoaded and player.IsPlaying and player.TimeLength == 1)
player:Pause()
assert(not player.IsPlaying)
player.TimePosition = 0.5
assert(player.TimePosition == 0.5)
player:Resume()
assert(player.IsPlaying)
player:Stop()
assert(not player.IsPlaying and player.TimePosition == 0)
audio:Resize(32000)
player.Playing = true
assert(player.IsPlaying and player.TimeLength == 2)
player.Playing = false
assert(not player.IsPlaying)
player.AudioContent = Content.fromObject(clone)
assert(player.EditableSound == clone)
clone:Destroy()
assert(player.EditableSound == nil)
player:Play()
assert(not player.IsPlaying)
player.EditableSound = nil
assert(player.EditableSound == nil)
player:Destroy()
audio:Destroy()
`
	ok, err := vm.Run(&state, source, "editable_sound_smoke")
	if !ok {fmt.eprintln(err); panic("EditableSound smoke failed")}
	vm.Close(&state)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("EDITABLE_SOUND_SMOKE_PASSED")
}
