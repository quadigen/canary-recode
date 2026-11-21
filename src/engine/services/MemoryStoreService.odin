package services


import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

MEMORY_STORE_TAG :: 54
MEMORY_STORE_MAX_CONTAINERS :: 128
MEMORY_STORE_MAX_ENTRIES :: 4096
MEMORY_STORE_MAX_VALUE :: 32 * 1024
MEMORY_STORE_MAX_BYTES :: 32 * 1024 * 1024
MEMORY_STORE_MAX_EXPIRATION :: 45 * 24 * 60 * 60

MemoryStoreService_Class := classes.Class_Info {
	name   = "MemoryStoreService",
	parent = &Service_Class,
}
Memory_Kind :: enum {
	Hash,
	Sorted,
	Queue,
}
Memory_Value :: struct {
	kind:    vm.Value_Type,
	number:  f64,
	integer: i64,
	text:    string,
	items:   [dynamic]Memory_Value,
}
Memory_Entry :: struct {
	key:                      string,
	value:                    Memory_Value,
	sort:                     Memory_Value,
	size:                     int,
	expires, invisible_until: time.Tick,
	sequence, receipt:        i64,
	priority:                 f64,
}
Memory_Container :: struct {
	owner:        ^MemoryStoreService,
	refs:         int,
	kind:         Memory_Kind,
	name:         string,
	entries:      map[string]Memory_Entry,
	queue:        [dynamic]Memory_Entry,
	invisibility: f64,
	sequence:     i64,
	updating:     bool,
	next_prune:   time.Tick,
}
MemoryStoreService :: struct {
	using service: Service,
	containers:    [dynamic]^Memory_Container,
	bytes_used:    int,
	next_receipt:  i64,
}
memory_store_binding := vm.Userdata_Binding {
	name     = "MemoryStore",
	tag      = MEMORY_STORE_TAG,
	get      = memory_store_handle_get,
	namecall = memory_store_handle_call,
	destroy  = memory_store_handle_destroy,
}

memory_value_free :: proc(v: ^Memory_Value) {
	delete(v.text)
	for &item in v.items {memory_value_free(&item)}
	delete(v.items)
	v^ = {}
}


memory_value_capture :: proc(
	L: ^vm.State,
	index, depth: int,
	budget: ^int,
	v: ^Memory_Value,
) -> bool {
	if depth > 16 || !vm.CheckStack(L, 8) || budget^ < size_of(Memory_Value) {return false}
	budget^ -= size_of(Memory_Value)
	v.kind = vm.TypeOf(L, index)
	#partial switch v.kind {
	case .Boolean:
		v.integer = vm.ArgBoolean(L, index) ? 1 : 0
	case .Integer:
		v.integer = vm.ArgInteger(L, index)
	case .Number:
		v.number = vm.ArgNumber(L, index)
		if math.is_nan(v.number) || math.is_inf(v.number) {return false}
	case .String:
		s, _ := vm.ToString(L, index)
		if len(s) > budget^ {return false}
		budget^ -= len(s)
		v.text = strings.clone(s)
	case .Table:
		top := vm.StackTop(L)
		defer vm.SetStackTop(L, top)
		vm.PushNil(L)
		for vm.Next(L, index) {
			k: Memory_Value
			item: Memory_Value
			ki := vm.StackTop(L) - 1
			kt := vm.TypeOf(L, ki)
			if kt == .String {
				text, _ := vm.ToString(L, ki)
				if strings.contains(text, "\x00") {return false}
			} else if kt == .Number || kt == .Integer {
				n := vm.ArgNumber(L, ki)
				if n < -2147483648 || n > 2147483647 || n != math.floor(n) {return false}
			} else {return false}
			if !memory_value_capture(L, ki, depth + 1, budget, &k) {
				memory_value_free(&k)
				return false
			}
			if !memory_value_capture(L, ki + 1, depth + 1, budget, &item) {
				memory_value_free(&k)
				memory_value_free(&item)
				return false
			}
			append(&v.items, k, item)
			vm.Pop(L)
		}
	case:
		return false
	}
	return true
}

