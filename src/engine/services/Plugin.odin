package services
// wire:service global="plugin"


import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import fsutil "../fsutil"
import signals "../signals"
import vm "../vm"
import fmt "core:fmt"

import "core:encoding/json"
import "core:os"
import "core:strings"

Plugin_Class := classes.Class_Info {
	name   = "Plugin",
	parent = &Service_Class,
}

Plugin :: struct {
	using service:   Service,
	call_count:      i64,
	active:          bool,
	exclusive_mouse: bool,
	deactivation:    ^signals.Signal,
	unloading:       ^signals.Signal,
	settings:        map[string]Studio_Setting,
	buttons:         [dynamic]^PluginButton,
	toolbars:        [dynamic]^PluginToolbar,
	menus:           [dynamic]^PluginMenu,
	dock_widgets:    [dynamic]^DockWidgetPluginGui,
	next_button_id:  i64,
	next_dock_id:    i64,
}

PluginButton_Kind :: enum {
	Action,
	ToolbarButton,
}

PluginButton :: struct {
	plugin:        ^Plugin,
	id:            i64,
	kind:          PluginButton_Kind,
	toolbar:       ^PluginToolbar,
	action_id:     string,
	text:          string,
	tooltip:       string,
	status_tip:    string,
	icon:          string,
	enabled:       bool,
	allow_binding: bool,
	active:        bool,
	triggered:     ^signals.Signal,
	clicked:       ^signals.Signal,
}

PluginAction :: struct {
	using object: classes.Object,
	button:       PluginButton,
}

PluginToolbarButton :: struct {
	using object: classes.Object,
	button:       PluginButton,
}

PluginToolbar :: struct {
	using object: classes.Object,
	plugin:       ^Plugin,
	title:        string,
	buttons:      [dynamic]^PluginToolbarButton,
}

PluginMenu_Item :: struct {
	separator: bool,
	action:    ^PluginAction,
	menu:      ^PluginMenu,
}

PluginMenu :: struct {
	using object: classes.Object,
	plugin:       ^Plugin,
	title:        string,
	icon:         string,
	items:        [dynamic]PluginMenu_Item,
}

DockWidgetPluginGui_Class := classes.Class_Info {
	name   = "DockWidgetPluginGui",
	parent = &classes.Frame_Class,
}

DockWidgetPluginGui :: struct {
	using frame:   classes.Frame,
	plugin:        ^Plugin,
	id:            i64,
	title:         string,
	title_bar:     bool,
	bind_to_close: bool,
	focused:       bool,
	closed:        bool,
}

PluginAction_Class := classes.Class_Info {
	name   = "PluginAction",
	parent = &classes.Instance_Class,
}

PluginToolbarButton_Class := classes.Class_Info {
	name   = "PluginToolbarButton",
	parent = &classes.Instance_Class,
}

PluginToolbar_Class := classes.Class_Info {
	name   = "PluginToolbar",
	parent = &classes.Instance_Class,
}

PluginMenu_Class := classes.Class_Info {
	name   = "PluginMenu",
	parent = &classes.Instance_Class,
}

Plugin_Engine :: struct {
	min_version: string `json:"minVersion"`,
}

Plugin_Assets :: struct {
	icon_url:      string `json:"iconUrl"`,
	thumbnail_url: string `json:"thumbnailUrl"`,
}

Plugin_Download :: struct {
	name:   string `json:"name"`,
	url:    string `json:"url"`,
	size:   i64 `json:"size"`,
	sha256: string `json:"sha256"`,
}

Plugin_Manifest :: struct {
	name:         string `json:"name"`,
	id:           string `json:"id"`,
	version:      string `json:"version"`,
	description:  string `json:"description"`,
	icon:         string `json:"icon"`,
	thumbnail:    string `json:"thumbnail"`,
	homepage:     string `json:"homepage"`,
	repository:   string `json:"repository"`,
	keywords:     []string `json:"keywords"`,
	author:       string `json:"author"`,
	license:      string `json:"license"`,
	main:         string `json:"main"`,
	engine:       Plugin_Engine `json:"engine"`,
	dependencies: map[string]string `json:"dependencies"`,
	intents:      []string `json:"intents"`,
}

KinemiumPlugin :: struct {
	slug:         string `json:"slug"`,
	generated_at: string `json:"generatedAt"`,
	updated_at:   string `json:"updatedAt"`,
	manifest:     Plugin_Manifest `json:"manifest"`,
	assets:       Plugin_Assets `json:"assets"`,
	download:     Plugin_Download `json:"download"`,
	details_url:  string `json:"detailsUrl"`,
	file_count:   int `json:"fileCount"`,
}

Plugin_List :: struct {
	version:      int `json:"version"`,
	generated_at: string `json:"generatedAt"`,
	plugin_count: int `json:"pluginCount"`,
	plugins:      []KinemiumPlugin `json:"plugins"`,
}

Studio_Theme :: struct {
	Name:           string,
	Canvas:         datatypes.Color3,
	Panel:          datatypes.Color3,
	PanelRaised:    datatypes.Color3,
	Surface:        datatypes.Color3,
	SurfaceAlt:     datatypes.Color3,
	RowEven:        datatypes.Color3,
	RowOdd:         datatypes.Color3,
	Hover:          datatypes.Color3,
	Pressed:        datatypes.Color3,
	Input:          datatypes.Color3,
	Border:         datatypes.Color3,
	BorderStrong:   datatypes.Color3,
	Text:           datatypes.Color3,
	Subtext:        datatypes.Color3,
	Muted:          datatypes.Color3,
	Accent:         datatypes.Color3,
	AccentSoft:     datatypes.Color3,
	Selection:      datatypes.Color3,
	SelectionHover: datatypes.Color3,
	Focus:          datatypes.Color3,
	Warning:        datatypes.Color3,
	Error:          datatypes.Color3,
	Success:        datatypes.Color3,
}

Studio_Window :: struct {
	Content:     ^classes.Object,
	Name:        string,
	Id:          string,
	Tabs:        ^classes.Object,
	selectedTab: string,
	Size:        ^datatypes.UDim2,
	Position:    ^datatypes.UDim2,
}

Studio_Topbar_Button_Type :: enum {
	Default,
	Separator,
	Custom,
}

Studio_Topbar_Button :: struct {
	Name:     string,
	Type:     Studio_Topbar_Button_Type,
	Icon:     string,
	Route:    string,
	Shortcut: string,
	Width:    f64,
	Enabled:  bool,
}

Studio_Topbar_Category :: struct {
	Name:    string,
	Buttons: []Studio_Topbar_Button,
}

Studio_Topbar_New_Category :: struct {
	Name:    string,
	Buttons: []Studio_Topbar_Button,
}

Studio_Topbar_Remove_Category :: struct {
	Name: string,
}

Studio_Topbar_New_Button :: struct {
	Category: string,
	Button:   Studio_Topbar_Button,
	Index:    i64,
}

Studio_Topbar_Remove_Button :: struct {
	Category: string,
	Name:     string,
}

Studio_Topbar_Update_Button :: struct {
	Category:   string,
	Name:       string,
	Properties: Studio_Topbar_Button,
}

Studio_Topbar_Move_Button :: struct {
	Category: string,
	Name:     string,
	Index:    i64,
}

Studio_Topbar_Add_Separator :: struct {
	Category: string,
	Index:    i64,
}

Studio_Topbar_Select_Category :: struct {
	Name: string,
}

Studio_Topbar_Set_Expanded :: struct {
	Value: bool,
}

Studio_Window_Visibility :: struct {
	Name:    string,
	Visible: bool,
}

Studio_Toast :: struct {
	Name:         string,
	Type:         string,
	Title:        string,
	Message:      string,
	Details:      string,
	DetailsTitle: string,
	Duration:     f64,
}

Studio_File_Open :: struct {
	Path: string,
	Name: string,
}

Studio_Snap :: struct {
	Tool:  string,
	Value: f64,
}

Studio_File_Type :: struct {
	Name:       string,
	Extensions: []string,
	Icon:       string,
}

Studio_Window_Background :: struct {
	Name:         string,
	Image:        string,
	Transparency: f64,
	Color:        datatypes.Color3,
	ScaleType:    string,
}

plugins: Plugin_List

plugin_settings_path :: proc() -> (string, bool) {
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
	path, path_err := os.join_path({kinemium_dir, "plugin-settings.json"}, context.allocator)
	delete(kinemium_dir)
	if path_err != nil {
		return "", false
	}
	return path, true
}

