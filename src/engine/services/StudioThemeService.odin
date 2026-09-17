package services

// wire:service global="StudioThemeService"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import gui "../gui"
import "core:fmt"

THEME_BASE_COLOR :=
    Studio_Theme_Color{15, 15, 15, 255}

THEME_BACKGROUND_COLOR :=
    Studio_Theme_Color{35, 35, 35, 255}

THEME_ACCENT_COLOR :=
    Studio_Theme_Color{214, 133, 37, 255}

THEME_SECONDARY_COLOR :=
    Studio_Theme_Color{43, 43, 43, 255}

THEME_THIRD_COLOR :=
    Studio_Theme_Color{25, 25, 25, 255}


THEME_TEXT_COLOR :=
    Studio_Theme_Color{220, 220, 220, 255}

THEME_SECONDARY_TEXT_COLOR :=
    Studio_Theme_Color{180, 180, 180, 255}

THEME_DIMMED_TEXT_COLOR :=
    Studio_Theme_Color{170, 170, 170, 255}


THEME_INPUT_COLOR :=
    Studio_Theme_Color{38, 38, 38, 255}

THEME_INPUT_FOCUS_COLOR :=
    Studio_Theme_Color{51, 51, 64, 255}

THEME_INPUT_TEXT_COLOR :=
    Studio_Theme_Color{255, 255, 255, 255}

THEME_INPUT_PLACEHOLDER_COLOR :=
    Studio_Theme_Color{128, 128, 128, 255}


THEME_ROW_EVEN_COLOR :=
    Studio_Theme_Color{50, 50, 50, 255}

THEME_ROW_ODD_COLOR :=
    Studio_Theme_Color{45, 45, 45, 255}


THEME_CODE_EDITOR_BACKGROUND :=
    Studio_Theme_Color{0, 0, 0, 204}

Studio_Theme_Color :: struct {
	r: f64,
	g: f64,
	b: f64,
	a: f64,
}

theme_color :: proc(
	r, g, b: f64,
	a: f64 = 255,
) -> Studio_Theme_Color {
	return Studio_Theme_Color{
		r = r,
		g = g,
		b = b,
		a = a,
	}
}

StudioThemeService_Class := classes.Class_Info{
	name   = "StudioThemeService",
	parent = &Service_Class,
}

StudioThemeService :: struct {
	using service: Service,

	explorer_hidden: bool,

	selected_theme_ref: i32,
	theme_object_ref:   i32,

	theme_changed: ^signals.Signal,

	padding:        f64,
	header_height:  f64,
	bottom_padding: f64,
	show_output:    bool,
	layout_width:  f32,
	layout_height: f32,
}

studio_theme_color :: proc(
	L: ^vm.State,
	r, g, b: f64,
	a: f64 = 255,
) {
	vm.NewTable(L, 0, 4)

	vm.PushNumber(L, r / 255.0)
	vm.SetField(L, -2, "R")

	vm.PushNumber(L, g / 255.0)
	vm.SetField(L, -2, "G")

	vm.PushNumber(L, b / 255.0)
	vm.SetField(L, -2, "B")

	vm.PushNumber(L, a / 255.0)
	vm.SetField(L, -2, "A")
}

StudioThemeService_Update_Layout :: proc(
	registry: ^Registry,
	L: ^vm.State,
	datatype_registry: ^datatypes.Registry,
	width, height: i32,
) {
	if registry == nil ||
	   L == nil ||
	   datatype_registry == nil ||
	   width <= 0 ||
	   height <= 0 {
		return
	}

	descriptor := Find_Service(
		registry,
		"StudioThemeService",
	)

	if descriptor == nil || descriptor.object == nil {
		return
	}

	service := cast(^StudioThemeService)descriptor.object

	size_changed :=
		service.layout_width  != f32(width) ||
		service.layout_height != f32(height)

	service.layout_width = f32(width)
	service.layout_height = f32(height)

	studio_theme_ensure_initialized(
		L,
		service,
		datatype_registry,
	)

	vm.PushRegistryReference(
		L,
		service.selected_theme_ref,
	)

	studio_theme_set_coordinates(
		L,
		service,
		datatype_registry,
	)

	if size_changed {
		fmt.printf(
			"[StudioTheme Resize] %gx%g -> %dx%d\n",
			service.layout_width,
			service.layout_height,
			width,
			height,
		)

		studio_theme_fire_changed(
			L,
			service,
		)
	}

	vm.Pop(L)
}

