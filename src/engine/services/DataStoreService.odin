#+build !js
// wire:service

package services


import "core:encoding/base64"
import "core:encoding/endian"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import rocksdb "../rocksdb"
import target "../target"
import vm "../vm"

DATASTORE_DEFAULT_SCOPE :: "global"
DATASTORE_GLOBAL_NAME :: "global"
DATASTORE_REQUEST_BUDGET :: 60
DATASTORE_MAX_PAGE_SIZE :: 100
DATASTORE_DEFAULT_PATH :: "./kinemium_datastore"
DATASTORE_TAG :: 51
DATASTORE_KEY_INFO_TAG :: 52
DATASTORE_PAGES_TAG :: 53

DataStoreService :: struct {
	using service: Service,
	db:            ^rocksdb.rocksdb_t,
	path:          string,
	mutex:         sync.Mutex,
	limit_reached: bool,
}

DataStore_Handle :: struct {
	service:            ^DataStoreService,
	name:               string,
	scope:              string,
	ordered:            bool,
	datatypes_registry: ^datatypes.Registry,
	enums_registry:     ^enums.Registry,
}

DataStore_Key_Info :: struct {
	version:      i64,
	created_time: f64,
	updated_time: f64,
	metadata:     string,
	user_ids:     string,
}

DataStore_Record :: struct {
	key:          string,
	value:        string,
	version:      i64,
	created_time: f64,
	updated_time: f64,
	metadata:     string,
	user_ids:     string,
	sort_value:   f64,
	has_sort:     bool,
}

DataStore_Page_Entry :: struct {
	key:          string,
	value:        string,
	version:      i64,
	created_time: f64,
	updated_time: f64,
	metadata:     string,
	user_ids:     string,
	sort_value:   f64,
}

DataStore_Pages :: struct {
	entries:            []DataStore_Page_Entry,
	page_size:          int,
	page:               int,
	datatypes_registry: ^datatypes.Registry,
	enums_registry:     ^enums.Registry,
}

data_store_binding := vm.Userdata_Binding {
	name     = "DataStore",
	tag      = DATASTORE_TAG,
	get      = data_store_get,
	namecall = data_store_namecall,
	string   = data_store_string,
	destroy  = data_store_destroy,
}

data_store_key_info_binding := vm.Userdata_Binding {
	name     = "DataStoreKeyInfo",
	tag      = DATASTORE_KEY_INFO_TAG,
	get      = data_store_key_info_get,
	namecall = data_store_key_info_namecall,
	string   = data_store_key_info_string,
	destroy  = data_store_key_info_destroy,
}

data_store_pages_binding := vm.Userdata_Binding {
	name     = "DataStorePages",
	tag      = DATASTORE_PAGES_TAG,
	get      = data_store_pages_get,
	namecall = data_store_pages_namecall,
	string   = data_store_pages_string,
	destroy  = data_store_pages_destroy,
}

DataStoreService_Class := classes.Class_Info {
	name   = "DataStoreService",
	parent = &Service_Class,
}

data_store_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(DataStoreService)
	service.service = Service_Init(&DataStoreService_Class, "DataStoreService", data_model)
	return &service.object
}

data_store_mode_allowed :: proc(service: ^DataStoreService) -> bool {
	if service == nil || service.destroyed {
		return false
	}
	mode := target.current_mode
	if service.data_model != nil && service.data_model.registry != nil {
		mode = service.data_model.registry.mode
	}
	switch mode {
	case .Client, .Editor:
		return false
	case .Server, .Standalone, .Singleplayer:
		return true
	}
	return false
}

data_store_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^DataStoreService)object
	switch key {
	case "LimitReached":
		vm.PushBoolean(L, service.limit_reached)
		return true
	case "GetDataStore",
	     "GetGlobalDataStore",
	     "GetOrderedDataStore",
	     "CreateDataStore",
	     "CreateGlobalDataStore",
	     "CreateOrderedDataStore",
	     "RemoveDataStore",
	     "GetRequestBudgetForRequestType":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

data_store_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^DataStoreService)object
	is_data_store_method :=
		method == "GetDataStore" ||
		method == "CreateDataStore" ||
		method == "GetGlobalDataStore" ||
		method == "CreateGlobalDataStore" ||
		method == "GetOrderedDataStore" ||
		method == "CreateOrderedDataStore" ||
		method == "RemoveDataStore" ||
		method == "GetRequestBudgetForRequestType"
	if is_data_store_method && !data_store_mode_allowed(service) {
		return data_store_raise(
			L,
			"DataStoreService: DataStores are only available to the server runtime",
		)
	}
	switch method {
	case "GetDataStore", "CreateDataStore":
		name := vm.ArgString(L, 2)
		scope := vm.ArgOptionalString(L, 3, DATASTORE_DEFAULT_SCOPE)
		if name == "" {
			return data_store_raise(L, "DataStoreService:GetDataStore requires a name")
		}
		data_store_push(L, service, name, scope, false, datatype_registry, enum_registry)
		return 1, true

	case "GetGlobalDataStore", "CreateGlobalDataStore":
		data_store_push(
			L,
			service,
			DATASTORE_GLOBAL_NAME,
			DATASTORE_DEFAULT_SCOPE,
			false,
			datatype_registry,
			enum_registry,
		)
		return 1, true

	case "GetOrderedDataStore", "CreateOrderedDataStore":
		name := vm.ArgString(L, 2)
		scope := vm.ArgOptionalString(L, 3, DATASTORE_DEFAULT_SCOPE)
		if name == "" {
			return data_store_raise(L, "DataStoreService:GetOrderedDataStore requires a name")
		}
		data_store_push(L, service, name, scope, true, datatype_registry, enum_registry)
		return 1, true

	case "RemoveDataStore":
		name := vm.ArgString(L, 2)
		scope := vm.ArgOptionalString(L, 3, DATASTORE_DEFAULT_SCOPE)
		if name == "" {
			return data_store_raise(L, "DataStoreService:RemoveDataStore requires a name")
		}
		if err := data_store_remove_all(service, name, scope); err != "" {
			return data_store_raise_owned(L, err)
		}
		return 0, true

	case "GetRequestBudgetForRequestType":
		vm.PushNumber(L, DATASTORE_REQUEST_BUDGET)
		return 1, true
	}
	return 0, false
}

data_store_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^DataStoreService)object
	if service.db != nil {
		rocksdb.rocksdb_close(service.db)
		service.db = nil
	}
	delete(service.path)
	classes.Object_Destroy(object)
	free(service)
}

Register_DataStoreService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&DataStoreService_Class,
		data_store_service_construct,
		data_store_service_destroy,
		creatable = false,
		get = data_store_service_get,
		namecall = data_store_service_namecall,
	)
}

data_store_raise :: proc(L: ^vm.State, message: string) -> (i32, bool) {
	return vm.RaiseError(L, message), true
}

data_store_raise_owned :: proc(L: ^vm.State, message: string) -> (i32, bool) {
	result := vm.RaiseError(L, message)
	delete(message)
	return result, true
}

data_store_push :: proc(
	L: ^vm.State,
	service: ^DataStoreService,
	name: string,
	scope: string,
	ordered: bool,
	datatypes_registry: ^datatypes.Registry,
	enums_registry: ^enums.Registry,
) {
	handle := new(DataStore_Handle)
	handle^ = DataStore_Handle {
		service            = service,
		name               = strings.clone(name),
		scope              = strings.clone(scope),
		ordered            = ordered,
		datatypes_registry = datatypes_registry,
		enums_registry     = enums_registry,
	}
	vm.PushUserdata(&vm.VM{L = L}, handle, &data_store_binding)
}

data_store_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	handle := cast(^DataStore_Handle)value
	switch key {
	case "Name":
		vm.PushString(L, handle.name)
		return true
	case "Scope":
		vm.PushString(L, handle.scope)
		return true
	case "GetAsync",
	     "SetAsync",
	     "UpdateAsync",
	     "RemoveAsync",
	     "IncrementAsync",
	     "GetVersionAsync",
	     "ListVersionsAsync",
	     "RemoveVersionAsync",
	     "GetSortedAsync":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

data_store_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	handle := cast(^DataStore_Handle)value

	switch method {
	case "GetAsync":
		return data_store_get_async(L, handle, vm.ArgString(L, 2))
	case "SetAsync":
		return data_store_set_async(L, handle, vm.ArgString(L, 2))
	case "UpdateAsync":
		return data_store_update_async(L, handle, vm.ArgString(L, 2))
	case "RemoveAsync":
		return data_store_remove_async(L, handle, vm.ArgString(L, 2))
	case "IncrementAsync":
		return data_store_increment_async(L, handle, vm.ArgString(L, 2))
	case "GetVersionAsync":
		return data_store_get_version_async(L, handle, vm.ArgString(L, 2))
	case "ListVersionsAsync":
		return data_store_list_versions_async(L, handle, vm.ArgString(L, 2))
	case "RemoveVersionAsync":
		return data_store_remove_version_async(L, handle, vm.ArgString(L, 2))
	case "GetSortedAsync":
		return data_store_get_sorted_async(L, handle)
	}
	return data_store_raise(L, "DataStore: unknown method")
}

data_store_string :: proc(value, ctx: rawptr) -> string {
	handle := cast(^DataStore_Handle)value
	return fmt.tprintf("DataStore(%s)", handle.name)
}

data_store_destroy :: proc(value, ctx: rawptr) {
	handle := cast(^DataStore_Handle)value
	delete(handle.name)
	delete(handle.scope)
	free(handle)
}

