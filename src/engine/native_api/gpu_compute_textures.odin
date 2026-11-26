package native_api

import kineffi "../bindings"
import classes "../classes"
import gpu "../gpucompute"
import odin_runtime "base:runtime"
import "core:strings"

SDK_GPU_Texture_Desc :: struct {
	width, height, depth, layers:      u32,
	format, dimension:                 u32,
	writable, nearest, clamp, mipmaps: bool,
}

SDK_GPU_Texture_Info :: struct {
	desc:       SDK_GPU_Texture_Desc,
	mip_levels: u32,
}

SDK_GPU_Render_Stats :: struct {
	direct_texture_dispatches, direct_texture_bytes: u64,
	pixel_readback_bytes, pixel_upload_bytes:        u64,
}

@(export)
Kinemium_GPUComputeCreateTexture :: proc "c" (
	ctx: ^Context,
	desc: ^SDK_GPU_Texture_Desc,
	pixels: rawptr,
	pixel_bytes: u64,
	out: ^u32,
) -> bool {
	context = odin_runtime.default_context()
	if desc == nil || out == nil || !gpu_compute_check(ctx) {return false}
	if desc.format > u32(gpu.Texture_Format.R32UI) ||
	   desc.dimension > u32(gpu.Texture_Dimension.D2Array) ||
	   pixel_bytes > gpu.MAX_CUSTOM_BUFFER_BYTES ||
	   (pixels == nil && pixel_bytes != 0) {
		sdk_error(ctx, "invalid GPUCompute texture description or pixel data")
		return false
	}
	texture_desc := gpu.Texture_Desc {
		width     = desc.width,
		height    = desc.height,
		depth     = desc.depth,
		layers    = desc.layers,
		format    = gpu.Texture_Format(desc.format),
		dimension = gpu.Texture_Dimension(desc.dimension),
		writable  = desc.writable,
		nearest   = desc.nearest,
		clamp     = desc.clamp,
		mipmaps   = desc.mipmaps,
	}
	id, err := gpu.create_texture_desc(
		ctx.gpu_device,
		texture_desc,
		gpu_compute_slice(pixels, pixel_bytes),
	)
	return gpu_compute_id(ctx, id, err, out)
}

@(export)
Kinemium_GPUComputeGetTextureInfo :: proc "c" (
	ctx: ^Context,
	id: u32,
	out: ^SDK_GPU_Texture_Info,
) -> bool {
	context = odin_runtime.default_context()
	if out == nil || !gpu_compute_check(ctx) {return false}
	info, err := gpu.get_texture_info(ctx.gpu_device, id)
	if !gpu_compute_status(ctx, err) {return false}
	d := info.desc
	out^ = {
		desc = {
			width = d.width,
			height = d.height,
			depth = d.depth,
			layers = d.layers,
			format = u32(d.format),
			dimension = u32(d.dimension),
			writable = d.writable,
			nearest = d.nearest,
			clamp = d.clamp,
			mipmaps = d.mipmaps,
		},
		mip_levels = info.mip_levels,
	}
	return true
}

@(export)
Kinemium_GPUComputeBindTexture :: proc "c" (ctx: ^Context, binding, id: u32) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	return gpu_compute_status(ctx, gpu.bind_texture(ctx.gpu_device, binding, id))
}

@(export)
Kinemium_GPUComputeDestroyTexture :: proc "c" (ctx: ^Context, id: u32) -> bool {
	context = odin_runtime.default_context()
	if !gpu_compute_check(ctx) {return false}
	return gpu_compute_status(ctx, gpu.destroy_texture(ctx.gpu_device, id))
}


@(export)
Kinemium_GPUComputeDispatchMaterialTexture :: proc "c" (
	ctx: ^Context,
	variant_handle: u64,
	uniform_name, shader_source: cstring,
	width, height: u32,
) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil ||
	   !ctx.active ||
	   ctx.renderer == nil ||
	   uniform_name == nil ||
	   shader_source == nil {
		return false
	}
	object := resolve_handle(ctx, variant_handle)
	if object == nil || !classes.Is_A(object, "MaterialVariant") {
		sdk_error(ctx, "GPUCompute material target must be a live MaterialVariant")
		return false
	}
	variant := cast(^classes.MaterialVariant)object
	if variant.filament_shader == nil || variant.dirty || variant.compile_job != nil {
		sdk_error(ctx, "MaterialVariant must finish compiling before GPUCompute texture dispatch")
		return false
	}
	name := string(uniform_name)
	source := string(shader_source)
	if len(name) == 0 ||
	   len(name) > 256 ||
	   strings.contains(name, "\x00") ||
	   len(source) == 0 ||
	   len(source) > gpu.MAX_SHADER_SOURCE_BYTES ||
	   width == 0 ||
	   height == 0 ||
	   width > 1024 ||
	   height > 1024 {
		sdk_error(ctx, "invalid GPUCompute material texture name, dimensions, or shader source")
		return false
	}
	when kineffi.KINE_SHADER_COMPILER_LINKED {
		words: ^u32
		count: uint
		diagnostic: [4096]u8
		if kineffi.Kine_Shader_Compile(
			   raw_data(source),
			   uint(len(source)),
			   &words,
			   &count,
			   &diagnostic[0],
			   uint(len(diagnostic)),
		   ) ==
		   0 {
			n := 0
			for n < len(diagnostic) && diagnostic[n] != 0 {n += 1}
			sdk_error(
				ctx,
				n == 0 ? "GPUCompute material shader compile failed" : string(diagnostic[:n]),
			)
			return false
		}
		defer kineffi.Kine_Shader_Free(words)
		if words == nil || count < 5 || count > 4 * 1024 * 1024 {
			sdk_error(ctx, "GPUCompute material shader returned invalid SPIR-V")
			return false
		}
		if err := gpu.validate_render_texture_shader((cast([^]u32)words)[:int(count)]); err != "" {
			sdk_error(ctx, err)
			return false
		}
		c_name := strings.clone_to_cstring(name)
		defer delete(c_name)
		if !kineffi.Kine_Filament_Shader_DispatchTexture(
			variant.filament_shader,
			c_name,
			words,
			count * 4,
			width,
			height,
		) {
			sdk_error(
				ctx,
				"GPUCompute direct material texture dispatch requires a shared Vulkan renderer and sampler2d",
			)
			return false
		}
		variant.revision += 1
		classes.Render_3D_Mark_Dirty()
		sdk_clear_error(ctx)
		return true
	} else {
		sdk_error(
			ctx,
			"GPUCompute direct material texture shader compiler is unavailable on this platform",
		)
		return false
	}
}

@(export)
Kinemium_GPUComputeGetRenderStats :: proc "c" (out: ^SDK_GPU_Render_Stats) -> bool {
	context = odin_runtime.default_context()
	if out == nil {return false}
	data: [4]u64
	kineffi.Kine_Filament_ComputeTextureStats(&data[0])
	out^ = {data[0], data[1], data[2], data[3]}
	return true
}
