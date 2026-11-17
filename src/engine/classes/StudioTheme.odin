package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:strings"

StudioTheme_Class := Class_Info {
	name   = "StudioTheme",
	parent = &Instance_Class,
}

StudioTheme :: struct {
	using object: Object,
	palette_ref:  ^i32,
}

StudioTheme_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	theme := new(StudioTheme)
	theme.object = Object_Init(&StudioTheme_Class, "Dark")
	theme.archivable = false
	theme.can_replicate = false
	return &theme.object
}

StudioTheme_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	theme := cast(^StudioTheme)object
	theme.palette_ref = nil
	Object_Destroy(object)
	free(theme)
}

StudioTheme_Set_Palette :: proc(theme: ^StudioTheme, palette_ref: ^i32) {
	if theme == nil {return}
	theme.palette_ref = palette_ref
}

StudioTheme_Set_Kind :: proc(theme: ^StudioTheme, name: string) {
	if theme == nil {return}
	if name == "Light" {
		Set_Name(&theme.object, "Light")
	} else {
		Set_Name(&theme.object, "Dark")
	}
}

studio_theme_enum_name :: proc(L: ^vm.State, index: int) -> (string, bool) {
	if vm.IsNoneOrNil(L, index) {return "", false}
	kind := vm.GetField(L, index, "Name")
	if kind != .String {
		vm.Pop(L)
		return "", false
	}
	name := strings.clone(vm.ArgString(L, -1))
	vm.Pop(L)
	return name, true
}

// Map Roblox StudioStyleGuideColor to the existing Kinemium theme tokens.
// Unknown UI roles use MainBackground, rather than returning nil or crashing.
studio_theme_palette_token :: proc(role: string) -> string {
	switch role {
	case "MainBackground", "MainSection", "ScrollBarBackground", "TabBar", "Menu", "RibbonTab":
		return "BgColor"
	case "Titlebar", "Tab", "Separator", "Border", "ButtonBorder", "InputFieldBorder":
		return "ThirdColor"
	case "Button", "Dropdown", "Tooltip", "Notification", "ScrollBar", "DialogMainButton":
		return "SecondaryColor"
	case "MainButton", "ActionBar", "LinkText", "FilterButtonChecked", "WarningText":
		return "AccentColor"
	case "MainText", "BrightText", "ButtonText", "InputFieldText", "TabText", "TooltipText":
		return "TextColor"
	case "SubText", "DimmedText", "DisabledText", "SubTextColor", "PlaceholderText",
	     "InfoText", "CheckedFieldBorder", "CheckedFieldIndicator":
		return "SecondaryTextColor"
	case "InputField", "InputFieldBackground", "DropdownText":
		return "InputColor"
	case "Selected", "Selection", "SelectedText", "SelectedBackground":
		return "InputFocusColor"
	case "ScriptBackground", "ScriptEditorBackground":
		return "CodeEditorBgColor"
	}
	return "BgColor"
}

studio_theme_table_number :: proc(L: ^vm.State, field: string) -> (f32, bool) {
	kind := vm.GetField(L, -1, field)
	if kind != .Number {
		vm.Pop(L)
		return 0, false
	}
	n := f32(vm.ArgNumber(L, -1))
	vm.Pop(L)
	return n, true
}

studio_theme_color_from_palette :: proc(
	L: ^vm.State,
	palette_ref: i32,
	token: string,
) -> (
	datatypes.Color3,
	bool,
) {
	if palette_ref <= 0 {return {}, false}

	vm.PushRegistryReference(L, palette_ref)
	if vm.GetField(L, -1, token) != .Table {
		vm.Pop(L)
		vm.Pop(L)
		return {}, false
	}

	r, rok := studio_theme_table_number(L, "R")
	g, gok := studio_theme_table_number(L, "G")
	b, bok := studio_theme_table_number(L, "B")
	vm.Pop(L) // color table
	vm.Pop(L) // selected palette

	if !rok || !gok || !bok {return {}, false}
	return datatypes.Color3{r, g, b}, true
}

