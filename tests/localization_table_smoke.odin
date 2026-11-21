package main

import classes "../src/engine/classes"
import runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.Run(v, source, "localization_table")
	if !ok {fmt.eprintln(err); panic("localization table smoke failed")}
}

main :: proc() {
	v := vm.New()
	env: runtime.Environment
	runtime.Environment_Init(&env, &v)
	run(
		&v,
		`
local service = game:GetService("LocalizationService")
local t = Instance.new("LocalizationTable", service)
t.Name = "TableSmoke"
assert(t.SourceLocaleId == "en-us")
t.SourceLocaleId = "EN-GB"
assert(t.SourceLocaleId == "en-gb")
t:SetEntries({
	{Key = "play", Source = "Play", Values = {["FR-fr"] = "Jouer", ["de-de"] = "Spielen"}},
	{Source = "Play", Context = "some.context", Example = "button", Values = {["fr-fr"] = "Lancer"}},
})
assert(#t:GetEntries() == 2)
assert(t:GetEntries()[1].Values["fr-fr"] == "Jouer")
local snapshot = t:GetEntries()
snapshot[1].Values["fr-fr"] = "bad"
assert(t:GetEntries()[1].Values["fr-fr"] == "Jouer")
assert(not pcall(function() t:SetEntries({{Key="dup"}, {Key="dup"}}) end))
assert(not pcall(function() t:SetEntries({{Source="bad", Values={fr=3}}}) end))
assert(not pcall(function() t:SetEntries({[1]={Key="a"}, extra={Key="b"}}) end))
local metatableCalled = false
local invalid = setmetatable({}, {__index = function()
	metatableCalled = true
	return "injected"
end})
assert(not pcall(function() t:SetEntries({invalid}) end))
assert(not metatableCalled)
assert(#t:GetEntries() == 2)
t:SetEntryContext("", "Play", "some.context", "another.context")
t:SetEntryExample("", "Play", "another.context", "new example")
t:SetEntryKey("", "Play", "another.context", "contextPlay")
assert(not pcall(function() t:SetEntryKey("contextPlay", "", "", "play") end))
assert(t:GetEntries()[2].Key == "contextPlay")
t:SetEntrySource("contextPlay", "", "", "Start")
assert(t:GetEntries()[2].Source == "Start" and t:GetEntries()[2].Example == "new example")
t:SetEntryValue("contextPlay", "", "", "FR-FR", "Démarrer")
assert(t:GetEntries()[2].Values["fr-fr"] == "Démarrer")
t:SetEntryValue("created", "Created", "", "fr-fr", "Créé")
assert(#t:GetEntries() == 3)
t:RemoveEntryValue("created", "", "", "FR-FR")
assert(t:GetEntries()[3].Values["fr-fr"] == nil)
t:SetEntryValue("created", "", "", "fr-fr", "again")
t:SetEntryValue("created", "", "", "fr-fr", "")
assert(t:GetEntries()[3].Values["fr-fr"] == nil)
t:RemoveTargetLocale("DE-DE")
assert(t:GetEntries()[1].Values["de-de"] == nil)
t:RemoveEntry("created", "", "")
assert(#t:GetEntries() == 2)
t:RemoveEntry("missing", "", "")
assert(#t:GetEntries() == 2)
service:SetLocale("FR-FR")
assert(service:Translate("Play") == "Jouer")
local label = Instance.new("TextLabel")
label.Name = "LocalizationTableLabel"
label.Text = "Play"
t:SetEntryValue("", "Play", label:GetFullName(), "fr-fr", "Lancer")
assert(#t:GetEntries() == 3)
assert(label.Text == "Play")
local clone = t:Clone()
assert(clone.SourceLocaleId == "en-gb" and #clone:GetEntries() == 3)
clone:RemoveEntry("play", "", "")
assert(#t:GetEntries() == 3 and #clone:GetEntries() == 2)
clone:Destroy()
local encoded = t.SerializedEntries
local fromJSON = Instance.new("LocalizationTable")
fromJSON.SerializedEntries = encoded
assert(#fromJSON:GetEntries() == 3 and fromJSON:GetEntries()[2].Values["fr-fr"] == "Démarrer")
assert(not pcall(function() fromJSON.SerializedEntries = '[{"Key":3}]' end))
assert(#fromJSON:GetEntries() == 3)
fromJSON:Destroy()
`,
	)
	desc := classes.Find_Class(&env.classes, "LocalizationTable")
	labels := classes.Find_Class(&env.classes, "TextLabel")
	table: ^classes.Object
	label: ^classes.TextLabel
	for object in desc.instances {if !object.destroyed && object.name == "TableSmoke" {table = object}}
	for object in labels.instances {if object.name == "LocalizationTableLabel" {label = cast(^classes.TextLabel)object}}
	assert(table != nil && label != nil)
	assert(classes.localized_text(label) == "Lancer")
	bytes, err := serializer.Serialize(&env.classes, v.L, table)
	assert(err.kind == .None)
	defer delete(bytes)
	restored, load_err := serializer.Deserialize(&env.classes, v.L, nil, bytes)
	assert(load_err.kind == .None && restored != nil)
	copy := cast(^classes.LocalizationTable)restored
	assert(copy.source_locale == "en-gb" && len(copy.entries) == 3)
	assert(copy.entries[1].Values["fr-fr"] == "Démarrer")
	run(
		&v,
		`
local service = game:GetService("LocalizationService")
local t = service.TableSmoke
t.Parent = nil
assert(service:Translate("Play") == "Play")
`,
	)
	assert(classes.localized_text(label) == "Play")
	vm.Close(&v)
	runtime.Environment_Destroy(&env)
	fmt.println("LOCALIZATION_TABLE_SMOKE_PASSED")
}
