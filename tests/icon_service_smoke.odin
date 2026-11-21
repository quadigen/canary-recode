package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "core:strings"

run :: proc(v: ^vm.VM, code: string) {
	ok, err := vm.RunInternal(v, code, "icon_service_smoke")
	if !ok {fmt.eprintln(err); delete(err); panic("IconService smoke failed")}
}

main :: proc() {
	v := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v, nil, .Server)
	defer {
		vm.Close(&v)
		engine_runtime.Environment_Destroy(&env)
	}

	ok, err := vm.RunWithSecurityCapabilities(
		&v,
		`
local icons = game:GetService("IconService")
assert(icons:IsA("Instance"))
assert(icons:GetFullName() == "game.IconService")
assert(icons.ActiveIconPack == nil)
local allowed, message = pcall(function()
    icons:ResetIconPack()
end)
assert(not allowed and string.find(message, "IconService requires Internals capability", 1, true))
`,
		vm.THREAD_SECURITY_NONE,
		"icon_service_unprivileged",
	)
	if !ok {fmt.eprintln(err); delete(err); panic("IconService capability smoke failed")}

	uri :: "builtin://icons/Folder.svg"
	original, exists := classes.ImageLabel_Resolve_Builtin_Image(uri)
	assert(exists)
	revision := classes.IconPack_Revision()
	label := classes.ImageLabel_Init()
	classes.ImageLabel_Set_Image(&label, uri)
	defer {
		classes.ImageLabel_Destroy_Stored_Image(&label)
		delete(label.owned_image)
	}
	assert(label.stored_image != nil)

	run(
		&v,
		`
local icons = game:GetService("IconService")
assert(icons.ActiveIconPack == "Default")
assert(not icons:SetIconPack("missing"))
assert(not icons:RegisterIconPack("Default", {["Folder.svg"] = "x"}))
assert(icons:RegisterIconPack("Custom", {
    ["Folder.svg"] = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect width="24" height="24" fill="red"/></svg>',
    ["builtin://global-icons/custom.svg"] = "global"
}))
assert(icons:SetIconPack("Custom"))
assert(icons.ActiveIconPack == "Custom")
`,
	)
	override, found := classes.ImageLabel_Resolve_Builtin_Image(uri)
	assert(found && strings.contains(transmute(string)override, "red"))
	assert(classes.IconPack_Revision() != revision)
	assert(label.icon_pack_revision != classes.IconPack_Revision())
	classes.ImageLabel_Refresh_Icon_Pack(&label)
	assert(label.icon_pack_revision == classes.IconPack_Revision())
	assert(label.image == uri && label.stored_image != nil)
	fallback, has_fallback := classes.ImageLabel_Resolve_Builtin_Image("builtin://icons/Part.svg")
	expected, has_expected := classes.ImageLabel_Resolve_Default_Builtin_Image(
		"builtin://icons/Part.svg",
	)
	assert(has_fallback && has_expected && transmute(string)fallback == transmute(string)expected)
	global, has_global := classes.IconPack_Resolve("builtin://global-icons/custom.svg")
	assert(has_global && transmute(string)global == "global")

	run(
		&v,
		`
local icons = game:GetService("IconService")
assert(icons:RegisterIconPack("Custom", {["Folder.svg"] = "invalid-image"}))
`,
	)
	classes.ImageLabel_Refresh_Icon_Pack(&label)
	assert(label.stored_image != nil, "invalid override should fall back")
	run(
		&v,
		`
local icons = game:GetService("IconService")
assert(icons:ResetIconPack())
assert(icons.ActiveIconPack == "Default")
assert(icons:SetIconPack("Custom"))
assert(icons:UnregisterIconPack("Custom"))
assert(icons.ActiveIconPack == "Default")
assert(not icons:SetIconPack("Custom"))
`,
	)
	restored, restored_ok := classes.ImageLabel_Resolve_Builtin_Image(uri)
	assert(restored_ok && transmute(string)restored == transmute(string)original)
	classes.ImageLabel_Refresh_Icon_Pack(&label)
	assert(label.stored_image != nil)
	fmt.println("IconService smoke passed")
}
