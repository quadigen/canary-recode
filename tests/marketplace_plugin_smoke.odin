package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import target "../src/engine/target"
import vm "../src/engine/vm"

expect :: proc(ok: bool, message: string) {
	if !ok {
		panic(message)
	}
}

write_plugin_package :: proc(
	version_dir, name, version, entrypoint, source, tags: string,
	downloaded_at := i64(1),
	manifest_type := "",
) -> bool {
	metadata_dir, join_err := filepath.join(
		[]string{version_dir, ".kinemium-package"},
		context.allocator,
	)
	if join_err != nil {
		return false
	}
	defer delete(metadata_dir)
	if err := os.make_directory_all(metadata_dir); err != nil && !os.is_directory(metadata_dir) {
		return false
	}

	entrypoint_path, entrypoint_err := filepath.join(
		[]string{version_dir, entrypoint},
		context.allocator,
	)
	if entrypoint_err != nil {
		return false
	}
	defer delete(entrypoint_path)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, nil, .Editor)
	defer {
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
	}

	folder, folder_ok := classes.Push_New(&environment.classes, &script_vm, "Folder")
	script, script_ok := classes.Push_New(&environment.classes, &script_vm, "Script")
	expect(
		folder_ok && folder != nil && script_ok && script != nil,
		"could not create the plugin model",
	)
	classes.Set_Name(folder, "PluginPackage")
	classes.Set_Name(script, "PluginMain")
	classes.Set_Parent(script, folder)
	classes.Script_Common_Set_Source(script_vm.L, classes.Script_Common_Of(script), source)
	vm.Pop(script_vm.L)
	vm.Pop(script_vm.L)

	data, serialize_err := serializer.Serialize(&environment.classes, script_vm.L, folder)
	if !serializer.Error_Is_None(serialize_err) {
		detail := serializer.Error_String(serialize_err)
		fmt.eprintln(detail)
		delete(detail)
		serializer.Error_Delete(&serialize_err)
		return false
	}
	defer delete(data)

	if os.write_entire_file(entrypoint_path, data) != nil {
		return false
	}

	metadata_path, metadata_err := filepath.join(
		[]string{metadata_dir, "metadata.json"},
		context.allocator,
	)
	if metadata_err != nil {
		return false
	}
	defer delete(metadata_path)

	manifest_type_field := ""
	if manifest_type != "" {
		manifest_type_field = strings.concatenate(
			{`,"type":"`, manifest_type, `"`},
			context.allocator,
		)
	}
	defer if manifest_type_field != "" {
		delete(manifest_type_field)
	}

	metadata := strings.concatenate(
		{
			`{"namespace":"smoke","name":"`,
			name,
			`","version":"`,
			version,
			`","downloadedAt":`,
			fmt.tprintf("%d", downloaded_at),
			`,"packageData":{"package":{"tags":[`,
			tags,
			`]},"version":{"entrypoint":"`,
			entrypoint,
			`","manifest":{"entrypoint":"`,
			entrypoint,
			`"`,
			manifest_type_field,
			`}}}}`,
		},
		context.allocator,
	)
	defer delete(metadata)
	return os.write_entire_file_from_string(metadata_path, metadata) == nil
}