plugin_load_settings :: proc(service: ^Plugin) {
	path, ok := plugin_settings_path()
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

plugin_save_settings :: proc(service: ^Plugin) {
	path, ok := plugin_settings_path()
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

plugin_free_settings :: proc(service: ^Plugin) {
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

plugin_pipe_send :: proc(studio: ^Studio, L: ^vm.State, event: string, ref: i32) {
	Studio_Send_Through_Pipe(studio, event, ref)
	vm.ReleaseValue(L, ref)
	vm.Pop(L, 1)
}

plugin_studio :: proc(service: ^Plugin) -> ^Studio {
	if service == nil || service.data_model == nil || service.data_model.registry == nil {
		return nil
	}
	descriptor := Find_Service(service.data_model.registry, "Studio")
	if descriptor == nil || descriptor.object == nil {
		return nil
	}
	return cast(^Studio)descriptor.object
}

plugin_get_color3_arg :: proc(
	field: string,
	L: ^vm.State,
	index: int,
	datatype_registry: ^datatypes.Registry,
) -> datatypes.Color3 {
	_ = vm.GetField(L, index, field)
	defer vm.Pop(L)
	if datatype_registry == nil || !vm.IsUserdataType(L, -1, &datatype_registry.color3) {
		return {}
	}
	return datatypes.Arg_Color3(L, -1, datatype_registry)
}

plugin_next_button_id :: proc(service: ^Plugin) -> i64 {
	service.next_button_id += 1
	return service.next_button_id
}

plugin_arg_string :: proc(L: ^vm.State, index: int) -> string {
	if vm.IsNoneOrNil(L, index) {
		return ""
	}
	return vm.ArgString(L, index)
}

plugin_register_button :: proc(service: ^Plugin, button: ^PluginButton) {
	button.plugin = service
	button.id = plugin_next_button_id(service)
	append(&service.buttons, button)
}

plugin_find_button :: proc(service: ^Plugin, id: i64) -> ^PluginButton {
	for button in service.buttons {
		if button != nil && button.id == id {
			return button
		}
	}
	return nil
}

plugin_emit_button_clicked :: proc(service: ^Plugin, button: ^PluginButton, L: ^vm.State) {
	if button == nil {
		return
	}

	signal := button.clicked
	if button.kind == .Action {
		signal = button.triggered
	}

	if signal != nil {
		signals.Fire(L, signal, 0)
	}
}

Plugin_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Plugin)
	service^ = Plugin {
		service  = Service_Init(&Plugin_Class, "Plugin", data_model),
		settings = make(map[string]Studio_Setting),
	}

	if service.data_model != nil &&
	   service.data_model.registry != nil &&
	   service.data_model.registry.signal_registry != nil {
		service.deactivation = signals.Create(service.data_model.registry.signal_registry)
		service.unloading = signals.Create(service.data_model.registry.signal_registry)
	}

	plugin_load_settings(service)

	return &service.object
}

Plugin_New_Window :: proc(Studio: ^Studio, L: ^vm.State, window: Studio_Window, service: ^Plugin) {
	registry := service.data_model.registry
	dt := registry.classes.datatypes

	vm.NewTable(L, 0, 7)

	vm.PushString(L, window.Name)
	vm.SetField(L, -2, "Name")

	vm.PushString(L, window.Id)
	vm.SetField(L, -2, "Id")

	vm.PushString(L, window.selectedTab)
	vm.SetField(L, -2, "selectedTab")

	if window.Content != nil {
		classes.Push_Object(L, window.Content)
	} else {
		vm.PushNil(L)
	}
	vm.SetField(L, -2, "Content")

	if window.Tabs != nil {
		classes.Push_Object(L, window.Tabs)
	} else {
		vm.PushNil(L)
	}
	vm.SetField(L, -2, "Tabs")

	if window.Size != nil {
		datatypes.Push_UDim2(L, dt, window.Size^)
	} else {
		vm.PushNil(L)
	}
	vm.SetField(L, -2, "Size")

	if window.Position != nil {
		datatypes.Push_UDim2(L, dt, window.Position^)
	} else {
		vm.PushNil(L)
	}
	vm.SetField(L, -2, "Position")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "NewWindow", ref)
}

Studio_Push_Topbar_Button :: proc(Studio: ^Studio, L: ^vm.State, button: Studio_Topbar_Button) {
	vm.NewTable(L, 0, 7)

	vm.PushString(L, button.Name)
	vm.SetField(L, -2, "name")

	switch button.Type {
	case .Default:
		vm.PushNil(L)
	case .Separator:
		vm.PushString(L, "separator")
	case .Custom:
		vm.PushString(L, "custom")
	}
	vm.SetField(L, -2, "type")

	vm.PushString(L, button.Icon)
	vm.SetField(L, -2, "icon")

	vm.PushString(L, button.Route)
	vm.SetField(L, -2, "route")

	vm.PushString(L, button.Shortcut)
	vm.SetField(L, -2, "shortcut")

	vm.PushNumber(L, button.Width)
	vm.SetField(L, -2, "width")

	vm.PushBoolean(L, button.Enabled)
	vm.SetField(L, -2, "enabled")
}

Plugin_Topbar_New_Category :: proc(
	Studio: ^Studio,
	L: ^vm.State,
	category: Studio_Topbar_Category,
) {
	vm.NewTable(L, 0, 2)

	vm.PushString(L, category.Name)
	vm.SetField(L, -2, "Name")

	vm.NewTable(L, len(category.Buttons), 0)

	for button, index in category.Buttons {
		Studio_Push_Topbar_Button(Studio, L, button)
		vm.RawSetIndex(L, -2, index + 1)
	}

	vm.SetField(L, -2, "Buttons")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "NewCategory", ref)
}

Plugin_Topbar_Remove_Category :: proc(Studio: ^Studio, L: ^vm.State, categoryName: string) {
	vm.PushString(L, categoryName)
	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "RemoveCategory", ref)
}

Plugin_Topbar_New_Button :: proc(Studio: ^Studio, L: ^vm.State, data: Studio_Topbar_New_Button) {
	vm.NewTable(L, 0, 3)

	vm.PushString(L, data.Category)
	vm.SetField(L, -2, "Category")

	Studio_Push_Topbar_Button(Studio, L, data.Button)
	vm.SetField(L, -2, "Button")

	vm.PushInteger(L, data.Index)
	vm.SetField(L, -2, "Index")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "NewTopbarButton", ref)
}

Plugin_Topbar_Remove_Button :: proc(
	Studio: ^Studio,
	L: ^vm.State,
	data: Studio_Topbar_Remove_Button,
) {
	vm.NewTable(L, 0, 2)

	vm.PushString(L, data.Category)
	vm.SetField(L, -2, "Category")

	vm.PushString(L, data.Name)
	vm.SetField(L, -2, "Name")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "RemoveTopbarButton", ref)
}

Plugin_Topbar_Move_Button :: proc(Studio: ^Studio, L: ^vm.State, data: Studio_Topbar_Move_Button) {
	vm.NewTable(L, 0, 3)

	vm.PushString(L, data.Category)
	vm.SetField(L, -2, "Category")

	vm.PushString(L, data.Name)
	vm.SetField(L, -2, "Name")

	vm.PushInteger(L, data.Index)
	vm.SetField(L, -2, "Index")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "MoveTopbarButton", ref)
}

Plugin_Topbar_Add_Separator :: proc(
	Studio: ^Studio,
	L: ^vm.State,
	data: Studio_Topbar_Add_Separator,
) {
	vm.NewTable(L, 0, 2)

	vm.PushString(L, data.Category)
	vm.SetField(L, -2, "Category")

	vm.PushInteger(L, data.Index)
	vm.SetField(L, -2, "Index")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "AddTopbarSeparator", ref)
}

Plugin_Topbar_Select_Category :: proc(Studio: ^Studio, L: ^vm.State, categoryName: string) {
	vm.PushString(L, categoryName)
	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "SelectTopbarCategory", ref)
}

Plugin_Topbar_Set_Expanded :: proc(Studio: ^Studio, L: ^vm.State, expanded: bool) {
	vm.PushBoolean(L, expanded)
	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "SetTopbarExpanded", ref)
}

