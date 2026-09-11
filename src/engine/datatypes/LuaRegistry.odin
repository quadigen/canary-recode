package datatypes

import vm "../vm"
import engine_enums "../enum"

DATATYPE_TAG_BASE :: 64

Registry :: struct {
	enums: ^engine_enums.Registry,
	// wire:begin datatype-fields
	axes: vm.Userdata_Binding,
	c_frame: vm.Userdata_Binding,
	color3: vm.Userdata_Binding,
	color_sequence: vm.Userdata_Binding,
	color_sequence_keypoint: vm.Userdata_Binding,
	faces: vm.Userdata_Binding,
	font: vm.Userdata_Binding,
	number_range: vm.Userdata_Binding,
	number_sequence: vm.Userdata_Binding,
	number_sequence_keypoint: vm.Userdata_Binding,
	path_waypoint: vm.Userdata_Binding,
	physical_properties: vm.Userdata_Binding,
	quaternion: vm.Userdata_Binding,
	ray: vm.Userdata_Binding,
	raycast_params: vm.Userdata_Binding,
	raycast_result: vm.Userdata_Binding,
	rect: vm.Userdata_Binding,
	region3: vm.Userdata_Binding,
	region3int16: vm.Userdata_Binding,
	security_capabilities: vm.Userdata_Binding,
	tween_info: vm.Userdata_Binding,
	u_dim: vm.Userdata_Binding,
	u_dim2: vm.Userdata_Binding,
	unique_id: vm.Userdata_Binding,
	vector2: vm.Userdata_Binding,
	vector2int16: vm.Userdata_Binding,
	vector3: vm.Userdata_Binding,
	vector3int16: vm.Userdata_Binding,
	// wire:end datatype-fields
}

