package services

// wire:service global="TweenService"

import "core:fmt"
import "core:math"
import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

TweenService_Class := classes.Class_Info {
	name   = "TweenService",
	parent = &Service_Class,
}

Tween_Value_Kind :: enum {
	Number,
	UDim2,
	Color3,
}

Tween_Value :: struct {
	kind:   Tween_Value_Kind,
	number: f64,
	udim2:  datatypes.UDim2,
	color3: datatypes.Color3,
}

Tween_Property :: struct {
	name:  string,
	start: Tween_Value,
	goal:  Tween_Value,
}

TweenService :: struct {
	using service: Service,
}

Tween_Class := classes.Class_Info {
	name   = "Tween",
	parent = &classes.Instance_Class,
}

Tween :: struct {
	using object:         classes.Object,
	instance_ref:         i32,
	info:                 datatypes.TweenInfo,
	state:                enums.PlaybackState,
	properties:           [dynamic]Tween_Property,
	elapsed:              f64,
	time_position:        f64,
	duration:             f64,
	total_cycles:         i64,
	completed_signal_ref: i32,
}

tween_read_value :: proc(L: ^vm.State, index: int) -> (Tween_Value, bool) {
	if vm.IsNumber(L, index) {
		value, ok := vm.ToNumber(L, index)

		if !ok {
			return Tween_Value{}, false
		}

		return Tween_Value{kind = .Number, number = value}, true
	}

	binding := vm.UserdataBindingOf(L, index)

	if binding == nil {
		return Tween_Value{}, false
	}

	switch binding.name {
	case "UDim2":
		ptr := cast(^datatypes.UDim2)vm.UserdataValue(L, index)

		if ptr == nil {
			return Tween_Value{}, false
		}

		return Tween_Value{kind = .UDim2, udim2 = ptr^}, true

	case "Color3":
		ptr := cast(^datatypes.Color3)vm.UserdataValue(L, index)

		if ptr == nil {
			return Tween_Value{}, false
		}

		return Tween_Value{kind = .Color3, color3 = ptr^}, true
	}

	return Tween_Value{}, false
}

tween_values_compatible :: proc(a, b: Tween_Value) -> bool {
	return a.kind == b.kind
}

tween_push_interpolated_value :: proc(
	L: ^vm.State,
	datatype_registry: ^datatypes.Registry,
	start, goal: Tween_Value,
	alpha: f64,
) -> bool {
	if start.kind != goal.kind {
		return false
	}

	switch start.kind {
	case .Number:
		value := start.number + (goal.number - start.number) * alpha

		vm.PushNumber(L, value)
		return true

	case .UDim2:
		value := datatypes.UDim2_Lerp(start.udim2, goal.udim2, f32(alpha))

		datatypes.Push_UDim2(L, datatype_registry, value)

		return true

	case .Color3:
		value := datatypes.Lerp(start.color3, goal.color3, f32(alpha))

		datatypes.Push_Color3(L, datatype_registry, value)

		return true
	}

	return false
}

tween_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	tween := new(Tween)
	tween.object = classes.Object_Init(&Tween_Class, "Tween")
	tween.state = .Begin
	tween.instance_ref = -1
	tween.completed_signal_ref = -1
	tween.total_cycles = 1
	return &tween.object
}

tween_loop_duration :: proc(info: datatypes.TweenInfo) -> (f64, i64) {
	total_cycles := i64(1)
	if info.RepeatCount >= 0 {
		total_cycles += i64(info.RepeatCount)
	}
	return f64(info.Time) * f64(total_cycles), total_cycles
}

tween_play :: proc(tween: ^Tween) {
	switch tween.state {
	case .Paused:
		tween.state = .Playing
	case .Begin, .Completed, .Cancelled:
		tween.elapsed = 0
		tween.time_position = 0
		tween.state = .Playing
	case .Playing, .Delayed:
	// already running
	}
}

