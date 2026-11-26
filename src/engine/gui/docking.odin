package gui

import datatypes "../datatypes"
import "core:strings"

Dock_Column :: enum {
	Left,
	Center,
	Right,
}

Dock_Row :: enum {
	Top,
	Middle,
	Bottom,
}

Dock_Anchor :: enum {
	Top_Left,
	Top_Center,
	Top_Right,
	Middle_Left,
	Middle_Center,
	Middle_Right,
	Bottom_Left,
	Bottom_Center,
	Bottom_Right,
}

dock_anchor_column :: proc(a: Dock_Anchor) -> Dock_Column {
	return Dock_Column(int(a) % 3)
}

dock_anchor_row :: proc(a: Dock_Anchor) -> Dock_Row {
	return Dock_Row(int(a) / 3)
}

dock_make_anchor :: proc(col: Dock_Column, row: Dock_Row) -> Dock_Anchor {
	return Dock_Anchor(int(row) * 3 + int(col))
}

Dock_Panel :: enum {
	Topbar,
	Viewport,
	Explorer,
	Inspector,
	Output,
	Custom_0,
	Custom_1,
	Custom_2,
	Custom_3,
	Custom_4,
	Custom_5,
	Custom_6,
	Custom_7,
	Custom_8,
	Custom_9,
	Custom_10,
	Custom_11,
	Custom_12,
	Custom_13,
	Custom_14,
	Custom_15,
	Custom_16,
	Custom_17,
	Custom_18,
	Custom_19,
	Custom_20,
	Custom_21,
	Custom_22,
	Custom_23,
	Custom_24,
	Custom_25,
	Custom_26,
	Custom_27,
	Custom_28,
	Custom_29,
	Custom_30,
	Custom_31,
	Custom_32,
	Custom_33,
	Custom_34,
	Custom_35,
	Custom_36,
	Custom_37,
	Custom_38,
	Custom_39,
	Custom_40,
	Custom_41,
	Custom_42,
	Custom_43,
	Custom_44,
	Custom_45,
	Custom_46,
	Custom_47,
	Custom_48,
	Custom_49,
	Custom_50,
	Custom_51,
	Custom_52,
	Custom_53,
	Custom_54,
	Custom_55,
	Custom_56,
	Custom_57,
	Custom_58,
	Custom_59,
	Custom_60,
	Custom_61,
	Custom_62,
	Custom_63,
}

Dock_Slot :: struct {
	anchor:    Dock_Anchor,
	order:     i32,
	weight:    f32,
	visible:   bool,
	full_span: bool,
}

Dock_State :: struct {
	slots:         [Dock_Panel]Dock_Slot,
	names:         [Dock_Panel]string,
	column_weight: [Dock_Column]f32,
	band_size:     [Dock_Row]f32,
}


Dock_Default_State :: proc() -> Dock_State {
	s: Dock_State

	s.slots[.Topbar] = {
		anchor    = .Top_Center,
		weight    = 1,
		visible   = true,
		full_span = true,
	}
	s.slots[.Viewport] = {
		anchor  = .Middle_Center,
		weight  = 0.7,
		order   = 1,
		visible = true,
	}
	s.slots[.Output] = {
		anchor  = .Bottom_Center,
		weight  = 0.3,
		order   = 2,
		visible = true,
	}
	s.slots[.Explorer] = {
		anchor  = .Top_Right,
		weight  = 0.5,
		order   = 1,
		visible = true,
	}
	s.slots[.Inspector] = {
		anchor  = .Bottom_Right,
		weight  = 0.5,
		order   = 2,
		visible = true,
	}

	s.column_weight = {
		.Left   = 0.22,
		.Center = 0.78,
		.Right  = 0.22,
	}
	s.band_size = {
		.Top    = 0.1,
		.Middle = 0,
		.Bottom = 0.25,
	}
	return s
}

dock_panel_id :: proc(state: ^Dock_State, p: Dock_Panel) -> string {
	#partial switch p {
	case .Topbar:
		return "Topbar"
	case .Viewport:
		return "Viewport"
	case .Explorer:
		return "Explorer"
	case .Inspector:
		return "Inspector"
	case .Output:
		return "Output"
	case:
		return state.names[p]
	}
	return ""
}

dock_column_id :: proc(c: Dock_Column) -> string {
	switch c {
	case .Left:
		return "Left"
	case .Center:
		return "Center"
	case .Right:
		return "Right"
	}
	return ""
}


dock_panel_fixed_height :: proc(p: Dock_Panel, config: ^Editor_Layout_Config) -> f32 {
	if p == .Topbar {
		return config.TopH
	}
	return 0
}

