#+build js
package platform

Window :: struct {}
Cursor :: struct { kind: SystemCursor }

Scancode :: enum i32 {
	UNKNOWN = 0,
	A = 4, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
	_1 = 30, _2, _3, _4, _5, _6, _7, _8, _9, _0,
	RETURN = 40, ESCAPE, BACKSPACE, TAB, SPACE, MINUS, EQUALS, LEFTBRACKET, RIGHTBRACKET,
	BACKSLASH, NONUSHASH, SEMICOLON, APOSTROPHE, GRAVE, COMMA, PERIOD, SLASH, CAPSLOCK,
	F1 = 58, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
	PRINTSCREEN = 70, SCROLLLOCK, PAUSE, INSERT, HOME, PAGEUP, DELETE, END, PAGEDOWN,
	RIGHT, LEFT, DOWN, UP, NUMLOCKCLEAR,
	KP_DIVIDE, KP_MULTIPLY, KP_MINUS, KP_PLUS, KP_ENTER, KP_1, KP_2, KP_3, KP_4, KP_5,
	KP_6, KP_7, KP_8, KP_9, KP_0, KP_PERIOD, APPLICATION, POWER, KP_EQUALS,
	F13, F14, F15, F16, F17, F18, F19, F20, F21, F22, F23, F24,
	VOLUMEUP = 128, VOLUMEDOWN,
	LCTRL = 224, LSHIFT, LALT, LGUI, RCTRL, RSHIFT, RALT, RGUI,
}

KeymodFlag :: enum u16 {
	LSHIFT = 0, RSHIFT = 1, LEVEL5 = 2, LCTRL = 6, RCTRL = 7,
	LALT = 8, RALT = 9, LGUI = 10, RGUI = 11, NUM = 12,
}
Keymod :: distinct bit_set[KeymodFlag; u16]

MouseButtonFlag :: enum u32 { LEFT, MIDDLE, RIGHT, X1, X2 }
MouseButtonFlags :: distinct bit_set[MouseButtonFlag; u32]

SystemCursor :: enum i32 {
	DEFAULT, TEXT, WAIT, CROSSHAIR, PROGRESS, NWSE_RESIZE, NESW_RESIZE,
	EW_RESIZE, NS_RESIZE, MOVE, NOT_ALLOWED, POINTER, NW_RESIZE, N_RESIZE,
	NE_RESIZE, E_RESIZE, SE_RESIZE, S_RESIZE, SW_RESIZE, W_RESIZE,
}

SystemTheme :: enum i32 { UNKNOWN, LIGHT, DARK }

EventType :: enum i32 {
	UNKNOWN,
	QUIT,
	WINDOW_CLOSE_REQUESTED,
	WINDOW_DESTROYED,
	WINDOW_MINIMIZED,
	WINDOW_RESTORED,
	WINDOW_RESIZED,
	WINDOW_PIXEL_SIZE_CHANGED,
	KEY_DOWN,
	KEY_UP,
	TEXT_INPUT,
	MOUSE_MOTION,
	MOUSE_BUTTON_DOWN,
	MOUSE_BUTTON_UP,
	MOUSE_WHEEL,
}

KeyboardEvent :: struct {
	scancode: Scancode,
	mod:      Keymod,
	repeat:   bool,
}

TextInputEvent :: struct { text: cstring }
MouseMotionEvent :: struct { state: MouseButtonFlags, x, y, xrel, yrel: f32 }
MouseButtonEvent :: struct { button: u8, down: bool, clicks: u8, x, y: f32 }
MouseWheelEvent :: struct { x, y, mouse_x, mouse_y: f32 }

Event :: struct {
	type:   EventType,
	key:    KeyboardEvent,
	text:   TextInputEvent,
	motion: MouseMotionEvent,
	button: MouseButtonEvent,
	wheel:  MouseWheelEvent,
}

INIT_VIDEO: u32 = 1
INIT_EVENTS: u32 = 2
WINDOW_RESIZABLE: u64 = 1
WINDOW_VULKAN: u64 = 0

BUTTON_LEFT   :: u8(1)
BUTTON_MIDDLE :: u8(2)
BUTTON_RIGHT  :: u8(3)

foreign import "kinemium_platform"

@(default_calling_convention="c")
foreign kinemium_platform {
	host_poll_event       :: proc() -> i32 ---
	host_event_scancode   :: proc() -> i32 ---
	host_event_modifiers  :: proc() -> u16 ---
	host_event_repeat     :: proc() -> bool ---
	host_event_button     :: proc() -> u8 ---
	host_event_clicks     :: proc() -> u8 ---
	host_event_x          :: proc() -> f32 ---
	host_event_y          :: proc() -> f32 ---
	host_event_dx         :: proc() -> f32 ---
	host_event_dy         :: proc() -> f32 ---
	host_copy_event_text  :: proc(destination: ^u8, capacity: i32) -> i32 ---
	host_width            :: proc() -> i32 ---
	host_height           :: proc() -> i32 ---
	host_dpi_scale        :: proc() -> f32 ---
	host_now_ns           :: proc() -> u64 ---
	host_focused          :: proc() -> bool ---
	host_system_theme     :: proc() -> i32 ---
	host_mouse_x          :: proc() -> f32 ---
	host_mouse_y          :: proc() -> f32 ---
	host_mouse_dx         :: proc() -> f32 ---
	host_mouse_dy         :: proc() -> f32 ---
	host_mouse_buttons    :: proc() -> u32 ---
	host_key_down         :: proc(scancode: i32) -> bool ---
	host_modifiers        :: proc() -> u16 ---
	host_set_relative     :: proc(enabled: bool) ---
	host_show_cursor      :: proc(visible: bool) ---
	host_warp_mouse       :: proc(x, y: f32) ---
	host_set_cursor       :: proc(kind: i32) ---
	host_text_input       :: proc(enabled: bool) ---
	host_set_clipboard    :: proc(text: cstring) -> bool ---
	host_copy_clipboard   :: proc(destination: ^u8, capacity: i32) -> i32 ---
	host_debug_phase      :: proc(code: i32) ---
}