data_store_key_info_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	info := cast(^DataStore_Key_Info)value
	switch key {
	case "Version":
		vm.PushString(L, fmt.tprintf("%d", info.version))
		return true
	case "CreatedTime":
		vm.PushNumber(L, info.created_time)
		return true
	case "UpdatedTime":
		vm.PushNumber(L, info.updated_time)
		return true
	case "GetMetadata", "GetUserIds":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

data_store_key_info_namecall :: proc(
	L: ^vm.State,
	value, ctx: rawptr,
	method: string,
) -> (
	i32,
	bool,
) {
	info := cast(^DataStore_Key_Info)value
	switch method {
	case "GetMetadata":
		data_store_push_json_text(L, info.metadata)
		return 1, true
	case "GetUserIds":
		data_store_push_json_text(L, info.user_ids)
		return 1, true
	}
	return data_store_raise(L, "DataStoreKeyInfo: unknown method")
}

data_store_key_info_string :: proc(value, ctx: rawptr) -> string {
	return "DataStoreKeyInfo"
}

data_store_key_info_destroy :: proc(value, ctx: rawptr) {
	info := cast(^DataStore_Key_Info)value
	delete(info.metadata)
	delete(info.user_ids)
	free(info)
}

data_store_pages_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	switch key {
	case "GetCurrentPage", "AdvanceToNextPageAsync":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

data_store_pages_namecall :: proc(
	L: ^vm.State,
	value, ctx: rawptr,
	method: string,
) -> (
	i32,
	bool,
) {
	pages := cast(^DataStore_Pages)value
	switch method {
	case "GetCurrentPage":
		data_store_pages_push_current(L, pages)
		return 1, true
	case "AdvanceToNextPageAsync":
		pages.page += 1
		return 0, true
	}
	return data_store_raise(L, "DataStorePages: unknown method")
}

data_store_pages_string :: proc(value, ctx: rawptr) -> string {
	return "DataStorePages"
}

data_store_pages_destroy :: proc(value, ctx: rawptr) {
	pages := cast(^DataStore_Pages)value
	for entry in pages.entries {
		delete(entry.key)
		delete(entry.value)
		delete(entry.metadata)
		delete(entry.user_ids)
	}
	delete(pages.entries)
	free(pages)
}

data_store_pages_push_current :: proc(L: ^vm.State, pages: ^DataStore_Pages) {
	start := pages.page * pages.page_size
	if start < 0 {
		start = 0
	}
	end := start + pages.page_size
	if end > len(pages.entries) {
		end = len(pages.entries)
	}
	if start > end {
		start = end
	}

	vm.NewTable(L, 0, 0)
	for entry, index in pages.entries[start:end] {
		vm.NewTable(L, 0, 3)
		vm.PushString(L, entry.key)
		vm.SetField(L, -2, "key")
		data_store_push_value_text(L, pages.datatypes_registry, pages.enums_registry, entry.value)
		vm.SetField(L, -2, "value")
		data_store_push_key_info(
			L,
			entry.version,
			entry.created_time,
			entry.updated_time,
			entry.metadata,
			entry.user_ids,
		)
		vm.SetField(L, -2, "keyInfo")
		vm.SetArrayValue(L, -2, index + 1)
	}
}

DATASTORE_MAX_VALUE_DEPTH :: 20
DATASTORE_TYPE_KEY :: "__kinemium_type"

data_store_json_put :: proc(object: ^json.Object, key: string, value: json.Value) {
	object^[strings.clone(key)] = value
}

data_store_json_put_number :: proc(object: ^json.Object, key: string, value: f64) {
	data_store_json_put(object, key, json.Float(value))
}

data_store_json_put_integer :: proc(object: ^json.Object, key: string, value: i64) {
	data_store_json_put(object, key, json.Integer(value))
}

data_store_json_put_boolean :: proc(object: ^json.Object, key: string, value: bool) {
	data_store_json_put(object, key, json.Boolean(value))
}

data_store_json_put_string :: proc(object: ^json.Object, key: string, value: string) {
	data_store_json_put(object, key, json.String(strings.clone(value)))
}

data_store_json_typed_object :: proc(type_name: string) -> ^json.Object {
	object := new(json.Object, context.temp_allocator)
	object^ = make(json.Object)
	data_store_json_put_string(object, DATASTORE_TYPE_KEY, type_name)
	return object
}

data_store_json_put_vector2 :: proc(object: ^json.Object, key: string, x, y: f32) {
	nested := make(json.Object)
	data_store_json_put_number(&nested, "X", f64(x))
	data_store_json_put_number(&nested, "Y", f64(y))
	data_store_json_put(object, key, nested)
}

data_store_json_put_vector3 :: proc(object: ^json.Object, key: string, x, y, z: f32) {
	nested := make(json.Object)
	data_store_json_put_number(&nested, "X", f64(x))
	data_store_json_put_number(&nested, "Y", f64(y))
	data_store_json_put_number(&nested, "Z", f64(z))
	data_store_json_put(object, key, nested)
}

data_store_json_put_color3 :: proc(object: ^json.Object, key: string, color: datatypes.Color3) {
	nested := make(json.Object)
	data_store_json_put_number(&nested, "R", f64(color.R))
	data_store_json_put_number(&nested, "G", f64(color.G))
	data_store_json_put_number(&nested, "B", f64(color.B))
	data_store_json_put(object, key, nested)
}

data_store_lua_to_json :: proc(
	L: ^vm.State,
	index: int,
	depth: int,
) -> (
	value: json.Value,
	err: string,
) {
	if depth > DATASTORE_MAX_VALUE_DEPTH {
		return nil, "DataStore value is nested too deeply (is there a cycle?)"
	}

	#partial switch vm.TypeOf(L, index) {
	case .Nil:
		return json.Null(nil), ""

	case .Boolean:
		return json.Boolean(vm.ArgBoolean(L, index)), ""

	case .Integer:
		return json.Integer(vm.ArgInteger(L, index)), ""

	case .Number:
		number, _ := vm.ToNumber(L, index)
		if number != number || math.is_inf(number) {
			return nil, "DataStore values cannot contain NaN or infinity"
		}
		return json.Float(number), ""

	case .String:
		text, _ := vm.ToString(L, index)
		return json.String(strings.clone(text)), ""

	case .Vector:
		x, y, z := vm.ArgVector3(L, index)
		object := data_store_json_typed_object("Vector3")
		data_store_json_put_number(object, "X", f64(x))
		data_store_json_put_number(object, "Y", f64(y))
		data_store_json_put_number(object, "Z", f64(z))
		return object^, ""

	case .Table:
		return data_store_lua_table_to_json(L, index, depth)

	case .Userdata:
		return data_store_lua_userdata_to_json(L, index)
	}

	return nil, fmt.aprintf("cannot store a %s value in a DataStore", vm.TypeName(L, index))
}

data_store_lua_table_to_json :: proc(
	L: ^vm.State,
	index: int,
	depth: int,
) -> (
	value: json.Value,
	err: string,
) {
	count := 0

	vm.PushNil(L)

	for vm.Next(L, index) {
		count += 1

		vm.Pop(L)
	}

	length := vm.RawLen(L, index)

	if count > 0 && count == length {
		array := make(json.Array, 0, length)

		for position in 1 ..= length {
			vm.RawGetIndex(L, index, position)

			item, item_err := data_store_lua_to_json(L, vm.StackTop(L), depth + 1)

			vm.Pop(L)

			if item_err != "" {
				return nil, item_err
			}

			append(&array, item)
		}

		return array, ""
	}

	object := make(json.Object)

	vm.PushNil(L)

	for vm.Next(L, index) {
		value_index := vm.StackTop(L)
		key_index := value_index - 1

		key: string

		#partial switch vm.TypeOf(L, key_index) {
		case .Integer:
			key = fmt.tprintf("%d", vm.ArgInteger(L, key_index))

		case .Number:
			number, _ := vm.ToNumber(L, key_index)

			if number == math.floor(number) && abs(number) < 1e15 {
				key = fmt.tprintf("%d", i64(number))
			} else {
				key = fmt.tprintf("%v", number)
			}

		case .String:
			raw_key, _ := vm.ToString(L, key_index)
			key = strings.clone(raw_key)

		case:
			return nil, "DataStore table keys must be strings or numbers"
		}

		item, item_err := data_store_lua_to_json(L, value_index, depth + 1)

		if item_err != "" {
			return nil, item_err
		}

		object[key] = item

		vm.Pop(L)
	}

	return object, ""
}

