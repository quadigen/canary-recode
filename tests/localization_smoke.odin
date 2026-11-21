package main

import classes "../src/engine/classes"
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: runtime.Environment
	runtime.Environment_Init(&environment, &script_vm)
	ok, err := vm.Run(
		&script_vm,
		`
local s = game:GetService("LocalizationService")
assert(s:LoadTranslations("FR-FR", '{"Play":"Jouer"}'))
s:SetLocale("fr-fr")
assert(s:Translate("Play") == "Jouer")
assert(s:Translate("Missing") == "Missing")
assert(not s:LoadTranslations("fr-fr", '{"Play":3}'))
assert(s:Translate("Play") == "Jouer")
local l = Instance.new("TextLabel")
l.Name = "LocalizedSmoke"
l.Text = "Play"
assert(l.Text == "Play")
`,
		"localization",
	)
	if !ok {fmt.eprintln(err); panic("localization setup failed")}
	descriptor := classes.Find_Class(&environment.classes, "TextLabel")
	for object in descriptor.instances {
		if object.name != "LocalizedSmoke" {continue}
		label := cast(^classes.TextLabel)object
		assert(classes.localized_text(label) == "Jouer")
	}
	ok, err = vm.Run(
		&script_vm,
		`
local s = game:GetService("LocalizationService")
assert(s:LoadTranslations("en-us", '{"Play":"Start"}'))
s:SetLocale("en-us")
assert(s:Translate("Play") == "Start")
`,
		"switch",
	)
	if !ok {fmt.eprintln(err); panic("locale switch failed")}
	for object in descriptor.instances {
		if object.name ==
		   "LocalizedSmoke" {assert(classes.localized_text(cast(^classes.TextLabel)object) == "Start")}
	}
	vm.Close(&script_vm)
	runtime.Environment_Destroy(&environment)
	fmt.println("LOCALIZATION_SMOKE_PASSED")
}
