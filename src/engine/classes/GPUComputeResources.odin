package classes
import assets "../assetstore"
import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import gpu "../gpucompute"
import materials "../material"
import vm "../vm"
import "core:math"
import "core:strings"
import image "vendor:stb/image"

GPUCompute_Luau_Buffer :: struct {
	data: rawptr,
	id:   u32,
	ref:  i32,
}

gpu_compute_release_refs :: proc(L: ^vm.State, compute: ^GPUCompute) {
	for &entry in compute.native_buffers {
		if entry.ref > 0 {vm.ReleaseValue(L, entry.ref)}
		entry = {}
	}
}

gpu_compute_lookup_luau :: proc(compute: ^GPUCompute, data: []u8) -> ^GPUCompute_Luau_Buffer {
	if len(data) == 0 {return nil}
	for &entry in compute.native_buffers {
		if entry.id != 0 && entry.data == rawptr(raw_data(data)) {return &entry}
	}
	return nil
}

gpu_compute_bind_luau :: proc(
	L: ^vm.State,
	compute: ^GPUCompute,
	binding: u32,
	index: int,
) -> string {
	data := vm.ArgBuffer(L, index)
	device := &compute.device
	if entry := gpu_compute_lookup_luau(compute, data); entry != nil {
		return gpu.bind_buffer(device, binding, entry.id)
	}
	if len(data) == 0 ||
	   len(data) > gpu.MAX_CUSTOM_BUFFER_BYTES ||
	   len(data) % 4 != 0 {return "GPUCompute needs a nonempty four-byte-aligned Luau buffer"}
	for &entry in compute.native_buffers {
		if entry.id != 0 {continue}
		id, err := gpu.create_buffer(device, len(data))
		if err != "" {return err}
		if reason := gpu.write_buffer(device, id, data, 0); reason != "" {
			_ = gpu.destroy_buffer(device, id)
			return reason
		}
		if reason := gpu.bind_buffer(device, binding, id); reason != "" {
			_ = gpu.destroy_buffer(device, id)
			return reason
		}
		entry = {rawptr(raw_data(data)), id, vm.RetainValue(L, index)}
		return ""
	}
	return "GPUCompute native buffer limit exceeded"
}

gpu_compute_sync_luau :: proc(L: ^vm.State, compute: ^GPUCompute, method: string) -> string {
	data := vm.ArgBuffer(L, 2)
	entry := gpu_compute_lookup_luau(compute, data)
	if entry == nil {return "Luau buffer has not been bound to this GPUCompute"}
	device := &compute.device
	switch method {
	case "UploadBuffer":
		return gpu.write_buffer(device, entry.id, data, 0)
	case "DownloadBuffer":
		result, err := gpu.read_buffer(device, entry.id, 0, len(data))
		if err == "" {copy(data, result)}
		return err
	case "ReleaseBuffer":
		err := gpu.destroy_buffer(device, entry.id)
		if err != "" {return err}
		vm.ReleaseValue(L, entry.ref)
		entry^ = {}
		return ""
	}
	return "unknown GPUCompute buffer operation"
}

