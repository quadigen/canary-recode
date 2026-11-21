#+build linux, windows
package gpucompute

import "core:math"
import vk "vendor:vulkan"

Custom_Texture :: struct {
	id:         u32,
	history:    Task_Access_History,
	desc:       Texture_Desc,
	mip_levels: u32,
	image:      vk.Image,
	memory:     vk.DeviceMemory,
	view:       vk.ImageView,
	sampler:    vk.Sampler,
	layout:     vk.ImageLayout,
	bytes:      int,
}

texture_find :: proc(device: ^Device, id: u32) -> ^Custom_Texture {
	if id == 0 {return nil}
	for &entry in device.custom.textures {if entry.id == id {return &entry}}
	return nil
}

texture_free :: proc(device: ^Device, t: ^Custom_Texture) {
	d := &device.procs
	h := device.handle
	if t.sampler != 0 {d.DestroySampler(h, t.sampler, nil)}
	if t.view != 0 {d.DestroyImageView(h, t.view, nil)}
	if t.image != 0 {d.DestroyImage(h, t.image, nil)}
	if t.memory != 0 {d.FreeMemory(h, t.memory, nil)}
	t^ = {}
}

create_texture :: proc(
	device: ^Device,
	width, height: u32,
	pixels: []u8,
	srgb: bool,
	writable: bool = false,
) -> (
	u32,
	string,
) {
	return create_texture_desc(
		device,
		{
			width = width,
			height = height,
			depth = 1,
			layers = 1,
			dimension = .D2,
			format = srgb ? .RGBA8_SRGB : .RGBA8,
			writable = writable,
		},
		pixels,
	)
}

texture_format_vk :: proc(format: Texture_Format) -> vk.Format {
	switch format {
	case .RGBA8:
		return .R8G8B8A8_UNORM
	case .RGBA8_SRGB:
		return .R8G8B8A8_SRGB
	case .R8:
		return .R8_UNORM
	case .RG8:
		return .R8G8_UNORM
	case .R32F:
		return .R32_SFLOAT
	case .RG32F:
		return .R32G32_SFLOAT
	case .RGBA16F:
		return .R16G16B16A16_SFLOAT
	case .RGBA32F:
		return .R32G32B32A32_SFLOAT
	case .R32UI:
		return .R32_UINT
	}
	return .UNDEFINED
}

