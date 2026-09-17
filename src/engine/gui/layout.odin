package gui

import datatypes "../datatypes"

Layout_Direction :: enum {
	Row,
	Column,
}

Layout_Padding :: struct {
	left:   f32,
	right:  f32,
	top:    f32,
	bottom: f32,
}

Layout_Item_Config :: struct {
	flex_grow:    f32,
	min_width:    f32,
	min_height:   f32,
	max_width:    f32,
	max_height:   f32,
	aspect_ratio: f32,
	layout_order: i32,
}

Layout_Item :: struct {
	id: string,

	width:  f32,
	height: f32,

	min_width:  f32,
	min_height: f32,
	max_width:  f32,
	max_height: f32,

	aspect_ratio: f32,
	layout_order: i32,
	flex_grow:    f32,

	x:             f32,
	y:             f32,
	actual_width:  f32,
	actual_height: f32,
}

Layout_Container :: struct {
	direction: Layout_Direction,

	width:  f32,
	height: f32,

	gap:     f32,
	padding: Layout_Padding,
}

Layout_Coordinate :: struct {
	Position: datatypes.UDim2,
	Size:     datatypes.UDim2,
}

Editor_Layout_Coordinates :: struct {
	TopbarCoordinates:     Layout_Coordinate,
	ViewportCoordinates:   Layout_Coordinate,
	CodeEditorCoordinates: Layout_Coordinate,
	OutputCoordinates:     Layout_Coordinate,
	ExplorerCoordinates:   Layout_Coordinate,
	InspectorCoordinates:  Layout_Coordinate,
}

Editor_Layout_Config :: struct {
	P:         f32,
	TopH:      f32,
	Padding: f32,

	Topbar:   Layout_Item_Config,
	Content:  Layout_Item_Config,

	Left:  Layout_Item_Config,
	Right: Layout_Item_Config,

	Viewport:  Layout_Item_Config,
	Output:    Layout_Item_Config,

	Explorer:  Layout_Item_Config,
	Inspector: Layout_Item_Config,

	show_output: bool,
}

Editor_Layout_Window :: enum {
	Topbar,
	Content,
	Left,
	Right,
	Viewport,
	CodeEditor,
	Output,
	Explorer,
	Inspector,
}

Editor_Layout_Default_Config :: proc() -> Editor_Layout_Config {
	return Editor_Layout_Config {
		P         = 4,
		TopH      = 33,
		Padding = 5,

		Topbar = {
			flex_grow = 0,
		},
		Content = {
			flex_grow = 1,
		},

		Left = {
			flex_grow = 0.78,
			min_width = 0,
		},
		Right = {
			flex_grow = 0.22,
			min_width = 0,
		},

		Viewport = {
			flex_grow    = 0.7,
			layout_order = 1,
		},
		Output = {
			flex_grow    = 0.3,
			layout_order = 2,
		},

		Explorer = {
			flex_grow    = 0.5,
			layout_order = 1,
		},
		Inspector = {
			flex_grow    = 0.5,
			layout_order = 2,
		},

		show_output = true,
	}
}

Editor_Layout_Get_Window :: proc(
	config: ^Editor_Layout_Config,
	window: Editor_Layout_Window,
) -> ^Layout_Item_Config {
	if config == nil {
		return nil
	}

	switch window {
	case .Topbar:
		return &config.Topbar
	case .Content:
		return &config.Content
	case .Left:
		return &config.Left
	case .Right:
		return &config.Right
	case .Viewport, .CodeEditor:
		return &config.Viewport
	case .Output:
		return &config.Output
	case .Explorer:
		return &config.Explorer
	case .Inspector:
		return &config.Inspector
	}

	return nil
}

layout_create_item :: proc(
	id: string,
	width, height: f32,
	config: Layout_Item_Config,
) -> Layout_Item {
	return Layout_Item {
		id = id,

		width  = width,
		height = height,

		min_width  = config.min_width,
		min_height = config.min_height,
		max_width  = config.max_width,
		max_height = config.max_height,

		aspect_ratio = config.aspect_ratio,
		layout_order = config.layout_order,
		flex_grow    = config.flex_grow,

		actual_width  = width,
		actual_height = height,
	}
}