gpu_compute_layout :: proc(
	L: ^vm.State,
	index: int,
) -> (
	count: u32,
	kinds: gpu.Binding_Layout,
	err: string,
) {
	if !vm.IsTable(
		L,
		index,
	) {return gpu_compute_integer(L, index, 1, gpu.MAX_CUSTOM_BINDINGS), {}, ""}
	seen: [gpu.MAX_CUSTOM_BINDINGS]bool
	vm.PushNil(L)
	for vm.Next(L, index) {
		if vm.TypeOf(L, -2) != .Number || vm.TypeOf(L, -1) != .String {
			vm.Pop(L); vm.Pop(L)
			return 0, {}, "descriptor layout requires zero-based integer keys and string types"
		}
		n := vm.ArgNumber(L, -2)
		if !(n >= 0 && n < gpu.MAX_CUSTOM_BINDINGS) || math.floor(n) != n {
			vm.Pop(L); vm.Pop(L)
			return 0, {}, "descriptor binding out of range"
		}
		i := int(n)
		switch vm.ArgString(L, -1) {
		case "StorageBuffer":
			kinds[i] = .StorageBuffer
		case "UniformBuffer":
			kinds[i] = .UniformBuffer
		case "SampledTexture":
			kinds[i] = .SampledTexture
		case "StorageTexture":
			kinds[i] = .StorageTexture
		case:
			vm.Pop(L); vm.Pop(L)
			return 0, {}, "unknown GPUCompute descriptor type"
		}
		seen[i] = true
		count = max(count, u32(i + 1))
		vm.Pop(L)
	}
	if count == 0 {return 0, {}, "empty GPUCompute binding layout"}
	for i in 0 ..< int(count) {if !seen[i] {return 0, {}, "GPUCompute bindings must be contiguous from zero"}}
	return count, kinds, ""
}

gpu_compute_texture_encoded :: proc(
	device: ^gpu.Device,
	data: []u8,
	srgb: bool,
	mips: bool = false,
	nearest: bool = false,
	clamp_address: bool = false,
) -> (
	u32,
	string,
) {
	if len(data) == 0 ||
	   len(data) > gpu.MAX_CUSTOM_BUFFER_BYTES {return 0, "invalid encoded texture size"}
	w, h, c: i32
	if image.info_from_memory(raw_data(data), i32(len(data)), &w, &h, &c) == 0 ||
	   w <= 0 ||
	   h <= 0 ||
	   u64(w) * u64(h) * 4 > gpu.MAX_CUSTOM_BUFFER_BYTES {
		return 0, "invalid or oversized texture image"
	}
	pixels := image.load_from_memory(raw_data(data), i32(len(data)), &w, &h, &c, 4)
	if pixels == nil {return 0, "could not decode texture"}
	defer image.image_free(pixels)
	return gpu.create_texture_desc(
		device,
		{
			width = u32(w),
			height = u32(h),
			depth = 1,
			layers = 1,
			dimension = .D2,
			format = srgb ? .RGBA8_SRGB : .RGBA8,
			mipmaps = mips,
			nearest = nearest,
			clamp = clamp_address,
		},
		pixels[:int(w) * int(h) * 4],
	)
}

gpu_compute_texture_path :: proc(
	L: ^vm.State,
	device: ^gpu.Device,
	path: string,
	srgb: bool,
	mips: bool = false,
	nearest: bool = false,
	clamp_address: bool = false,
) -> (
	u32,
	string,
) {
	if !assets.Is_Uri(path) &&
	   !strings.has_prefix(path, assets.PROJECT_ASSET_SCHEME) &&
	   !strings.has_prefix(path, RUNTIME_IMAGE_PREFIX) &&
	   !vm.ThreadHasSecurityCapability(L, datatypes.SECURITY_CAPABILITY_INTERNAL_STUDIO_ACCESS) {
		return 0, "filesystem textures require trusted editor permissions"
	}
	if data, found := Texture_Resolve_Bytes(path);
	   found {return gpu_compute_texture_encoded(device, data, srgb, mips, nearest, clamp_address)}
	when #config(BUILD_TARGET, "editor") != "editor" {
		if !assets.Is_Uri(path) &&
		   !strings.has_prefix(
				   path,
				   assets.PROJECT_ASSET_SCHEME,
			   ) {return 0, "use a project or embedded texture asset outside the editor"}
	}
	return gpu_compute_texture_file(device, path, srgb, mips, nearest, clamp_address)
}

gpu_compute_option_bool :: proc(L: ^vm.State, index: int, name: string, fallback: bool) -> bool {
	if !vm.IsTable(L, index) {return fallback}
	_ = vm.GetField(L, index, name)
	result := fallback
	if vm.IsBoolean(L, -1) {result = vm.ArgBoolean(L, -1)}
	vm.Pop(L)
	return result
}

