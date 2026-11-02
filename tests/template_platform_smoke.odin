package main

import fsutil "../src/engine/fsutil"
import services "../src/engine/services"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

write_1mb_with_magic :: proc(path: string, magic: []u8) {
	data := make([]u8, 1_000_000)
	copy(data[:], magic)
	_ = os.write_entire_file(path, data)
}

check_platform :: proc(os_name, arch_name, ext: string, format: services.Binary_Format) {
	p, ok := services.Template_Platform_From(os_name, arch_name)
	assert(ok, fmt.tprintf("Template_Platform_From(%s, %s) should succeed", os_name, arch_name))
	assert(p.os_name == os_name, "platform os_name should match input")
	assert(p.arch_name == arch_name, "platform arch_name should match input")
	assert(p.ext == ext, fmt.tprintf("platform ext for %s/%s", os_name, arch_name))
	assert(p.format == format, fmt.tprintf("platform format for %s/%s", os_name, arch_name))

	server_name := services.Template_Asset_Name(services.Template_Kind.Server, p)
	client_name := services.Template_Asset_Name(services.Template_Kind.Client, p)
	assert(
		server_name == strings.concatenate({"kinemium-server-", os_name, "-", arch_name, ext}),
		fmt.tprintf("bad server asset name: %s", server_name),
	)
	assert(
		client_name == strings.concatenate({"kinemium-client-", os_name, "-", arch_name, ext}),
		fmt.tprintf("bad client asset name: %s", client_name),
	)
	delete(server_name)
	delete(client_name)
}

main :: proc() {

	check_platform("windows", "x86_64", ".exe", services.Binary_Format.PE)
	check_platform("windows", "arm64", ".exe", services.Binary_Format.PE)
	check_platform("linux", "x86_64", "", services.Binary_Format.ELF)
	check_platform("linux", "arm64", "", services.Binary_Format.ELF)
	check_platform("macos", "arm64", "", services.Binary_Format.Mach_O)
	check_platform("macos", "x86_64", "", services.Binary_Format.Mach_O)
	check_platform("darwin", "arm64", "", services.Binary_Format.Mach_O)


	alias_p, alias_ok := services.Template_Platform_From("windows", "amd64")
	assert(alias_ok, "amd64 should be accepted as an architecture alias")
	assert(alias_p.arch_name == "x86_64", "amd64 should normalize to x86_64")
	alias_name := services.Template_Asset_Name(services.Template_Kind.Server, alias_p)
	assert(
		alias_name == "kinemium-server-windows-x86_64.exe",
		fmt.tprintf("bad alias asset name: %s", alias_name),
	)
	delete(alias_name)


	_, ok := services.Template_Platform_From("android", "arm64-v8a")
	assert(!ok, "android is not a native-binary template target")
	_, ok = services.Template_Platform_From("emscripten", "wasm32")
	assert(!ok, "emscripten is not a native-binary template target")


	host := services.Template_Host_Platform()
	hp, _ := services.Template_Platform_From(services.update_os_tag(), services.update_arch_tag())
	assert(
		host.os_name == hp.os_name && host.arch_name == hp.arch_name,
		"host platform should match update tags",
	)


	fake_dir := strings.concatenate({"build", "/template_platform_smoke"})
	_ = fsutil.Make_Directory_All(fake_dir)

	pe := strings.concatenate({fake_dir, "/pe_test.bin"})
	write_1mb_with_magic(pe, []u8{'M', 'Z'})
	assert(services.Template_Validate(pe, services.Binary_Format.PE), "PE magic should validate")
	assert(
		!services.Template_Validate(pe, services.Binary_Format.ELF),
		"PE file should not validate as ELF",
	)
	assert(
		!services.Template_Validate(pe, services.Binary_Format.Mach_O),
		"PE file should not validate as Mach-O",
	)
	_ = os.remove(pe)

	elf := strings.concatenate({fake_dir, "/elf_test.bin"})
	write_1mb_with_magic(elf, []u8{0x7f, 'E', 'L', 'F'})
	assert(
		services.Template_Validate(elf, services.Binary_Format.ELF),
		"ELF magic should validate",
	)
	assert(
		!services.Template_Validate(elf, services.Binary_Format.PE),
		"ELF file should not validate as PE",
	)
	assert(
		!services.Template_Validate(elf, services.Binary_Format.Mach_O),
		"ELF file should not validate as Mach-O",
	)
	_ = os.remove(elf)

	macho := strings.concatenate({fake_dir, "/macho_test.bin"})
	write_1mb_with_magic(macho, []u8{0xcf, 0xfa, 0xed, 0xfe})
	assert(
		services.Template_Validate(macho, services.Binary_Format.Mach_O),
		"Mach-O magic should validate",
	)
	assert(
		!services.Template_Validate(macho, services.Binary_Format.PE),
		"Mach-O file should not validate as PE",
	)
	assert(
		!services.Template_Validate(macho, services.Binary_Format.ELF),
		"Mach-O file should not validate as ELF",
	)
	_ = os.remove(macho)

	universal := strings.concatenate({fake_dir, "/universal_test.bin"})
	write_1mb_with_magic(universal, []u8{0xca, 0xfe, 0xba, 0xbe})
	assert(
		services.Template_Validate(universal, services.Binary_Format.Mach_O),
		"universal Mach-O magic should validate",
	)
	_ = os.remove(universal)

	_ = os.remove_all(fake_dir)


	small := strings.concatenate({fake_dir, "/small.bin"})
	_ = os.write_entire_file_from_string(small, "MZ")
	assert(
		!services.Template_Validate(small, services.Binary_Format.PE),
		"sub-1MB file should not validate",
	)
	_ = os.remove(small)

	fmt.println("TEMPLATE_PLATFORM_SMOKE_PASSED")
}
