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
part:SetAttribute("RuntimeOnly", WorkerRole)
local attachment = Instance.new("Attachment", part)
attachment.Name = "CopyChild"
local ref = Instance.new("ObjectValue", part)
ref.Name = "CopyReference"
ref.Value = attachment
`,
			"worker",
		)
		if !ok {fmt.eprintln(err); os.exit(1)}
		for {
			services.Playtest_Tree_Pump(directory, &env.services, v.L)
			time.sleep(100 * time.Millisecond)
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
assert(not pcall(function() p:RequestGameTree("Server") end))
assert(not pcall(function() p:RequestCopyInstance("Server", "invalid") end))
assert(not pcall(function() p:PollTreeRequest("Server", 1) end))
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
-- Leave the two workers running for nonblocking tests.
AsyncService = p
ServerToken = assert(p:RequestGameTree("Server"))
ClientToken = assert(p:RequestGameTree("Client"))
assert(not p:RequestGameTree("Server"))
AsyncStage = 0
`,
		"editor",
	)
	if !ok {fmt.eprintln(err); panic("playtest tree smoke failed")}


	deadline := time.tick_add(time.tick_now(), 8 * time.Second)
	for time.tick_diff(time.tick_now(), deadline) > 0 {
		started := time.tick_now()
		ready, poll_err := vm.RunInternal(
			&v,
			`
local p = AsyncService
if AsyncStage == 0 then
    if ServerToken then
        local rows, version = p:PollTreeRequest("Server", ServerToken)
        if rows ~= nil or version then
            assert(type(rows) == "table", version)
            ServerToken = nil
            ServerVersion = version
        end
    end
    if ClientToken then
        local rows, version = p:PollTreeRequest("Client", ClientToken)
        if rows ~= nil or version then
            assert(type(rows) == "table", version)
            ClientToken = nil
            for _, node in ipairs(rows) do
                if node.Name == "Original" then ClientId = node.Id end
            end
        end
    end
    if not ServerToken and not ClientToken then
        assert(ClientId)
        ServerToken = assert(p:RequestGameTree("Server", ServerVersion))
        ClientToken = assert(p:RequestSetInstanceProperty("Client", ClientId, "Name", "AsyncChanged"))
        AsyncStage = 1
    end
elseif AsyncStage == 1 then
    if ServerToken then
        local result, version = p:PollTreeRequest("Server", ServerToken)
        if result ~= nil or version then
            assert(result == false and version == ServerVersion)
            ServerToken = nil
        end
    end
    if ClientToken then
        local result, err = p:PollTreeRequest("Client", ClientToken)
        if result ~= nil or err then assert(result == true, err); ClientToken = nil end
    end
    if not ServerToken and not ClientToken then
        ClientToken = assert(p:RequestInstanceProperties("Client", ClientId))
        AsyncStage = 2
    end
elseif AsyncStage == 2 then
    local props, err = p:PollTreeRequest("Client", ClientToken)
    if props ~= nil or err then
        assert(props and props.Name == "AsyncChanged", err)
        ClientToken = assert(p:RequestCopyInstance("Client", ClientId))
        AsyncStage = 3
    end
elseif AsyncStage == 3 then
    local data, err = p:PollTreeRequest("Client", ClientToken)
    if data ~= nil or err then
        assert(typeof(data) == "buffer", err)
        ClipboardData = data
        AsyncStage = 4
    end
end
`,
			"async_poll",
		)
		if !ready {fmt.eprintln(poll_err); panic("async polling failed")}
		assert(
			time.tick_since(started) < 100 * time.Millisecond,
			"poll blocked waiting for a playtest process",
		)
		_ = vm.GetGlobal(v.L, "AsyncStage")
		stage := vm.ArgNumber(v.L, -1)
		vm.Pop(v.L)
		if stage == 4 {break}
		time.sleep(5 * time.Millisecond)
	}
	ok, err = vm.RunInternal(
		&v,
		`
assert(AsyncStage == 4, "async test timed out")
assert(AsyncService:Stop())
local serializer = game:GetService("SerializationService")
local copy1 = serializer:DeserializeInstancesAsync(ClipboardData, true)[1]
local copy2 = serializer:DeserializeInstancesAsync(ClipboardData, true)[1]
assert(copy1.Name == "AsyncChanged" and copy1.Anchored)
assert(copy1:GetAttribute("RuntimeOnly") == "Client")
assert(copy1.CopyChild:IsA("Attachment"))
assert(copy1.CopyReference.Value == copy1.CopyChild)
assert(copy2.CopyReference.Value == copy2.CopyChild)
assert(copy1.UniqueId ~= copy2.UniqueId)
assert(copy1.CopyChild.UniqueId ~= copy2.CopyChild.UniqueId)
copy1.Parent = workspace
copy2.Parent = workspace
assert(copy1.Parent == workspace and copy2.Parent == workspace)
copy1:Destroy()
copy2:Destroy()
`,
		"async_done",
	)
	if !ok {fmt.eprintln(err); panic("async inspection failed")}
	fmt.println(
		"PLAYTEST_TREE_SMOKE PASSED (nonblocking reads, unchanged snapshots, writes and clipboard round trip)",
	)
}
