package main

import classes "../src/engine/classes"
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: runtime.Environment
	runtime.Environment_Init(&environment, &script_vm)
	ok, err := vm.RunInternal(
		&script_vm,
		`
local s = game:GetService("LocalizationService")
assert(table.find(s:GetAvailableLocales(), "en-us"))
assert(table.find(s:GetAvailableLocales(), "fr-fr"))
assert(s.StudioLocaleId == "en-us")
assert(s:SetStudioLocale("FR-FR"))
assert(s.StudioLocaleId == "fr-fr")
assert(s:TranslateStudio("Settings") == "Paramètres")
assert(s:TranslateStudio("Missing") == "Missing")
assert(not s:SetStudioLocale("missing"))
assert(s.StudioLocaleId == "fr-fr")
assert(s.RobloxLocaleId == "en-us")
local screen = Instance.new("ScreenGui")
screen.Parent = game:GetService("CoreGui")
local studioLabel = Instance.new("TextLabel")
studioLabel.Name = "StudioLocalizedSmoke"
studioLabel.Text = "Settings"
studioLabel.Parent = screen
local rawLabel = Instance.new("TextLabel")
rawLabel.Name = "StudioRawSmoke"
rawLabel.Text = "Settings"
rawLabel.AutoLocalize = false
rawLabel.Parent = screen
local studioButton = Instance.new("TextButton")
studioButton.Name = "StudioButtonSmoke"
studioButton.Text = "Settings"
studioButton.Parent = screen
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
		if object.name == "StudioLocalizedSmoke" {
			assert(classes.localized_text(cast(^classes.TextLabel)object) == "Paramètres")
		}
		if object.name == "StudioRawSmoke" {
			assert(classes.localized_text(cast(^classes.TextLabel)object) == "Settings")
		}
		if object.name != "LocalizedSmoke" {continue}
		label := cast(^classes.TextLabel)object
		assert(classes.localized_text(label) == "Jouer")
	}
	buttons := classes.Find_Class(&environment.classes, "TextButton")
	for object in buttons.instances {
		if object.name == "StudioButtonSmoke" {
			label := classes.TextButton_to_text_label(cast(^classes.TextButton)object)
			assert(classes.localized_text(&label) == "Paramètres")
		}
	}
	ok, err = vm.RunInternal(
		&script_vm,
		`
local s = game:GetService("LocalizationService")
assert(s:LoadTranslations("en-us", '{"Play":"Start"}'))
s:SetLocale("en-us")
assert(s:Translate("Play") == "Start")
assert(s.StudioLocaleId == "fr-fr")
assert(s:SetStudioLocale("en-us"))
assert(s:TranslateStudio("Settings") == "Settings")
`,
		"switch",
	)
	if !ok {fmt.eprintln(err); panic("locale switch failed")}
	for object in descriptor.instances {
		if object.name == "StudioLocalizedSmoke" {
			assert(classes.localized_text(cast(^classes.TextLabel)object) == "Settings")
		}
		if object.name ==
		   "LocalizedSmoke" {assert(classes.localized_text(cast(^classes.TextLabel)object) == "Start")}
	}
	vm.Close(&script_vm)
	runtime.Environment_Destroy(&environment)
	fmt.println("LOCALIZATION_SMOKE_PASSED")
}
