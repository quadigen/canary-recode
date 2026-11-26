package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	source := `
local assetService = game:GetService("AssetService")
local source = assetService:CreateEditableSound({SampleRate=16000, Channels=1, FrameCount=32000})
local sound = Instance.new("Sound")
local count = {Loaded=0, Played=0, Paused=0, Resumed=0, Stopped=0, Ended=0, DidLoop=0}
for name in pairs(count) do
    sound[name]:Connect(function(...)
        assert(select("#", ...) == 0, name .. " event should have no arguments")
        count[name] += 1
    end)
end
assert(not sound.IsLoaded)
sound.EditableSound = source
assert(sound.IsLoaded and count.Loaded == 1)

sound:Play()
assert(sound.IsPlaying and count.Played == 1)
sound:Play()
assert(count.Played == 1, "already-playing Play must not duplicate event")
sound:Pause()
assert(not sound.IsPlaying and count.Paused == 1)
sound:Pause()
assert(count.Paused == 1, "repeated Pause must not duplicate event")
sound:Resume()
assert(sound.IsPlaying and count.Resumed == 1)
sound:Resume()
assert(count.Resumed == 1, "repeated Resume must not duplicate event")
sound:Stop()
assert(not sound.IsPlaying and count.Stopped == 1)
sound:Stop()
assert(count.Stopped == 1, "repeated Stop must not duplicate event")

sound.Playing = true
assert(sound.IsPlaying and count.Played == 2)
sound.Playing = false
assert(not sound.IsPlaying and count.Stopped == 2)

sound.EditableSound = nil
assert(not sound.IsLoaded)
assert(count.Loaded == 1, "clearing sound must not emit Loaded")

sound:Destroy()
source:Destroy()
`
	ok, err := vm.Run(&script_vm, source, "sound_event_parity_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("Sound lifecycle event parity smoke failed")
	}
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("SOUND_EVENT_PARITY_SMOKE_PASSED")
}
