package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_breadth :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("replication breadth smoke failed")
	}
}

breadth_step :: proc(server: ^engine_runtime.Environment, server_vm: ^vm.VM, client: ^engine_runtime.Environment, client_vm: ^vm.VM, frames: int) {
	for frame in 0..<frames {
		engine_runtime.Environment_Update_Step(server, server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Update_Step(client, client_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(server, server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(client, client_vm, 1.0 / 60.0)
	}
}

main :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	run_breadth(&server_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39234))

-- StarterGui tree (ScreenGui -> Frame -> TextLabel with UDim2/UDim/Color3/enum props)
local starter_gui = game:GetService("StarterGui")
local hud = Instance.new("ScreenGui", starter_gui)
hud.Name = "Hud"
local frame = Instance.new("Frame", hud)
frame.Name = "Backdrop"
frame.Size = UDim2.new(0.5, 0, 0.25, 0)
frame.Position = UDim2.new(0.25, 0, 0.1, 0)
frame.BackgroundColor3 = Color3.new(1, 0, 0)
frame.BackgroundTransparency = 0.5
local label = Instance.new("TextLabel", frame)
label.Name = "Title"
label.Position = UDim2.new(0, 0, 0, 0)
label.Size = UDim2.new(1, 0, 1, 0)
label.Text = "Hello Replication"
label.Font = Enum.Font.Arcade
label.TextScaled = true
local corner = Instance.new("UICorner", frame)
corner.CornerRadius = UDim.new(0, 8)

-- Lighting effects
local lighting = game:GetService("Lighting")
local nite = Instance.new("ColorCorrectionEffect", lighting)
nite.Name = "Nite"
nite.Brightness = 0.4
nite.Contrast = 0.2
nite.Saturation = 0.5
nite.TintColor = Color3.new(0.2, 0.4, 0.8)
local atmosphere = Instance.new("Atmosphere", lighting)
atmosphere.Name = "SkyBox"
atmosphere.Density = 0.3
atmosphere.Color = Color3.new(0.5, 0.5, 0.6)

-- PointLight on a part
local lamp = Instance.new("Part", workspace)
lamp.Name = "Lamp"
lamp.Anchored = true
lamp.Size = vector.create(1, 2, 1)
lamp.CFrame = CFrame.new(0, 20, 0)
local lamp_light = Instance.new("PointLight", lamp)
lamp_light.Name = "LampLight"
lamp_light.Brightness = 2
lamp_light.Range = 24
lamp_light.Color = Color3.new(1, 1, 0)

-- Scripts: ModuleScript Source must replicate; LocalScript runs on the client;
-- Server Script runs on the server only and must not leak its Source elsewhere.
local shared_mod = Instance.new("ModuleScript", game:GetService("ReplicatedStorage"))
shared_mod.Name = "SharedMod"
shared_mod.Source = "return { greeting = 'hi-from-module', count = 42 }"
local client_script = Instance.new("LocalScript", game:GetService("ReplicatedStorage"))
client_script.Name = "ClientScript"
client_script.Source = "_G.CLIENT_SCRIPT_RAN = true"
local server_script = Instance.new("Script", workspace)
server_script.Name = "ServerBootstrap"
server_script.Source = "_G.SERVER_SCRIPT_RAN = true"

-- These must never reach a client.
local secret_part = Instance.new("Part", game:GetService("ServerStorage"))
secret_part.Name = "SecretPart"
local secret_flag = Instance.new("BoolValue", game:GetService("ServerStorage"))
secret_flag.Name = "SecretFlag"
secret_flag.Value = true
local secret_script = Instance.new("Script", game:GetService("ServerScriptService"))
secret_script.Name = "SecretScript"
secret_script.Source = "print('secret')"
`, "breadth_server_setup")

	fmt.eprintln("P1 SERVER_SETUP_DONE")

	run_breadth(&client_vm, `
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39234))
`, "breadth_client_connect")

	fmt.eprintln("P2 CLIENT_CONNECT_DONE")

	breadth_step(&server, &server_vm, &client, &client_vm, 120)

	fmt.eprintln("P3 INITIAL_STEP_DONE")

	// The server-side Script must have run on the server.
	run_breadth(&server_vm, `
assert(game:GetService("ServerStorage"):FindFirstChild("SecretPart") ~= nil, "server keeps ServerStorage")
assert(_G.SERVER_SCRIPT_RAN == true, "server script should run on the server")
`, "breadth_server_side")

	run_breadth(&client_vm, `
local function close(a, b) return math.abs(a - b) <= 0.01 end

