package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:encoding/json"
import "core:strings"

LocalizationTable_Class := Class_Info {
	name   = "LocalizationTable",
	parent = &Instance_Class,
}

Localization_Entry :: struct {
	Key, Source, Context, Example: string,
	Values:                        map[string]string,
}

LocalizationTable :: struct {
	using object:  Object,
	source_locale: string,
	entries:       [dynamic]Localization_Entry,
}

localization_table_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	table := new(LocalizationTable)
	table.object = Object_Init(&LocalizationTable_Class, "LocalizationTable")
	table.source_locale = strings.clone("en-us")
	return &table.object
}

localization_entry_free :: proc(entry: ^Localization_Entry) {
	delete(entry.Key)
	delete(entry.Source)
	delete(entry.Context)
	delete(entry.Example)
	for key, value in entry.Values {
		delete(key)
		delete(value)
	}
	delete(entry.Values)
	entry^ = {}
}

localization_entries_free :: proc(entries: ^[dynamic]Localization_Entry) {
	for &entry in entries^ {localization_entry_free(&entry)}
	delete(entries^)
	entries^ = nil
}

localization_table_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	table := cast(^LocalizationTable)object
	localization_entries_free(&table.entries)
	delete(table.source_locale)
	Object_Destroy(object)
	free(table)
}

localization_entry_new :: proc(key, source, path: string) -> Localization_Entry {
	return {
		Key = strings.clone(key),
		Source = strings.clone(source),
		Context = strings.clone(path),
		Values = make(map[string]string),
	}
}

localization_find :: proc(
	entries: []Localization_Entry,
	key, source, path: string,
	except := -1,
) -> int {
	for &entry, i in entries {
		if i == except {continue}
		if key != "" {
			if entry.Key == key {return i}
		} else if entry.Key == "" && entry.Source == source && entry.Context == path {return i}
	}
	return -1
}

localization_remove_value :: proc(entry: ^Localization_Entry, locale: string) -> bool {
	for key, value in entry.Values {
		if key != locale {continue}
		delete_key(&entry.Values, key)
		delete(key)
		delete(value)
		return true
	}
	return false
}

localization_store_value :: proc(entry: ^Localization_Entry, locale, value: string) {
	_ = localization_remove_value(entry, locale)
	if value != "" {entry.Values[strings.clone(locale)] = strings.clone(value)}
}

localization_table_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^LocalizationTable)source, cast(^LocalizationTable)destination
	delete(dst.source_locale)
	dst.source_locale = strings.clone(src.source_locale)
	localization_entries_free(&dst.entries)
	for &entry in src.entries {
		copy := localization_entry_new(entry.Key, entry.Source, entry.Context)
		copy.Example = strings.clone(entry.Example)
		for key, value in entry.Values {localization_store_value(&copy, key, value)}
		append(&dst.entries, copy)
	}
}

localization_table_changed :: proc(table: ^LocalizationTable, property := "SerializedEntries") {
	Invalidate_Localized_Text(table.signal_registry)
	Object_Fire_Property_Changed(&table.object, property)
}

localization_read_lua_values :: proc(
	L: ^vm.State,
	index: int,
	entry: ^Localization_Entry,
) -> bool {
	if !vm.IsTable(L, index) {return false}
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	vm.PushNil(L)
	for vm.Next(L, index) {
		locale, locale_ok := vm.ToString(L, -2)
		value, value_ok := vm.ToString(L, -1)
		if !locale_ok ||
		   !value_ok ||
		   locale == "" ||
		   strings.contains(locale, "\x00") {return false}
		normalized := strings.to_lower(locale, context.allocator)
		if normalized in entry.Values {delete(normalized); return false}
		localization_store_value(entry, normalized, value)
		delete(normalized)
		vm.Pop(L)
	}
	return true
}

localization_read_lua_entry :: proc(L: ^vm.State, index: int, entry: ^Localization_Entry) -> bool {
	if !vm.IsTable(L, index) {return false}
	entry^ = localization_entry_new("", "", "")
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)

	vm.PushNil(L)
	for vm.Next(L, index) {
		field, field_ok := vm.ToString(L, -2)
		if field_ok {
			switch field {
			case "Key", "Source", "Context", "Example":
				value, ok := vm.ToString(L, -1)
				if !ok {return false}
				switch field {
				case "Key":
					delete(entry.Key); entry.Key = strings.clone(value)
				case "Source":
					delete(entry.Source); entry.Source = strings.clone(value)
				case "Context":
					delete(entry.Context); entry.Context = strings.clone(value)
				case "Example":
					delete(entry.Example); entry.Example = strings.clone(value)
				}
			case "Values":
				if !localization_read_lua_values(L, vm.StackTop(L), entry) {return false}
			}
		}
		vm.Pop(L)
	}
	return entry.Key != "" || entry.Source != ""
}

