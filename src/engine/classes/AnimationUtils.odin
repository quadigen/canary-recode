package classes

import assetstore "../assetstore"
import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:math"
import "core:strings"

Animation_Native_Priority :: proc(value: i64) -> i32 {
	if value == 1000 {return 0}
	if value >= 0 && value <= 5 {return i32(value) + 1}
	return 0
}
Animation_Engine_Priority :: proc(value: i32) -> i64 {
	if value <= 0 {return 1000}
	return i64(value - 1)
}
Animation_Push_Priority :: proc(L: ^vm.State, registry: ^enums.Registry, value: i32) {
	if registry == nil {vm.PushNumber(L, f64(value)); return}
	_ = enums.Push_Item_By_Value(
		L,
		registry,
		"AnimationPriority",
		Animation_Engine_Priority(value),
	)
}
Animation_Arg_Priority :: proc(L: ^vm.State, registry: ^enums.Registry, index: int) -> i32 {
	if registry == nil {return 0}
	item := enums.Arg_Item(L, index, registry, "AnimationPriority")
	if item == nil {return 0}
	return Animation_Native_Priority(item.value)
}

Animation_Is_Live :: proc(registry: ^Registry, class_name: string, candidate: ^Object) -> bool {
	if registry == nil || candidate == nil {return false}
	descriptor := Find_Class(registry, class_name)
	if descriptor == nil {return false}
	for item in descriptor.instances {
		if item == candidate {return !item.destroyed}
	}
	return false
}
Animation_Signal :: proc(object: ^Object, signal: ^^signals.Signal) -> ^signals.Signal {
	if signal^ == nil &&
	   object != nil &&
	   object.signal_registry != nil &&
	   object.signal_registry.signal_registry != nil {
		signal^ = signals.Create(object.signal_registry.signal_registry)
	}
	return signal^
}
Animation_Signal_Destroy :: proc(signal: ^^signals.Signal) {
	if signal^ != nil {
		signals.Destroy(signal^)
		signal^ = nil
	}
}
Animation_Signal_Fire :: proc(L: ^vm.State, signal: ^signals.Signal) {
	if L != nil && signal != nil {signals.Fire(L, signal, 0)}
}
Animation_Signal_Fire_Object :: proc(L: ^vm.State, signal: ^signals.Signal, object: ^Object) {
	if L == nil || signal == nil {return}
	Push_Object(L, object)
	signals.Fire(L, signal, 1)
	vm.Pop(L)
}
Animation_Signal_Fire_String :: proc(L: ^vm.State, signal: ^signals.Signal, value: string) {
	if L == nil || signal == nil {return}
	vm.PushString(L, value)
	signals.Fire(L, signal, 1)
	vm.Pop(L)
}

