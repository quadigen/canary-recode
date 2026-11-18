package classes

import assetstore "../assetstore"
import kineffi "../bindings"
import enums "../enum"
import signals "../signals"
import vm "../vm"
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

// Animation_Import_Clips copies clips from an animation asset onto the rig,
// matching channels by bone name. The source mesh is temporary: only the
// animation records survive, so a rig can play a clip from a file that was
// authored separately from its mesh.
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

Animation_MeshPart_Namecall :: proc(
	L: ^vm.State,
	mesh_part: ^MeshPart,
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
