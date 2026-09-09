package datatypes

import "core:fmt"
import "core:time"

UniqueId :: struct {
	Random: i64,
	Time:   u32,
	Index:  u32,
}

unique_id_index: u32

UniqueId_New :: proc() -> UniqueId {
	unique_id_index += 1
	now := time.now()
	nanoseconds := time.to_unix_nanoseconds(now)
	random := nanoseconds ~ (i64(unique_id_index) * 0x5851f42d4c957f2d)
	return UniqueId{
		Random = random,
		Time   = u32(time.to_unix_seconds(now)),
		Index  = unique_id_index,
	}
}

UniqueId_ToString :: proc(value: UniqueId) -> string {
	return fmt.tprintf("%016x%08x%08x", cast(u64)value.Random, value.Time, value.Index)
}
