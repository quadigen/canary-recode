package classes

import "base:runtime"

import "core:fmt"

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

UIListLayout_Class := Class_Info {
	name   = "UIListLayout",
	parent = &Instance_Class,
}

UIListLayout :: struct {
	using object:                   Object,
	enabled:                        bool,
	fill_direction:                 enums.FillDirection,
	horizontal_alignment:           enums.HorizontalAlignment,
	vertical_alignment:             enums.VerticalAlignment,
	sort_order:                     enums.SortOrder,
	padding:                        datatypes.UDim,
	line_padding:                   datatypes.UDim,
	padding_left:                   datatypes.UDim,
	padding_right:                  datatypes.UDim,
	padding_top:                    datatypes.UDim,
	padding_bottom:                 datatypes.UDim,
	wraps:                          bool,
	reverse:                        bool,
	max_items_per_line:             i32,
	ignore_invisible:               bool,
	horizontal_flex:                enums.UIFlexAlignment,
	vertical_flex:                  enums.UIFlexAlignment,
	item_line_alignment:            enums.ItemLineAlignment,
	position_callback:              i32,
	position_callback_capabilities: vm.Thread_Security_Capabilities,
	absolute_content_size:          datatypes.Vector2,
}

UIListLayout_Item :: struct {
	object:   ^Object,
	gui:      ^GuiObject,
	width:    f32,
	height:   f32,
	sequence: int,
}

UIListLayout_Line :: struct {
	start:        int,
	count:        int,
	main_size:    f32,
	cross_size:   f32,
	flex_leading: f32,
	flex_gap:     f32,
	flex_active:  bool,
}

UIListLayout_Init :: proc() -> UIListLayout {
	return UIListLayout {
		object = Object_Init(&UIListLayout_Class),
		enabled = true,
		fill_direction = .Vertical,
		horizontal_alignment = .Left,
		vertical_alignment = .Top,
		sort_order = .LayoutOrder,
		padding = datatypes.UDim{Scale = 0, Offset = 0},
		line_padding = datatypes.UDim{Scale = 0, Offset = 0},
		padding_left = datatypes.UDim{Scale = 0, Offset = 0},
		padding_right = datatypes.UDim{Scale = 0, Offset = 0},
		padding_top = datatypes.UDim{Scale = 0, Offset = 0},
		padding_bottom = datatypes.UDim{Scale = 0, Offset = 0},
		wraps = false,
		reverse = false,
		max_items_per_line = 0,
		ignore_invisible = true,
		horizontal_flex = .None,
		vertical_flex = .None,
		item_line_alignment = .Automatic,
		position_callback = -1,
		absolute_content_size = {0, 0},
	}
}

UIListLayout_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	layout := new(UIListLayout)
	layout^ = UIListLayout_Init()
	layout.name = "UIListLayout"

	return &layout.object
}

UIListLayout_release_position_callback :: proc(layout: ^UIListLayout) {
	if layout == nil || layout.position_callback <= 0 {
		return
	}

	if layout.signal_registry != nil &&
	   layout.signal_registry.vm_state != nil &&
	   layout.signal_registry.vm_state.L != nil {
		vm.ReleaseValue(layout.signal_registry.vm_state.L, layout.position_callback)
	}

	layout.position_callback = -1
	layout.position_callback_capabilities = {}
}

UIListLayout_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	layout := cast(^UIListLayout)object
	UIListLayout_release_position_callback(layout)

	Object_Destroy(object)
	free(layout)
}

ui_list_layout_resolve_udim :: proc(value: datatypes.UDim, basis: f32) -> f32 {
	return value.Scale * basis + value.Offset
}

ui_list_layout_string_less :: proc(a, b: string) -> bool {
	count := min(len(a), len(b))

	for i in 0 ..< count {
		if a[i] < b[i] {
			return true
		}

		if a[i] > b[i] {
			return false
		}
	}

	return len(a) < len(b)
}

