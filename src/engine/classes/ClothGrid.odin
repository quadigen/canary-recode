package classes

import enums "../enum"
import "core:math"
import "core:math/linalg"

Cloth_Link_Kind :: enum {Stretch, Shear, Bend, Fold}

Cloth_Link :: struct {
	a, b: int,
	length, lambda, compliance: f32,
	kind: Cloth_Link_Kind,
}

Cloth_Vertex_Count :: proc(cloth: ^Cloth) -> int {
	return (cloth.segments_x + 1) * (cloth.segments_y + 1)
}

cloth_free_grid :: proc(cloth: ^Cloth) {
	delete(cloth.particles)
	delete(cloth.rest)
	delete(cloth.pin_attachments)
	delete(cloth.pinned)
	delete(cloth.pin_offsets)
	delete(cloth.pin_weights)
	delete(cloth.active_weights)
	delete(cloth.pin_targets)
	delete(cloth.pin_starts)
	delete(cloth.previous)
	delete(cloth.pin_links)
	delete(cloth.links)
	delete(cloth.self_heads)
	delete(cloth.self_next)
	delete(cloth.self_cells)
	delete(cloth.self_positions)
	delete(cloth.snapshot_start)
	delete(cloth.snapshot_target)
}

Cloth_Ensure_Grid :: proc(cloth: ^Cloth) {
	if cloth.grid == ([2]int{cloth.segments_x, cloth.segments_y}) {return}
	old_grid := cloth.grid
	old_pins, old_offsets, old_weights := cloth.pin_attachments, cloth.pin_offsets, cloth.pin_weights
	cloth.pin_attachments, cloth.pin_offsets, cloth.pin_weights = nil, nil, nil
	cloth_free_grid(cloth)
	defer delete(old_pins)
	defer delete(old_offsets)
	defer delete(old_weights)

	n := Cloth_Vertex_Count(cloth)
	cloth.grid = {cloth.segments_x, cloth.segments_y}
	cloth.particles = make([]Cloth_Particle, n)
	cloth.rest = make([][3]f32, n)
	cloth.pin_attachments = make([]^Object, n)
	cloth.pinned = make([]bool, n)
	cloth.pin_offsets = make([][3]f32, n)
	cloth.pin_weights = make([]f32, n)
	cloth.active_weights = make([]f32, n)
	cloth.pin_targets = make([][3]f32, n)
	cloth.pin_starts = make([][3]f32, n)
	cloth.previous = make([][3]f32, n)
	cloth.pin_links = make([]f32, n)
	cloth.links = make([dynamic]Cloth_Link, 0, n * 6)
	cloth.self_heads = make([]int, n * 2 + 1)
	cloth.self_next = make([]int, n)
	cloth.self_cells = make([][3]int, n)
	cloth.self_positions = make([][3]f32, n)
	cloth.snapshot_start = make([][3]f32, n)
	cloth.snapshot_target = make([][3]f32, n)
	for &weight in cloth.pin_weights {weight = 1}
	for pin, i in old_pins {
		if pin == nil {continue}
		u := f32(i % (old_grid.x + 1)) / f32(old_grid.x)
		v := f32(i / (old_grid.x + 1)) / f32(old_grid.y)
		x := int(math.floor(u * f32(cloth.segments_x) + 0.5))
		y := int(math.floor(v * f32(cloth.segments_y) + 0.5))
		j := y * (cloth.segments_x + 1) + x
		cloth.pin_attachments[j], cloth.pin_offsets[j], cloth.pin_weights[j] = pin, old_offsets[i], old_weights[i]
	}
	cloth.initialized = false
	cloth.snapshot_received = false
	cloth.revision += 1
}

Cloth_Set_Type :: proc(cloth: ^Cloth, kind: enums.ClothType) {
	if cloth.cloth_type == kind {return}
	cloth.cloth_type = kind
	cloth.initialized = false
	if kind == .Curtain && cloth.fold_count == 0 && cloth.fold_depth == 0 {
		cloth.fold_count, cloth.fold_depth, cloth.gather_ratio = 6, 0.25, 0.65
	}
}

Cloth_Gathered_Width :: proc(cloth: ^Cloth) -> f32 {
	if cloth.cloth_type == .Curtain {
		ratio := cloth.gather_ratio if cloth.gather_ratio > 0 else 1
		return max(CLOTH_MIN_SPAN, cloth.size.X * ratio)
	}
	// Older projects stored the fraction removed from the flat width.
	return cloth.size.X * max(1 - cloth.gather_ratio, 0.1)
}

Cloth_Sag :: proc(cloth: ^Cloth, u: f32) -> f32 {
	return cloth.size.X * 0.2 * 4 * u * (1 - u) if cloth.cloth_type == .Hammock else 0
}

cloth_add_link :: proc(cloth: ^Cloth, a, b: int, kind: Cloth_Link_Kind) {
	append(&cloth.links, Cloth_Link{a = a, b = b, kind = kind})
}

Cloth_Build_Links :: proc(cloth: ^Cloth) {
	if len(cloth.links) == 0 {
		nx, ny := cloth.segments_x, cloth.segments_y
		stride := nx + 1
		for y in 0..=ny {
			for x in 0..=nx {
				i := y * stride + x
				if x < nx {cloth_add_link(cloth, i, i + 1, .Stretch)}
				if y < ny {cloth_add_link(cloth, i, i + stride, .Stretch)}
				if x < nx && y < ny {
					cloth_add_link(cloth, i, i + stride + 1, .Shear)
					cloth_add_link(cloth, i + 1, i + stride, .Shear)
				}
				if x + 2 <= nx {cloth_add_link(cloth, i, i + 2, .Fold)}
				if y + 2 <= ny {cloth_add_link(cloth, i, i + stride * 2, .Bend)}
			}
		}
	}
	for &link in cloth.links {link.length = linalg.length(cloth.rest[link.b] - cloth.rest[link.a])}
}