// Fallbacks are derived from the defaults in StudioThemeService. These are
// approximate Roblox-style slots, not a full 130-entry Studio color database.
studio_theme_default_color :: proc(token: string, is_light: bool) -> datatypes.Color3 {
	if is_light {
		switch token {
		case "BgColor":
			return datatypes.FromRGB(242, 242, 242)
		case "BaseColor":
			return datatypes.FromRGB(255, 255, 255)
		case "ThirdColor":
			return datatypes.FromRGB(225, 225, 225)
		case "SecondaryColor":
			return datatypes.FromRGB(235, 235, 235)
		case "TextColor":
			return datatypes.FromRGB(35, 35, 35)
		case "SecondaryTextColor":
			return datatypes.FromRGB(90, 90, 90)
		case "InputColor":
			return datatypes.FromRGB(255, 255, 255)
		case "InputFocusColor":
			return datatypes.FromRGB(215, 230, 250)
		case "CodeEditorBgColor":
			return datatypes.FromRGB(255, 255, 255)
		case "AccentColor":
			return datatypes.FromRGB(214, 133, 37)
		}
	}
	switch token {
	case "BaseColor":
		return datatypes.FromRGB(15, 15, 15)
	case "ThirdColor":
		return datatypes.FromRGB(25, 25, 25)
	case "SecondaryColor":
		return datatypes.FromRGB(43, 43, 43)
	case "TextColor":
		return datatypes.FromRGB(220, 220, 220)
	case "SecondaryTextColor":
		return datatypes.FromRGB(180, 180, 180)
	case "InputColor":
		return datatypes.FromRGB(38, 38, 38)
	case "InputFocusColor":
		return datatypes.FromRGB(51, 51, 64)
	case "CodeEditorBgColor":
		return datatypes.FromRGB(0, 0, 0)
	case "AccentColor":
		return datatypes.FromRGB(214, 133, 37)
	}
	return datatypes.FromRGB(35, 35, 35)
}

studio_theme_modify_channel :: proc(c: f32, factor: f32) -> f32 {
	value := c * factor
	if value < 0 {return 0}
	if value > 1 {return 1}
	return value
}

studio_theme_apply_modifier :: proc(
	color: datatypes.Color3,
	modifier: string,
) -> datatypes.Color3 {
	factor: f32 = 1
	switch modifier {
	case "Hover":
		factor = 1.12
	case "Pressed":
		factor = 0.85
	case "Selected":
		factor = 1.18
	case "Disabled":
		factor = 0.55
	}
	return datatypes.Color3 {
		studio_theme_modify_channel(color.R, factor),
		studio_theme_modify_channel(color.G, factor),
		studio_theme_modify_channel(color.B, factor),
	}
}

StudioTheme_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "GetColor":
		vm.PushUserdataMethod(L, key)
		return true
	case "Name":
		vm.PushString(L, object.name)
		return true
	}
	return false
}

StudioTheme_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "GetColor" {return 0, false}
	if datatype_registry == nil {
		return vm.RaiseError(L, "StudioTheme:GetColor: datatype registry unavailable"), true
	}

	role, role_ok := studio_theme_enum_name(L, 2)
	if !role_ok {
		return vm.RaiseError(L, "StudioTheme:GetColor expects Enum.StudioStyleGuideColor"), true
	}
	defer delete(role)

	modifier := "Default"
	owned_modifier: string
	if !vm.IsNoneOrNil(L, 3) {
		next, modifier_ok := studio_theme_enum_name(L, 3)
		if !modifier_ok {
			return vm.RaiseError(
					L,
					"StudioTheme:GetColor modifier must be Enum.StudioStyleGuideModifier",
				),
				true
		}
		owned_modifier = next
		modifier = owned_modifier
	}
	defer delete(owned_modifier)

	theme := cast(^StudioTheme)object
	token := studio_theme_palette_token(role)
	color: datatypes.Color3
	found := false
	if theme.palette_ref != nil {
		color, found = studio_theme_color_from_palette(L, theme.palette_ref^, token)
	}
	if !found {color = studio_theme_default_color(token, theme.name == "Light")}
	color = studio_theme_apply_modifier(color, modifier)

	datatypes.Push_Color3(L, datatype_registry, color)
	return 1, true
}

Register_StudioTheme :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&StudioTheme_Class,
		StudioTheme_construct,
		StudioTheme_destroy,
		creatable = false,
		get = StudioTheme_get,
		namecall = StudioTheme_namecall,
		properties = []string{"Name"},
		methods = []string{"GetColor"},
	)
}