layout_sort :: proc(items: []Layout_Item) {
	for i := 1; i < len(items); i += 1 {
		current := items[i]
		j := i

		for j > 0 && items[j - 1].layout_order > current.layout_order {
			items[j] = items[j - 1]
			j -= 1
		}

		items[j] = current
	}
}

layout_clamp_size :: proc(
	value: f32,
	minimum: f32,
	maximum: f32,
) -> f32 {
	result := max(value, minimum)

	if maximum > 0 {
		result = min(result, maximum)
	}

	return result
}

layout_calculate :: proc(
	container: Layout_Container,
	items: []Layout_Item,
) {
	if len(items) == 0 {
		return
	}

	layout_sort(items)

	is_row := container.direction == .Row

	content_width :=
		max(
			container.width -
			container.padding.left -
			container.padding.right,
			0,
		)

	content_height :=
		max(
			container.height -
			container.padding.top -
			container.padding.bottom,
			0,
		)

	content_main := content_height

	if is_row {
		content_main = content_width
	}

	total_main: f32
	total_flex: f32

	for i := 0; i < len(items); i += 1 {
		item := &items[i]

		if item.aspect_ratio > 0 {
			if is_row {
				item.width = item.height * item.aspect_ratio
			} else {
				item.height = item.width / item.aspect_ratio
			}
		}

		if is_row {
			item.actual_width = layout_clamp_size(
				item.width,
				item.min_width,
				item.max_width,
			)

			item.actual_height = layout_clamp_size(
				min(item.height, content_height),
				item.min_height,
				item.max_height,
			)

			total_main += item.actual_width
		} else {
			item.actual_height = layout_clamp_size(
				item.height,
				item.min_height,
				item.max_height,
			)

			item.actual_width = layout_clamp_size(
				min(item.width, content_width),
				item.min_width,
				item.max_width,
			)

			total_main += item.actual_height
		}

		total_flex += max(item.flex_grow, 0)
	}

	if len(items) > 1 {
		total_main += container.gap * f32(len(items) - 1)
	}

	remaining := content_main - total_main

	if remaining > 0 && total_flex > 0 {
		for i := 0; i < len(items); i += 1 {
			item := &items[i]

			if item.flex_grow <= 0 {
				continue
			}

			growth := remaining * (item.flex_grow / total_flex)

			if is_row {
				item.actual_width = layout_clamp_size(
					item.actual_width + growth,
					item.min_width,
					item.max_width,
				)
			} else {
				item.actual_height = layout_clamp_size(
					item.actual_height + growth,
					item.min_height,
					item.max_height,
				)
			}
		}
	}

	cursor := container.padding.top

	if is_row {
		cursor = container.padding.left
	}

	for i := 0; i < len(items); i += 1 {
		item := &items[i]

		if is_row {
			item.x = cursor
			item.y = container.padding.top

			cursor += item.actual_width + container.gap
		} else {
			item.x = container.padding.left
			item.y = cursor

			cursor += item.actual_height + container.gap
		}
	}
}

layout_find :: proc(
	items: []Layout_Item,
	id: string,
) -> ^Layout_Item {
	for i := 0; i < len(items); i += 1 {
		if items[i].id == id {
			return &items[i]
		}
	}

	return nil
}

layout_to_coordinate :: proc(
	item: ^Layout_Item,
	offset_x, offset_y: f32,
) -> Layout_Coordinate {
	assert(item != nil)

	return Layout_Coordinate {
		Position = datatypes.UDim2_FromOffset(
			offset_x + item.x,
			offset_y + item.y,
		),

		Size = datatypes.UDim2_FromOffset(
			item.actual_width,
			item.actual_height,
		),
	}
}