create_texture_desc :: proc(
	device: ^Device,
	desc: Texture_Desc,
	pixels: []u8,
) -> (
	id: u32,
	err: string,
) {
	if reason := custom_idle(device); reason != "" {return 0, reason}
	width, height, depth, layers := desc.width, desc.height, desc.depth, desc.layers
	if width == 0 ||
	   height == 0 ||
	   depth == 0 ||
	   layers == 0 ||
	   max(width, height, depth) > 16384 ||
	   layers > 2048 {return 0, "invalid texture dimensions"}
	switch desc.dimension {
	case .D1:
		if height != 1 ||
		   depth != 1 ||
		   layers != 1 {return 0, "1D textures require height, depth and layers of one"}
	case .D2:
		if depth != 1 || layers != 1 {return 0, "2D textures require depth and layers of one"}
	case .D3:
		if layers != 1 {return 0, "3D texture arrays are unsupported"}
	case .D2Array:
		if depth != 1 {return 0, "2D texture arrays require depth of one"}
	}
	bytes_u64 :=
		u64(width) * u64(height) * u64(depth) * u64(layers) * texture_pixel_bytes(desc.format)
	if bytes_u64 == 0 ||
	   bytes_u64 >
		   MAX_CUSTOM_BUFFER_BYTES {return 0, "GPUCompute texture dimensions exceed limits"}
	bytes := int(bytes_u64)
	if pixels != nil &&
	   len(pixels) !=
		   bytes {return 0, "GPUCompute pixel buffer length does not match texture dimensions and format"}
	if desc.writable &&
	   desc.format == .RGBA8_SRGB {return 0, "storage textures require a linear format"}
	if desc.mipmaps &&
	   (desc.writable ||
			   desc.dimension != .D2 ||
			   (desc.format != .RGBA8 &&
					   desc.format !=
						   .RGBA8_SRGB)) {return 0, "mipmaps currently require sampled 2D RGBA8 textures"}
	mip_levels: u32 = 1
	upload_bytes := bytes
	if desc.mipmaps {
		w, h := width, height
		for w > 1 || h > 1 {
			w, h = max(w / 2, 1), max(h / 2, 1)
			upload_bytes += int(w) * int(h) * 4
			mip_levels += 1
		}
	}
	if upload_bytes > MAX_CUSTOM_BUFFER_BYTES {return 0, "texture mip data exceeds upload budget"}
	if reason := open(device); reason != "" {return 0, reason}
	caps := device.capabilities
	limit := caps.texture_2d
	if desc.dimension == .D1 {limit = caps.texture_1d}
	if desc.dimension == .D3 {limit = caps.texture_3d}
	if max(width, height, depth) > limit ||
	   layers > caps.texture_layers {return 0, "texture dimensions exceed device limit"}
	if desc.writable &&
	   !caps.storage_extended &&
	   (desc.format == .R8 ||
			   desc.format == .RG8 ||
			   desc.format ==
				   .RG32F) {return 0, "GPU does not support extended storage image formats"}
	c := &device.custom
	if c.total_bytes >
	   MAX_CUSTOM_TOTAL_BYTES - bytes {return 0, "GPUCompute resource budget exceeded"}
	if c.next_id == max(u32) {return 0, "GPUCompute IDs exhausted"}
	t: ^Custom_Texture
	for &entry in c.textures {if entry.id == 0 {t = &entry; break}}
	if t == nil {return 0, "GPUCompute texture count exceeded"}
	d := &device.procs
	h := device.handle
	defer {if err != "" {texture_free(device, t)}}
	format := texture_format_vk(desc.format)
	props: vk.FormatProperties
	device.format_properties(device.physical, format, &props)
	if .SAMPLED_IMAGE not_in
	   props.optimalTilingFeatures {return 0, "texture format cannot be sampled"}
	if desc.writable &&
	   .STORAGE_IMAGE not_in
		   props.optimalTilingFeatures {return 0, "texture format cannot be written"}
	usage: vk.ImageUsageFlags = {.SAMPLED, .TRANSFER_DST}
	if desc.writable {usage += {.STORAGE}}
	image_type: vk.ImageType = .D2
	view_type: vk.ImageViewType = .D2
	switch desc.dimension {
	case .D1:
		image_type, view_type = .D1, .D1
	case .D2:
	case .D3:
		image_type, view_type = .D3, .D3
	case .D2Array:
		view_type = .D2_ARRAY
	}
	info := vk.ImageCreateInfo {
		sType         = .IMAGE_CREATE_INFO,
		imageType     = image_type,
		format        = format,
		extent        = {width, height, depth},
		mipLevels     = mip_levels,
		arrayLayers   = layers,
		samples       = {._1},
		tiling        = .OPTIMAL,
		usage         = usage,
		sharingMode   = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}
	if d.CreateImage(h, &info, nil, &t.image) !=
	   .SUCCESS {return 0, "could not create compute image"}
	requirements: vk.MemoryRequirements
	d.GetImageMemoryRequirements(h, t.image, &requirements)
	if requirements.size >
	   vk.DeviceSize(
		   MAX_CUSTOM_TOTAL_BYTES - c.total_bytes,
	   ) {return 0, "GPUCompute image allocation exceeds budget"}
	for pass in 0 ..< 2 {
		for i in 0 ..< device.memory.memoryTypeCount {
			if requirements.memoryTypeBits & (u32(1) << i) == 0 {continue}
			if pass == 0 &&
			   .DEVICE_LOCAL not_in device.memory.memoryTypes[i].propertyFlags {continue}
			alloc := vk.MemoryAllocateInfo {
				sType           = .MEMORY_ALLOCATE_INFO,
				allocationSize  = requirements.size,
				memoryTypeIndex = i,
			}
			if d.AllocateMemory(h, &alloc, nil, &t.memory) == .SUCCESS {break}
		}
		if t.memory != 0 {break}
	}
	if t.memory == 0 ||
	   d.BindImageMemory(h, t.image, t.memory, 0) !=
		   .SUCCESS {return 0, "could not allocate compute image memory"}
	range := vk.ImageSubresourceRange {
		aspectMask = {.COLOR},
		levelCount = mip_levels,
		layerCount = layers,
	}
	view := vk.ImageViewCreateInfo {
		sType            = .IMAGE_VIEW_CREATE_INFO,
		image            = t.image,
		viewType         = view_type,
		format           = format,
		subresourceRange = range,
	}
	if d.CreateImageView(h, &view, nil, &t.view) !=
	   .SUCCESS {return 0, "could not create compute image view"}
	filter: vk.Filter = .NEAREST
	if !desc.nearest &&
	   desc.format != .R32UI &&
	   .SAMPLED_IMAGE_FILTER_LINEAR in props.optimalTilingFeatures {filter = .LINEAR}
	address: vk.SamplerAddressMode = desc.clamp ? .CLAMP_TO_EDGE : .REPEAT
	sampler := vk.SamplerCreateInfo {
		sType        = .SAMPLER_CREATE_INFO,
		magFilter    = filter,
		minFilter    = filter,
		mipmapMode   = filter == .LINEAR ? .LINEAR : .NEAREST,
		addressModeU = address,
		addressModeV = address,
		addressModeW = address,
		maxLod       = f32(mip_levels - 1),
	}
	if d.CreateSampler(h, &sampler, nil, &t.sampler) !=
	   .SUCCESS {return 0, "could not create compute image sampler"}
	staging: Storage
	defer custom_free_storage(device, &staging)
	if !create_storage(
		device,
		&staging,
		(upload_bytes + 3) &~ 3,
	) {return 0, "could not allocate texture staging buffer"}
	if pixels != nil {copy(staging.data, pixels)} else {for &v in staging.data {v = 0}}
	if mip_levels >
	   1 {texture_mip_chain(staging.data, width, height, mip_levels, desc.format == .RGBA8_SRGB)}
	command: vk.CommandBuffer
	fence: vk.Fence
	defer {
		if fence != 0 {d.DestroyFence(h, fence, nil)}
		if command != nil {d.FreeCommandBuffers(h, device.commands, 1, &command)}
	}
	ci := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = device.commands,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	if d.AllocateCommandBuffers(h, &ci, &command) !=
	   .SUCCESS {return 0, "could not allocate upload commands"}
	begin := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if d.BeginCommandBuffer(command, &begin) !=
	   .SUCCESS {return 0, "could not begin texture upload"}
	barrier := vk.ImageMemoryBarrier {
		sType               = .IMAGE_MEMORY_BARRIER,
		oldLayout           = .UNDEFINED,
		newLayout           = .TRANSFER_DST_OPTIMAL,
		dstAccessMask       = {.TRANSFER_WRITE},
		srcQueueFamilyIndex = max(u32),
		dstQueueFamilyIndex = max(u32),
		image               = t.image,
		subresourceRange    = range,
	}
	d.CmdPipelineBarrier(command, {.TOP_OF_PIPE}, {.TRANSFER}, {}, 0, nil, 0, nil, 1, &barrier)
	regions: [16]vk.BufferImageCopy
	mw, mh := width, height
	offset: int
	for i in 0 ..< mip_levels {
		regions[i] = {
			bufferOffset = vk.DeviceSize(offset),
			imageSubresource = {aspectMask = {.COLOR}, mipLevel = i, layerCount = layers},
			imageExtent = {mw, mh, depth},
		}
		offset +=
			int(mw) * int(mh) * int(depth) * int(layers) * int(texture_pixel_bytes(desc.format))
		mw, mh = max(mw / 2, 1), max(mh / 2, 1)
	}
	d.CmdCopyBufferToImage(
		command,
		staging.buffer,
		t.image,
		.TRANSFER_DST_OPTIMAL,
		mip_levels,
		&regions[0],
	)
	t.layout = .SHADER_READ_ONLY_OPTIMAL
	if desc.writable {t.layout = .GENERAL}
	barrier.oldLayout = .TRANSFER_DST_OPTIMAL
	barrier.newLayout = t.layout
	barrier.srcAccessMask = {.TRANSFER_WRITE}
	barrier.dstAccessMask = {.SHADER_READ}
	if desc.writable {barrier.dstAccessMask += {.SHADER_WRITE}}
	d.CmdPipelineBarrier(command, {.TRANSFER}, {.COMPUTE_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)
	if d.EndCommandBuffer(command) != .SUCCESS {return 0, "could not end texture upload"}
	fi := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
	}
	if d.CreateFence(h, &fi, nil, &fence) !=
	   .SUCCESS {return 0, "could not allocate texture upload fence"}
	submit := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &command,
	}
	if d.QueueSubmit(device.queue, 1, &submit, fence) !=
	   .SUCCESS {return 0, "could not submit texture upload"}
	if d.WaitForFences(h, 1, &fence, true, max(u64)) !=
	   .SUCCESS {return 0, "texture upload failed"}
	c.next_id += 1
	t.id, t.desc, t.mip_levels, t.bytes = c.next_id, desc, mip_levels, int(requirements.size)
	c.total_bytes += t.bytes
	return t.id, ""
}

