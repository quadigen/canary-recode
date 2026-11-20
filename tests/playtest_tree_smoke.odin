package main

import datatypes "../src/engine/datatypes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import "core:time"

main :: proc() {
	directory, role: string
	for arg, i in os.args {
		if arg == "--playtest-tree-dir" && i + 1 < len(os.args) {directory = os.args[i + 1]}
		if arg == "--server" {role = "Server"}
		if arg == "--client" {role = "Client"}
	}
	v := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v)
	defer engine_runtime.Environment_Destroy(&env)
	defer vm.Close(&v)
	if directory != "" {
		vm.AddGlobal_String(&v, "WorkerRole", role)
		ok, err := vm.RunInternal(
			&v,
			`
local folder = Instance.new("Folder", workspace)
folder.Name = WorkerRole .. "Only"
local part = Instance.new("Part", folder)
part.Name = "Original"
part.Anchored = true
`,
			"worker",
		)
		if !ok {fmt.eprintln(err); os.exit(1)}
		for {
			services.Playtest_Tree_Pump(directory, &env.services, v.L)
			time.sleep(5 * time.Millisecond)
		}
	}
	dir, dir_err := os.make_directory_temp("", "kinemium-tree-test-*", context.allocator)
	assert(dir_err == nil)
	defer delete(dir)
	defer _ = os.remove_all(dir)
	path, path_err := os.join_path({dir, "test.kine"}, context.allocator)
	assert(path_err == nil)
	defer delete(path)
	assert(os.write_entire_file(path, []u8{0}) == nil)
	vm.AddGlobal_String(&v, "TestMapPath", path)
	caps := vm.ThreadSecurityAddCapability(
		vm.THREAD_SECURITY_NONE,
		datatypes.SECURITY_CAPABILITY_INTERNAL_STUDIO_ACCESS,
	)
	allowed, security_err := vm.RunWithSecurityCapabilities(
		&v,
		`
local p = game:GetService("PlaytestService")
assert(p)
assert(not pcall(function() p:GetGameTree("Server") end))
`,
		caps,
		"permission_check",
	)
	if !allowed {fmt.eprintln(security_err); panic("playtest internal capability check failed")}
	ok, err := vm.RunInternal(
		&v,
		`
local p = game:GetService("PlaytestService")
local noTree, noErr = p:GetGameTree("Server")
assert(noTree == nil and type(noErr) == "string")
assert(p:Start(TestMapPath, false, true, true), p.LastError)
local server, serverErr = p:GetGameTree("Server")
assert(server, serverErr)
local client, clientErr = p:GetGameTree("Client")
assert(client, clientErr)
local function locate(tree, name)
    for _, node in ipairs(tree) do
        if node.Name == name then return node end
    end
end
local s = assert(locate(server, "ServerOnly"))
local c = assert(locate(client, "ClientOnly"))
assert(not locate(client, "ServerOnly"))
assert(not locate(server, "ClientOnly"))
local original = assert(locate(server, "Original"))
assert(original.ParentId == s.Id and original.ClassName == "Part")
local props, pe = p:GetInstanceProperties("Server", original.Id)
assert(props, pe)
assert(props.Name == "Original" and props.Anchored == true)
assert(p:SetInstanceProperty("Server", original.Id, "Name", "Changed"))
assert(p:SetInstanceProperty("Server", original.Id, "Size", Vector3.new(3, 4, 5)))
assert(p:GetInstanceProperty("Server", original.Id, "Size") == Vector3.new(3,4,5))
assert(p:GetInstanceProperty("Server", original.Id, "Name") == "Changed")
assert(p:GetInstanceProperty("Client", locate(client, "Original").Id, "Name") == "Original")
local model, me = p:CreateInstance("Server", s.Id, "Model", "Created")
assert(model, me)
assert(p:ReparentInstance("Server", original.Id, model))
local rp = assert(p:GetInstanceProperty("Server", original.Id, "Parent"))
assert(rp.InstanceId == model)
assert(p:SetInstanceReference("Server", model, "PrimaryPart", original.Id))
assert(p:GetInstanceProperty("Server", model, "PrimaryPart").InstanceId == original.Id)
assert(not p:ReparentInstance("Server", model, original.Id))
assert(not p:SetInstanceProperty("Server", original.Id, "Size", "invalid"))
assert(p:DestroyInstance("Server", model))
assert(not p:GetInstanceProperty("Server", original.Id, "Name"))
assert(not p:DestroyInstance("Server", s.ParentId))
assert(p:Stop())
`,
		"editor",
	)
	if !ok {fmt.eprintln(err); panic("playtest tree smoke failed")}
	fmt.println("PLAYTEST_TREE_SMOKE PASSED")
}
