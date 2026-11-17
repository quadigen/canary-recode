package services
// wire:service

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:strings"

// A host implementation can supply its own icon atlas. Image, offset and size
// are returned in the same shape as Roblox StudioService:GetClassIcon().
StudioService_Class_Icon :: struct {
	image:    string,
	offset_x: f32,
	offset_y: f32,
	size_x:   f32,
	size_y:   f32,
}

StudioService_Icon_Provider :: proc(
	ctx: rawptr,
	class_name: string,
) -> (
	StudioService_Class_Icon,
	bool,
)

StudioService_File_Importer :: proc(
	ctx: rawptr,
	allowed_extensions: []string,
	multiple: bool,
) -> []^classes.Object

StudioService_Class := classes.Class_Info {
	name   = "StudioService",
	parent = &Service_Class,
}

StudioService :: struct {
	using service:             Service,
	active_script:             ^classes.Object,
	dragger_solve_constraints: bool,
	draw_constraints_on_top:   bool,
	grid_size:                 f64,
	rotate_increment:          f64,
	show_constraint_details:   bool,
	show_weld_details:         bool,
	studio_locale_id:          string,
	use_local_space:           bool,
	user_id:                   i64,
	icon_provider:             StudioService_Icon_Provider,
	icon_context:              rawptr,
	file_importer:             StudioService_File_Importer,
	import_context:            rawptr,
}

StudioService_Editor_State :: struct {
	dragger_solve_constraints: bool,
	draw_constraints_on_top:   bool,
	grid_size:                 f64,
	rotate_increment:          f64,
	show_constraint_details:   bool,
	show_weld_details:         bool,
	use_local_space:           bool,
}

studio_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(StudioService)
	service^ = StudioService {
		service          = Service_Init(&StudioService_Class, "StudioService", data_model),
		grid_size        = 1,
		rotate_increment = 15,
		studio_locale_id = strings.clone("en_US"),
	}
	return &service.object
}

StudioService_Set_Active_Script :: proc(
	service: ^StudioService,
	L: ^vm.State,
	script: ^classes.Object,
) {
	if service == nil || service.object.destroyed {return}
	if script != nil && script.destroyed {return}
	if service.active_script == script {return}
	service.active_script = script
	classes.Object_Fire_Property_Changed(&service.object, "ActiveScript", L)
}

StudioService_Update_Editor_State :: proc(
	service: ^StudioService,
	L: ^vm.State,
	state: StudioService_Editor_State,
) {
	if service == nil || service.object.destroyed {return}

	if service.dragger_solve_constraints != state.dragger_solve_constraints {
		service.dragger_solve_constraints = state.dragger_solve_constraints
		classes.Object_Fire_Property_Changed(&service.object, "DraggerSolveConstraints", L)
	}
	if service.draw_constraints_on_top != state.draw_constraints_on_top {
		service.draw_constraints_on_top = state.draw_constraints_on_top
		classes.Object_Fire_Property_Changed(&service.object, "DrawConstraintsOnTop", L)
	}
	if service.grid_size != state.grid_size {
		service.grid_size = state.grid_size
		classes.Object_Fire_Property_Changed(&service.object, "GridSize", L)
	}
	if service.rotate_increment != state.rotate_increment {
		service.rotate_increment = state.rotate_increment
		classes.Object_Fire_Property_Changed(&service.object, "RotateIncrement", L)
	}
	if service.show_constraint_details != state.show_constraint_details {
		service.show_constraint_details = state.show_constraint_details
		classes.Object_Fire_Property_Changed(&service.object, "ShowConstraintDetails", L)
	}
	if service.show_weld_details != state.show_weld_details {
		service.show_weld_details = state.show_weld_details
		classes.Object_Fire_Property_Changed(&service.object, "ShowWeldDetails", L)
	}
	if service.use_local_space != state.use_local_space {
		service.use_local_space = state.use_local_space
		classes.Object_Fire_Property_Changed(&service.object, "UseLocalSpace", L)
	}
}

StudioService_Set_Locale :: proc(service: ^StudioService, L: ^vm.State, locale: string) {
	if service == nil || service.object.destroyed || service.studio_locale_id == locale {return}
	value := strings.clone(locale)
	delete(service.studio_locale_id)
	service.studio_locale_id = value
	classes.Object_Fire_Property_Changed(&service.object, "StudioLocaleId", L)
}

StudioService_Set_User_Id :: proc(service: ^StudioService, user_id: i64) {
	if service == nil || service.object.destroyed {return}
	service.user_id = user_id
}

StudioService_Set_Icon_Provider :: proc(
	service: ^StudioService,
	provider: StudioService_Icon_Provider,
	ctx: rawptr = nil,
) {
	if service == nil || service.object.destroyed {return}
	service.icon_provider = provider
	service.icon_context = ctx
}

StudioService_Set_File_Importer :: proc(
	service: ^StudioService,
	importer: StudioService_File_Importer,
	ctx: rawptr = nil,
) {
	if service == nil || service.object.destroyed {return}
	service.file_importer = importer
	service.import_context = ctx
}

studio_service_push_class_icon :: proc(
	L: ^vm.State,
	datatype_registry: ^datatypes.Registry,
	icon: StudioService_Class_Icon,
) {
	vm.NewTable(L, 0, 3)
	vm.PushString(L, icon.image)
	vm.SetField(L, -2, "Image")
	datatypes.Push_Vector2(L, datatype_registry, datatypes.Vector2{icon.offset_x, icon.offset_y})
	vm.SetField(L, -2, "ImageRectOffset")
	datatypes.Push_Vector2(L, datatype_registry, datatypes.Vector2{icon.size_x, icon.size_y})
	vm.SetField(L, -2, "ImageRectSize")
}

