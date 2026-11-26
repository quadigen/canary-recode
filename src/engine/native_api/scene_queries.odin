package native_api

import classes "../classes"
import odin_runtime "base:runtime"

scene_descendants :: proc(ctx: ^Context, handle: u64) -> [dynamic]^classes.Object {
	result: [dynamic]^classes.Object
	root := resolve_handle(ctx, handle)
	if root == nil {return result}

	to_visit: [dynamic]^classes.Object
	defer delete(to_visit)
	for child in classes.Get_Children(root) {
		if child != nil && !child.destroyed {append(&to_visit, child)}
	}
	for index := 0; index < len(to_visit); index += 1 {
		object := to_visit[index]
		if object == nil || object.destroyed {continue}
		append(&result, object)
		for child in classes.Get_Children(object) {
			if child != nil && !child.destroyed {append(&to_visit, child)}
		}
	}
	return result
}

@(export)
Kinemium_HandleFindDescendant :: proc "c" (ctx: ^Context, ancestor: u64, name: cstring) -> u64 {
	context = odin_runtime.default_context()
	if name == nil {return 0}
	objects := scene_descendants(ctx, ancestor)
	defer delete(objects)
	for object in objects {
		if classes.Get_Name(object) == string(name) {return register_handle(ctx, object)}
	}
	return 0
}

@(export)
Kinemium_HandleFindDescendantOfClass :: proc "c" (
	ctx: ^Context,
	ancestor: u64,
	class_name: cstring,
) -> u64 {
	context = odin_runtime.default_context()
	if class_name == nil {return 0}
	objects := scene_descendants(ctx, ancestor)
	defer delete(objects)
	for object in objects {
		if classes.Is_A(object, string(class_name)) {return register_handle(ctx, object)}
	}
	return 0
}

@(export)
Kinemium_HandleGetDescendantAt :: proc "c" (ctx: ^Context, ancestor, index: u64) -> u64 {
	context = odin_runtime.default_context()
	objects := scene_descendants(ctx, ancestor)
	defer delete(objects)
	if index >= u64(len(objects)) {return 0}
	return register_handle(ctx, objects[int(index)])
}

@(export)
Kinemium_HandleCountTaggedDescendants :: proc "c" (
	ctx: ^Context,
	ancestor: u64,
	tag: cstring,
) -> u64 {
	context = odin_runtime.default_context()
	if tag == nil {return 0}
	objects := scene_descendants(ctx, ancestor)
	defer delete(objects)
	count: u64
	for object in objects {
		if classes.Object_Has_Tag(object, string(tag)) {count += 1}
	}
	return count
}

@(export)
Kinemium_HandleFindTaggedDescendant :: proc "c" (
	ctx: ^Context,
	ancestor: u64,
	tag: cstring,
) -> u64 {
	context = odin_runtime.default_context()
	if tag == nil {return 0}
	objects := scene_descendants(ctx, ancestor)
	defer delete(objects)
	for object in objects {
		if classes.Object_Has_Tag(object, string(tag)) {return register_handle(ctx, object)}
	}
	return 0
}
