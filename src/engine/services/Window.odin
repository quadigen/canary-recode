package services
// wire:service
import platform "../platform"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Window_Class := classes.Class_Info {
	name   = "Window",
	parent = &Service_Class,
}

Window :: struct {
	using service: Service,
}

Window_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Window)
	service.service = Service_Init(&Window_Class, "Window", data_model)

	return &service.object
}

Window_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "GetResolution", "SetResolution", "SetUIScale":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {return false}
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

Window_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	service := cast(^Window)object
	if method != "GetResolution" && method != "SetResolution" && method != "SetUIScale" {return 0, false}

	if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {return 0, false}
	registry := service.data_model.registry
	if registry == nil || registry.mode != .Editor || registry.classes.renderer == nil {
		vm.PushBoolean(L, false)
		return 1, true
	}
	window := registry.classes.renderer.Window
	if window == nil {
		vm.PushNil(L)
		return 1, true
	}

	ok := false
	switch method {
	case "GetResolution":
		width, height: i32
		if !platform.GetWindowSize(window, &width, &height) {
			vm.PushNil(L)
		} else {
			datatypes.Push_Vector2(L, datatype_registry, {f32(width), f32(height)})
		}
		return 1, true
	case "SetResolution":
		when ODIN_OS != .JS {
			width, height := vm.ArgNumber(L, 2), vm.ArgNumber(L, 3)
			if width >= 320 && width <= 7680 && height >= 240 && height <= 4320 {
				ok = window_set_resolution(window, i32(width), i32(height))
			}
		}
	case "SetUIScale":
		scale := vm.ArgNumber(L, 2)
		if scale >= 0.75 && scale <= 2 {
			platform.UI_Scale = f32(scale)
			classes.Gui_Layout_Mark_Dirty()
			ok = true
		}
	}
	vm.PushBoolean(L, ok)
	return 1, true
}

Window_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Window)object)
}

Register_Window_Class :: proc(registry: ^classes.Registry) {
	step: classes.Class_Step
	when ODIN_OS != .JS {step = Window_step}
	classes.Register_Class(
		registry,
		&Window_Class,
		Window_construct,
		Window_destroy,
		creatable = false,
		_step = step,
		get = Window_get,
		namecall = Window_namecall,
		methods = []string{"GetResolution", "SetResolution", "SetUIScale"},
	)
}