data_store_lua_userdata_to_json :: proc(
	L: ^vm.State,
	index: int,
) -> (
	value: json.Value,
	err: string,
) {
	binding := vm.UserdataBindingOf(L, index)
	if binding == nil {
		return nil, "cannot store a userdata with no registered binding in a DataStore"
	}

	ptr := vm.UserdataValue(L, index)
	if ptr == nil {
		return nil, fmt.aprintf("cannot store a %s value in a DataStore", binding.name)
	}

	switch binding.name {
	case "Axes":
		value := cast(^datatypes.Axes)ptr
		object := data_store_json_typed_object("Axes")
		data_store_json_put_boolean(object, "X", value.X)
		data_store_json_put_boolean(object, "Y", value.Y)
		data_store_json_put_boolean(object, "Z", value.Z)
		return object^, ""

	case "BrickColor":
		value := cast(^datatypes.BrickColor)ptr
		object := data_store_json_typed_object("BrickColor")
		data_store_json_put_integer(object, "Number", i64(value.number))
		data_store_json_put_string(object, "Name", value.name)
		data_store_json_put_color3(object, "Color", value.color)
		return object^, ""

	case "CFrame":
		value := cast(^datatypes.CFrame)ptr
		object := data_store_json_typed_object("CFrame")
		data_store_json_put_number(object, "X", f64(value.x))
		data_store_json_put_number(object, "Y", f64(value.y))
		data_store_json_put_number(object, "Z", f64(value.z))
		data_store_json_put_number(object, "R00", f64(value.r00))
		data_store_json_put_number(object, "R01", f64(value.r01))
		data_store_json_put_number(object, "R02", f64(value.r02))
		data_store_json_put_number(object, "R10", f64(value.r10))
		data_store_json_put_number(object, "R11", f64(value.r11))
		data_store_json_put_number(object, "R12", f64(value.r12))
		data_store_json_put_number(object, "R20", f64(value.r20))
		data_store_json_put_number(object, "R21", f64(value.r21))
		data_store_json_put_number(object, "R22", f64(value.r22))
		return object^, ""

	case "Color3":
		value := cast(^datatypes.Color3)ptr
		object := data_store_json_typed_object("Color3")
		data_store_json_put_number(object, "R", f64(value.R))
		data_store_json_put_number(object, "G", f64(value.G))
		data_store_json_put_number(object, "B", f64(value.B))
		return object^, ""

	case "ColorSequence":
		value := cast(^datatypes.ColorSequence)ptr
		object := data_store_json_typed_object("ColorSequence")
		keypoints := make(json.Array, 0, len(value.Keypoints))
		for keypoint in value.Keypoints {
			item := make(json.Object)
			data_store_json_put_number(&item, "Time", f64(keypoint.Time))
			data_store_json_put_color3(&item, "Value", keypoint.Value)
			append(&keypoints, item)
		}
		data_store_json_put(object, "Keypoints", keypoints)
		return object^, ""

	case "Content":
		value := cast(^datatypes.Content)ptr
		object := data_store_json_typed_object("Content")
		data_store_json_put_string(object, "URI", value.uri)
		data_store_json_put_integer(object, "ObjectId", i64(value.object_id))
		data_store_json_put_integer(object, "ObjectKind", i64(value.object_kind))
		return object^, ""

	case "DateTime":
		value := cast(^datatypes.DateTime)ptr
		object := data_store_json_typed_object("DateTime")
		data_store_json_put_number(object, "UnixTimestampMillis", value.UnixTimestampMillis)
		return object^, ""

	case "Faces":
		value := cast(^datatypes.Faces)ptr
		object := data_store_json_typed_object("Faces")
		data_store_json_put_boolean(object, "Top", value.Top)
		data_store_json_put_boolean(object, "Bottom", value.Bottom)
		data_store_json_put_boolean(object, "Left", value.Left)
		data_store_json_put_boolean(object, "Right", value.Right)
		data_store_json_put_boolean(object, "Front", value.Front)
		data_store_json_put_boolean(object, "Back", value.Back)
		return object^, ""

	case "Font":
		value := cast(^datatypes.Font)ptr
		object := data_store_json_typed_object("Font")
		data_store_json_put_string(object, "Family", value.Family)
		data_store_json_put_integer(object, "Weight", i64(value.Weight))
		data_store_json_put_integer(object, "Style", i64(value.Style))
		if len(value.Data) > 0 {
			encoded := base64.encode(value.Data, allocator = context.temp_allocator)
			data_store_json_put_string(object, "Data", encoded)
		}
		return object^, ""

	case "NumberRange":
		value := cast(^datatypes.NumberRange)ptr
		object := data_store_json_typed_object("NumberRange")
		data_store_json_put_number(object, "Min", f64(value.Min))
		data_store_json_put_number(object, "Max", f64(value.Max))
		return object^, ""

	case "NumberSequence":
		value := cast(^datatypes.NumberSequence)ptr
		object := data_store_json_typed_object("NumberSequence")
		keypoints := make(json.Array, 0, len(value.Keypoints))
		for keypoint in value.Keypoints {
			item := make(json.Object)
			data_store_json_put_number(&item, "Time", f64(keypoint.Time))
			data_store_json_put_number(&item, "Value", f64(keypoint.Value))
			data_store_json_put_number(&item, "Envelope", f64(keypoint.Envelope))
			append(&keypoints, item)
		}
		data_store_json_put(object, "Keypoints", keypoints)
		return object^, ""

	case "PathWaypoint":
		value := cast(^datatypes.PathWaypoint)ptr
		object := data_store_json_typed_object("PathWaypoint")
		data_store_json_put_vector3(
			object,
			"Position",
			value.Position.x,
			value.Position.y,
			value.Position.z,
		)
		data_store_json_put_integer(object, "Action", i64(value.Action))
		data_store_json_put_string(object, "Label", value.Label)
		return object^, ""

	case "PhysicalProperties":
		value := cast(^datatypes.PhysicalProperties)ptr
		object := data_store_json_typed_object("PhysicalProperties")
		data_store_json_put_number(object, "Density", f64(value.Density))
		data_store_json_put_number(object, "Friction", f64(value.Friction))
		data_store_json_put_number(object, "Elasticity", f64(value.Elasticity))
		data_store_json_put_number(object, "FrictionWeight", f64(value.FrictionWeight))
		data_store_json_put_number(object, "ElasticityWeight", f64(value.ElasticityWeight))
		return object^, ""

	case "Quaternion":
		value := cast(^datatypes.Quaternion)ptr
		object := data_store_json_typed_object("Quaternion")
		data_store_json_put_number(object, "X", f64(value.X))
		data_store_json_put_number(object, "Y", f64(value.Y))
		data_store_json_put_number(object, "Z", f64(value.Z))
		data_store_json_put_number(object, "W", f64(value.W))
		return object^, ""

	case "Ray":
		value := cast(^datatypes.Ray)ptr
		object := data_store_json_typed_object("Ray")
		data_store_json_put_vector3(
			object,
			"Origin",
			value.Origin.x,
			value.Origin.y,
			value.Origin.z,
		)
		data_store_json_put_vector3(
			object,
			"Direction",
			value.Direction.x,
			value.Direction.y,
			value.Direction.z,
		)
		return object^, ""

	case "Rect":
		value := cast(^datatypes.Rect)ptr
		object := data_store_json_typed_object("Rect")
		data_store_json_put_vector2(object, "Min", value.Min.X, value.Min.Y)
		data_store_json_put_vector2(object, "Max", value.Max.X, value.Max.Y)
		return object^, ""

	case "Region3":
		value := cast(^datatypes.Region3)ptr
		object := data_store_json_typed_object("Region3")
		data_store_json_put_vector3(object, "Min", value.Min.x, value.Min.y, value.Min.z)
		data_store_json_put_vector3(object, "Max", value.Max.x, value.Max.y, value.Max.z)
		return object^, ""

	case "Region3int16":
		value := cast(^datatypes.Region3int16)ptr
		object := data_store_json_typed_object("Region3int16")
		data_store_json_put_vector3(
			object,
			"Min",
			f32(value.Min.X),
			f32(value.Min.Y),
			f32(value.Min.Z),
		)
		data_store_json_put_vector3(
			object,
			"Max",
			f32(value.Max.X),
			f32(value.Max.Y),
			f32(value.Max.Z),
		)
		return object^, ""

	case "SecurityCapabilities":
		value := cast(^datatypes.SecurityCapabilities)ptr
		object := data_store_json_typed_object("SecurityCapabilities")
		data_store_json_put_integer(object, "BitsLow", i64(value.bits_low))
		data_store_json_put_integer(object, "BitsHigh", i64(value.bits_high))
		return object^, ""

	case "TweenInfo":
		value := cast(^datatypes.TweenInfo)ptr
		object := data_store_json_typed_object("TweenInfo")
		data_store_json_put_number(object, "Time", f64(value.Time))
		data_store_json_put_integer(object, "EasingStyle", i64(value.EasingStyle))
		data_store_json_put_integer(object, "EasingDirection", i64(value.EasingDirection))
		data_store_json_put_integer(object, "RepeatCount", i64(value.RepeatCount))
		data_store_json_put_boolean(object, "Reverses", value.Reverses)
		data_store_json_put_number(object, "DelayTime", f64(value.DelayTime))
		return object^, ""

	case "UDim":
		value := cast(^datatypes.UDim)ptr
		object := data_store_json_typed_object("UDim")
		data_store_json_put_number(object, "Scale", f64(value.Scale))
		data_store_json_put_number(object, "Offset", f64(value.Offset))
		return object^, ""

	case "UDim2":
		value := cast(^datatypes.UDim2)ptr
		object := data_store_json_typed_object("UDim2")
		data_store_json_put_number(object, "XScale", f64(value.X_Scale))
		data_store_json_put_number(object, "XOffset", f64(value.X_Offset))
		data_store_json_put_number(object, "YScale", f64(value.Y_Scale))
		data_store_json_put_number(object, "YOffset", f64(value.Y_Offset))
		return object^, ""

	case "UniqueId":
		value := cast(^datatypes.UniqueId)ptr
		object := data_store_json_typed_object("UniqueId")
		data_store_json_put_integer(object, "Random", value.Random)
		data_store_json_put_integer(object, "Time", i64(value.Time))
		data_store_json_put_integer(object, "Index", i64(value.Index))
		return object^, ""

	case "Vector2":
		value := cast(^datatypes.Vector2)ptr
		object := data_store_json_typed_object("Vector2")
		data_store_json_put_number(object, "X", f64(value.X))
		data_store_json_put_number(object, "Y", f64(value.Y))
		return object^, ""

	case "Vector2int16":
		value := cast(^datatypes.Vector2int16)ptr
		object := data_store_json_typed_object("Vector2int16")
		data_store_json_put_integer(object, "X", i64(value.X))
		data_store_json_put_integer(object, "Y", i64(value.Y))
		return object^, ""

	case "Vector3":
		value := cast(^datatypes.Vector3)ptr
		object := data_store_json_typed_object("Vector3")
		data_store_json_put_number(object, "X", f64(value.x))
		data_store_json_put_number(object, "Y", f64(value.y))
		data_store_json_put_number(object, "Z", f64(value.z))
		return object^, ""

	case "Vector3int16":
		value := cast(^datatypes.Vector3int16)ptr
		object := data_store_json_typed_object("Vector3int16")
		data_store_json_put_integer(object, "X", i64(value.X))
		data_store_json_put_integer(object, "Y", i64(value.Y))
		data_store_json_put_integer(object, "Z", i64(value.Z))
		return object^, ""

	case "EnumItem":
		item := cast(^enums.Enum_Item)ptr
		if item == nil || item.enum_type == nil {
			return nil, "cannot store an EnumItem with no Enum behind it"
		}
		object := data_store_json_typed_object("EnumItem")
		data_store_json_put_string(object, "Enum", item.enum_type.name)
		data_store_json_put_string(object, "Name", item.name)
		data_store_json_put_integer(object, "Value", item.value)
		return object^, ""
	}

	return nil, fmt.aprintf("cannot store a %s value in a DataStore", binding.name)
}

