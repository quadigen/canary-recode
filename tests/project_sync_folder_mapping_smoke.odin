package main

import packages "../src/engine/packages"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"

main :: proc() {
	v := vm.New()
	env: runtime.Environment
	view: renderer.RendererObject
	runtime.Environment_Init(&env, &v, &view, .Editor)
	defer {
		vm.Close(&v)
		runtime.Environment_Destroy(&env)
	}
	assert(len(os.args) > 1)
	assert(packages.Load_Internal_Modules_From_Directory(&env.packages, os.args[1]))
	root :: "/tmp/kine-project-mapping-smoke"
	assert(!os.exists(root), "Test directory already exists")
	assert(os.make_directory_all(root) == nil)
	defer os.remove_all(root)
	ok, err := vm.RunInternal(
		&v,
		`
local Sync = require("@internal/project_sync")
local FS = game:GetService("Filesystem")
local Http = game:GetService("HttpService")
local project = {Name = "MappingSmoke", Path = "/tmp/kine-project-mapping-smoke"}
local root = project.Path
local shared = game:GetService("ReplicatedStorage")
local function mkdir(path, name)
	assert(FS:CreateFolder(path, name) ~= "")
	return path .. "/" .. name
end
local function write(path, text)
	assert(FS:WriteFileAtomic(path, text), path)
end
local function manifest()
	return Http:JSONDecode(FS:ReadFile(root .. "/default.project.json"))
end
local function mapped(path, service, child, previous)
	local ok, message = Sync.mapFolder(path, service, child, previous)
	assert(ok, tostring(message))
	assert(Sync.step(), tostring(message))
end
assert(Sync.available)
assert(Sync.start(project))
assert(Sync.servicePath("ReplicatedStorage") == "scripts/shared")
local packages = mkdir(root, "Packages")
write(packages .. "/Util.luau", "return 42")
mapped(packages, "ReplicatedStorage", true)
assert(shared.Packages.Util.Source == "return 42")
assert(manifest().tree.ReplicatedStorage["$path"] == "scripts/shared")
assert(manifest().tree.ReplicatedStorage.Packages["$path"] == "Packages")
shared.Packages.Util.Source = "return 43"
assert(Sync.step())
assert(FS:ReadFile(packages .. "/Util.luau") == "return 43")
assert(not FS:PathExists(root .. "/scripts/shared/Packages"))
local direct = mkdir(root, "Direct")
write(direct .. "/DirectModule.luau", "return 7")
mapped(direct, "ServerStorage", false)
assert(game:GetService("ServerStorage").DirectModule.Source == "return 7")
assert(manifest().tree.ServerStorage["$path"] == "Direct")
local replace = mkdir(root, "Replacement")
write(replace .. "/Other.luau", "return 9")
assert(not Sync.mapFolder(replace, "ServerStorage", false))
mapped(replace, "ServerStorage", false, "Direct")
assert(game:GetService("ServerStorage").Other.Source == "return 9")
assert(FS:ReadFile(direct .. "/DirectModule.luau") == "return 7")
assert(FS:ReadFile(replace .. "/DirectModule.luau") == "return 7")
local conflict = mkdir(root, "Conflict")
write(conflict .. "/Other.luau", "return 0")
assert(not Sync.mapFolder(conflict, "ServerStorage", false, "Replacement"))
assert(manifest().tree.ServerStorage["$path"] == "Replacement")
assert(game:GetService("ServerStorage").Other.Source == "return 9")
assert(not Sync.mapFolder(root .. "/../Outside", "Workspace", false))
assert(not Sync.mapFolder(packages, "Workspace", false))
assert(not FS:PathExists(root .. "/scripts/shared/Packages"))
Sync.stop()
assert(Sync.start(project))
write(packages .. "/Util.luau", "return 44")
assert(Sync.step())
assert(shared.Packages.Util.Source == "return 44")
assert(not FS:PathExists(root .. "/scripts/shared/Packages"))
assert(Sync.setPaused(true))
local paused = mkdir(root, "Paused")
write(paused .. "/Wait.luau", "return 5")
assert(Sync.mapFolder(paused, "ReplicatedFirst", false))
assert(Sync.isPaused())
assert(not game:GetService("ReplicatedFirst"):FindFirstChild("Wait"))
assert(Sync.setPaused(false))
assert(game:GetService("ReplicatedFirst").Wait.Source == "return 5")
local function findMapping(name)
	for _, entry in ipairs(Sync.getMappings()) do
		if table.concat(entry.names, ".") == name then return entry end
	end
end
assert(Sync.status().active and Sync.status().ready)
assert(Sync.syncNow())
local entry = assert(findMapping("ReplicatedStorage.Packages"))
local nextDir = mkdir(root, "PackagesNext")
write(nextDir .. "/Util.luau", "return 44")
assert(Sync.editMapping(entry, "PackagesNext"))
assert(not Sync.editMapping(entry, nil))
assert(findMapping("ReplicatedStorage.Packages").path == "PackagesNext")
shared.Packages.Util.Source = "return 45"
assert(Sync.step())
assert(FS:ReadFile(nextDir .. "/Util.luau") == "return 45")
assert(FS:ReadFile(packages .. "/Util.luau") == "return 44")
assert(not Sync.editMapping(findMapping("ReplicatedStorage.Packages"), "../Outside"))
assert(Sync.setPaused(true))
assert(not Sync.syncNow())
assert(Sync.editMapping(findMapping("ReplicatedStorage.Packages"), nil))
assert(Sync.isPaused())
assert(not findMapping("ReplicatedStorage.Packages"))
assert(Sync.setPaused(false))
shared.Packages.Util.Source = "return 46"
assert(Sync.step())
assert(FS:ReadFile(nextDir .. "/Util.luau") == "return 45")
assert(not FS:PathExists(root .. "/scripts/shared/Packages"))
Sync.stop()
assert(Sync.start(project))
assert(shared.Packages.Util.Source == "return 46")
assert(not FS:PathExists(root .. "/scripts/shared/Packages"))
assert(Sync.editMapping(findMapping("ServerStorage"), nil))
assert(game:GetService("ServerStorage").Other.Source == "return 9")
assert(FS:ReadFile(replace .. "/Other.luau") == "return 9")
assert(Sync.status().conflicts == 0)
local Tools = require("@internal/project_tools")
Tools.mappings()
Tools.mappings()
assert(type(require("@internal/files")) == "function")
Sync.stop()
`,
		"project_sync_folder_mapping_smoke",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("project sync mapping failed")
	}
	fmt.println("PROJECT_SYNC_FOLDER_MAPPING_SMOKE_PASSED")
}
