package main

import "core:fmt"
import "core:os"
import "core:path/filepath"

import kineffi "../src/engine/bindings"
import packages "../src/engine/packages"
import services "../src/engine/services"

expect :: proc(ok: bool, message: string) {
	if !ok {
		panic(message)
	}
}

main :: proc() {
	temp_dir, temp_err := os.make_directory_temp(
		"",
		"kinemium-editor-blob-*",
		context.allocator,
	)
	expect(temp_err == nil, "failed to create temporary directory")
	defer {
		_ = os.remove_all(temp_dir)
		delete(temp_dir)
	}
	expect(
		services.EditorService_Ensure_Directory(temp_dir),
		"existing editor cache directory was rejected",
	)
	cache_archive, cache_version, cache_ok := services.EditorService_Cache_Paths_From_Base(
		temp_dir,
		"Kinemium",
		"smoke test",
	)
	expect(cache_ok, "failed resolving editor cache paths")
	delete(cache_archive)
	delete(cache_version)

	archive_path, path_err := filepath.join(
		[]string{temp_dir, "editor.zip"},
		context.allocator,
	)
	expect(path_err == nil, "failed to create archive path")
	defer delete(archive_path)

	archive, created := kineffi.Zip_Create(archive_path)
	expect(created, "failed to create editor blob")
	expect(
		kineffi.Zip_Add_String(
			archive,
			"kinemium-editor-main/internal/editor_ui.luau",
			"return { source = 'remote editor' }",
		),
		"failed to add editor entrypoint",
	)
	expect(
		kineffi.Zip_Add_String(
			archive,
			"kinemium-editor-main/internal/panel.luau",
			"return { panel = true }",
		),
		"failed to add editor module",
	)
	expect(kineffi.Zip_Close(archive), "failed to finalize editor blob")

	expect(
		services.EditorService_Validate_Blob(archive_path),
		"valid editor blob was rejected",
	)
	expect(
		!services.EditorService_Needs_Download(
			true,
			"08bcf50a034887b05ce66e23464a886b24ab6594",
			"08bcf50a034887b05ce66e23464a886b24ab6594",
			true,
		),
		"matching editor version requested an update",
	)
	expect(
		services.EditorService_Needs_Download(
			true,
			"0000000000000000000000000000000000000000",
			"08bcf50a034887b05ce66e23464a886b24ab6594",
			true,
		),
		"new editor version was not detected",
	)
	expect(
		!services.EditorService_Needs_Download(true, "", "", false),
		"offline update check rejected a valid cache",
	)

	registry: packages.Registry
	expect(
		packages.Load_Internal_Modules_From_Blob(&registry, archive_path),
		"failed to load modules directly from editor blob",
	)
	expect(len(registry.internal_modules) == 2, "wrong editor module count")
	expect(registry.internal_modules[0].name == "editor_ui", "entrypoint module name was not normalized")
	expect(
		registry.internal_modules[0].source == "return { source = 'remote editor' }",
		"entrypoint module source did not come from the blob",
	)

	packages.Destroy(&registry)
	fmt.println("EDITOR_BLOB_SMOKE_PASSED")
}
