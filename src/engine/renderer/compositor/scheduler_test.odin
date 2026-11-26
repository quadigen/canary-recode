#+build !js
package compositor

import "core:testing"
import vk "vendor:vulkan"

@(test)
offscreen_ring_is_bounded_and_retires_in_order :: proc(t: ^testing.T) {
	s: Offscreen_Scheduler
	a, a_ok := claim_offscreen(&s)
	b, b_ok := claim_offscreen(&s)
	c, c_ok := claim_offscreen(&s)
	_, full := claim_offscreen(&s)
	testing.expect(t, a_ok && b_ok && c_ok && !full)
	testing.expect(t, a.index != b.index && b.index != c.index && a.index != c.index)
	testing.expect(t, !advance_offscreen(&s, a, .Rendering, .Copying))
	testing.expect(t, advance_offscreen(&s, b, .Rendering, .Ready))
	testing.expect(t, advance_offscreen(&s, a, .Rendering, .Ready))
	oldest, ok := oldest_ready(&s)
	testing.expect(t, ok && oldest == a)
	testing.expect(t, advance_offscreen(&s, a, .Ready, .Copying))
	testing.expect(t, !advance_offscreen(&s, a, .Ready, .Copying))
	testing.expect(t, advance_offscreen(&s, a, .Copying, .Free))
	d, d_ok := claim_offscreen(&s)
	testing.expect(t, d_ok && d.index == a.index && d.generation != a.generation)
	testing.expect(t, !advance_offscreen(&s, a, .Rendering, .Ready))
}

@(test)
transition_scopes_preserve_color_and_snapshot_dependencies :: proc(t: ^testing.T) {
	src, dst, read, write := transition_scope(.UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL)
	testing.expect(
		t,
		src == {.TOP_OF_PIPE} &&
		dst == {.COLOR_ATTACHMENT_OUTPUT} &&
		read == {} &&
		write == {.COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE},
	)
	src, dst, read, write = transition_scope(.COLOR_ATTACHMENT_OPTIMAL, .PRESENT_SRC_KHR)
	testing.expect(
		t,
		src == {.COLOR_ATTACHMENT_OUTPUT, .TRANSFER} &&
		dst == {.BOTTOM_OF_PIPE} &&
		read == {.COLOR_ATTACHMENT_WRITE, .TRANSFER_READ} &&
		write == {},
	)
	properties: vk.PhysicalDeviceMemoryProperties
	properties.memoryTypeCount = 2
	properties.memoryTypes[1].propertyFlags = {.DEVICE_LOCAL}
	index, ok := memory_type(&properties, 3, {.DEVICE_LOCAL})
	testing.expect(t, ok && index == 1)
	_, ok = memory_type(&properties, 1, {.DEVICE_LOCAL})
	testing.expect(t, !ok)
}

@(test)
ready_slot_selection_prefers_completed_work :: proc(t: ^testing.T) {
	following: u32
	testing.expect(t, select_ready_callback(0, 3, 4, &following) == 2)
	testing.expect(t, following == 0)
	testing.expect(t, select_ready_callback(2, 3, 3, &following) == 0)
	testing.expect(t, following == 1)
	testing.expect(t, select_ready_callback(1, 3, 0, &following) == 1)
	testing.expect(t, following == 2)
	testing.expect(t, select_ready_callback(0, 0, 0, &following) == max(u32))
	testing.expect(t, select_ready_callback(0, 33, 0, &following) == max(u32))
}
