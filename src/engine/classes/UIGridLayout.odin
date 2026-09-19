package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

UIGridLayout_Class := Class_Info{
	name   = "UIGridLayout",
	parent = &Instance_Class,
}

UIGridLayout :: struct {
	using object: Object,

	enabled:              bool,
	fill_direction:       enums.FillDirection,
	horizontal_alignment: enums.HorizontalAlignment,
	vertical_alignment:   enums.VerticalAlignment,
	sort_order:           enums.SortOrder,

	cell_padding: datatypes.UDim2,
	cell_size:    datatypes.UDim2,

	fill_direction_max_cells: i32,
	ignore_invisible:         bool,

	absolute_cell_count:  datatypes.Vector2,
	absolute_cell_size:   datatypes.Vector2,
	absolute_content_size: datatypes.Vector2,
}

UIGridLayout_Item :: struct {
	object:   ^Object,
	gui:      ^GuiObject,
	sequence: int,
}

UIGridLayout_Init :: proc() -> UIGridLayout {
	return UIGridLayout{
		object = Object_Init(&UIGridLayout_Class),

		enabled = true,

		fill_direction       = .Horizontal,
		horizontal_alignment = .Left,
		vertical_alignment   = .Top,
		sort_order           = .LayoutOrder,

		cell_padding = datatypes.UDim2{
			X_Scale  = 0,
			X_Offset = 5,
			Y_Scale  = 0,
			Y_Offset = 5,
		},

		cell_size = datatypes.UDim2{
			X_Scale  = 0,
			X_Offset = 100,
			Y_Scale  = 0,
			Y_Offset = 100,
		},

		fill_direction_max_cells = 0,
		ignore_invisible         = true,

		absolute_cell_count   = {0, 0},
		absolute_cell_size    = {0, 0},
		absolute_content_size = {0, 0},
	}
}

UIGridLayout_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	layout := new(UIGridLayout)
	layout^ = UIGridLayout_Init()
	layout.name = "UIGridLayout"

	return &layout.object
}

UIGridLayout_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	Object_Destroy(object)
	free(cast(^UIGridLayout)object)
}

ui_grid_layout_string_less :: proc(
	a, b: string,
) -> bool {
	count := min(len(a), len(b))

	for i in 0..<count {
		if a[i] < b[i] {
			return true
		}

		if a[i] > b[i] {
			return false
		}
	}

	return len(a) < len(b)
}

ui_grid_layout_item_less :: proc(
	layout: ^UIGridLayout,
	a, b: UIGridLayout_Item,
) -> bool {
	#partial switch layout.sort_order {
	case .Name:
		if a.object.name != b.object.name {
			return ui_grid_layout_string_less(
				a.object.name,
				b.object.name,
			)
		}

	case .LayoutOrder:
		if a.gui.layout_order != b.gui.layout_order {
			return a.gui.layout_order < b.gui.layout_order
		}
	}

	return a.sequence < b.sequence
}

ui_grid_layout_sort_items :: proc(
	layout: ^UIGridLayout,
	items: ^[dynamic]UIGridLayout_Item,
) {
	if items == nil || len(items^) <= 1 {
		return
	}

	for i in 1..<len(items^) {
		current := items^[i]
		j := i

		for j > 0 &&
		    ui_grid_layout_item_less(
			    layout,
			    current,
			    items^[j-1],
		    ) {
			items^[j] = items^[j-1]
			j -= 1
		}

		items^[j] = current
	}
}

ui_grid_layout_horizontal_alignment :: proc(
	alignment: enums.HorizontalAlignment,
	free_space: f32,
) -> f32 {
	#partial switch alignment {
	case .Center:
		return free_space * 0.5

	case .Right:
		return free_space
	}

	return 0
}

ui_grid_layout_vertical_alignment :: proc(
	alignment: enums.VerticalAlignment,
	free_space: f32,
) -> f32 {
	#partial switch alignment {
	case .Center:
		return free_space * 0.5

	case .Bottom:
		return free_space
	}

	return 0
}

ui_grid_layout_collect_items :: proc(
	layout: ^UIGridLayout,
	registry: ^Registry,
	items: ^[dynamic]UIGridLayout_Item,
) {
	if layout == nil ||
	   registry == nil ||
	   layout.object.parent == nil {
		return
	}

	sequence := 0

	for descriptor in registry.classes {
		for object in descriptor.instances {
			if object == nil ||
			   object.destroyed ||
			   object.parent != layout.object.parent ||
			   !Is_A(object, "GuiObject") {
				continue
			}

			gui := cast(^GuiObject)object

			if layout.ignore_invisible && !gui.visible {
				continue
			}

			append(
				items,
				UIGridLayout_Item{
					object   = object,
					gui      = gui,
					sequence = sequence,
				},
			)

			sequence += 1
		}
	}
}

