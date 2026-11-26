package main
import classes "../src/engine/classes"
import dt "../src/engine/datatypes"
import services "../src/engine/services"
import "core:fmt"
import "core:math"
main :: proc() {
	history: services.Replication_Rewind_History
	defer services.Replication_Rewind_Destroy(&history)
	assert(
		!services.Replication_Rewind_Configure(&history, 2, 120, 8192),
		"reject oversized history",
	)
	assert(services.Replication_Rewind_Configure(&history, 0.5, 30, 2))
	service: services.ReplicatorService; service.mode = .Server
	service.entity_by_id = make(
		map[u32]^services.Replication_Entity,
	); defer delete(service.entity_by_id)
	service.entity_ids = make(map[^classes.Object]u32); defer delete(service.entity_ids)
	part: classes.Part
	part.class = &classes.Part_Class; part.unique_id = dt.UniqueId_New()
	part.cframe = dt.CFrame_Identity; part.size = {2, 2, 2}; part.can_query = true
	entity := services.Replication_Entity {
		id     = 1,
		object = &part.object,
	}
	append(&service.entity_list, &entity); defer delete(service.entity_list)
	service.entity_by_id[1] = &entity; service.entity_ids[&part.object] = 1
	for tick in 0 ..< 30 {part.cframe.x = f64(tick); services.Replication_Rewind_Capture(&history, &service, f64(tick) / 30)}
	before := part.cframe
	frame, ok := services.Replication_Rewind_Frame(&history, &service, &part.object, 0.75)
	assert(ok && math.abs(frame.x - 22.5) < 0.001, "interpolates authoritative transform")
	hit, found := services.Replication_Rewind_Raycast(
		&history,
		&service,
		{20, 0, 0},
		{10, 0, 0},
		0.75,
	)
	assert(
		found && hit.object == &part.object && math.abs(hit.distance - 1.5) < 0.001,
		"historical box hit",
	)
	assert(part.cframe == before, "historical queries never mutate live transform")
	_, ok = services.Replication_Rewind_Frame(&history, &service, &part.object, 0)
	assert(!ok, "expired history refused")
	_, ok = services.Replication_Rewind_Frame(&history, &service, &part.object, 2)
	assert(!ok, "future time refused")
	part.cframe.x = 1000
	services.Replication_Rewind_Capture(&history, &service, 1.0)
	_, ok = services.Replication_Rewind_Frame(&history, &service, &part.object, 0.99)
	assert(!ok, "teleport discontinuities are not interpolated into phantom hit paths")
	part.unique_id = dt.UniqueId_New()
	_, ok = services.Replication_Rewind_Frame(&history, &service, &part.object, 0.75)
	assert(!ok, "identity reuse refuses previous occupant history")
	part.destroyed = true
	services.Replication_Rewind_Capture(&history, &service, 2)
	assert(len(history.tracks) == 0 && history.bytes == 0, "destroyed history reclaimed")
	assert(services.Replication_Rewind_Configure(&history, 0, 30, 1) && !history.enabled)
	replay: services.Replication_Input_Replay
	assert(
		services.Replication_Replay_Init(&replay, 4, {}),
	); defer services.Replication_Replay_Destroy(&replay)
	for tick in 1 ..= 6 {assert(services.Replication_Replay_Push(&replay, {u64(tick), 0.1, {10, 0, 0}}))}
	assert(replay.count == 4, "input history bounded")
	assert(
		!services.Replication_Replay_Reconcile(&replay, 1, {}),
		"evicted authoritative tick refused",
	)
	assert(services.Replication_Replay_Reconcile(&replay, 4, {{1, 0, 0}, {4, 0, 0}}))
	assert(
		math.abs(replay.state.position.x - 2) < 0.001 &&
		math.abs(replay.state.velocity.x - 6) < 0.001,
		"replays ticks 5 and 6 against corrected state",
	)
	assert(replay.replayed == 2)
	assert(
		!services.Replication_Replay_Push(&replay, {6, 0.1, {0, 0, 0}}),
		"duplicate input refused",
	)
	fmt.println("REPLICATION_REWIND_REPLAY_SMOKE_PASSED")
}
