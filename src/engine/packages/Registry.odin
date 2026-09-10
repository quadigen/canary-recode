package packages

import "core:fmt"
import "core:strings"
import base_runtime "base:runtime"

import renderer "../renderer"
import vm "../vm"

Package_Installer :: proc(L: ^vm.State, ctx: rawptr, renderer_object: ^renderer.RendererObject)
Package_Begin_Frame :: proc(ctx: rawptr, width, height: i32)

Package_Descriptor :: struct {
	name:      string,
	installer: Package_Installer,
	begin_frame: Package_Begin_Frame,
	ctx:       rawptr,
	reference: i32,
}

Draw_Callback :: struct {
	reference: i32,
	priority:  i32,
}

Registry :: struct {
	vm_state:   ^vm.VM,
	renderer:   ^renderer.RendererObject,
	packages:   [dynamic]Package_Descriptor,
	callbacks:  [dynamic]Draw_Callback,
	contexts:   Package_Contexts,
	width:      i32,
	height:     i32,
}

Register_Package :: proc(
	registry: ^Registry,
	name: string,
	installer: Package_Installer,
	begin_frame: Package_Begin_Frame,
	ctx: rawptr,
) {
	assert(registry != nil)
	assert(installer != nil)
	for descriptor in registry.packages { assert(descriptor.name != name) }
	append(&registry.packages, Package_Descriptor{
		name = name,
		installer = installer,
		begin_frame = begin_frame,
		ctx = ctx,
	})
}

Resolve :: proc(L: ^vm.State, path: string, raw_registry: rawptr) -> bool {
	registry := cast(^Registry)raw_registry
	if registry == nil { return false }

	name := path
	if strings.has_prefix(path, "@engine/") {
		name = path[len("@engine/"):]
	} else if len(path) > 1 && path[0] == '@' {
		name = path[1:]
	} else {
		return false
	}

	for descriptor in registry.packages {
		if descriptor.name == name && descriptor.reference > 0 {
			vm.PushRegistryReference(L, descriptor.reference)
			return true
		}
	}
	return false
}

function_offset :: proc(L: ^vm.State) -> int {
	return vm.IsTable(L, 1) ? 1 : 0
}

registry_from_upvalue :: proc(L: ^vm.State) -> ^Registry {
	return cast(^Registry)vm.UpvaluePointer(L)
}

pool_new :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()
	registry := registry_from_upvalue(L)
	offset := function_offset(L)
	phase := vm.ArgString(L, 1+offset)
	if phase != "2d" && phase != "2da" {
		return vm.RaiseError(L, "renderer.Pool only supports 2d callbacks")
	}
	callback_index := 2+offset
	if !vm.IsFunction(L, callback_index) {
		return vm.RaiseError(L, "renderer.Pool.new expects a callback")
	}
	priority := i32(vm.ArgOptionalInteger(L, 3+offset, 0))
	reference := vm.RetainValue(L, callback_index)
	append(&registry.callbacks, Draw_Callback{reference = reference, priority = priority})
	for index := len(registry.callbacks)-1;
	    index > 0 && registry.callbacks[index-1].priority > priority;
	    index -= 1 {
		registry.callbacks[index] = registry.callbacks[index-1]
		registry.callbacks[index-1] = Draw_Callback{reference = reference, priority = priority}
	}
	vm.PushInteger(L, i64(reference))
	return 1
}

install_renderer_global :: proc(registry: ^Registry) {
	L := registry.vm_state.L
	vm.NewTable(L, 0, 8)
	vm.PushNumber(L, 0); vm.SetField(L, -2, "Width")
	vm.PushNumber(L, 0); vm.SetField(L, -2, "Height")
	vm.PushString(L, "3D"); vm.SetField(L, -2, "Dimension")
	vm.PushLightUserdata(L, registry.renderer); vm.SetField(L, -2, "Window")
	vm.NewTable(L, 0, 1)
	vm.PushNumber(L, 0); vm.SetField(L, -2, "dt")
	vm.SetField(L, -2, "RuntimeLibrary")
	vm.NewTable(L, 0, 1)
	vm.PushLightUserdata(L, registry)
	vm.PushFunction(L, "renderer.Pool.new", pool_new, 1)
	vm.SetField(L, -2, "new")
	vm.SetField(L, -2, "Pool")
	vm.SetGlobalFromStack(registry.vm_state, "renderer")
}

Init :: proc(registry: ^Registry, vm_state: ^vm.VM, renderer_object: ^renderer.RendererObject) {
	assert(registry != nil)
	registry.vm_state = vm_state
	registry.renderer = renderer_object
	Register_Default_Packages(registry)

	for &descriptor in registry.packages {
		descriptor.installer(vm_state.L, descriptor.ctx, renderer_object)
		assert(vm.IsTable(vm_state.L, -1))
		descriptor.reference = vm.RetainValue(vm_state.L)
		vm.PushValue(vm_state.L, -1)
		vm.SetGlobalFromStack(vm_state, descriptor.name)
		vm.Pop(vm_state.L)
	}

	install_renderer_global(registry)
	vm.AddGlobal_Boolean(vm_state, "IsServer", false)
	vm.AddGlobal_Boolean(vm_state, "IsClient", false)
	vm.NewTable(vm_state.L, 0, 8)
	vm.SetGlobalFromStack(vm_state, "ishared")
}

update_renderer_global :: proc(registry: ^Registry, delta_time: f32) {
	L := registry.vm_state.L
	if vm.GetGlobal(L, "renderer") != .Table { vm.Pop(L); return }
	defer vm.Pop(L)
	vm.PushNumber(L, f64(registry.width)); vm.SetField(L, -2, "Width")
	vm.PushNumber(L, f64(registry.height)); vm.SetField(L, -2, "Height")
	if vm.GetField(L, -1, "RuntimeLibrary") == .Table {
		vm.PushNumber(L, f64(delta_time)); vm.SetField(L, -2, "dt")
	}
	vm.Pop(L)
}

Render_2D :: proc(registry: ^Registry, width, height: i32, delta_time: f32) {
	if registry == nil || registry.vm_state == nil || registry.vm_state.L == nil { return }
	registry.width = width
	registry.height = height
	for descriptor in registry.packages {
		if descriptor.begin_frame != nil {
			descriptor.begin_frame(descriptor.ctx, width, height)
		}
	}
	update_renderer_global(registry, delta_time)

	for callback in registry.callbacks {
		vm.PushRegistryReference(registry.vm_state.L, callback.reference)
		vm.NewTable(registry.vm_state.L, 0, 1)
		vm.PushNumber(registry.vm_state.L, f64(delta_time))
		vm.SetField(registry.vm_state.L, -2, "dt")
		ok, err := vm.ProtectedCall(registry.vm_state.L, 1, 0)
		if !ok {
			fmt.eprintf("engine package render callback failed: %s\n", err)
			delete(err)
		}
	}
}

Destroy :: proc(registry: ^Registry) {
	if registry == nil { return }
	if registry.vm_state != nil && registry.vm_state.L != nil {
		for callback in registry.callbacks {
			vm.ReleaseValue(registry.vm_state.L, callback.reference)
		}
		for descriptor in registry.packages {
			vm.ReleaseValue(registry.vm_state.L, descriptor.reference)
		}
	}
	delete(registry.callbacks)
	delete(registry.packages)
	registry^ = Registry{}
}
