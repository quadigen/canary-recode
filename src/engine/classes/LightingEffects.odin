package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

LightingEffect_Class := Class_Info {
	name   = "LightingEffect",
	parent = &Instance_Class,
}
BlurEffect_Class := Class_Info {
	name   = "BlurEffect",
	parent = &LightingEffect_Class,
}
BloomEffect_Class := Class_Info {
	name   = "BloomEffect",
	parent = &LightingEffect_Class,
}
ColorCorrectionEffect_Class := Class_Info {
	name   = "ColorCorrectionEffect",
	parent = &LightingEffect_Class,
}
DepthOfFieldEffect_Class := Class_Info {
	name   = "DepthOfFieldEffect",
	parent = &LightingEffect_Class,
}
SunRaysEffect_Class := Class_Info {
	name   = "SunRaysEffect",
	parent = &LightingEffect_Class,
}
SSAOEffect_Class := Class_Info {
	name   = "SSAOEffect",
	parent = &LightingEffect_Class,
}
Atmosphere_Class := Class_Info {
	name   = "Atmosphere",
	parent = &LightingEffect_Class,
}
AntiAliasingEffect_Class := Class_Info {
	name   = "AntiAliasingEffect",
	parent = &LightingEffect_Class,
}
DitheringEffect_Class := Class_Info {
	name   = "DitheringEffect",
	parent = &LightingEffect_Class,
}
RenderQualityEffect_Class := Class_Info {
	name   = "RenderQualityEffect",
	parent = &LightingEffect_Class,
}
VignetteEffect_Class := Class_Info {
	name   = "VignetteEffect",
	parent = &LightingEffect_Class,
}
ScreenSpaceReflectionsEffect_Class := Class_Info {
	name   = "ScreenSpaceReflectionsEffect",
	parent = &LightingEffect_Class,
}

LightingEffect :: struct {
	using object: Object,
	enabled:      bool,
}

BlurEffect :: struct {
	using effect: LightingEffect,
	size:         f64,
}

BloomEffect :: struct {
	using effect: LightingEffect,
	intensity:    f64,
	size:         f64,
	threshold:    f64,
	lens_flare:   bool,
}

ColorCorrectionEffect :: struct {
	using effect: LightingEffect,
	brightness:   f64,
	contrast:     f64,
	saturation:   f64,
	tint_color:   datatypes.Color3,
}

DepthOfFieldEffect :: struct {
	using effect:    LightingEffect,
	far_intensity:   f64,
	focus_distance:  f64,
	in_focus_radius: f64,
	near_intensity:  f64,
}

SunRaysEffect :: struct {
	using effect: LightingEffect,
	intensity:    f64,
	spread:       f64,
}

SSAOEffect :: struct {
	using effect: LightingEffect,
	radius:       f64,
	power:        f64,
	intensity:    f64,
	quality:      i64,
	ao_type:      i64,
}

Atmosphere :: struct {
	using effect:  LightingEffect,
	density:       f64,
	offset:        f64,
	color:         datatypes.Color3,
	decay:         datatypes.Color3,
	glare:         f64,
	haze:          f64,
	sun_direction: datatypes.Vector3,
	sky_color:     datatypes.Color3,
	horizon_color: datatypes.Color3,
	ground_color:  datatypes.Color3,
	sun_intensity: f64,
}

// AntiAliasingEffect exposes Filament's three edge-anti-aliasing modes. They
// are independent flags rather than one enum because Filament configures them
// that way, and because FXAA and MSAA cost real frame time on a blocky scene.
//
// SampleCount is stored as f64 and exchanged with the VM as a number. Luau's
// 64-bit integer type is distinct from number, so an integer-typed property
// rejects a plain `SampleCount = 8` and reads back as something that does not
// compare equal to a number literal.
AntiAliasingEffect :: struct {
	using effect: LightingEffect,
	fxaa:         bool,
	taa:          bool,
	msaa:         bool,
	sample_count: f64,
}