memory_value_push :: proc(L: ^vm.State, v: ^Memory_Value) {
	#partial switch v.kind {
	case .Boolean:
		vm.PushBoolean(L, v.integer != 0)
	case .Integer:
		vm.PushInteger(L, v.integer)
	case .Number:
		vm.PushNumber(L, v.number)
	case .String:
		vm.PushString(L, v.text)
	case .Table:
		vm.NewTable(L)
		for i := 0; i < len(v.items); i += 2 {
			key := &v.items[i]
			memory_value_push(L, &v.items[i + 1])
			if key.kind ==
			   .String {vm.SetField(L, -2, key.text)} else {vm.SetArrayValue(L, -2, key.kind == .Integer ? int(key.integer) : int(key.number))}
		}
	case:
		vm.PushNil(L)
	}
}
memory_store_error :: proc(L: ^vm.State, message: string) -> (i32, bool) {
	return vm.RaiseError(L, message), true
}
memory_store_allowed :: proc(service: ^MemoryStoreService) -> bool {
	if service == nil ||
	   service.destroyed ||
	   service.data_model == nil ||
	   service.data_model.registry == nil {return false}
	mode := service.data_model.registry.mode
	return mode != .Client && mode != .Editor
}
memory_store_text :: proc(L: ^vm.State, i: int) -> (string, bool) {
	s, ok := vm.ToString(L, i)
	return s, ok && len(s) > 0 && len(s) <= 128
}
memory_store_number :: proc(L: ^vm.State, i: int, min_value, max_value: f64) -> (f64, bool) {
	t := vm.TypeOf(L, i)
	if t != .Number && t != .Integer {return 0, false}
	n := vm.ArgNumber(L, i)
	return n, !math.is_nan(n) && !math.is_inf(n) && n >= min_value && n <= max_value
}
memory_store_expiry :: proc(L: ^vm.State, i: int) -> (time.Tick, bool) {
	n, ok := memory_store_number(L, i, 0.000001, MEMORY_STORE_MAX_EXPIRATION)
	if !ok {return {}, false}
	return time.tick_add(time.tick_now(), time.Duration(n * f64(time.Second))), true
}
memory_entry_free :: proc(store: ^Memory_Container, entry: ^Memory_Entry) {
	store.owner.bytes_used -= entry.size
	delete(entry.key)
	memory_value_free(&entry.value)
	memory_value_free(&entry.sort)
}
memory_store_prune :: proc(store: ^Memory_Container) {
	now := time.tick_now()
	store.next_prune = time.tick_add(now, time.Second)
	if store.kind == .Queue {
		i := 0
		for i < len(store.queue) {
			if time.tick_diff(store.queue[i].expires, now) >= 0 {
				memory_entry_free(store, &store.queue[i])
				unordered_remove(&store.queue, i)
			} else {i += 1}
		}
	} else {
		for key, entry in store.entries {
			if time.tick_diff(entry.expires, now) >= 0 {
				old := entry
				delete_key(&store.entries, key)
				memory_entry_free(store, &old)
			}
		}
	}
}
memory_store_prune_all :: proc(service: ^MemoryStoreService) {
	for store in service.containers {
		if !store.updating {memory_store_prune(store)}
	}
}
memory_store_release :: proc(store: ^Memory_Container) {
	store.refs -= 1
	if store.refs == 0 {
		delete(store.name)
		free(store)
	}
}
memory_store_handle_destroy :: proc(value, ctx: rawptr) {
	memory_store_release(cast(^Memory_Container)value)
}
memory_store_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(MemoryStoreService)
	service.service = Service_Init(&MemoryStoreService_Class, "MemoryStoreService", data_model)
	return &service.object
}
memory_store_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "GetMap",
	     "GetSortedMap",
	     "GetQueue",
	     "GetHashMap",
	     "CreateQueue",
	     "CreateHashMap",
	     "CreateMemoryStore",
	     "CreateSortedMap",
	     "CreateMemoryQueue":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}