Animation_Search_Mesh :: proc(root: ^Object) -> ^MeshPart {
	if root == nil || root.destroyed {return nil}
	if Is_A_Class(root, &MeshPart_Class) {return cast(^MeshPart)root}
	for child in root.children {
		result := Animation_Search_Mesh(child)
		if result != nil {return result}
	}
	return nil
}
Animation_Resolve_Mesh :: proc(a: ^Animator) -> ^MeshPart {
	if a == nil {return nil}
	registry := a.object.signal_registry
	if Animation_Is_Live(registry, "MeshPart", a.mesh_part) {
		return cast(^MeshPart)a.mesh_part
	}
	node := a.object.parent
	for node != nil {
		if Is_A_Class(node, &MeshPart_Class) {return cast(^MeshPart)node}
		if Is_A_Class(node, &AnimationController_Class) {
			controller := cast(^AnimationController)node
			if Animation_Is_Live(registry, "MeshPart", controller.mesh_part) {
				return cast(^MeshPart)controller.mesh_part
			}
			return Animation_Search_Mesh(node.parent)
		}
		if Is_A_Class(node, &Humanoid_Class) {
			return Animation_Search_Mesh(node.parent)
		}
		if Is_A_Class(node, &Model_Class) {
			return Animation_Search_Mesh(node)
		}
		node = node.parent
	}
	return nil
}
Animation_Native_Live :: proc(a: ^Animator) -> bool {
	if a == nil || a.native_animator == nil || a.object.signal_registry == nil {return false}
	descriptor := Find_Class(a.object.signal_registry, "MeshPart")
	if descriptor == nil {return false}
	for object in descriptor.instances {
		if object == nil || object.destroyed {continue}
		mesh := cast(^MeshPart)object
		if mesh.native_mesh != nil &&
		   mesh.native_mesh == a.native_mesh &&
		   mesh.native_context != nil &&
		   mesh.native_context == a.native_context {return true}
	}
	return false
}
Animation_Invalidate_Tracks :: proc(a: ^Animator) {
	if a == nil {return}
	for t in a.tracks {
		if t != nil {
			t.native_track = nil
			t.cached_state = {}
		}
	}
	a.native_animator = nil
	a.native_mesh = nil
	a.native_context = nil
}
Animation_Animator_Valid :: proc(a: ^Animator) -> bool {
	if a == nil || a.native_animator == nil {return false}
	mesh := Animation_Resolve_Mesh(a)
	if mesh == nil ||
	   mesh.native_mesh == nil ||
	   mesh.native_context == nil ||
	   mesh.native_mesh != a.native_mesh ||
	   mesh.native_context != a.native_context {
		if Animation_Native_Live(a) {kineffi.Kine_Filament_AnimatorDestroy(a.native_animator)}
		Animation_Invalidate_Tracks(a)
		return false
	}
	return true
}
Animation_Animator_Ready :: proc(a: ^Animator) -> bool {
	if Animation_Animator_Valid(a) {return true}
	mesh := Animation_Resolve_Mesh(a)
	if mesh == nil || mesh.native_mesh == nil || mesh.native_context == nil {return false}
	native := kineffi.Kine_Filament_AnimatorCreate(mesh.native_context, mesh.native_mesh)
	if native == nil {return false}
	a.native_animator = native
	a.native_mesh = mesh.native_mesh
	a.native_context = mesh.native_context
	return true
}
Animation_Track_Valid :: proc(t: ^AnimationTrack) -> bool {
	return t != nil && t.native_track != nil && t.owner != nil && Animation_Animator_Valid(t.owner)
}

Animation_Import_Clips :: proc(
	ctx: ^kineffi.KineFilamentContext,
	mesh: ^kineffi.KineFilamentMesh,
	source: string,
) -> bool {
	if ctx == nil || mesh == nil || source == "" {return false}

	temporary: ^kineffi.KineFilamentMesh
	if data, found := assetstore.Resolve_Bytes(source); found && len(data) > 0 {
		hint := assetstore.Format_Hint(source)
		defer delete(hint)
		c_hint := strings.clone_to_cstring(hint == "" ? "glb" : hint)
		defer delete(c_hint)
		temporary = kineffi.Kine_Filament_CreateMeshFromMemoryIndexed(
			ctx,
			raw_data(data),
			uintptr(len(data)),
			c_hint,
			0,
		)
	} else if !assetstore.Is_Uri(source) {
		path := assetstore.Resolve_Path(source)
		defer delete(path)
		if path != "" {
			c_path := strings.clone_to_cstring(path)
			defer delete(c_path)
			temporary = kineffi.Kine_Filament_CreateMeshFromPathIndexed(ctx, c_path, 0)
		}
	}
	if temporary == nil {return false}
	defer _ = kineffi.Kine_Filament_DestroyMesh(ctx, temporary)

	return kineffi.Kine_Filament_MeshImportAnimations(mesh, temporary) > 0
}