localization_read_entries :: proc(
	L: ^vm.State,
	index: int,
	entries: ^[dynamic]Localization_Entry,
) -> bool {
	if !vm.IsTable(L, index) {return false}
	count, top := vm.RawLen(L, index), vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	for i in 1 ..= count {
		_ = vm.RawGetIndex(L, index, i)
		entry: Localization_Entry
		if !localization_read_lua_entry(L, vm.StackTop(L), &entry) {
			localization_entry_free(&entry)
			return false
		}
		if localization_find(entries^[:], entry.Key, entry.Source, entry.Context) >= 0 {
			localization_entry_free(&entry)
			return false
		}
		append(entries, entry)
		vm.Pop(L)
	}

	actual := 0
	vm.PushNil(L)
	for vm.Next(L, index) {
		actual += 1
		n, ok := vm.ToNumber(L, -2)
		if vm.TypeOf(L, -2) != .Number ||
		   !ok ||
		   n < 1 ||
		   n > f64(count) ||
		   n != f64(int(n)) {return false}
		vm.Pop(L)
	}
	return actual == count
}

localization_push_entries :: proc(L: ^vm.State, entries: []Localization_Entry) {
	vm.NewTable(L, len(entries))
	for &entry, i in entries {
		vm.NewTable(L, 0, 5)
		vm.PushString(L, entry.Key)
		vm.SetField(L, -2, "Key")
		vm.PushString(L, entry.Source)
		vm.SetField(L, -2, "Source")
		vm.PushString(L, entry.Context)
		vm.SetField(L, -2, "Context")
		vm.PushString(L, entry.Example)
		vm.SetField(L, -2, "Example")
		vm.NewTable(L, 0, len(entry.Values))
		for locale, value in entry.Values {
			vm.PushString(L, value)
			vm.SetField(L, -2, locale)
		}
		vm.SetField(L, -2, "Values")
		vm.SetArrayValue(L, -2, i + 1)
	}
}

localization_parse_json_entry :: proc(value: json.Value, entry: ^Localization_Entry) -> bool {
	obj, ok := value.(json.Object)
	if !ok {return false}
	fields: [4]string
	names := [?]string{"Key", "Source", "Context", "Example"}
	for field, i in names {
		if v, found := obj[field]; found {
			s, valid := v.(json.String)
			if !valid {return false}
			fields[i] = string(s)
		}
	}
	if fields[0] == "" && fields[1] == "" {return false}
	entry^ = localization_entry_new(fields[0], fields[1], fields[2])
	entry.Example = strings.clone(fields[3])
	if v, found := obj["Values"]; found {
		values, valid := v.(json.Object)
		if !valid {return false}
		for locale, raw in values {
			text, text_ok := raw.(json.String)
			if !text_ok || locale == "" || strings.contains(locale, "\x00") {return false}
			normalized := strings.to_lower(locale, context.allocator)
			if normalized in entry.Values {delete(normalized); return false}
			localization_store_value(entry, normalized, string(text))
			delete(normalized)
		}
	}
	return true
}

localization_set_serialized :: proc(table: ^LocalizationTable, source: string) -> bool {
	value, err := json.parse_string(source, allocator = context.allocator)
	if err != nil {return false}
	defer json.destroy_value(value)
	array, ok := value.(json.Array)
	if !ok {return false}
	entries: [dynamic]Localization_Entry
	defer localization_entries_free(&entries)
	for value in array {
		entry: Localization_Entry
		if !localization_parse_json_entry(value, &entry) {
			localization_entry_free(&entry)
			return false
		}
		if localization_find(entries[:], entry.Key, entry.Source, entry.Context) >= 0 {
			localization_entry_free(&entry)
			return false
		}
		append(&entries, entry)
	}
	localization_entries_free(&table.entries)
	table.entries = entries
	entries = nil

	Invalidate_Localized_Text(table.signal_registry)
	return true
}

localization_table_get :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	table := cast(^LocalizationTable)object
	switch key {
	case "SourceLocaleId":
		vm.PushString(L, table.source_locale)
	case "SerializedEntries":
		if len(table.entries) == 0 {vm.PushString(L, "[]"); return true}
		bytes, err := json.marshal(table.entries[:], {spec = .JSON}, context.allocator)
		defer delete(bytes)
		if err != nil {return false}
		vm.PushString(L, string(bytes))
	case:
		return false
	}
	return true
}

localization_table_set :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	table := cast(^LocalizationTable)object
	switch key {
	case "SourceLocaleId":
		locale := vm.ArgString(L, index)
		if locale == "" || strings.contains(locale, "\x00") {return false}
		normalized := strings.to_lower(locale, context.allocator)
		delete(table.source_locale)
		table.source_locale = normalized

		Invalidate_Localized_Text(table.signal_registry)
		return true
	case "SerializedEntries":
		return localization_set_serialized(table, vm.ArgString(L, index))
	}
	return false
}