ui_list_layout_item_less :: proc(layout: ^UIListLayout, a, b: UIListLayout_Item) -> bool {
	#partial switch layout.sort_order {
	case .Name:
		if a.object.name != b.object.name {
			return ui_list_layout_string_less(a.object.name, b.object.name)
		}

	case .LayoutOrder:
		if a.gui.layout_order != b.gui.layout_order {
			return a.gui.layout_order < b.gui.layout_order
		}
	}

	return a.sequence < b.sequence
}

ui_list_layout_sort_items :: proc(layout: ^UIListLayout, items: ^[dynamic]UIListLayout_Item) {
	if items == nil || len(items^) <= 1 {
		return
	}

	for i in 1 ..< len(items^) {
		current := items^[i]
		j := i

		for j > 0 && ui_list_layout_item_less(layout, current, items^[j - 1]) {
			items^[j] = items^[j - 1]
			j -= 1
		}

		items^[j] = current
	}

	if layout.reverse {
		left := 0
		right := len(items^) - 1

		for left < right {
			items^[left], items^[right] = items^[right], items^[left]

			left += 1
			right -= 1
		}
	}
}

ui_list_layout_horizontal_alignment :: proc(
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

ui_list_layout_vertical_alignment :: proc(
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

ui_list_layout_collect_items :: proc(
	layout: ^UIListLayout,
	registry: ^Registry,
	parent_width, parent_height: f32,
	items: ^[dynamic]UIListLayout_Item,
) {
	if layout == nil || registry == nil || layout.object.parent == nil {
		return
	}

	parent := layout.object.parent
	if parent == nil {
		return
	}

	sequence := 0

	for object in parent.children {
		if object == nil || object.destroyed || !Is_A_Class(object, &GuiObject_Class) {
			continue
		}

		gui := cast(^GuiObject)object

		if layout.ignore_invisible && !gui.visible {
			continue
		}

		width, height := gui_effective_size(gui, parent_width, parent_height)

		width = max(f32(0), width)
		height = max(f32(0), height)

		append(
			items,
			UIListLayout_Item {
				object = object,
				gui = gui,
				width = width,
				height = height,
				sequence = sequence,
			},
		)

		sequence += 1
	}
}

ui_list_layout_build_lines :: proc(
	layout: ^UIListLayout,
	items: []UIListLayout_Item,
	available_main: f32,
	item_padding: f32,
	lines: ^[dynamic]UIListLayout_Line,
) {
	if len(items) == 0 {
		return
	}

	line_start := 0
	line_count := 0

	line_main: f32 = 0
	line_cross: f32 = 0

	for index in 0 ..< len(items) {
		item := items[index]

		item_main: f32
		item_cross: f32

		if layout.fill_direction == .Vertical {
			item_main = item.height
			item_cross = item.width
		} else {
			item_main = item.width
			item_cross = item.height
		}

		extra_padding: f32 = 0

		if line_count > 0 {
			extra_padding = item_padding
		}

		over_size :=
			layout.wraps &&
			line_count > 0 &&
			available_main > 0 &&
			line_main + extra_padding + item_main > available_main

		over_count :=
			layout.wraps &&
			line_count > 0 &&
			layout.max_items_per_line > 0 &&
			line_count >= int(layout.max_items_per_line)

		if over_size || over_count {
			append(
				lines,
				UIListLayout_Line {
					start = line_start,
					count = line_count,
					main_size = line_main,
					cross_size = line_cross,
				},
			)

			line_start = index
			line_count = 0
			line_main = 0
			line_cross = 0

			extra_padding = 0
		}

		line_main += extra_padding + item_main
		line_cross = max(line_cross, item_cross)

		line_count += 1
	}

	if line_count > 0 {
		append(
			lines,
			UIListLayout_Line {
				start = line_start,
				count = line_count,
				main_size = line_main,
				cross_size = line_cross,
			},
		)
	}
}

ui_list_layout_main_size :: #force_inline proc(
	layout: ^UIListLayout,
	item: ^UIListLayout_Item,
) -> f32 {
	if layout.fill_direction == .Horizontal {
		return item.width
	}
	return item.height
}

ui_list_layout_cross_size :: #force_inline proc(
	layout: ^UIListLayout,
	item: ^UIListLayout_Item,
) -> f32 {
	if layout.fill_direction == .Horizontal {
		return item.height
	}
	return item.width
}