// DitheringEffect maps to Filament's temporal dithering, which trades a little
// temporal noise for the removal of banding in smooth gradients.
DitheringEffect :: struct {
	using effect: LightingEffect,
}

// RenderQualityEffect selects Filament's HDR quality level, which is what
// post-processing gets to work with. 0 LOW, 1 MEDIUM, 2 HIGH, 3 ULTRA, matching
// the shim's kine_quality_from_int. Held as f64 for the same reason
// AntiAliasingEffect.SampleCount is.
RenderQualityEffect :: struct {
	using effect: LightingEffect,
	quality:      f64,
}

// VignetteEffect darkens the frame corners.
VignetteEffect :: struct {
	using effect: LightingEffect,
	midpoint:     f64,
	roundness:    f64,
	feather:      f64,
	color:        datatypes.Color3,
	transparency: f64,
}

ScreenSpaceReflectionsEffect :: struct {
	using effect: LightingEffect,
	thickness:    f64,
	bias:         f64,
	max_distance: f64,
	stride:       f64,
}

lighting_effect_init :: proc(class: ^Class_Info, name: string) -> LightingEffect {
	return LightingEffect{object = Object_Init(class, name), enabled = true}
}

BlurEffect_Init :: proc() -> BlurEffect {
	return BlurEffect{effect = lighting_effect_init(&BlurEffect_Class, "BlurEffect"), size = 10}
}

BloomEffect_Init :: proc() -> BloomEffect {
	return BloomEffect {
		effect = lighting_effect_init(&BloomEffect_Class, "BloomEffect"),
		intensity = 0.5,
		size = 50,
		threshold = 1,
	}
}

ColorCorrectionEffect_Init :: proc() -> ColorCorrectionEffect {
	return ColorCorrectionEffect {
		effect = lighting_effect_init(&ColorCorrectionEffect_Class, "ColorCorrectionEffect"),
		tint_color = datatypes.Color3{1, 1, 1},
	}
}

DepthOfFieldEffect_Init :: proc() -> DepthOfFieldEffect {
	return DepthOfFieldEffect {
		effect = lighting_effect_init(&DepthOfFieldEffect_Class, "DepthOfFieldEffect"),
		far_intensity = 0.25,
		focus_distance = 10,
		in_focus_radius = 10,
		near_intensity = 0.25,
	}
}

SunRaysEffect_Init :: proc() -> SunRaysEffect {
	return SunRaysEffect {
		effect = lighting_effect_init(&SunRaysEffect_Class, "SunRaysEffect"),
		intensity = 0.1,
		spread = 1,
	}
}

SSAOEffect_Init :: proc() -> SSAOEffect {
	return SSAOEffect {
		effect = lighting_effect_init(&SSAOEffect_Class, "SSAOEffect"),
		radius = 0.3,
		power = 1,
		intensity = 1,
		quality = 2,
	}
}

// Every anti-aliasing mode defaults off. The engine used to force FXAA on and
// it cost visible frame time, so opting in has to be deliberate.
AntiAliasingEffect_Init :: proc() -> AntiAliasingEffect {
	return AntiAliasingEffect {
		effect = lighting_effect_init(&AntiAliasingEffect_Class, "AntiAliasingEffect"),
		sample_count = 4,
	}
}

DitheringEffect_Init :: proc() -> DitheringEffect {
	return DitheringEffect {
		effect = lighting_effect_init(&DitheringEffect_Class, "DitheringEffect"),
	}
}

RenderQualityEffect_Init :: proc() -> RenderQualityEffect {
	return RenderQualityEffect {
		effect  = lighting_effect_init(&RenderQualityEffect_Class, "RenderQualityEffect"),
		// MEDIUM is Filament's own default, so enabling this instance is a
		// no-op until the quality is actually moved.
		quality = 1,
	}
}