tween_ensure_signal :: proc(L: ^vm.State, tween: ^Tween) -> bool {
	if tween.completed_signal_ref > 0 {
		return true
	}
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)

	if vm.GetGlobal(L, "Signal") != .Table {
		return false
	}
	if vm.GetField(L, -1, "new") != .Function {
		return false
	}
	ok, err := vm.ProtectedCall(L, 0, 1)
	if !ok {
		if err != "" {
			delete(err)
		}
		return false
	}
	tween.completed_signal_ref = vm.RetainValue(L)
	return tween.completed_signal_ref > 0
}

tween_push_signal :: proc(L: ^vm.State, tween: ^Tween) {
	if tween_ensure_signal(L, tween) {
		vm.PushRegistryReference(L, tween.completed_signal_ref)
	} else {
		vm.PushNil(L)
	}
}

tween_fire_completed :: proc(tween: ^Tween, L: ^vm.State) {
	if tween.completed_signal_ref <= 0 {
		return
	}
	class_registry := tween.signal_registry
	if class_registry == nil || class_registry.enums == nil {
		return
	}
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)

	vm.PushRegistryReference(L, tween.completed_signal_ref)
	if vm.TypeOf(L, -1) == .Nil {
		return
	}
	signal := cast(^signals.Signal)vm.UserdataValue(L, -1)
	if signal == nil {
		return
	}
	_ = enums.Push_Item_By_Value(L, class_registry.enums, "PlaybackState", i64(tween.state))
	signals.Fire(L, signal, 1)
}

tween_finish_completed :: proc(tween: ^Tween, L: ^vm.State) {
	if tween.state == .Completed || tween.state == .Cancelled {
		return
	}
	tween.state = .Completed
	tween_fire_completed(tween, L)
}

tween_cancel :: proc(tween: ^Tween, L: ^vm.State) {
	if tween.state == .Cancelled {
		return
	}
	tween.state = .Cancelled
	tween_fire_completed(tween, L)
}

apply_goal :: proc(tween: ^Tween, L: ^vm.State, eased: f64) {
	base := vm.StackTop(L)
	defer vm.SetStackTop(L, base)

	class_registry := tween.signal_registry

	if class_registry == nil || class_registry.datatypes == nil {
		return
	}

	datatype_registry := class_registry.datatypes

	vm.PushRegistryReference(L, tween.instance_ref)

	if vm.TypeOf(L, -1) == .Nil {
		return
	}

	instance_index := vm.StackTop(L)

	for prop in tween.properties {
		vm.SetStackTop(L, instance_index)

		if !tween_push_interpolated_value(L, datatype_registry, prop.start, prop.goal, eased) {
			continue
		}

		vm.SetField(L, instance_index, prop.name)
	}
}

tween_step :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	if ctx == nil || ctx.L == nil {
		return
	}
	tween := cast(^Tween)object
	if tween.destroyed {
		return
	}
	if tween.state != .Playing && tween.state != .Delayed {
		return
	}

	L := ctx.L
	tween.elapsed += f64(max(ctx.delta_time, 0))

	delay := f64(tween.info.DelayTime)
	if tween.elapsed < delay {
		tween.state = .Delayed
		tween.time_position = 0
		return
	}

	t := tween.elapsed - delay
	time_len := f64(tween.info.Time)

	if tween.info.RepeatCount >= 0 && t >= tween.duration {
		apply_goal(tween, L, 1.0)
		tween.time_position = tween.duration
		tween_finish_completed(tween, L)
		return
	}

	if time_len <= 0 {
		apply_goal(tween, L, 1.0)
		tween.time_position = tween.duration
		tween_finish_completed(tween, L)
		return
	}

	tween.state = .Playing

	cycle_index := i64(math.floor(t / time_len))
	alpha_cycle := clamp(t / time_len - f64(cycle_index), 0.0, 1.0)

	if tween.info.Reverses && cycle_index % 2 == 1 {
		alpha_cycle = 1.0 - alpha_cycle
	}

	eased := tween_get_value(
		alpha_cycle,
		i64(tween.info.EasingStyle),
		i64(tween.info.EasingDirection),
	)

	apply_goal(tween, L, eased)

	tween.time_position = min(t, tween.duration)
}