Plugin_New_Theme :: proc(Studio: ^Studio, L: ^vm.State, theme: Studio_Theme, service: ^Plugin) {
	registry := service.data_model.registry
	dt := registry.classes.datatypes

	vm.NewTable(L, 0, 2)
	vm.PushString(L, theme.Name)
	vm.SetField(L, -2, "Name")

	vm.NewTable(L, 0, 23)

	datatypes.Push_Color3(L, dt, theme.Canvas)
	vm.SetField(L, -2, "Canvas")

	datatypes.Push_Color3(L, dt, theme.Panel)
	vm.SetField(L, -2, "Panel")

	datatypes.Push_Color3(L, dt, theme.Accent)
	vm.SetField(L, -2, "Accent")

	datatypes.Push_Color3(L, dt, theme.PanelRaised)
	vm.SetField(L, -2, "PanelRaised")

	datatypes.Push_Color3(L, dt, theme.Surface)
	vm.SetField(L, -2, "Surface")

	datatypes.Push_Color3(L, dt, theme.SurfaceAlt)
	vm.SetField(L, -2, "SurfaceAlt")

	datatypes.Push_Color3(L, dt, theme.RowEven)
	vm.SetField(L, -2, "RowEven")

	datatypes.Push_Color3(L, dt, theme.RowOdd)
	vm.SetField(L, -2, "RowOdd")

	datatypes.Push_Color3(L, dt, theme.Hover)
	vm.SetField(L, -2, "Hover")

	datatypes.Push_Color3(L, dt, theme.Pressed)
	vm.SetField(L, -2, "Pressed")

	datatypes.Push_Color3(L, dt, theme.Input)
	vm.SetField(L, -2, "Input")

	datatypes.Push_Color3(L, dt, theme.Border)
	vm.SetField(L, -2, "Border")

	datatypes.Push_Color3(L, dt, theme.BorderStrong)
	vm.SetField(L, -2, "BorderStrong")

	datatypes.Push_Color3(L, dt, theme.Text)
	vm.SetField(L, -2, "Text")

	datatypes.Push_Color3(L, dt, theme.Subtext)
	vm.SetField(L, -2, "Subtext")

	datatypes.Push_Color3(L, dt, theme.Muted)
	vm.SetField(L, -2, "Muted")

	datatypes.Push_Color3(L, dt, theme.AccentSoft)
	vm.SetField(L, -2, "AccentSoft")

	datatypes.Push_Color3(L, dt, theme.Selection)
	vm.SetField(L, -2, "Selection")

	datatypes.Push_Color3(L, dt, theme.SelectionHover)
	vm.SetField(L, -2, "SelectionHover")

	datatypes.Push_Color3(L, dt, theme.Focus)
	vm.SetField(L, -2, "Focus")

	datatypes.Push_Color3(L, dt, theme.Warning)
	vm.SetField(L, -2, "Warning")

	datatypes.Push_Color3(L, dt, theme.Error)
	vm.SetField(L, -2, "Error")

	datatypes.Push_Color3(L, dt, theme.Success)
	vm.SetField(L, -2, "Success")

	vm.SetField(L, -2, "Color")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "NewTheme", ref)
}

Plugin_Set_Theme :: proc(Studio: ^Studio, L: ^vm.State, theme: string, service: ^Plugin) {
	vm.NewTable(L, 0, 1)

	vm.PushString(L, theme)
	vm.SetField(L, -2, "Name")

	ref := vm.RetainValue(L)
	plugin_pipe_send(Studio, L, "ChangeTheme", ref)
}

Studio_Push_String_Array :: proc(L: ^vm.State, values: []string) {
	vm.NewTable(L, len(values), 0)

	for value, index in values {
		vm.PushString(L, value)
		vm.RawSetIndex(L, -2, index + 1)
	}
}

Plugin_Toggle_Window :: proc(Studio: ^Studio, window: string) {
	Studio_Send_Through_Pipe(Studio, "ToggleWindow", window)
}

Plugin_Set_Window_Visible :: proc(Studio: ^Studio, L: ^vm.State, data: Studio_Window_Visibility) {
	vm.NewTable(L, 0, 2)

	vm.PushString(L, data.Name)
	vm.SetField(L, -2, "Name")

	vm.PushBoolean(L, data.Visible)
	vm.SetField(L, -2, "Visible")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "SetWindowVisible", ref)
}

Plugin_Send_Toast :: proc(Studio: ^Studio, L: ^vm.State, toast: Studio_Toast) {
	vm.NewTable(L, 0, 7)

	vm.PushString(L, toast.Name)
	vm.SetField(L, -2, "name")

	vm.PushString(L, toast.Type)
	vm.SetField(L, -2, "type")

	vm.PushString(L, toast.Title)
	vm.SetField(L, -2, "title")

	vm.PushString(L, toast.Message)
	vm.SetField(L, -2, "message")

	vm.PushString(L, toast.Details)
	vm.SetField(L, -2, "details")

	vm.PushString(L, toast.DetailsTitle)
	vm.SetField(L, -2, "detailsTitle")

	vm.PushNumber(L, toast.Duration)
	vm.SetField(L, -2, "duration")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "Toast", ref)
}

Plugin_Set_Reduce_Motion :: proc(Studio: ^Studio, value: bool) {
	Studio_Send_Through_Pipe(Studio, "SetReduceMotion", value)
}

Plugin_Open_Script :: proc(Studio: ^Studio, object: ^classes.Object) {
	Studio_Send_Through_Pipe(Studio, "OpenScript", object)
}

Plugin_Close_Script :: proc(Studio: ^Studio, object: ^classes.Object) {
	Studio_Send_Through_Pipe(Studio, "CloseScript", object)
}

Plugin_Close_All_Scripts :: proc(Studio: ^Studio) {
	Studio_Send_Through_Pipe(Studio, "CloseAllScripts", true)
}

Plugin_Open_File :: proc(Studio: ^Studio, L: ^vm.State, data: Studio_File_Open) {
	vm.NewTable(L, 0, 2)

	vm.PushString(L, data.Path)
	vm.SetField(L, -2, "Path")

	vm.PushString(L, data.Name)
	vm.SetField(L, -2, "Name")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "OpenFile", ref)
}

Plugin_Close_File :: proc(Studio: ^Studio, path: string) {
	Studio_Send_Through_Pipe(Studio, "CloseFile", path)
}

Plugin_Activate_Tool :: proc(Studio: ^Studio, tool: string) {
	Studio_Send_Through_Pipe(Studio, "ActivateTool", tool)
}

Plugin_Set_Snap :: proc(Studio: ^Studio, L: ^vm.State, data: Studio_Snap) {
	vm.NewTable(L, 0, 2)

	vm.PushString(L, data.Tool)
	vm.SetField(L, -2, "Tool")

	vm.PushNumber(L, data.Value)
	vm.SetField(L, -2, "Value")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "SetSnap", ref)
}

Plugin_Set_Drop_Highlight :: proc(Studio: ^Studio, visible: bool) {
	Studio_Send_Through_Pipe(Studio, "SetDropHighlight", visible)
}

Plugin_Refresh_Files :: proc(Studio: ^Studio) {
	Studio_Send_Through_Pipe(Studio, "RefreshFiles", true)
}

Plugin_Register_File_Type :: proc(Studio: ^Studio, L: ^vm.State, data: Studio_File_Type) {
	vm.NewTable(L, 0, 3)

	vm.PushString(L, data.Name)
	vm.SetField(L, -2, "name")

	Studio_Push_String_Array(L, data.Extensions)
	vm.SetField(L, -2, "extensions")

	vm.PushString(L, data.Icon)
	vm.SetField(L, -2, "icon")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "RegisterFileType", ref)
}

Plugin_Toggle_Explorer :: proc(Studio: ^Studio) {
	Studio_Send_Through_Pipe(Studio, "ToggleExplorer", true)
}

Plugin_Toggle_Inspector :: proc(Studio: ^Studio) {
	Studio_Send_Through_Pipe(Studio, "ToggleInspector", true)
}

Plugin_Toggle_Output :: proc(Studio: ^Studio) {
	Studio_Send_Through_Pipe(Studio, "ToggleOutput", true)
}

Plugin_Set_Exporter_Visible :: proc(Studio: ^Studio, visible: bool) {
	if visible {
		Studio_Send_Through_Pipe(Studio, "ShowExporter", true)
	} else {
		Studio_Send_Through_Pipe(Studio, "HideExporter", true)
	}
}

Plugin_Toggle_Exporter :: proc(Studio: ^Studio) {
	Studio_Send_Through_Pipe(Studio, "ToggleExporter", true)
}

Plugin_Set_Terrain_Editor_Visible :: proc(Studio: ^Studio, visible: bool) {
	if visible {
		Studio_Send_Through_Pipe(Studio, "ShowTerrainEditor", true)
	} else {
		Studio_Send_Through_Pipe(Studio, "HideTerrainEditor", true)
	}
}

Plugin_Toggle_Terrain_Editor :: proc(Studio: ^Studio) {
	Studio_Send_Through_Pipe(Studio, "ToggleTerrainEditor", true)
}