gpu_compute_option_string :: proc(L: ^vm.State, index: int, name, fallback: string) -> string {
	if !vm.IsTable(L, index) {return fallback}
	_ = vm.GetField(L, index, name)
	result := fallback
	if vm.TypeOf(L, -1) == .String {result = vm.ArgString(L, -1)}
	vm.Pop(L)
	return result
}

gpu_compute_push_id :: proc(L: ^vm.State, id: u32, err: string) -> (i32, bool) {
	if err != "" {return gpu_compute_nil_error(L, err)}
	vm.PushNumber(L, f64(id))
	return 1, true
}

gpu_compute_material :: proc(
	L: ^vm.State,
	compute: ^GPUCompute,
	registry: ^enums.Registry,
) -> (
	i32,
	bool,
) {
	device := &compute.device
	mips := gpu_compute_option_bool(L, 3, "GenerateMipmaps", false)
	ids: [7]u32
	names: [7]string
	roughness, metallic, uv_scale, height_scale: f32
	if obj := object_from_argument(L, 2); obj != nil && Is_A(obj, "MaterialVariant") {
		variant := cast(^MaterialVariant)obj
		names = {"Albedo", "Normal", "RoughnessMap", "MetallicMap", "Height", "AO", "Emissive"}
		roughness, metallic, uv_scale, height_scale =
			variant.uniforms[1].values[0],
			variant.uniforms[2].values[0],
			1 /
			variant.studs_per_tile,
			variant.height_scale
		for path, i in variant.maps {
			if path == "" {continue}
			id, err := gpu_compute_texture_path(L, device, path, i == 0 || i == 6, mips)
			if err != "" {
				for prev in ids {if prev != 0 {_ = gpu.destroy_texture(device, prev)}}
				return gpu_compute_nil_error(L, err)
			}
			ids[i] = id
		}
	} else {
		if registry == nil {return gpu_compute_nil_error(L, "material enum unavailable")}
		item := enums.Arg_Item(L, 2, registry, "Material")
		index := int(item.value)
		if index < 0 ||
		   index >=
			   enums.MATERIAL_COUNT {return gpu_compute_nil_error(L, "unknown built-in material")}
		material := enums.Material(index)
		config := materials.builtin_material_configs[index]
		roughness, metallic, uv_scale, height_scale =
			config.roughness, config.metallic, config.uv_scale, config.height_scale
		names = {"Albedo", "Normal", "ORM", "Height", "", "", ""}
		for file in materials.builtin_material_files(material) {
			i := -1
			switch file.name {
			case "albedo.png", "albedo.jpg", "albedo.jpeg":
				i = 0
			case "normal.png", "normal.jpg", "normal.jpeg":
				i = 1
			case "orm.png", "orm.jpg", "orm.jpeg":
				i = 2
			case "height.png", "height.jpg", "height.jpeg":
				i = 3
			}
			if i < 0 {continue}
			id, err := gpu_compute_texture_encoded(device, file.data, i == 0, mips)
			if err != "" {
				for prev in ids {if prev != 0 {_ = gpu.destroy_texture(device, prev)}}
				return gpu_compute_nil_error(L, err)
			}
			if ids[i] != 0 {_ = gpu.destroy_texture(device, ids[i])}
			ids[i] = id
		}
	}
	vm.NewTable(L, 0, 12)
	for id, i in ids {
		if id != 0 {vm.PushNumber(L, f64(id)); vm.SetField(L, -2, names[i])}
	}
	vm.PushNumber(L, f64(roughness)); vm.SetField(L, -2, "Roughness")
	vm.PushNumber(L, f64(metallic)); vm.SetField(L, -2, "Metallic")
	vm.PushNumber(L, f64(uv_scale)); vm.SetField(L, -2, "UVScale")
	vm.PushNumber(L, f64(height_scale)); vm.SetField(L, -2, "HeightScale")
	return 1, true
}

