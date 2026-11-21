package gpucompute

import "core:math"

BVH_Node :: struct {
	minimum: [3]f32,
	first:   u32,
	maximum: [3]f32,
	count:   u32,
}
#assert(size_of(BVH_Node) == 32)
BVH_Primitive :: struct {
	minimum, maximum, centroid: [3]f32,
}
BVH_MAX_TRIANGLES :: 500_000

bvh_read_u32 :: proc(data: []u8, offset: int) -> u32 {
	return(
		u32(data[offset]) |
		u32(data[offset + 1]) << 8 |
		u32(data[offset + 2]) << 16 |
		u32(data[offset + 3]) << 24 \
	)
}

bvh_build :: proc(
	vertices, indices: []u8,
	leaf_size: int,
) -> (
	nodes: [dynamic]BVH_Node,
	order: []u32,
	err: string,
) {
	if len(vertices) < 96 ||
	   len(vertices) % 32 != 0 ||
	   len(indices) < 12 ||
	   len(indices) % 12 != 0 ||
	   len(indices) / 12 > BVH_MAX_TRIANGLES ||
	   leaf_size < 1 ||
	   leaf_size > 64 {
		return nil, nil, "invalid mesh or BVH limits"
	}
	vertex_count := len(vertices) / 32
	tri_count := len(indices) / 12
	primitives := make([]BVH_Primitive, tri_count)
	defer delete(primitives)
	order = make([]u32, tri_count)
	nodes = make([dynamic]BVH_Node, 1, tri_count * 2 - 1)
	defer {
		if err != "" {delete(nodes); delete(order); nodes = nil; order = nil}
	}
	for &p, i in primitives {
		order[i] = u32(i)
		p.minimum = {max(f32), max(f32), max(f32)}
		p.maximum = {-max(f32), -max(f32), -max(f32)}
		for k in 0 ..< 3 {
			index := int(bvh_read_u32(indices, (i * 3 + k) * 4))
			if index >=
			   vertex_count {return nodes, order, "mesh has an out-of-range triangle index"}
			for axis in 0 ..< 3 {
				value := transmute(f32)bvh_read_u32(vertices, index * 32 + axis * 4)
				if math.is_nan(value) ||
				   math.is_inf(value) {return nodes, order, "mesh contains nonfinite positions"}
				p.minimum[axis] = min(p.minimum[axis], value)
				p.maximum[axis] = max(p.maximum[axis], value)
			}
		}
		for axis in 0 ..< 3 {p.centroid[axis] = p.minimum[axis] * 0.5 + p.maximum[axis] * 0.5}
	}
	bvh_split(&nodes, order, primitives, 0, 0, tri_count, leaf_size)
	return nodes, order, ""
}

bvh_split :: proc(
	nodes: ^[dynamic]BVH_Node,
	order: []u32,
	primitives: []BVH_Primitive,
	node_index, first, count, leaf_size: int,
) {
	minimum := [3]f32{max(f32), max(f32), max(f32)}
	maximum := [3]f32{-max(f32), -max(f32), -max(f32)}
	center_min, center_max := minimum, maximum
	for id in order[first:first + count] {
		p := primitives[id]
		for k in 0 ..< 3 {
			minimum[k] = min(minimum[k], p.minimum[k])
			maximum[k] = max(maximum[k], p.maximum[k])
			center_min[k] = min(center_min[k], p.centroid[k])
			center_max[k] = max(center_max[k], p.centroid[k])
		}
	}
	node := BVH_Node {
		minimum = minimum,
		maximum = maximum,
		first   = u32(first),
		count   = u32(count),
	}
	if count <= leaf_size {
		nodes^[node_index] = node
		return
	}
	axis := 0
	for k in 1 ..< 3 {
		if f64(center_max[k]) - f64(center_min[k]) >
		   f64(center_max[axis]) - f64(center_min[axis]) {axis = k}
	}
	split := center_min[axis] * 0.5 + center_max[axis] * 0.5
	left, right := first, first + count
	for left < right {
		if primitives[order[left]].centroid[axis] < split {left += 1} else {
			right -= 1
			order[left], order[right] = order[right], order[left]
		}
	}
	left_count := left - first

	if left_count < max(1, count / 8) ||
	   count - left_count < max(1, count / 8) {left_count = count / 2}
	child := len(nodes^)
	append(nodes, BVH_Node{}, BVH_Node{})
	node.first, node.count = u32(child), 0
	nodes^[node_index] = node
	bvh_split(nodes, order, primitives, child, first, left_count, leaf_size)
	bvh_split(
		nodes,
		order,
		primitives,
		child + 1,
		first + left_count,
		count - left_count,
		leaf_size,
	)
}