VignetteEffect_Init :: proc() -> VignetteEffect {
	return VignetteEffect {
		effect = lighting_effect_init(&VignetteEffect_Class, "VignetteEffect"),
		midpoint = 0.5,
		roundness = 0.4,
		feather = 0.5,
		color = datatypes.Color3{0, 0, 0},
		transparency = 0.25,
	}
}

ScreenSpaceReflectionsEffect_Init :: proc() -> ScreenSpaceReflectionsEffect {
	// These match the values the lighting step used to hardcode, so enabling
	// the instance without touching them reproduces the previous behaviour.
	return ScreenSpaceReflectionsEffect {
		effect = lighting_effect_init(
			&ScreenSpaceReflectionsEffect_Class,
			"ScreenSpaceReflectionsEffect",
		),
		thickness = 0.5,
		bias = 0.05,
		max_distance = 10.0,
		stride = 0.5,
	}
}

Atmosphere_Init :: proc() -> Atmosphere {
	return Atmosphere {
		effect = lighting_effect_init(&Atmosphere_Class, "Atmosphere"),
		density = 0.3,
		color = datatypes.Color3{0.78, 0.86, 1},
		decay = datatypes.Color3{0.35, 0.45, 0.6},
		glare = 0,
		haze = 0,
		sun_direction = datatypes.Vector3{0.35, 0.85, 0.25},
		sky_color = datatypes.Color3{0.32, 0.58, 0.95},
		horizon_color = datatypes.Color3{0.78, 0.86, 1},
		ground_color = datatypes.Color3{0.1, 0.12, 0.14},
		sun_intensity = 100000,
	}
}

lighting_effect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	effect := new(LightingEffect)
	effect^ = lighting_effect_init(&LightingEffect_Class, "LightingEffect")
	return &effect.object
}

BlurEffect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {effect :=
		new(BlurEffect)
	effect^ = BlurEffect_Init()
	return &effect.object}
	
BloomEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {effect := new(BloomEffect); effect^ = BloomEffect_Init(); return &effect.object}
ColorCorrectionEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {effect := new(ColorCorrectionEffect); effect^ = ColorCorrectionEffect_Init(); return(
		&effect.object \
	)}
DepthOfFieldEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {effect := new(DepthOfFieldEffect); effect^ = DepthOfFieldEffect_Init(); return(
		&effect.object \
	)}
SunRaysEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {effect := new(SunRaysEffect); effect^ = SunRaysEffect_Init(); return &effect.object}
SSAOEffect_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {effect :=
		new(SSAOEffect)
	effect^ = SSAOEffect_Init()
	return &effect.object}
Atmosphere_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {effect :=
		new(Atmosphere)
	effect^ = Atmosphere_Init()
	return &effect.object}
AntiAliasingEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {effect := new(AntiAliasingEffect); effect^ = AntiAliasingEffect_Init(); return(
		&effect.object \
	)}
DitheringEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {effect := new(DitheringEffect); effect^ = DitheringEffect_Init(); return(
		&effect.object \
	)}
RenderQualityEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {effect := new(RenderQualityEffect); effect^ = RenderQualityEffect_Init(); return(
		&effect.object \
	)}
VignetteEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {effect := new(VignetteEffect); effect^ = VignetteEffect_Init(); return(
		&effect.object \
	)}
ScreenSpaceReflectionsEffect_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {effect := new(ScreenSpaceReflectionsEffect); effect^ =
		ScreenSpaceReflectionsEffect_Init()
	return &effect.object}

lighting_effect_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {Object_Destroy(
		object,
	)
	free(object)}

