#+build !js
// wire:service

package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import fsutil "../fsutil"
import signals "../signals"
import vm "../vm"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"


Studio :: struct {
	using service:   Service,
	settings:        map[string]Studio_Setting,
	setting_changed: ^signals.Signal,
	main_pipe:       ^signals.Signal,
}

Studio_Setting_Kind :: enum {
	Boolean,
	Number,
	String,
}

Studio_Setting :: struct {
	kind:       Studio_Setting_Kind,
	boolean:    bool,
	number:     f64,
	string_val: string,
}

Studio_Class := classes.Class_Info {
	name   = "Studio",
	parent = &Service_Class,
}

Pipe_Value :: union #no_nil {
	^classes.Object,
	string,
	f64,
	bool,
	i32,
}

Studio_Helper_Get_VM :: proc(service: ^Studio) -> vm.State {
	if service == nil || service.main_pipe == nil {
		return vm.State{}
	}
	registry := service.data_model.registry
	if registry == nil || registry.vm_state == nil {
		return vm.State{}
	}
	L := registry.vm_state.L
	return L^
}

Studio_Send_Through_Pipe :: proc(service: ^Studio, event: string, value: Pipe_Value) {
	if service == nil || service.main_pipe == nil {
		return
	}
	registry := service.data_model.registry
	if registry == nil || registry.vm_state == nil {
		return
	}
	L := registry.vm_state.L

	vm.PushString(L, event)
	switch v in value {
	case ^classes.Object:
		classes.Push_Object(L, v)
	case string:
		vm.PushString(L, v)
	case f64:
		vm.PushNumber(L, v)
	case bool:
		vm.PushBoolean(L, v)
	case i32:
		vm.PushRegistryReference(L, v)
	}
	signals.Fire(L, service.main_pipe, 2)
	vm.Pop(L, 2)
}

studio_setting_clear :: proc(setting: Studio_Setting) {
	if setting.kind == .String && len(setting.string_val) > 0 {
		delete(setting.string_val)
	}
}

studio_free_settings :: proc(service: ^Studio) {
	if service == nil {
		return
	}
	for key, value in service.settings {
		delete(key)
		studio_setting_clear(value)
	}
	delete(service.settings)
	service.settings = nil
}

studio_settings_path :: proc() -> (string, bool) {
	data_dir, err := os.user_data_dir(context.allocator)
	if err != nil {
		return "", false
	}
	defer delete(data_dir)

	kinemium_dir, join_err := os.join_path({data_dir, "Kinemium"}, context.allocator)
	if join_err != nil {
		return "", false
	}
	if !os.exists(kinemium_dir) {
		if make_err := fsutil.Make_Directory_All(kinemium_dir); make_err != nil {
			delete(kinemium_dir)
			return "", false
		}
	}
	path, path_err := os.join_path({kinemium_dir, "studio-settings.json"}, context.allocator)
	delete(kinemium_dir)
	if path_err != nil {
		return "", false
	}
	return path, true
}

studio_load_settings :: proc(service: ^Studio) {
	path, ok := studio_settings_path()
	if !ok {
		return
	}
	defer delete(path)

	if !os.exists(path) {
		return
	}

	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		return
	}
	defer delete(data, context.allocator)

	value, parse_err := json.parse_string(
		string(data),
		parse_integers = false,
		allocator = context.allocator,
	)
	if parse_err != nil {
		return
	}
	defer json.destroy_value(value)

	obj, is_obj := value.(json.Object)
	if !is_obj {
		return
	}

	for key, v in obj {
		#partial switch typed in v {
		case json.Boolean:
			service.settings[strings.clone(key)] = Studio_Setting {
				kind    = .Boolean,
				boolean = typed,
			}
		case json.Float:
			service.settings[strings.clone(key)] = Studio_Setting {
				kind   = .Number,
				number = typed,
			}
		case json.Integer:
			service.settings[strings.clone(key)] = Studio_Setting {
				kind   = .Number,
				number = f64(typed),
			}
		case json.String:
			service.settings[strings.clone(key)] = Studio_Setting {
				kind       = .String,
				string_val = strings.clone(typed),
			}
		}
	}
}

