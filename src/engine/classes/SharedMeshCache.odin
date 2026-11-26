package classes

import kineffi "../bindings"
import "core:strings"
import "core:sync"


Shared_Mesh_Cache_Key :: struct {
	ctx:      ^kineffi.KineFilamentContext,
	source:   string,
	index:    u32,
	revision: u64,
	embedded: bool,
}

Shared_Mesh_Cache_Entry :: struct {
	key:        Shared_Mesh_Cache_Key,
	mesh:       ^kineffi.KineFilamentMesh,
	references: int,
}

shared_mesh_cache_mutex: sync.Mutex
shared_mesh_cache: map[Shared_Mesh_Cache_Key]^Shared_Mesh_Cache_Entry
shared_mesh_by_handle: map[^kineffi.KineFilamentMesh]^Shared_Mesh_Cache_Entry

Shared_Mesh_Can_Share :: proc(mesh: ^kineffi.KineFilamentMesh) -> bool {
	return(
		mesh != nil &&
		kineffi.Kine_Filament_GetMeshBoneCount(mesh) == 0 &&
		kineffi.Kine_Filament_GetMeshAnimationCount(mesh) == 0 \
	)
}


Shared_Mesh_Acquire :: proc(
	ctx: ^kineffi.KineFilamentContext,
	source: string,
	index: u32,
	revision: u64,
	embedded: bool,
) -> ^kineffi.KineFilamentMesh {
	if ctx == nil || source == "" {return nil}
	sync.mutex_lock(&shared_mesh_cache_mutex)
	defer sync.mutex_unlock(&shared_mesh_cache_mutex)
	if entry, found :=
		   shared_mesh_cache[Shared_Mesh_Cache_Key{ctx, source, index, revision, embedded}];
	   found {
		entry.references += 1
		return entry.mesh
	}
	return nil
}


Shared_Mesh_Register :: proc(
	ctx: ^kineffi.KineFilamentContext,
	source: string,
	index: u32,
	revision: u64,
	embedded: bool,
	loaded: ^kineffi.KineFilamentMesh,
) -> ^kineffi.KineFilamentMesh {
	if loaded == nil || ctx == nil || source == "" {return loaded}
	sync.mutex_lock(&shared_mesh_cache_mutex)
	key := Shared_Mesh_Cache_Key{ctx, source, index, revision, embedded}
	if existing, found := shared_mesh_cache[key]; found {
		existing.references += 1
		sync.mutex_unlock(&shared_mesh_cache_mutex)
		if existing.mesh != loaded {_ = kineffi.Kine_Filament_DestroyMesh(ctx, loaded)}
		return existing.mesh
	}
	entry := new(Shared_Mesh_Cache_Entry)
	entry.key = {ctx, strings.clone(source), index, revision, embedded}
	entry.mesh = loaded
	entry.references = 1
	if shared_mesh_cache == nil {
		shared_mesh_cache = make(map[Shared_Mesh_Cache_Key]^Shared_Mesh_Cache_Entry)
		shared_mesh_by_handle = make(map[^kineffi.KineFilamentMesh]^Shared_Mesh_Cache_Entry)
	}
	shared_mesh_cache[entry.key] = entry
	shared_mesh_by_handle[loaded] = entry
	sync.mutex_unlock(&shared_mesh_cache_mutex)
	return loaded
}


Shared_Mesh_Release :: proc(
	ctx: ^kineffi.KineFilamentContext,
	mesh: ^kineffi.KineFilamentMesh,
	destroy_native: bool = true,
) -> bool {
	if ctx == nil || mesh == nil {return false}
	sync.mutex_lock(&shared_mesh_cache_mutex)
	entry, found := shared_mesh_by_handle[mesh]
	if !found || entry.key.ctx != ctx {
		sync.mutex_unlock(&shared_mesh_cache_mutex)
		return false
	}
	assert(entry.references > 0)
	entry.references -= 1
	if entry.references != 0 {
		sync.mutex_unlock(&shared_mesh_cache_mutex)
		return true
	}
	delete_key(&shared_mesh_cache, entry.key)
	delete_key(&shared_mesh_by_handle, mesh)
	if len(shared_mesh_cache) == 0 {
		delete(shared_mesh_cache)
		delete(shared_mesh_by_handle)
		shared_mesh_cache = nil
		shared_mesh_by_handle = nil
	}
	sync.mutex_unlock(&shared_mesh_cache_mutex)

	if destroy_native {_ = kineffi.Kine_Filament_DestroyMesh(ctx, mesh)}
	delete(entry.key.source)
	free(entry)
	return true
}

Shared_Mesh_Destroy :: proc(ctx: ^kineffi.KineFilamentContext, mesh: ^kineffi.KineFilamentMesh) {
	if ctx == nil || mesh == nil {return}
	if !Shared_Mesh_Release(ctx, mesh) {_ = kineffi.Kine_Filament_DestroyMesh(ctx, mesh)}
}

Shared_Mesh_Cache_Entry_Count :: proc() -> int {
	sync.mutex_lock(&shared_mesh_cache_mutex)
	defer sync.mutex_unlock(&shared_mesh_cache_mutex)
	return len(shared_mesh_cache)
}

Shared_Mesh_Cache_References :: proc(mesh: ^kineffi.KineFilamentMesh) -> int {
	sync.mutex_lock(&shared_mesh_cache_mutex)
	defer sync.mutex_unlock(&shared_mesh_cache_mutex)
	if entry, found := shared_mesh_by_handle[mesh]; found {return entry.references}
	return 0
}