studio_theme_set_color :: proc(
	L: ^vm.State,
	name: string,
	r, g, b: f64,
	a: f64 = 255,
) {
	studio_theme_color(L, r, g, b, a)
	vm.SetField(L, -2, name)
}


studio_theme_push_udim2 :: proc(
	L: ^vm.State,
	registry: ^datatypes.Registry,
	x_scale, x_offset,
	y_scale, y_offset: f32,
) {
	datatypes.Push_UDim2(
		L,
		registry,
		datatypes.UDim2_New(
			x_scale,
			x_offset,
			y_scale,
			y_offset,
		),
	)
}


studio_theme_push_vector2 :: proc(
	L: ^vm.State,
	registry: ^datatypes.Registry,
	x, y: f32,
) {
	datatypes.Push_Vector2(
		L,
		registry,
		datatypes.Vector2{x, y},
	)
}

studio_theme_set_coordinate :: proc(
	L: ^vm.State,
	registry: ^datatypes.Registry,
	name: string,
	coordinate: gui.Layout_Coordinate,
) {
	vm.NewTable(L, 0, 2)

	datatypes.Push_UDim2(
		L,
		registry,
		coordinate.Size,
	)
	vm.SetField(L, -2, "Size")

	datatypes.Push_UDim2(
		L,
		registry,
		coordinate.Position,
	)
	vm.SetField(L, -2, "Position")

	vm.SetField(L, -2, name)
}

studio_theme_set_coordinates :: proc(
	L: ^vm.State,
	service: ^StudioThemeService,
	registry: ^datatypes.Registry,
) {
	if registry == nil {
		return
	}

	config := gui.Editor_Layout_Default_Config()

	config.P = f32(service.padding)
	config.TopH = f32(service.header_height)
	config.show_output = service.show_output

	coordinates := gui.Editor_Layout_Compute(
		&config,
		service.layout_width,
		service.layout_height,
	)

	studio_theme_set_coordinate(
		L,
		registry,
		"TopbarCoordinates",
		coordinates.TopbarCoordinates,
	)

	studio_theme_set_coordinate(
		L,
		registry,
		"ViewportCoordinates",
		coordinates.ViewportCoordinates,
	)

	studio_theme_set_coordinate(
		L,
		registry,
		"CodeEditorCoordinates",
		coordinates.CodeEditorCoordinates,
	)

	studio_theme_set_coordinate(
		L,
		registry,
		"OutputCoordinates",
		coordinates.OutputCoordinates,
	)

	studio_theme_set_coordinate(
		L,
		registry,
		"ExplorerCoordinates",
		coordinates.ExplorerCoordinates,
	)

	studio_theme_set_coordinate(
		L,
		registry,
		"InspectorCoordinates",
		coordinates.InspectorCoordinates,
	)
}


// -----------------------------------------------------------------------------
// LayoutConfig
// -----------------------------------------------------------------------------

