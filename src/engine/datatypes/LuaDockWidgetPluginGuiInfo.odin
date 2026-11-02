package datatypes

import engine_enums "../enum"
import vm "../vm"
import "base:runtime"
import "core:fmt"

push_dock_widget_plugin_gui_info :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
	value: DockWidgetPluginGuiInfo,
) {
	push_value(L, binding, value)
}

Push_DockWidgetPluginGuiInfo :: proc(
	L: ^vm.State,
	registry: ^Registry,
	value: DockWidgetPluginGuiInfo,
) {
	push_dock_widget_plugin_gui_info(L, &registry.dock_widget_plugin_gui_info, value)
}

Arg_DockWidgetPluginGuiInfo :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> DockWidgetPluginGuiInfo {
	if !vm.IsUserdataType(L, index, &registry.dock_widget_plugin_gui_info) {
		_ = vm.RaiseError(L, "expected DockWidgetPluginGuiInfo")
		return {}
	}
	return (cast(^DockWidgetPluginGuiInfo)vm.UserdataValue(L, index))^
}

dock_widget_plugin_gui_info_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)

	result := DockWidgetPluginGuiInfo {
		initial_dock_state       = .Top,
		initial_enabled          = true,
		override_enabled_restore = false,
	}

	top := vm.StackTop(L)

	if top >= 1 && !vm.IsNil(L, 1) {
		if registry == nil || registry.enums == nil {
			return vm.RaiseError(L, "DockWidgetPluginGuiInfo enum registry is unavailable")
		}
		item := engine_enums.Arg_Item(L, 1, registry.enums, "InitialDockState")
		if item == nil {
			return 0
		}
		result.initial_dock_state = cast(engine_enums.InitialDockState)item.value
	}

	if top >= 2 && !vm.IsNil(L, 2) {
		result.initial_enabled = vm.ArgBoolean(L, 2)
	}

	if top >= 3 && !vm.IsNil(L, 3) {
		result.override_enabled_restore = vm.ArgBoolean(L, 3)
	}

	if top >= 4 {
		result.floating_x_size = i32(vm.ArgNumber(L, 4))
	}

	if top >= 5 {
		result.floating_y_size = i32(vm.ArgNumber(L, 5))
	}

	if top >= 6 {
		result.min_width = i32(vm.ArgNumber(L, 6))
	}

	if top >= 7 {
		result.min_height = i32(vm.ArgNumber(L, 7))
	}

	push_dock_widget_plugin_gui_info(L, binding, result)
	return 1
}

dock_widget_plugin_gui_info_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	info := cast(^DockWidgetPluginGuiInfo)value
	registry := registry_from_binding(cast(^vm.Userdata_Binding)ctx)

	switch key {
	case "InitialDockState":
		if registry == nil || registry.enums == nil {
			vm.PushNil(L)
			return true
		}
		engine_enums.Push_Item_By_Value(
			L,
			registry.enums,
			"InitialDockState",
			i64(info.initial_dock_state),
		)
	case "InitialEnabled":
		vm.PushBoolean(L, info.initial_enabled)
	case "InitialEnabledShouldOverrideRestore":
		vm.PushBoolean(L, info.override_enabled_restore)
	case "FloatingXSize":
		vm.PushNumber(L, f64(info.floating_x_size))
	case "FloatingYSize":
		vm.PushNumber(L, f64(info.floating_y_size))
	case "MinWidth":
		vm.PushNumber(L, f64(info.min_width))
	case "MinHeight":
		vm.PushNumber(L, f64(info.min_height))
	case:
		return false
	}

	return true
}

dock_widget_plugin_gui_info_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^DockWidgetPluginGuiInfo)value)^ == (cast(^DockWidgetPluginGuiInfo)other)^
}

dock_widget_plugin_gui_info_string :: proc(value, ctx: rawptr) -> string {
	info := cast(^DockWidgetPluginGuiInfo)value
	return fmt.tprintf(
		"DockWidgetPluginGuiInfo(%v, %v, %v, %d, %d, %d, %d)",
		info.initial_dock_state,
		info.initial_enabled,
		info.override_enabled_restore,
		info.floating_x_size,
		info.floating_y_size,
		info.min_width,
		info.min_height,
	)
}

dock_widget_plugin_gui_info_destroy :: proc(value, ctx: rawptr) {
	free(cast(^DockWidgetPluginGuiInfo)value)
}

DockWidgetPluginGuiInfo_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding {
		name = "DockWidgetPluginGuiInfo",
		get = dock_widget_plugin_gui_info_get,
		string = dock_widget_plugin_gui_info_string,
		destroy = dock_widget_plugin_gui_info_destroy,
		equal = dock_widget_plugin_gui_info_equal,
	}
}

DockWidgetPluginGuiInfo_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", dock_widget_plugin_gui_info_new)
}