dock_band_thickness :: proc(
	state: ^Dock_State,
	config: ^Editor_Layout_Config,
	members: []Dock_Panel,
	row: Dock_Row,
	window_h: f32,
) -> f32 {
	t: f32
	for p in members {
		t = max(t, dock_panel_fixed_height(p, config))
	}
	if t <= 0 {
		t = window_h * state.band_size[row]
	}
	return t
}


dock_layout_group :: proc(
	state: ^Dock_State,
	config: ^Editor_Layout_Config,
	members: []Dock_Panel,
	x, y, w, h, pad: f32,
	vertical: bool,
	out: ^[Dock_Panel]Layout_Coordinate,
) {
	if len(members) == 0 {
		return
	}

	items: [len(Dock_Panel)]Layout_Item
	n := 0

	for p in members {
		slot := state.slots[p]
		fixed := dock_panel_fixed_height(p, config)

		rank: i32
		if vertical {
			rank = i32(dock_anchor_row(slot.anchor))
		} else {
			rank = i32(dock_anchor_column(slot.anchor))
		}

		cfg := Layout_Item_Config {
			flex_grow    = slot.weight,
			layout_order = rank * 1000 + slot.order,
		}

		if vertical {
			if fixed > 0 {
				cfg.flex_grow = 0
				items[n] = layout_create_item(dock_panel_id(state, p), w, fixed, cfg)
			} else {
				items[n] = layout_create_item(dock_panel_id(state, p), w, 0, cfg)
			}
		} else {
			items[n] = layout_create_item(dock_panel_id(state, p), 0, h, cfg)
		}
		n += 1
	}

	layout_calculate(
		Layout_Container {
			direction = vertical ? .Column : .Row,
			width = w,
			height = h,
			gap = config.P,
			padding = {top = pad, bottom = pad},
		},
		items[:n],
	)


	for p in members {
		if it := layout_find(items[:n], dock_panel_id(state, p)); it != nil {
			out[p] = layout_to_coordinate(it, x, y)
		}
	}
}

Editor_Layout_Compute_Docked :: proc(
	config: ^Editor_Layout_Config,
	dock: ^Dock_State,
	width, height: f32,
	all_panels: ^[Dock_Panel]Layout_Coordinate = nil,
) -> (
	coords: Editor_Layout_Coordinates,
	bounds: Layout_Coordinate,
) {
	assert(config != nil && dock != nil)
	P := config.P


	columns: [Dock_Column][len(Dock_Panel)]Dock_Panel
	column_n: [Dock_Column]int
	top_bar: [len(Dock_Panel)]Dock_Panel
	bottom_bar: [len(Dock_Panel)]Dock_Panel
	top_n, bottom_n := 0, 0

	for p in Dock_Panel {
		slot := dock.slots[p]
		if !slot.visible {
			continue
		}

		row := dock_anchor_row(slot.anchor)
		col := dock_anchor_column(slot.anchor)

		if slot.full_span && row == .Top {
			top_bar[top_n] = p
			top_n += 1
		} else if slot.full_span && row == .Bottom {
			bottom_bar[bottom_n] = p
			bottom_n += 1
		} else {
			columns[col][column_n[col]] = p
			column_n[col] += 1
		}
	}


	root: [3]Layout_Item
	rn := 0

	if top_n > 0 {
		root[rn] = layout_create_item(
			"TopBar",
			width,
			dock_band_thickness(dock, config, top_bar[:top_n], .Top, height),
			{layout_order = 0},
		)
		rn += 1
	}

	root[rn] = layout_create_item("Body", width, 0, {flex_grow = 1, layout_order = 1})
	rn += 1

	if bottom_n > 0 {
		root[rn] = layout_create_item(
			"BottomBar",
			width,
			dock_band_thickness(dock, config, bottom_bar[:bottom_n], .Bottom, height),
			{layout_order = 2},
		)
		rn += 1
	}

	layout_calculate(
		Layout_Container {
			direction = .Column,
			width = width,
			height = height,
			gap = P,
			padding = {left = P, right = P, top = P, bottom = P},
		},
		root[:rn],
	)

	panels: [Dock_Panel]Layout_Coordinate
	hidden := Layout_Coordinate {
		Position = datatypes.UDim2_FromOffset(0, height),
		Size     = datatypes.UDim2_Zero,
	}
	for p in Dock_Panel {
		panels[p] = hidden
	}


	if it := layout_find(root[:rn], "TopBar"); it != nil {
		dock_layout_group(
			dock,
			config,
			top_bar[:top_n],
			it.x,
			it.y,
			it.actual_width,
			it.actual_height,
			0,
			false,
			&panels,
		)
	}
	if it := layout_find(root[:rn], "BottomBar"); it != nil {
		dock_layout_group(
			dock,
			config,
			bottom_bar[:bottom_n],
			it.x,
			it.y,
			it.actual_width,
			it.actual_height,
			0,
			false,
			&panels,
		)
	}


	if body := layout_find(root[:rn], "Body"); body != nil {
		cols: [3]Layout_Item
		cn := 0

		for c in Dock_Column {
			if column_n[c] == 0 {
				continue
			}
			cols[cn] = layout_create_item(
				dock_column_id(c),
				0,
				body.actual_height,
				{flex_grow = dock.column_weight[c], layout_order = i32(c)},
			)
			cn += 1
		}

		layout_calculate(
			Layout_Container {
				direction = .Row,
				width = body.actual_width,
				height = body.actual_height,
				gap = P,
			},
			cols[:cn],
		)

		for c in Dock_Column {
			if column_n[c] == 0 {
				continue
			}
			it := layout_find(cols[:cn], dock_column_id(c))
			dock_layout_group(
				dock,
				config,
				columns[c][:column_n[c]],
				body.x + it.x,
				body.y + it.y,
				it.actual_width,
				it.actual_height,
				config.Padding,
				true,
				&panels,
			)
		}
	}

	if all_panels != nil {all_panels^ = panels}
	coords = Editor_Layout_Coordinates {
		TopbarCoordinates     = panels[.Topbar],
		ViewportCoordinates   = panels[.Viewport],
		CodeEditorCoordinates = panels[.Viewport],
		OutputCoordinates     = panels[.Output],
		ExplorerCoordinates   = panels[.Explorer],
		InspectorCoordinates  = panels[.Inspector],
	}

	bounds = Layout_Coordinate {
		Position = datatypes.UDim2_FromOffset(0, 0),
		Size     = datatypes.UDim2_FromOffset(width, height),
	}
	return
}


