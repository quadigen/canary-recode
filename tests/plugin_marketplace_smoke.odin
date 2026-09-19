package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

run_user_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("PluginMarketplace user-script test failed")
	}
}

run_internal_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("PluginMarketplace internal-script test failed")
	}
}

expect :: proc(ok: bool, message: string) {
	if !ok {
		panic(message)
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	// Normal scripts must NOT be able to see or call GetPlugins: the method is
	// gated behind the Internals security capability.
	run_user_script(&script_vm, `
local marketplace = game:GetService("PluginMarketplace")
assert(marketplace ~= nil)
assert(marketplace.ClassName == "PluginMarketplace")

-- GetPlugins is not a valid member of a user-visible PluginMarketplace.
assert(marketplace.GetPlugins == nil)
local okCall, callErr = pcall(function()
    marketplace:GetPlugins()
end)
assert(not okCall)
assert(callErr ~= nil)

-- The gated member must stay hidden even after an internal script runs.
assert(marketplace.GetPlugins == nil)
`, "plugin_marketplace_user")

	// Internal execution holds the Internals capability, so GetPlugins is a
	// callable member. We only index it (never invoke it: that would perform a
	// real network fetch of the registry and make the test nondeterministic).
	run_internal_script(&script_vm, `
local marketplace = game:GetService("PluginMarketplace")
assert(marketplace ~= nil)
assert(marketplace.GetPlugins ~= nil)
`, "plugin_marketplace_internal")

	// The gate is per-thread: GetPlugins is nil again on the user level after
	// the internal run.
	run_user_script(&script_vm, `
assert(game:GetService("PluginMarketplace").GetPlugins == nil)
`, "plugin_marketplace_restored")

	marketplace_descriptor := services.Find_Service(&environment.services, "PluginMarketplace")
	expect(marketplace_descriptor != nil && marketplace_descriptor.object != nil, "PluginMarketplace descriptor missing")

	http_descriptor := services.Find_Service(&environment.services, "HttpService")
	expect(http_descriptor != nil && http_descriptor.object != nil, "HttpService descriptor missing")
	http_service := cast(^services.HttpService)http_descriptor.object

	// An empty relative URL is rejected without any network activity. The
	// non-empty path would hit the network (PluginMarketplace_Load_Image builds
	// a URL under PLUGIN_MARKETPLACE_BASE_URL), so it is intentionally not
	// exercised here to keep the test deterministic and offline.
	empty_icon := services.PluginMarketplace_Load_Image(http_service, "my-plugin", "icon", "")
	expect(empty_icon == "", "PluginMarketplace_Load_Image must short-circuit on an empty URL")
	delete(empty_icon)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)

	fmt.println("PLUGIN_MARKETPLACE_SMOKE_PASSED")
}