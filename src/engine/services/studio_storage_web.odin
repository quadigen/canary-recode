#+build js
package services

studio_read_settings :: proc() -> ([]u8, bool) {
	size := host_storage_get("kinemium.web.studio.settings", nil, 0)
	if size <= 0 {return nil, false}
	data := make([]u8, int(size))
	got := host_storage_get("kinemium.web.studio.settings", raw_data(data), size)
	if got != size {delete(data); return nil, false}
	return data, true
}

studio_write_settings :: proc(data: []u8) {
	_ = host_storage_set("kinemium.web.studio.settings", raw_data(data), i32(len(data)))
}