ui_list_layout_add_main :: proc(layout: ^UIListLayout, item: ^UIListLayout_Item, amount: f32) {
	if layout.fill_direction == .Horizontal {
		item.width = max(f32(0), item.width + amount)
	} else {
		item.height = max(f32(0), item.height + amount)
	}
}

ui_list_layout_set_cross :: proc(layout: ^UIListLayout, item: ^UIListLayout_Item, amount: f32) {
	if layout.fill_direction == .Horizontal {
		item.height = max(f32(0), amount)
	} else {
		item.width = max(f32(0), amount)
	}
}

ui_list_layout_cross_alignment :: proc(
	layout: ^UIListLayout,
	cross_flex: enums.UIFlexAlignment,
) -> enums.ItemLineAlignment {
	if layout.item_line_alignment != .Automatic {
		return layout.item_line_alignment
	}

	if cross_flex == .Fill {
		return .Stretch
	}

	if layout.fill_direction == .Vertical {
		#partial switch layout.horizontal_alignment {
		case .Center:
			return .Center
		case .Right:
			return .End
		}
	} else {
		#partial switch layout.vertical_alignment {
		case .Center:
			return .Center
		case .Bottom:
			return .End
		}
	}

	return .Start
}

ui_list_layout_item_cross_offset :: proc(
	alignment: enums.ItemLineAlignment,
	free_space: f32,
) -> f32 {
	#partial switch alignment {
	case .Center:
		return free_space * 0.5
	case .End:
		return free_space
	}

	return 0
}

ui_list_layout_apply_main_flex :: proc(
	layout: ^UIListLayout,
	items: []UIListLayout_Item,
	line: ^UIListLayout_Line,
	available_main, item_padding: f32,
	flex: enums.UIFlexAlignment,
) {
	line.flex_leading = 0
	line.flex_gap = 0
	line.flex_active = false

	sum_main: f32 = 0

	for index in line.start ..< line.start + line.count {
		sum_main += ui_list_layout_main_size(layout, &items[index])
	}

	normal_padding := f32(max(0, line.count - 1)) * item_padding
	free := available_main - sum_main - normal_padding

	#partial switch flex {
	case .Fill:
		if free > 0 && line.count > 0 {
			each := free / f32(line.count)

			for index in line.start ..< line.start + line.count {
				ui_list_layout_add_main(layout, &items[index], each)
			}

			line.main_size = available_main
			line.flex_active = true
		}
	case .SpaceAround:
		if free > 0 && line.count > 0 {
			gap := free / f32(line.count)
			line.flex_leading = gap * 0.5
			line.flex_gap = gap
			line.flex_active = true
		}
	case .SpaceBetween:
		if free > 0 && line.count > 1 {
			line.flex_gap = free / f32(line.count - 1)
			line.flex_active = true
		}
	case .SpaceEvenly:
		if free > 0 {
			gap := free / f32(line.count + 1)
			line.flex_leading = gap
			line.flex_gap = gap
			line.flex_active = true
		}
	}

	if !line.flex_active {
		line.main_size = sum_main + normal_padding
	}
}

UIListLayout_apply_position_callback :: proc(
	layout: ^UIListLayout,
	registry: ^Registry,
	ctx: ^Class_Step_Context,
	item: ^UIListLayout_Item,
	index: int,
	default_position: datatypes.Vector2,
) -> datatypes.Vector2 {
	if layout == nil ||
	   layout.position_callback <= 0 ||
	   item == nil ||
	   item.object == nil ||
	   registry == nil ||
	   registry.datatypes == nil ||
	   ctx == nil {
		return default_position
	}

	L := ctx.L

	if L == nil && registry.vm_state != nil {
		L = registry.vm_state.L
	}

	if L == nil {
		return default_position
	}

	base := vm.StackTop(L)
	defer vm.SetStackTop(L, base)

	previous_capabilities := vm.GetThreadSecurityCapabilities(L)
	vm.SetThreadSecurityCapabilities(L, layout.position_callback_capabilities)
	defer vm.SetThreadSecurityCapabilities(L, previous_capabilities)

	vm.PushRegistryReference(L, layout.position_callback)
	Push_Object(L, item.object)
	vm.PushNumber(L, f64(index))
	datatypes.Push_Vector2(L, registry.datatypes, default_position)
	vm.PushNumber(L, f64(ctx.delta_time))

	ok, err := vm.ProtectedCall(L, 4, 1)

	if !ok {
		fmt.eprintf("UIListLayout.PositionCallback failed: %s\n", err)
		delete(err)
		return default_position
	}

	if vm.IsUserdataType(L, -1, &registry.datatypes.vector2) {
		return (cast(^datatypes.Vector2)vm.UserdataValue(L, -1))^
	}

	return default_position
}

