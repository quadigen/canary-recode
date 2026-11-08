package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import target "../src/engine/target"
import vm "../src/engine/vm"


KINE_PATH :: "build/template-release-export-smoke.kine"
OUT_FOLDER :: "build/template-release-export-smoke-out"
EXE_PATH :: OUT_FOLDER + "/KinemiumServer.exe"
ADDRESS :: "127.0.0.1"
PORT :: u16(47654)
GAME_NAME :: "template-release-export-smoke.kine"


@(private = "file")
run_script :: proc(script_vm: ^vm.VM, body, name: string) {
	previous := vm.GetThreadSecurityCapabilities(script_vm.L)
	vm.SetThreadSecurityCapabilities(script_vm.L, vm.THREAD_SECURITY_ALL)
	defer vm.SetThreadSecurityCapabilities(script_vm.L, previous)

	ok, err := vm.Run(script_vm, body, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("the script failed")
	}
}


build_and_export_map :: proc(script_vm: ^vm.VM) {
	run_script(
		script_vm,
		`
local model = Instance.new("Model")
model.Name = "ReleaseExportMap"
local part = Instance.new("Part")
part.Name = "Marker"
part.Position = Vector3.new(64, 12, 32)
part.Parent = model
model.Parent = game:GetService("Workspace")

assert(
	game:GetService("ExportService"):ExportToFileSync("` +
		KINE_PATH +
		`"),
	"ExportService:ExportToFile returned false"
)
`,
		"template_release_export_map",
	)
}


@(private = "file")
read_file :: proc(path: string) -> []u8 {
	data, read_error := os.read_entire_file_from_path(path, context.allocator)
	if read_error != nil || len(data) == 0 {
		panic(fmt.tprintf("could not read a non-empty file at %s", path))
	}
	return data
}

main :: proc() {
	os_name := services.update_os_tag()
	arch_name := services.update_arch_tag()
	p, ok := services.Template_Platform_From(os_name, arch_name)
	assert(ok, fmt.tprintf("host platform %s/%s is not a template target", os_name, arch_name))
	server_asset_name := services.Template_Asset_Name(.Server, p)
	defer delete(server_asset_name)


	latest, release_ok := services.Template_Fetch_Latest(p)
	if !release_ok {
		panic(
			"could not reach the canary-recode release manifest; the download cannot be exercised",
		)
	}
	defer services.Template_Checkpoint_Destroy(&latest)
	assert(len(latest.tag) > 0, "the release should carry a tag")
	assert(
		latest.server_asset.name == server_asset_name ||
		latest.server_asset.name == fmt.tprintf("%s.zip", server_asset_name),
		fmt.tprintf(
			"the release should publish %s, found %s",
			server_asset_name,
			latest.server_asset.name,
		),
	)
	assert(
		latest.client_asset.name != "",
		"the release should publish a client template alongside the server one",
	)
	fmt.printf(
		"[TemplateReleaseExport] release %s publishes %s (%d bytes)\n",
		latest.tag,
		latest.server_asset.name,
		latest.server_asset.size,
	)


	source_vm := vm.New()
	source: engine_runtime.Environment
	engine_runtime.Environment_Init(&source, &source_vm)
	defer {
		vm.Close(&source_vm)
		engine_runtime.Environment_Destroy(&source)
		_ = os.remove(KINE_PATH)
		_ = os.remove_all(OUT_FOLDER)
	}

	build_and_export_map(&source_vm)
	map_bytes := read_file(KINE_PATH)
	defer delete(map_bytes)


	template_path, problem := services.Template_Resolve(.Server, p)
	if template_path == "" {
		panic(fmt.tprintf("could not obtain the server template: %s", problem))
	}
	defer delete(template_path)

	assert(
		services.Template_Validate(template_path, p.format),
		fmt.tprintf("the resolved template %s is not a runnable executable", template_path),
	)


	cache_dir, _ := services.TemplateService_Cache_Paths()
	assert(cache_dir != "", "could not locate the template cache directory")
	defer delete(cache_dir)
	cached_path, cached_join := filepath.join(
		[]string{cache_dir, server_asset_name},
		context.allocator,
	)
	assert(cached_join == nil)
	defer delete(cached_path)
	version_file := strings.concatenate({cached_path, ".version"}, context.allocator)
	defer delete(version_file)
	bundled := strings.has_suffix(latest.server_asset.name, ".zip")
	assert(filepath.base(template_path) == server_asset_name)
	if bundled {
		assert(os.are_paths_identical(filepath.dir(filepath.dir(template_path)), cache_dir))
	} else {
		assert(
			template_path == cached_path ||
			os.are_paths_identical(filepath.dir(filepath.dir(template_path)), cache_dir),
		)
	}


	version_bytes := read_file(version_file)
	defer delete(version_bytes)
	cached_tag := strings.trim_space(string(version_bytes))
	assert(
		cached_tag == latest.tag,
		fmt.tprintf(
			"the cached template is marked %q but the release is %q",
			cached_tag,
			latest.tag,
		),
	)


	bake_ok, message := services.Exporter_Bake(
		OUT_FOLDER,
		ADDRESS,
		PORT,
		GAME_NAME,
		map_bytes,
		.Server,
		p,
	)
	if !bake_ok {
		panic(fmt.tprintf("bundling the downloaded template failed: %s", message))
	}
	defer delete(message)

	assert(os.is_file(EXE_PATH), "the export did not emit KinemiumServer.exe")
	assert(
		services.Template_Validate(EXE_PATH, p.format),
		"the bundled executable should still be a runnable image",
	)


	exe_bytes := read_file(EXE_PATH)
	defer delete(exe_bytes)
	template_file, open_err := os.open(template_path)
	assert(open_err == nil)
	template_size, size_err := os.file_size(template_file)
	os.close(template_file)
	assert(size_err == nil && i64(len(exe_bytes)) > template_size)
	if bundled && p.os_name == "windows" {
		assert(os.is_file(OUT_FOLDER + "/SDL3.dll"), "the export should include SDL3.dll")
	}

	payload, payload_ok := services.Payload_Read_Back(exe_bytes)
	assert(payload_ok, "the bundled executable should carry a readable payload")
	assert(
		payload.mode == target.Mode.Server,
		"the payload should be a server, matching the template",
	)
	assert(payload.address == ADDRESS, "the payload should carry the requested address")
	assert(payload.port == PORT, "the payload should carry the requested port")
	assert(payload.name == GAME_NAME, "the payload should carry the game name")
	assert(
		slice.equal(payload.map_bytes, map_bytes),
		"the map exported through ExportService should survive the bundle byte for byte",
	)

	fmt.printf(
		"[TemplateReleaseExport] bundled %s from release %s into %s\n",
		server_asset_name,
		latest.tag,
		EXE_PATH,
	)
	fmt.println("TEMPLATE_RELEASE_EXPORT_SMOKE_PASSED")
}
