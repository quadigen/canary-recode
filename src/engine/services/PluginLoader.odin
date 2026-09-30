package services

import "core:fmt"

// wire:service global="PluginLoader"

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import dynlib "core:dynlib"

Extension_API :: struct {
	version:        u32,
	register_class: proc(info: ^classes.Class_Info) -> bool,
}

// api surface
API_Register_Class :: proc(info: ^classes.Class_Info) -> bool {
	
    return true
}

api := Extension_API {
	version        = 1,
	register_class = API_Register_Class,
}

// load_native_library
pluginloader_ldnl :: proc(path: string) {
	lib, ok := dynlib.load_library(path)

	if !ok {
		fmt.eprintf("Failed to load library: %s\n", dynlib.last_error())
		return
	}

	Extension_Initialize_Proc :: proc "c" (api: ^Extension_API) -> bool

	sym_addr, found := dynlib.symbol_address(lib, "KinemiumExtension_Initialize")
	if !found {
		fmt.eprintf("Extension is missing KinemiumExtension_Initialize\n")
		return
	}

	initialize := cast(Extension_Initialize_Proc)sym_addr

	success := initialize(&api)
	if !success {
		fmt.eprintf("Extension initialization failed\n")
		return
	}
}
