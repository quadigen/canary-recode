package datatypes

import enums "../enum"

DockWidgetPluginGuiInfo :: struct {
	initial_dock_state:       enums.InitialDockState,
	initial_enabled:          bool,
	override_enabled_restore: bool,
	floating_x_size:          i32,
	floating_y_size:          i32,
	min_width:                i32,
	min_height:               i32,
}