memory_store_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^MemoryStoreService)object
	kind: Memory_Kind
	switch method {
	case "GetMap", "GetHashMap", "CreateMemoryStore", "CreateHashMap":
		kind = .Hash
	case "GetSortedMap", "CreateSortedMap":
		kind = .Sorted
	case "GetQueue", "CreateQueue", "CreateMemoryQueue":
		kind = .Queue
	case:
		return 0, false
	}
	if !memory_store_allowed(
		service,
	) {return memory_store_error(L, "MemoryStoreService requires a server runtime")}
	name, ok := memory_store_text(L, 2)
	if !ok {return memory_store_error(L, "MemoryStore name must be a nonempty string of at most 128 bytes")}
	invisibility: f64 = 30
	if kind == .Queue && !vm.IsNoneOrNil(L, 3) {
		invisibility, ok = memory_store_number(L, 3, 0, 43200)
		if !ok {return memory_store_error(L, "Invalid queue invisibility timeout")}
	}
	for store in service.containers {
		if store.kind == kind && store.name == name {
			if kind == .Queue && !vm.IsNoneOrNil(L, 3) && invisibility != store.invisibility {
				return memory_store_error(L, "Queue already has a different invisibility timeout")
			}
			store.refs += 1
			vm.PushUserdata(&vm.VM{L = L}, store, &memory_store_binding)
			return 1, true
		}
	}
	if len(service.containers) >=
	   MEMORY_STORE_MAX_CONTAINERS {return memory_store_error(L, "MemoryStore container limit exceeded")}
	store := new(Memory_Container)
	store^ = {
		owner        = service,
		refs         = 2,
		kind         = kind,
		name         = strings.clone(name),
		invisibility = invisibility,
	}
	if kind != .Queue {store.entries = make(map[string]Memory_Entry)}
	append(&service.containers, store)
	vm.PushUserdata(&vm.VM{L = L}, store, &memory_store_binding)
	return 1, true
}
memory_store_handle_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	store := cast(^Memory_Container)value
	switch key {
	case "Name":
		vm.PushString(L, store.name); return true
	case "DataStoreType":
		vm.PushString(L, "memory"); return true
	case "DataStoreTypeName":
		vm.PushString(L, "MemoryStore"); return true
	case "DataStoreCapacity":
		vm.PushInteger(L, MEMORY_STORE_MAX_ENTRIES); return true
	case "GetSizeAsync", "RemoveAsync":
		vm.PushUserdataMethod(L, key); return true
	case "GetAsync", "SetAsync", "UpdateAsync":
		if store.kind != .Queue {vm.PushUserdataMethod(L, key); return true}
	case "GetRangeAsync":
		if store.kind == .Sorted {vm.PushUserdataMethod(L, key); return true}
	case "AddAsync", "ReadAsync":
		if store.kind == .Queue {vm.PushUserdataMethod(L, key); return true}
	}
	return false
}
memory_store_sort_key :: proc(L: ^vm.State, index: int, budget: ^int, v: ^Memory_Value) -> bool {
	if vm.IsNoneOrNil(L, index) {return true}
	t := vm.TypeOf(L, index)
	if t != .Number && t != .Integer && t != .String {return false}
	return memory_value_capture(L, index, 0, budget, v)
}
memory_store_commit :: proc(store: ^Memory_Container, key: string, entry: ^Memory_Entry) -> bool {
	if store.owner.bytes_used + entry.size >
	   MEMORY_STORE_MAX_BYTES {memory_store_prune_all(store.owner)}
	if len(store.entries) >= MEMORY_STORE_MAX_ENTRIES {memory_store_prune(store)}
	old, found := store.entries[key]
	if !found && len(store.entries) >= MEMORY_STORE_MAX_ENTRIES {return false}
	if store.owner.bytes_used - old.size + entry.size > MEMORY_STORE_MAX_BYTES {return false}
	if found {
		entry.key = old.key
		old.key = ""
		memory_entry_free(store, &old)
	} else {entry.key = strings.clone(key)}
	store.entries[entry.key] = entry^
	store.owner.bytes_used += entry.size
	entry^ = {}
	return true
}
memory_store_capture_entry :: proc(
	L: ^vm.State,
	value_index, sort_index: int,
	store: ^Memory_Container,
	entry: ^Memory_Entry,
) -> bool {
	budget := MEMORY_STORE_MAX_VALUE
	ok := memory_value_capture(L, value_index, 0, &budget, &entry.value)
	if ok && store.kind == .Sorted && sort_index != 0 {
		ok = memory_store_sort_key(L, sort_index, &budget, &entry.sort)
	}
	entry.size = MEMORY_STORE_MAX_VALUE - budget + size_of(Memory_Entry) + 128
	return ok
}
memory_store_discard :: proc(entry: ^Memory_Entry) {
	memory_value_free(&entry.value)
	memory_value_free(&entry.sort)
}
memory_store_handle_call :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	store := cast(^Memory_Container)value
	if vm.ThreadIsParallel(
		L,
	) {return memory_store_error(L, "MemoryStore requires task.synchronize()")}
	if !memory_store_allowed(
		store.owner,
	) {return memory_store_error(L, "MemoryStore is no longer available in this runtime")}
	if store.updating {return memory_store_error(L, "Cannot access the same MemoryStore from its UpdateAsync callback")}
	if !vm.CheckStack(L, 48) {return memory_store_error(L, "Insufficient Luau stack space")}
	if store.kind == .Queue ||
	   method == "GetSizeAsync" ||
	   method == "GetRangeAsync" ||
	   time.tick_diff(store.next_prune, time.tick_now()) >= 0 {
		memory_store_prune(store)
	}
	if method == "GetSizeAsync" {
		vm.PushNumber(L, f64(len(store.entries) + len(store.queue)))
		return 1, true
	}
	if store.kind == .Queue {return memory_store_queue_call(L, store, method)}
	if method == "GetRangeAsync" && store.kind == .Sorted {return memory_store_range(L, store)}
	key, valid := memory_store_text(L, 2)
	if !valid {return memory_store_error(L, "MemoryStore key must be a nonempty string of at most 128 bytes")}
	old, found := store.entries[key]
	if found && time.tick_diff(old.expires, time.tick_now()) >= 0 {
		delete_key(&store.entries, key)
		memory_entry_free(store, &old)
		old = {}
		found = false
	}
	switch method {
	case "GetAsync":
		if !found {vm.PushNil(L); return 1, true}
		memory_value_push(L, &old.value)
		if store.kind == .Sorted {memory_value_push(L, &old.sort); return 2, true}
		return 1, true
	case "RemoveAsync":
		if found {
			delete_key(&store.entries, key)
			memory_entry_free(store, &old)
		}
		vm.PushBoolean(L, found)
		return 1, true
	case "SetAsync", "UpdateAsync":
		entry: Memory_Entry
		entry.expires, valid = memory_store_expiry(L, 4)
		if !valid {return memory_store_error(L, "Expiration must be positive and at most 45 days")}
		if method == "UpdateAsync" {
			if !vm.IsFunction(
				L,
				3,
			) {return memory_store_error(L, "UpdateAsync requires a transform function")}
			vm.PushValue(L, 3)
			memory_value_push(L, &old.value)
			nargs, nresults := 1, 1
			if store.kind == .Sorted {memory_value_push(L, &old.sort); nargs = 2; nresults = 2}
			store.updating = true
			ok, err := vm.ProtectedCall(L, nargs, nresults)
			store.updating = false
			if !ok {return vm.RaiseOwnedError(L, &err), true}
			if !memory_store_allowed(
				store.owner,
			) {return memory_store_error(L, "MemoryStore was destroyed during UpdateAsync")}
			index := vm.StackTop(L) - nresults + 1
			if vm.IsNoneOrNil(L, index) {vm.PushNil(L); return 1, true}
			if !memory_store_capture_entry(
				L,
				index,
				nresults == 2 ? index + 1 : 0,
				store,
				&entry,
			) {
				memory_store_discard(&entry)
				return memory_store_error(L, "Unsupported or oversized MemoryStore value")
			}
			entry.expires, _ = memory_store_expiry(L, 4)
		} else {
			if !memory_store_capture_entry(L, 3, 5, store, &entry) {
				memory_store_discard(&entry)
				return memory_store_error(L, "Unsupported or oversized MemoryStore value")
			}
		}
		if !memory_store_commit(store, key, &entry) {
			memory_store_discard(&entry)
			return memory_store_error(L, "MemoryStore capacity exceeded")
		}
		if method == "SetAsync" {vm.PushBoolean(L, true); return 1, true}
		current := store.entries[key]
		memory_value_push(L, &current.value)
		if store.kind == .Sorted {memory_value_push(L, &current.sort); return 2, true}
		return 1, true
	}
	return 0, false
}
memory_store_sort_compare :: proc(a, b: Memory_Value) -> int {
	if a.kind == .Nil || a.kind == .None {
		if b.kind == .Nil || b.kind == .None {return 0}
		return -1
	}
	if b.kind == .Nil || b.kind == .None {return 1}
	if a.kind == .String && b.kind == .String {
		if a.text < b.text {return -1}
		if a.text > b.text {return 1}
		return 0
	}
	if a.kind == .String {return 1}
	if b.kind == .String {return -1}
	if a.kind == .Integer && b.kind == .Integer {
		if a.integer < b.integer {return -1}
		if a.integer > b.integer {return 1}
		return 0
	}
	an := a.kind == .Integer ? f64(a.integer) : a.number
	bn := b.kind == .Integer ? f64(b.integer) : b.number
	if an < bn {return -1}
	if an > bn {return 1}
	return 0
}
memory_store_entry_less :: proc(a, b: Memory_Entry) -> bool {
	c := memory_store_sort_compare(a.sort, b.sort)
	if c == 0 {return a.key < b.key}
	return c < 0
}