bind_texture :: proc(device: ^Device, binding, id: u32) -> string {
	if reason := custom_bind_idle(device); reason != "" {return reason}
	c := &device.custom
	if binding >= c.shader.count {return "GPUCompute binding index is outside the compiled layout"}
	kind := c.shader.kinds[binding]
	if kind != .SampledTexture &&
	   kind != .StorageTexture {return "GPUCompute binding requires a buffer"}
	t := texture_find(device, id)
	if t == nil {return "unknown GPUCompute texture"}
	spec := c.shader.image_requirements[binding]
	if spec.declared &&
	   (spec.dimension != t.desc.dimension ||
			   spec.unsigned !=
				   (t.desc.format ==
						   .R32UI)) {return "texture dimension or sample type mismatches shader"}
	if kind == .StorageTexture &&
	   (!t.desc.writable ||
			   (spec.declared &&
					   spec.format !=
						   t.desc.format)) {return "storage texture usage or format mismatches shader"}
	c.bindings[binding] = id
	return ""
}

destroy_texture :: proc(device: ^Device, id: u32) -> string {
	if reason := parallel_cpu_idle(device); reason != "" {return reason}
	if task_resource_busy(device, id) {return "GPUCompute resource is in use by a task"}
	t := texture_find(device, id)
	if t == nil {return "unknown GPUCompute texture"}
	c := &device.custom
	for &binding, i in c.bindings {
		if binding == id &&
		   (c.shader.kinds[i] == .SampledTexture ||
				   c.shader.kinds[i] == .StorageTexture) {binding = 0}
	}
	for &pipeline in c.pipelines {pipeline_clear_binding(&pipeline, id, true)}
	pipeline_clear_binding(&c.legacy, id, true)
	c.total_bytes -= t.bytes
	texture_free(device, t)
	return ""
}


