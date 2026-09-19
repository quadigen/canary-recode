package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("Font enum smoke test setup failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(&script_vm, `
-- TextLabel: Font as an Enum.Font
local label = Instance.new("TextLabel")
assert(type(label.Font) == "userdata")
assert(label.Font == Enum.Font.Legacy)

label.Font = Enum.Font.Arial
assert(label.Font == Enum.Font.Arial)
assert(label.Font ~= Enum.Font.Legacy)

label.Font = Enum.Font.Code
assert(label.Font == Enum.Font.Code)
assert(label.Font.Value == 10)

-- TextLabel: Font as a family string maps back to the enum
label.Font = "Montserrat-Medium"
assert(type(label.Font) == "userdata")
assert(label.Font == Enum.Font.GothamMedium)

-- TextBox: Font as an Enum.Font
local box = Instance.new("TextBox")
assert(type(box.Font) == "userdata")
assert(box.Font == Enum.Font.Legacy)

box.Font = Enum.Font.ArimoBold
assert(box.Font == Enum.Font.ArimoBold)
assert(box.Font.Value == 51)

box.Font = "Arimo-Bold"
assert(box.Font == Enum.Font.ArimoBold)
`, "font_enum_smoke")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)

	fmt.println("FONT_ENUM_SMOKE_PASSED")
}