gpu_compute_push_mesh :: proc(L: ^vm.State, vertices: [][8]f32, indices: []u32) -> (i32, bool) {
	vm.NewTable(L, 0, 6)
	vm.PushBuffer(
		L,
		(cast([^]u8)raw_data(vertices))[:len(vertices) * 32],
	); vm.SetField(L, -2, "Vertices")
	vm.PushBuffer(
		L,
		(cast([^]u8)raw_data(indices))[:len(indices) * 4],
	); vm.SetField(L, -2, "Indices")
	vm.PushNumber(L, f64(len(vertices))); vm.SetField(L, -2, "VertexCount")
	vm.PushNumber(L, f64(len(indices))); vm.SetField(L, -2, "IndexCount")
	vm.PushNumber(L, f64(len(indices) / 3)); vm.SetField(L, -2, "TriangleCount")
	vm.PushNumber(L, 32); vm.SetField(L, -2, "VertexStride")
	return 1, true
}

gpu_compute_load_mesh :: proc(L: ^vm.State, path: string, index: u32) -> (i32, bool) {
	if !assets.Is_Uri(path) &&
	   !strings.has_prefix(path, assets.PROJECT_ASSET_SCHEME) &&
	   !vm.ThreadHasSecurityCapability(L, datatypes.SECURITY_CAPABILITY_INTERNAL_STUDIO_ACCESS) {
		return gpu_compute_nil_error(L, "filesystem meshes require trusted editor permissions")
	}
	when ODIN_OS == .JS {return gpu_compute_nil_error(L, "Assimp mesh import unavailable on this platform")} else {
		when #config(BUILD_TARGET, "editor") != "editor" {
			if !assets.Is_Uri(path) &&
			   !strings.has_prefix(
					   path,
					   assets.PROJECT_ASSET_SCHEME,
				   ) {return gpu_compute_nil_error(L, "use a project or embedded mesh asset outside the editor")}
		}

		resolved := assets.Resolve_C_Path(path)
		defer delete(resolved)
		mesh: ^kineffi.KineFilamentMeshData
		if resolved !=
		   nil {mesh = kineffi.Kine_Filament_LoadMeshDataFromPathIndexed(resolved, index)}
		if mesh == nil {
			if bytes, found := assets.Resolve_Bytes(path); found && len(bytes) > 0 {
				hint := assets.Format_Hint(path)
				defer delete(hint)
				chint := strings.clone_to_cstring(hint)
				defer delete(chint)
				mesh = kineffi.Kine_Filament_LoadMeshDataFromMemoryIndexed(
					raw_data(bytes),
					uintptr(len(bytes)),
					chint,
					index,
				)
			}
		}
		if mesh == nil {return gpu_compute_nil_error(L, "Assimp could not import mesh")}
		defer kineffi.Kine_Filament_DestroyMeshData(mesh)
		count := kineffi.Kine_Filament_GetMeshDataVertexCount(mesh)
		icount := kineffi.Kine_Filament_GetMeshDataIndexCount(mesh)
		if count < 3 ||
		   count > gpu.MAX_CUSTOM_BUFFER_BYTES / 32 ||
		   icount < 3 ||
		   icount > gpu.MAX_CUSTOM_BUFFER_BYTES / 4 ||
		   icount % 3 != 0 {
			return gpu_compute_nil_error(L, "invalid or oversized mesh")
		}
		vertices := make([][8]f32, count)
		defer delete(vertices)
		indices := make([]u32, icount)
		defer delete(indices)
		if !kineffi.Kine_Filament_CopyMeshDataVertices(mesh, &vertices[0][0], count * 8) ||
		   kineffi.Kine_Filament_CopyMeshDataIndices(mesh, &indices[0], icount) == 0 {
			return gpu_compute_nil_error(L, "could not copy Assimp geometry")
		}
		for i in indices {if i >= u32(count) {return gpu_compute_nil_error(L, "invalid imported triangle index")}}
		return gpu_compute_push_mesh(L, vertices, indices)
	}
}