Animation_Ensure_Child_Animator :: proc(L: ^vm.State, container: ^Object) -> ^Animator {
	if container == nil || container.signal_registry == nil {return nil}
	for child in container.children {
		if Is_A_Class(child, &Animator_Class) {return cast(^Animator)child}
	}
	registry := container.signal_registry
	if registry.vm_state == nil {return nil}
	object, ok := Push_New(registry, registry.vm_state, "Animator")
	if !ok {return nil}
	Set_Parent(object, container)
	vm.Pop(registry.vm_state.L)
	return cast(^Animator)object
}

Animation_Push_Track_Array :: proc(L: ^vm.State, a: ^Animator) {
	vm.NewTable(L, 0)
	if a == nil {return}
	index := 0
	for t in a.tracks {
		if t == nil || t.object.destroyed || !Animation_Track_Valid(t) {continue}
		state: kineffi.KineAnimationTrackState
		if !kineffi.Kine_Filament_AnimationTrackGetState(t.native_track, &state) ||
		   state.isPlaying == 0 {continue}
		index += 1
		Push_Object(L, &t.object)
		vm.SetArrayValue(L, -2, index)
	}
}

Animation_MeshPart_Find_Bone :: proc(mesh: ^kineffi.KineFilamentMesh, name: string) -> i32 {
	if mesh == nil || name == "" {return -1}
	count := kineffi.Kine_Filament_GetMeshBoneCount(mesh)
	for index: i32 = 0; index < count; index += 1 {
		bone_name := kineffi.Kine_Filament_GetMeshBoneName(mesh, index)
		if bone_name != nil && string(bone_name) == name {return index}
	}
	return -1
}

MeshPart_Reset_Bone_Transforms :: proc(part: ^MeshPart) {
	if part == nil {return}
	if part.bone_transforms != nil {delete(part.bone_transforms)}
	part.bone_transforms = nil
	part.bone_transforms_mesh = nil
}

Animation_Matrix_To_CFrame :: proc(m: [16]f32) -> datatypes.CFrame {
	return datatypes.CFrame {
		x = f64(m[3]),
		y = f64(m[7]),
		z = f64(m[11]),
		r00 = f64(m[0]),
		r01 = f64(m[1]),
		r02 = f64(m[2]),
		r10 = f64(m[4]),
		r11 = f64(m[5]),
		r12 = f64(m[6]),
		r20 = f64(m[8]),
		r21 = f64(m[9]),
		r22 = f64(m[10]),
	}
}

Animation_CFrame_To_Matrix :: proc(cframe: datatypes.CFrame) -> [16]f32 {
	return [16]f32 {
		f32(cframe.r00),
		f32(cframe.r01),
		f32(cframe.r02),
		f32(cframe.x),
		f32(cframe.r10),
		f32(cframe.r11),
		f32(cframe.r12),
		f32(cframe.y),
		f32(cframe.r20),
		f32(cframe.r21),
		f32(cframe.r22),
		f32(cframe.z),
		0,
		0,
		0,
		1,
	}
}

Animation_Multiply_Matrices :: proc(a, b: [16]f32) -> [16]f32 {
	result: [16]f32
	for row in 0 ..< 4 {
		for column in 0 ..< 4 {
			sum: f32
			for index in 0 ..< 4 {
				sum += a[row * 4 + index] * b[index * 4 + column]
			}
			result[row * 4 + column] = sum
		}
	}
	return result
}

Animation_MeshPart_Bone_Transforms :: proc(part: ^MeshPart) -> [][16]f32 {
	if part == nil || part.native_mesh == nil {return nil}
	count := kineffi.Kine_Filament_GetMeshBoneCount(part.native_mesh)
	if count <= 0 {return nil}
	if part.bone_transforms != nil &&
	   part.bone_transforms_mesh == part.native_mesh &&
	   len(part.bone_transforms) == int(count) {
		return part.bone_transforms
	}

	MeshPart_Reset_Bone_Transforms(part)
	transforms := make([][16]f32, int(count))
	for index in 0 ..< int(count) {
		if !kineffi.Kine_Filament_CopyMeshBoneBindTransform(
			part.native_mesh,
			i32(index),
			&transforms[index][0],
		) {
			transforms[index] = Animation_CFrame_To_Matrix(datatypes.CFrame_Identity)
		}
	}
	part.bone_transforms = transforms
	part.bone_transforms_mesh = part.native_mesh
	return transforms
}