studio_theme_push_layout_config :: proc(
	L: ^vm.State,
	service: ^StudioThemeService,
) {
	vm.NewTable(L, 0, 12)

	vm.PushNumber(L, service.padding)
	vm.SetField(L, -2, "P")

	vm.PushNumber(L, service.header_height)
	vm.SetField(L, -2, "TopH")

	vm.PushNumber(L, service.bottom_padding)
	vm.SetField(L, -2, "BottomPad")


	// Topbar
	vm.NewTable(L, 0, 1)
	vm.PushNumber(L, 0)
	vm.SetField(L, -2, "flexGrow")
	vm.SetField(L, -2, "Topbar")


	// Content
	vm.NewTable(L, 0, 1)
	vm.PushNumber(L, 1)
	vm.SetField(L, -2, "flexGrow")
	vm.SetField(L, -2, "Content")


	// Left
	vm.NewTable(L, 0, 2)

	vm.PushNumber(L, 0.78)
	vm.SetField(L, -2, "flexGrow")

	vm.PushNumber(L, 0)
	vm.SetField(L, -2, "minWidth")

	vm.SetField(L, -2, "Left")


	// Right
	vm.NewTable(L, 0, 2)

	vm.PushNumber(L, 0.22)
	vm.SetField(L, -2, "flexGrow")

	vm.PushNumber(L, 0)
	vm.SetField(L, -2, "minWidth")

	vm.SetField(L, -2, "Right")


	// Viewport
	vm.NewTable(L, 0, 2)

	vm.PushNumber(L, 0.7)
	vm.SetField(L, -2, "flexGrow")

	vm.PushNumber(L, 1)
	vm.SetField(L, -2, "layoutOrder")

	vm.SetField(L, -2, "Viewport")


	// CodeEditor
	vm.NewTable(L, 0, 1)

	vm.PushString(L, "Viewport")
	vm.SetField(L, -2, "target")

	vm.SetField(L, -2, "CodeEditor")


	// Output
	vm.NewTable(L, 0, 2)

	vm.PushNumber(L, 0.3)
	vm.SetField(L, -2, "flexGrow")

	vm.PushNumber(L, 2)
	vm.SetField(L, -2, "layoutOrder")

	vm.SetField(L, -2, "Output")


	// Explorer
	vm.NewTable(L, 0, 2)

	vm.PushNumber(L, 0.5)
	vm.SetField(L, -2, "flexGrow")

	vm.PushNumber(L, 1)
	vm.SetField(L, -2, "layoutOrder")

	vm.SetField(L, -2, "Explorer")


	// Inspector
	vm.NewTable(L, 0, 2)

	vm.PushNumber(L, 0.5)
	vm.SetField(L, -2, "flexGrow")

	vm.PushNumber(L, 2)
	vm.SetField(L, -2, "layoutOrder")

	vm.SetField(L, -2, "Inspector")
}


// -----------------------------------------------------------------------------
// Window layouts
// -----------------------------------------------------------------------------

studio_theme_push_padded_window_config :: proc(
	L: ^vm.State,
	registry: ^datatypes.Registry,
) {
	vm.NewTable(L, 0, 6)


	// Explorer
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 1, -20, 0, 40)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 1, 0)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(L, registry, 0, 400, 0.38, 0)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "Explorer")


	// GameSettings
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 0.5, 0, 0.5, 0)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 0.5, 0.5)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(L, registry, 0.5, 0, 0.7, 0)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "GameSettings")


	// Toolbox
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 0.5, 0, 0.5, 0)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 0.5, 0.5)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(L, registry, 0.6, 0, 0.7, 0)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "Toolbox")


	// Inspector
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 1, -20, 0.44, 0)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 1, 0)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(L, registry, 0, 400, 0.55, 0)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "Inspector")


	// Output
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 0, 20, 0.99, 0)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 0, 1)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(L, registry, 1, -450, 0, 200)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "Output")


	// Toolbar
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 0, 0, 0, 0)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 0, 0)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(L, registry, 1, 0, 0, 170)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "Toolbar")


	// CodeEditor
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 0, 20, 0, 40)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 0, 0)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(L, registry, 0, 800, 0, 600)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "CodeEditor")
}


