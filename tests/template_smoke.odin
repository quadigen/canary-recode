package main

import "core:fmt"
import "core:os"
import services "../src/engine/services"

main :: proc() {
	name := services.Template_Asset_Name(services.Template_Kind.Server, "windows", "x86_64")
	assert(name == "kinemium-server-windows-x86_64.exe")
	delete(name)
	name = services.Template_Asset_Name(services.Template_Kind.Client, "windows", "x86_64")
	assert(name == "kinemium-client-windows-x86_64.exe")
	delete(name)

	fake := "build/template_smoke_fake.bin"
	defer os.remove(fake)
	_ = os.write_entire_file_from_string(fake, "not a real template")
	assert(!services.Template_Validate(fake))

	if os.is_file("build/kinemium-server.exe") {
		assert(services.Template_Validate("build/kinemium-server.exe"))
	}

	fmt.println("TEMPLATE_SMOKE_PASSED")
}