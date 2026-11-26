package main

import datatypes "../src/engine/datatypes"
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
	ok, err := vm.Run(
		&state,
		`
local cases = {
	{ "Packages", "DownloadPackage", "Package installation requires Studio capability" },
	{ "ZipService", "ExtractZip", "ZIP filesystem access requires Internals capability" },
	{ "ZipService", "GetZipContents", "ZIP filesystem access requires Internals capability" },
	{ "ContentProvider", "DownloadZip", "ZIP download requires Internals capability" },
	{ "TemplateService", "ExportServerExe", "Executable export requires Studio capability" },
	{ "TemplateService", "ExportClientExe", "Executable export requires Studio capability" },
	{ "TemplateService", "ExportSinglePlayerExe", "Executable export requires Studio capability" },
	{ "UpdateService", "ApplyUpdate", "Engine update requires Studio capability" },
	{ "UpdateService", "FinishUpdateRestart", "Engine update requires Studio capability" },
}
for _, case in ipairs(cases) do
	local service = game:GetService(case[1])
	local success, message = pcall(function()
		service[case[2]](service)
	end)
	assert(not success and string.find(tostring(message), case[3], 1, true), case[1] .. ":" .. case[2] .. ": " .. tostring(message))
end
local packages = game:GetService("Packages")
local changed, message = pcall(function() packages.MarketplaceServer = "https://example.invalid" end)
assert(not changed and string.find(tostring(message), "Marketplace configuration requires Studio capability", 1, true))
`,
		"security-host-api",
	)
	if !ok {
		fmt.eprintln(err)
		panic("security host API regression")
	}
	ok, err = vm.RunWithSecurityCapabilities(
		&state,
		`
local cases = {
	{ "ExportService", "ExportToFile", "File import/export requires Internals capability" },
	{ "ExportService", "ExportToFileSync", "File import/export requires Internals capability" },
	{ "ExportService", "Export", "File import/export requires Internals capability" },
	{ "ExportService", "ImportFile", "File import/export requires Internals capability" },
	{ "PlaytestService", "Start", "Playtest process control requires Internals capability" },
	{ "PlaytestService", "StartServer", "Playtest process control requires Internals capability" },
	{ "PlaytestService", "StartClient", "Playtest process control requires Internals capability" },
	{ "PlaytestService", "StartSinglePlayer", "Playtest process control requires Internals capability" },
	{ "PlaytestService", "Stop", "Playtest process control requires Internals capability" },
}
for _, case in ipairs(cases) do
	local service = game:GetService(case[1])
	local success, message = pcall(function() service[case[2]](service) end)
	assert(not success and string.find(tostring(message), case[3], 1, true), case[1] .. ":" .. case[2] .. ": " .. tostring(message))
end
assert(type(game:GetService("ExportService"):GetExportProgress()) == "number")
assert(type(game:GetService("PlaytestService").IsRunning) == "boolean")
`,
		vm.ThreadSecurityAddCapability(
			vm.THREAD_SECURITY_NONE,
			datatypes.SECURITY_CAPABILITY_INTERNAL_STUDIO_ACCESS,
		),
		"security-studio-only",
	)
	if !ok {
		fmt.eprintln(err)
		panic("security Studio-only host API regression")
	}
	fmt.println("SECURITY_HOST_API_SMOKE_PASSED")
}