-- StarterGui tree replicated with values intact.
local hud = game:GetService("StarterGui"):FindFirstChild("Hud")
assert(hud ~= nil, "ScreenGui should replicate to the client")
assert(hud:IsA("ScreenGui"))
local frame = hud:FindFirstChild("Backdrop")
assert(frame ~= nil, "Frame should replicate")
assert(close(frame.Size.X.Scale, 0.5) and close(frame.Size.Y.Scale, 0.25), "Frame Size UDim2")
assert(close(frame.Position.X.Scale, 0.25) and close(frame.Position.Y.Scale, 0.1), "Frame Position UDim2")
assert(close(frame.BackgroundColor3.R, 1) and close(frame.BackgroundColor3.G, 0), "Frame color")
assert(close(frame.BackgroundTransparency, 0.5), "Frame BackgroundTransparency")
local label = frame:FindFirstChild("Title")
assert(label ~= nil, "TextLabel should replicate")
assert(label.Text == "Hello Replication", "TextLabel text")
assert(label.Font == Enum.Font.Arcade, "TextLabel Font enum")
assert(label.TextScaled == true, "TextLabel TextScaled")
local corner = frame:FindFirstChild("UICorner")
assert(corner ~= nil and close(corner.CornerRadius.Offset, 8), "UICorner UDim")

-- Lighting effects replicated.
local nite = game:GetService("Lighting"):FindFirstChild("Nite")
assert(nite ~= nil and nite:IsA("ColorCorrectionEffect"), "ColorCorrectionEffect should replicate")
assert(close(nite.Brightness, 0.4) and close(nite.Saturation, 0.5), "ColorCorrectionEffect numbers")
assert(close(nite.TintColor.B, 0.8), "ColorCorrectionEffect TintColor")
local sky = game:GetService("Lighting"):FindFirstChild("SkyBox")
assert(sky ~= nil and close(sky.Density, 0.3), "Atmosphere should replicate")

-- PointLight property replication.
local lamp = workspace:FindFirstChild("Lamp")
assert(lamp ~= nil, "Lamp part replicates")
local lamp_light = lamp:FindFirstChild("LampLight")
assert(lamp_light ~= nil and lamp_light:IsA("PointLight"), "PointLight should replicate")
assert(close(lamp_light.Brightness, 2) and close(lamp_light.Range, 24), "PointLight numbers")
assert(close(lamp_light.Color.G, 1) and close(lamp_light.Color.B, 0), "PointLight Color")

-- Script code replication: ModuleScript Source requires + LocalScript runs on client.
local shared_mod = game:GetService("ReplicatedStorage"):FindFirstChild("SharedMod")
assert(shared_mod ~= nil, "ModuleScript should replicate to the client")
assert(shared_mod:IsA("ModuleScript"))
local mod = require(shared_mod)
assert(mod.greeting == "hi-from-module" and mod.count == 42, "ModuleScript Source should replicate")
local client_script = game:GetService("ReplicatedStorage"):FindFirstChild("ClientScript")
assert(client_script ~= nil and _G.CLIENT_SCRIPT_RAN == true, "LocalScript should replicate and run on the client")

-- ServerStorage / ServerScriptService must not leak.
assert(game:GetService("ServerStorage"):FindFirstChild("SecretPart") == nil, "ServerStorage must not replicate")
assert(game:GetService("ServerStorage"):FindFirstChild("SecretFlag") == nil, "ServerStorage values must not replicate")
assert(game:GetService("ServerScriptService"):FindFirstChild("SecretScript") == nil, "ServerScriptService must not replicate")
`, "breadth_client_broadcast")

	// Live property updates of replicated classes must reach the client.
	run_breadth(&server_vm, `
local frame = game:GetService("StarterGui"):FindFirstChild("Hud"):FindFirstChild("Backdrop")
frame:FindFirstChild("Title").Text = "Updated Text"
frame.BackgroundColor3 = Color3.new(0, 1, 0)
workspace:FindFirstChild("Lamp"):FindFirstChild("LampLight").Range = 30
`, "breadth_server_mutate")

	breadth_step(&server, &server_vm, &client, &client_vm, 15)

	run_breadth(&client_vm, `
local function close(a, b) return math.abs(a - b) <= 0.01 end

local frame = game:GetService("StarterGui"):FindFirstChild("Hud"):FindFirstChild("Backdrop")
assert(frame:FindFirstChild("Title").Text == "Updated Text", "live Text update should replicate")
assert(close(frame.BackgroundColor3.G, 1) and close(frame.BackgroundColor3.R, 0), "live color update should replicate")
assert(close(workspace:FindFirstChild("Lamp"):FindFirstChild("LampLight").Range, 30), "live PointLight update should replicate")
`, "breadth_client_live_update")

	run_breadth(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "breadth_server_stop")
	run_breadth(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "breadth_client_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("REPLICATION_BREADTH_SMOKE_PASSED")
}