memory_store_bound :: proc(L: ^vm.State, index: int) -> (bound: Memory_Entry, present, ok: bool) {
	if vm.IsNoneOrNil(L, index) {return {}, false, true}
	if vm.TypeOf(L, index) != .Table {return {}, true, false}
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	key_found := false
	vm.PushNil(L)
	for vm.Next(L, index) {
		ki := vm.StackTop(L) - 1
		if vm.TypeOf(L, ki) == .String {
			field, _ := vm.ToString(L, ki)
			switch field {
			case "key":
				bound.key, key_found = memory_store_text(L, ki + 1)
				if !key_found {return {}, true, false}
			case "sortKey":
				v := &bound.sort
				v.kind = vm.TypeOf(L, ki + 1)
				#partial switch v.kind {
				case .String:
					v.text, _ = vm.ToString(L, ki + 1)
				case .Integer:
					v.integer = vm.ArgInteger(L, ki + 1)
				case .Number:
					v.number = vm.ArgNumber(L, ki + 1)
					if math.is_nan(v.number) || math.is_inf(v.number) {return {}, true, false}
				case:
					return {}, true, false
				}
			}
		}
		vm.Pop(L)
	}
	return bound, true, key_found
}
memory_store_range :: proc(L: ^vm.State, store: ^Memory_Container) -> (i32, bool) {
	item := cast(^enums.Enum_Item)vm.UserdataValue(L, 2)

	binding := vm.UserdataBindingOf(L, 2)
	if binding == nil ||
	   binding.name != "EnumItem" ||
	   item == nil ||
	   item.enum_type == nil ||
	   item.enum_type.name != "SortDirection" {
		return memory_store_error(L, "GetRangeAsync requires Enum.SortDirection")
	}
	count, ok := memory_store_number(L, 3, 1, 200)
	if !ok ||
	   count !=
		   math.floor(
			   count,
		   ) {return memory_store_error(L, "Range count must be an integer from 1 to 200")}
	lower, has_lower, lower_ok := memory_store_bound(L, 4)
	if !lower_ok {return memory_store_error(L, "Invalid exclusive lower bound")}
	upper, has_upper, upper_ok := memory_store_bound(L, 5)
	if !upper_ok {return memory_store_error(L, "Invalid exclusive upper bound")}
	entries := make([dynamic]Memory_Entry, 0, len(store.entries))
	defer delete(entries)
	for _, entry in store.entries {
		if has_lower && !memory_store_entry_less(lower, entry) {continue}
		if has_upper && !memory_store_entry_less(entry, upper) {continue}
		append(&entries, entry)
	}
	slice.sort_by(entries[:], memory_store_entry_less)
	n := min(int(count), len(entries))
	descending := item.value == 1
	vm.NewTable(L, n)
	for i in 0 ..< n {
		entry := entries[descending ? len(entries) - 1 - i : i]
		vm.NewTable(L, 0, 3)
		vm.PushString(L, entry.key); vm.SetField(L, -2, "key")
		memory_value_push(L, &entry.value); vm.SetField(L, -2, "value")
		memory_value_push(L, &entry.sort); vm.SetField(L, -2, "sortKey")
		vm.SetArrayValue(L, -2, i + 1)
	}
	return 1, true
}
memory_store_queue_less :: proc(a, b: Memory_Entry) -> bool {
	if a.priority != b.priority {return a.priority > b.priority}
	return a.sequence < b.sequence
}
memory_store_queue_call :: proc(
	L: ^vm.State,
	store: ^Memory_Container,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "AddAsync":
		entry: Memory_Entry
		ok: bool
		entry.expires, ok = memory_store_expiry(L, 3)
		if !ok {return memory_store_error(L, "Expiration must be positive and at most 45 days")}
		if !vm.IsNoneOrNil(L, 4) {
			entry.priority, ok = memory_store_number(L, 4, -1e15, 1e15)
			if !ok {return memory_store_error(L, "Invalid queue priority")}
		}
		if !memory_store_capture_entry(L, 2, 0, store, &entry) {
			memory_store_discard(&entry)
			return memory_store_error(L, "Unsupported or oversized MemoryStore value")
		}
		if store.owner.bytes_used + entry.size >
		   MEMORY_STORE_MAX_BYTES {memory_store_prune_all(store.owner)}
		if len(store.queue) >= MEMORY_STORE_MAX_ENTRIES ||
		   store.owner.bytes_used + entry.size > MEMORY_STORE_MAX_BYTES {
			memory_store_discard(&entry)
			return memory_store_error(L, "MemoryStore capacity exceeded")
		}
		store.sequence += 1
		entry.sequence = store.sequence
		append(&store.queue, entry)
		store.owner.bytes_used += entry.size
		return 0, true
	case "ReadAsync":
		count, ok := memory_store_number(L, 2, 1, 100)
		if !ok ||
		   count !=
			   math.floor(
				   count,
			   ) {return memory_store_error(L, "Read count must be an integer from 1 to 100")}
		all := vm.ArgOptionalBoolean(L, 3, false)
		wait := vm.ArgOptionalNumber(L, 4, 0)
		if wait !=
		   0 {return memory_store_error(L, "Local queue reads are nonblocking; use a wait timeout of 0")}
		now := time.tick_now()
		available := 0
		for entry in store.queue {
			if entry.receipt == 0 ||
			   time.tick_diff(entry.invisible_until, now) >= 0 {available += 1}
		}
		n := min(int(count), available)
		if all && n < int(count) {n = 0}
		vm.NewTable(L, n)
		if n == 0 {vm.PushNil(L); return 2, true}
		slice.sort_by(store.queue[:], memory_store_queue_less)
		store.owner.next_receipt += 1
		receipt := store.owner.next_receipt
		i := 0
		for &entry in store.queue {
			if entry.receipt != 0 && time.tick_diff(entry.invisible_until, now) < 0 {continue}
			entry.receipt = receipt
			entry.invisible_until = time.tick_add(
				now,
				time.Duration(store.invisibility * f64(time.Second)),
			)
			memory_value_push(L, &entry.value)
			i += 1
			vm.SetArrayValue(L, -2, i)
			if i == n {break}
		}
		vm.PushString(L, fmt.tprintf("%d", receipt))
		return 2, true
	case "RemoveAsync":
		text, ok := memory_store_text(L, 2)
		if !ok {return memory_store_error(L, "RemoveAsync requires a queue receipt")}
		receipt, parsed := strconv.parse_i64(text, 10)
		if !parsed || receipt <= 0 {vm.PushBoolean(L, false); return 1, true}
		now := time.tick_now()
		i := 0
		removed := false
		for i < len(store.queue) {
			entry := &store.queue[i]
			if entry.receipt == receipt &&
			   (store.invisibility == 0 || time.tick_diff(entry.invisible_until, now) < 0) {
				memory_entry_free(store, entry)
				unordered_remove(&store.queue, i)
				removed = true
			} else {i += 1}
		}
		vm.PushBoolean(L, removed)
		return 1, true
	}
	return 0, false
}
memory_store_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^MemoryStoreService)object
	for store in service.containers {
		for _, entry in store.entries {old := entry; memory_entry_free(store, &old)}
		delete(store.entries)
		for &entry in store.queue {memory_entry_free(store, &entry)}
		delete(store.queue)
		store.owner = nil
		memory_store_release(store)
	}
	delete(service.containers)
	classes.Object_Destroy(object)
	free(service)
}
Register_MemoryStoreService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&MemoryStoreService_Class,
		memory_store_service_construct,
		memory_store_service_destroy,
		creatable = false,
		get = memory_store_service_get,
		namecall = memory_store_service_namecall,
	)
}
