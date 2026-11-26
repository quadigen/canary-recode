package native_api

import classes "../classes"
import odin_runtime "base:runtime"

handle_class_members :: proc(
	ctx: ^Context,
	handle: u64,
	kind: classes.Class_Member_List,
) -> [dynamic]classes.Class_Member_Entry {
	result: [dynamic]classes.Class_Member_Entry
	object := resolve_handle(ctx, handle)
	if object == nil || ctx.classes == nil {return result}
	return classes.Collect_Class_Members(ctx.classes, object.class.name, kind)
}

handle_export_names :: proc(ctx: ^Context, handle: u64) -> [dynamic]string {
	result: [dynamic]string
	object := resolve_handle(ctx, handle)
	if object == nil || ctx.classes == nil {return result}
	chain: [dynamic]^classes.Class_Info
	defer delete(chain)
	current := object.class
	for current != nil {
		append(&chain, current)
		current = current.parent
	}
	for i := len(chain) - 1; i >= 0; i -= 1 {
		descriptor := classes.Find_Class(ctx.classes, chain[i].name)
		if descriptor == nil {continue}
		for exported in descriptor.exports {
			found := false
			for name in result {
				if name == exported.name {found = true; break}
			}
			if !found {append(&result, exported.name)}
		}
	}
	return result
}

@(export)
Kinemium_HandleGetMethodCount :: proc "c" (ctx: ^Context, handle: u64) -> u64 {
	context = odin_runtime.default_context()
	members := handle_class_members(ctx, handle, .Methods)
	defer delete(members)
	return u64(len(members))
}

@(export)
Kinemium_HandleCopyMethodName :: proc "c" (
	ctx: ^Context,
	handle: u64,
	index: u64,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	members := handle_class_members(ctx, handle, .Methods)
	defer delete(members)
	if index >= u64(len(members)) {return -1}
	return sdk_copy_string(members[int(index)].name, buffer, capacity)
}

@(export)
Kinemium_HandleHasMethod :: proc "c" (ctx: ^Context, handle: u64, method: cstring) -> bool {
	context = odin_runtime.default_context()
	if method == nil {return false}
	members := handle_class_members(ctx, handle, .Methods)
	defer delete(members)
	for member in members {
		if member.name == string(method) {return true}
	}
	return false
}

@(export)
Kinemium_HandleGetExportCount :: proc "c" (ctx: ^Context, handle: u64) -> u64 {
	context = odin_runtime.default_context()
	exports := handle_export_names(ctx, handle)
	defer delete(exports)
	return u64(len(exports))
}

@(export)
Kinemium_HandleCopyExportName :: proc "c" (
	ctx: ^Context,
	handle: u64,
	index: u64,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	exports := handle_export_names(ctx, handle)
	defer delete(exports)
	if index >= u64(len(exports)) {return -1}
	return sdk_copy_string(exports[int(index)], buffer, capacity)
}

@(export)
Kinemium_HandleHasExport :: proc "c" (ctx: ^Context, handle: u64, name: cstring) -> bool {
	context = odin_runtime.default_context()
	if name == nil {return false}
	exports := handle_export_names(ctx, handle)
	defer delete(exports)
	for entry in exports {
		if entry == string(name) {return true}
	}
	return false
}

class_members :: proc(
	ctx: ^Context,
	class_name: cstring,
	kind: classes.Class_Member_List,
) -> [dynamic]classes.Class_Member_Entry {
	result: [dynamic]classes.Class_Member_Entry
	if ctx == nil || !ctx.active || ctx.classes == nil || class_name == nil {return result}
	return classes.Collect_Class_Members(ctx.classes, string(class_name), kind)
}

@(export)
Kinemium_ClassCopyParentName :: proc "c" (
	ctx: ^Context,
	class_name: cstring,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || class_name == nil {return -1}
	descriptor := classes.Find_Class(ctx.classes, string(class_name))
	if descriptor == nil || descriptor.info == nil || descriptor.info.parent == nil {return -1}
	return sdk_copy_string(descriptor.info.parent.name, buffer, capacity)
}

@(export)
Kinemium_ClassIsA :: proc "c" (ctx: ^Context, class_name, ancestor_name: cstring) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || class_name == nil || ancestor_name == nil {return false}
	descriptor := classes.Find_Class(ctx.classes, string(class_name))
	if descriptor == nil || descriptor.info == nil {return false}
	ancestor := classes.Find_Class(ctx.classes, string(ancestor_name))
	if ancestor == nil || ancestor.info == nil {return false}
	current := descriptor.info
	for current != nil {
		if current == ancestor.info {return true}
		current = current.parent
	}
	return false
}

@(export)
Kinemium_ClassGetMethodCount :: proc "c" (ctx: ^Context, class_name: cstring) -> u64 {
	context = odin_runtime.default_context()
	members := class_members(ctx, class_name, .Methods)
	defer delete(members)
	return u64(len(members))
}

@(export)
Kinemium_ClassCopyMethodName :: proc "c" (
	ctx: ^Context,
	class_name: cstring,
	index: u64,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	members := class_members(ctx, class_name, .Methods)
	defer delete(members)
	if index >= u64(len(members)) {return -1}
	return sdk_copy_string(members[int(index)].name, buffer, capacity)
}

@(export)
Kinemium_ClassHasMethod :: proc "c" (ctx: ^Context, class_name: cstring, name: cstring) -> bool {
	context = odin_runtime.default_context()
	if name == nil {return false}
	members := class_members(ctx, class_name, .Methods)
	defer delete(members)
	for member in members {
		if member.name == string(name) {return true}
	}
	return false
}

@(export)
Kinemium_ClassGetEventCount :: proc "c" (ctx: ^Context, class_name: cstring) -> u64 {
	context = odin_runtime.default_context()
	members := class_members(ctx, class_name, .Events)
	defer delete(members)
	return u64(len(members))
}

@(export)
Kinemium_ClassCopyEventName :: proc "c" (
	ctx: ^Context,
	class_name: cstring,
	index: u64,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	members := class_members(ctx, class_name, .Events)
	defer delete(members)
	if index >= u64(len(members)) {return -1}
	return sdk_copy_string(members[int(index)].name, buffer, capacity)
}

@(export)
Kinemium_ClassHasEvent :: proc "c" (ctx: ^Context, class_name: cstring, name: cstring) -> bool {
	context = odin_runtime.default_context()
	if name == nil {return false}
	members := class_members(ctx, class_name, .Events)
	defer delete(members)
	for member in members {
		if member.name == string(name) {return true}
	}
	return false
}

@(export)
Kinemium_HandleGetEventCount :: proc "c" (ctx: ^Context, handle: u64) -> u64 {
	context = odin_runtime.default_context()
	members := handle_class_members(ctx, handle, .Events)
	defer delete(members)
	return u64(len(members))
}

@(export)
Kinemium_HandleCopyEventName :: proc "c" (
	ctx: ^Context,
	handle: u64,
	index: u64,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	members := handle_class_members(ctx, handle, .Events)
	defer delete(members)
	if index >= u64(len(members)) {return -1}
	return sdk_copy_string(members[int(index)].name, buffer, capacity)
}

@(export)
Kinemium_HandleHasEvent :: proc "c" (ctx: ^Context, handle: u64, name: cstring) -> bool {
	context = odin_runtime.default_context()
	if name == nil {return false}
	members := handle_class_members(ctx, handle, .Events)
	defer delete(members)
	for member in members {
		if member.name == string(name) {return true}
	}
	return false
}