ui_grid_layout_capacity :: proc(
	available: f32,
	cell: f32,
	padding: f32,
) -> int {
	if cell <= 0 {
		return 1
	}

	stride := cell + padding

	if stride <= 0 {
		return 1
	}

	count := int((available + padding) / stride)

	return max(1, count)
}

UIGridLayout_Apply :: proc(
	layout: ^UIGridLayout,
	registry: ^Registry,
	ctx: ^Class_Step_Context,
) {
	if layout == nil {
		return
	}

	layout.absolute_cell_count = {0, 0}
	layout.absolute_cell_size = {0, 0}
	layout.absolute_content_size = {0, 0}

	if !layout.enabled ||
	   layout.destroyed ||
	   layout.object.parent == nil ||
	   !Is_A(layout.object.parent, "GuiObject") {
		return
	}

	parent := cast(^GuiObject)layout.object.parent

	_, _, parent_width, parent_height :=
		GuiObject_get_absolute_transform(
			&parent.object,
			ctx,
		)

	parent_width = max(f32(0), parent_width)
	parent_height = max(f32(0), parent_height)

	cell_width :=
		layout.cell_size.X_Scale*parent_width +
		layout.cell_size.X_Offset

	cell_height :=
		layout.cell_size.Y_Scale*parent_height +
		layout.cell_size.Y_Offset

	padding_x :=
		layout.cell_padding.X_Scale*parent_width +
		layout.cell_padding.X_Offset

	padding_y :=
		layout.cell_padding.Y_Scale*parent_height +
		layout.cell_padding.Y_Offset

	cell_width = max(f32(0), cell_width)
	cell_height = max(f32(0), cell_height)

	padding_x = max(f32(0), padding_x)
	padding_y = max(f32(0), padding_y)

	layout.absolute_cell_size = {
		cell_width,
		cell_height,
	}

	items := make(
		[dynamic]UIGridLayout_Item,
		0,
		16,
	)
	defer delete(items)

	ui_grid_layout_collect_items(
		layout,
		registry,
		&items,
	)

	ui_grid_layout_sort_items(
		layout,
		&items,
	)

	item_count := len(items)

	if item_count == 0 {
		return
	}

	columns := 1
	rows := 1

	if layout.fill_direction == .Horizontal {
		columns =
			ui_grid_layout_capacity(
				parent_width,
				cell_width,
				padding_x,
			)

		if layout.fill_direction_max_cells > 0 {
			columns =
				min(
					columns,
					int(layout.fill_direction_max_cells),
				)
		}

		columns = min(columns, item_count)
		rows = (item_count + columns - 1) / columns
	} else {
		rows =
			ui_grid_layout_capacity(
				parent_height,
				cell_height,
				padding_y,
			)

		if layout.fill_direction_max_cells > 0 {
			rows =
				min(
					rows,
					int(layout.fill_direction_max_cells),
				)
		}

		rows = min(rows, item_count)
		columns = (item_count + rows - 1) / rows
	}

	layout.absolute_cell_count = {
		f32(columns),
		f32(rows),
	}

	content_width :=
		f32(columns)*cell_width +
		f32(max(0, columns-1))*padding_x

	content_height :=
		f32(rows)*cell_height +
		f32(max(0, rows-1))*padding_y

	layout.absolute_content_size = {
		content_width,
		content_height,
	}

	start_x :=
		ui_grid_layout_horizontal_alignment(
			layout.horizontal_alignment,
			parent_width-content_width,
		)

	start_y :=
		ui_grid_layout_vertical_alignment(
			layout.vertical_alignment,
			parent_height-content_height,
		)

	for index in 0..<item_count {
		row: int
		column: int

		if layout.fill_direction == .Horizontal {
			column = index % columns
			row = index / columns
		} else {
			row = index % rows
			column = index / rows
		}

		x :=
			start_x +
			f32(column)*(cell_width+padding_x)

		y :=
			start_y +
			f32(row)*(cell_height+padding_y)

		item := &items[index]

		item.gui.layout_override_active = true
		item.gui.layout_override_position = {
			x,
			y,
		}

		item.gui.layout_override_size_active = true
		item.gui.layout_override_size = {
			cell_width,
			cell_height,
		}
	}
}

