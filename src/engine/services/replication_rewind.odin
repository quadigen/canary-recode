package services

import classes "../classes"
import datatypes "../datatypes"
import vm "../vm"
import "core:math"

REWIND_MAX_BYTES :: 32 * 1024 * 1024
REWIND_MAX_SAMPLES :: 128
REWIND_MAX_ENTITIES :: 8192

Replication_Rewind_Sample :: struct {
	time:                     f64,
	frame:                    datatypes.CFrame,
	size:                     datatypes.Vector3,
	can_query, discontinuous: bool,
}
Replication_Rewind_Track :: struct {
	identity:    datatypes.UniqueId,
	samples:     []Replication_Rewind_Sample,
	head, count: int,
	seen:        u64,
}
Replication_Rewind_History :: struct {
	enabled:                             bool,
	window, interval, now, last_capture: f64,
	capacity, max_entities:              int,
	tracks:                              map[u32]^Replication_Rewind_Track,
	generation, captures, dropped:       u64,
	bytes:                               int,
}
Replication_Rewind_Hit :: struct {
	object:    ^classes.Object,
	entity_id: u32,
	position:  datatypes.Vector3,
	normal:    datatypes.Vector3,
	distance:  f64,
}
rewind_finite :: proc(v: f64) -> bool {return !math.is_nan(v) && !math.is_inf(v)}
rewind_finite_vec :: proc(v: datatypes.Vector3) -> bool {return(
		rewind_finite(v.x) &&
		rewind_finite(v.y) &&
		rewind_finite(v.z) \
	)}