data_store_json_number :: proc(object: json.Object, key: string) -> f64 {
	value, ok := object[key]
	if !ok {
		return 0
	}
	#partial switch number in value {
	case json.Integer:
		return f64(number)
	case json.Float:
		return f64(number)
	}
	return 0
}

data_store_json_integer :: proc(object: json.Object, key: string) -> i64 {
	value, ok := object[key]
	if !ok {
		return 0
	}
	#partial switch number in value {
	case json.Integer:
		return i64(number)
	case json.Float:
		return i64(number)
	}
	return 0
}

data_store_json_boolean :: proc(object: json.Object, key: string) -> bool {
	value, ok := object[key]
	if !ok {
		return false
	}
	#partial switch boolean in value {
	case json.Boolean:
		return bool(boolean)
	}
	return false
}

data_store_json_string :: proc(object: json.Object, key: string) -> string {
	value, ok := object[key]
	if !ok {
		return ""
	}
	#partial switch text in value {
	case json.String:
		return string(text)
	}
	return ""
}

data_store_json_type_name :: proc(object: json.Object) -> (string, bool) {
	value, ok := object[DATASTORE_TYPE_KEY]
	if !ok {
		return "", false
	}
	#partial switch text in value {
	case json.String:
		return string(text), true
	}
	return "", false
}

data_store_json_vector2 :: proc(object: json.Object, key: string) -> datatypes.Vector2 {
	value, ok := object[key]
	if !ok {
		return {}
	}
	#partial switch nested in value {
	case json.Object:
		return {
			X = f32(data_store_json_number(nested, "X")),
			Y = f32(data_store_json_number(nested, "Y")),
		}
	}
	return {}
}

data_store_json_vector3 :: proc(object: json.Object, key: string) -> datatypes.Vector3 {
	value, ok := object[key]
	if !ok {
		return {}
	}
	#partial switch nested in value {
	case json.Object:
		return {
			x = f32(data_store_json_number(nested, "X")),
			y = f32(data_store_json_number(nested, "Y")),
			z = f32(data_store_json_number(nested, "Z")),
		}
	}
	return {}
}

data_store_json_color3 :: proc(object: json.Object, key: string) -> datatypes.Color3 {
	value, ok := object[key]
	if !ok {
		return {}
	}
	#partial switch nested in value {
	case json.Object:
		return {
			R = f32(data_store_json_number(nested, "R")),
			G = f32(data_store_json_number(nested, "G")),
			B = f32(data_store_json_number(nested, "B")),
		}
	}
	return {}
}

data_store_push_datatype :: proc(
	L: ^vm.State,
	datatypes_registry: ^datatypes.Registry,
	enums_registry: ^enums.Registry,
	type_name: string,
	object: json.Object,
) -> bool {
	if type_name == "Vector3" {
		vm.PushVector3(
			L,
			f32(data_store_json_number(object, "X")),
			f32(data_store_json_number(object, "Y")),
			f32(data_store_json_number(object, "Z")),
		)
		return true
	}

	if type_name == "EnumItem" {
		if enums_registry == nil {
			vm.PushNil(L)
			return true
		}
		enums.Push_Item_By_Value(
			L,
			enums_registry,
			data_store_json_string(object, "Enum"),
			data_store_json_integer(object, "Value"),
		)
		return true
	}

	if datatypes_registry == nil {
		vm.PushNil(L)
		return true
	}

	switch type_name {
	case "Axes":
		datatypes.Push_Axes(
			L,
			datatypes_registry,
			{
				X = data_store_json_boolean(object, "X"),
				Y = data_store_json_boolean(object, "Y"),
				Z = data_store_json_boolean(object, "Z"),
			},
		)

	case "BrickColor":
		datatypes.Push_BrickColor(
			L,
			datatypes_registry,
			datatypes.BrickColor_From_Number(i32(data_store_json_integer(object, "Number"))),
		)

	case "CFrame":
		datatypes.Push_CFrame(
			L,
			datatypes_registry,
			datatypes.CFrame_New_Matrix(
				f32(data_store_json_number(object, "X")),
				f32(data_store_json_number(object, "Y")),
				f32(data_store_json_number(object, "Z")),
				f32(data_store_json_number(object, "R00")),
				f32(data_store_json_number(object, "R01")),
				f32(data_store_json_number(object, "R02")),
				f32(data_store_json_number(object, "R10")),
				f32(data_store_json_number(object, "R11")),
				f32(data_store_json_number(object, "R12")),
				f32(data_store_json_number(object, "R20")),
				f32(data_store_json_number(object, "R21")),
				f32(data_store_json_number(object, "R22")),
			),
		)

	case "Color3":
		datatypes.Push_Color3(
			L,
			datatypes_registry,
			{
				R = f32(data_store_json_number(object, "R")),
				G = f32(data_store_json_number(object, "G")),
				B = f32(data_store_json_number(object, "B")),
			},
		)

	case "ColorSequence":
		keypoints := make([dynamic]datatypes.ColorSequenceKeypoint, 0)
		if value, ok := object["Keypoints"]; ok {
			#partial switch array in value {
			case json.Array:
				for item in array {
					#partial switch keypoint in item {
					case json.Object:
						append(
							&keypoints,
							datatypes.ColorSequenceKeypoint {
								Time = f32(data_store_json_number(keypoint, "Time")),
								Value = data_store_json_color3(keypoint, "Value"),
							},
						)
					}
				}
			}
		}
		datatypes.Push_ColorSequence(
			L,
			datatypes_registry,
			datatypes.ColorSequence{Keypoints = keypoints[:]},
		)

	case "Content":
		uri := data_store_json_string(object, "URI")
		datatypes.Push_Content(
			L,
			datatypes_registry,
			datatypes.Content {
				uri = strings.clone(uri),
				object_id = u32(data_store_json_integer(object, "ObjectId")),
				object_kind = u8(data_store_json_integer(object, "ObjectKind")),
			},
		)

	case "DateTime":
		datatypes.Push_DateTime(
			L,
			datatypes_registry,
			datatypes.DateTime {
				UnixTimestampMillis = data_store_json_number(object, "UnixTimestampMillis"),
			},
		)

	case "Faces":
		datatypes.Push_Faces(
			L,
			datatypes_registry,
			{
				Top = data_store_json_boolean(object, "Top"),
				Bottom = data_store_json_boolean(object, "Bottom"),
				Left = data_store_json_boolean(object, "Left"),
				Right = data_store_json_boolean(object, "Right"),
				Front = data_store_json_boolean(object, "Front"),
				Back = data_store_json_boolean(object, "Back"),
			},
		)

	case "Font":
		font := datatypes.Font {
			Family = data_store_json_string(object, "Family"),
			Weight = enums.FontWeight(data_store_json_integer(object, "Weight")),
			Style  = enums.FontStyle(data_store_json_integer(object, "Style")),
		}
		if data := data_store_json_string(object, "Data"); data != "" {
			decoded, decode_err := base64.decode(data, allocator = context.temp_allocator)
			if decode_err == nil {
				font.Data = decoded
			}
		}
		datatypes.Push_Font(L, datatypes_registry, font)

	case "NumberRange":
		datatypes.Push_NumberRange(
			L,
			datatypes_registry,
			{
				Min = f32(data_store_json_number(object, "Min")),
				Max = f32(data_store_json_number(object, "Max")),
			},
		)

	case "NumberSequence":
		keypoints := make([dynamic]datatypes.NumberSequenceKeypoint, 0)
		if value, ok := object["Keypoints"]; ok {
			#partial switch array in value {
			case json.Array:
				for item in array {
					#partial switch keypoint in item {
					case json.Object:
						append(
							&keypoints,
							datatypes.NumberSequenceKeypoint {
								Time = f32(data_store_json_number(keypoint, "Time")),
								Value = f32(data_store_json_number(keypoint, "Value")),
								Envelope = f32(data_store_json_number(keypoint, "Envelope")),
							},
						)
					}
				}
			}
		}
		datatypes.Push_NumberSequence(
			L,
			datatypes_registry,
			datatypes.NumberSequence{Keypoints = keypoints[:]},
		)

	case "PathWaypoint":
		datatypes.Push_PathWaypoint(
			L,
			datatypes_registry,
			{
				Position = data_store_json_vector3(object, "Position"),
				Action = enums.PathWaypointAction(data_store_json_integer(object, "Action")),
				Label = data_store_json_string(object, "Label"),
			},
		)

	case "PhysicalProperties":
		datatypes.Push_PhysicalProperties(
			L,
			datatypes_registry,
			{
				Density = f32(data_store_json_number(object, "Density")),
				Friction = f32(data_store_json_number(object, "Friction")),
				Elasticity = f32(data_store_json_number(object, "Elasticity")),
				FrictionWeight = f32(data_store_json_number(object, "FrictionWeight")),
				ElasticityWeight = f32(data_store_json_number(object, "ElasticityWeight")),
			},
		)

	case "Quaternion":
		datatypes.Push_Quaternion(
			L,
			datatypes_registry,
			{
				X = f32(data_store_json_number(object, "X")),
				Y = f32(data_store_json_number(object, "Y")),
				Z = f32(data_store_json_number(object, "Z")),
				W = f32(data_store_json_number(object, "W")),
			},
		)

	case "Ray":
		datatypes.Push_Ray(
			L,
			datatypes_registry,
			{
				Origin = data_store_json_vector3(object, "Origin"),
				Direction = data_store_json_vector3(object, "Direction"),
			},
		)

	case "Rect":
		datatypes.Push_Rect(
			L,
			datatypes_registry,
			{
				Min = data_store_json_vector2(object, "Min"),
				Max = data_store_json_vector2(object, "Max"),
			},
		)

	case "Region3":
		datatypes.Push_Region3(
			L,
			datatypes_registry,
			{
				Min = data_store_json_vector3(object, "Min"),
				Max = data_store_json_vector3(object, "Max"),
			},
		)

	case "Region3int16":
		min := data_store_json_vector3(object, "Min")
		max := data_store_json_vector3(object, "Max")
		datatypes.Push_Region3int16(
			L,
			datatypes_registry,
			{
				Min = {X = i16(min.x), Y = i16(min.y), Z = i16(min.z)},
				Max = {X = i16(max.x), Y = i16(max.y), Z = i16(max.z)},
			},
		)

	case "SecurityCapabilities":
		datatypes.Push_SecurityCapabilities(
			L,
			datatypes_registry,
			{
				bits_low = u64(data_store_json_integer(object, "BitsLow")),
				bits_high = u64(data_store_json_integer(object, "BitsHigh")),
			},
		)

	case "TweenInfo":
		datatypes.Push_TweenInfo(
			L,
			datatypes_registry,
			{
				Time = f32(data_store_json_number(object, "Time")),
				EasingStyle = enums.EasingStyle(data_store_json_integer(object, "EasingStyle")),
				EasingDirection = enums.EasingDirection(
					data_store_json_integer(object, "EasingDirection"),
				),
				RepeatCount = i32(data_store_json_integer(object, "RepeatCount")),
				Reverses = data_store_json_boolean(object, "Reverses"),
				DelayTime = f32(data_store_json_number(object, "DelayTime")),
			},
		)

	case "UDim":
		datatypes.Push_UDim(
			L,
			datatypes_registry,
			{
				Scale = f32(data_store_json_number(object, "Scale")),
				Offset = f32(data_store_json_number(object, "Offset")),
			},
		)

	case "UDim2":
		datatypes.Push_UDim2(
			L,
			datatypes_registry,
			{
				X_Scale = f32(data_store_json_number(object, "XScale")),
				X_Offset = f32(data_store_json_number(object, "XOffset")),
				Y_Scale = f32(data_store_json_number(object, "YScale")),
				Y_Offset = f32(data_store_json_number(object, "YOffset")),
			},
		)

	case "UniqueId":
		datatypes.Push_UniqueId(
			L,
			datatypes_registry,
			{
				Random = data_store_json_integer(object, "Random"),
				Time = u32(data_store_json_integer(object, "Time")),
				Index = u32(data_store_json_integer(object, "Index")),
			},
		)

	case "Vector2":
		datatypes.Push_Vector2(
			L,
			datatypes_registry,
			{
				X = f32(data_store_json_number(object, "X")),
				Y = f32(data_store_json_number(object, "Y")),
			},
		)

	case "Vector2int16":
		datatypes.Push_Vector2int16(
			L,
			datatypes_registry,
			{
				X = i16(data_store_json_integer(object, "X")),
				Y = i16(data_store_json_integer(object, "Y")),
			},
		)

	case "Vector3int16":
		datatypes.Push_Vector3int16(
			L,
			datatypes_registry,
			{
				X = i16(data_store_json_integer(object, "X")),
				Y = i16(data_store_json_integer(object, "Y")),
				Z = i16(data_store_json_integer(object, "Z")),
			},
		)

	case:
		return false
	}

	return true
}