localization_table_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	table := cast(^LocalizationTable)object
	switch method {
	case "GetEntries":
		localization_push_entries(L, table.entries[:])
		return 1, true
	case "SetEntries":
		entries: [dynamic]Localization_Entry
		if !localization_read_entries(L, 2, &entries) {
			localization_entries_free(&entries)
			return vm.RaiseError(L, "invalid or duplicate localization entries"), true
		}
		localization_entries_free(&table.entries)
		table.entries = entries
		localization_table_changed(table)
		return 0, true
	case "RemoveTargetLocale":
		raw := vm.ArgString(L, 2)
		if raw == "" {return vm.RaiseError(L, "locale must not be empty"), true}
		locale := strings.to_lower(raw, context.allocator)
		changed := false
		for &entry in table.entries {
			if localization_remove_value(&entry, locale) {changed = true}
		}
		delete(locale)
		if changed {localization_table_changed(table)}
		return 0, true
	case "RemoveEntry",
	     "RemoveEntryValue",
	     "SetEntryContext",
	     "SetEntryExample",
	     "SetEntryKey",
	     "SetEntrySource",
	     "SetEntryValue":
		key, source, path := vm.ArgString(L, 2), vm.ArgString(L, 3), vm.ArgString(L, 4)
		i := localization_find(table.entries[:], key, source, path)
		if method == "RemoveEntry" {
			if i >= 0 {
				localization_entry_free(&table.entries[i])
				ordered_remove(&table.entries, i)
				localization_table_changed(table)
			}
			return 0, true
		}
		if method == "RemoveEntryValue" {
			raw := vm.ArgString(L, 5)
			if raw == "" {return vm.RaiseError(L, "locale must not be empty"), true}
			if i >= 0 {
				locale := strings.to_lower(raw, context.allocator)
				changed := localization_remove_value(&table.entries[i], locale)
				delete(locale)
				if changed {localization_table_changed(table)}
			}
			return 0, true
		}
		new_value := vm.ArgString(L, 5)
		text := ""
		if method == "SetEntryValue" {
			text = vm.ArgString(L, 6)
			if new_value == "" ||
			   strings.contains(
				   new_value,
				   "\x00",
			   ) {return vm.RaiseError(L, "invalid locale"), true}
		}
		if i >= 0 {
			entry := &table.entries[i]
			key, source, path = entry.Key, entry.Source, entry.Context
		}
		switch method {
		case "SetEntryKey":
			key = new_value
		case "SetEntrySource":
			source = new_value
		case "SetEntryContext":
			path = new_value
		}
		if key == "" && source == "" {return vm.RaiseError(L, "entry needs a key or source"), true}
		if localization_find(table.entries[:], key, source, path, i) >= 0 {
			return vm.RaiseError(L, "localization entry already exists"), true
		}
		if i < 0 {
			append(&table.entries, localization_entry_new(key, source, path))
			i = len(table.entries) - 1
		}
		entry := &table.entries[i]
		switch method {
		case "SetEntryKey":
			delete(entry.Key); entry.Key = strings.clone(new_value)
		case "SetEntrySource":
			delete(entry.Source); entry.Source = strings.clone(new_value)
		case "SetEntryContext":
			delete(entry.Context); entry.Context = strings.clone(new_value)
		case "SetEntryExample":
			delete(entry.Example); entry.Example = strings.clone(new_value)
		case "SetEntryValue":
			locale := strings.to_lower(new_value, context.allocator)
			localization_store_value(entry, locale, text)
			delete(locale)
		}
		localization_table_changed(table)
		return 0, true
	}
	return 0, false
}


LocalizationTable_Translate :: proc(
	table: ^LocalizationTable,
	source, locale, path: string,
) -> (
	string,
	int,
	bool,
) {
	best := -1
	result := source
	for &entry in table.entries {
		if entry.Source != source {continue}
		n := len(entry.Context)
		if n <= best {continue}
		if n != 0 &&
		   !(path == entry.Context ||
				   (len(path) > n &&
						   path[n] == '.' &&
						   strings.has_prefix(path, entry.Context))) {continue}
		if value, found := entry.Values[locale]; found {
			result, best = value, n
		} else if locale == table.source_locale {
			result, best = source, n
		}
	}
	return result, best, best >= 0
}

Register_LocalizationTable :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&LocalizationTable_Class,
		localization_table_construct,
		localization_table_destroy,
		get = localization_table_get,
		set = localization_table_set,
		namecall = localization_table_namecall,
		clone = localization_table_clone,
		properties = []string{"SourceLocaleId", "SerializedEntries"},
		methods = []string {
			"GetEntries",
			"SetEntries",
			"RemoveEntry",
			"RemoveEntryValue",
			"RemoveTargetLocale",
			"SetEntryContext",
			"SetEntryExample",
			"SetEntryKey",
			"SetEntrySource",
			"SetEntryValue",
		},
	)
}