Plugin_Set_Font_Picker_Visible :: proc(Studio: ^Studio, visible: bool) {
	if visible {
		Studio_Send_Through_Pipe(Studio, "ShowFontPicker", true)
	} else {
		Studio_Send_Through_Pipe(Studio, "HideFontPicker", true)
	}
}

Plugin_Toggle_Font_Picker :: proc(Studio: ^Studio) {
	Studio_Send_Through_Pipe(Studio, "ToggleFontPicker", true)
}

Plugin_Set_Icon_Picker_Visible :: proc(Studio: ^Studio, visible: bool) {
	if visible {
		Studio_Send_Through_Pipe(Studio, "ShowIconPicker", true)
	} else {
		Studio_Send_Through_Pipe(Studio, "HideIconPicker", true)
	}
}

Plugin_Toggle_Icon_Picker :: proc(Studio: ^Studio) {
	Studio_Send_Through_Pipe(Studio, "ToggleIconPicker", true)
}

Plugin_Show_Image :: proc(Studio: ^Studio, L: ^vm.State, data: Studio_File_Open) {
	vm.NewTable(L, 0, 2)

	vm.PushString(L, data.Path)
	vm.SetField(L, -2, "Path")

	vm.PushString(L, data.Name)
	vm.SetField(L, -2, "Name")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "ShowImage", ref)
}

Plugin_Open_Login :: proc(Studio: ^Studio, L: ^vm.State) {
	vm.NewTable(L, 0, 0)
	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "Login", ref)
}

Plugin_Open_Sign_Up :: proc(Studio: ^Studio, L: ^vm.State) {
	vm.NewTable(L, 0, 0)
	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "SignUp", ref)
}

Plugin_Send_Module_Call :: proc(
	Studio: ^Studio,
	L: ^vm.State,
	module_name, method_name: string,
	args_ref: i32 = 0,
) {
	vm.NewTable(L, 0, 3)

	vm.PushString(L, module_name)
	vm.SetField(L, -2, "Module")

	vm.PushString(L, method_name)
	vm.SetField(L, -2, "Method")

	if args_ref != 0 {
		vm.PushRegistryReference(L, args_ref)
	} else {
		vm.NewTable(L, 0, 0)
	}
	vm.SetField(L, -2, "Args")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "ModuleCall", ref)
}

Plugin_Refresh_Component :: proc(Studio: ^Studio, component: string) {
	Studio_Send_Through_Pipe(Studio, "RefreshComponent", component)
}

Plugin_Refresh_Component_With_Props :: proc(
	Studio: ^Studio,
	L: ^vm.State,
	component: string,
	props_ref: i32,
) {
	vm.NewTable(L, 0, 2)

	vm.PushString(L, component)
	vm.SetField(L, -2, "Component")

	if props_ref != 0 {
		vm.PushRegistryReference(L, props_ref)
	} else {
		vm.NewTable(L, 0, 0)
	}
	vm.SetField(L, -2, "Props")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "RefreshComponent", ref)
}

Plugin_Set_Component_Props :: proc(
	Studio: ^Studio,
	L: ^vm.State,
	component: string,
	props_ref: i32,
) {
	vm.NewTable(L, 0, 2)

	vm.PushString(L, component)
	vm.SetField(L, -2, "Component")

	if props_ref != 0 {
		vm.PushRegistryReference(L, props_ref)
	} else {
		vm.NewTable(L, 0, 0)
	}
	vm.SetField(L, -2, "Props")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "SetComponentProps", ref)
}

Plugin_Refresh_Components :: proc(Studio: ^Studio) {
	Studio_Send_Through_Pipe(Studio, "RefreshComponents", true)
}

Plugin_Refresh_Module :: proc(Studio: ^Studio, L: ^vm.State, module_name: string) {
	vm.NewTable(L, 0, 1)

	vm.PushString(L, module_name)
	vm.SetField(L, -2, "Module")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "RefreshModule", ref)
}

Plugin_Set_Window_Background :: proc(
	Studio: ^Studio,
	L: ^vm.State,
	background: Studio_Window_Background,
	service: ^Plugin,
) {
	registry := service.data_model.registry
	dt := registry.classes.datatypes

	component := strings.concatenate({"window:", background.Name})
	defer delete(component)

	vm.NewTable(L, 0, 2)

	vm.PushString(L, component)
	vm.SetField(L, -2, "Component")

	vm.NewTable(L, 0, 4)

	vm.PushString(L, background.Image)
	vm.SetField(L, -2, "backgroundImage")

	vm.PushNumber(L, background.Transparency)
	vm.SetField(L, -2, "backgroundImageTransparency")

	datatypes.Push_Color3(L, dt, background.Color)
	vm.SetField(L, -2, "backgroundImageColor")

	if background.ScaleType != "" {
		vm.PushString(L, background.ScaleType)
		vm.SetField(L, -2, "backgroundImageScaleType")
	}

	vm.SetField(L, -2, "Props")

	ref := vm.RetainValue(L)
	Studio_Send_Through_Pipe(Studio, "SetComponentProps", ref)
}

Plugin_Send_Dock_Title :: proc(studio: ^Studio, L: ^vm.State, dock: ^DockWidgetPluginGui) {
	vm.NewTable(L, 0, 2)

	vm.PushNumber(L, f64(dock.id))
	vm.SetField(L, -2, "Id")

	vm.PushString(L, dock.title)
	vm.SetField(L, -2, "Title")

	ref := vm.RetainValue(L)
	plugin_pipe_send(studio, L, "PluginDockWidgetTitle", ref)
}

PLUGIN_MENU_MAX_DEPTH :: 32

plugin_push_menu_items :: proc(L: ^vm.State, menu: ^PluginMenu, depth := 0) {
	if menu == nil || depth > PLUGIN_MENU_MAX_DEPTH {
		vm.NewTable(L, 0, 0)
		return
	}

	items := menu.items
	vm.NewTable(L, len(items), 0)

	for item, index in items {
		if item.separator {
			vm.NewTable(L, 0, 1)
			vm.PushBoolean(L, true)
			vm.SetField(L, -2, "Separator")
		} else if item.menu != nil {
			vm.NewTable(L, 0, 3)
			vm.PushString(L, item.menu.title)
			vm.SetField(L, -2, "Label")
			if len(item.menu.icon) > 0 {
				vm.PushString(L, item.menu.icon)
				vm.SetField(L, -2, "Icon")
			}
			plugin_push_menu_items(L, item.menu, depth + 1)
			vm.SetField(L, -2, "Children")
		} else if item.action != nil {
			vm.NewTable(L, 0, 4)
			vm.PushString(L, item.action.button.text)
			vm.SetField(L, -2, "Label")
			vm.PushString(L, item.action.button.icon)
			vm.SetField(L, -2, "Icon")
			vm.PushBoolean(L, item.action.button.enabled)
			vm.SetField(L, -2, "Enabled")
			vm.PushNumber(L, f64(item.action.button.id))
			vm.SetField(L, -2, "ActionId")
		} else {
			vm.NewTable(L, 0, 0)
		}

		vm.RawSetIndex(L, -2, index + 1)
	}
}

Plugin_Send_Menu :: proc(studio: ^Studio, L: ^vm.State, menu: ^PluginMenu) {
	vm.NewTable(L, 0, 1)
	plugin_push_menu_items(L, menu)
	vm.SetField(L, -2, "Items")

	ref := vm.RetainValue(L)
	plugin_pipe_send(studio, L, "PluginMenuShow", ref)
}

Plugin_Send_Dock_Created :: proc(studio: ^Studio, L: ^vm.State, dock: ^DockWidgetPluginGui) {
	vm.NewTable(L, 0, 6)

	vm.PushNumber(L, f64(dock.id))
	vm.SetField(L, -2, "Id")

	vm.PushString(L, dock.title)
	vm.SetField(L, -2, "Title")

	vm.PushBoolean(L, dock.frame.gui_object.visible)
	vm.SetField(L, -2, "Visible")

	classes.Push_Object(L, &dock.frame.object)
	vm.SetField(L, -2, "Object")

	vm.PushNumber(L, f64(dock.frame.gui_object.size.X_Offset))
	vm.SetField(L, -2, "Width")

	vm.PushNumber(L, f64(dock.frame.gui_object.size.Y_Offset))
	vm.SetField(L, -2, "Height")

	ref := vm.RetainValue(L)
	plugin_pipe_send(studio, L, "PluginDockWidgetCreated", ref)
}

Plugin_Send_Dock_Closed :: proc(studio: ^Studio, L: ^vm.State, dock: ^DockWidgetPluginGui) {
	vm.NewTable(L, 0, 1)

	vm.PushNumber(L, f64(dock.id))
	vm.SetField(L, -2, "Id")

	ref := vm.RetainValue(L)
	plugin_pipe_send(studio, L, "PluginDockWidgetClosed", ref)
}