data_store_push_typed_json :: proc(
	L: ^vm.State,
	datatypes_registry: ^datatypes.Registry,
	enums_registry: ^enums.Registry,
	value: json.Value,
) {
	#partial switch current in value {
	case json.Null:
		vm.PushNil(L)

	case json.Integer:
		vm.PushNumber(L, f64(i64(current)))

	case json.Float:
		vm.PushNumber(L, f64(current))

	case json.Boolean:
		vm.PushBoolean(L, bool(current))

	case json.String:
		vm.PushString(L, string(current))

	case json.Array:
		vm.NewTable(L, 0, 0)
		for item, index in current {
			data_store_push_typed_json(L, datatypes_registry, enums_registry, item)
			vm.SetArrayValue(L, -2, index + 1)
		}

	case json.Object:
		if type_name, ok := data_store_json_type_name(current); ok {
			if data_store_push_datatype(
				L,
				datatypes_registry,
				enums_registry,
				type_name,
				current,
			) {
				return
			}
		}
		vm.NewTable(L, 0, 0)
		for key, item in current {
			data_store_push_typed_json(L, datatypes_registry, enums_registry, item)
			vm.SetField(L, -2, string(key))
		}
	}
}

data_store_encode_value :: proc(L: ^vm.State, index: int) -> (encoded: string, err: string) {
	if vm.IsNoneOrNil(L, index) {
		return strings.clone("null"), ""
	}

	absolute_index := index
	if absolute_index < 0 {
		absolute_index = vm.StackTop(L) + absolute_index + 1
	}

	tree, convert_err := data_store_lua_to_json(L, absolute_index, 0)
	if convert_err != "" {
		return "", convert_err
	}
	defer json.destroy_value(tree)

	data, marshal_err := json.marshal(
		tree,
		json.Marshal_Options{spec = .JSON, sort_maps_by_key = true},
		context.temp_allocator,
	)
	if marshal_err != nil {
		return "", fmt.aprintf("DataStore value could not be encoded as JSON: %v", marshal_err)
	}

	return strings.clone(string(data)), ""
}

data_store_push_json_text :: proc(L: ^vm.State, text: string) {
	if text == "" || text == "null" {
		vm.PushNil(L)
		return
	}

	decoded, decode_err := json.parse_string(
		text,
		parse_integers = false,
		allocator = context.temp_allocator,
	)
	if decode_err != nil {
		vm.PushNil(L)
		return
	}
	defer json.destroy_value(decoded, context.temp_allocator)

	http_push_json_value(L, decoded)
}

data_store_push_value_text :: proc(
	L: ^vm.State,
	datatypes_registry: ^datatypes.Registry,
	enums_registry: ^enums.Registry,
	text: string,
) {
	if text == "" || text == "null" {
		vm.PushNil(L)
		return
	}

	decoded, decode_err := json.parse_string(
		text,
		parse_integers = false,
		allocator = context.temp_allocator,
	)
	if decode_err != nil {
		vm.PushNil(L)
		return
	}
	defer json.destroy_value(decoded, context.temp_allocator)

	data_store_push_typed_json(L, datatypes_registry, enums_registry, decoded)
}

data_store_push_key_info :: proc(
	L: ^vm.State,
	version: i64,
	created_time: f64,
	updated_time: f64,
	metadata: string,
	user_ids: string,
) {
	info := new(DataStore_Key_Info)
	info^ = DataStore_Key_Info {
		version      = version,
		created_time = created_time,
		updated_time = updated_time,
		metadata     = strings.clone(metadata == "" ? "{}" : metadata),
		user_ids     = strings.clone(user_ids == "" ? "[]" : user_ids),
	}
	vm.PushUserdata(&vm.VM{L = L}, info, &data_store_key_info_binding)
}

data_store_now :: proc() -> f64 {
	return f64(time.to_unix_seconds(time.now()))
}

data_store_append_u32 :: proc(b: ^strings.Builder, value: u32) {
	buffer: [4]u8
	endian.unchecked_put_u32be(buffer[:], value)
	strings.write_bytes(b, buffer[:])
}

data_store_append_u64 :: proc(b: ^strings.Builder, value: u64) {
	buffer: [8]u8
	endian.unchecked_put_u64be(buffer[:], value)
	strings.write_bytes(b, buffer[:])
}

data_store_append_component :: proc(b: ^strings.Builder, value: string) {
	data_store_append_u32(b, u32(len(value)))
	strings.write_string(b, value)
}

data_store_prefix_builder :: proc(kind: u8, name, scope: string) -> strings.Builder {
	builder := strings.builder_make()
	strings.write_byte(&builder, kind)
	data_store_append_component(&builder, name)
	data_store_append_component(&builder, scope)
	return builder
}

data_store_key_record :: proc(name, scope, key: string) -> string {
	builder := data_store_prefix_builder('d', name, scope)
	data_store_append_component(&builder, key)
	return strings.to_string(builder)
}

data_store_key_version :: proc(name, scope, key: string, version: i64) -> string {
	builder := data_store_prefix_builder('v', name, scope)
	data_store_append_component(&builder, key)
	data_store_append_u64(&builder, u64(version))
	return strings.to_string(builder)
}

data_store_sort_bits :: proc(value: f64) -> u64 {
	bits := transmute(u64)value
	sign := u64(1) << 63
	if bits & sign != 0 {
		return ~bits
	}
	return bits ~ sign
}

data_store_key_sorted :: proc(name, scope: string, sort_value: f64, key: string) -> string {
	builder := data_store_prefix_builder('s', name, scope)
	data_store_append_u64(&builder, data_store_sort_bits(sort_value))
	data_store_append_component(&builder, key)
	return strings.to_string(builder)
}