lighting_effect_get :: proc(
	L: ^vm.State,
	object: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
) -> bool {
	if Is_A(object, "LightingEffect") {
		effect := cast(^LightingEffect)object
		if key == "Enabled" {vm.PushBoolean(L, effect.enabled); return true}
	}
	switch Get_Class_Name(object) {
	case "BlurEffect":
		value := cast(^BlurEffect)object
		if key == "Size" {vm.PushNumber(L, value.size); return true}
	case "BloomEffect":
		value := cast(^BloomEffect)object
		switch key {case "Intensity":
			vm.PushNumber(L, value.intensity); case "Size":
			vm.PushNumber(L, value.size); case "Threshold":
			vm.PushNumber(L, value.threshold); case "LensFlare":
			vm.PushBoolean(L, value.lens_flare); case:
			return false}; return true
	case "ColorCorrectionEffect":
		value := cast(^ColorCorrectionEffect)object
		switch key {case "Brightness":
			vm.PushNumber(L, value.brightness); case "Contrast":
			vm.PushNumber(L, value.contrast); case "Saturation":
			vm.PushNumber(L, value.saturation); case "TintColor":
			datatypes.Push_Color3(L, dr, value.tint_color); case:
			return false}; return true
	case "DepthOfFieldEffect":
		value := cast(^DepthOfFieldEffect)object
		switch key {case "FarIntensity":
			vm.PushNumber(L, value.far_intensity); case "FocusDistance":
			vm.PushNumber(L, value.focus_distance); case "InFocusRadius":
			vm.PushNumber(L, value.in_focus_radius); case "NearIntensity":
			vm.PushNumber(L, value.near_intensity); case:
			return false}; return true
	case "SunRaysEffect":
		value := cast(^SunRaysEffect)object
		switch key {case "Intensity":
			vm.PushNumber(L, value.intensity); case "Spread":
			vm.PushNumber(L, value.spread); case:
			return false}; return true
	case "SSAOEffect":
		value := cast(^SSAOEffect)object
		switch key {case "Radius":
			vm.PushNumber(L, value.radius); case "Power":
			vm.PushNumber(L, value.power); case "Intensity":
			vm.PushNumber(L, value.intensity); case "Quality":
			vm.PushInteger(L, value.quality); case "AOType":
			vm.PushInteger(L, value.ao_type); case:
			return false}; return true
	case "Atmosphere":
		value := cast(^Atmosphere)object
		switch key {
		case "Density":
			vm.PushNumber(L, value.density)
		case "Offset":
			vm.PushNumber(L, value.offset)
		case "Color":
			datatypes.Push_Color3(L, dr, value.color)
		case "Decay":
			datatypes.Push_Color3(L, dr, value.decay)
		case "Glare":
			vm.PushNumber(L, value.glare)
		case "Haze":
			vm.PushNumber(L, value.haze)
		case "SunDirection":
			datatypes.Push_Vector3(L, value.sun_direction)
		case "SkyColor":
			datatypes.Push_Color3(L, dr, value.sky_color)
		case "HorizonColor":
			datatypes.Push_Color3(L, dr, value.horizon_color)
		case "GroundColor":
			datatypes.Push_Color3(L, dr, value.ground_color)
		case "SunIntensity":
			vm.PushNumber(L, value.sun_intensity)
		case:
			return false
		}; return true
	case "AntiAliasingEffect":
		value := cast(^AntiAliasingEffect)object
		switch key {
		case "FXAA":
			vm.PushBoolean(L, value.fxaa)
		case "TAA":
			vm.PushBoolean(L, value.taa)
		case "MSAA":
			vm.PushBoolean(L, value.msaa)
		case "SampleCount":
			vm.PushNumber(L, value.sample_count)
		case:
			return false
		}; return true
	case "DitheringEffect":
		// Dithering is a pure on/off, so Enabled is the whole contract and it
		// is already handled by the LightingEffect branch above.
		return false
	case "RenderQualityEffect":
		value := cast(^RenderQualityEffect)object
		switch key {
		case "Quality":
			vm.PushNumber(L, value.quality)
		case:
			return false
		}; return true
	case "VignetteEffect":
		value := cast(^VignetteEffect)object
		switch key {
		case "Midpoint":
			vm.PushNumber(L, value.midpoint)
		case "Roundness":
			vm.PushNumber(L, value.roundness)
		case "Feather":
			vm.PushNumber(L, value.feather)
		case "Color":
			datatypes.Push_Color3(L, dr, value.color)
		case "Transparency":
			vm.PushNumber(L, value.transparency)
		case:
			return false
		}; return true
	case "ScreenSpaceReflectionsEffect":
		value := cast(^ScreenSpaceReflectionsEffect)object
		switch key {
		case "Thickness":
			vm.PushNumber(L, value.thickness)
		case "Bias":
			vm.PushNumber(L, value.bias)
		case "MaxDistance":
			vm.PushNumber(L, value.max_distance)
		case "Stride":
			vm.PushNumber(L, value.stride)
		case:
			return false
		}; return true
	}
	return false
}

