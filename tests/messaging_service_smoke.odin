package main

import engine_runtime "../src/engine/runtime"
import target "../src/engine/target"
import vm "../src/engine/vm"
import sandbox "../src/sandboxed"
import "core:fmt"

main :: proc() {
	target.set_mode(.Server)
	script_vm := vm.New()
	environment: engine_runtime.Environment
	sandbox.init_runtime(&script_vm, &environment, nil)
	defer {
		vm.Close(&script_vm)
		sandbox.shutdown()
	}
	ok, err := vm.Run(
		&script_vm,
		`
local service = game:GetService("MessagingService")
local received = {}
local legacy = service:Subscribe("chat")
local a = legacy:Connect(function(message)
    table.insert(received, message)
end)
local b = service:SubscribeAsync("chat", function(message)
    table.insert(received, message)
end)
local isolated = service:SubscribeAsync("other", function() error("wrong topic") end)
assert(#service:GetSubscribers("chat") == 2)
local payload = {nested = {count = 2}, [3] = "three", text = "a" .. string.char(0) .. "b"}
service:PublishAsync("chat", payload)
assert(#received == 2)
assert(received[1].Data.nested.count == 2 and received[2].Data[3] == "three")
assert(received[1].Data.text == payload.text)
assert(received[1].topic == "chat" and type(received[1].Sent) == "number")
payload.nested.count = 5
assert(received[1].Data.nested.count == 2)
assert(not pcall(function() received[1].Data.nested.count = 9 end))
service:Unsubscribe("other", b)
assert(b.Connected)
service:Unsubscribe("chat", a)
assert(not a.Connected and b.Connected)
service:Publish("chat", false)
assert(#received == 3 and received[3].Data == false)
b:Disconnect()
assert(#service:GetSubscribers("chat") == 0)
service:PublishAsync("chat", nil)
assert(#received == 3)
local onceCount = 0
legacy:Once(function() onceCount += 1 end)
service:PublishAsync("chat", 1)
service:PublishAsync("chat", 1)
assert(onceCount == 1)
local self
self = service:SubscribeAsync("chat", function()
    self:Disconnect()
    service:PublishAsync("other", "nested")
end)
isolated:Disconnect()
local nested = 0
local nestedConn = service:SubscribeAsync("other", function(message)
    assert(message.Data == "nested")
    nested += 1
end)
service:PublishAsync("chat", {})
assert(nested == 1 and not self.Connected)
local all = service:Subscribe("chat", function() error("unsubscribed") end)
service:UnsubscribeAll()
assert(not all.Connected and not nestedConn.Connected)
assert(#service:GetSubscribers("chat") == 0)
local keep = service:SubscribeAsync("chat", function() end)
service:UnsubscribeAll("chat")
assert(not keep.Connected)
local count = #service:GetTopics()
for i = 1, 100 do service:PublishAsync("missing" .. i, i) end
assert(#service:GetTopics() == count)
local cycle = {}; cycle.self = cycle
assert(not pcall(function() service:PublishAsync("chat", cycle) end))
assert(not pcall(function() service:PublishAsync("chat", function() end) end))
assert(not pcall(function() service:PublishAsync("chat", string.rep("a", 70000)) end))
assert(not pcall(function() service:PublishAsync("chat", 0/0) end))
assert(not pcall(function() service:PublishAsync("", 1) end))
assert(not pcall(function() service:PublishAsync("chat") end))
assert(not pcall(function() service:SubscribeAsync("chat", 42) end))
assert(not pcall(function() service:SubscribeAsync("chat") end))
local reuse = service:Subscribe("chat")
local valid = reuse:Connect(function(message) assert(message.Data == "ok") end)
service:PublishAsync("chat", "ok")
valid:Disconnect()
`,
		"messaging_service_smoke",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("messaging smoke failed")
	}
	engine_runtime.Environment_Set_Mode(&environment, .Client)
	ok, err = vm.Run(
		&script_vm,
		`
local service = game:GetService("MessagingService")
assert(not pcall(function() service:PublishAsync("chat", "bad") end))
assert(not pcall(function() service:Subscribe("chat") end))
`,
		"messaging_client_denied",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("client denial failed")
	}
	fmt.println("MESSAGING_SERVICE_SMOKE_PASSED")
}