data_store_prefix_end :: proc(prefix: string) -> string {
	builder := strings.builder_make()
	if len(prefix) == 0 {
		return strings.to_string(builder)
	}
	last := prefix[len(prefix) - 1]
	if last < 0xff {
		prefix_bytes := transmute([]u8)prefix
		strings.write_bytes(&builder, prefix_bytes[:len(prefix) - 1])
		strings.write_byte(&builder, last + 1)
	} else {
		strings.write_string(&builder, prefix)
		strings.write_byte(&builder, 0xff)
	}
	return strings.to_string(builder)
}

data_store_take_error :: proc(err: ^cstring) -> string {
	if err == nil || err^ == nil {
		return ""
	}
	message, _ := strings.clone_from_cstring(err^)
	rocksdb.rocksdb_free(cast(rawptr)err^)
	err^ = nil
	return message
}

data_store_error :: proc(err: ^cstring, fallback: string) -> string {
	message := data_store_take_error(err)
	if message != "" {
		return message
	}
	return strings.clone(fallback)
}

data_store_ensure_db :: proc(service: ^DataStoreService) -> string {
	if service == nil || service.destroyed {
		return strings.clone("DataStoreService is unavailable")
	}
	if !data_store_mode_allowed(service) {
		return strings.clone(
			"DataStoreService: DataStores are only available to the server runtime",
		)
	}
	if service.db != nil {
		return ""
	}

	path := os.get_env("KINEMIUM_DATASTORE_PATH", context.temp_allocator)
	if path == "" {
		path = DATASTORE_DEFAULT_PATH
	}
	_ = os.make_directory_all(path)

	options := rocksdb.rocksdb_options_create()
	if options == nil {
		return strings.clone("DataStoreService: could not create RocksDB options")
	}
	defer rocksdb.rocksdb_options_destroy(options)
	rocksdb.rocksdb_options_set_create_if_missing(options, 1)

	c_path := strings.clone_to_cstring(path, context.temp_allocator)
	err: cstring
	db := rocksdb.rocksdb_open(options, c_path, &err)
	if db == nil {
		return data_store_error(&err, "DataStoreService: could not open the RocksDB database")
	}

	service.db = db
	service.path = strings.clone(path)
	return ""
}

data_store_get_bytes :: proc(
	service: ^DataStoreService,
	key: string,
) -> (
	value: string,
	found: bool,
	err: string,
) {
	options := rocksdb.rocksdb_readoptions_create()
	if options == nil {
		return "", false, strings.clone("DataStoreService: could not create RocksDB read options")
	}
	defer rocksdb.rocksdb_readoptions_destroy(options)

	value_len: uint
	c_err: cstring
	ptr := rocksdb.rocksdb_get(
		service.db,
		options,
		raw_data(key),
		uint(len(key)),
		&value_len,
		&c_err,
	)
	if c_err != nil {
		return "", false, data_store_take_error(&c_err)
	}
	if ptr == nil {
		return "", false, ""
	}

	value = strings.clone(string(ptr[:int(value_len)]))
	rocksdb.rocksdb_free(cast(rawptr)ptr)
	return value, true, ""
}

data_store_put_bytes :: proc(service: ^DataStoreService, key: string, value: string) -> string {
	options := rocksdb.rocksdb_writeoptions_create()
	if options == nil {
		return strings.clone("DataStoreService: could not create RocksDB write options")
	}
	defer rocksdb.rocksdb_writeoptions_destroy(options)

	c_err: cstring
	rocksdb.rocksdb_put(
		service.db,
		options,
		raw_data(key),
		uint(len(key)),
		raw_data(value),
		uint(len(value)),
		&c_err,
	)
	if c_err != nil {
		return data_store_take_error(&c_err)
	}
	return ""
}

data_store_write_batch :: proc(
	service: ^DataStoreService,
	batch: ^rocksdb.rocksdb_writebatch_t,
) -> string {
	options := rocksdb.rocksdb_writeoptions_create()
	if options == nil {
		return strings.clone("DataStoreService: could not create RocksDB write options")
	}
	defer rocksdb.rocksdb_writeoptions_destroy(options)

	c_err: cstring
	rocksdb.rocksdb_write(service.db, options, batch, &c_err)
	if c_err != nil {
		return data_store_take_error(&c_err)
	}
	return ""
}

data_store_encode_record :: proc(record: ^DataStore_Record) -> (encoded: string, err: string) {
	data, marshal_err := json.marshal(
		record^,
		json.Marshal_Options{spec = .JSON, sort_maps_by_key = true},
		context.temp_allocator,
	)
	if marshal_err != nil {
		return "", fmt.aprintf("DataStore record could not be encoded: %v", marshal_err)
	}
	return strings.clone(string(data)), ""
}

data_store_decode_record :: proc(data: string) -> (record: DataStore_Record, ok: bool) {
	if json.unmarshal_string(data, &record) != nil {
		return DataStore_Record{}, false
	}
	if record.metadata == "" {
		record.metadata = strings.clone("{}")
	}
	if record.user_ids == "" {
		record.user_ids = strings.clone("[]")
	}
	return record, true
}

data_store_free_record :: proc(record: ^DataStore_Record) {
	delete(record.key)
	delete(record.value)
	delete(record.metadata)
	delete(record.user_ids)
	record^ = DataStore_Record{}
}

data_store_read_current :: proc(
	service: ^DataStoreService,
	name, scope, key: string,
) -> (
	record: DataStore_Record,
	found: bool,
	err: string,
) {
	record_key := data_store_key_record(name, scope, key)
	defer delete(record_key)

	raw, exists, read_err := data_store_get_bytes(service, record_key)
	if read_err != "" {
		return DataStore_Record{}, false, read_err
	}
	if !exists {
		return DataStore_Record{}, false, ""
	}
	defer delete(raw)

	decoded, ok := data_store_decode_record(raw)
	if !ok {
		return DataStore_Record{}, false, strings.clone("DataStore record is corrupt")
	}
	return decoded, true, ""
}

data_store_read_version :: proc(
	service: ^DataStoreService,
	name, scope, key: string,
	version: i64,
) -> (
	record: DataStore_Record,
	found: bool,
	err: string,
) {
	version_key := data_store_key_version(name, scope, key, version)
	defer delete(version_key)

	raw, exists, read_err := data_store_get_bytes(service, version_key)
	if read_err != "" {
		return DataStore_Record{}, false, read_err
	}
	if !exists {
		return DataStore_Record{}, false, ""
	}
	defer delete(raw)

	decoded, ok := data_store_decode_record(raw)
	if !ok {
		return DataStore_Record{}, false, strings.clone("DataStore version record is corrupt")
	}
	return decoded, true, ""
}

data_store_value_sort_value :: proc(value_json: string) -> (value: f64, ok: bool) {
	parsed, parse_err := json.parse_string(
		value_json,
		parse_integers = false,
		allocator = context.temp_allocator,
	)
	if parse_err != nil {
		return 0, false
	}
	defer json.destroy_value(parsed, context.temp_allocator)

	#partial switch number in parsed {
	case json.Float:
		return f64(number), true
	case json.Integer:
		return f64(number), true
	}
	return 0, false
}

data_store_write_record :: proc(
	service: ^DataStoreService,
	name, scope: string,
	record: ^DataStore_Record,
	old: ^DataStore_Record,
	has_old: bool,
	include_version: bool,
) -> string {
	encoded, encode_err := data_store_encode_record(record)
	if encode_err != "" {
		return encode_err
	}
	defer delete(encoded)

	batch := rocksdb.rocksdb_writebatch_create()
	if batch == nil {
		return strings.clone("DataStoreService: could not create a RocksDB write batch")
	}
	defer rocksdb.rocksdb_writebatch_destroy(batch)

	current_key := data_store_key_record(name, scope, record.key)
	defer delete(current_key)
	rocksdb.rocksdb_writebatch_put(
		batch,
		raw_data(current_key),
		uint(len(current_key)),
		raw_data(encoded),
		uint(len(encoded)),
	)

	if include_version {
		version_key := data_store_key_version(name, scope, record.key, record.version)
		defer delete(version_key)
		rocksdb.rocksdb_writebatch_put(
			batch,
			raw_data(version_key),
			uint(len(version_key)),
			raw_data(encoded),
			uint(len(encoded)),
		)
	}

	if has_old && old.has_sort {
		old_sorted_key := data_store_key_sorted(name, scope, old.sort_value, old.key)
		defer delete(old_sorted_key)
		rocksdb.rocksdb_writebatch_delete(
			batch,
			raw_data(old_sorted_key),
			uint(len(old_sorted_key)),
		)
	}

	if record.has_sort {
		sorted_key := data_store_key_sorted(name, scope, record.sort_value, record.key)
		defer delete(sorted_key)
		rocksdb.rocksdb_writebatch_put(
			batch,
			raw_data(sorted_key),
			uint(len(sorted_key)),
			raw_data(encoded),
			uint(len(encoded)),
		)
	}

	return data_store_write_batch(service, batch)
}

data_store_get_async :: proc(L: ^vm.State, handle: ^DataStore_Handle, key: string) -> (i32, bool) {
	if key == "" {
		return data_store_raise(L, "DataStore:GetAsync requires a key")
	}

	sync.mutex_lock(&handle.service.mutex)
	defer sync.mutex_unlock(&handle.service.mutex)

	if err := data_store_ensure_db(handle.service); err != "" {
		return data_store_raise_owned(L, err)
	}

	record, found, err := data_store_read_current(handle.service, handle.name, handle.scope, key)
	if err != "" {
		return data_store_raise_owned(L, err)
	}
	if !found {
		vm.PushNil(L)
		vm.PushNil(L)
		return 2, true
	}
	defer data_store_free_record(&record)

	data_store_push_value_text(L, handle.datatypes_registry, handle.enums_registry, record.value)
	data_store_push_key_info(
		L,
		record.version,
		record.created_time,
		record.updated_time,
		record.metadata,
		record.user_ids,
	)
	return 2, true
}

