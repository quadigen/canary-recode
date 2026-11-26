package services

import datatypes "../datatypes"
import vm "../vm"

REPLAY_MAX_FRAMES :: 256
Replication_Replay_State :: struct {
	position, velocity: datatypes.Vector3,
}
Replication_Replay_Input :: struct {
	tick:         u64,
	dt:           f64,
	acceleration: datatypes.Vector3,
}
Replication_Replay_Frame :: struct {
	input: Replication_Replay_Input,
	state: Replication_Replay_State,
}
Replication_Input_Replay :: struct {
	frames:            []Replication_Replay_Frame,
	head, count:       int,
	state:             Replication_Replay_State,
	last_tick:         u64,
	acknowledged_tick: u64,
	replayed:          u64,
}
Replication_Replay_Init :: proc(
	replay: ^Replication_Input_Replay,
	capacity: int,
	state: Replication_Replay_State,
) -> bool {
	if replay == nil ||
	   capacity < 1 ||
	   capacity > REPLAY_MAX_FRAMES ||
	   !rewind_finite_vec(state.position) ||
	   !rewind_finite_vec(state.velocity) {return false}
	Replication_Replay_Destroy(replay)
	replay.frames = make([]Replication_Replay_Frame, capacity); replay.state = state
	return true
}
Replication_Replay_Destroy :: proc(replay: ^Replication_Input_Replay) {if replay != nil {delete(
			replay.frames,
		)
		replay^ = {}}}
replay_kinematic_step :: proc(
	state: Replication_Replay_State,
	input: Replication_Replay_Input,
) -> Replication_Replay_State {
	return {
		datatypes.Vec3_Add(
			state.position,
			datatypes.Vec3_Add(
				datatypes.Vec3_Multiply(state.velocity, input.dt),
				datatypes.Vec3_Multiply(input.acceleration, 0.5 * input.dt * input.dt),
			),
		),
		datatypes.Vec3_Add(state.velocity, datatypes.Vec3_Multiply(input.acceleration, input.dt)),
	}
}
Replication_Replay_Push :: proc(
	replay: ^Replication_Input_Replay,
	input: Replication_Replay_Input,
) -> bool {
	if replay == nil ||
	   len(replay.frames) == 0 ||
	   input.tick <= replay.last_tick ||
	   !rewind_finite(input.dt) ||
	   input.dt <= 0 ||
	   input.dt > 0.25 ||
	   !rewind_finite_vec(input.acceleration) {return false}
	next := replay_kinematic_step(replay.state, input)
	if !rewind_finite_vec(next.position) || !rewind_finite_vec(next.velocity) {return false}
	replay.state = next; replay.last_tick = input.tick
	replay.frames[replay.head] = {
		input,
		next,
	}; replay.head = (replay.head + 1) % len(replay.frames); replay.count = min(replay.count + 1, len(replay.frames))
	return true
}
Replication_Replay_Reconcile :: proc(
	replay: ^Replication_Input_Replay,
	tick: u64,
	authoritative: Replication_Replay_State,
) -> bool {
	if replay == nil ||
	   replay.count == 0 ||
	   tick < replay.acknowledged_tick ||
	   !rewind_finite_vec(authoritative.position) ||
	   !rewind_finite_vec(authoritative.velocity) {return false}
	oldest := (replay.head - replay.count + len(replay.frames)) % len(replay.frames)
	index := -1
	for i in 0 ..< replay.count {if replay.frames[(oldest + i) % len(replay.frames)].input.tick == tick {index = i; break}}
	if index < 0 {return false}
	state := authoritative
	for i := index + 1; i < replay.count; i += 1 {
		slot :=
			(oldest + i) %
			len(replay.frames); state = replay_kinematic_step(state, replay.frames[slot].input)
		if !rewind_finite_vec(state.position) || !rewind_finite_vec(state.velocity) {return false}
	}
	state = authoritative
	for i := index + 1; i < replay.count; i += 1 {
		slot :=
			(oldest + i) %
			len(replay.frames); state = replay_kinematic_step(state, replay.frames[slot].input)
		replay.frames[slot].state = state; replay.replayed += 1
	}
	replay.frames[(oldest + index) % len(replay.frames)].state = authoritative
	replay.state = state; replay.acknowledged_tick = tick; replay.count -= index
	return true
}

