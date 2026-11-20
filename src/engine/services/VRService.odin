package services

// wire:service

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

VRService_Class := classes.Class_Info {
	name   = "VRService",
	parent = &Service_Class,
}

vr_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Service)
	service^ = Service_Init(&VRService_Class, "VRService", data_model)
	return &service.object
}

vr_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Service)object)
}

vr_service_context :: proc(service: ^Service) -> ^kineffi.KineFilamentContext {
	if service == nil ||
	   service.data_model == nil ||
	   service.data_model.registry == nil {return nil}
	registry := service.data_model.registry
	if registry.mode == .Server ||
	   registry.classes == nil ||
	   registry.classes.renderer == nil {return nil}
	return registry.classes.renderer.Filament
}

VR_Service_Enabled :: proc(service: ^Service) -> bool {
	when ODIN_OS == .Linux && !#config(KINE_ANDROID, false) {
		if ctx := vr_service_context(service); ctx != nil {
			return kineffi.Kine_Filament_XR_Active(ctx)
		}
	}
	return false
}

vr_service_available :: proc(service: ^Service) -> bool {
	when ODIN_OS == .Linux && !#config(KINE_ANDROID, false) {
		if ctx := vr_service_context(service); ctx != nil {
			return kineffi.Kine_Filament_XR_Available(ctx)
		}
	}
	return false
}

vr_service_pose :: proc(service: ^Service, index: i32) -> (datatypes.CFrame, bool) {
	when ODIN_OS == .Linux && !#config(KINE_ANDROID, false) {
		if ctx := vr_service_context(service); ctx != nil {
			values: [12]f32
			if kineffi.Kine_Filament_XR_GetPose(ctx, index, &values[0]) {
				return datatypes.CFrame {
						x = values[0],
						y = values[1],
						z = values[2],
						r00 = values[3],
						r01 = values[4],
						r02 = values[5],
						r10 = values[6],
						r11 = values[7],
						r12 = values[8],
						r20 = values[9],
						r21 = values[10],
						r22 = values[11],
					},
					true
			}
		}
	}
	return datatypes.CFrame_Identity, false
}

vr_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	types: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^Service)object
	switch key {
	case "VREnabled":
		vm.PushBoolean(L, VR_Service_Enabled(service))
	case "VRAvailable":
		vm.PushBoolean(L, vr_service_available(service))
	case "GetUserCFrame", "GetUserCFrameEnabled", "GetControllerState", "SetControllerHaptic":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

vr_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	types: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "GetUserCFrame", "GetUserCFrameEnabled":
		item := enums.Arg_Item(L, 2, enum_registry, "UserCFrame")
		pose, valid := vr_service_pose(cast(^Service)object, i32(item.value))
		if method == "GetUserCFrame" {
			datatypes.Push_CFrame(L, types, pose)
		} else {
			vm.PushBoolean(L, valid)
		}
		return 1, true
	case "GetControllerState":
		item := enums.Arg_Item(L, 2, enum_registry, "UserCFrame")
		hand := i32(item.value) - 1
		if hand < 0 || hand > 1 {
			_ = vm.RaiseError(L, "expected Enum.UserCFrame.LeftHand or RightHand")
			return 0, true
		}
		state: kineffi.KineXRControllerState
		active := false
		when ODIN_OS == .Linux && !#config(KINE_ANDROID, false) {
			if ctx := vr_service_context(cast(^Service)object); ctx != nil {
				active = kineffi.Kine_Filament_XR_GetControllerState(ctx, hand, &state)
			}
		}
		vm.NewTable(L, 0, 7)
		vm.PushBoolean(L, active)
		vm.SetField(L, -2, "Active")
		vm.PushNumber(L, f64(state.trigger))
		vm.SetField(L, -2, "Trigger")
		vm.PushNumber(L, f64(state.grip))
		vm.SetField(L, -2, "Grip")
		datatypes.Push_Vector2(L, types, datatypes.Vector2{state.stick_x, state.stick_y})
		vm.SetField(L, -2, "Thumbstick")
		vm.PushBoolean(L, (state.active_mask & 1) != 0)
		vm.SetField(L, -2, "TriggerAvailable")
		vm.PushBoolean(L, (state.active_mask & 2) != 0)
		vm.SetField(L, -2, "GripAvailable")
		vm.PushBoolean(L, (state.active_mask & 4) != 0)
		vm.SetField(L, -2, "ThumbstickAvailable")
		return 1, true
	case "SetControllerHaptic":
		item := enums.Arg_Item(L, 2, enum_registry, "UserCFrame")
		hand := i32(item.value) - 1
		if hand < 0 || hand > 1 {
			_ = vm.RaiseError(L, "expected Enum.UserCFrame.LeftHand or RightHand")
			return 0, true
		}
		amplitude := f32(vm.ArgNumber(L, 3))
		seconds := f32(vm.ArgNumber(L, 4))
		frequency := f32(vm.ArgOptionalNumber(L, 5, 0))
		ok := false
		when ODIN_OS == .Linux && !#config(KINE_ANDROID, false) {
			if ctx := vr_service_context(cast(^Service)object); ctx != nil {
				ok = kineffi.Kine_Filament_XR_SetHaptic(ctx, hand, amplitude, seconds, frequency)
			}
		}
		vm.PushBoolean(L, ok)
		return 1, true
	}
	return 0, false
}

Register_VRService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&VRService_Class,
		vr_service_construct,
		vr_service_destroy,
		creatable = false,
		get = vr_service_get,
		namecall = vr_service_namecall,
		properties = []string{"VREnabled", "VRAvailable"},
		methods = []string {
			"GetUserCFrame",
			"GetUserCFrameEnabled",
			"GetControllerState",
			"SetControllerHaptic",
		},
	)
}