lighting_effect_set :: proc(
	L: ^vm.State,
	object: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	if Is_A(object, "LightingEffect") && key == "Enabled" {
		effect := cast(^LightingEffect)object
		effect.enabled = vm.ArgBoolean(L, index)
		return true
	}
	switch Get_Class_Name(object) {
	case "BlurEffect":
		if key == "Size" {
			value := cast(^BlurEffect)object
			value.size = max(0, vm.ArgNumber(L, index))
			return true
		}
	case "BloomEffect":
		value := cast(^BloomEffect)object; switch key {case "Intensity":
			value.intensity = max(0, vm.ArgNumber(L, index)); case "Size":
			value.size = max(0, vm.ArgNumber(L, index)); case "Threshold":
			value.threshold = max(0, vm.ArgNumber(L, index)); case "LensFlare":
			value.lens_flare = vm.ArgBoolean(L, index); case:
			return false}; return true
	case "ColorCorrectionEffect":
		value := cast(^ColorCorrectionEffect)object; switch key {case "Brightness":
			value.brightness = clamp(vm.ArgNumber(L, index), -1, 1); case "Contrast":
			value.contrast = clamp(vm.ArgNumber(L, index), -1, 1); case "Saturation":
			value.saturation = clamp(vm.ArgNumber(L, index), -1, 1); case "TintColor":
			value.tint_color = datatypes.Arg_Color3(L, index, dr); case:
			return false}; return true
	case "DepthOfFieldEffect":
		value := cast(^DepthOfFieldEffect)object; switch key {case "FarIntensity":
			value.far_intensity = clamp(vm.ArgNumber(L, index), 0, 1); case "FocusDistance":
			value.focus_distance = max(0.001, vm.ArgNumber(L, index)); case "InFocusRadius":
			value.in_focus_radius = max(0, vm.ArgNumber(L, index)); case "NearIntensity":
			value.near_intensity = clamp(vm.ArgNumber(L, index), 0, 1); case:
			return false}; return true
	case "SunRaysEffect":
		value := cast(^SunRaysEffect)object; switch key {case "Intensity":
			value.intensity = clamp(vm.ArgNumber(L, index), 0, 1); case "Spread":
			value.spread = clamp(vm.ArgNumber(L, index), 0, 1); case:
			return false}; return true
	case "SSAOEffect":
		value := cast(^SSAOEffect)object; switch key {case "Radius":
			value.radius = max(0, vm.ArgNumber(L, index)); case "Power":
			value.power = max(0.001, vm.ArgNumber(L, index)); case "Intensity":
			value.intensity = max(0, vm.ArgNumber(L, index)); case "Quality":
			value.quality = clamp(vm.ArgInteger(L, index), 0, 3); case "AOType":
			value.ao_type = clamp(vm.ArgInteger(L, index), 0, 1); case:
			return false}; return true
	case "Atmosphere":
		value := cast(^Atmosphere)object; switch key {case "Density":
			value.density = clamp(vm.ArgNumber(L, index), 0, 1); case "Offset":
			value.offset = clamp(vm.ArgNumber(L, index), -1, 1); case "Color":
			value.color = datatypes.Arg_Color3(L, index, dr); case "Decay":
			value.decay = datatypes.Arg_Color3(L, index, dr); case "Glare":
			value.glare = clamp(vm.ArgNumber(L, index), 0, 1); case "Haze":
			value.haze = max(0, vm.ArgNumber(L, index)); case "SunDirection":
			value.sun_direction = datatypes.Arg_Vector3(L, index); case "SkyColor":
			value.sky_color = datatypes.Arg_Color3(L, index, dr); case "HorizonColor":
			value.horizon_color = datatypes.Arg_Color3(L, index, dr); case "GroundColor":
			value.ground_color = datatypes.Arg_Color3(L, index, dr); case "SunIntensity":
			value.sun_intensity = max(0, vm.ArgNumber(L, index)); case:
			return false}; return true
	case "AntiAliasingEffect":
		// The modes are independent booleans rather than a single enum so a
		// place can pick exactly the one it is willing to pay for.
		value := cast(^AntiAliasingEffect)object; switch key {case "FXAA":
			value.fxaa = vm.ArgBoolean(L, index); case "TAA":
			value.taa = vm.ArgBoolean(L, index); case "MSAA":
			value.msaa = vm.ArgBoolean(L, index); case "SampleCount":
			value.sample_count = clamp(vm.ArgNumber(L, index), 1, 8); case:
			return false}; return true
	case "DitheringEffect":
		return false
	case "RenderQualityEffect":
		// 0 LOW, 1 MEDIUM, 2 HIGH, 3 ULTRA. Clamped because the shim maps an
		// out-of-range integer onto MEDIUM, which would silently override the
		// value the script just set.
		value := cast(^RenderQualityEffect)object; switch key {case "Quality":
			value.quality = clamp(vm.ArgNumber(L, index), 0, 3); case:
			return false}; return true
	case "VignetteEffect":
		value := cast(^VignetteEffect)object; switch key {case "Midpoint":
			value.midpoint = clamp(vm.ArgNumber(L, index), 0, 1); case "Roundness":
			value.roundness = clamp(vm.ArgNumber(L, index), 0, 1); case "Feather":
			value.feather = clamp(vm.ArgNumber(L, index), 0, 1); case "Color":
			value.color = datatypes.Arg_Color3(L, index, dr); case "Transparency":
			value.transparency = clamp(vm.ArgNumber(L, index), 0, 1); case:
			return false}; return true
	case "ScreenSpaceReflectionsEffect":
		// Thickness, Bias and Stride are Filament tuning dials with no natural
		// upper bound, so only the ones that cannot be nonsensical are clamped.
		// MaxDistance is floored at zero because a negative range would make
		// Filament trace backwards.
		value := cast(^ScreenSpaceReflectionsEffect)object; switch key {case "Thickness":
			value.thickness = max(0, vm.ArgNumber(L, index)); case "Bias":
			value.bias = vm.ArgNumber(L, index); case "MaxDistance":
			value.max_distance = max(0, vm.ArgNumber(L, index)); case "Stride":
			value.stride = max(0, vm.ArgNumber(L, index)); case:
			return false}; return true
	}
	return false
}

