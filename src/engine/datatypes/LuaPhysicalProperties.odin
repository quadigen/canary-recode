package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_physical_properties :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
	value: PhysicalProperties,
) {
	push_value(L, binding, value)
}

Push_PhysicalProperties :: proc(
	L: ^vm.State,
	registry: ^Registry,
	value: PhysicalProperties,
) {
	push_physical_properties(L, &registry.physical_properties, value)
}

Arg_PhysicalProperties :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> PhysicalProperties {
	return require_physical_properties(
		L,
		index,
		&registry.physical_properties,
	)^
}

require_physical_properties :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^PhysicalProperties {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected PhysicalProperties")
		return nil
	}

	return cast(^PhysicalProperties)vm.UserdataValue(L, index)
}

physical_properties_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	value := PhysicalProperties_New(
		f32(vm.ArgNumber(L, 1)),
		f32(vm.ArgNumber(L, 2)),
		f32(vm.ArgNumber(L, 3)),
		f32(vm.ArgOptionalNumber(L, 4, 100)),
		f32(vm.ArgOptionalNumber(L, 5, 100)),
	)

	if !PhysicalProperties_IsValid(value) {
		return vm.RaiseError(L, "invalid PhysicalProperties values")
	}

	push_physical_properties(
		L,
		binding_from_upvalue(L),
		value,
	)

	return 1
}

physical_properties_get :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
) -> bool {
	properties := cast(^PhysicalProperties)value

	switch key {
	case "Density":
		vm.PushNumber(L, f64(properties.Density))
	case "Friction":
		vm.PushNumber(L, f64(properties.Friction))
	case "Elasticity":
		vm.PushNumber(L, f64(properties.Elasticity))
	case "FrictionWeight":
		vm.PushNumber(L, f64(properties.FrictionWeight))
	case "ElasticityWeight":
		vm.PushNumber(L, f64(properties.ElasticityWeight))
	case:
		return false
	}

	return true
}

physical_properties_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^PhysicalProperties)value)^ ==
	       (cast(^PhysicalProperties)other)^
}

physical_properties_string :: proc(value, ctx: rawptr) -> string {
	p := cast(^PhysicalProperties)value

	return fmt.tprintf(
		"%g, %g, %g, %g, %g",
		p.Density,
		p.Friction,
		p.Elasticity,
		p.FrictionWeight,
		p.ElasticityWeight,
	)
}

physical_properties_destroy :: proc(value, ctx: rawptr) {
	free(cast(^PhysicalProperties)value)
}

PhysicalProperties_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "PhysicalProperties",
		get     = physical_properties_get,
		string  = physical_properties_string,
		destroy = physical_properties_destroy,
		equal   = physical_properties_equal,
	}
}

PhysicalProperties_Install_Fields :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
) {
	add_library_function(L, binding, "new", physical_properties_new)

	push_physical_properties(L, binding, PhysicalProperties_Default)
	vm.SetField(L, -2, "default")
}