dock_find_named :: proc(state: ^Dock_State, name: string, create := false) -> (Dock_Panel, bool) {
	for p in Dock_Panel {
		if p < .Custom_0 {continue}
		if state.names[p] == name && name != "" {return p, true}
	}
	if create && name != "" && len(name) <= 128 {
		for p in Dock_Panel {
			if p < .Custom_0 || state.names[p] != "" {continue}
			state.names[p] = strings.clone(name)
			state.slots[p] = Dock_Slot {
				weight = 0.5,
			}
			return p, true
		}
	}
	return .Custom_0, false
}

dock_remove_named :: proc(state: ^Dock_State, p: Dock_Panel) {
	if p < .Custom_0 {return}
	delete(state.names[p])
	state.names[p] = ""
	state.slots[p] = {}
}

dock_release_names :: proc(state: ^Dock_State) {
	for p in Dock_Panel {if p >= .Custom_0 {dock_remove_named(state, p)}}
}

dock_move_panel :: proc(
	state: ^Dock_State,
	panel: Dock_Panel,
	anchor: Dock_Anchor,
	full_span := false,
) {
	highest: i32 = 0
	for p in Dock_Panel {
		other := state.slots[p]
		if p != panel && other.visible && other.anchor == anchor {
			highest = max(highest, other.order)
		}
	}

	slot := &state.slots[panel]
	slot.anchor = anchor
	slot.order = highest + 1
	slot.visible = true
	slot.full_span = full_span && dock_anchor_row(anchor) != .Middle
}


dock_swap_panels :: proc(state: ^Dock_State, a, b: Dock_Panel) {
	sa := &state.slots[a]
	sb := &state.slots[b]
	sa.anchor, sb.anchor = sb.anchor, sa.anchor
	sa.order, sb.order = sb.order, sa.order
	sa.full_span, sb.full_span = sb.full_span, sa.full_span
}

dock_set_visible :: proc(state: ^Dock_State, panel: Dock_Panel, visible: bool) {
	state.slots[panel].visible = visible
}


dock_set_weight :: proc(state: ^Dock_State, panel: Dock_Panel, weight: f32) {
	state.slots[panel].weight = max(weight, 0.01)
}


dock_set_column_weight :: proc(state: ^Dock_State, col: Dock_Column, weight: f32) {
	state.column_weight[col] = max(weight, 0.01)
}


dock_hit_test :: proc(x, y, w, h: f32, mouse_x, mouse_y: f32) -> (anchor: Dock_Anchor, ok: bool) {
	if w <= 0 || h <= 0 {
		return
	}

	rx := (mouse_x - x) / w
	ry := (mouse_y - y) / h
	if rx < 0 || rx > 1 || ry < 0 || ry > 1 {
		return
	}

	col := clamp(int(rx * 3), 0, 2)
	row := clamp(int(ry * 3), 0, 2)
	return dock_make_anchor(Dock_Column(col), Dock_Row(row)), true
}


dock_anchor_rect :: proc(anchor: Dock_Anchor, x, y, w, h: f32) -> (rx, ry, rw, rh: f32) {
	cw, ch := w / 3, h / 3
	return x + f32(int(dock_anchor_column(anchor))) * cw,
		y + f32(int(dock_anchor_row(anchor))) * ch,
		cw,
		ch
}