studio_theme_push_boxed_window_config :: proc(
	L: ^vm.State,
	registry: ^datatypes.Registry,
) {
	X_SIZE :: f32(350)

	vm.NewTable(L, 0, 7)


	// Toolbar
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 0, 0, 0, 0)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 0, 0)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(L, registry, 1, 0, 0, 200)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "Toolbar")


	// Explorer
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 1, 0, 0, 30)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 1, 0)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(
		L,
		registry,
		0,
		X_SIZE,
		0.5,
		-50,
	)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "Explorer")


	// Inspector
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 1, 0, 0.5, -20)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 1, 0)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(
		L,
		registry,
		0,
		X_SIZE,
		0.5,
		20,
	)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "Inspector")


	// CodeEditor
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 0, X_SIZE, 0, 0)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 0, 0)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(
		L,
		registry,
		1,
		-X_SIZE*2,
		1,
		-200,
	)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "CodeEditor")


	// Output
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 0, 0, 1, 0)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 0, 1)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(
		L,
		registry,
		1,
		-X_SIZE,
		0,
		200,
	)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "Output")


	// GameSettings
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 0.5, 0, 0.5, 0)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 0.5, 0.5)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(L, registry, 0.5, 0, 0.7, 0)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "GameSettings")


	// Toolbox
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 0.5, 0, 0.5, 0)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 0.5, 0.5)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(L, registry, 0.6, 0, 0.7, 0)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "Toolbox")


	// FileBrowser
	vm.NewTable(L, 0, 3)

	studio_theme_push_udim2(L, registry, 0, 0, 1, 0)
	vm.SetField(L, -2, "position")

	studio_theme_push_vector2(L, registry, 0, 1)
	vm.SetField(L, -2, "anchorPoint")

	studio_theme_push_udim2(
		L,
		registry,
		0,
		X_SIZE,
		1,
		-20,
	)
	vm.SetField(L, -2, "size")

	vm.SetField(L, -2, "FileBrowser")
}


// -----------------------------------------------------------------------------
// ThemeObject compatibility object
// -----------------------------------------------------------------------------
//
// The old Luau implementation creates Instance.new("StudioTheme").
// That Instance has not been ported to the current Odin class registry yet,
// so for now this is a table of Color3 values with the same color names.
//
// Once StudioTheme.odin exists this function can be replaced by an actual
// classes.Push_New(..., "StudioTheme") call.
//

studio_theme_push_theme_object :: proc(
	L: ^vm.State,
	registry: ^datatypes.Registry,
) {
	vm.NewTable(L, 0, 7)

	datatypes.Push_Color3(
		L,
		registry,
		datatypes.FromRGB(35, 35, 35),
	)
	vm.SetField(L, -2, "MainBackground")

	datatypes.Push_Color3(
		L,
		registry,
		datatypes.FromRGB(25, 25, 25),
	)
	vm.SetField(L, -2, "Titlebar")

	datatypes.Push_Color3(
		L,
		registry,
		datatypes.FromRGB(43, 43, 43),
	)
	vm.SetField(L, -2, "Button")

	datatypes.Push_Color3(
		L,
		registry,
		datatypes.FromRGB(214, 133, 37),
	)
	vm.SetField(L, -2, "MainButton")

	datatypes.Push_Color3(
		L,
		registry,
		datatypes.FromRGB(220, 220, 220),
	)
	vm.SetField(L, -2, "MainText")

	datatypes.Push_Color3(
		L,
		registry,
		datatypes.FromRGB(180, 180, 180),
	)
	vm.SetField(L, -2, "SubText")

	datatypes.Push_Color3(
		L,
		registry,
		datatypes.FromRGB(38, 38, 38),
	)
	vm.SetField(L, -2, "InputFieldBackground")
}


// -----------------------------------------------------------------------------
// Default theme
// -----------------------------------------------------------------------------

studio_theme_set_color_value :: proc(
	L: ^vm.State,
	name: string,
	color: Studio_Theme_Color,
) {
	studio_theme_set_color(
		L,
		name,
		color.r,
		color.g,
		color.b,
		color.a,
	)
}

