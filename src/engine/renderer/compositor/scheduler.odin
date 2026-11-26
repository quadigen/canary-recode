package compositor

import "base:runtime"

next_slot_callback :: proc "c" (next, count: u32, following: ^u32) -> u32 {
	context = runtime.default_context()
	if count == 0 || following == nil {return max(u32)}
	selected := next % count
	following^ = (selected + 1) % count
	return selected
}

Offscreen_Phase :: enum u8 {
	Free,
	Rendering,
	Ready,
	Copying,
}
Offscreen_Token :: struct {
	index:      u32,
	generation: u64,
}
Offscreen_Slot :: struct {
	phase:              Offscreen_Phase,
	generation, serial: u64,
}
Offscreen_Scheduler :: struct {
	slots:  [3]Offscreen_Slot,
	next:   u32,
	serial: u64,
}

claim_offscreen :: proc(s: ^Offscreen_Scheduler) -> (Offscreen_Token, bool) {
	if s == nil {return {}, false}
	for step in 0 ..< len(s.slots) {
		index := (s.next + u32(step)) % u32(len(s.slots))
		slot := &s.slots[index]
		if slot.phase != .Free {continue}
		s.serial += 1
		slot.generation += 1
		slot.serial = s.serial
		slot.phase = .Rendering
		s.next = (index + 1) % u32(len(s.slots))
		return {index, slot.generation}, true
	}
	return {}, false
}

advance_offscreen :: proc(
	s: ^Offscreen_Scheduler,
	token: Offscreen_Token,
	from, to: Offscreen_Phase,
) -> bool {
	if s == nil || token.index >= u32(len(s.slots)) {return false}
	slot := &s.slots[token.index]
	if slot.generation != token.generation || slot.phase != from {return false}
	switch from {
	case .Free:
		return false
	case .Rendering:
		if to != .Ready && to != .Free {return false}
	case .Ready:
		if to != .Copying {return false}
	case .Copying:
		if to != .Free {return false}
	}
	slot.phase = to
	return true
}

oldest_ready :: proc(s: ^Offscreen_Scheduler) -> (Offscreen_Token, bool) {
	if s == nil {return {}, false}
	index := max(u32)
	serial := max(u64)
	for slot, i in s.slots {
		if slot.phase == .Ready && slot.serial < serial {
			serial = slot.serial
			index = u32(i)
		}
	}
	if index == max(u32) {return {}, false}
	return {index, s.slots[index].generation}, true
}

select_ready_callback :: proc "c" (next, count, ready_mask: u32, following: ^u32) -> u32 {
	context = runtime.default_context()
	if count == 0 || count > 32 || following == nil {return max(u32)}
	selected := next % count
	for step in 0 ..< count {
		index := (selected + step) % count
		if ready_mask & (u32(1) << index) != 0 {
			following^ = (index + 1) % count
			return index
		}
	}
	following^ = (selected + 1) % count
	return selected
}