DebugPhase :: proc(code: i32) { host_debug_phase(code) }

window: Window
cursor: Cursor
keyboard_state: [512]bool
event_text: [4096]u8
clipboard_text: [4096]u8

Init :: proc(flags: u32) -> bool { return true }
Quit :: proc() {}
CreateWindow :: proc(title: cstring, width, height: i32, flags: u64) -> ^Window { return &window }
DestroyWindow :: proc(value: ^Window) {}
GetWindowSizeInPixels :: proc(value: ^Window, width, height: ^i32) -> bool {
	if width != nil { width^ = host_width() }
	if height != nil { height^ = host_height() }
	return true
}

PollEvent :: proc(event: ^Event) -> bool {
	if event == nil { return false }
	event_type := EventType(host_poll_event())
	if event_type == .UNKNOWN { return false }
	event^ = Event{type = event_type}
	switch event_type {
	case .KEY_DOWN, .KEY_UP:
		event.key.scancode = Scancode(host_event_scancode())
		event.key.mod = transmute(Keymod)host_event_modifiers()
		event.key.repeat = host_event_repeat()
	case .TEXT_INPUT:
		_ = host_copy_event_text(&event_text[0], len(event_text))
		event.text.text = cstring(&event_text[0])
	case .MOUSE_MOTION:
		event.motion = {x = host_event_x(), y = host_event_y(), xrel = host_event_dx(), yrel = host_event_dy(), state = transmute(MouseButtonFlags)host_mouse_buttons()}
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		event.button = {button = host_event_button(), down = event_type == .MOUSE_BUTTON_DOWN, clicks = host_event_clicks(), x = host_event_x(), y = host_event_y()}
	case .MOUSE_WHEEL:
		event.wheel = {x = host_event_dx(), y = host_event_dy(), mouse_x = host_event_x(), mouse_y = host_event_y()}
	case .UNKNOWN, .QUIT, .WINDOW_CLOSE_REQUESTED, .WINDOW_DESTROYED, .WINDOW_MINIMIZED,
	     .WINDOW_RESTORED, .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED:
	}
	return true
}

GetTicksNS :: proc() -> u64 { return host_now_ns() }
Delay :: proc(milliseconds: u32) {}
GetKeyboardFocus :: proc() -> ^Window { return host_focused() ? &window : nil }
GetMouseFocus :: proc() -> ^Window { return host_focused() ? &window : nil }
GetWindowDisplayScale :: proc(value: ^Window) -> f32 { return host_dpi_scale() }
GetSystemTheme :: proc() -> SystemTheme { return SystemTheme(host_system_theme()) }

GetMouseState :: proc(x, y: ^f32) -> MouseButtonFlags {
	if x != nil { x^ = host_mouse_x() }
	if y != nil { y^ = host_mouse_y() }
	return transmute(MouseButtonFlags)host_mouse_buttons()
}
GetRelativeMouseState :: proc(x, y: ^f32) -> MouseButtonFlags {
	if x != nil { x^ = host_mouse_dx() }
	if y != nil { y^ = host_mouse_dy() }
	return transmute(MouseButtonFlags)host_mouse_buttons()
}
GetKeyboardState :: proc(count: ^i32) -> [^]bool {
	if count != nil { count^ = len(keyboard_state) }
	for &value, index in keyboard_state { value = host_key_down(i32(index)) }
	return &keyboard_state[0]
}
GetModState :: proc() -> Keymod { return transmute(Keymod)host_modifiers() }
SetWindowRelativeMouseMode :: proc(value: ^Window, enabled: bool) -> bool { host_set_relative(enabled); return true }
ShowCursor :: proc() -> bool { host_show_cursor(true); return true }
HideCursor :: proc() -> bool { host_show_cursor(false); return true }
WarpMouseInWindow :: proc(value: ^Window, x, y: f32) { host_warp_mouse(x, y) }
CreateSystemCursor :: proc(kind: SystemCursor) -> ^Cursor { cursor.kind = kind; return &cursor }
SetCursor :: proc(value: ^Cursor) -> bool { if value != nil { host_set_cursor(i32(value.kind)) }; return true }
StartTextInput :: proc(value: ^Window) -> bool { host_text_input(true); return true }
StopTextInput :: proc(value: ^Window) -> bool { host_text_input(false); return true }
SetClipboardText :: proc(text: cstring) -> bool { return host_set_clipboard(text) }
GetClipboardText :: proc() -> rawptr {
	_ = host_copy_clipboard(&clipboard_text[0], len(clipboard_text))
	return rawptr(&clipboard_text[0])
}
strlen :: proc(text: cstring) -> uintptr {
	length: uintptr
	if text == nil { return 0 }
	bytes := cast([^]u8)text
	for bytes[length] != 0 { length += 1 }
	return length
}
free :: proc(value: rawptr) {}
