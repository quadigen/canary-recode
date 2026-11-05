#+build windows
package services

import "core:os"
import win32 "core:sys/windows"

foreign import kernel32 "system:kernel32.lib"

foreign kernel32 {
	@(link_name = "BeginUpdateResourceW")
	export_icon_begin :: proc "system" (path: win32.LPCWSTR, delete_existing: win32.BOOL) -> win32.HANDLE ---
	@(link_name = "UpdateResourceW")
	export_icon_update :: proc "system" (update: win32.HANDLE, kind, name: rawptr, language: u16, data: rawptr, size: u32) -> win32.BOOL ---
	@(link_name = "EndUpdateResourceW")
	export_icon_end :: proc "system" (update: win32.HANDLE, discard: win32.BOOL) -> win32.BOOL ---
}

export_embed_windows_icon :: proc(path, icon_path: string) -> string {
	icon, err := os.read_entire_file_from_path(icon_path, context.allocator)
	if err != nil {
		return "Could not read the icon file"
	}
	defer delete(icon)
	if len(icon) < 6 || payload_read_le_u16(icon, 0) != 0 || payload_read_le_u16(icon, 2) != 1 {
		return "Executable icon must be a Windows .ico file"
	}
	count := int(payload_read_le_u16(icon, 4))
	directory_size := 6 + 16 * count
	if count == 0 || count > 256 || directory_size > len(icon) {
		return "Invalid .ico image directory"
	}
	for i in 0 ..< count {
		entry := 6 + 16 * i
		size := i64(payload_read_le_u32(icon, entry + 8))
		offset := i64(payload_read_le_u32(icon, entry + 12))
		if size == 0 || offset < i64(directory_size) || offset + size > i64(len(icon)) {
			return "Invalid .ico image data"
		}
	}

	wide_path := win32.utf8_to_utf16(path)
	if len(wide_path) == 0 {
		return "Could not encode the executable path for Windows"
	}
	update := export_icon_begin(cast(win32.LPCWSTR)raw_data(wide_path), false)
	if update == nil {
		return "Could not open the executable's Windows resources"
	}
	discard := true
	defer if discard {_ = export_icon_end(update, true)}

	group := make([]u8, 6 + 14 * count, context.temp_allocator)
	copy(group[:6], icon[:6])
	for i in 0 ..< count {
		entry := 6 + 16 * i
		group_entry := 6 + 14 * i
		id := u16(1024 + i)
		copy(group[group_entry:group_entry + 12], icon[entry:entry + 12])
		payload_write_le_u16(group, group_entry + 12, id)

		size := payload_read_le_u32(icon, entry + 8)
		offset := int(payload_read_le_u32(icon, entry + 12))
		if !export_icon_update(
			update,
			rawptr(uintptr(3)),
			rawptr(uintptr(id)),
			0,
			&icon[offset],
			size,
		) {
			return "Could not write the executable's icon image"
		}
	}
	if !export_icon_update(
		update,
		rawptr(uintptr(14)),
		rawptr(uintptr(1)),
		0,
		raw_data(group),
		u32(len(group)),
	) {
		return "Could not write the executable's icon group"
	}
	discard = false
	if !export_icon_end(update, false) {
		return "Could not save the executable's icon"
	}
	return ""
}