gpu_compute_resource_namecall :: proc(
	L: ^vm.State,
	compute: ^GPUCompute,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	device := &compute.device
	switch method {
	case "CreateTexture":
		desc := gpu.Texture_Desc {
			width     = 1,
			height    = 1,
			depth     = 1,
			layers    = 1,
			dimension = .D2,
		}
		pixels: []u8
		opt := 5
		if vm.IsTable(L, 2) {
			opt = 2
			desc.width = gpu_compute_option_int(L, 2, "Width", 1, 16384)
			desc.height = gpu_compute_option_int(L, 2, "Height", 1, 16384)
			desc.depth = gpu_compute_option_int(L, 2, "Depth", 1, 16384)
			desc.layers = gpu_compute_option_int(L, 2, "Layers", 1, 2048)
			switch gpu_compute_option_string(L, 2, "Dimension", "2D") {
			case "1D":
				desc.dimension = .D1
			case "2D":
				desc.dimension = .D2
			case "3D":
				desc.dimension = .D3
			case "2DArray":
				desc.dimension = .D2Array
			case:
				return gpu_compute_nil_error(L, "unknown texture dimension")
			}
			switch gpu_compute_option_string(L, 2, "Format", "RGBA8") {
			case "RGBA8":
				desc.format = .RGBA8
			case "RGBA8_SRGB":
				desc.format = .RGBA8_SRGB
			case "R8":
				desc.format = .R8
			case "RG8":
				desc.format = .RG8
			case "R32F":
				desc.format = .R32F
			case "RG32F":
				desc.format = .RG32F
			case "RGBA16F":
				desc.format = .RGBA16F
			case "RGBA32F":
				desc.format = .RGBA32F
			case "R32UI":
				desc.format = .R32UI
			case:
				return gpu_compute_nil_error(L, "unknown texture format")
			}
			if !vm.IsNoneOrNil(L, 3) {pixels = vm.ArgBuffer(L, 3)}
		} else {
			desc.width = gpu_compute_integer(L, 2, 1, 16384)
			desc.height = gpu_compute_integer(L, 3, 1, 16384)
			if !vm.IsNoneOrNil(L, 4) {pixels = vm.ArgBuffer(L, 4)}
			desc.format =
				gpu_compute_option_string(L, opt, "ColorSpace", "Linear") == "SRGB" ? .RGBA8_SRGB : .RGBA8
		}
		desc.writable = gpu_compute_option_bool(L, opt, "Storage", false)
		if vm.IsTable(L, opt) {
			if vm.GetField(L, opt, "Usage") == .Table {
				array_index := -1
				for i in 1 ..= vm.RawLen(L, array_index) {
					_ = vm.RawGetIndex(L, array_index, i)
					if vm.TypeOf(L, -1) == .String &&
					   vm.ArgString(L, -1) == "Storage" {desc.writable = true}
					vm.Pop(L)
				}
			}
			vm.Pop(L)
		}
		desc.mipmaps = gpu_compute_option_bool(L, opt, "GenerateMipmaps", false)
		desc.nearest = gpu_compute_option_string(L, opt, "Filter", "Linear") == "Nearest"
		desc.clamp = gpu_compute_option_string(L, opt, "AddressMode", "Repeat") == "ClampToEdge"
		id, err := gpu.create_texture_desc(device, desc, pixels)
		return gpu_compute_push_id(L, id, err)
	case "LoadTexture":
		srgb := gpu_compute_option_string(L, 3, "ColorSpace", "SRGB") == "SRGB"
		mips := gpu_compute_option_bool(L, 3, "GenerateMipmaps", false)
		nearest := gpu_compute_option_string(L, 3, "Filter", "Linear") == "Nearest"
		clamp_address := gpu_compute_option_string(L, 3, "AddressMode", "Repeat") == "ClampToEdge"
		if obj := object_from_argument(L, 2); obj != nil && Is_A(obj, "Image") {
			edit := cast(^EditableImage)obj
			id, err := gpu.create_texture_desc(
				device,
				{
					width = u32(edit.width),
					height = u32(edit.height),
					depth = 1,
					layers = 1,
					dimension = .D2,
					format = srgb ? .RGBA8_SRGB : .RGBA8,
					mipmaps = mips,
					nearest = nearest,
					clamp = clamp_address,
				},
				edit.pixels,
			)
			return gpu_compute_push_id(L, id, err)
		}
		if vm.IsBuffer(L, 2) {
			id, err := gpu_compute_texture_encoded(
				device,
				vm.ArgBuffer(L, 2),
				srgb,
				mips,
				nearest,
				clamp_address,
			)
			return gpu_compute_push_id(L, id, err)
		}
		path: string
		if dt != nil && vm.IsUserdataType(L, 2, &dt.content) {
			path = datatypes.Arg_Content(L, 2, dt).uri
		} else {path = vm.ArgString(L, 2)}
		id, err := gpu_compute_texture_path(L, device, path, srgb, mips, nearest, clamp_address)
		return gpu_compute_push_id(L, id, err)
	case "GetTextureInfo":
		info, err := gpu.get_texture_info(device, gpu_compute_buffer_id(L, 2))
		if err != "" {return gpu_compute_nil_error(L, err)}
		d := info.desc
		vm.NewTable(L, 0, 9)
		gpu_compute_set_number(L, "Width", d.width)
		gpu_compute_set_number(L, "Height", d.height)
		gpu_compute_set_number(L, "Depth", d.depth)
		gpu_compute_set_number(L, "Layers", d.layers)
		gpu_compute_set_number(L, "MipLevels", info.mip_levels)
		vm.PushString(L, gpu_compute_format_name(d.format)); vm.SetField(L, -2, "Format")
		dimensions := [4]string{"1D", "2D", "3D", "2DArray"}
		vm.PushString(L, dimensions[int(d.dimension)]); vm.SetField(L, -2, "Dimension")
		vm.PushBoolean(L, d.writable); vm.SetField(L, -2, "Storage")
		return 1, true
	case "BindTexture":
		return gpu_compute_result(
			L,
			gpu.bind_texture(
				device,
				gpu_compute_integer(L, 2, 0, gpu.MAX_CUSTOM_BINDINGS - 1),
				gpu_compute_buffer_id(L, 3),
			),
		)
	case "DestroyTexture":
		return gpu_compute_result(L, gpu.destroy_texture(device, gpu_compute_buffer_id(L, 2)))
	case "GetMaterialTextures":
		return gpu_compute_material(L, compute, en)
	case "LoadMesh":
		path: string
		if dt != nil && vm.IsUserdataType(L, 2, &dt.content) {
			content := datatypes.Arg_Content(L, 2, dt)
			if content.object_id != 0 {
				edit := EditableMesh_Of_Handle(content.object_id)
				if edit == nil ||
				   !Object_Is_Accessible(
						   L,
						   &edit.object,
					   ) {return gpu_compute_nil_error(L, "EditableMesh is unavailable")}
				return gpu_compute_editable_mesh(L, edit)
			}
			path = content.uri
		} else {path = vm.ArgString(L, 2)}
		index: u32
		if !vm.IsNoneOrNil(L, 3) {index = gpu_compute_integer(L, 3, 0, f64(max(u32)))}
		return gpu_compute_load_mesh(L, path, index)
	case "GetMeshFromInstance":
		obj := object_from_argument(L, 2)
		if obj != nil && Is_A(obj, "MeshPart") {
			part := cast(^MeshPart)obj
			if part.editable_mesh_id != 0 {
				edit := EditableMesh_Of_Handle(part.editable_mesh_id)
				if edit == nil {return gpu_compute_nil_error(L, "EditableMesh is unavailable")}
				return gpu_compute_editable_mesh(L, edit)
			}
			return gpu_compute_load_mesh(L, MeshPart_Source_Path(part), part.mesh_index)
		}
		if obj != nil &&
		   Is_A(obj, "EditableMesh") {return gpu_compute_editable_mesh(L, cast(^EditableMesh)obj)}
		return gpu_compute_nil_error(L, "expected MeshPart or EditableMesh")
	case "BuildBVH":
		if !vm.IsTable(L, 2) {return gpu_compute_nil_error(L, "expected a mesh table")}
		leaf: u32 = 4
		if vm.IsTable(L, 3) {leaf = gpu_compute_option_int(L, 3, "MaxLeafTriangles", 4, 64)}
		if vm.GetField(L, 2, "Vertices") !=
		   .Buffer {vm.Pop(L); return gpu_compute_nil_error(L, "mesh needs a Vertices buffer")}
		vertices := vm.ArgBuffer(L, -1)
		if vm.GetField(L, 2, "Indices") !=
		   .Buffer {vm.Pop(L); vm.Pop(L); return gpu_compute_nil_error(L, "mesh needs an Indices buffer")}
		indices := vm.ArgBuffer(L, -1)
		nodes, order, err := gpu.bvh_build(vertices, indices, int(leaf))
		vm.Pop(L); vm.Pop(L)
		if err != "" {return gpu_compute_nil_error(L, err)}
		defer delete(nodes)
		defer delete(order)
		vm.NewTable(L, 0, 4)
		vm.PushBuffer(
			L,
			(cast([^]u8)raw_data(nodes))[:len(nodes) * 32],
		); vm.SetField(L, -2, "Nodes")
		vm.PushBuffer(
			L,
			(cast([^]u8)raw_data(order))[:len(order) * 4],
		); vm.SetField(L, -2, "Triangles")
		gpu_compute_set_number(L, "NodeCount", u32(len(nodes)))
		gpu_compute_set_number(L, "TriangleCount", u32(len(order)))
		return 1, true
	case "GetCapabilities":
		caps, err := gpu.get_capabilities(device)
		if err != "" {return gpu_compute_nil_error(L, err)}
		vm.NewTable(L, 0, 20)
		n := 0
		for n < len(caps.name) && caps.name[n] != 0 {n += 1}
		vm.PushString(L, string(caps.name[:n])); vm.SetField(L, -2, "DeviceName")
		gpu_compute_set_number(L, "MaxBufferSize", caps.buffer_size)
		gpu_compute_set_number(L, "MaxUniformBufferSize", caps.uniform_size)
		gpu_compute_set_number(L, "MaxTextureSize", caps.texture_2d)
		gpu_compute_set_number(L, "MaxTextureSize1D", caps.texture_1d)
		gpu_compute_set_number(L, "MaxTextureSize3D", caps.texture_3d)
		gpu_compute_set_number(L, "MaxTextureLayers", caps.texture_layers)
		gpu_compute_set_number(L, "SharedMemorySize", caps.shared_memory)
		gpu_compute_set_number(L, "MaxWorkgroupInvocations", caps.workgroup_invocations)
		gpu_compute_set_number(L, "MaxBindings", gpu.MAX_CUSTOM_BINDINGS)
		gpu_compute_set_number(L, "ComputeQueueCount", caps.compute_queues)
		gpu_compute_set_number(L, "MaxPendingTasks", gpu.MAX_PARALLEL_TASKS)
		vm.PushBoolean(L, caps.compute_queues > 1); vm.SetField(L, -2, "ParallelQueues")
		vm.PushBoolean(L, caps.timeline_semaphores); vm.SetField(L, -2, "TimelineSemaphores")
		vm.NewTable(L, 3, 0)
		for v, i in caps.workgroup_size {vm.PushNumber(L, f64(v)); vm.RawSetIndex(L, -2, i + 1)}
		vm.SetField(L, -2, "MaxWorkgroupSize")
		vm.NewTable(L, 3, 0)
		for v, i in caps.workgroup_count {vm.PushNumber(L, f64(v)); vm.RawSetIndex(L, -2, i + 1)}
		vm.SetField(L, -2, "MaxWorkgroupCount")
		vm.PushBoolean(L, caps.float64); vm.SetField(L, -2, "Float64")
		vm.PushBoolean(L, caps.int64); vm.SetField(L, -2, "Int64")
		vm.PushBoolean(L, caps.int16); vm.SetField(L, -2, "Int16")
		vm.PushBoolean(L, caps.storage_extended); vm.SetField(L, -2, "ExtendedStorageFormats")
		vm.PushBoolean(L, true); vm.SetField(L, -2, "SampledTextures")
		vm.PushBoolean(L, false); vm.SetField(L, -2, "DescriptorIndexing")
		vm.PushBoolean(L, false); vm.SetField(L, -2, "RayQuery")
		return 1, true
	}
	return 0, false
}