studio_save_settings :: proc(service: ^Studio) {
	path, ok := studio_settings_path()
	if !ok {
		return
	}
	defer delete(path)

	obj := make(json.Object, context.temp_allocator)
	for key, setting in service.settings {
		switch setting.kind {
		case .Boolean:
			obj[key] = json.Boolean(setting.boolean)
		case .Number:
			obj[key] = json.Float(setting.number)
		case .String:
			obj[key] = json.String(setting.string_val)
		}
	}

	marshalled, err := json.marshal(json.Value(obj), {spec = .JSON}, context.temp_allocator)
	if err != nil {
		return
	}

	_ = os.write_entire_file(path, marshalled)
}

studio_fire_changed :: proc(L: ^vm.State, service: ^Studio, key: string, value_index: int) {
	if service == nil || service.setting_changed == nil || L == nil {
		return
	}

	vm.PushString(L, key)
	vm.PushValue(L, value_index)
	signals.Fire(L, service.setting_changed, 2)
	vm.Pop(L, 2)
}

studio_push_setting :: proc(L: ^vm.State, setting: Studio_Setting) {
	switch setting.kind {
	case .Boolean:
		vm.PushBoolean(L, setting.boolean)
	case .Number:
		vm.PushNumber(L, setting.number)
	case .String:
		vm.PushString(L, setting.string_val)
	}
}

studio_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Studio)
	service^ = Studio {
		service  = Service_Init(&Studio_Class, "Studio", data_model),
		settings = make(map[string]Studio_Setting),
	}

	if service.data_model != nil &&
	   service.data_model.registry != nil &&
	   service.data_model.registry.signal_registry != nil {
		service.setting_changed = signals.Create(service.data_model.registry.signal_registry)
		service.main_pipe = signals.Create(service.data_model.registry.signal_registry)
	}

	studio_load_settings(service)

	return &service.object
}

Studio_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^Studio)object
	if service == nil {
		classes.Object_Destroy(object)
		return
	}


	studio_free_settings(service)
	service.setting_changed = nil

	classes.Object_Destroy(object)
	free(service)
}

studio_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^Studio)object
	switch key {
	case "ReduceMotion":
		if setting, ok := service.settings["reduceMotion"]; ok {
			if setting.kind == .Boolean {
				vm.PushBoolean(L, setting.boolean)
				return true
			}
		}
		vm.PushBoolean(L, false)
		return true
	case "Theme":
		if setting, ok := service.settings["theme"]; ok {
			if setting.kind == .String {
				vm.PushString(L, setting.string_val)
				return true
			}
		}
		vm.PushString(L, "Dark")
		return true
	case "Settings":
		vm.NewTable(L, 0, len(service.settings))
		for k, setting in service.settings {
			studio_push_setting(L, setting)
			vm.SetField(L, -2, k)
		}
		return true
	case "SettingChanged":
		if service.setting_changed != nil {
			signals.Push(L, service.setting_changed)
		} else {
			vm.PushNil(L)
		}
		return true
	case "Pipe":
		signals.Push(L, service.main_pipe)
		return true
	case "GetSetting",
	     "SetSetting",
	     "GetSettings",
	     "ResetSettings",
	     "Reload",
	     "Save",
	     "Test",
	     "GetAvailableThemes":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

studio_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	service := cast(^Studio)object
	switch key {
	case "ReduceMotion":
		value := vm.ArgBoolean(L, value_index)
		if existing, ok := service.settings["reduceMotion"]; ok {
			studio_setting_clear(existing)
		}
		service.settings[strings.clone("reduceMotion")] = Studio_Setting {
			kind    = .Boolean,
			boolean = value,
		}
		studio_save_settings(service)
		vm.PushBoolean(L, value)
		studio_fire_changed(L, service, "reduceMotion", vm.StackTop(L))
		vm.Pop(L)
		return true
	case "Theme":
		value := vm.ArgString(L, value_index)
		if existing, ok := service.settings["theme"]; ok {
			studio_setting_clear(existing)
		}
		service.settings[strings.clone("theme")] = Studio_Setting {
			kind       = .String,
			string_val = strings.clone(value),
		}
		studio_save_settings(service)
		vm.PushString(L, value)
		studio_fire_changed(L, service, "theme", vm.StackTop(L))
		vm.Pop(L)
		return true
	}
	return false
}

