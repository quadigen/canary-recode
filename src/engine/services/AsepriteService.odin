package services

// wire:service

import assetstore "../assetstore"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import aseprite "../util/aseprite"
import vm "../vm"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:slice"

AsepriteService_Class := classes.Class_Info {
	name   = "AsepriteService",
	parent = &Service_Class,
}

aseprite_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Service)
	service^ = Service_Init(&AsepriteService_Class, "AsepriteService", data_model)
	return &service.object
}

aseprite_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Service)object)
}

aseprite_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "GetInfo", "CreateImageLabel", "CreateImageLabels", "CreateAnimated":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

aseprite_service_source :: proc(
	L: ^vm.State,
	dt: ^datatypes.Registry,
) -> (
	data: []u8,
	owned: bool,
) {
	if bytes, ok := vm.ToBuffer(L, 2); ok {return bytes, false}
	value: string
	if vm.IsUserdataType(L, 2, &dt.animated) {
		value = datatypes.Arg_Animated(L, 2, dt).uri
	} else if vm.TypeOf(L, 2) == .String {
		value = vm.ArgString(L, 2)
	} else {return nil, false}
	if len(value) >= 6 && value[4] == 0xe0 && value[5] == 0xa5 {
		return transmute([]u8)value, false
	}
	if bytes, ok := assetstore.Resolve_Bytes(value); ok {return bytes, false}
	if _, ok := assetstore.Project_Asset_Path(value); ok {
		path := assetstore.Resolve_Path(value)
		defer delete(path)
		bytes, found := assetstore.Read_Asset_File(path)
		return bytes, found
	}
	return nil, false
}

aseprite_frame_uri :: proc(ase: ^aseprite.Ase, index: int) -> string {
	frame := &ase.frames[index]
	img := image.Image {
		width    = ase.w,
		height   = ase.h,
		channels = 4,
		depth    = 8,
	}
	img.pixels = make([dynamic]u8, len(frame.pixels) * 4)
	defer delete(img.pixels)
	copy(img.pixels[:], (cast([^]u8)raw_data(frame.pixels))[:len(frame.pixels) * 4])
	encoded: [dynamic]u8
	defer delete(encoded)
	if png.save_to_buffer(&encoded, &img) != nil {return ""}
	id := assetstore.Register(slice.clone(encoded[:]), "aseprite-frame.png", .Texture)
	defer delete(id)
	if id == "" {return ""}
	return assetstore.Make_Uri(id)
}

aseprite_push_label :: proc(
	L: ^vm.State,
	registry: ^classes.Registry,
	ase: ^aseprite.Ase,
	index: int,
	uri: string,
) -> bool {
	object, ok := classes.Push_New(registry, &vm.VM{L = L}, "ImageLabel")
	if !ok {return false}
	label := cast(^classes.ImageLabel)object
	classes.Set_Name(object, fmt.tprintf("Frame_%d", index + 1))
	label.size = datatypes.UDim2{0, f32(ase.w), 0, f32(ase.h)}
	label.bg_transparency = 1
	label.border_size_pixels = 0
	label.resample_mode = .Nearest
	classes.ImageLabel_Set_Image(label, uri)
	return true
}

aseprite_push_info :: proc(L: ^vm.State, dt: ^datatypes.Registry, ase: ^aseprite.Ase) {
	vm.NewTable(L, 0, 5)
	datatypes.Push_Vector2(L, dt, {f32(ase.w), f32(ase.h)})
	vm.SetField(L, -2, "Size")
	vm.PushNumber(L, f64(len(ase.frames)))
	vm.SetField(L, -2, "FrameCount")
	vm.NewTable(L, len(ase.frames), 0)
	for frame, i in ase.frames {
		vm.PushNumber(L, f64(frame.duration_ms) / 1000)
		vm.RawSetIndex(L, -2, i + 1)
	}
	vm.SetField(L, -2, "Durations")
	vm.NewTable(L, len(ase.tags), 0)
	for tag, i in ase.tags {
		vm.NewTable(L, 0, 5)
		vm.PushString(L, tag.name)
		vm.SetField(L, -2, "Name")
		vm.PushNumber(L, f64(tag.from_frame + 1))
		vm.SetField(L, -2, "FromFrame")
		vm.PushNumber(L, f64(tag.to_frame + 1))
		vm.SetField(L, -2, "ToFrame")
		direction := "Forward"
		switch tag.loop_animation_direction {
		case .Forwards:
			direction = "Forward"
		case .Backwards:
			direction = "Reverse"
		case .Ping_Pong:
			direction = "PingPong"
		case .Ping_Pong_Reverse:
			direction = "PingPongReverse"
		}
		vm.PushString(L, direction)
		vm.SetField(L, -2, "Direction")
		vm.PushNumber(L, f64(tag.repeat))
		vm.SetField(L, -2, "Repeat")
		vm.RawSetIndex(L, -2, i + 1)
	}
	vm.SetField(L, -2, "Tags")
	vm.NewTable(L, len(ase.layers), 0)
	for layer, i in ase.layers {
		vm.PushString(L, layer.name)
		vm.RawSetIndex(L, -2, i + 1)
	}
	vm.SetField(L, -2, "Layers")
}