lighting_effect_clone :: proc(source: ^Object, destination: ^Object) {
	if source == nil || destination == nil {return}
	switch Get_Class_Name(source) {
	case "LightingEffect":
		src, dst := cast(^LightingEffect)source, cast(^LightingEffect)destination
		dst.enabled = src.enabled
	case "BlurEffect":
		src, dst := cast(^BlurEffect)source, cast(^BlurEffect)destination
		dst.enabled, dst.size = src.enabled, src.size
	case "BloomEffect":
		src, dst := cast(^BloomEffect)source, cast(^BloomEffect)destination
		dst.enabled, dst.intensity, dst.size, dst.threshold, dst.lens_flare =
			src.enabled, src.intensity, src.size, src.threshold, src.lens_flare
	case "ColorCorrectionEffect":
		src, dst := cast(^ColorCorrectionEffect)source, cast(^ColorCorrectionEffect)destination
		dst.enabled, dst.brightness, dst.contrast, dst.saturation, dst.tint_color =
			src.enabled, src.brightness, src.contrast, src.saturation, src.tint_color
	case "DepthOfFieldEffect":
		src, dst := cast(^DepthOfFieldEffect)source, cast(^DepthOfFieldEffect)destination
		dst.enabled, dst.far_intensity, dst.focus_distance, dst.in_focus_radius, dst.near_intensity =
			src.enabled,
			src.far_intensity,
			src.focus_distance,
			src.in_focus_radius,
			src.near_intensity
	case "SunRaysEffect":
		src, dst := cast(^SunRaysEffect)source, cast(^SunRaysEffect)destination
		dst.enabled, dst.intensity, dst.spread = src.enabled, src.intensity, src.spread
	case "SSAOEffect":
		src, dst := cast(^SSAOEffect)source, cast(^SSAOEffect)destination
		dst.enabled, dst.radius, dst.power, dst.intensity, dst.quality, dst.ao_type =
			src.enabled, src.radius, src.power, src.intensity, src.quality, src.ao_type
	case "Atmosphere":
		src, dst := cast(^Atmosphere)source, cast(^Atmosphere)destination
		dst.enabled, dst.density, dst.offset = src.enabled, src.density, src.offset
		dst.color, dst.decay = src.color, src.decay
		dst.glare, dst.haze, dst.sun_direction = src.glare, src.haze, src.sun_direction
		dst.sky_color, dst.horizon_color, dst.ground_color =
			src.sky_color, src.horizon_color, src.ground_color
		dst.sun_intensity = src.sun_intensity
	case "AntiAliasingEffect":
		src, dst := cast(^AntiAliasingEffect)source, cast(^AntiAliasingEffect)destination
		dst.enabled, dst.fxaa, dst.taa, dst.msaa = src.enabled, src.fxaa, src.taa, src.msaa
		dst.sample_count = src.sample_count
	case "DitheringEffect":
		src, dst := cast(^DitheringEffect)source, cast(^DitheringEffect)destination
		dst.enabled = src.enabled
	case "RenderQualityEffect":
		src, dst := cast(^RenderQualityEffect)source, cast(^RenderQualityEffect)destination
		dst.enabled, dst.quality = src.enabled, src.quality
	case "VignetteEffect":
		src, dst := cast(^VignetteEffect)source, cast(^VignetteEffect)destination
		dst.enabled = src.enabled
		dst.midpoint, dst.roundness, dst.feather = src.midpoint, src.roundness, src.feather
		dst.color, dst.transparency = src.color, src.transparency
	case "ScreenSpaceReflectionsEffect":
		src, dst :=
			cast(^ScreenSpaceReflectionsEffect)source,
			cast(^ScreenSpaceReflectionsEffect)destination
		dst.enabled = src.enabled
		dst.thickness, dst.bias = src.thickness, src.bias
		dst.max_distance, dst.stride = src.max_distance, src.stride
	}
}