UIListLayout_Apply :: proc(layout: ^UIListLayout, registry: ^Registry, ctx: ^Class_Step_Context) {
	if layout == nil {
		return
	}

	old_content_size := layout.absolute_content_size
	layout.absolute_content_size = {0, 0}

	if !layout.enabled ||
	   layout.destroyed ||
	   layout.object.parent == nil ||
	   !Is_A_Class(layout.object.parent, &GuiObject_Class) {
		if abs(old_content_size.X) > 0.01 || abs(old_content_size.Y) > 0.01 {
			gui_layout_changed = true
		}
		return
	}

	parent := cast(^GuiObject)layout.object.parent

	_, _, parent_width, parent_height := GuiObject_get_absolute_transform(&parent.object, ctx)

	parent_width = max(f32(0), parent_width)
	parent_height = max(f32(0), parent_height)

	uip_left, uip_right, uip_top, uip_bottom, _ := gui_resolve_uipadding(
		parent,
		registry,
		parent_width,
		parent_height,
	)

	content_width := max(f32(0), parent_width - uip_left - uip_right)
	content_height := max(f32(0), parent_height - uip_top - uip_bottom)

	pad_left := ui_list_layout_resolve_udim(layout.padding_left, parent_width)
	pad_right := ui_list_layout_resolve_udim(layout.padding_right, parent_width)
	pad_top := ui_list_layout_resolve_udim(layout.padding_top, parent_height)
	pad_bottom := ui_list_layout_resolve_udim(layout.padding_bottom, parent_height)

	origin_x := uip_left + pad_left
	origin_y := uip_top + pad_top

	// Items and lines are local to this pass, including when Lua callbacks run.
	scratch := runtime.default_temp_allocator_temp_begin()
	defer runtime.default_temp_allocator_temp_end(scratch)
	allocator := context.temp_allocator if scratch.arena != nil else context.allocator
	items := make([dynamic]UIListLayout_Item, 0, len(parent.object.children), allocator)
	defer delete(items)

	ui_list_layout_collect_items(layout, registry, parent_width, parent_height, &items)

	ui_list_layout_sort_items(layout, &items)

	main_basis := content_height
	cross_basis := content_width
	main_available := max(f32(0), content_height - pad_top - pad_bottom)
	cross_available := max(f32(0), content_width - pad_left - pad_right)

	if layout.fill_direction == .Horizontal {
		main_basis = content_width
		cross_basis = content_height
		main_available = max(f32(0), content_width - pad_left - pad_right)
		cross_available = max(f32(0), content_height - pad_top - pad_bottom)
	}

	item_padding := ui_list_layout_resolve_udim(layout.padding, main_basis)

	line_padding := ui_list_layout_resolve_udim(layout.line_padding, cross_basis)

	lines := make([dynamic]UIListLayout_Line, 0, 4, allocator)
	defer delete(lines)

	ui_list_layout_build_lines(layout, items[:], main_available, item_padding, &lines)

	main_flex := layout.vertical_flex
	cross_flex := layout.horizontal_flex

	if layout.fill_direction == .Horizontal {
		main_flex = layout.horizontal_flex
		cross_flex = layout.vertical_flex
	}

	for line_index in 0 ..< len(lines) {
		line := &lines[line_index]

		ui_list_layout_apply_main_flex(
			layout,
			items[:],
			line,
			main_available,
			item_padding,
			main_flex,
		)

		if cross_flex == .Fill {
			line.cross_size = cross_available
		}
	}

	if len(lines) == 0 {
		layout.absolute_content_size = {
			max(f32(0), pad_left + pad_right),
			max(f32(0), pad_top + pad_bottom),
		}

		if abs(old_content_size.X - layout.absolute_content_size.X) > 0.01 ||
		   abs(old_content_size.Y - layout.absolute_content_size.Y) > 0.01 {
			gui_layout_changed = true
		}

		return
	}

	if layout.position_callback > 0 {
		gui_layout_animated = true
	}

	total_cross: f32 = 0
	max_main: f32 = 0

	for index in 0 ..< len(lines) {
		line := lines[index]

		if index > 0 {
			total_cross += line_padding
		}

		total_cross += line.cross_size
		max_main = max(max_main, line.main_size)
	}

	alignment := ui_list_layout_cross_alignment(layout, cross_flex)

	if layout.fill_direction == .Vertical {
		layout.absolute_content_size = {
			max(f32(0), pad_left + pad_right + total_cross),
			max(f32(0), pad_top + pad_bottom + max_main),
		}

		group_cross_offset := ui_list_layout_horizontal_alignment(
			layout.horizontal_alignment,
			max(f32(0), cross_available - total_cross),
		)

		column_offset := group_cross_offset

		for line_index in 0 ..< len(lines) {
			line := &lines[line_index]

			main_offset := line.flex_leading

			if !line.flex_active {
				main_offset = ui_list_layout_vertical_alignment(
					layout.vertical_alignment,
					max(f32(0), main_available - line.main_size),
				)
			}

			y := origin_y + main_offset

			for item_index in line.start ..< line.start + line.count {
				item := &items[item_index]

				if cross_flex == .Fill || alignment == .Stretch {
					ui_list_layout_set_cross(layout, item, line.cross_size)
				}

				item_cross_offset := ui_list_layout_item_cross_offset(
					alignment,
					line.cross_size - ui_list_layout_cross_size(layout, item),
				)

				default_position := datatypes.Vector2 {
					origin_x + column_offset + item_cross_offset,
					y,
				}

				item.gui.layout_override_active = true
				item.gui.layout_override_position = UIListLayout_apply_position_callback(
					layout,
					registry,
					ctx,
					item,
					item_index + 1,
					default_position,
				)

				item.gui.layout_override_size_active = true
				item.gui.layout_override_size = {item.width, item.height}

				if layout.destroyed {
					return
				}

				y += item.height

				if item_index < line.start + line.count - 1 {
					y += item_padding + line.flex_gap
				}
			}

			column_offset += line.cross_size

			if line_index < len(lines) - 1 {
				column_offset += line_padding
			}
		}
	} else {
		layout.absolute_content_size = {
			max(f32(0), pad_left + pad_right + max_main),
			max(f32(0), pad_top + pad_bottom + total_cross),
		}

		group_cross_offset := ui_list_layout_vertical_alignment(
			layout.vertical_alignment,
			max(f32(0), cross_available - total_cross),
		)

		row_offset := group_cross_offset

		for line_index in 0 ..< len(lines) {
			line := &lines[line_index]

			main_offset := line.flex_leading

			if !line.flex_active {
				main_offset = ui_list_layout_horizontal_alignment(
					layout.horizontal_alignment,
					max(f32(0), main_available - line.main_size),
				)
			}

			x := origin_x + main_offset

			for item_index in line.start ..< line.start + line.count {
				item := &items[item_index]

				if cross_flex == .Fill || alignment == .Stretch {
					ui_list_layout_set_cross(layout, item, line.cross_size)
				}

				item_cross_offset := ui_list_layout_item_cross_offset(
					alignment,
					line.cross_size - ui_list_layout_cross_size(layout, item),
				)

				default_position := datatypes.Vector2{x, origin_y + row_offset + item_cross_offset}

				item.gui.layout_override_active = true
				item.gui.layout_override_position = UIListLayout_apply_position_callback(
					layout,
					registry,
					ctx,
					item,
					item_index + 1,
					default_position,
				)

				item.gui.layout_override_size_active = true
				item.gui.layout_override_size = {item.width, item.height}

				if layout.destroyed {
					return
				}

				x += item.width

				if item_index < line.start + line.count - 1 {
					x += item_padding + line.flex_gap
				}
			}

			row_offset += line.cross_size

			if line_index < len(lines) - 1 {
				row_offset += line_padding
			}
		}
	}

	if abs(old_content_size.X - layout.absolute_content_size.X) > 0.01 ||
	   abs(old_content_size.Y - layout.absolute_content_size.Y) > 0.01 {
		gui_layout_changed = true
	}
}


