package classes

import "core:strings"

DEFAULT_ICON_PACK :: "Default"

Icon_Pack :: struct {
	name:  string,
	icons: map[string]string,
}


icon_packs: map[string]Icon_Pack
active_icon_pack: string
icon_pack_revision: u64 = 1

IconPack_Revision :: proc() -> u64 {return icon_pack_revision}

IconPack_Active :: proc() -> string {
	return DEFAULT_ICON_PACK if active_icon_pack == "" else active_icon_pack
}

IconPack_Key :: proc(name: string) -> string {
	if strings.has_prefix(name, BUILTIN_ICON_PREFIX) ||
	   strings.has_prefix(name, BUILTIN_GLOBAL_ICON_PREFIX) {
		return name
	}
	if name == "" || strings.contains(name, "/") {return ""}
	return strings.concatenate({BUILTIN_ICON_PREFIX, name}, context.temp_allocator)
}

IconPack_Free_Entries :: proc(icons: map[string]string) {
	for key, data in icons {
		delete(key)
		delete(data)
	}
	delete(icons)
}

icon_pack_changed :: proc() {
	icon_pack_revision += 1
	Gui_Render_Mark_Dirty()
}


IconPack_Register :: proc(name: string, icons: map[string]string) -> bool {
	if name == "" || name == DEFAULT_ICON_PACK || len(icons) == 0 {return false}
	existing, found := icon_packs[name]
	owned_name := existing.name if found else strings.clone(name)
	if found {IconPack_Free_Entries(existing.icons)}
	icon_packs[owned_name] = {owned_name, icons}
	if active_icon_pack == owned_name {icon_pack_changed()}
	return true
}

IconPack_Set :: proc(name: string) -> bool {
	if name == IconPack_Active() {return true}
	if name == DEFAULT_ICON_PACK {
		active_icon_pack = ""
	} else {
		pack, found := icon_packs[name]
		if !found {return false}
		active_icon_pack = pack.name
	}
	icon_pack_changed()
	return true
}

IconPack_Remove :: proc(name: string) -> bool {
	pack, found := icon_packs[name]
	if !found {return false}
	if active_icon_pack == name {_ = IconPack_Set(DEFAULT_ICON_PACK)}
	delete_key(&icon_packs, pack.name)
	IconPack_Free_Entries(pack.icons)
	delete(pack.name)
	return true
}

IconPack_Resolve :: proc(path: string) -> ([]u8, bool) {
	if active_icon_pack != "" {
		pack, found := icon_packs[active_icon_pack]
		if found {
			data, has_icon := pack.icons[path]
			if has_icon && len(data) > 0 {return transmute([]u8)data, true}
		}
	}
	return nil, false
}

IconPack_Is_URI :: proc(path: string) -> bool {
	return(
		strings.has_prefix(path, BUILTIN_ICON_PREFIX) ||
		strings.has_prefix(path, BUILTIN_GLOBAL_ICON_PREFIX) \
	)
}
