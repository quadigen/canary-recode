package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("tween service smoke test failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(&script_vm, `
TweenService = game:GetService("TweenService")
assert(TweenService ~= nil)
assert(TweenService.ClassName == "TweenService")

-- Smoke: GetValue easing helper
assert(math.abs(TweenService:GetValue(0, Enum.EasingStyle.Linear, Enum.EasingDirection.In)) < 1e-6)
assert(math.abs(TweenService:GetValue(1, Enum.EasingStyle.Linear, Enum.EasingDirection.In) - 1) < 1e-6)
assert(math.abs(TweenService:GetValue(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) - 0.75) < 1e-3)

-- Create tween on a fresh Part
partA = Instance.new("Part")
partA.Transparency = 0
assert(partA.Transparency == 0)

local okCreate, errCreate = pcall(function()
	tweenA = TweenService:Create(
		partA,
		TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0),
		{ Transparency = 1 }
	)
end)
print("CREATE_OK", okCreate, "ERR", errCreate)
print("TWEENTYPE", typeof(tweenA))
print("TWEENCLASS", tweenA and tweenA.ClassName)
assert(typeof(tweenA) == "Tween")
assert(math.abs(tweenA.Duration - 1) < 1e-6)
assert(tweenA.TimePosition == 0)
assert(tweenA.PlaybackState == Enum.PlaybackState.Begin)

-- Connect Completed event
completedValueA = nil
tweenA.Completed:Connect(function(state)
	completedValueA = state
end)

-- Play
tweenA:Play()
assert(tweenA.PlaybackState == Enum.PlaybackState.Playing)
`, "tween_service_setup")

	// Step halfway (linear: alpha 0.5)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 0.5)
	run_script(&script_vm, `
assert(math.abs(partA.Transparency - 0.5) < 0.02)
assert(tweenA.PlaybackState == Enum.PlaybackState.Playing)
assert(math.abs(tweenA.TimePosition - 0.5) < 0.05)
`, "tween_service_halfway")

	// Pause and step (should not change)
	run_script(&script_vm, `
tweenA:Pause()
assert(tweenA.PlaybackState == Enum.PlaybackState.Paused)
`, "tween_service_pause")
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 0.5)
	run_script(&script_vm, `
assert(math.abs(partA.Transparency - 0.5) < 0.02)
`, "tween_service_paused")

	// Resume and complete
	run_script(&script_vm, `
tweenA:Play()
`, "tween_service_resume")
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0)
	run_script(&script_vm, `
assert(math.abs(partA.Transparency - 1) < 0.02)
assert(tweenA.PlaybackState == Enum.PlaybackState.Completed)
assert(completedValueA == Enum.PlaybackState.Completed)
`, "tween_service_completed")

	// Cancel test
	run_script(&script_vm, `
partB = Instance.new("Part")
tweenB = TweenService:Create(
	partB,
	TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.In),
	{ Transparency = 1 }
)
completedValueB = nil
tweenB.Completed:Connect(function(state) completedValueB = state end)
tweenB:Play()
assert(tweenB.PlaybackState == Enum.PlaybackState.Playing)
tweenB:Cancel()
assert(tweenB.PlaybackState == Enum.PlaybackState.Cancelled)
assert(completedValueB == Enum.PlaybackState.Cancelled)
assert(partB.Transparency == 0)
`, "tween_service_cancel")

	// Delay test
	run_script(&script_vm, `
partC = Instance.new("Part")
tweenC = TweenService:Create(
	partC,
	TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.25),
	{ Transparency = 1 }
)
tweenC:Play()
`, "tween_service_delay_setup")

	engine_runtime.Environment_Update_Step(&environment, &script_vm, 0.1)
	run_script(&script_vm, `
assert(tweenC.PlaybackState == Enum.PlaybackState.Delayed)
assert(partC.Transparency == 0)
`, "tween_service_delay_during")

	engine_runtime.Environment_Update_Step(&environment, &script_vm, 0.3)
	run_script(&script_vm, `
assert(math.abs(partC.Transparency - 0.5) < 0.15)
assert(tweenC.PlaybackState == Enum.PlaybackState.Playing)
`, "tween_service_delay_after")

	engine_runtime.Environment_Update_Step(&environment, &script_vm, 0.5)
	run_script(&script_vm, `
assert(tweenC.PlaybackState == Enum.PlaybackState.Completed)
assert(math.abs(partC.Transparency - 1) < 0.02)
`, "tween_service_delay_done")

	// Repeat test
	run_script(&script_vm, `
partD = Instance.new("Part")
tweenD = TweenService:Create(
	partD,
	TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 1, false, 0),
	{ Transparency = 1 }
)
assert(math.abs(tweenD.Duration - 1) < 1e-6)
tweenD:Play()
`, "tween_service_repeat_setup")

	engine_runtime.Environment_Update_Step(&environment, &script_vm, 0.75)
	run_script(&script_vm, `
assert(math.abs(partD.Transparency - 0.5) < 0.05)
assert(tweenD.PlaybackState == Enum.PlaybackState.Playing)
`, "tween_service_repeat_mid")

	engine_runtime.Environment_Update_Step(&environment, &script_vm, 0.5)
	run_script(&script_vm, `
assert(tweenD.PlaybackState == Enum.PlaybackState.Completed)
assert(math.abs(partD.Transparency - 1) < 0.02)
`, "tween_service_repeat_done")

	// Error cases
	run_script(&script_vm, `
assert(not pcall(function() TweenService:Create(1, TweenInfo.new(1), {Transparency=1}) end))
assert(not pcall(function() TweenService:Create(partA, nil, {Transparency=1}) end))
assert(not pcall(function() TweenService:Create(partA, TweenInfo.new(1), {}) end))
`, "tween_service_errors")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("TWEEN_SERVICE_SMOKE_PASSED")
}