data_store_set_async :: proc(L: ^vm.State, handle: ^DataStore_Handle, key: string) -> (i32, bool) {
	if key == "" {
		return data_store_raise(L, "DataStore:SetAsync requires a key")
	}

	value_json, encode_err := data_store_encode_value(L, 3)
	if encode_err != "" {
		return data_store_raise(L, encode_err)
	}
	defer delete(value_json)

	user_ids_json: string
	if vm.IsTable(L, 4) {
		encoded, err := data_store_encode_value(L, 4)
		if err != "" {
			return data_store_raise(L, err)
		}
		user_ids_json = encoded
	} else {
		user_ids_json = strings.clone("[]")
	}
	defer delete(user_ids_json)

	sync.mutex_lock(&handle.service.mutex)
	defer sync.mutex_unlock(&handle.service.mutex)

	if err := data_store_ensure_db(handle.service); err != "" {
		return data_store_raise_owned(L, err)
	}

	old, found, read_err := data_store_read_current(handle.service, handle.name, handle.scope, key)
	if read_err != "" {
		return data_store_raise_owned(L, read_err)
	}
	defer data_store_free_record(&old)
	now := data_store_now()
	sort_value, has_sort := data_store_value_sort_value(value_json)
	record := DataStore_Record {
		key          = strings.clone(key),
		value        = strings.clone(value_json),
		version      = found ? old.version + 1 : 1,
		created_time = found ? old.created_time : now,
		updated_time = now,
		metadata     = strings.clone(found ? old.metadata : "{}"),
		user_ids     = strings.clone(user_ids_json),
		sort_value   = sort_value,
		has_sort     = has_sort,
	}
	defer data_store_free_record(&record)

	if err := data_store_write_record(
		handle.service,
		handle.name,
		handle.scope,
		&record,
		&old,
		found,
		true,
	); err != "" {
		return data_store_raise_owned(L, err)
	}

	return 0, true
}

data_store_update_async :: proc(
	L: ^vm.State,
	handle: ^DataStore_Handle,
	key: string,
) -> (
	i32,
	bool,
) {
	if key == "" {
		return data_store_raise(L, "DataStore:UpdateAsync requires a key")
	}
	if !vm.IsFunction(L, 3) {
		return data_store_raise(L, "DataStore:UpdateAsync requires a transform function")
	}

	sync.mutex_lock(&handle.service.mutex)
	defer sync.mutex_unlock(&handle.service.mutex)

	if err := data_store_ensure_db(handle.service); err != "" {
		return data_store_raise_owned(L, err)
	}

	old, found, read_err := data_store_read_current(handle.service, handle.name, handle.scope, key)
	if read_err != "" {
		return data_store_raise_owned(L, read_err)
	}
	defer data_store_free_record(&old)

	vm.PushValue(L, 3)
	if found {
		data_store_push_value_text(L, handle.datatypes_registry, handle.enums_registry, old.value)
	} else {
		vm.PushNil(L)
	}

	call_ok, call_err := vm.ProtectedCall(L, 1, 1)
	if !call_ok {
		return data_store_raise_owned(L, call_err)
	}

	if vm.IsNoneOrNil(L, -1) {
		vm.Pop(L)
		vm.PushNil(L)
		return 1, true
	}

	new_json, encode_err := data_store_encode_value(L, -1)
	vm.Pop(L)
	if encode_err != "" {
		return data_store_raise(L, encode_err)
	}
	defer delete(new_json)

	now := data_store_now()
	sort_value, has_sort := data_store_value_sort_value(new_json)
	record := DataStore_Record {
		key          = strings.clone(key),
		value        = strings.clone(new_json),
		version      = found ? old.version + 1 : 1,
		created_time = found ? old.created_time : now,
		updated_time = now,
		metadata     = strings.clone(found ? old.metadata : "{}"),
		user_ids     = strings.clone(found ? old.user_ids : "[]"),
		sort_value   = sort_value,
		has_sort     = has_sort,
	}
	defer data_store_free_record(&record)

	if err := data_store_write_record(
		handle.service,
		handle.name,
		handle.scope,
		&record,
		&old,
		found,
		true,
	); err != "" {
		return data_store_raise_owned(L, err)
	}

	data_store_push_value_text(L, handle.datatypes_registry, handle.enums_registry, new_json)
	data_store_push_key_info(
		L,
		record.version,
		record.created_time,
		record.updated_time,
		record.metadata,
		record.user_ids,
	)
	return 2, true
}

data_store_remove_async :: proc(
	L: ^vm.State,
	handle: ^DataStore_Handle,
	key: string,
) -> (
	i32,
	bool,
) {
	if key == "" {
		return data_store_raise(L, "DataStore:RemoveAsync requires a key")
	}

	sync.mutex_lock(&handle.service.mutex)
	defer sync.mutex_unlock(&handle.service.mutex)

	if err := data_store_ensure_db(handle.service); err != "" {
		return data_store_raise_owned(L, err)
	}

	record, found, read_err := data_store_read_current(
		handle.service,
		handle.name,
		handle.scope,
		key,
	)
	if read_err != "" {
		return data_store_raise_owned(L, read_err)
	}
	if !found {
		vm.PushNil(L)
		return 1, true
	}
	defer data_store_free_record(&record)

	batch := rocksdb.rocksdb_writebatch_create()
	if batch == nil {
		return data_store_raise(L, "DataStoreService: could not create a RocksDB write batch")
	}
	defer rocksdb.rocksdb_writebatch_destroy(batch)

	current_key := data_store_key_record(handle.name, handle.scope, key)
	defer delete(current_key)
	rocksdb.rocksdb_writebatch_delete(batch, raw_data(current_key), uint(len(current_key)))

	if record.has_sort {
		sorted_key := data_store_key_sorted(handle.name, handle.scope, record.sort_value, key)
		defer delete(sorted_key)
		rocksdb.rocksdb_writebatch_delete(batch, raw_data(sorted_key), uint(len(sorted_key)))
	}

	if err := data_store_write_batch(handle.service, batch); err != "" {
		return data_store_raise_owned(L, err)
	}

	data_store_push_value_text(L, handle.datatypes_registry, handle.enums_registry, record.value)
	data_store_push_key_info(
		L,
		record.version,
		record.created_time,
		record.updated_time,
		record.metadata,
		record.user_ids,
	)
	return 2, true
}

data_store_increment_async :: proc(
	L: ^vm.State,
	handle: ^DataStore_Handle,
	key: string,
) -> (
	i32,
	bool,
) {
	if key == "" {
		return data_store_raise(L, "DataStore:IncrementAsync requires a key")
	}

	delta := vm.ArgNumber(L, 3)
	if delta != delta {
		return data_store_raise(L, "DataStore:IncrementAsync delta must be a number")
	}

	sync.mutex_lock(&handle.service.mutex)
	defer sync.mutex_unlock(&handle.service.mutex)

	if err := data_store_ensure_db(handle.service); err != "" {
		return data_store_raise_owned(L, err)
	}

	old, found, read_err := data_store_read_current(handle.service, handle.name, handle.scope, key)
	if read_err != "" {
		return data_store_raise_owned(L, read_err)
	}
	defer data_store_free_record(&old)

	base := f64(0)
	if found && old.has_sort {
		base = old.sort_value
	}
	new_value := base + delta
	now := data_store_now()

	record := DataStore_Record {
		key          = strings.clone(key),
		value        = fmt.aprintf("%v", new_value),
		version      = found ? old.version + 1 : 1,
		created_time = found ? old.created_time : now,
		updated_time = now,
		metadata     = strings.clone(found ? old.metadata : "{}"),
		user_ids     = strings.clone(found ? old.user_ids : "[]"),
		sort_value   = new_value,
		has_sort     = true,
	}
	defer data_store_free_record(&record)

	if err := data_store_write_record(
		handle.service,
		handle.name,
		handle.scope,
		&record,
		&old,
		found,
		true,
	); err != "" {
		return data_store_raise_owned(L, err)
	}

	data_store_push_value_text(L, handle.datatypes_registry, handle.enums_registry, record.value)
	data_store_push_key_info(
		L,
		record.version,
		record.created_time,
		record.updated_time,
		record.metadata,
		record.user_ids,
	)
	return 2, true
}

data_store_get_version_async :: proc(
	L: ^vm.State,
	handle: ^DataStore_Handle,
	key: string,
) -> (
	i32,
	bool,
) {
	if key == "" {
		return data_store_raise(L, "DataStore:GetVersionAsync requires a key")
	}

	version_text := vm.ArgString(L, 3)
	version, version_ok := strconv.parse_i64(version_text)
	if !version_ok {
		return data_store_raise(L, "DataStore:GetVersionAsync requires a valid version")
	}

	sync.mutex_lock(&handle.service.mutex)
	defer sync.mutex_unlock(&handle.service.mutex)

	if err := data_store_ensure_db(handle.service); err != "" {
		return data_store_raise_owned(L, err)
	}

	record, found, read_err := data_store_read_version(
		handle.service,
		handle.name,
		handle.scope,
		key,
		version,
	)
	if read_err != "" {
		return data_store_raise_owned(L, read_err)
	}
	if !found {
		vm.PushNil(L)
		vm.PushNil(L)
		return 2, true
	}
	defer data_store_free_record(&record)

	data_store_push_value_text(L, handle.datatypes_registry, handle.enums_registry, record.value)
	data_store_push_key_info(
		L,
		record.version,
		record.created_time,
		record.updated_time,
		record.metadata,
		record.user_ids,
	)
	return 2, true
}