studio_theme_push_default_theme :: proc(
	L: ^vm.State,
	service: ^StudioThemeService,
	registry: ^datatypes.Registry,
) {
	vm.NewTable(L, 0, 32)

	studio_theme_set_color_value(
		L,
		"BaseColor",
		THEME_BASE_COLOR,
	)

	studio_theme_set_color_value(
		L,
		"BgColor",
		THEME_BACKGROUND_COLOR,
	)

	studio_theme_set_color_value(
		L,
		"AccentColor",
		THEME_ACCENT_COLOR,
	)

	studio_theme_set_color_value(
		L,
		"SecondaryColor",
		THEME_SECONDARY_COLOR,
	)

	studio_theme_set_color_value(
		L,
		"ThirdColor",
		THEME_THIRD_COLOR,
	)

	studio_theme_set_color_value(
		L,
		"SecondaryTextColor",
		THEME_SECONDARY_TEXT_COLOR,
	)

	studio_theme_set_color_value(
		L,
		"TextColor",
		THEME_TEXT_COLOR,
	)

	studio_theme_set_color_value(
		L,
		"TextColorDimmed",
		THEME_DIMMED_TEXT_COLOR,
	)

	studio_theme_set_color_value(
		L,
		"InputColor",
		THEME_INPUT_COLOR,
	)

	studio_theme_set_color_value(
		L,
		"InputFocusColor",
		THEME_INPUT_FOCUS_COLOR,
	)

	studio_theme_set_color_value(
		L,
		"InputTextColor",
		THEME_INPUT_TEXT_COLOR,
	)

	studio_theme_set_color_value(
		L,
		"InputPlaceholderColor",
		THEME_INPUT_PLACEHOLDER_COLOR,
	)

	studio_theme_set_color_value(
		L,
		"AlternatingColor1",
		THEME_ROW_EVEN_COLOR,
	)

	studio_theme_set_color_value(
		L,
		"AlternatingColor2",
		THEME_ROW_ODD_COLOR,
	)

	studio_theme_set_color_value(
		L,
		"CodeEditorBgColor",
		THEME_CODE_EDITOR_BACKGROUND,
	)


	vm.PushNumber(L, 6)
	vm.SetField(L, -2, "CornerRadius")

	vm.PushNumber(L, 4)
	vm.SetField(L, -2, "ButtonCornerRadius")

	vm.PushString(
		L,
		"./src/engine/assets/fonts/Montserrat-Regular.ttf",
	)
	vm.SetField(L, -2, "Font")

	vm.PushString(
		L,
		"./src/engine/assets/fonts/Montserrat-Regular.ttf",
	)
	vm.SetField(L, -2, "FontBold")

	studio_theme_set_coordinates(
		L,
		service,
		registry,
	)

	studio_theme_push_layout_config(
		L,
		service,
	)
	vm.SetField(
		L,
		-2,
		"LayoutConfig",
	)

	studio_theme_push_boxed_window_config(
		L,
		registry,
	)
	vm.SetField(
		L,
		-2,
		"WindowConfig",
	)
}


// -----------------------------------------------------------------------------
// Lifetime helpers
// -----------------------------------------------------------------------------

studio_theme_release_ref :: proc(
	L: ^vm.State,
	ref: ^i32,
) {
	if ref == nil || ref^ <= 0 {
		return
	}

	vm.ReleaseValue(L, ref^)
	ref^ = -1
}


studio_theme_ensure_initialized :: proc(
	L: ^vm.State,
	service: ^StudioThemeService,
	registry: ^datatypes.Registry,
) {
	if service.selected_theme_ref > 0 {
		return
	}

	studio_theme_push_default_theme(
		L,
		service,
		registry,
	)

	service.selected_theme_ref = vm.RetainValue(L)
	vm.Pop(L)

	studio_theme_push_theme_object(
		L,
		registry,
	)

	service.theme_object_ref = vm.RetainValue(L)
	vm.Pop(L)
}


studio_theme_reset_default :: proc(
	L: ^vm.State,
	service: ^StudioThemeService,
	registry: ^datatypes.Registry,
) {
	studio_theme_release_ref(
		L,
		&service.selected_theme_ref,
	)

	studio_theme_release_ref(
		L,
		&service.theme_object_ref,
	)

	studio_theme_push_default_theme(
		L,
		service,
		registry,
	)

	service.selected_theme_ref = vm.RetainValue(L)
	vm.Pop(L)

	studio_theme_push_theme_object(
		L,
		registry,
	)

	service.theme_object_ref = vm.RetainValue(L)
	vm.Pop(L)
}


studio_theme_set_selected :: proc(
	L: ^vm.State,
	service: ^StudioThemeService,
	value_index: int,
) -> bool {
	if !vm.IsTable(L, value_index) {
		_ = vm.RaiseError(
			L,
			"StudioThemeService theme must be a table",
		)
		return false
	}

	studio_theme_release_ref(
		L,
		&service.selected_theme_ref,
	)

	vm.PushValue(L, value_index)
	service.selected_theme_ref = vm.RetainValue(L)
	vm.Pop(L)

	return true
}