studio_service_default_icon :: proc(class_name: string) -> StudioService_Class_Icon {
	icon := StudioService_Class_Icon {
		image  = "rbxasset://textures/ClassImages.png",
		size_x = 16,
		size_y = 16,
	}
	// The Part rectangle is documented by Roblox. Other classes use the
	// atlas's generic first icon until an editor icon provider is supplied.
	if class_name == "Part" {icon.offset_x = 16}
	return icon
}

studio_service_read_file_filters :: proc(
	L: ^vm.State,
	index: int,
) -> (
	filters: [dynamic]string,
	valid: bool,
) {
	if vm.IsNoneOrNil(L, index) {return nil, true}
	if !vm.IsTable(L, index) {return nil, false}

	count := vm.RawLen(L, index)
	for i := 1; i <= count; i += 1 {
		_ = vm.RawGetIndex(L, index, i)
		if !vm.IsString(L, -1) {
			vm.Pop(L)
			delete(filters)
			return nil, false
		}
		extension := vm.ArgString(L, -1)
		// Borrowed VM strings remain alive on the caller's stack during import.
		append(&filters, extension)
		vm.Pop(L)
	}
	return filters, true
}

studio_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^StudioService)object
	switch key {
	case "ActiveScript":
		if service.active_script != nil && service.active_script.destroyed {
			service.active_script = nil
		}
		classes.Push_Object(L, service.active_script)
	case "DraggerSolveConstraints":
		vm.PushBoolean(L, service.dragger_solve_constraints)
	case "DrawConstraintsOnTop":
		vm.PushBoolean(L, service.draw_constraints_on_top)
	case "GridSize":
		vm.PushNumber(L, service.grid_size)
	case "RotateIncrement":
		vm.PushNumber(L, service.rotate_increment)
	case "ShowConstraintDetails":
		vm.PushBoolean(L, service.show_constraint_details)
	case "StudioLocaleId":
		vm.PushString(L, service.studio_locale_id)
	case "UseLocalSpace":
		vm.PushBoolean(L, service.use_local_space)
	case "GetClassIcon",
	     "GetUserId",
	     "PromptImportFile",
	     "PromptImportFileAsync",
	     "PromptImportFiles",
	     "PromptImportFilesAsync":
		vm.PushUserdataMethod(L, key)
	case "Secrets", "ShowWeldDetails":
		return false
	case:
		return false
	}
	return true
}

studio_service_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	service := cast(^StudioService)object
	switch key {
	case "UseLocalSpace":
		if !vm.IsBoolean(L, value_index) {
			_ = vm.RaiseError(L, "UseLocalSpace must be a boolean")
			return true
		}
		value := vm.ArgBoolean(L, value_index)
		if service.use_local_space != value {
			service.use_local_space = value
			classes.Object_Fire_Property_Changed(&service.object, "UseLocalSpace", L)
		}
		return true
	}
	return false
}

studio_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^StudioService)object
	switch method {
	case "GetUserId":
		vm.PushNumber(L, f64(service.user_id))
		return 1, true

	case "GetClassIcon":
		class_name := vm.ArgString(L, 2)
		if datatype_registry == nil {
			return vm.RaiseError(L, "Vector2 registry is unavailable"), true
		}
		icon := studio_service_default_icon(class_name)
		if service.icon_provider != nil {
			supplied, found := service.icon_provider(service.icon_context, class_name)
			if found {icon = supplied}
		}
		studio_service_push_class_icon(L, datatype_registry, icon)
		return 1, true

	case "PromptImportFile",
	     "PromptImportFileAsync",
	     "PromptImportFiles",
	     "PromptImportFilesAsync":
		if service.file_importer == nil {
			return vm.RaiseError(
					L,
					"StudioService file importer is not connected to the native editor",
				),
				true
		}

		filters, valid := studio_service_read_file_filters(L, 2)
		defer delete(filters)
		if !valid {
			return vm.RaiseError(L, "fileTypeFilter must be an array of file extensions"), true
		}

		multiple := method == "PromptImportFiles" || method == "PromptImportFilesAsync"
		imported := service.file_importer(service.import_context, filters[:], multiple)

		if !multiple {
			if len(imported) == 0 || imported[0] == nil || imported[0].destroyed {
				vm.PushNil(L)
			} else {
				classes.Push_Object(L, imported[0])
			}
			return 1, true
		}

		vm.NewTable(L, len(imported))
		index := 1
		for entry in imported {
			if entry == nil || entry.destroyed {continue}
			classes.Push_Object(L, entry)
			vm.SetArrayValue(L, -2, index)
			index += 1
		}
		return 1, true
	}
	return 0, false
}

studio_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^StudioService)object
	service.active_script = nil
	service.file_importer = nil
	service.icon_provider = nil
	delete(service.studio_locale_id)
	classes.Object_Destroy(object)
	free(service)
}

Register_StudioService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&StudioService_Class,
		studio_service_construct,
		studio_service_destroy,
		creatable = false,
		get = studio_service_get,
		set = studio_service_set,
		namecall = studio_service_namecall,
		properties = []string {
			"ActiveScript",
			"DraggerSolveConstraints",
			"DrawConstraintsOnTop",
			"GridSize",
			"RotateIncrement",
			"ShowConstraintDetails",
			"StudioLocaleId",
			"UseLocalSpace",
		},
		methods = []string {
			"GetClassIcon",
			"GetUserId",
			"PromptImportFile",
			"PromptImportFileAsync",
			"PromptImportFiles",
			"PromptImportFilesAsync",
		},
	)
}