UIListLayout_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	layout := cast(^UIListLayout)object

	switch key {
	case "Enabled":
		vm.PushBoolean(L, layout.enabled)

	case "Wraps":
		vm.PushBoolean(L, layout.wraps)

	case "Reverse":
		vm.PushBoolean(L, layout.reverse)

	case "IgnoreInvisible":
		vm.PushBoolean(L, layout.ignore_invisible)

	case "MaxItemsPerLine":
		vm.PushNumber(L, f64(layout.max_items_per_line))

	case "FillDirection":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(L, enum_registry, "FillDirection", i64(layout.fill_direction))

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

		_ = enums.Push_Item_By_Value(L, enum_registry, "SortOrder", i64(layout.sort_order))

	case "HorizontalFlex":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"UIFlexAlignment",
			i64(layout.horizontal_flex),
		)

	case "VerticalFlex":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"UIFlexAlignment",
			i64(layout.vertical_flex),
		)

	case "ItemLineAlignment":
		if enum_registry == nil {
			return false
		}

		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"ItemLineAlignment",
			i64(layout.item_line_alignment),
		)

	case "Padding":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_UDim(L, datatype_registry, layout.padding)

	case "LinePadding":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_UDim(L, datatype_registry, layout.line_padding)

	case "PaddingLeft":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_UDim(L, datatype_registry, layout.padding_left)

	case "PaddingRight":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_UDim(L, datatype_registry, layout.padding_right)

	case "PaddingTop":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_UDim(L, datatype_registry, layout.padding_top)

	case "PaddingBottom":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_UDim(L, datatype_registry, layout.padding_bottom)

	case "PositionCallback":
		if layout.position_callback > 0 {
			vm.PushRegistryReference(L, layout.position_callback)
		} else {
			vm.PushNil(L)
		}

	case "AbsoluteContentSize":
		if datatype_registry == nil {
			return false
		}

		datatypes.Push_Vector2(L, datatype_registry, layout.absolute_content_size)

	case:
		return false
	}

	return true
}