gpu_compute_buffer_argument :: proc(L: ^vm.State, compute: ^GPUCompute, index: int) -> u32 {
	if vm.IsBuffer(L, index) {
		if entry := gpu_compute_lookup_luau(compute, vm.ArgBuffer(L, index));
		   entry != nil {return entry.id}
		return 0
	}
	return gpu_compute_buffer_id(L, index)
}

gpu_compute_optional_size :: proc(L: ^vm.State, index: int, fallback: int) -> int {
	if vm.IsNoneOrNil(L, index) {return fallback}
	return int(gpu_compute_integer(L, index, 0, gpu.MAX_CUSTOM_BUFFER_BYTES))
}


gpu_compute_format_name :: proc(format: gpu.Texture_Format) -> string {
	names := [9]string {
		"RGBA8",
		"RGBA8_SRGB",
		"R8",
		"RG8",
		"R32F",
		"RG32F",
		"RGBA16F",
		"RGBA32F",
		"R32UI",
	}
	return names[int(format)]
}

gpu_compute_option_int :: proc(
	L: ^vm.State,
	index: int,
	name: string,
	fallback, maximum: u32,
) -> u32 {
	_ = vm.GetField(L, index, name)
	result := fallback
	if !vm.IsNoneOrNil(L, -1) {result = gpu_compute_integer(L, -1, 1, f64(maximum))}
	vm.Pop(L)
	return result
}

gpu_compute_set_number :: proc(L: ^vm.State, name: string, value: u32) {
	vm.PushNumber(L, f64(value))
	vm.SetField(L, -2, name)
}


gpu_compute_editable_mesh :: proc(L: ^vm.State, mesh: ^EditableMesh) -> (i32, bool) {
	corners: [dynamic]EditableMesh_Corner_Data
	defer delete(corners)
	_ = EditableMesh_Collect_Triangles(mesh, &corners)
	if len(corners) < 3 ||
	   len(corners) >
		   gpu.MAX_CUSTOM_BUFFER_BYTES /
			   32 {return gpu_compute_nil_error(L, "invalid or oversized EditableMesh")}
	vertices := make([][8]f32, len(corners))
	defer delete(vertices)
	indices := make([]u32, len(corners))
	defer delete(indices)
	for v, i in corners {
		vertices[i] = {
			f32(v.position.x),
			f32(v.position.y),
			f32(v.position.z),
			f32(v.normal.x),
			f32(v.normal.y),
			f32(v.normal.z),
			v.uv.X,
			v.uv.Y,
		}
		indices[i] = u32(i)
	}
	return gpu_compute_push_mesh(L, vertices, indices)
}
