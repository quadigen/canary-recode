package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	state := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &state, nil, .Editor)
	defer {
		engine_runtime.Environment_Destroy(&environment)
		vm.Close(&state)
	}

	ok, err := vm.RunInternal(
		&state,
		`
local loader = game:GetService("PluginLoader")
local plugins = loader:GetNativePlugins()
assert(type(plugins) == "table", "plugin list missing")
local found = false
for _, plugin in ipairs(plugins) do
    if plugin.Id == "native.example" then
        found = true
        assert(plugin.Native == true)
        assert(plugin.UnrestrictedNativeAccess == true)
        assert(plugin.Loaded == false, "native code ran before consent")
        assert(plugin.ApiMajor == 2)
        assert(type(plugin.Capabilities) == "table")
    end
end
assert(found, "native.example manifest not discovered")
assert(NativePluginSum == nil, "native plugin loaded without approval")
local loaded, message = loader:LoadNativePlugin("native.example")
assert(loaded == true, tostring(message))
assert(NativePluginSum(4, 5) == 9, "native SDK entry not loaded")
local loadedPlugins = loader:GetNativePlugins()
local running = false
for _, plugin in ipairs(loadedPlugins) do
    if plugin.Id == "native.example" then
        running = plugin.Loaded
    end
end
assert(running, "status was not updated")
local unloaded, unloadError = loader:UnloadNativePlugin("native.example")
assert(unloaded == true, tostring(unloadError))
assert(NativePluginSum == nil, "native plugin survived unload")
`,
		"native_plugin_consent_smoke",
	)

	if !ok {
		fmt.eprintln(err)
		panic("native plugin consent smoke failed")
	}
	fmt.println("NATIVE_PLUGIN_CONSENT_SMOKE_PASSED")
}
