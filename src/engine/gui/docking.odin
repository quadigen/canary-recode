package gui

import datatypes "../datatypes"

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
	Viewport, // also drives CodeEditor
	Explorer,
	Inspector,
	Output,
}

Dock_Slot :: struct {
	anchor:    Dock_Anchor,
	order:     i32, // tie-break between panels in the same cell
	weight:    f32, // share of the space along the stacking axis
	visible:   bool,
	full_span: bool, // Top/Bottom rows only: span every column
}

Dock_State :: struct {
	slots:         [Dock_Panel]Dock_Slot,
	column_weight: [Dock_Column]f32, // relative column widths (empty ones collapse)
	band_size:     [Dock_Row]f32, // window-height fraction for full_span bars with no fixed height
}

// Reproduces the original hardcoded layout:
//   full-width Topbar, then [Viewport over Output] | [Explorer over Inspector]
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

dock_panel_id :: proc(p: Dock_Panel) -> string {
	switch p {
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

// The topbar is the only panel with a fixed height (config.TopH).
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

// ---------------------------------------------------------------------------
// Lay out one group of panels inside a rect.
//   vertical = true  -> a column (stacked top to bottom, ordered by row)
//   vertical = false -> a full-width bar (left to right, ordered by column)
// ---------------------------------------------------------------------------

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
				items[n] = layout_create_item(dock_panel_id(p), w, fixed, cfg)
			} else {
				items[n] = layout_create_item(dock_panel_id(p), w, 0, cfg)
			}
		} else {
			items[n] = layout_create_item(dock_panel_id(p), 0, h, cfg)
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

	// layout_calculate sorts the slice, so map results back by id.
	for p in members {
		if it := layout_find(items[:n], dock_panel_id(p)); it != nil {
			out[p] = layout_to_coordinate(it, x, y)
		}
	}
}

// ---------------------------------------------------------------------------
// Full editor layout. `bounds` is the whole window rect, which is what you
// want for drop-target hit testing (every window can go anywhere).
// ---------------------------------------------------------------------------

Editor_Layout_Compute_Docked :: proc(
	config: ^Editor_Layout_Config,
	dock: ^Dock_State,
	width, height: f32,
) -> (
	coords: Editor_Layout_Coordinates,
	bounds: Layout_Coordinate,
) {
	assert(config != nil && dock != nil)
	P := config.P

	// 1. Bucket visible panels into columns and the two full-width bars.
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

	// 2. Root column: [top bar] [body] [bottom bar]
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

	// 3. Bars
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

	// 4. Body row: one item per non-empty column
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
				config.Padding, // same top/bottom padding the old side columns had
				true,
				&panels,
			)
		}
	}

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

// ---------------------------------------------------------------------------
// Editing the layout
// ---------------------------------------------------------------------------

// Move a panel to an anchor, appended after whatever is already in that cell.
// full_span only applies to the Top/Bottom rows.
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

// Swap the positions of two panels (weights stay with their panel).
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

// Size of a panel relative to the others in its column (or bar).
dock_set_weight :: proc(state: ^Dock_State, panel: Dock_Panel, weight: f32) {
	state.slots[panel].weight = max(weight, 0.01)
}

// Width of a column relative to the other non-empty columns.
dock_set_column_weight :: proc(state: ^Dock_State, col: Dock_Column, weight: f32) {
	state.column_weight[col] = max(weight, 0.01)
}

// ---------------------------------------------------------------------------
// Drag & drop: which of the 9 cells is the mouse over?
// Pass the `bounds` returned by Editor_Layout_Compute_Docked.
// ---------------------------------------------------------------------------

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

// Rect of an anchor cell, for drawing the drop highlight while dragging.
dock_anchor_rect :: proc(anchor: Dock_Anchor, x, y, w, h: f32) -> (rx, ry, rw, rh: f32) {
	cw, ch := w / 3, h / 3
	return x + f32(int(dock_anchor_column(anchor))) * cw,
		y + f32(int(dock_anchor_row(anchor))) * ch,
		cw,
		ch
}