get_texture_info :: proc(device: ^Device, id: u32) -> (Texture_Info, string) {
	t := texture_find(device, id)
	if t == nil {return {}, "unknown GPUCompute texture"}
	return {desc = t.desc, mip_levels = t.mip_levels}, ""
}

texture_mip_chain :: proc(data: []u8, width, height, levels: u32, srgb: bool) {
	lut: [256]f32
	for &v, i in lut {
		v = f32(i) / 255
		if srgb {
			v = v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4)
		}
	}
	w, h := int(width), int(height)
	offset := 0
	for _ in 1 ..< levels {
		nw, nh := max(w / 2, 1), max(h / 2, 1)
		next_offset := offset + w * h * 4
		for y in 0 ..< nh {
			for x in 0 ..< nw {

				x0, x1 := x * w / nw, (x + 1) * w / nw
				y0, y1 := y * h / nh, (y + 1) * h / nh
				for c in 0 ..< 4 {
					sum: f32
					for sy in y0 ..< y1 {
						for sx in x0 ..< x1 {
							v := data[offset + (sy * w + sx) * 4 + c]
							sum += (srgb && c < 3) ? lut[v] : f32(v) / 255
						}
					}
					v := sum / f32((x1 - x0) * (y1 - y0))
					if srgb &&
					   c <
						   3 {v = v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1.0 / 2.4) - 0.055}
					data[next_offset + (y * nw + x) * 4 + c] = u8(clamp(v * 255 + 0.5, 0, 255))
				}
			}
		}
		offset, w, h = next_offset, nw, nh
	}
}