Registry_Init :: proc(registry: ^Registry, enum_registry: ^engine_enums.Registry = nil) {
	assert(registry != nil)
	registry.enums = enum_registry
	// wire:begin datatype-bindings
	registry.axes = Axes_Luau_Binding()
	registry.c_frame = CFrame_Luau_Binding()
	registry.color3 = Color3_Luau_Binding()
	registry.color_sequence = ColorSequence_Luau_Binding()
	registry.color_sequence_keypoint = ColorSequenceKeypoint_Luau_Binding()
	registry.faces = Faces_Luau_Binding()
	registry.font = Font_Luau_Binding()
	registry.number_range = NumberRange_Luau_Binding()
	registry.number_sequence = NumberSequence_Luau_Binding()
	registry.number_sequence_keypoint = NumberSequenceKeypoint_Luau_Binding()
	registry.path_waypoint = PathWaypoint_Luau_Binding()
	registry.physical_properties = PhysicalProperties_Luau_Binding()
	registry.quaternion = Quaternion_Luau_Binding()
	registry.ray = Ray_Luau_Binding()
	registry.raycast_params = RaycastParams_Luau_Binding()
	registry.raycast_result = RaycastResult_Luau_Binding()
	registry.rect = Rect_Luau_Binding()
	registry.region3 = Region3_Luau_Binding()
	registry.region3int16 = Region3int16_Luau_Binding()
	registry.security_capabilities = SecurityCapabilities_Luau_Binding()
	registry.tween_info = TweenInfo_Luau_Binding()
	registry.u_dim = UDim_Luau_Binding()
	registry.u_dim2 = UDim2_Luau_Binding()
	registry.unique_id = UniqueId_Luau_Binding()
	registry.vector2 = Vector2_Luau_Binding()
	registry.vector2int16 = Vector2int16_Luau_Binding()
	registry.vector3 = Vector3_Luau_Binding()
	registry.vector3int16 = Vector3int16_Luau_Binding()
	// wire:end datatype-bindings

	// wire:begin datatype-tags
	registry.axes.tag = DATATYPE_TAG_BASE + 0
	registry.c_frame.tag = DATATYPE_TAG_BASE + 1
	registry.color3.tag = DATATYPE_TAG_BASE + 2
	registry.color_sequence.tag = DATATYPE_TAG_BASE + 3
	registry.color_sequence_keypoint.tag = DATATYPE_TAG_BASE + 4
	registry.faces.tag = DATATYPE_TAG_BASE + 5
	registry.font.tag = DATATYPE_TAG_BASE + 6
	registry.number_range.tag = DATATYPE_TAG_BASE + 7
	registry.number_sequence.tag = DATATYPE_TAG_BASE + 8
	registry.number_sequence_keypoint.tag = DATATYPE_TAG_BASE + 9
	registry.path_waypoint.tag = DATATYPE_TAG_BASE + 10
	registry.physical_properties.tag = DATATYPE_TAG_BASE + 11
	registry.quaternion.tag = DATATYPE_TAG_BASE + 12
	registry.ray.tag = DATATYPE_TAG_BASE + 13
	registry.raycast_params.tag = DATATYPE_TAG_BASE + 14
	registry.raycast_result.tag = DATATYPE_TAG_BASE + 15
	registry.rect.tag = DATATYPE_TAG_BASE + 16
	registry.region3.tag = DATATYPE_TAG_BASE + 17
	registry.region3int16.tag = DATATYPE_TAG_BASE + 18
	registry.security_capabilities.tag = DATATYPE_TAG_BASE + 19
	registry.tween_info.tag = DATATYPE_TAG_BASE + 20
	registry.u_dim.tag = DATATYPE_TAG_BASE + 21
	registry.u_dim2.tag = DATATYPE_TAG_BASE + 22
	registry.unique_id.tag = DATATYPE_TAG_BASE + 23
	registry.vector2.tag = DATATYPE_TAG_BASE + 24
	registry.vector2int16.tag = DATATYPE_TAG_BASE + 25
	registry.vector3.tag = DATATYPE_TAG_BASE + 26
	registry.vector3int16.tag = DATATYPE_TAG_BASE + 27
	// wire:end datatype-tags

	// wire:begin datatype-contexts
	registry.axes.ctx = &registry.axes
	registry.axes.owner = registry
	registry.c_frame.ctx = &registry.c_frame
	registry.c_frame.owner = registry
	registry.color3.ctx = &registry.color3
	registry.color3.owner = registry
	registry.color_sequence.ctx = &registry.color_sequence
	registry.color_sequence.owner = registry
	registry.color_sequence_keypoint.ctx = &registry.color_sequence_keypoint
	registry.color_sequence_keypoint.owner = registry
	registry.faces.ctx = &registry.faces
	registry.faces.owner = registry
	registry.font.ctx = &registry.font
	registry.font.owner = registry
	registry.number_range.ctx = &registry.number_range
	registry.number_range.owner = registry
	registry.number_sequence.ctx = &registry.number_sequence
	registry.number_sequence.owner = registry
	registry.number_sequence_keypoint.ctx = &registry.number_sequence_keypoint
	registry.number_sequence_keypoint.owner = registry
	registry.path_waypoint.ctx = &registry.path_waypoint
	registry.path_waypoint.owner = registry
	registry.physical_properties.ctx = &registry.physical_properties
	registry.physical_properties.owner = registry
	registry.quaternion.ctx = &registry.quaternion
	registry.quaternion.owner = registry
	registry.ray.ctx = &registry.ray
	registry.ray.owner = registry
	registry.raycast_params.ctx = &registry.raycast_params
	registry.raycast_params.owner = registry
	registry.raycast_result.ctx = &registry.raycast_result
	registry.raycast_result.owner = registry
	registry.rect.ctx = &registry.rect
	registry.rect.owner = registry
	registry.region3.ctx = &registry.region3
	registry.region3.owner = registry
	registry.region3int16.ctx = &registry.region3int16
	registry.region3int16.owner = registry
	registry.security_capabilities.ctx = &registry.security_capabilities
	registry.security_capabilities.owner = registry
	registry.tween_info.ctx = &registry.tween_info
	registry.tween_info.owner = registry
	registry.u_dim.ctx = &registry.u_dim
	registry.u_dim.owner = registry
	registry.u_dim2.ctx = &registry.u_dim2
	registry.u_dim2.owner = registry
	registry.unique_id.ctx = &registry.unique_id
	registry.unique_id.owner = registry
	registry.vector2.ctx = &registry.vector2
	registry.vector2.owner = registry
	registry.vector2int16.ctx = &registry.vector2int16
	registry.vector2int16.owner = registry
	registry.vector3.ctx = &registry.vector3
	registry.vector3.owner = registry
	registry.vector3int16.ctx = &registry.vector3int16
	registry.vector3int16.owner = registry
	// wire:end datatype-contexts
}