Animation_Eval_Bone_Global :: proc(
	index: int,
	locals: [][16]f32,
	globals: [][16]f32,
	states: []u8,
	mesh: ^kineffi.KineFilamentMesh,
) -> bool {
	if index < 0 || index >= len(locals) || index >= len(globals) || index >= len(states) {
		return false
	}
	if states[index] == 1 {return true}
	if states[index] == 2 {return false}

	states[index] = 2
	parent := kineffi.Kine_Filament_GetMeshBoneParent(mesh, i32(index))
	if parent >= 0 && int(parent) < len(locals) && int(parent) != index {
		if !Animation_Eval_Bone_Global(int(parent), locals, globals, states, mesh) {
			return false
		}
		globals[index] = Animation_Multiply_Matrices(globals[int(parent)], locals[index])
	} else {
		globals[index] = locals[index]
	}
	states[index] = 1
	return true
}

Animation_MeshPart_Bone_Globals :: proc(part: ^MeshPart) -> [][16]f32 {
	locals := Animation_MeshPart_Bone_Transforms(part)
	if locals == nil {return nil}

	globals := make([][16]f32, len(locals))
	states := make([]u8, len(locals))
	defer delete(states)
	for index in 0 ..< len(locals) {
		if !Animation_Eval_Bone_Global(index, locals, globals, states, part.native_mesh) {
			delete(globals)
			return nil
		}
	}
	return globals
}

Animation_MeshPart_Apply_Bone_Transforms :: proc(part: ^MeshPart) -> bool {
	if part == nil || part.native_mesh == nil || part.native_context == nil {return false}
	globals := Animation_MeshPart_Bone_Globals(part)
	if globals == nil || len(globals) == 0 {return false}
	defer delete(globals)
	return kineffi.Kine_Filament_SetMeshBoneTransforms(
		part.native_context,
		part.native_mesh,
		&globals[0][0],
		i32(len(globals)),
	)
}

Animation_MeshPart_Bone_World_CFrame :: proc(
	part: ^MeshPart,
	index: int,
) -> (
	datatypes.CFrame,
	bool,
) {
	if part == nil {return {}, false}
	transform: [16]f32
	if !kineffi.Kine_Filament_CopyMeshBoneGlobalTransform(
		part.native_mesh,
		i32(index),
		&transform[0],
	) {
		return {}, false
	}
	local := Animation_Matrix_To_CFrame(transform)
	scale := datatypes.Vector3{part.size.x * 0.5, part.size.y * 0.5, part.size.z * 0.5}
	position := datatypes.CFrame_PointToWorldSpace(
		part.cframe,
		datatypes.Vector3{local.x * scale.x, local.y * scale.y, local.z * scale.z},
	)
	result := datatypes.CFrame_Mul_CFrame(part.cframe, local)
	result.x = position.x
	result.y = position.y
	result.z = position.z
	return result, true
}