Editor_Layout_Compute :: proc(
	config: ^Editor_Layout_Config,
	width, height: f32,
) -> Editor_Layout_Coordinates {
	assert(config != nil)

	P := config.P

	root_items := [2]Layout_Item {
		layout_create_item(
			"Topbar",
			width,
			config.TopH,
			config.Topbar,
		),
		layout_create_item(
			"Content",
			width,
			0,
			config.Content,
		),
	}

	layout_calculate(
		Layout_Container {
			direction = .Column,
			width     = width,
			height    = height,
			gap       = P,

			padding = {
				left   = P,
				right  = P,
				top    = P,
				bottom = P,
			},
		},
		root_items[:],
	)

	topbar_item := layout_find(root_items[:], "Topbar")
	content_item := layout_find(root_items[:], "Content")

	assert(topbar_item != nil)
	assert(content_item != nil)

	row_items := [2]Layout_Item {
		layout_create_item(
			"Left",
			0,
			content_item.actual_height,
			config.Left,
		),
		layout_create_item(
			"Right",
			0,
			content_item.actual_height,
			config.Right,
		),
	}

	layout_calculate(
		Layout_Container {
			direction = .Row,
			width     = content_item.actual_width,
			height    = content_item.actual_height,
			gap       = P,
		},
		row_items[:],
	)

	left_item := layout_find(row_items[:], "Left")
	right_item := layout_find(row_items[:], "Right")

	assert(left_item != nil)
	assert(right_item != nil)

	left_offset_x := content_item.x + left_item.x
	left_offset_y := content_item.y + left_item.y

	right_offset_x := content_item.x + right_item.x
	right_offset_y := content_item.y + right_item.y

	viewport_coordinate: Layout_Coordinate
	output_coordinate: Layout_Coordinate

	if config.show_output {
		left_column_items := [2]Layout_Item {
			layout_create_item(
				"Viewport",
				left_item.actual_width,
				0,
				config.Viewport,
			),
			layout_create_item(
				"Output",
				left_item.actual_width,
				0,
				config.Output,
			),
		}

		layout_calculate(
			Layout_Container {
				direction = .Column,
				width     = left_item.actual_width,
				height    = left_item.actual_height,
				gap       = P,

				padding = {
					left   = config.Padding,
					right  = config.Padding,
					top    = config.Padding,
					bottom = config.Padding,
				},
			},
			left_column_items[:],
		)

		viewport_item := layout_find(
			left_column_items[:],
			"Viewport",
		)

		output_item := layout_find(
			left_column_items[:],
			"Output",
		)

		viewport_coordinate =
			layout_to_coordinate(
				viewport_item,
				left_offset_x,
				left_offset_y,
			)

		output_coordinate =
			layout_to_coordinate(
				output_item,
				left_offset_x,
				left_offset_y,
			)
	} else {
		viewport_config := config.Viewport
		viewport_config.flex_grow = 1

		left_column_items := [1]Layout_Item {
			layout_create_item(
				"Viewport",
				left_item.actual_width,
				0,
				viewport_config,
			),
		}

		layout_calculate(
			Layout_Container {
				direction = .Column,
				width     = left_item.actual_width,
				height    = left_item.actual_height,

				padding = {
					left   = config.Padding,
					right  = config.Padding,
					top    = config.Padding,
					bottom = config.Padding,
				},
			},
			left_column_items[:],
		)

		viewport_coordinate =
			layout_to_coordinate(
				&left_column_items[0],
				left_offset_x,
				left_offset_y,
			)

		output_coordinate = Layout_Coordinate {
			Position = datatypes.UDim2_FromOffset(
				0,
				height,
			),
			Size = datatypes.UDim2_Zero,
		}
	}

	right_column_items := [2]Layout_Item {
		layout_create_item(
			"Explorer",
			right_item.actual_width,
			0,
			config.Explorer,
		),
		layout_create_item(
			"Inspector",
			right_item.actual_width,
			0,
			config.Inspector,
		),
	}

	layout_calculate(
		Layout_Container {
			direction = .Column,
			width     = right_item.actual_width,
			height    = right_item.actual_height,
			gap       = P,

			padding = {
				left   = config.Padding,
				right  = config.Padding,
				top    = config.Padding,
				bottom = config.Padding,
			},
		},
		right_column_items[:],
	)

	explorer_item :=
		layout_find(
			right_column_items[:],
			"Explorer",
		)

	inspector_item :=
		layout_find(
			right_column_items[:],
			"Inspector",
		)

	return Editor_Layout_Coordinates {
		TopbarCoordinates =
			layout_to_coordinate(
				topbar_item,
				0,
				0,
			),

		ViewportCoordinates = viewport_coordinate,

		// Canary's CodeEditor targets Viewport.
		CodeEditorCoordinates = viewport_coordinate,

		OutputCoordinates = output_coordinate,

		ExplorerCoordinates =
			layout_to_coordinate(
				explorer_item,
				right_offset_x,
				right_offset_y,
			),

		InspectorCoordinates =
			layout_to_coordinate(
				inspector_item,
				right_offset_x,
				right_offset_y,
			),
	}
}