tween_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	tween := cast(^Tween)object
	switch key {
	case "PlaybackState":
		if enum_registry == nil {
			return false
		}
		_ = enums.Push_Item_By_Value(L, enum_registry, "PlaybackState", i64(tween.state))
	case "TimePosition":
		vm.PushNumber(L, tween.time_position)
	case "Duration":
		vm.PushNumber(L, tween.duration)
	case "Completed":
		tween_push_signal(L, tween)
	case "Play", "Pause", "Cancel":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

tween_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	tween := cast(^Tween)object
	switch key {
	case "TimePosition":
		position := max(0.0, vm.ArgNumber(L, value_index))
		tween.time_position = position
		tween.elapsed = f64(tween.info.DelayTime) + position
	case:
		return false
	}
	return true
}

tween_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	tween := cast(^Tween)object
	switch method {
	case "Play":
		tween_play(tween)
		return 0, true
	case "Pause":
		if tween.state == .Playing || tween.state == .Delayed {
			tween.state = .Paused
		}
		return 0, true
	case "Cancel":
		tween_cancel(tween, L)
		return 0, true
	}
	return 0, false
}

tween_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	tween := cast(^Tween)object
	class_registry := tween.signal_registry
	L: ^vm.State = nil
	if class_registry != nil &&
	   class_registry.vm_state != nil &&
	   class_registry.vm_state.L != nil {
		L = class_registry.vm_state.L
	}
	if L != nil {
		if tween.instance_ref > 0 {
			vm.ReleaseValue(L, tween.instance_ref)
		}
		if tween.completed_signal_ref > 0 {
			vm.ReleaseValue(L, tween.completed_signal_ref)
		}
	}
	for prop in tween.properties {
		delete(prop.name)
	}
	delete(tween.properties)
	classes.Object_Destroy(object)
	free(tween)
}

tween_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(TweenService)
	service.service = Service_Init(&TweenService_Class, "TweenService", data_model)
	return &service.object
}

tween_bounce_out :: proc(t: f64) -> f64 {
	n1: f64 = 7.5625
	d1: f64 = 2.75

	if t < 1 / d1 {
		return n1 * t * t
	}

	if t < 2 / d1 {
		x := t - 1.5 / d1
		return n1 * x * x + 0.75
	}

	if t < 2.5 / d1 {
		x := t - 2.25 / d1
		return n1 * x * x + 0.9375
	}

	x := t - 2.625 / d1
	return n1 * x * x + 0.984375
}

tween_ease_in :: proc(alpha: f64, style: i64) -> f64 {
	t := clamp(alpha, 0.0, 1.0)

	switch style {
	case 0:
		// Linear
		return t

	case 1:
		// Sine
		return 1 - math.cos((t * math.PI) / 2)

	case 2:
		// Back
		c1: f64 = 1.70158
		c3 := c1 + 1
		return c3 * t * t * t - c1 * t * t

	case 3:
		// Quad
		return t * t

	case 4:
		// Quart
		t2 := t * t
		return t2 * t2

	case 5:
		// Quint
		t2 := t * t
		return t2 * t2 * t

	case 6:
		// Bounce
		return 1 - tween_bounce_out(1 - t)

	case 7:
		// Elastic
		if t == 0 || t == 1 {
			return t
		}
		c4 := (2 * math.PI) / 3
		return -math.pow(2.0, 10 * t - 10) * math.sin((t * 10 - 10.75) * c4)

	case 8:
		// Exponential
		if t == 0 {
			return 0
		}
		return math.pow(2.0, 10 * t - 10)

	case 9:
		// Circular
		return 1 - math.sqrt(max(0.0, 1 - t * t))

	case 10:
		// Cubic
		return t * t * t
	}

	return t
}

tween_get_value :: proc(alpha: f64, style: i64, direction: i64) -> f64 {
	t := clamp(alpha, 0.0, 1.0)

	switch direction {
	case 0:
		// In
		return tween_ease_in(t, style)

	case 1:
		// Out
		return 1 - tween_ease_in(1 - t, style)

	case 2:
		// InOut
		if t < 0.5 {
			return tween_ease_in(t * 2, style) / 2
		}
		return 1 - tween_ease_in((1 - t) * 2, style) / 2
	}

	return tween_ease_in(t, style)
}