UIListLayout_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	layout := cast(^UIListLayout)object

	Gui_Layout_Mark_Dirty()

	switch key {
	case "Enabled":
		layout.enabled = vm.ArgBoolean(L, value_index)

	case "Wraps":
		layout.wraps = vm.ArgBoolean(L, value_index)

	case "Reverse":
		layout.reverse = vm.ArgBoolean(L, value_index)

	case "IgnoreInvisible":
		layout.ignore_invisible = vm.ArgBoolean(L, value_index)

	case "MaxItemsPerLine":
		layout.max_items_per_line = max(i32(0), i32(vm.ArgNumber(L, value_index)))

	case "FillDirection":
		if enum_registry == nil {
			return false
		}

		layout.fill_direction = enums.FillDirection(
			enums.Arg_Item(L, value_index, enum_registry, "FillDirection").value,
		)

	case "HorizontalAlignment":
		if enum_registry == nil {
			return false
		}

		layout.horizontal_alignment = enums.HorizontalAlignment(
			enums.Arg_Item(L, value_index, enum_registry, "HorizontalAlignment").value,
		)

	case "VerticalAlignment":
		if enum_registry == nil {
			return false
		}

		layout.vertical_alignment = enums.VerticalAlignment(
			enums.Arg_Item(L, value_index, enum_registry, "VerticalAlignment").value,
		)

	case "SortOrder":
		if enum_registry == nil {
			return false
		}

		layout.sort_order = enums.SortOrder(
			enums.Arg_Item(L, value_index, enum_registry, "SortOrder").value,
		)

	case "HorizontalFlex":
		if enum_registry == nil {
			return false
		}

		layout.horizontal_flex = enums.UIFlexAlignment(
			enums.Arg_Item(L, value_index, enum_registry, "UIFlexAlignment").value,
		)

	case "VerticalFlex":
		if enum_registry == nil {
			return false
		}

		layout.vertical_flex = enums.UIFlexAlignment(
			enums.Arg_Item(L, value_index, enum_registry, "UIFlexAlignment").value,
		)

	case "ItemLineAlignment":
		if enum_registry == nil {
			return false
		}

		layout.item_line_alignment = enums.ItemLineAlignment(
			enums.Arg_Item(L, value_index, enum_registry, "ItemLineAlignment").value,
		)

	case "Padding":
		if datatype_registry == nil {
			return false
		}

		layout.padding = datatypes.Arg_UDim(L, value_index, datatype_registry)

	case "LinePadding":
		if datatype_registry == nil {
			return false
		}

		layout.line_padding = datatypes.Arg_UDim(L, value_index, datatype_registry)

	case "PaddingLeft":
		if datatype_registry == nil {
			return false
		}

		layout.padding_left = datatypes.Arg_UDim(L, value_index, datatype_registry)

	case "PaddingRight":
		if datatype_registry == nil {
			return false
		}

		layout.padding_right = datatypes.Arg_UDim(L, value_index, datatype_registry)

	case "PaddingTop":
		if datatype_registry == nil {
			return false
		}

		layout.padding_top = datatypes.Arg_UDim(L, value_index, datatype_registry)

	case "PaddingBottom":
		if datatype_registry == nil {
			return false
		}

		layout.padding_bottom = datatypes.Arg_UDim(L, value_index, datatype_registry)

	case "PositionCallback":
		if vm.IsNil(L, value_index) {
			UIListLayout_release_position_callback(layout)
		} else if !vm.IsFunction(L, value_index) {
			_ = vm.RaiseError(L, "PositionCallback must be a function or nil")
			return true
		} else {
			UIListLayout_release_position_callback(layout)

			vm.PushValue(L, value_index)
			layout.position_callback = vm.RetainValue(L)
			layout.position_callback_capabilities = vm.GetThreadSecurityCapabilities(L)
			vm.Pop(L)
		}

	case "AbsoluteContentSize":
		_ = vm.RaiseError(L, "AbsoluteContentSize cannot be changed")

	case:
		return false
	}

	Gui_Layout_Mark_Dirty()

	return true
}