dock_resize_pair :: proc(
	first, second: ^f32,
	first_size, second_size, delta, minimum: f32,
) -> bool {
	total := first_size + second_size
	if total <= 0 {return false}
	limit := min(minimum, total * 0.5)
	next := clamp(first_size + delta, limit, total - limit)
	if abs(next - first_size) < 0.01 {return false}

	weight := first^ + second^
	first^ = weight * next / total
	second^ = weight - first^
	return true
}

dock_resize_panel :: proc(
	state: ^Dock_State,
	config: ^Editor_Layout_Config,
	panel: Dock_Panel,
	width, height, x, y, w, h: f32,
	edges: int,
) -> bool {
	slot := state.slots[panel]
	if !slot.visible || panel == .Topbar {return false}

	rects: [Dock_Panel]Layout_Coordinate
	Editor_Layout_Compute_Docked(config, state, width, height, &rects)
	rect := rects[panel]
	px, py := rect.Position.X_Offset, rect.Position.Y_Offset
	pw, ph := rect.Size.X_Offset, rect.Size.Y_Offset
	if pw <= 0 || ph <= 0 {return false}

	col := dock_anchor_column(slot.anchor)
	row := dock_anchor_row(slot.anchor)
	band := slot.full_span && row != .Middle
	changed := false

	if edges & 3 != 0 {
		left := edges & 1 != 0
		delta := left ? x - px : x + w - px - pw
		neighbor: Dock_Panel
		found := false
		distance: f32 = 1e9

		for other in Dock_Panel {
			if other == panel || !state.slots[other].visible {continue}
			os := state.slots[other]
			orow := dock_anchor_row(os.anchor)
			ocol := dock_anchor_column(os.anchor)
			oband := os.full_span && orow != .Middle
			if band {
				if !oband || orow != row {continue}
			} else if oband || ocol == col {
				continue
			}

			r := rects[other]
			ox, ow := r.Position.X_Offset, r.Size.X_Offset
			if ow <= 0 {continue}
			gap := left ? px - ox - ow : ox - px - pw
			if gap >= -0.01 && gap < distance {
				neighbor, found, distance = other, true, gap
			}
		}

		if found {
			ow := rects[neighbor].Size.X_Offset
			a, b: ^f32
			if band {
				a, b = &state.slots[panel].weight, &state.slots[neighbor].weight
			} else {
				a, b =
					&state.column_weight[col],
					&state.column_weight[dock_anchor_column(state.slots[neighbor].anchor)]
			}
			changed = dock_resize_pair(a, b, pw, ow, left ? -delta : delta, 160) || changed
		}
	}

	if edges & 12 != 0 {
		top := edges & 4 != 0
		delta := top ? y - py : y + h - py - ph

		if band {
			if (row == .Top && !top) || (row == .Bottom && top) {
				fixed := false
				for other in Dock_Panel {
					os := state.slots[other]
					if os.visible &&
					   os.full_span &&
					   dock_anchor_row(os.anchor) == row &&
					   dock_panel_fixed_height(other, config) > 0 {fixed = true}
				}
				if !fixed && height > 0 {
					other_row := row == .Top ? Dock_Row.Bottom : Dock_Row.Top
					reserved: f32
					for other in Dock_Panel {
						os := state.slots[other]
						if os.visible && os.full_span && dock_anchor_row(os.anchor) == other_row {
							reserved = max(reserved, rects[other].Size.Y_Offset)
						}
					}
					available := max(0, height - reserved - config.P * 4)
					limit := min(f32(94), available * 0.5)
					next := clamp(
						ph + (top ? -delta : delta),
						limit,
						max(limit, available - limit),
					)
					if abs(next - ph) >= 0.01 {
						state.band_size[row] = next / height
						changed = true
					}
				}
			}
		} else {
			neighbor: Dock_Panel
			found := false
			distance: f32 = 1e9

			for other in Dock_Panel {
				if other == panel || !state.slots[other].visible {continue}
				os := state.slots[other]
				if os.full_span || dock_anchor_column(os.anchor) != col {continue}
				if dock_panel_fixed_height(other, config) > 0 {continue}
				r := rects[other]
				oy, oh := r.Position.Y_Offset, r.Size.Y_Offset
				if oh <= 0 {continue}
				gap := top ? py - oy - oh : oy - py - ph
				if gap >= -0.01 && gap < distance {
					neighbor, found, distance = other, true, gap
				}
			}

			if found {
				changed =
					dock_resize_pair(
						&state.slots[panel].weight,
						&state.slots[neighbor].weight,
						ph,
						rects[neighbor].Size.Y_Offset,
						top ? -delta : delta,
						94,
					) ||
					changed
			}
		}
	}
	return changed
}