tween_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "Create", "GetValue":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}

tween_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "Create":
		return tween_create(L, object, datatype_registry)

	case "GetValue":
		if enum_registry == nil {
			return 0, false
		}

		alpha := vm.ArgNumber(L, 2)

		style := enums.Arg_Item(L, 3, enum_registry, "EasingStyle")

		direction := enums.Arg_Item(L, 4, enum_registry, "EasingDirection")

		vm.PushNumber(L, tween_get_value(alpha, style.value, direction.value))

		return 1, true
	}

	return 0, false
}

tween_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^TweenService)object)
}

tween_create :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
) -> (
	i32,
	bool,
) {
	service := cast(^TweenService)object
	if service == nil ||
	   service.data_model == nil ||
	   service.data_model.registry == nil ||
	   service.data_model.registry.classes == nil {
		return vm.RaiseError(L, "TweenService is unavailable"), true
	}
	class_registry := service.data_model.registry.classes

	binding := vm.UserdataBindingOf(L, 2)
	if binding == nil || binding.name != "Instance" {
		return vm.RaiseError(L, "TweenService:Create expects an Instance"), true
	}
	target := cast(^classes.Object)vm.UserdataValue(L, 2)
	if target == nil || target.destroyed || !classes.Object_Is_Accessible(L, target) {
		return vm.RaiseError(L, "TweenService:Create expects an accessible Instance"), true
	}

	if datatype_registry == nil {
		return vm.RaiseError(L, "TweenService datatypes are unavailable"), true
	}
	info := datatypes.Arg_TweenInfo(L, 3, datatype_registry)

	if !vm.IsTable(L, 4) {
		return vm.RaiseError(L, "TweenService:Create expects a goal table"), true
	}

	vm_state := vm.VM {
		L = L,
	}
	tween_object, ok := classes.Push_New(class_registry, &vm_state, "Tween", false)
	if !ok {
		return vm.RaiseError(L, "failed to create Tween"), true
	}
	tween := cast(^Tween)tween_object
	tween.info = info
	tween.duration, tween.total_cycles = tween_loop_duration(info)

	vm.PushValue(L, 2)
	tween.instance_ref = vm.RetainValue(L)
	vm.Pop(L)

	property_count := 0

	vm.PushNil(L)

	for vm.Next(L, 4) {
		property_name, name_ok := vm.ToString(L, -2)

		if !name_ok {
			return vm.RaiseError(L, "TweenService:Create goal table keys must be property names"),
				true
		}

		goal, goal_ok := tween_read_value(L, -1)

		if !goal_ok {
			return vm.RaiseError(
					L,
					fmt.tprintf(
						"TweenService:Create unsupported goal type for property %q",
						property_name,
					),
				),
				true
		}

		vm.GetField(L, 2, property_name)

		start, start_ok := tween_read_value(L, -1)

		vm.Pop(L)

		if !start_ok {
			return vm.RaiseError(
					L,
					fmt.tprintf("TweenService:Create property %q is not tweenable", property_name),
				),
				true
		}

		if !tween_values_compatible(start, goal) {
			return vm.RaiseError(
					L,
					fmt.tprintf(
						"TweenService:Create property %q has incompatible start and goal types",
						property_name,
					),
				),
				true
		}

		append(
			&tween.properties,
			Tween_Property{name = strings.clone(property_name), start = start, goal = goal},
		)

		property_count += 1

		vm.Pop(L)
	}

	if property_count == 0 {
		return vm.RaiseError(L, "TweenService:Create goal table must not be empty"), true
	}

	return 1, true
}

Register_TweenService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&TweenService_Class,
		tween_service_construct,
		tween_service_destroy,
		creatable = false,
		get = tween_service_get,
		namecall = tween_service_namecall,
	)
}

Register_Tween_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Tween_Class,
		tween_construct,
		tween_destroy,
		creatable = false,
		get = tween_get,
		set = tween_set,
		namecall = tween_namecall,
		_step = tween_step,
		_step_phase = .Update,
	)
}