UIListLayout_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UIListLayout)source
	dst := cast(^UIListLayout)destination

	dst.enabled = src.enabled

	dst.fill_direction = src.fill_direction

	dst.horizontal_alignment = src.horizontal_alignment

	dst.vertical_alignment = src.vertical_alignment

	dst.sort_order = src.sort_order

	dst.padding = src.padding

	dst.line_padding = src.line_padding

	dst.padding_left = src.padding_left

	dst.padding_right = src.padding_right

	dst.padding_top = src.padding_top

	dst.padding_bottom = src.padding_bottom

	dst.wraps = src.wraps

	dst.reverse = src.reverse

	dst.max_items_per_line = src.max_items_per_line

	dst.ignore_invisible = src.ignore_invisible

	dst.horizontal_flex = src.horizontal_flex
	dst.vertical_flex = src.vertical_flex
	dst.item_line_alignment = src.item_line_alignment

	dst.absolute_content_size = {0, 0}
}

Register_UIListLayout :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UIListLayout_Class,
		UIListLayout_construct,
		UIListLayout_destroy,
		get = UIListLayout_get,
		set = UIListLayout_set,
		clone = UIListLayout_clone,
		properties = []string {
			"Enabled",
			"FillDirection",
			"HorizontalAlignment",
			"VerticalAlignment",
			"SortOrder",
			"Padding",
			"LinePadding",
			"PaddingLeft",
			"PaddingRight",
			"PaddingTop",
			"PaddingBottom",
			"Wraps",
			"Reverse",
			"MaxItemsPerLine",
			"IgnoreInvisible",
			"HorizontalFlex",
			"VerticalFlex",
			"ItemLineAlignment",
			"PositionCallback",
			"AbsoluteContentSize",
		},
	)
}