Plugin_Send_Dock_Visible :: proc(studio: ^Studio, L: ^vm.State, dock: ^DockWidgetPluginGui) {
	vm.NewTable(L, 0, 2)

	vm.PushNumber(L, f64(dock.id))
	vm.SetField(L, -2, "Id")

	vm.PushBoolean(L, dock.frame.gui_object.visible)
	vm.SetField(L, -2, "Visible")

	ref := vm.RetainValue(L)
	plugin_pipe_send(studio, L, "PluginDockWidgetVisible", ref)
}

Plugin_Send_Button_Added :: proc(studio: ^Studio, L: ^vm.State, button: ^PluginButton) {
	vm.NewTable(L, 0, 7)

	vm.PushNumber(L, f64(button.id))
	vm.SetField(L, -2, "Id")

	vm.PushString(L, button.text)
	vm.SetField(L, -2, "Text")

	vm.PushString(L, plugin_button_toolbar_title(button))
	vm.SetField(L, -2, "Toolbar")

	vm.PushString(L, button.tooltip)
	vm.SetField(L, -2, "ToolTip")

	vm.PushString(L, button.icon)
	vm.SetField(L, -2, "Icon")

	vm.PushBoolean(L, button.enabled)
	vm.SetField(L, -2, "Enabled")

	vm.PushBoolean(L, button.active)
	vm.SetField(L, -2, "Active")

	ref := vm.RetainValue(L)
	plugin_pipe_send(studio, L, "PluginToolbarButtonAdded", ref)
}

plugin_button_toolbar_title :: proc(button: ^PluginButton) -> string {
	if button.toolbar == nil {
		return ""
	}

	return button.toolbar.title
}

Plugin_Send_Button_Updated :: proc(
	studio: ^Studio,
	L: ^vm.State,
	button: ^PluginButton,
	old_text: string,
) {
	vm.NewTable(L, 0, 8)

	vm.PushNumber(L, f64(button.id))
	vm.SetField(L, -2, "Id")

	vm.PushString(L, button.text)
	vm.SetField(L, -2, "Text")

	vm.PushString(L, old_text)
	vm.SetField(L, -2, "OldText")

	vm.PushString(L, plugin_button_toolbar_title(button))
	vm.SetField(L, -2, "Toolbar")

	vm.PushString(L, button.tooltip)
	vm.SetField(L, -2, "ToolTip")

	vm.PushString(L, button.icon)
	vm.SetField(L, -2, "Icon")

	vm.PushBoolean(L, button.enabled)
	vm.SetField(L, -2, "Enabled")

	vm.PushBoolean(L, button.active)
	vm.SetField(L, -2, "Active")

	ref := vm.RetainValue(L)
	plugin_pipe_send(studio, L, "PluginToolbarButtonUpdated", ref)
}

Plugin_Send_Button_Removed :: proc(studio: ^Studio, L: ^vm.State, button: ^PluginButton) {
	vm.NewTable(L, 0, 2)

	vm.PushNumber(L, f64(button.id))
	vm.SetField(L, -2, "Id")

	vm.PushString(L, button.text)
	vm.SetField(L, -2, "Text")

	ref := vm.RetainValue(L)
	plugin_pipe_send(studio, L, "PluginToolbarButtonRemoved", ref)
}

plugin_button_free_strings :: proc(button: ^PluginButton) {
	if button == nil {
		return
	}
	if len(button.text) > 0 {
		delete(button.text)
	}
	if len(button.tooltip) > 0 {
		delete(button.tooltip)
	}
	if len(button.status_tip) > 0 {
		delete(button.status_tip)
	}
	if len(button.icon) > 0 {
		delete(button.icon)
	}
	if len(button.action_id) > 0 {
		delete(button.action_id)
	}
	button.text = ""
	button.tooltip = ""
	button.status_tip = ""
	button.icon = ""
	button.action_id = ""
}

plugin_remove_button :: proc(button: ^PluginButton) {
	if button == nil || button.plugin == nil {
		return
	}
	service := button.plugin
	for candidate, index in service.buttons {
		if candidate == button {
			ordered_remove(&service.buttons, index)
			break
		}
	}
	if studio := plugin_studio(service); studio != nil {
		if registry := service.data_model.registry;
		   registry != nil && registry.vm_state != nil && registry.vm_state.L != nil {
			Plugin_Send_Button_Removed(studio, registry.vm_state.L, button)
		}
	}
	if button.triggered != nil {
		signals.Destroy(button.triggered)
		button.triggered = nil
	}
	if button.clicked != nil {
		signals.Destroy(button.clicked)
		button.clicked = nil
	}
	plugin_button_free_strings(button)
}

plugin_button_get :: proc(L: ^vm.State, button: ^PluginButton, key: string) -> bool {
	switch key {
	case "ActionId":
		vm.PushString(L, button.action_id)
	case "AllowBinding":
		vm.PushBoolean(L, button.allow_binding)
	case "Text":
		vm.PushString(L, button.text)
	case "ToolTip":
		vm.PushString(L, button.tooltip)
	case "StatusTip":
		vm.PushString(L, button.status_tip)
	case "Icon":
		vm.PushString(L, button.icon)
	case "Enabled":
		vm.PushBoolean(L, button.enabled)
	case "Active":
		vm.PushBoolean(L, button.active)
	case "Triggered":
		if button.triggered == nil {
			button.triggered = signals.Create(button.plugin.object.signal_registry.signal_registry)
		}
		signals.Push(L, button.triggered)
	case "Click", "Clicked":
		if button.clicked == nil {
			button.clicked = signals.Create(button.plugin.object.signal_registry.signal_registry)
		}
		signals.Push(L, button.clicked)
	case:
		return false
	}
	return true
}

plugin_button_set :: proc(
	L: ^vm.State,
	button: ^PluginButton,
	key: string,
	value_index: int,
) -> bool {
	studio := plugin_studio(button.plugin)
	old_text := button.text

	old_value := ""
	switch key {
	case "Text":
		old_value = button.text
		button.text = strings.clone(vm.ArgString(L, value_index))
	case "ToolTip":
		old_value = button.tooltip
		button.tooltip = strings.clone(vm.ArgString(L, value_index))
	case "StatusTip":
		old_value = button.status_tip
		button.status_tip = strings.clone(vm.ArgString(L, value_index))
	case "Icon":
		old_value = button.icon
		button.icon = strings.clone(vm.ArgString(L, value_index))
	case "Enabled":
		button.enabled = vm.ArgBoolean(L, value_index)
	case:
		return false
	}

	if studio != nil {
		Plugin_Send_Button_Updated(studio, L, button, old_text)
	}

	if len(old_value) > 0 {
		delete(old_value)
	}

	return true
}

plugin_action_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	action := new(PluginAction)
	action^ = PluginAction {
		object = classes.Object_Init(&PluginAction_Class, "PluginAction"),
		button = PluginButton{kind = .Action, enabled = true, allow_binding = true},
	}
	return &action.object
}

plugin_action_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	action := cast(^PluginAction)object
	if action.button.plugin != nil {
		for menu in action.button.plugin.menus {
			if menu == nil {
				continue
			}
			for index := len(menu.items) - 1; index >= 0; index -= 1 {
				if menu.items[index].action == action {
					ordered_remove(&menu.items, index)
				}
			}
		}
	}
	plugin_remove_button(&action.button)
	classes.Object_Destroy(object)
	free(action)
}

plugin_action_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	action := cast(^PluginAction)object
	return plugin_button_get(L, &action.button, key)
}

plugin_action_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	action := cast(^PluginAction)object
	return plugin_button_set(L, &action.button, key, value_index)
}

plugin_action_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	action := cast(^PluginAction)object
	switch method {
	case "SetActive":
		action.button.active = vm.ArgBoolean(L, 2)
		return 0, true
	}
	return 0, false
}

plugin_toolbar_button_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	button := new(PluginToolbarButton)
	button^ = PluginToolbarButton {
		object = classes.Object_Init(&PluginToolbarButton_Class, "PluginToolbarButton"),
		button = PluginButton{kind = .ToolbarButton, enabled = true},
	}
	return &button.object
}

plugin_toolbar_button_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	button := cast(^PluginToolbarButton)object
	plugin_remove_button(&button.button)
	if button.button.toolbar != nil {
		for candidate, index in button.button.toolbar.buttons {
			if candidate == button {
				ordered_remove(&button.button.toolbar.buttons, index)
				break
			}
		}
	}
	classes.Object_Destroy(object)
	free(button)
}