Register_Lighting_Effect :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&LightingEffect_Class,
		lighting_effect_construct,
		lighting_effect_destroy,
		get = lighting_effect_get,
		set = lighting_effect_set,
		clone = lighting_effect_clone,
		properties = []string{"Enabled"},
	)
	Register_Class(
		registry,
		&BlurEffect_Class,
		BlurEffect_construct,
		lighting_effect_destroy,
		get = lighting_effect_get,
		set = lighting_effect_set,
		clone = lighting_effect_clone,
		properties = []string{"Enabled", "Size"},
	)
	Register_Class(
		registry,
		&BloomEffect_Class,
		BloomEffect_construct,
		lighting_effect_destroy,
		get = lighting_effect_get,
		set = lighting_effect_set,
		clone = lighting_effect_clone,
		properties = []string{"Enabled", "Intensity", "Size", "Threshold", "LensFlare"},
	)
	Register_Class(
		registry,
		&ColorCorrectionEffect_Class,
		ColorCorrectionEffect_construct,
		lighting_effect_destroy,
		get = lighting_effect_get,
		set = lighting_effect_set,
		clone = lighting_effect_clone,
		properties = []string{"Enabled", "Brightness", "Contrast", "Saturation", "TintColor"},
	)
	Register_Class(
		registry,
		&DepthOfFieldEffect_Class,
		DepthOfFieldEffect_construct,
		lighting_effect_destroy,
		get = lighting_effect_get,
		set = lighting_effect_set,
		clone = lighting_effect_clone,
		properties = []string {
			"Enabled",
			"FarIntensity",
			"FocusDistance",
			"InFocusRadius",
			"NearIntensity",
		},
	)
	Register_Class(
		registry,
		&SunRaysEffect_Class,
		SunRaysEffect_construct,
		lighting_effect_destroy,
		get = lighting_effect_get,
		set = lighting_effect_set,
		clone = lighting_effect_clone,
		properties = []string{"Enabled", "Intensity", "Spread"},
	)
	Register_Class(
		registry,
		&SSAOEffect_Class,
		SSAOEffect_construct,
		lighting_effect_destroy,
		get = lighting_effect_get,
		set = lighting_effect_set,
		clone = lighting_effect_clone,
		properties = []string{"Enabled", "Radius", "Power", "Intensity", "Quality", "AOType"},
	)
	Register_Class(
		registry,
		&Atmosphere_Class,
		Atmosphere_construct,
		lighting_effect_destroy,
		get = lighting_effect_get,
		set = lighting_effect_set,
		clone = lighting_effect_clone,
		properties = []string {
			"Enabled",
			"Density",
			"Offset",
			"Color",
			"Decay",
			"Glare",
			"Haze",
			"SunDirection",
			"SkyColor",
			"HorizonColor",
			"GroundColor",
			"SunIntensity",
		},
	)
	Register_Class(
		registry,
		&AntiAliasingEffect_Class,
		AntiAliasingEffect_construct,
		lighting_effect_destroy,
		get = lighting_effect_get,
		set = lighting_effect_set,
		clone = lighting_effect_clone,
		properties = []string{"Enabled", "FXAA", "TAA", "MSAA", "SampleCount"},
	)
	Register_Class(
		registry,
		&DitheringEffect_Class,
		DitheringEffect_construct,
		lighting_effect_destroy,
		get = lighting_effect_get,
		set = lighting_effect_set,
		clone = lighting_effect_clone,
		properties = []string{"Enabled"},
	)
	Register_Class(
		registry,
		&RenderQualityEffect_Class,
		RenderQualityEffect_construct,
		lighting_effect_destroy,
		get = lighting_effect_get,
		set = lighting_effect_set,
		clone = lighting_effect_clone,
		properties = []string{"Enabled", "Quality"},
	)
	Register_Class(
		registry,
		&VignetteEffect_Class,
		VignetteEffect_construct,
		lighting_effect_destroy,
		get = lighting_effect_get,
		set = lighting_effect_set,
		clone = lighting_effect_clone,
		properties = []string {
			"Enabled",
			"Midpoint",
			"Roundness",
			"Feather",
			"Color",
			"Transparency",
		},
	)
	Register_Class(
		registry,
		&ScreenSpaceReflectionsEffect_Class,
		ScreenSpaceReflectionsEffect_construct,
		lighting_effect_destroy,
		get = lighting_effect_get,
		set = lighting_effect_set,
		clone = lighting_effect_clone,
		properties = []string{"Enabled", "Thickness", "Bias", "MaxDistance", "Stride"},
	)
}