aseprite_service_convert :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	method: string,
	frame_number: f64,
) -> (
	i32,
	string,
) {
	data, owned := aseprite_service_source(L, dt)
	defer if owned {delete(data)}
	if len(data) == 0 {return 0, "expected Aseprite bytes, a buffer, or a valid asset URI"}
	ase, err := aseprite.load_from_memory(data)
	if err != .None {return 0, fmt.tprintf("could not decode Aseprite: %v", err)}
	defer aseprite.destroy(ase)
	switch method {
	case "CreateAnimated":
		animated, ok := datatypes.Animated_From_Bytes(data)
		if !ok {return 0, "could not register Aseprite animation"}
		defer delete(animated.uri)
		datatypes.Push_Animated(L, dt, animated)
		aseprite_push_info(L, dt, ase)
		return 2, ""
	case "GetInfo":
		aseprite_push_info(L, dt, ase)
		return 1, ""
	case "CreateImageLabel":
		if !(frame_number >= 1 && frame_number <= f64(len(ase.frames))) ||
		   f64(int(frame_number)) != frame_number {
			return 0, "frame index must be a valid 1-based integer"
		}
		index := int(frame_number) - 1
		uri := aseprite_frame_uri(ase, index)
		defer delete(uri)
		if uri == "" ||
		   !aseprite_push_label(
				   L,
				   object.signal_registry,
				   ase,
				   index,
				   uri,
			   ) {return 0, "could not create Aseprite ImageLabel"}
		vm.PushNumber(L, f64(ase.frames[index].duration_ms) / 1000)
		return 2, ""
	case "CreateImageLabels":
		uris := make([]string, len(ase.frames))
		defer {
			for uri in uris {delete(uri)}
			delete(uris)
		}
		for &uri, i in uris {
			uri = aseprite_frame_uri(ase, i)
			if uri == "" {return 0, "could not encode Aseprite frame"}
		}
		vm.NewTable(L, len(uris), 0)
		for uri, i in uris {
			if !aseprite_push_label(
				L,
				object.signal_registry,
				ase,
				i,
				uri,
			) {return 0, "could not create Aseprite ImageLabel"}
			vm.RawSetIndex(L, -2, i + 1)
		}
		aseprite_push_info(L, dt, ase)
		animated, ok := datatypes.Animated_From_Bytes(data)
		if !ok {return 0, "could not register Aseprite animation"}
		defer delete(animated.uri)
		datatypes.Push_Animated(L, dt, animated)
		return 3, ""
	}
	return 0, "unknown AsepriteService method"
}

aseprite_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "GetInfo" &&
	   method != "CreateImageLabel" &&
	   method != "CreateImageLabels" &&
	   method != "CreateAnimated" {return 0, false}
	frame_number: f64 = 1
	if method == "CreateImageLabel" && !vm.IsNoneOrNil(L, 3) {
		frame_number = vm.ArgNumber(L, 3)
	}
	count, err := aseprite_service_convert(L, object, dt, method, frame_number)
	if err != "" {return vm.RaiseError(L, err), true}
	return count, true
}

Register_AsepriteService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&AsepriteService_Class,
		aseprite_service_construct,
		aseprite_service_destroy,
		creatable = false,
		get = aseprite_service_get,
		namecall = aseprite_service_namecall,
		methods = []string{"GetInfo", "CreateImageLabel", "CreateImageLabels", "CreateAnimated"},
	)
}