Animation_MeshPart_Namecall :: proc(
	L: ^vm.State,
	mesh_part: ^MeshPart,
	datatype_registry: ^datatypes.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "GetBoneNames":
		vm.NewTable(L, 0)
		if mesh_part == nil || mesh_part.native_mesh == nil {return 1, true}
		count := kineffi.Kine_Filament_GetMeshBoneCount(mesh_part.native_mesh)
		for i: i32 = 0; i < count; i += 1 {
			name := kineffi.Kine_Filament_GetMeshBoneName(mesh_part.native_mesh, i)
			if name == nil {continue}
			vm.PushString(L, string(name))
			vm.SetArrayValue(L, -2, int(i) + 1)
		}
		return 1, true
	case "GetBoneWorldCFrame":
		if mesh_part == nil || mesh_part.native_mesh == nil {
			vm.PushNil(L)
			return 1, true
		}
		index := Animation_MeshPart_Find_Bone(mesh_part.native_mesh, vm.ArgString(L, 2))
		if index < 0 {
			vm.PushNil(L)
			return 1, true
		}
		if world, ok := Animation_MeshPart_Bone_World_CFrame(mesh_part, int(index)); ok {
			datatypes.Push_CFrame(L, datatype_registry, world)
		} else {
			vm.PushNil(L)
		}
		return 1, true
	case "GetBoneWorldCFrames":
		vm.NewTable(L, 0)
		if mesh_part == nil || mesh_part.native_mesh == nil {return 1, true}
		count := kineffi.Kine_Filament_GetMeshBoneCount(mesh_part.native_mesh)
		for i in 0 ..< count {
			name := kineffi.Kine_Filament_GetMeshBoneName(mesh_part.native_mesh, i)
			if name == nil {continue}
			if world, ok := Animation_MeshPart_Bone_World_CFrame(mesh_part, int(i)); ok {
				datatypes.Push_CFrame(L, datatype_registry, world)
				vm.SetField(L, -2, string(name))
			}
		}
		return 1, true
	case "GetBoneBindTransform":
		if mesh_part == nil || mesh_part.native_mesh == nil {vm.PushNil(L); return 1, true}
		index := Animation_MeshPart_Find_Bone(mesh_part.native_mesh, vm.ArgString(L, 2))
		bind: [16]f32
		if index < 0 ||
		   !kineffi.Kine_Filament_CopyMeshBoneBindTransform(
				   mesh_part.native_mesh,
				   index,
				   &bind[0],
			   ) {
			vm.PushNil(L)
		} else {
			datatypes.Push_CFrame(L, datatype_registry, Animation_Matrix_To_CFrame(bind))
		}
		return 1, true
	case "SetBoneTransforms":
		if !vm.IsTable(
			L,
			2,
		) {return vm.RaiseError(L, "expected a table of bone names and CFrames"), true}
		transforms := Animation_MeshPart_Bone_Transforms(mesh_part)
		if len(transforms) == 0 {vm.PushBoolean(L, false); return 1, true}

		updated := make([][16]f32, len(transforms), context.temp_allocator)
		copy(updated, transforms)
		vm.PushNil(L)
		for vm.Next(L, 2) {
			if vm.TypeOf(L, -2) != .String ||
			   !vm.IsUserdataType(L, -1, &datatype_registry.c_frame) {
				vm.Pop(L, 2)
				vm.PushBoolean(L, false)
				return 1, true
			}
			index := Animation_MeshPart_Find_Bone(mesh_part.native_mesh, vm.ArgString(L, -2))
			if index < 0 || int(index) >= len(updated) {
				vm.Pop(L, 2)
				vm.PushBoolean(L, false)
				return 1, true
			}
			updated[index] = Animation_CFrame_To_Matrix(
				datatypes.Arg_CFrame(L, -1, datatype_registry),
			)
			for component in updated[index] {
				if math.is_nan(component) || math.is_inf(component) {
					vm.Pop(L, 2)
					vm.PushBoolean(L, false)
					return 1, true
				}
			}
			vm.Pop(L)
		}
		globals := make([][16]f32, len(updated), context.temp_allocator)
		states := make([]u8, len(updated), context.temp_allocator)
		for index in 0 ..< len(updated) {
			if !Animation_Eval_Bone_Global(
				index,
				updated,
				globals,
				states,
				mesh_part.native_mesh,
			) {
				vm.PushBoolean(L, false)
				return 1, true
			}
		}
		ok :=
			mesh_part.native_context != nil &&
			kineffi.Kine_Filament_SetMeshBoneTransforms(
				mesh_part.native_context,
				mesh_part.native_mesh,
				&globals[0][0],
				i32(len(globals)),
			)
		if ok {copy(transforms, updated)}
		vm.PushBoolean(L, ok)
		return 1, true
	case "GetBoneTransform":
		if mesh_part == nil || mesh_part.native_mesh == nil {
			vm.PushNil(L)
			return 1, true
		}
		index := Animation_MeshPart_Find_Bone(mesh_part.native_mesh, vm.ArgString(L, 2))
		transforms := Animation_MeshPart_Bone_Transforms(mesh_part)
		if index < 0 || transforms == nil || int(index) >= len(transforms) {
			vm.PushNil(L)
			return 1, true
		}
		datatypes.Push_CFrame(
			L,
			datatype_registry,
			Animation_Matrix_To_CFrame(transforms[int(index)]),
		)
		return 1, true
	case "SetBoneTransform":
		if mesh_part == nil || mesh_part.native_mesh == nil {return 0, true}
		index := Animation_MeshPart_Find_Bone(mesh_part.native_mesh, vm.ArgString(L, 2))
		transforms := Animation_MeshPart_Bone_Transforms(mesh_part)
		if index < 0 || transforms == nil || int(index) >= len(transforms) {
			return 0, true
		}
		previous := transforms[int(index)]
		transforms[int(index)] = Animation_CFrame_To_Matrix(
			datatypes.Arg_CFrame(L, 3, datatype_registry),
		)
		if !Animation_MeshPart_Apply_Bone_Transforms(mesh_part) {
			transforms[int(index)] = previous
		}
		return 0, true
	case "GetBoneParent":
		if mesh_part == nil || mesh_part.native_mesh == nil {
			vm.PushNil(L)
			return 1, true
		}
		index := Animation_MeshPart_Find_Bone(mesh_part.native_mesh, vm.ArgString(L, 2))
		if index < 0 {
			vm.PushNil(L)
			return 1, true
		}
		parent := kineffi.Kine_Filament_GetMeshBoneParent(mesh_part.native_mesh, index)
		if parent < 0 {
			vm.PushNil(L)
			return 1, true
		}
		name := kineffi.Kine_Filament_GetMeshBoneName(mesh_part.native_mesh, parent)
		if name == nil {
			vm.PushNil(L)
		} else {
			vm.PushString(L, string(name))
		}
		return 1, true
	case "GetAnimationClips":
		vm.NewTable(L, 0)
		if mesh_part == nil || mesh_part.native_mesh == nil {return 1, true}
		count := kineffi.Kine_Filament_GetMeshAnimationCount(mesh_part.native_mesh)
		for i: i32 = 0; i < count; i += 1 {
			vm.NewTable(L, 0)
			vm.PushNumber(L, f64(i))
			vm.SetField(L, -2, "Index")
			name := kineffi.Kine_Filament_GetMeshAnimationName(mesh_part.native_mesh, i)
			if name != nil {
				vm.PushString(L, string(name))
				vm.SetField(L, -2, "Name")
			}
			vm.PushNumber(
				L,
				f64(kineffi.Kine_Filament_GetMeshAnimationDuration(mesh_part.native_mesh, i)),
			)
			vm.SetField(L, -2, "Length")
			vm.SetArrayValue(L, -2, int(i) + 1)
		}
		return 1, true
	}
	return 0, false
}

Animation_Humanoid_Namecall :: proc(L: ^vm.State, object: ^Object, method: string) -> (i32, bool) {
	switch method {
	case "LoadAnimation":
		a := Animation_Ensure_Child_Animator(L, object)
		if a == nil {return vm.RaiseError(L, "could not construct child Animator"), true}
		return Animation_Load_Track(L, a, object_from_argument(L, 2))
	case "GetPlayingAnimationTracks":
		for child in object.children {
			if Is_A_Class(child, &Animator_Class) {
				Animation_Push_Track_Array(L, cast(^Animator)child)
				return 1, true
			}
		}
		vm.NewTable(L, 0)
		return 1, true
	}
	return 0, false
}