studio_theme_set_theme_object :: proc(
	L: ^vm.State,
	service: ^StudioThemeService,
	value_index: int,
) {
	studio_theme_release_ref(
		L,
		&service.theme_object_ref,
	)

	vm.PushValue(L, value_index)
	service.theme_object_ref = vm.RetainValue(L)
	vm.Pop(L)
}


studio_theme_fire_changed :: proc(
	L: ^vm.State,
	service: ^StudioThemeService,
) {
	if service.theme_changed == nil {
		return
	}

	if service.theme_object_ref > 0 {
		vm.PushRegistryReference(
			L,
			service.theme_object_ref,
		)
	} else {
		vm.PushNil(L)
	}

	signals.Fire(
		L,
		service.theme_changed,
		1,
	)

	vm.Pop(L)
}


// -----------------------------------------------------------------------------
// Property API
// -----------------------------------------------------------------------------

studio_theme_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^StudioThemeService)object

	switch key {
	case "ExplorerHidden":
		vm.PushBoolean(
			L,
			service.explorer_hidden,
		)

	case "_Intents":
		if enum_registry == nil {
			vm.PushNil(L)
			return true
		}

		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"PluginIntents",
			i64(enums.PluginIntents.UI),
		)

	case "ThemeChanged":
		signals.Push(
			L,
			service.theme_changed,
		)

	case "SelectedTheme":
		studio_theme_ensure_initialized(
			L,
			service,
			datatype_registry,
		)

		vm.PushRegistryReference(
			L,
			service.selected_theme_ref,
		)

	case "ThemeObject":
		studio_theme_ensure_initialized(
			L,
			service,
			datatype_registry,
		)

		if service.theme_object_ref > 0 {
			vm.PushRegistryReference(
				L,
				service.theme_object_ref,
			)
		} else {
			vm.PushNil(L)
		}

	case "InitRenderer",
	     "GetTheme",
	     "SetTheme",
	     "ChangeLayoutSettings",
	     "MakeUIPadded",
	     "MakeUIBoxed",
	     "ExportThemeAsJson",
	     "LoadThemeJson":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}


studio_theme_service_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	service := cast(^StudioThemeService)object

	switch key {
	case "ExplorerHidden":
		service.explorer_hidden =
			vm.ArgBoolean(L, value_index)

	case "SelectedTheme":
		_ = studio_theme_set_selected(
			L,
			service,
			value_index,
		)

	case "ThemeObject":
		studio_theme_set_theme_object(
			L,
			service,
			value_index,
		)

	case:
		return false
	}

	return true
}


// -----------------------------------------------------------------------------
// Methods
// -----------------------------------------------------------------------------