plugin_toolbar_button_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	button := cast(^PluginToolbarButton)object
	return plugin_button_get(L, &button.button, key)
}

plugin_toolbar_button_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	button := cast(^PluginToolbarButton)object
	return plugin_button_set(L, &button.button, key, value_index)
}

plugin_toolbar_button_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	button := cast(^PluginToolbarButton)object
	switch method {
	case "SetActive":
		button.button.active = vm.ArgBoolean(L, 2)
		if studio := plugin_studio(button.button.plugin); studio != nil {
			Plugin_Send_Button_Updated(studio, L, &button.button, button.button.text)
		}
		return 0, true
	}
	return 0, false
}

plugin_toolbar_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	toolbar := new(PluginToolbar)
	toolbar^ = PluginToolbar {
		object = classes.Object_Init(&PluginToolbar_Class, "PluginToolbar"),
	}
	return &toolbar.object
}

plugin_toolbar_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	toolbar := cast(^PluginToolbar)object
	for child in toolbar.buttons {
		if child != nil && child.button.toolbar == toolbar {
			child.button.toolbar = nil
		}
	}
	if toolbar.plugin != nil {
		for candidate, index in toolbar.plugin.toolbars {
			if candidate == toolbar {
				ordered_remove(&toolbar.plugin.toolbars, index)
				break
			}
		}
	}
	if len(toolbar.title) > 0 {
		delete(toolbar.title)
	}
	delete(toolbar.buttons)
	classes.Object_Destroy(object)
	free(toolbar)
}

plugin_toolbar_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	toolbar := cast(^PluginToolbar)object
	switch key {
	case "Title":
		vm.PushString(L, toolbar.title)
	case "CreateButton":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

plugin_toolbar_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	toolbar := cast(^PluginToolbar)object
	service := toolbar.plugin

	switch method {
	case "CreateButton":
		if service == nil || service.data_model == nil || service.data_model.registry == nil {
			return 0, false
		}
		registry := service.data_model.registry

		button_id := vm.ArgString(L, 2)
		tooltip := plugin_arg_string(L, 3)
		icon := plugin_arg_string(L, 4)
		text := plugin_arg_string(L, 5)
		if text == "" {
			text = button_id
		}

		button_object, ok := classes.Push_New(
			registry.classes,
			&vm.VM{L = L},
			"PluginToolbarButton",
			false,
		)
		if !ok || button_object == nil {
			return 0, false
		}

		button := cast(^PluginToolbarButton)button_object
		button.button.toolbar = toolbar
		button.button.text = strings.clone(text)
		button.button.tooltip = strings.clone(tooltip)
		button.button.icon = strings.clone(icon)
		plugin_register_button(service, &button.button)
		append(&toolbar.buttons, button)

		if studio := plugin_studio(service); studio != nil {
			Plugin_Send_Button_Added(studio, L, &button.button)
		}

		return 1, true
	}

	return 0, false
}

plugin_menu_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	menu := new(PluginMenu)
	menu^ = PluginMenu {
		object = classes.Object_Init(&PluginMenu_Class, "PluginMenu"),
	}
	return &menu.object
}

plugin_menu_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	menu := cast(^PluginMenu)object
	if menu.plugin != nil {
		for other in menu.plugin.menus {
			if other == nil || other == menu {
				continue
			}
			for index := len(other.items) - 1; index >= 0; index -= 1 {
				if other.items[index].menu == menu {
					ordered_remove(&other.items, index)
				}
			}
		}
		for candidate, index in menu.plugin.menus {
			if candidate == menu {
				ordered_remove(&menu.plugin.menus, index)
				break
			}
		}
	}
	if len(menu.title) > 0 {
		delete(menu.title)
	}
	if len(menu.icon) > 0 {
		delete(menu.icon)
	}
	delete(menu.items)
	classes.Object_Destroy(object)
	free(menu)
}

plugin_menu_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	menu := cast(^PluginMenu)object
	switch key {
	case "Title":
		vm.PushString(L, menu.title)
	case "Icon":
		vm.PushString(L, menu.icon)
	case "AddAction", "AddMenu", "AddNewAction", "AddSeparator", "Clear", "ShowAsync":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

plugin_menu_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	menu := cast(^PluginMenu)object

	switch method {
	case "AddAction":
		target := cast(^classes.Object)vm.UserdataValue(L, 2)
		if target == nil || !classes.Is_A(target, "PluginAction") {
			_ = vm.RaiseError(L, "PluginMenu:AddAction expects a PluginAction")
			return 0, false
		}
		append(&menu.items, PluginMenu_Item{action = cast(^PluginAction)target})
		return 0, true
	case "AddMenu":
		target := cast(^classes.Object)vm.UserdataValue(L, 2)
		if target == nil || !classes.Is_A(target, "PluginMenu") {
			_ = vm.RaiseError(L, "PluginMenu:AddMenu expects a PluginMenu")
			return 0, false
		}
		append(&menu.items, PluginMenu_Item{menu = cast(^PluginMenu)target})
		return 0, true
	case "AddNewAction":
		service := menu.plugin
		if service == nil || service.data_model == nil || service.data_model.registry == nil {
			return 0, false
		}

		action_id := vm.ArgString(L, 2)
		text := plugin_arg_string(L, 3)
		icon := plugin_arg_string(L, 4)

		object, ok := classes.Push_New(
			service.data_model.registry.classes,
			&vm.VM{L = L},
			"PluginAction",
			false,
		)
		if !ok || object == nil {
			return 0, false
		}
		action := cast(^PluginAction)object
		action.button.action_id = strings.clone(action_id)
		action.button.text = strings.clone(text)
		action.button.icon = strings.clone(icon)
		if len(action.button.text) == 0 {
			action.button.text = strings.clone(action.button.action_id)
		}
		plugin_register_button(service, &action.button)
		append(&menu.items, PluginMenu_Item{action = action})
		return 1, true
	case "AddSeparator":
		append(&menu.items, PluginMenu_Item{separator = true})
		return 0, true
	case "Clear":
		clear(&menu.items)
		return 0, true
	case "ShowAsync":
		if studio := plugin_studio(menu.plugin); studio != nil {
			Plugin_Send_Menu(studio, L, menu)
		}
		vm.PushNil(L)
		return 1, true
	}

	return 0, false
}

plugin_dock_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	dock := new(DockWidgetPluginGui)
	dock^ = DockWidgetPluginGui {
		frame     = classes.Frame_Init(),
		title_bar = true,
	}
	dock.frame.object.class = &DockWidgetPluginGui_Class
	dock.frame.object.name = "DockWidgetPluginGui"
	return &dock.frame.object
}

plugin_dock_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	dock := cast(^DockWidgetPluginGui)object
	if dock.plugin != nil {
		if !dock.closed {
			if studio := plugin_studio(dock.plugin); studio != nil {
				if registry := dock.plugin.data_model.registry;
				   registry != nil && registry.vm_state != nil && registry.vm_state.L != nil {
					Plugin_Send_Dock_Closed(studio, registry.vm_state.L, dock)
				}
			}
		}
		for candidate, index in dock.plugin.dock_widgets {
			if candidate == dock {
				ordered_remove(&dock.plugin.dock_widgets, index)
				break
			}
		}
	}
	if len(dock.title) > 0 {
		delete(dock.title)
	}
	classes.GuiObject_Free_Signals(cast(^classes.GuiObject)object)
	classes.Object_Destroy(object)
	free(dock)
}

plugin_dock_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	dock := cast(^DockWidgetPluginGui)object
	switch key {
	case "Title":
		vm.PushString(L, dock.title)
	case "TitleBar":
		vm.PushBoolean(L, dock.title_bar)
	case "BindToClose":
		vm.PushBoolean(L, dock.bind_to_close)
	case "IsFocused":
		vm.PushBoolean(L, dock.focused)
	case "Enabled":
		vm.PushBoolean(L, dock.frame.gui_object.visible)
	case "Close":
		vm.PushUserdataMethod(L, key)
	case:
		return classes.Frame_get(L, object, datatype_registry, enum_registry, key)
	}
	return true
}

plugin_dock_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	fmt.println("[dock_set] key =", key)
	dock := cast(^DockWidgetPluginGui)object
	studio := plugin_studio(dock.plugin)
	fmt.println("[dock_set] studio nil?", studio == nil, "plugin nil?", dock.plugin == nil)

	switch key {
	case "Title":
		if len(dock.title) > 0 {
			delete(dock.title)
		}
		dock.title = strings.clone(vm.ArgString(L, value_index))
		if studio != nil {
			Plugin_Send_Dock_Title(studio, L, dock)
		}
		return true
	case "TitleBar":
		dock.title_bar = vm.ArgBoolean(L, value_index)
		return true
	case "BindToClose":
		dock.bind_to_close = vm.ArgBoolean(L, value_index)
		return true
	case "Enabled":
		dock.frame.gui_object.visible = vm.ArgBoolean(L, value_index)
		if studio != nil {
			Plugin_Send_Dock_Visible(studio, L, dock)
		}
		return true
	}

	return classes.Frame_set(L, object, datatype_registry, enum_registry, key, value_index)
}

