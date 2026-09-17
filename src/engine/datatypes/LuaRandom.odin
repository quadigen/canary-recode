package datatypes

import "base:runtime"
import "core:math"
import core_rand "core:math/rand"

import vm "../vm"

RANDOM_MAX_SEED :: 9007199254740991.0

push_random :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
	value: Random,
) {
	push_value(L, binding, value)
}

Push_Random :: proc(
	L: ^vm.State,
	registry: ^Registry,
	value: Random,
) {
	push_random(
		L,
		&registry.random,
		value,
	)
}

require_random :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^Random {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected Random")
		return nil
	}

	return cast(^Random)vm.UserdataValue(L, index)
}

Arg_Random :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> ^Random {
	if registry == nil {
		return nil
	}

	return require_random(
		L,
		index,
		&registry.random,
	)
}

random_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	seed: u64

	if vm.IsNoneOrNil(L, 1) {
		seed = core_rand.uint64()
	} else {
		seed_number := vm.ArgNumber(L, 1)

		if seed_number != seed_number ||
		   seed_number < -RANDOM_MAX_SEED ||
		   seed_number > RANDOM_MAX_SEED {
			return vm.RaiseError(
				L,
				"Random seed must be between -9007199254740991 and 9007199254740991",
			)
		}

		seed_integer := i64(math.floor(seed_number))

		seed = u64(seed_integer)
	}

	push_random(
		L,
		binding_from_upvalue(L),
		Random_New(seed),
	)

	return 1
}

random_get :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
) -> bool {
	switch key {
	case "Clone",
	     "NextInteger",
	     "NextNumber",
	     "NextUnitVector",
	     "Shuffle":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}

random_clone :: proc(
	L: ^vm.State,
	random: ^Random,
	binding: ^vm.Userdata_Binding,
) -> i32 {
	push_random(
		L,
		binding,
		Random_Clone(random^),
	)

	return 1
}

random_next_integer :: proc(
	L: ^vm.State,
	random: ^Random,
) -> i32 {
	minimum := vm.ArgInteger(L, 2)
	maximum := vm.ArgInteger(L, 3)

	if minimum > maximum {
		return vm.RaiseError(
			L,
			"minimum cannot be greater than maximum",
		)
	}

	vm.PushInteger(
		L,
		Random_Next_Integer(
			random,
			minimum,
			maximum,
		),
	)

	return 1
}

random_next_number :: proc(
	L: ^vm.State,
	random: ^Random,
) -> i32 {
	argument_count := vm.StackTop(L) - 1

	if argument_count == 0 {
		vm.PushNumber(
			L,
			Random_Next_Number(random),
		)

		return 1
	}

	if argument_count != 2 {
		return vm.RaiseError(
			L,
			"NextNumber expects either 0 or 2 arguments",
		)
	}

	minimum := vm.ArgNumber(L, 2)
	maximum := vm.ArgNumber(L, 3)

	if minimum > maximum {
		return vm.RaiseError(
			L,
			"minimum cannot be greater than maximum",
		)
	}

	vm.PushNumber(
		L,
		Random_Next_Number(
			random,
			minimum,
			maximum,
		),
	)

	return 1
}

random_next_unit_vector :: proc(
	L: ^vm.State,
	random: ^Random,
) -> i32 {
	value := Random_Next_Unit_Vector(random)

	vm.PushVector3(
		L,
		value.x,
		value.y,
		value.z,
	)

	return 1
}

random_shuffle :: proc(
	L: ^vm.State,
	random: ^Random,
) -> i32 {
	if !vm.IsTable(L, 2) {
		return vm.RaiseError(
			L,
			"Shuffle expects a table",
		)
	}

	count := vm.RawLen(L, 2)

	for i in 1 ..= count {
		_ = vm.RawGetIndex(L, 2, i)

		if vm.IsNil(L, -1) {
			vm.Pop(L)

			return vm.RaiseError(
				L,
				"table contains a nil value",
			)
		}

		vm.Pop(L)
	}

	if count >= 2 {
		for i := count; i > 1; i -= 1 {
			j := int(
				Random_Next_Integer(
					random,
					1,
					i64(i),
				),
			)

			if i == j {
				continue
			}

			_ = vm.RawGetIndex(L, 2, i)
			_ = vm.RawGetIndex(L, 2, j)

			vm.PushValue(L, -1)
			vm.RawSetIndex(L, 2, i)

			vm.PushValue(L, -2)
			vm.RawSetIndex(L, 2, j)

			vm.Pop(L, 2)
		}
	}

	return 0
}

random_namecall :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	method: string,
) -> (i32, bool) {
	random := cast(^Random)value
	binding := cast(^vm.Userdata_Binding)ctx

	switch method {
	case "Clone":
		return random_clone(
			L,
			random,
			binding,
		), true

	case "NextInteger":
		return random_next_integer(
			L,
			random,
		), true

	case "NextNumber":
		return random_next_number(
			L,
			random,
		), true

	case "NextUnitVector":
		return random_next_unit_vector(
			L,
			random,
		), true

	case "Shuffle":
		return random_shuffle(
			L,
			random,
		), true
	}

	return 0, false
}

random_string :: proc(
	value,
	ctx: rawptr,
) -> string {
	return "Random"
}

random_destroy :: proc(
	value,
	ctx: rawptr,
) {
	free(cast(^Random)value)
}

Random_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name     = "Random",
		get      = random_get,
		namecall = random_namecall,
		string   = random_string,
		destroy  = random_destroy,
	}
}

Random_Install_Fields :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
) {
	add_library_function(
		L,
		binding,
		"new",
		random_new,
	)
}