main :: proc() {
	target.set_mode(.Editor)

	version_dir, temp_err := os.make_directory_temp(
		"",
		"kinemium-marketplace-plugin-*",
		context.allocator,
	)
	expect(temp_err == nil, "could not create the plugin package directory")
	defer {
		_ = os.remove_all(version_dir)
		delete(version_dir)
	}

	expect(
		write_plugin_package(
			version_dir,
			"pluginpkg",
			"1.0.0",
			"plugin.kine",
			`plugin:CreateToolbar("MarketplaceSmoke")`,
			`"Plugin"`,
		),
		"could not build the plugin package",
	)

	case_fold_dir, case_fold_err := os.make_directory_temp(
		"",
		"kinemium-marketplace-plugin-case-*",
		context.allocator,
	)
	expect(case_fold_err == nil, "could not create the case-fold plugin package directory")
	defer {
		_ = os.remove_all(case_fold_dir)
		delete(case_fold_dir)
	}
	expect(
		write_plugin_package(
			case_fold_dir,
			"pluginpkg",
			"1.0.1",
			"plugin.kine",
			`plugin:CreateToolbar("CaseFoldPlugin")`,
			`"plugin"`,
		),
		"could not build the case-fold plugin package",
	)

	not_a_plugin_dir, not_a_plugin_err := os.make_directory_temp(
		"",
		"kinemium-marketplace-plugin-other-*",
		context.allocator,
	)
	expect(not_a_plugin_err == nil, "could not create the ordinary package directory")
	defer {
		_ = os.remove_all(not_a_plugin_dir)
		delete(not_a_plugin_dir)
	}
	expect(
		write_plugin_package(
			not_a_plugin_dir,
			"pluginpkg",
			"1.0.2",
			"plugin.kine",
			`plugin:CreateToolbar("ShouldNotRun")`,
			`"ui"`,
		),
		"could not build the ordinary package",
	)

	type_plugin_dir, type_plugin_err := os.make_directory_temp(
		"",
		"kinemium-marketplace-plugin-type-*",
		context.allocator,
	)
	expect(type_plugin_err == nil, "could not create the type plugin package directory")
	defer {
		_ = os.remove_all(type_plugin_dir)
		delete(type_plugin_dir)
	}
	expect(
		write_plugin_package(
			type_plugin_dir,
			"typeplugin",
			"1.0.0",
			"plugin.kine",
			`plugin:CreateToolbar("TypePlugin")`,
			"",
			1,
			"plugin",
		),
		"could not build the type-tagged plugin package",
	)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, nil, .Editor)
	defer {
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
	}

	packages_object := services.Ensure_Service(&environment.services, "Packages")
	expect(packages_object != nil, "the Packages service is unavailable")
	packages := cast(^services.Packages)packages_object

	expect(
		services.Packages_Run_Plugin_Directory(packages, version_dir),
		"a tagged plugin package was not loaded",
	)

	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)

	plugin_object := services.Ensure_Service(&environment.services, "Plugin")
	expect(plugin_object != nil, "the Plugin service is unavailable")
	plugin := cast(^services.Plugin)plugin_object
	expect(len(plugin.toolbars) == 1, "the plugin script did not run")
	expect(
		plugin.toolbars[0].title == "MarketplaceSmoke",
		"the plugin toolbar has the wrong title",
	)

	expect(
		services.Packages_Run_Plugin_Directory(packages, version_dir),
		"loading the same plugin twice should be a no-op",
	)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	expect(len(plugin.toolbars) == 1, "the same plugin package ran twice")

	expect(
		services.Packages_Run_Plugin_Directory(packages, case_fold_dir),
		"the plugin tag should be case-insensitive",
	)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	expect(len(plugin.toolbars) == 2, "the case-fold plugin did not run")

	expect(
		!services.Packages_Run_Plugin_Directory(packages, not_a_plugin_dir),
		"a package without the Plugin tag should not run",
	)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	expect(len(plugin.toolbars) == 2, "an ordinary package ran as a plugin")

	expect(
		services.Packages_Run_Plugin_Directory(packages, type_plugin_dir),
		"a package with manifest type plugin was not loaded",
	)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	expect(len(plugin.toolbars) == 3, "the manifest type plugin did not run")
	expect(
		plugin.toolbars[2].title == "TypePlugin",
		"the manifest type plugin has the wrong title",
	)

	scan_root, scan_err := os.make_directory_temp(
		"",
		"kinemium-marketplace-scan-*",
		context.allocator,
	)
	expect(scan_err == nil, "could not create the downloaded-packages root")
	defer {
		_ = os.remove_all(scan_root)
		delete(scan_root)
	}

	scan_dirs: [3]string
	defer for dir in scan_dirs {
		if dir != "" {
			delete(dir)
		}
	}

	scan_dirs[0], _ = filepath.join(
		[]string{scan_root, "smoke", "pluginpkg", "1.0.0"},
		context.allocator,
	)
	scan_dirs[1], _ = filepath.join(
		[]string{scan_root, "smoke", "pluginpkg", "2.0.0"},
		context.allocator,
	)
	scan_dirs[2], _ = filepath.join(
		[]string{scan_root, "smoke", "otherpkg", "1.0.0"},
		context.allocator,
	)

	expect(
		write_plugin_package(
			scan_dirs[0],
			"pluginpkg",
			"1.0.0",
			"plugin.kine",
			`plugin:CreateToolbar("ScanOldVersion")`,
			`"Plugin"`,
			1,
		),
		"could not build the old plugin package",
	)
	expect(
		write_plugin_package(
			scan_dirs[1],
			"pluginpkg",
			"2.0.0",
			"plugin.kine",
			`plugin:CreateToolbar("ScanNewVersion")`,
			`"Plugin"`,
			2,
		),
		"could not build the new plugin package",
	)
	expect(
		write_plugin_package(
			scan_dirs[2],
			"otherpkg",
			"1.0.0",
			"plugin.kine",
			`plugin:CreateToolbar("ScanShouldNotRun")`,
			`"ui"`,
			3,
		),
		"could not build the scan's ordinary package",
	)

	scan_vm := vm.New()
	scan_environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&scan_environment, &scan_vm, nil, .Editor)
	defer {
		vm.Close(&scan_vm)
		engine_runtime.Environment_Destroy(&scan_environment)
	}

	scan_packages_object := services.Ensure_Service(&scan_environment.services, "Packages")
	expect(scan_packages_object != nil, "the scan Packages service is unavailable")
	scan_packages := cast(^services.Packages)scan_packages_object

	services.Packages_Run_Downloaded_Plugins_In(scan_packages, scan_root)
	engine_runtime.Environment_Update_Step(&scan_environment, &scan_vm, 1.0 / 60.0)

	scan_plugin_object := services.Ensure_Service(&scan_environment.services, "Plugin")
	expect(scan_plugin_object != nil, "the scan Plugin service is unavailable")
	scan_plugin := cast(^services.Plugin)scan_plugin_object
	expect(len(scan_plugin.toolbars) == 1, "the startup scan did not load exactly one plugin")
	expect(
		scan_plugin.toolbars[0].title == "ScanNewVersion",
		"the startup scan did not pick the newest plugin version",
	)

	services.Packages_Run_Downloaded_Plugins_In(scan_packages, scan_root)
	engine_runtime.Environment_Update_Step(&scan_environment, &scan_vm, 1.0 / 60.0)
	expect(len(scan_plugin.toolbars) == 1, "the startup scan ran a plugin twice")

	fmt.println("MARKETPLACE_PLUGIN_SMOKE_PASSED")
}