plugin_dock_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	dock := cast(^DockWidgetPluginGui)object

	switch method {
	case "Close":
		dock.closed = true
		dock.frame.gui_object.visible = false
		if studio := plugin_studio(dock.plugin); studio != nil {
			Plugin_Send_Dock_Closed(studio, L, dock)
		}
		return 0, true
	}

	return 0, false
}

plugin_create_toolbar :: proc(service: ^Plugin, L: ^vm.State) -> (i32, bool) {
	if service.data_model == nil || service.data_model.registry == nil {
		return 0, false
	}
	registry := service.data_model.registry
	title := vm.ArgString(L, 2)

	object, ok := classes.Push_New(registry.classes, &vm.VM{L = L}, "PluginToolbar", false)
	if !ok || object == nil {
		return 0, false
	}

	toolbar := cast(^PluginToolbar)object
	toolbar.plugin = service
	toolbar.title = strings.clone(title)
	append(&service.toolbars, toolbar)

	return 1, true
}

plugin_create_action :: proc(service: ^Plugin, L: ^vm.State) -> (i32, bool) {
	if service.data_model == nil || service.data_model.registry == nil {
		return 0, false
	}
	registry := service.data_model.registry

	action_id := vm.ArgString(L, 2)
	text := plugin_arg_string(L, 3)
	status_tip := plugin_arg_string(L, 4)
	icon := plugin_arg_string(L, 5)
	allow_binding := !vm.IsNoneOrNil(L, 6) && vm.ArgBoolean(L, 6)

	object, ok := classes.Push_New(registry.classes, &vm.VM{L = L}, "PluginAction", false)
	if !ok || object == nil {
		return 0, false
	}

	action := cast(^PluginAction)object
	action.button.kind = .Action
	action.button.action_id = strings.clone(action_id)
	action.button.text = strings.clone(text)
	action.button.status_tip = strings.clone(status_tip)
	action.button.icon = strings.clone(icon)
	action.button.allow_binding = allow_binding
	if len(action.button.text) == 0 {
		action.button.text = strings.clone(action.button.action_id)
	}
	plugin_register_button(service, &action.button)

	return 1, true
}

plugin_create_menu :: proc(service: ^Plugin, L: ^vm.State) -> (i32, bool) {
	if service.data_model == nil || service.data_model.registry == nil {
		return 0, false
	}
	registry := service.data_model.registry

	title := plugin_arg_string(L, 3)
	icon := plugin_arg_string(L, 4)

	object, ok := classes.Push_New(registry.classes, &vm.VM{L = L}, "PluginMenu", false)
	if !ok || object == nil {
		return 0, false
	}

	menu := cast(^PluginMenu)object
	menu.plugin = service
	menu.title = strings.clone(title)
	menu.icon = strings.clone(icon)
	append(&service.menus, menu)

	return 1, true
}

plugin_create_dock_widget :: proc(service: ^Plugin, L: ^vm.State, async: bool) -> (i32, bool) {
	if service.data_model == nil || service.data_model.registry == nil {
		return 0, false
	}
	registry := service.data_model.registry
	if registry.classes == nil || registry.classes.datatypes == nil {
		return 0, false
	}

	plugin_gui_id := strings.clone(vm.ArgString(L, 2))
	info := datatypes.Arg_DockWidgetPluginGuiInfo(L, 3, registry.classes.datatypes)

	object, ok := classes.Push_New(registry.classes, &vm.VM{L = L}, "DockWidgetPluginGui", false)
	if !ok || object == nil {
		delete(plugin_gui_id)
		return 0, false
	}

	dock := cast(^DockWidgetPluginGui)object
	dock.plugin = service
	service.next_dock_id += 1
	dock.id = service.next_dock_id
	dock.title = plugin_gui_id
	classes.Set_Name(&dock.frame.object, plugin_gui_id)
	dock.frame.gui_object.visible = info.initial_enabled
	dock.frame.gui_object.size = datatypes.UDim2_FromOffset(
		f32(info.floating_x_size),
		f32(info.floating_y_size),
	)
	append(&service.dock_widgets, dock)

	if studio := plugin_studio(service); studio != nil {
		Plugin_Send_Dock_Created(studio, L, dock)
	}

	return 1, true
}

plugin_get_setting :: proc(service: ^Plugin, L: ^vm.State, key: string) {
	if setting, ok := service.settings[key]; ok {
		studio_push_setting(L, setting)
		return
	}
	vm.PushNil(L)
}

plugin_remove_setting :: proc(service: ^Plugin, key: string) {
	existing, ok := service.settings[key]
	if !ok {
		return
	}

	studio_setting_clear(existing)

	stored_key := ""
	for candidate in service.settings {
		if candidate == key {
			stored_key = candidate
			break
		}
	}

	delete_key(&service.settings, key)
	if len(stored_key) > 0 {
		delete(stored_key)
	}
}

plugin_set_setting :: proc(service: ^Plugin, L: ^vm.State, key: string) {
	value_index := 3
	kind := vm.TypeOf(L, value_index)

	if vm.IsNoneOrNil(L, value_index) || (kind != .Boolean && kind != .Number && kind != .String) {
		plugin_remove_setting(service, key)
		plugin_save_settings(service)
		return
	}

	existing, has_existing := service.settings[key]
	stored_key := key
	if has_existing {
		studio_setting_clear(existing)
	} else {
		stored_key = strings.clone(key)
	}

	#partial switch kind {
	case .Boolean:
		service.settings[stored_key] = Studio_Setting {
			kind    = .Boolean,
			boolean = vm.ArgBoolean(L, value_index),
		}
	case .Number:
		service.settings[stored_key] = Studio_Setting {
			kind   = .Number,
			number = vm.ArgNumber(L, value_index),
		}
	case .String:
		service.settings[stored_key] = Studio_Setting {
			kind       = .String,
			string_val = strings.clone(vm.ArgString(L, value_index)),
		}
	case:
		if !has_existing {
			delete(stored_key)
		}
	}

	plugin_save_settings(service)
}

plugin_open_script :: proc(service: ^Plugin, L: ^vm.State) {
	script := cast(^classes.Object)vm.UserdataValue(L, 2)
	if script == nil {
		return
	}
	studio := plugin_studio(service)
	if studio == nil {
		return
	}

	vm.NewTable(L, 0, 2)
	classes.Push_Object(L, script)
	vm.SetField(L, -2, "Script")
	if !vm.IsNoneOrNil(L, 3) {
		vm.PushNumber(L, vm.ArgNumber(L, 3))
		vm.SetField(L, -2, "Line")
	}
	ref := vm.RetainValue(L)
	plugin_pipe_send(studio, L, "OpenScript", ref)
}

plugin_select_ribbon_tool :: proc(service: ^Plugin, L: ^vm.State, enum_registry: ^enums.Registry) {
	if enum_registry == nil {
		return
	}
	item := enums.Arg_Item(L, 2, enum_registry, "RibbonTool")
	if item == nil {
		return
	}

	tool := ""
	switch item.name {
	case "Select":
		tool = "select"
	case "Scale":
		tool = "size"
	case "Rotate":
		tool = "rotate"
	case "Move", "Transform":
		tool = "position"
	}

	if tool == "" {
		return
	}

	if studio := plugin_studio(service); studio != nil {
		Plugin_Activate_Tool(studio, tool)
	}
}

