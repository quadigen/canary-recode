package native_api

import classes "../classes"
import odin_runtime "base:runtime"

@(export)
Kinemium_HandleGetAttributeCount :: proc "c" (ctx: ^Context, handle: u64) -> u64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return 0}
	return u64(len(object.attributes))
}

@(export)
Kinemium_HandleCopyAttributeName :: proc "c" (
	ctx: ^Context,
	handle: u64,
	index: u64,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || index >= u64(len(object.attributes)) {return -1}
	return sdk_copy_string(object.attributes[int(index)].name, buffer, capacity)
}

@(export)
Kinemium_HandleHasAttribute :: proc "c" (ctx: ^Context, handle: u64, name: cstring) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || name == nil {return false}
	for attribute in object.attributes {
		if attribute.name == string(name) {return true}
	}
	return false
}

@(export)
Kinemium_HandleGetAttribute :: proc "c" (
	ctx: ^Context,
	handle: u64,
	name: cstring,
	output: ^SDK_Value,
	text_buffer: [^]u8,
	text_capacity: u64,
) -> bool {
	context = odin_runtime.default_context()
	if name == nil || output == nil || resolve_handle(ctx, handle) == nil {return false}
	argument := SDK_Value {
		kind        = .String,
		text        = name,
		text_length = u64(len(string(name))),
	}
	return Kinemium_Invoke(
		ctx,
		handle,
		"GetAttribute",
		&argument,
		1,
		output,
		text_buffer,
		text_capacity,
	)
}

@(export)
Kinemium_HandleSetAttribute :: proc "c" (
	ctx: ^Context,
	handle: u64,
	name: cstring,
	value: ^SDK_Value,
) -> bool {
	context = odin_runtime.default_context()
	if name == nil || value == nil || resolve_handle(ctx, handle) == nil {return false}
	if !classes.Attribute_Name_Is_Valid(string(name)) {
		sdk_error(ctx, "invalid attribute name")
		return false
	}
	#partial switch value.kind {
	case .Nil, .Boolean, .Number, .String, .Vector3:
	case:
		sdk_error(ctx, "unsupported attribute value kind")
		return false
	}
	arguments := [2]SDK_Value {
		{kind = .String, text = name, text_length = u64(len(string(name)))},
		value^,
	}
	return Kinemium_Invoke(ctx, handle, "SetAttribute", &arguments[0], 2, nil, nil, 0)
}

@(export)
Kinemium_HandleRemoveAttribute :: proc "c" (ctx: ^Context, handle: u64, name: cstring) -> bool {
	context = odin_runtime.default_context()
	value := SDK_Value {
		kind = .Nil,
	}
	return Kinemium_HandleSetAttribute(ctx, handle, name, &value)
}

@(export)
Kinemium_HandleGetTagCount :: proc "c" (ctx: ^Context, handle: u64) -> u64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return 0}
	return u64(len(object.tags))
}

@(export)
Kinemium_HandleCopyTagName :: proc "c" (
	ctx: ^Context,
	handle: u64,
	index: u64,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || index >= u64(len(object.tags)) {return -1}
	return sdk_copy_string(object.tags[int(index)], buffer, capacity)
}

@(export)
Kinemium_HandleHasTag :: proc "c" (ctx: ^Context, handle: u64, tag: cstring) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || tag == nil {return false}
	return classes.Object_Has_Tag(object, string(tag))
}

handle_tag_call :: proc(ctx: ^Context, handle: u64, tag: cstring, method: cstring) -> bool {
	if tag == nil || resolve_handle(ctx, handle) == nil {return false}
	if !classes.Tag_Name_Is_Valid(string(tag)) {
		sdk_error(ctx, "invalid tag name")
		return false
	}
	argument := SDK_Value {
		kind        = .String,
		text        = tag,
		text_length = u64(len(string(tag))),
	}
	return Kinemium_Invoke(ctx, handle, method, &argument, 1, nil, nil, 0)
}

@(export)
Kinemium_HandleAddTag :: proc "c" (ctx: ^Context, handle: u64, tag: cstring) -> bool {
	context = odin_runtime.default_context()
	return handle_tag_call(ctx, handle, tag, "AddTag")
}

@(export)
Kinemium_HandleRemoveTag :: proc "c" (ctx: ^Context, handle: u64, tag: cstring) -> bool {
	context = odin_runtime.default_context()
	return handle_tag_call(ctx, handle, tag, "RemoveTag")
}

@(export)
Kinemium_HandleGetMetadataRevision :: proc "c" (ctx: ^Context, handle: u64) -> u64 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil {return 0}
	return object.metadata_revision
}
