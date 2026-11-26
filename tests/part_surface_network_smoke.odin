package main

import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.Run(v, source, "part_surface_network_smoke")
	assert(ok, err)
}

step :: proc(server, client: ^runtime.Environment, server_vm, client_vm: ^vm.VM) {
	runtime.Environment_Render_Step(server, server_vm, 1.0 / 60.0)
	runtime.Environment_Render_Step(client, client_vm, 1.0 / 60.0)
	time.sleep(3 * time.Millisecond)
}

main :: proc() {
	server_vm, client_vm := vm.New(), vm.New()
	server, client: runtime.Environment
	runtime.Environment_Init(&server, &server_vm)
	runtime.Environment_Init(&client, &client_vm)
	defer {vm.Close(&server_vm); runtime.Environment_Destroy(&server)}
	defer {vm.Close(&client_vm); runtime.Environment_Destroy(&client)}
	run(&server_vm, `
local r = game:GetService("ReplicatorService")
assert(r:StartServer("127.0.0.1", 39873))
p = Instance.new("Part", workspace)
p.Name = "NetworkSurface"
p.Anchored = true
p.TopSurface = Enum.SurfaceType.Studs
p.BottomSurface = Enum.SurfaceType.Inlet
p.FrontSurface = Enum.SurfaceType.Glue
p.BackSurface = Enum.SurfaceType.Universal
p.LeftSurface = Enum.SurfaceType.Weld
p.RightSurface = Enum.SurfaceType.SmoothNoOutlines
`)
	run(&client_vm, `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39873))`)
	for _ in 0..<300 {step(&server, &client, &server_vm, &client_vm)}
	run(&client_vm, `
local p = workspace.NetworkSurface
assert(p.TopSurface == Enum.SurfaceType.Studs)
assert(p.BottomSurface == Enum.SurfaceType.Inlet)
assert(p.FrontSurface == Enum.SurfaceType.Glue)
assert(p.BackSurface == Enum.SurfaceType.Universal)
assert(p.LeftSurface == Enum.SurfaceType.Weld)
assert(p.RightSurface == Enum.SurfaceType.SmoothNoOutlines)
`)
	run(&server_vm, `p.TopSurface = Enum.SurfaceType.Smooth; p.FrontSurface = Enum.SurfaceType.Studs`)
	for _ in 0..<150 {step(&server, &client, &server_vm, &client_vm)}
	run(&client_vm, `
local p = workspace.NetworkSurface
assert(p.TopSurface == Enum.SurfaceType.Smooth)
assert(p.FrontSurface == Enum.SurfaceType.Studs)
game:GetService("ReplicatorService"):Stop()
`)
	run(&server_vm, `game:GetService("ReplicatorService"):Stop()`)
	fmt.println("PART_SURFACE_NETWORK_SMOKE_PASSED")
}
