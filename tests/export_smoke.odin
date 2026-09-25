package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import enet "vendor:ENet"
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import target "../src/engine/target"
import vm "../src/engine/vm"

enet_connect_ok :: proc(port: u16) -> bool {
	if enet.initialize() != 0 {
		return false
	}
	defer enet.deinitialize()
	host := enet.host_create(nil, 1, 2, 0, 0)
	if host == nil {
		return false
	}
	defer enet.host_destroy(host)
	endpoint := enet.Address{port = port}
	name := strings.clone_to_cstring("127.0.0.1")
	defer delete(name)
	if enet.address_set_host(&endpoint, name) != 0 {
		return false
	}
	peer := enet.host_connect(host, &endpoint, 2, 0)
	if peer == nil {
		return false
	}
	for iteration in 0 ..< 400 {
		event: enet.Event
		for enet.host_service(host, &event, 10) > 0 {
			switch event.type {
			case .CONNECT:
				return true
			case .DISCONNECT:
				return false
			case .RECEIVE:
				if event.packet != nil {
					enet.packet_destroy(event.packet)
				}
			case .NONE:
			}
		}
	}
	return false
}

main :: proc() {
	assert(os.is_file("build/kinemium-server.exe"), "Run `just server` first")

	source_vm := vm.New()
	source: engine_runtime.Environment
	engine_runtime.Environment_Init(&source, &source_vm)
	model, model_ok := classes.Push_New(&source.classes, &source_vm, "Model")
	assert(model_ok && model != nil)
	classes.Set_Name(model, "ExportSmokeModel")
	vm.Pop(source_vm.L)
	workspace_source := services.Ensure_Service(&source.services, "Workspace")
	classes.Set_Parent(model, workspace_source)
	assert(serializer.Serialize_To_File(
		&source.classes,
		source_vm.L,
		&source.services.data_model.object,
		"build/export-smoke.kine",
	))

	map_bytes, map_ok := os.read_entire_file_from_path("build/export-smoke.kine", context.allocator)
	assert(map_ok == nil && len(map_bytes) > 0)
	defer delete(map_bytes)

	ok, message := services.ExportToExecutable(
		services.Template_Kind.Server,
		"build/export-smoke-export.exe",
		target.Mode.Server,
		"127.0.0.1",
		34567,
		"export-smoke.kine",
		map_bytes,
	)
	assert(ok, message)
	defer delete(message)
	assert(os.is_file("build/export-smoke-export.exe"))

	server, start_err := os.process_start(os.Process_Desc{
		command = []string{"build/export-smoke-export.exe"},
		stdin   = os.stdin,
		stdout  = os.stdout,
		stderr  = os.stderr,
	})
	assert(start_err == nil)
	assert(enet_connect_ok(34567), "baked port 34567 did not accept an ENet connection")
	_ = os.process_kill(server)
	_, _ = os.process_wait(server)

	server2, start2_err := os.process_start(os.Process_Desc{
		command = []string{"build/export-smoke-export.exe", "--port", "24444"},
		stdin   = os.stdin,
		stdout  = os.stdout,
		stderr  = os.stderr,
	})
	assert(start2_err == nil)
	assert(enet_connect_ok(24444), "CLI override port 24444 did not accept an ENet connection")
	_ = os.process_kill(server2)
	_, _ = os.process_wait(server2)

	cache_dir, version_file := services.TemplateService_Cache_Paths()
	assert(cache_dir != "", "could not locate the template cache dir")
	defer delete(cache_dir)
	defer delete(version_file)
	server_asset_name := services.Template_Asset_Name(services.Template_Kind.Server, "windows", "x86_64")
	server_asset, server_join := filepath.join([]string{cache_dir, server_asset_name}, context.allocator)
	delete(server_asset_name)
	assert(server_join == nil)
	defer delete(server_asset)
	assert(os.copy_file(server_asset, "build/kinemium-server.exe") == os.ERROR_NONE)
	client_asset_name := services.Template_Asset_Name(services.Template_Kind.Client, "windows", "x86_64")
	client_asset, client_join := filepath.join([]string{cache_dir, client_asset_name}, context.allocator)
	delete(client_asset_name)
	assert(client_join == nil)
	defer delete(client_asset)
	assert(os.copy_file(client_asset, "build/kinemium-client.exe") == os.ERROR_NONE)
	sibling_seed, seed_join := filepath.join([]string{cache_dir, "config.toml"}, context.allocator)
	assert(seed_join == nil)
	defer delete(sibling_seed)
	_ = os.write_entire_file_from_string(sibling_seed, "engine = brandi\n")
	_ = os.write_entire_file_from_string(version_file, "v0.0.0-smoke")

	bake_ok, bake_message := services.Exporter_Bake(
		"build/export-smoke-out",
		"127.0.0.1",
		45678,
		"export-smoke.kine",
		map_bytes,
		services.Exporter_Kind.Both,
	)
	assert(bake_ok, bake_message)
	defer delete(bake_message)
	assert(os.is_file("build/export-smoke-out/KinemiumServer.exe"), "Exporter_Bake did not emit the server exe")
	assert(os.is_file("build/export-smoke-out/KinemiumClient.exe"), "Exporter_Bake did not emit the client exe")
	assert(os.is_file("build/export-smoke-out/config.toml"), "Exporter_Bake did not copy the template's runtime siblings")
	server3, start3_err := os.process_start(os.Process_Desc{
		command = []string{"build/export-smoke-out/KinemiumServer.exe"},
		stdin   = os.stdin,
		stdout  = os.stdout,
		stderr  = os.stderr,
	})
	assert(start3_err == nil)
	assert(enet_connect_ok(45678), "Exporter_Bake server port 45678 did not accept an ENet connection")
	_ = os.process_kill(server3)
	_, _ = os.process_wait(server3)

	fmt.println("EXPORT_SMOKE_PASSED")
}