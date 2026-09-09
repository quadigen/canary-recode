package globals

import vm "../vm"

Global_Kind :: enum {
	Nil,
	Number,
	Integer,
	Boolean,
	String,
	Function,
}

Global_Descriptor :: struct {
	name:         string,
	kind:         Global_Kind,
	number:       f64,
	integer:      int,
	boolean:      bool,
	string_value: string,
	function:     vm.CFunction,
}

Registry :: struct {
	globals: [dynamic]Global_Descriptor,
}

Register_String :: proc(registry: ^Registry, name, value: string) {
	append(&registry.globals, Global_Descriptor{name = name, kind = .String, string_value = value})
}

Register_Number :: proc(registry: ^Registry, name: string, value: f64) {
	append(&registry.globals, Global_Descriptor{name = name, kind = .Number, number = value})
}

Register_Integer :: proc(registry: ^Registry, name: string, value: int) {
	append(&registry.globals, Global_Descriptor{name = name, kind = .Integer, integer = value})
}

Register_Boolean :: proc(registry: ^Registry, name: string, value: bool) {
	append(&registry.globals, Global_Descriptor{name = name, kind = .Boolean, boolean = value})
}

Register_Function :: proc(registry: ^Registry, name: string, function: vm.CFunction) {
	append(&registry.globals, Global_Descriptor{name = name, kind = .Function, function = function})
}

Register_Default_Globals :: proc(registry: ^Registry) {
	Register_String(registry, "_KINEMIUM_VERSION", "0.1.0-odin")
	// wire:begin globals
	// wire:end globals
}

Install :: proc(registry: ^Registry, vm_state: ^vm.VM) {
	for global in registry.globals {
		switch global.kind {
		case .Nil:
			vm.AddGlobal_Nil(vm_state, global.name)
		case .Number:
			vm.AddGlobal_Number(vm_state, global.name, global.number)
		case .Integer:
			vm.AddGlobal_Integer(vm_state, global.name, global.integer)
		case .Boolean:
			vm.AddGlobal_Boolean(vm_state, global.name, global.boolean)
		case .String:
			vm.AddGlobal_String(vm_state, global.name, global.string_value)
		case .Function:
			vm.AddGlobal_Function(vm_state, global.name, global.function)
		}
	}
}

Registry_Destroy :: proc(registry: ^Registry) {
	if registry == nil {
		return
	}
	delete(registry.globals)
	registry.globals = nil
}