Replication_Rewind_Destroy :: proc(h: ^Replication_Rewind_History) {
	if h == nil {return}
	for _, t in h.tracks {delete(t.samples); free(t)}
	delete(h.tracks)
	h^ = {}
}
Replication_Rewind_Configure :: proc(
	h: ^Replication_Rewind_History,
	window_seconds, sample_rate: f64,
	max_entities: int,
) -> bool {
	if h == nil || !rewind_finite(window_seconds) || !rewind_finite(sample_rate) {return false}
	if window_seconds == 0 {Replication_Rewind_Destroy(h); return true}
	if window_seconds < 0.01 ||
	   window_seconds > 2 ||
	   sample_rate < 1 ||
	   sample_rate > 120 ||
	   max_entities < 1 ||
	   max_entities > REWIND_MAX_ENTITIES {return false}
	capacity := int(math.ceil(window_seconds * sample_rate)) + 2
	if capacity > REWIND_MAX_SAMPLES ||
	   capacity * max_entities * size_of(Replication_Rewind_Sample) >
		   REWIND_MAX_BYTES {return false}
	Replication_Rewind_Destroy(h)
	h.enabled = true; h.window = window_seconds; h.interval = 1 / sample_rate
	h.capacity = capacity; h.max_entities = max_entities
	h.tracks = make(map[u32]^Replication_Rewind_Track)
	h.last_capture = -1
	return true
}
Replication_Rewind_Capture :: proc(
	h: ^Replication_Rewind_History,
	service: ^ReplicatorService,
	now: f64,
) {
	if h == nil ||
	   !h.enabled ||
	   service == nil ||
	   service.mode != .Server ||
	   !rewind_finite(now) {return}
	if now < h.now {
		window, rate, limit := h.window, 1 / h.interval, h.max_entities
		_ = Replication_Rewind_Configure(h, window, rate, limit)
	}
	h.now = now
	if h.last_capture >= 0 && now - h.last_capture < h.interval {return}
	h.last_capture = now; h.generation += 1; h.captures += 1
	for entity in service.entity_list {
		if entity == nil ||
		   entity.object == nil ||
		   entity.object.destroyed ||
		   !classes.Is_A(entity.object, "Part") {continue}
		object := entity.object; part := cast(^classes.Part)object
		if !rewind_finite_vec(datatypes.CFrame_Position(part.cframe)) ||
		   !rewind_finite_vec(part.size) {continue}
		track := h.tracks[entity.id]
		if track != nil && track.identity != object.unique_id {
			delete(
				track.samples,
			); free(track); delete_key(&h.tracks, entity.id); h.bytes -= h.capacity * size_of(Replication_Rewind_Sample); track = nil
		}
		if track == nil {
			if len(h.tracks) >= h.max_entities {h.dropped += 1; continue}
			track = new(Replication_Rewind_Track)
			track.identity =
				object.unique_id; track.samples = make([]Replication_Rewind_Sample, h.capacity)
			h.tracks[entity.id] = track; h.bytes += h.capacity * size_of(Replication_Rewind_Sample)
		}
		track.seen = h.generation
		discontinuous := false
		if track.count > 0 {
			previous := track.samples[(track.head - 1 + len(track.samples)) % len(track.samples)]
			threshold := f64(service.teleport_threshold)
			if threshold <= 0 {threshold = 64}
			discontinuous =
				datatypes.Vec3_Magnitude(
					datatypes.Vec3_Subtract(
						datatypes.CFrame_Position(part.cframe),
						datatypes.CFrame_Position(previous.frame),
					),
				) >
				threshold
		}
		track.samples[track.head] = {now, part.cframe, part.size, part.can_query, discontinuous}
		track.head =
			(track.head + 1) %
			len(track.samples); track.count = min(track.count + 1, len(track.samples))
	}
	stale := make([dynamic]u32, 0, len(h.tracks), context.temp_allocator)
	for id, track in h.tracks {if track.seen != h.generation {append(&stale, id)}}
	for id in stale {track := h.tracks[id]; delete(track.samples); free(track); delete_key(&h.tracks, id); h.bytes -= h.capacity * size_of(Replication_Rewind_Sample)}
}
rewind_entity :: proc(
	h: ^Replication_Rewind_History,
	service: ^ReplicatorService,
	id: u32,
) -> (
	^Replication_Rewind_Track,
	^classes.Object,
) {
	if h == nil || !h.enabled || service == nil || service.mode != .Server {return nil, nil}
	entity := service.entity_by_id[id]; track := h.tracks[id]
	if entity == nil ||
	   track == nil ||
	   entity.object == nil ||
	   entity.object.destroyed ||
	   entity.object.unique_id != track.identity {return nil, nil}
	return track, entity.object
}
rewind_sample :: proc(
	h: ^Replication_Rewind_History,
	track: ^Replication_Rewind_Track,
	at: f64,
) -> (
	Replication_Rewind_Sample,
	bool,
) {
	if track == nil ||
	   track.count == 0 ||
	   !rewind_finite(at) ||
	   at > h.now ||
	   at < h.now - h.window {return {}, false}
	oldest := (track.head - track.count + len(track.samples)) % len(track.samples)
	left := track.samples[oldest]
	newest := track.samples[(track.head - 1 + len(track.samples)) % len(track.samples)]
	if at < left.time || at > newest.time {return {}, false}
	if at == left.time {return left, true}
	for i := 1; i < track.count; i += 1 {
		right := track.samples[(oldest + i) % len(track.samples)]
		if at <= right.time {
			if at == right.time {return right, true}
			if right.discontinuous {return {}, false}
			if right.time <= left.time {return right, true}
			alpha := (at - left.time) / (right.time - left.time)
			return {
					at,
					datatypes.CFrame_Lerp(left.frame, right.frame, alpha),
					datatypes.Vec3_Lerp(left.size, right.size, alpha),
					left.can_query,
					false,
				},
				true
		}
		left = right
	}
	return newest, true
}
Replication_Rewind_Frame :: proc(
	h: ^Replication_Rewind_History,
	service: ^ReplicatorService,
	object: ^classes.Object,
	at: f64,
) -> (
	datatypes.CFrame,
	bool,
) {
	if object == nil || object.destroyed || service == nil {return {}, false}
	id := service.entity_ids[object]; track, current := rewind_entity(h, service, id)
	if current != object {return {}, false}
	sample, ok := rewind_sample(h, track, at)
	return sample.frame, ok
}
rewind_box_hit :: proc(
	sample: Replication_Rewind_Sample,
	origin, direction: datatypes.Vector3,
) -> (
	f64,
	datatypes.Vector3,
	bool,
) {
	local_origin := datatypes.CFrame_PointToObjectSpace(sample.frame, origin)
	local_end := datatypes.CFrame_PointToObjectSpace(
		sample.frame,
		datatypes.Vec3_Add(origin, direction),
	)
	local_dir := datatypes.Vec3_Subtract(local_end, local_origin)
	p := [3]f64 {
		local_origin.x,
		local_origin.y,
		local_origin.z,
	}; d := [3]f64{local_dir.x, local_dir.y, local_dir.z}
	half := [3]f64 {
		math.abs(sample.size.x) * 0.5,
		math.abs(sample.size.y) * 0.5,
		math.abs(sample.size.z) * 0.5,
	}
	near, far := f64(0), f64(1); normal := datatypes.Vector3{}
	for axis in 0 ..< 3 {
		if math.abs(d[axis]) <
		   1e-12 {if p[axis] < -half[axis] || p[axis] > half[axis] {return 0, {}, false}; continue}
		first := (-half[axis] - p[axis]) / d[axis]; last := (half[axis] - p[axis]) / d[axis]
		sign := f64(-1)
		if first > last {first, last = last, first; sign = 1}
		if first > near {near = first; normal = {}; switch axis {case 0:
				normal.x = sign; case 1:
				normal.y = sign; case 2:
				normal.z = sign}}
		far = min(far, last)
		if near > far {return 0, {}, false}
	}
	transformed := datatypes.CFrame_Mul_Vector3(sample.frame, normal)
	transformed = datatypes.Vec3_Subtract(transformed, datatypes.CFrame_Position(sample.frame))
	return near, transformed, true
}
Replication_Rewind_Raycast :: proc(
	h: ^Replication_Rewind_History,
	service: ^ReplicatorService,
	origin, direction: datatypes.Vector3,
	at: f64,
) -> (
	Replication_Rewind_Hit,
	bool,
) {
	if h == nil ||
	   !h.enabled ||
	   service == nil ||
	   service.mode != .Server ||
	   !rewind_finite_vec(origin) ||
	   !rewind_finite_vec(direction) {return {}, false}
	length := datatypes.Vec3_Magnitude(direction)
	if length <= 0 || !rewind_finite(length) {return {}, false}
	nearest := f64(2); hit: Replication_Rewind_Hit
	for id, _ in h.tracks {
		track, object := rewind_entity(h, service, id); sample, ok := rewind_sample(h, track, at)
		if !ok || !sample.can_query {continue}
		fraction, normal, intersects := rewind_box_hit(sample, origin, direction)
		if intersects &&
		   fraction <
			   nearest {nearest = fraction; hit = {object, id, datatypes.Vec3_Add(origin, datatypes.Vec3_Multiply(direction, fraction)), normal, length * fraction}}
	}
	return hit, nearest <= 1
}
Replication_Rewind_Namecall :: proc(
	h: ^Replication_Rewind_History,
	service: ^ReplicatorService,
	L: ^vm.State,
	d: ^datatypes.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {case "ConfigureRewind",
	                    "GetHistoricalTransform",
	                    "RaycastRewind",
	                    "GetRewindStats",
	                    "GetRewindTime":
	case:
		return 0, false}
	if vm.ThreadIsParallel(
		L,
	) {return vm.RaiseError(L, "rewind history is unavailable in parallel Luau"), true}
	if service == nil ||
	   service.mode !=
		   .Server {return vm.RaiseError(L, "rewind queries require an active authoritative server"), true}
	switch method {
	case "ConfigureRewind":
		window := vm.ArgNumber(L, 2); rate := vm.ArgOptionalNumber(L, 3, 30)
		count := vm.ArgOptionalNumber(L, 4, 1024)
		if !rewind_finite(count) ||
		   count < 1 ||
		   count > REWIND_MAX_ENTITIES ||
		   math.floor(count) !=
			   count {return vm.RaiseError(L, "invalid rewind entity limit"), true}
		if !Replication_Rewind_Configure(
			h,
			window,
			rate,
			int(count),
		) {return vm.RaiseError(L, "rewind configuration exceeds time, sample or memory bounds"), true}
		vm.PushBoolean(L, true)
		return 1, true
	case "GetHistoricalTransform":
		object := collection_object_from_argument(L, 2)
		frame, ok := Replication_Rewind_Frame(h, service, object, vm.ArgNumber(L, 3))
		if ok {datatypes.Push_CFrame(L, d, frame)} else {vm.PushNil(L)}
		return 1, true
	case "RaycastRewind":
		hit, ok := Replication_Rewind_Raycast(
			h,
			service,
			datatypes.Arg_Vector3(L, 2),
			datatypes.Arg_Vector3(L, 3),
			vm.ArgNumber(L, 4),
		)
		if !ok {vm.PushNil(L); return 1, true}
		vm.NewTable(L, 0, 5)
		classes.Push_Object(L, hit.object)
		vm.SetField(L, -2, "Instance")
		datatypes.Push_Vector3(L, hit.position)
		vm.SetField(L, -2, "Position")
		datatypes.Push_Vector3(L, hit.normal)
		vm.SetField(L, -2, "Normal")
		vm.PushNumber(L, hit.distance)
		vm.SetField(L, -2, "Distance")
		return 1, true
	case "GetRewindTime":
		vm.PushNumber(L, f64(service.clock)); return 1, true
	case "GetRewindStats":
		vm.NewTable(L, 0, 5)
		vm.PushNumber(L, f64(h.bytes)); vm.SetField(L, -2, "Bytes")
		vm.PushNumber(L, f64(len(h.tracks))); vm.SetField(L, -2, "Entities")
		vm.PushNumber(L, f64(h.captures)); vm.SetField(L, -2, "Captures")
		vm.PushNumber(L, f64(h.dropped)); vm.SetField(L, -2, "Dropped")
		return 1, true
	}
	return 0, false
}