push_value :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: $T) {
	stored := new(T)
	stored^ = value
	vm_state := vm.VM{L = L}
	vm.PushUserdata(&vm_state, stored, binding)
}

binding_from_upvalue :: proc(L: ^vm.State) -> ^vm.Userdata_Binding {
	return cast(^vm.Userdata_Binding)vm.UpvaluePointer(L)
}

registry_from_binding :: proc(binding: ^vm.Userdata_Binding) -> ^Registry {
	if binding == nil {
		return nil
	}
	return cast(^Registry)binding.owner
}

add_library_function :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, name: string, function: vm.CFunction) {
	vm.PushLightUserdata(L, binding)
	vm.PushFunction(L, name, function, 1)
	vm.SetField(L, -2, name)
}

install_library :: proc(vm_state: ^vm.VM, name: string, binding: ^vm.Userdata_Binding, install_fields: proc(L: ^vm.State, binding: ^vm.Userdata_Binding)) {
	vm.NewTable(vm_state.L, 0, 12)
	install_fields(vm_state.L, binding)
	vm.SetReadOnly(vm_state.L, -1)
	vm.SetGlobalFromStack(vm_state, name)
}

Install :: proc(registry: ^Registry, vm_state: ^vm.VM) {
	// wire:begin datatype-libraries
	install_library(vm_state, "Axes", &registry.axes, Axes_Install_Fields)
	install_library(vm_state, "CFrame", &registry.c_frame, CFrame_Install_Fields)
	install_library(vm_state, "Color3", &registry.color3, Color3_Install_Fields)
	install_library(vm_state, "ColorSequence", &registry.color_sequence, ColorSequence_Install_Fields)
	install_library(vm_state, "ColorSequenceKeypoint", &registry.color_sequence_keypoint, ColorSequenceKeypoint_Install_Fields)
	install_library(vm_state, "Faces", &registry.faces, Faces_Install_Fields)
	install_library(vm_state, "Font", &registry.font, Font_Install_Fields)
	install_library(vm_state, "NumberRange", &registry.number_range, NumberRange_Install_Fields)
	install_library(vm_state, "NumberSequence", &registry.number_sequence, NumberSequence_Install_Fields)
	install_library(vm_state, "NumberSequenceKeypoint", &registry.number_sequence_keypoint, NumberSequenceKeypoint_Install_Fields)
	install_library(vm_state, "PathWaypoint", &registry.path_waypoint, PathWaypoint_Install_Fields)
	install_library(vm_state, "PhysicalProperties", &registry.physical_properties, PhysicalProperties_Install_Fields)
	install_library(vm_state, "Quaternion", &registry.quaternion, Quaternion_Install_Fields)
	install_library(vm_state, "Ray", &registry.ray, Ray_Install_Fields)
	install_library(vm_state, "RaycastParams", &registry.raycast_params, RaycastParams_Install_Fields)
	install_library(vm_state, "RaycastResult", &registry.raycast_result, RaycastResult_Install_Fields)
	install_library(vm_state, "Rect", &registry.rect, Rect_Install_Fields)
	install_library(vm_state, "Region3", &registry.region3, Region3_Install_Fields)
	install_library(vm_state, "Region3int16", &registry.region3int16, Region3int16_Install_Fields)
	install_library(vm_state, "SecurityCapabilities", &registry.security_capabilities, SecurityCapabilities_Install_Fields)
	install_library(vm_state, "TweenInfo", &registry.tween_info, TweenInfo_Install_Fields)
	install_library(vm_state, "UDim", &registry.u_dim, UDim_Install_Fields)
	install_library(vm_state, "UDim2", &registry.u_dim2, UDim2_Install_Fields)
	install_library(vm_state, "UniqueId", &registry.unique_id, UniqueId_Install_Fields)
	install_library(vm_state, "Vector2", &registry.vector2, Vector2_Install_Fields)
	install_library(vm_state, "Vector2int16", &registry.vector2int16, Vector2int16_Install_Fields)
	install_library(vm_state, "Vector3", &registry.vector3, Vector3_Install_Fields)
	install_library(vm_state, "Vector3int16", &registry.vector3int16, Vector3int16_Install_Fields)
	// wire:end datatype-libraries
}

