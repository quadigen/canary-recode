package main

import services "../src/engine/services"
import "core:fmt"

main :: proc() {
	values := [18]f64{10, 5, 20, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0}
	bytes: [dynamic]u8
	defer delete(bytes)
	services.replication_put_compact_f64s(&bytes, values[:])
	assert(len(bytes) == 17, "compact physics should need only 17 bytes for this sample")
	decoded: [18]f64
	reader := services.Replication_Reader {
		data  = bytes[:],
		valid = true,
	}
	services.replication_read_compact_f64s(&reader, decoded[:])
	assert(reader.valid && reader.offset == len(bytes) && values == decoded)
	for end in 0 ..< len(bytes) {
		truncated := services.Replication_Reader {
			data  = bytes[:end],
			valid = true,
		}
		services.replication_read_compact_f64s(&truncated, decoded[:])
		assert(!truncated.valid, "truncated compact payload was accepted")
	}
	edge := [8]f64 {
		0,
		1,
		-1,
		1.25,
		1.0 / 3.0,
		transmute(f64)u64(0x8000000000000000),
		transmute(f64)u64(0x7ff0000000000000),
		transmute(f64)u64(0x7ff8000000001234),
	}
	clear(&bytes)
	services.replication_put_compact_f64s(&bytes, edge[:])
	result: [8]f64
	reader = {
		data  = bytes[:],
		valid = true,
	}
	services.replication_read_compact_f64s(&reader, result[:])
	assert(reader.valid && reader.offset == len(bytes))
	for value, i in edge {assert(transmute(u64)value == transmute(u64)result[i])}
	fmt.println("REPLICATION_COMPACT_CODEC_SMOKE_PASSED")
}
