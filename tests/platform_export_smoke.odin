package main

import fsutil "../src/engine/fsutil"
import services "../src/engine/services"
import target "../src/engine/target"
import "core:fmt"
import "core:os"
import "core:strings"

write_1mb_with_magic :: proc(path: string, magic: []u8) {
	data := make([]u8, 1_000_000)
	copy(data[:], magic)
	_ = os.write_entire_file(path, data)
}

linux_server := "kinemium-server-linux-x86_64"
linux_client := "kinemium-client-linux-x86_64"
macos_server := "kinemium-server-macos-arm64"
macos_client := "kinemium-client-macos-arm64"

main :: proc() {
	linux_p, ok := services.Template_Platform_From("linux", "x86_64")
	assert(ok)
	macos_p, macos_ok := services.Template_Platform_From("macos", "arm64")
	assert(macos_ok)

	cache_dir, _ := services.TemplateService_Cache_Paths()
	assert(cache_dir != "", "could not locate template cache directory")
	defer delete(cache_dir)


	write_1mb_with_magic(
		strings.concatenate({cache_dir, "/", linux_server}),
		[]u8{0x7f, 'E', 'L', 'F'},
	)
	write_1mb_with_magic(
		strings.concatenate({cache_dir, "/", linux_client}),
		[]u8{0x7f, 'E', 'L', 'F'},
	)
	write_1mb_with_magic(
		strings.concatenate({cache_dir, "/", macos_server}),
		[]u8{0xcf, 0xfa, 0xed, 0xfe},
	)
	write_1mb_with_magic(
		strings.concatenate({cache_dir, "/", macos_client}),
		[]u8{0xcf, 0xfa, 0xed, 0xfe},
	)

	out_dir := strings.concatenate({"build", "/platform_export_smoke"})
	_ = os.remove_all(out_dir)
	if fsutil.Make_Directory_All(out_dir) != nil && !os.is_directory(out_dir) {
		panic("could not create export output directory")
	}

	map_bytes := []u8{1, 2, 3, 4, 5}
	message := ""


	linux_server_out := strings.concatenate({out_dir, "/linux_server"})
	ok, message = services.ExportToExecutable(
		services.Template_Kind.Server,
		linux_p,
		linux_server_out,
		target.Mode.Server,
		"127.0.0.1",
		8080,
		"platform_export.kine",
		map_bytes,
	)
	assert(ok, fmt.tprintf("linux server export failed: %s", message))
	defer delete(message)
	assert(os.is_file(linux_server_out), "linux server export did not emit")
	assert(
		services.Template_Validate(linux_server_out, linux_p.format),
		fmt.tprintf("linux server export is not a valid ELF: %s", linux_server_out),
	)


	linux_client_out := strings.concatenate({out_dir, "/linux_client"})
	ok, message = services.ExportToExecutable(
		services.Template_Kind.Client,
		linux_p,
		linux_client_out,
		target.Mode.Client,
		"127.0.0.1",
		8081,
		"platform_export.kine",
		map_bytes,
	)
	assert(ok, fmt.tprintf("linux client export failed: %s", message))
	defer delete(message)
	assert(os.is_file(linux_client_out), "linux client export did not emit")
	assert(
		services.Template_Validate(linux_client_out, linux_p.format),
		fmt.tprintf("linux client export is not a valid ELF: %s", linux_client_out),
	)


	macos_server_out := strings.concatenate({out_dir, "/macos_server"})
	ok, message = services.ExportToExecutable(
		services.Template_Kind.Server,
		macos_p,
		macos_server_out,
		target.Mode.Server,
		"127.0.0.1",
		8082,
		"platform_export.kine",
		map_bytes,
	)
	assert(ok, fmt.tprintf("macOS server export failed: %s", message))
	defer delete(message)
	assert(os.is_file(macos_server_out), "macOS server export did not emit")
	assert(
		services.Template_Validate(macos_server_out, macos_p.format),
		fmt.tprintf("macOS server export is not a valid Mach-O: %s", macos_server_out),
	)


	macos_client_out := strings.concatenate({out_dir, "/macos_client"})
	ok, message = services.ExportToExecutable(
		services.Template_Kind.Client,
		macos_p,
		macos_client_out,
		target.Mode.Client,
		"127.0.0.1",
		8083,
		"platform_export.kine",
		map_bytes,
	)
	assert(ok, fmt.tprintf("macOS client export failed: %s", message))
	defer delete(message)
	assert(os.is_file(macos_client_out), "macOS client export did not emit")
	assert(
		services.Template_Validate(macos_client_out, macos_p.format),
		fmt.tprintf("macOS client export is not a valid Mach-O: %s", macos_client_out),
	)

	_ = os.remove_all(out_dir)
	fmt.println("PLATFORM_EXPORT_SMOKE_PASSED")
}
