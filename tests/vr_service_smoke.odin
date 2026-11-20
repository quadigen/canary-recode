package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	ok, err := vm.Run(
		&script_vm,
		`
local vr = game:GetService("VRService")
assert(not vr.VREnabled and not vr.VRAvailable)
assert(not game:GetService("UserInputService").VREnabled)
for _, hand in ipairs({Enum.UserCFrame.LeftHand, Enum.UserCFrame.RightHand}) do
    assert(not vr:GetUserCFrameEnabled(hand))
    assert(vr:GetUserCFrame(hand) == CFrame.new())
    local state = vr:GetControllerState(hand)
    assert(not state.Active)
    assert(state.Trigger == 0 and state.Grip == 0)
    assert(state.Thumbstick == Vector2.new(0, 0))
    assert(not state.TriggerAvailable and not state.GripAvailable and not state.ThumbstickAvailable)
    assert(vr:SetControllerHaptic(hand, 0.5, 0.1) == false)
end
assert(not pcall(function() vr:GetControllerState(Enum.UserCFrame.Head) end))
assert(not pcall(function() vr:SetControllerHaptic(Enum.UserCFrame.Floor, 0.5, 0.1) end))
`,
		"vr_service_smoke",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("VRService smoke test failed")
	}
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("VR_SERVICE_SMOKE_PASSED")
}