studio_theme_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	service := cast(^StudioThemeService)object

	switch method {

	// -------------------------------------------------------------------------
	// InitRenderer
	//
	// The Luau implementation creates all state here. Native services are
	// already engine-owned, so this resets the native service to the exact
	// default theme/layout instead.
	// -------------------------------------------------------------------------

	case "InitRenderer":
		service.padding = 4
		service.header_height = 33
		service.bottom_padding = 12
		service.show_output = true

		studio_theme_reset_default(
			L,
			service,
			datatype_registry,
		)

		studio_theme_fire_changed(
			L,
			service,
		)

		return 0, true


	// -------------------------------------------------------------------------
	// GetTheme
	// -------------------------------------------------------------------------

	case "GetTheme":
		studio_theme_ensure_initialized(
			L,
			service,
			datatype_registry,
		)

		vm.PushRegistryReference(
			L,
			service.selected_theme_ref,
		)

		return 1, true


	// -------------------------------------------------------------------------
	// SetTheme(theme, robloxTheme?)
	// -------------------------------------------------------------------------

	case "SetTheme":
		studio_theme_ensure_initialized(
			L,
			service,
			datatype_registry,
		)

		if !studio_theme_set_selected(
			L,
			service,
			2,
		) {
			return 0, true
		}

		if !vm.IsNoneOrNil(L, 3) {
			studio_theme_set_theme_object(
				L,
				service,
				3,
			)
		}

		studio_theme_fire_changed(
			L,
			service,
		)

		return 0, true


	// -------------------------------------------------------------------------
	// ChangeLayoutSettings(padding, headerHeight, bottomPadding)
	// -------------------------------------------------------------------------

	case "ChangeLayoutSettings":
		service.padding = vm.ArgOptionalNumber(
			L,
			2,
			service.padding,
		)

		service.header_height = vm.ArgOptionalNumber(
			L,
			3,
			service.header_height,
		)

		service.bottom_padding = vm.ArgOptionalNumber(
			L,
			4,
			service.bottom_padding,
		)

		studio_theme_ensure_initialized(
			L,
			service,
			datatype_registry,
		)

		vm.PushRegistryReference(
			L,
			service.selected_theme_ref,
		)

		studio_theme_set_coordinates(
			L,
			service,
			datatype_registry,
		)

		if vm.GetField(L, -1, "LayoutConfig") == .Table {
			vm.PushNumber(L, service.padding)
			vm.SetField(L, -2, "P")

			vm.PushNumber(L, service.header_height)
			vm.SetField(L, -2, "TopH")

			vm.PushNumber(L, service.bottom_padding)
			vm.SetField(L, -2, "BottomPad")
		}

		vm.Pop(L) // LayoutConfig / nil
		vm.Pop(L) // SelectedTheme

		return 0, true


	// -------------------------------------------------------------------------
	// MakeUIPadded
	// -------------------------------------------------------------------------

	case "MakeUIPadded":
		studio_theme_ensure_initialized(
			L,
			service,
			datatype_registry,
		)

		vm.PushRegistryReference(
			L,
			service.selected_theme_ref,
		)

		studio_theme_push_padded_window_config(
			L,
			datatype_registry,
		)

		vm.SetField(
			L,
			-2,
			"WindowConfig",
		)

		vm.Pop(L)

		return 0, true

	case "MakeUIBoxed":
		studio_theme_ensure_initialized(
			L,
			service,
			datatype_registry,
		)

		vm.PushRegistryReference(
			L,
			service.selected_theme_ref,
		)

		studio_theme_push_boxed_window_config(
			L,
			datatype_registry,
		)

		vm.SetField(
			L,
			-2,
			"WindowConfig",
		)

		vm.Pop(L)

		return 0, true

	case "ExportThemeAsJson":
		return vm.RaiseError(
			L,
			"ExportThemeAsJson requires the native JSON/filesystem bridge",
		), true


	case "LoadThemeJson":
		return vm.RaiseError(
			L,
			"LoadThemeJson requires the native JSON/filesystem bridge",
		), true
	}

	return 0, false
}

StudioThemeService_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(StudioThemeService)

	service.service = Service_Init(
		&StudioThemeService_Class,
		"StudioThemeService",
		data_model,
	)

	service.explorer_hidden = true

	service.selected_theme_ref = -1
	service.theme_object_ref = -1

	service.padding = 4
	service.header_height = 33
	service.bottom_padding = 12
	service.show_output = true

	service.layout_width = 800
	service.layout_height = 600
	service.show_output = true

	model := cast(^DataModel)data_model

	if model != nil &&
	   model.registry != nil &&
	   model.registry.signal_registry != nil {
		service.theme_changed = signals.Create(
			model.registry.signal_registry,
		)
	}

	return &service.object
}


StudioThemeService_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	service := cast(^StudioThemeService)object

	if service.data_model != nil &&
	   service.data_model.registry != nil &&
	   service.data_model.registry.vm_state != nil &&
	   service.data_model.registry.vm_state.L != nil {

		L := service.data_model.registry.vm_state.L

		studio_theme_release_ref(
			L,
			&service.selected_theme_ref,
		)

		studio_theme_release_ref(
			L,
			&service.theme_object_ref,
		)
	}

	service.theme_changed = nil

	classes.Object_Destroy(object)
	free(service)
}

Register_StudioThemeService_Class :: proc(
	registry: ^classes.Registry,
) {
	classes.Register_Class(
		registry,
		&StudioThemeService_Class,
		StudioThemeService_construct,
		StudioThemeService_destroy,

		creatable = false,

		get      = studio_theme_service_get,
		set      = studio_theme_service_set,
		namecall = studio_theme_service_namecall,
	)
}