Plugin_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^Plugin)object
	switch key {
	case "CallCount":
		vm.PushNumber(L, f64(service.call_count))
	case "Deactivation":
		if service.deactivation != nil {
			signals.Push(L, service.deactivation)
		} else {
			vm.PushNil(L)
		}
	case "Unloading":
		if service.unloading != nil {
			signals.Push(L, service.unloading)
		} else {
			vm.PushNil(L)
		}
	case "Add",
	     "Echo",
	     "MakeColor",
	     "GetService",
	     "Activate",
	     "IsActivated",
	     "Deactivate",
	     "CreateToolbar",
	     "CreatePluginAction",
	     "CreatePluginMenu",
	     "CreateDockWidgetPluginGui",
	     "CreateDockWidgetPluginGuiAsync",
	     "GetMouse",
	     "GetSetting",
	     "SetSetting",
	     "OpenScript",
	     "NewTheme",
	     "SelectRibbonTool":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

Plugin_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^Plugin)object
	switch method {
	case "Add":
		service.call_count += 1
		vm.PushNumber(L, vm.ArgNumber(L, 2) + vm.ArgNumber(L, 3))
		return 1, true
	case "Echo":
		service.call_count += 1
		vm.PushValue(L, 2)
		return 1, true
	case "MakeColor":
		service.call_count += 1
		if datatype_registry == nil {return 0, false}
		datatypes.Push_Color3(
			L,
			datatype_registry,
			datatypes.Color3 {
				f32(vm.ArgNumber(L, 2)),
				f32(vm.ArgNumber(L, 3)),
				f32(vm.ArgNumber(L, 4)),
			},
		)
		return 1, true
	case "GetService":
		classes.Push_Object(L, Service_Get_Service(&service.service, vm.ArgString(L, 2)))
		return 1, true
	case "Activate":
		service.active = true
		service.exclusive_mouse = !vm.IsNoneOrNil(L, 2) && vm.ArgBoolean(L, 2)
		return 0, true
	case "IsActivated":
		vm.PushBoolean(L, service.active)
		return 1, true
	case "Deactivate":
		if service.active {
			service.active = false
			if service.deactivation != nil {
				signals.Fire(L, service.deactivation, 0)
			}
		}
		return 0, true
	case "CreateToolbar":
		return plugin_create_toolbar(service, L)
	case "CreatePluginAction":
		return plugin_create_action(service, L)
	case "CreatePluginMenu":
		return plugin_create_menu(service, L)
	case "CreateDockWidgetPluginGui":
		return plugin_create_dock_widget(service, L, false)
	case "CreateDockWidgetPluginGuiAsync":
		return plugin_create_dock_widget(service, L, true)
	case "GetMouse":
		if service.data_model != nil && service.data_model.registry != nil {
			descriptor := Find_Service(service.data_model.registry, "UserInputService")
			if descriptor != nil && descriptor.object != nil {
				user_input := cast(^UserInputService)descriptor.object
				if user_input.mouse != nil {
					classes.Push_Object(L, &user_input.mouse.object)
					return 1, true
				}
			}
		}
		vm.PushNil(L)
		return 1, true
	case "GetSetting":
		plugin_get_setting(service, L, vm.ArgString(L, 2))
		return 1, true
	case "SetSetting":
		plugin_set_setting(service, L, vm.ArgString(L, 2))
		return 0, true
	case "OpenScript":
		plugin_open_script(service, L)
		return 0, true
	case "NewTheme":
		Plugin := cast(^Plugin)object
		Studio := cast(^Studio)Service_Get_Service(&Plugin.service, "Studio")

		new := Studio_Theme{}

		if vm.IsTable(L, 2) {
			_ = vm.GetField(L, 2, "Name")
			if vm.IsString(L, -1) {
				new.Name = vm.ArgString(L, -1)
			}
			vm.Pop(L)

			new.Accent = plugin_get_color3_arg("Accent", L, 2, datatype_registry)
			new.AccentSoft = plugin_get_color3_arg("AccentSoft", L, 2, datatype_registry)
			new.Border = plugin_get_color3_arg("Border", L, 2, datatype_registry)
			new.BorderStrong = plugin_get_color3_arg("BorderStrong", L, 2, datatype_registry)
			new.Canvas = plugin_get_color3_arg("Canvas", L, 2, datatype_registry)
			new.Error = plugin_get_color3_arg("Error", L, 2, datatype_registry)
			new.Focus = plugin_get_color3_arg("Focus", L, 2, datatype_registry)
			new.Hover = plugin_get_color3_arg("Hover", L, 2, datatype_registry)
			new.Input = plugin_get_color3_arg("Input", L, 2, datatype_registry)
			new.Muted = plugin_get_color3_arg("Muted", L, 2, datatype_registry)
			new.Panel = plugin_get_color3_arg("Panel", L, 2, datatype_registry)
			new.PanelRaised = plugin_get_color3_arg("PanelRaised", L, 2, datatype_registry)
			new.Surface = plugin_get_color3_arg("Surface", L, 2, datatype_registry)
			new.SurfaceAlt = plugin_get_color3_arg("SurfaceAlt", L, 2, datatype_registry)
			new.RowEven = plugin_get_color3_arg("RowEven", L, 2, datatype_registry)
			new.RowOdd = plugin_get_color3_arg("RowOdd", L, 2, datatype_registry)
			new.Selection = plugin_get_color3_arg("Selection", L, 2, datatype_registry)
			new.SelectionHover = plugin_get_color3_arg("SelectionHover", L, 2, datatype_registry)
			new.Subtext = plugin_get_color3_arg("Subtext", L, 2, datatype_registry)
			new.Success = plugin_get_color3_arg("Success", L, 2, datatype_registry)
			new.Text = plugin_get_color3_arg("Text", L, 2, datatype_registry)
			new.Warning = plugin_get_color3_arg("Warning", L, 2, datatype_registry)
		}

		Plugin_New_Theme(Studio, L, new, Plugin)
		Plugin_Set_Theme(Studio, L, new.Name, Plugin)
		free(&new)
		return 0, true
	case "SelectRibbonTool":
		plugin_select_ribbon_tool(service, L, enum_registry)
		return 0, true
	case "__SyncPluginToolbars":
		if studio := plugin_studio(service); studio != nil {
			for button in service.buttons {
				if button != nil && button.kind == .ToolbarButton {
					Plugin_Send_Button_Added(studio, L, button)
				}
			}
		}
		return 0, true
	case "__PluginActionClicked":
		id := i64(vm.ArgNumber(L, 2))
		if button := plugin_find_button(service, id); button != nil {
			plugin_emit_button_clicked(service, button, L)
		}
		return 0, true
	case "__PluginDockWidgetClosed":
		id := i64(vm.ArgNumber(L, 2))
		for dock in service.dock_widgets {
			if dock != nil && dock.id == id {
				dock.closed = true
				dock.frame.gui_object.visible = false
				break
			}
		}
		return 0, true
	}
	return 0, false
}

Plugin_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^Plugin)object
	if service == nil {
		classes.Object_Destroy(object)
		return
	}

	plugin_free_settings(service)
	for button in service.buttons {
		if button != nil {
			button.plugin = nil
			button.toolbar = nil
		}
	}
	for toolbar in service.toolbars {
		if toolbar != nil {
			toolbar.plugin = nil
			for child in toolbar.buttons {
				if child != nil {
					child.button.toolbar = nil
				}
			}
		}
	}
	for menu in service.menus {
		if menu != nil {
			menu.plugin = nil
		}
	}
	for dock in service.dock_widgets {
		if dock != nil {
			dock.plugin = nil
		}
	}
	delete(service.buttons)
	delete(service.toolbars)
	delete(service.menus)
	delete(service.dock_widgets)
	service.buttons = nil
	service.toolbars = nil
	service.menus = nil
	service.dock_widgets = nil
	service.deactivation = nil
	service.unloading = nil

	classes.Object_Destroy(object)
	free(service)
}

Register_Plugin_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Plugin_Class,
		Plugin_construct,
		Plugin_destroy,
		creatable = false,
		get = Plugin_get,
		namecall = Plugin_namecall,
	)

	classes.Register_Class(
		registry,
		&PluginToolbar_Class,
		plugin_toolbar_construct,
		plugin_toolbar_destroy,
		creatable = false,
		get = plugin_toolbar_get,
		namecall = plugin_toolbar_namecall,
	)

	classes.Register_Class(
		registry,
		&PluginToolbarButton_Class,
		plugin_toolbar_button_construct,
		plugin_toolbar_button_destroy,
		creatable = false,
		get = plugin_toolbar_button_get,
		set = plugin_toolbar_button_set,
		namecall = plugin_toolbar_button_namecall,
	)

	classes.Register_Class(
		registry,
		&PluginAction_Class,
		plugin_action_construct,
		plugin_action_destroy,
		creatable = false,
		get = plugin_action_get,
		set = plugin_action_set,
		namecall = plugin_action_namecall,
	)

	classes.Register_Class(
		registry,
		&PluginMenu_Class,
		plugin_menu_construct,
		plugin_menu_destroy,
		creatable = false,
		get = plugin_menu_get,
		namecall = plugin_menu_namecall,
	)

	classes.Register_Class(
		registry,
		&DockWidgetPluginGui_Class,
		plugin_dock_construct,
		plugin_dock_destroy,
		creatable = false,
		get = plugin_dock_get,
		set = plugin_dock_set,
		namecall = plugin_dock_namecall,
	)
}