UIGridLayout_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	layout := cast(^UIGridLayout)object

	switch key {
	case "Enabled":
		vm.PushBoolean(L, layout.enabled)

	case "IgnoreInvisible":
		vm.PushBoolean(L, layout.ignore_invisible)

	case "FillDirectionMaxCells":
		vm.PushNumber(
			L,
			f64(layout.fill_direction_max_cells),
		)

	case "FillDirection":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"FillDirection",
			i64(layout.fill_direction),
		)

	case "HorizontalAlignment":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"HorizontalAlignment",
			i64(layout.horizontal_alignment),
		)

	case "VerticalAlignment":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"VerticalAlignment",
			i64(layout.vertical_alignment),
		)

	case "SortOrder":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"SortOrder",
			i64(layout.sort_order),
		)

	case "CellPadding":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_UDim2(
			L,
			datatype_registry,
			layout.cell_padding,
		)

	case "CellSize":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_UDim2(
			L,
			datatype_registry,
			layout.cell_size,
		)

	case "AbsoluteCellCount":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Vector2(
			L,
			datatype_registry,
			layout.absolute_cell_count,
		)

	case "AbsoluteCellSize":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Vector2(
			L,
			datatype_registry,
			layout.absolute_cell_size,
		)

	case "AbsoluteContentSize":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Vector2(
			L,
			datatype_registry,
			layout.absolute_content_size,
		)

	case:
		return false
	}

	return true
}

UIGridLayout_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	layout := cast(^UIGridLayout)object

	switch key {
	case "Enabled":
		layout.enabled =
			vm.ArgBoolean(
				L,
				value_index,
			)

	case "IgnoreInvisible":
		layout.ignore_invisible =
			vm.ArgBoolean(
				L,
				value_index,
			)

	case "FillDirectionMaxCells":
		layout.fill_direction_max_cells =
			max(
				i32(0),
				i32(
					vm.ArgNumber(
						L,
						value_index,
					),
				),
			)

	case "FillDirection":
		if enum_registry == nil {
			return false
		}

		layout.fill_direction =
			enums.FillDirection(
				enums.Arg_Item(
					L,
					value_index,
					enum_registry,
					"FillDirection",
				).value,
			)

	case "HorizontalAlignment":
		if enum_registry == nil {
			return false
		}

		layout.horizontal_alignment =
			enums.HorizontalAlignment(
				enums.Arg_Item(
					L,
					value_index,
					enum_registry,
					"HorizontalAlignment",
				).value,
			)

	case "VerticalAlignment":
		if enum_registry == nil {
			return false
		}

		layout.vertical_alignment =
			enums.VerticalAlignment(
				enums.Arg_Item(
					L,
					value_index,
					enum_registry,
					"VerticalAlignment",
				).value,
			)

	case "SortOrder":
		if enum_registry == nil {
			return false
		}

		layout.sort_order =
			enums.SortOrder(
				enums.Arg_Item(
					L,
					value_index,
					enum_registry,
					"SortOrder",
				).value,
			)

	case "CellPadding":
		if datatype_registry == nil {
			return false
		}

		layout.cell_padding =
			datatypes.Arg_UDim2(
				L,
				value_index,
				datatype_registry,
			)

	case "CellSize":
		if datatype_registry == nil {
			return false
		}

		layout.cell_size =
			datatypes.Arg_UDim2(
				L,
				value_index,
				datatype_registry,
			)

	case "AbsoluteCellCount":
		_ = vm.RaiseError(
			L,
			"AbsoluteCellCount cannot be changed",
		)

	case "AbsoluteCellSize":
		_ = vm.RaiseError(
			L,
			"AbsoluteCellSize cannot be changed",
		)

	case "AbsoluteContentSize":
		_ = vm.RaiseError(
			L,
			"AbsoluteContentSize cannot be changed",
		)

	case:
		return false
	}

	return true
}

UIGridLayout_clone :: proc(
	source: ^Object,
	destination: ^Object,
) {
	src := cast(^UIGridLayout)source
	dst := cast(^UIGridLayout)destination

	dst.enabled =
		src.enabled

	dst.fill_direction =
		src.fill_direction

	dst.horizontal_alignment =
		src.horizontal_alignment

	dst.vertical_alignment =
		src.vertical_alignment

	dst.sort_order =
		src.sort_order

	dst.cell_padding =
		src.cell_padding

	dst.cell_size =
		src.cell_size

	dst.fill_direction_max_cells =
		src.fill_direction_max_cells

	dst.ignore_invisible =
		src.ignore_invisible

	dst.absolute_cell_count =
		{0, 0}

	dst.absolute_cell_size =
		{0, 0}

	dst.absolute_content_size =
		{0, 0}
}

Register_UIGridLayout :: proc(
	registry: ^Registry,
) {
	Register_Class(
		registry,
		&UIGridLayout_Class,
		UIGridLayout_construct,
		UIGridLayout_destroy,

		get = UIGridLayout_get,
		set = UIGridLayout_set,
		clone = UIGridLayout_clone,

		properties = []string{
			"Enabled",
			"FillDirection",
			"HorizontalAlignment",
			"VerticalAlignment",
			"SortOrder",
			"CellPadding",
			"CellSize",
			"FillDirectionMaxCells",
			"IgnoreInvisible",
			"AbsoluteCellCount",
			"AbsoluteCellSize",
			"AbsoluteContentSize",
		},
	)
}