REPLAY_MAX_HISTORIES :: 64
Replication_Replay_Registry :: struct {
	histories: map[u32]^Replication_Input_Replay,
	next_id:   u32,
}
Replication_Replay_Destroy_All :: proc(registry: ^Replication_Replay_Registry) {
	if registry == nil {return}
	for _, history in registry.histories {Replication_Replay_Destroy(history); free(history)}
	delete(registry.histories); registry^ = {}
}
replay_push_state :: proc(L: ^vm.State, history: ^Replication_Input_Replay) -> i32 {
	datatypes.Push_Vector3(L, history.state.position)
	datatypes.Push_Vector3(L, history.state.velocity)
	vm.PushNumber(L, f64(history.last_tick))
	return 3
}
Replication_Replay_Namecall :: proc(
	registry: ^Replication_Replay_Registry,
	L: ^vm.State,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {case "CreateInputReplay",
	                    "PushReplayInput",
	                    "ReconcileInputReplay",
	                    "GetInputReplayState",
	                    "DestroyInputReplay":
	case:
		return 0, false}
	if vm.ThreadIsParallel(
		L,
	) {return vm.RaiseError(L, "input replay is unavailable in parallel Luau"), true}
	if method == "CreateInputReplay" {
		capacity := vm.ArgOptionalNumber(L, 4, 128)
		if !rewind_finite(capacity) ||
		   capacity < 1 ||
		   capacity > REPLAY_MAX_FRAMES ||
		   f64(int(capacity)) != capacity ||
		   len(registry.histories) >= REPLAY_MAX_HISTORIES ||
		   registry.next_id ==
			   max(u32) {return vm.RaiseError(L, "input replay capacity limit exceeded"), true}
		history := new(Replication_Input_Replay)
		state := Replication_Replay_State{datatypes.Arg_Vector3(L, 2), datatypes.Arg_Vector3(L, 3)}
		if !Replication_Replay_Init(
			history,
			int(capacity),
			state,
		) {free(history); return vm.RaiseError(L, "invalid input replay state"), true}
		if registry.histories == nil {registry.histories = make(map[u32]^Replication_Input_Replay)}
		registry.next_id += 1; registry.histories[registry.next_id] = history
		vm.PushNumber(L, f64(registry.next_id)); return 1, true
	}
	id := vm.ArgNumber(L, 2)
	if !rewind_finite(id) ||
	   id < 1 ||
	   id > f64(max(u32)) ||
	   f64(u32(id)) != id {return vm.RaiseError(L, "invalid input replay handle"), true}
	history := registry.histories[u32(id)]
	if history == nil {return vm.RaiseError(L, "input replay handle is closed"), true}
	switch method {
	case "DestroyInputReplay":
		Replication_Replay_Destroy(history); free(history)
		delete_key(&registry.histories, u32(id))
		return 0, true
	case "GetInputReplayState":
		return replay_push_state(L, history), true
	case "PushReplayInput", "ReconcileInputReplay":
		tick := vm.ArgNumber(L, 3)
		if !rewind_finite(tick) ||
		   tick < 1 ||
		   tick > 9007199254740991 ||
		   f64(u64(tick)) != tick {return vm.RaiseError(L, "invalid input replay tick"), true}
		ok := false
		if method == "PushReplayInput" {
			ok = Replication_Replay_Push(
				history,
				{u64(tick), vm.ArgNumber(L, 4), datatypes.Arg_Vector3(L, 5)},
			)
		} else {
			ok = Replication_Replay_Reconcile(
				history,
				u64(tick),
				{datatypes.Arg_Vector3(L, 4), datatypes.Arg_Vector3(L, 5)},
			)
		}
		if !ok {vm.PushNil(L); return 1, true}
		return replay_push_state(L, history), true
	}
	return 0, false
}