data_store_page_entry_from_record :: proc(record: ^DataStore_Record) -> DataStore_Page_Entry {
	return DataStore_Page_Entry {
		key = record.key,
		value = record.value,
		version = record.version,
		created_time = record.created_time,
		updated_time = record.updated_time,
		metadata = record.metadata,
		user_ids = record.user_ids,
		sort_value = record.sort_value,
	}
}

data_store_list_versions_async :: proc(
	L: ^vm.State,
	handle: ^DataStore_Handle,
	key: string,
) -> (
	i32,
	bool,
) {
	if key == "" {
		return data_store_raise(L, "DataStore:ListVersionsAsync requires a key")
	}

	sync.mutex_lock(&handle.service.mutex)
	defer sync.mutex_unlock(&handle.service.mutex)

	if err := data_store_ensure_db(handle.service); err != "" {
		return data_store_raise_owned(L, err)
	}

	page_size := int(vm.ArgOptionalNumber(L, 6, 25))
	if page_size < 1 {
		page_size = 1
	}
	if page_size > DATASTORE_MAX_PAGE_SIZE {
		page_size = DATASTORE_MAX_PAGE_SIZE
	}

	sort_direction := vm.ArgOptionalString(L, 3, "")
	descending := strings.contains(sort_direction, "Descending")

	has_min_date := !vm.IsNoneOrNil(L, 4)
	min_date := has_min_date ? vm.ArgNumber(L, 4) : 0
	has_max_date := !vm.IsNoneOrNil(L, 5)
	max_date := has_max_date ? vm.ArgNumber(L, 5) : 0

	prefix_builder := data_store_prefix_builder('v', handle.name, handle.scope)
	data_store_append_component(&prefix_builder, key)
	prefix := strings.to_string(prefix_builder)
	defer delete(prefix)

	read_options := rocksdb.rocksdb_readoptions_create()
	if read_options == nil {
		return data_store_raise(L, "DataStoreService: could not create RocksDB read options")
	}
	defer rocksdb.rocksdb_readoptions_destroy(read_options)

	iter := rocksdb.rocksdb_create_iterator(handle.service.db, read_options)
	if iter == nil {
		return data_store_raise(L, "DataStoreService: could not create a RocksDB iterator")
	}
	defer rocksdb.rocksdb_iter_destroy(iter)

	entries := make([dynamic]DataStore_Page_Entry, 0, 16)

	rocksdb.rocksdb_iter_seek(iter, raw_data(prefix), uint(len(prefix)))
	for rocksdb.rocksdb_iter_valid(iter) != 0 {
		key_len: uint
		key_ptr := rocksdb.rocksdb_iter_key(iter, &key_len)
		current_key := string(key_ptr[:int(key_len)])
		if !strings.has_prefix(current_key, prefix) {
			break
		}

		value_len: uint
		value_ptr := rocksdb.rocksdb_iter_value(iter, &value_len)
		raw := strings.clone(string(value_ptr[:int(value_len)]))
		decoded, ok := data_store_decode_record(raw)
		delete(raw)
		if ok {
			include := true
			if has_min_date && decoded.created_time < min_date {
				include = false
			}
			if has_max_date && decoded.created_time > max_date {
				include = false
			}
			if include {
				append(&entries, data_store_page_entry_from_record(&decoded))
			} else {
				data_store_free_record(&decoded)
			}
		}

		rocksdb.rocksdb_iter_next(iter)
	}

	slice.sort_by(entries[:], proc(a, b: DataStore_Page_Entry) -> bool {
		if a.created_time != b.created_time {
			return a.created_time < b.created_time
		}
		return a.version < b.version
	})
	if descending {
		slice.reverse(entries[:])
	}

	pages := new(DataStore_Pages)
	pages^ = DataStore_Pages {
		entries            = entries[:],
		page_size          = page_size,
		page               = 0,
		datatypes_registry = handle.datatypes_registry,
		enums_registry     = handle.enums_registry,
	}
	vm.PushUserdata(&vm.VM{L = L}, pages, &data_store_pages_binding)
	return 1, true
}

data_store_remove_version_async :: proc(
	L: ^vm.State,
	handle: ^DataStore_Handle,
	key: string,
) -> (
	i32,
	bool,
) {
	if key == "" {
		return data_store_raise(L, "DataStore:RemoveVersionAsync requires a key")
	}

	version_text := vm.ArgString(L, 3)
	version, version_ok := strconv.parse_i64(version_text)
	if !version_ok {
		return data_store_raise(L, "DataStore:RemoveVersionAsync requires a valid version")
	}

	sync.mutex_lock(&handle.service.mutex)
	defer sync.mutex_unlock(&handle.service.mutex)

	if err := data_store_ensure_db(handle.service); err != "" {
		return data_store_raise_owned(L, err)
	}

	batch := rocksdb.rocksdb_writebatch_create()
	if batch == nil {
		return data_store_raise(L, "DataStoreService: could not create a RocksDB write batch")
	}
	defer rocksdb.rocksdb_writebatch_destroy(batch)

	version_key := data_store_key_version(handle.name, handle.scope, key, version)
	defer delete(version_key)
	rocksdb.rocksdb_writebatch_delete(batch, raw_data(version_key), uint(len(version_key)))

	if err := data_store_write_batch(handle.service, batch); err != "" {
		return data_store_raise_owned(L, err)
	}
	return 0, true
}

data_store_get_sorted_async :: proc(L: ^vm.State, handle: ^DataStore_Handle) -> (i32, bool) {
	if !handle.ordered {
		return data_store_raise(
			L,
			"DataStore:GetSortedAsync is only available on OrderedDataStore",
		)
	}

	sync.mutex_lock(&handle.service.mutex)
	defer sync.mutex_unlock(&handle.service.mutex)

	if err := data_store_ensure_db(handle.service); err != "" {
		return data_store_raise_owned(L, err)
	}

	ascending := vm.ArgOptionalBoolean(L, 2, true)
	page_size := int(vm.ArgOptionalNumber(L, 3, 25))
	if page_size < 1 {
		page_size = 1
	}
	if page_size > DATASTORE_MAX_PAGE_SIZE {
		page_size = DATASTORE_MAX_PAGE_SIZE
	}

	has_min_value := !vm.IsNoneOrNil(L, 4)
	min_value := has_min_value ? vm.ArgNumber(L, 4) : 0
	has_max_value := !vm.IsNoneOrNil(L, 5)
	max_value := has_max_value ? vm.ArgNumber(L, 5) : 0

	prefix := strings.to_string(data_store_prefix_builder('s', handle.name, handle.scope))
	defer delete(prefix)

	read_options := rocksdb.rocksdb_readoptions_create()
	if read_options == nil {
		return data_store_raise(L, "DataStoreService: could not create RocksDB read options")
	}
	defer rocksdb.rocksdb_readoptions_destroy(read_options)

	iter := rocksdb.rocksdb_create_iterator(handle.service.db, read_options)
	if iter == nil {
		return data_store_raise(L, "DataStoreService: could not create a RocksDB iterator")
	}
	defer rocksdb.rocksdb_iter_destroy(iter)

	entries := make([dynamic]DataStore_Page_Entry, 0, 16)

	rocksdb.rocksdb_iter_seek(iter, raw_data(prefix), uint(len(prefix)))
	for rocksdb.rocksdb_iter_valid(iter) != 0 {
		key_len: uint
		key_ptr := rocksdb.rocksdb_iter_key(iter, &key_len)
		current_key := string(key_ptr[:int(key_len)])
		if !strings.has_prefix(current_key, prefix) {
			break
		}

		value_len: uint
		value_ptr := rocksdb.rocksdb_iter_value(iter, &value_len)
		raw := strings.clone(string(value_ptr[:int(value_len)]))
		decoded, ok := data_store_decode_record(raw)
		delete(raw)
		if ok {
			include := decoded.has_sort
			if include && has_min_value && decoded.sort_value < min_value {
				include = false
			}
			if include && has_max_value && decoded.sort_value > max_value {
				include = false
			}
			if include {
				append(&entries, data_store_page_entry_from_record(&decoded))
			} else {
				data_store_free_record(&decoded)
			}
		}

		rocksdb.rocksdb_iter_next(iter)
	}

	slice.sort_by(entries[:], proc(a, b: DataStore_Page_Entry) -> bool {
		if a.sort_value != b.sort_value {
			return a.sort_value < b.sort_value
		}
		return a.key < b.key
	})
	if !ascending {
		slice.reverse(entries[:])
	}

	pages := new(DataStore_Pages)
	pages^ = DataStore_Pages {
		entries            = entries[:],
		page_size          = page_size,
		page               = 0,
		datatypes_registry = handle.datatypes_registry,
		enums_registry     = handle.enums_registry,
	}
	vm.PushUserdata(&vm.VM{L = L}, pages, &data_store_pages_binding)
	return 1, true
}

data_store_remove_all :: proc(service: ^DataStoreService, name: string, scope: string) -> string {
	sync.mutex_lock(&service.mutex)
	defer sync.mutex_unlock(&service.mutex)

	if err := data_store_ensure_db(service); err != "" {
		return err
	}

	batch := rocksdb.rocksdb_writebatch_create()
	if batch == nil {
		return strings.clone("DataStoreService: could not create a RocksDB write batch")
	}
	defer rocksdb.rocksdb_writebatch_destroy(batch)

	prefixes := [3]u8{'d', 'v', 's'}
	for kind in prefixes {
		prefix := strings.to_string(data_store_prefix_builder(kind, name, scope))
		end := data_store_prefix_end(prefix)
		rocksdb.rocksdb_writebatch_delete_range(
			batch,
			raw_data(prefix),
			uint(len(prefix)),
			raw_data(end),
			uint(len(end)),
		)
		delete(prefix)
		delete(end)
	}

	return data_store_write_batch(service, batch)
}