studio_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^Studio)object
	switch method {
	case "GetSetting":
		key := vm.ArgString(L, 2)
		if setting, ok := service.settings[key]; ok {
			studio_push_setting(L, setting)
			return 1, true
		}
		if vm.StackTop(L) >= 3 {
			vm.PushValue(L, 3)
			return 1, true
		}
		vm.PushNil(L)
		return 1, true
	case "Test":
		dt := datatype_registry
		vm.NewTable(L, 0, 2)
		vm.PushString(L, "MyTheme")
		vm.SetField(L, -2, "Name")

		vm.NewTable(L, 0, 23)

		datatypes.Push_Color3(L, dt, datatypes.Color3{30.0 / 255.0, 30.0 / 255.0, 46.0 / 255.0})
		vm.SetField(L, -2, "Canvas")

		datatypes.Push_Color3(L, dt, datatypes.Color3{30.0 / 255.0, 30.0 / 255.0, 46.0 / 255.0})
		vm.SetField(L, -2, "Panel")

		datatypes.Push_Color3(L, dt, datatypes.Color3{203.0 / 255.0, 166.0 / 255.0, 247.0 / 255.0})
		vm.SetField(L, -2, "Accent")

		datatypes.Push_Color3(L, dt, datatypes.Color3{49.0 / 255.0, 50.0 / 255.0, 68.0 / 255.0})
		vm.SetField(L, -2, "PanelRaised")

		datatypes.Push_Color3(L, dt, datatypes.Color3{69.0 / 255.0, 71.0 / 255.0, 90.0 / 255.0})
		vm.SetField(L, -2, "Surface")

		datatypes.Push_Color3(L, dt, datatypes.Color3{49.0 / 255.0, 50.0 / 255.0, 68.0 / 255.0})
		vm.SetField(L, -2, "SurfaceAlt")

		datatypes.Push_Color3(L, dt, datatypes.Color3{24.0 / 255.0, 24.0 / 255.0, 37.0 / 255.0})
		vm.SetField(L, -2, "RowEven")

		datatypes.Push_Color3(L, dt, datatypes.Color3{35.0 / 255.0, 35.0 / 255.0, 52.0 / 255.0})
		vm.SetField(L, -2, "RowOdd")

		datatypes.Push_Color3(L, dt, datatypes.Color3{49.0 / 255.0, 50.0 / 255.0, 68.0 / 255.0})
		vm.SetField(L, -2, "Hover")

		datatypes.Push_Color3(L, dt, datatypes.Color3{69.0 / 255.0, 71.0 / 255.0, 90.0 / 255.0})
		vm.SetField(L, -2, "Pressed")

		datatypes.Push_Color3(L, dt, datatypes.Color3{24.0 / 255.0, 24.0 / 255.0, 37.0 / 255.0})
		vm.SetField(L, -2, "Input")

		datatypes.Push_Color3(L, dt, datatypes.Color3{88.0 / 255.0, 91.0 / 255.0, 112.0 / 255.0})
		vm.SetField(L, -2, "Border")

		datatypes.Push_Color3(L, dt, datatypes.Color3{203.0 / 255.0, 166.0 / 255.0, 247.0 / 255.0})
		vm.SetField(L, -2, "BorderStrong")

		datatypes.Push_Color3(L, dt, datatypes.Color3{205.0 / 255.0, 214.0 / 255.0, 244.0 / 255.0})
		vm.SetField(L, -2, "Text")

		datatypes.Push_Color3(L, dt, datatypes.Color3{186.0 / 255.0, 194.0 / 255.0, 222.0 / 255.0})
		vm.SetField(L, -2, "Subtext")

		datatypes.Push_Color3(L, dt, datatypes.Color3{127.0 / 255.0, 132.0 / 255.0, 156.0 / 255.0})
		vm.SetField(L, -2, "Muted")

		datatypes.Push_Color3(L, dt, datatypes.Color3{69.0 / 255.0, 61.0 / 255.0, 91.0 / 255.0})
		vm.SetField(L, -2, "AccentSoft")

		datatypes.Push_Color3(L, dt, datatypes.Color3{88.0 / 255.0, 91.0 / 255.0, 112.0 / 255.0})
		vm.SetField(L, -2, "Selection")

		datatypes.Push_Color3(L, dt, datatypes.Color3{108.0 / 255.0, 112.0 / 255.0, 134.0 / 255.0})
		vm.SetField(L, -2, "SelectionHover")

		datatypes.Push_Color3(L, dt, datatypes.Color3{180.0 / 255.0, 190.0 / 255.0, 254.0 / 255.0})
		vm.SetField(L, -2, "Focus")

		datatypes.Push_Color3(L, dt, datatypes.Color3{249.0 / 255.0, 226.0 / 255.0, 175.0 / 255.0})
		vm.SetField(L, -2, "Warning")

		datatypes.Push_Color3(L, dt, datatypes.Color3{243.0 / 255.0, 139.0 / 255.0, 168.0 / 255.0})
		vm.SetField(L, -2, "Error")

		datatypes.Push_Color3(L, dt, datatypes.Color3{166.0 / 255.0, 227.0 / 255.0, 161.0 / 255.0})
		vm.SetField(L, -2, "Success")

		vm.SetField(L, -2, "Color")

		ref := vm.RetainValue(L)
		Studio_Send_Through_Pipe(service, "NewTheme", ref)
	case "SetSetting":
		key := vm.ArgString(L, 2)
		vt := vm.TypeOf(L, 3)
		#partial switch vt {
		case .Boolean:
			v := vm.ArgBoolean(L, 3)
			if existing, ok := service.settings[key]; ok {
				studio_setting_clear(existing)
			}
			service.settings[strings.clone(key)] = Studio_Setting {
				kind    = .Boolean,
				boolean = v,
			}
			studio_save_settings(service)
			vm.PushBoolean(L, v)
			studio_fire_changed(L, service, key, vm.StackTop(L))
			vm.Pop(L)
			return 1, true
		case .Number:
			v := vm.ArgNumber(L, 3)
			if existing, ok := service.settings[key]; ok {
				studio_setting_clear(existing)
			}
			service.settings[strings.clone(key)] = Studio_Setting {
				kind   = .Number,
				number = v,
			}
			studio_save_settings(service)
			vm.PushNumber(L, v)
			studio_fire_changed(L, service, key, vm.StackTop(L))
			vm.Pop(L)
			return 1, true
		case .String:
			v := vm.ArgString(L, 3)
			if existing, ok := service.settings[key]; ok {
				studio_setting_clear(existing)
			}
			service.settings[strings.clone(key)] = Studio_Setting {
				kind       = .String,
				string_val = strings.clone(v),
			}
			studio_save_settings(service)
			vm.PushString(L, v)
			studio_fire_changed(L, service, key, vm.StackTop(L))
			vm.Pop(L)
			return 1, true
		}
		vm.PushBoolean(L, false)
		return 1, true
	case "GetSettings":
		vm.NewTable(L, 0, len(service.settings))
		for k, setting in service.settings {
			studio_push_setting(L, setting)
			vm.SetField(L, -2, k)
		}
		return 1, true
	case "ResetSettings":
		studio_free_settings(service)
		service.settings = make(map[string]Studio_Setting)
		studio_save_settings(service)
		vm.PushBoolean(L, true)
		return 1, true
	case "Reload":
		studio_free_settings(service)
		service.settings = make(map[string]Studio_Setting)
		studio_load_settings(service)
		vm.PushBoolean(L, true)
		return 1, true
	case "Save":
		studio_save_settings(service)
		vm.PushBoolean(L, true)
		return 1, true
	case "GetAvailableThemes":
		vm.NewTable(L, 0, 7)
		vm.PushString(L, "Dark")
		vm.RawSetIndex(L, -2, 1)
		vm.PushString(L, "Light")
		vm.RawSetIndex(L, -2, 2)
		vm.PushString(L, "Blue")
		vm.RawSetIndex(L, -2, 3)
		vm.PushString(L, "Night")
		vm.RawSetIndex(L, -2, 4)
		vm.PushString(L, "Catppuccin Mocha")
		vm.RawSetIndex(L, -2, 5)
		vm.PushString(L, "Void")
		vm.RawSetIndex(L, -2, 6)
		vm.PushString(L, "Red")
		vm.RawSetIndex(L, -2, 7)
		return 1, true
	}
	return 0, false
}

Register_Studio_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Studio_Class,
		studio_construct,
		Studio_destroy,
		creatable = false,
		get = studio_get,
		set = studio_set,
		namecall = studio_namecall,
	)
}
