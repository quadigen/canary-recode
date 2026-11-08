#+build !js
package platform

import "core:fmt"
import sdl "vendor:sdl3"

DebugPhase :: proc(code: i32) {}

Window :: sdl.Window
Cursor :: sdl.Cursor
Event :: sdl.Event
Scancode :: sdl.Scancode
FingerID :: sdl.FingerID
MouseButtonEvent :: sdl.MouseButtonEvent
MouseButtonFlag :: sdl.MouseButtonFlag
MouseButtonFlags :: sdl.MouseButtonFlags
SystemCursor :: sdl.SystemCursor
SystemTheme :: sdl.SystemTheme
MessageBoxFlags :: sdl.MessageBoxFlags
MessageBoxFlag :: sdl.MessageBoxFlag
DialogFileCallback :: sdl.DialogFileCallback
ShowOpenFolderDialog :: sdl.ShowOpenFolderDialog
ShowOpenFileDialog :: sdl.ShowOpenFileDialog

INIT_VIDEO :: sdl.INIT_VIDEO
INIT_EVENTS :: sdl.INIT_EVENTS
WINDOW_RESIZABLE :: sdl.WINDOW_RESIZABLE
WINDOW_VULKAN :: sdl.WINDOW_VULKAN
WINDOW_OPENGL :: sdl.WINDOW_OPENGL

BUTTON_LEFT :: sdl.BUTTON_LEFT
BUTTON_MIDDLE :: sdl.BUTTON_MIDDLE
BUTTON_RIGHT :: sdl.BUTTON_RIGHT

GetError :: sdl.GetError
ShowSimpleMessageBox :: sdl.ShowSimpleMessageBox

Init :: sdl.Init
SetAppMetadata :: sdl.SetAppMetadata
Quit :: sdl.Quit
CreateWindow :: sdl.CreateWindow
DestroyWindow :: sdl.DestroyWindow
GetWindowSizeInPixels :: sdl.GetWindowSizeInPixels
GetWindowSize :: sdl.GetWindowSize
PollEvent :: sdl.PollEvent
GetTicksNS :: sdl.GetTicksNS
Delay :: sdl.Delay
GetKeyboardFocus :: sdl.GetKeyboardFocus
GetMouseFocus :: sdl.GetMouseFocus
GetWindowDisplayScale :: sdl.GetWindowDisplayScale
GetDisplayContentScale :: sdl.GetDisplayContentScale
GetPrimaryDisplay :: sdl.GetPrimaryDisplay
GetSystemTheme :: sdl.GetSystemTheme
GetMouseState :: sdl.GetMouseState
GetRelativeMouseState :: sdl.GetRelativeMouseState
GetKeyboardState :: sdl.GetKeyboardState
GetModState :: sdl.GetModState
SetWindowRelativeMouseMode :: sdl.SetWindowRelativeMouseMode
ShowCursor :: sdl.ShowCursor
HideCursor :: sdl.HideCursor
WarpMouseInWindow :: sdl.WarpMouseInWindow
CreateSystemCursor :: sdl.CreateSystemCursor
SetCursor :: sdl.SetCursor
StartTextInput :: sdl.StartTextInput
StopTextInput :: sdl.StopTextInput
SetClipboardText :: sdl.SetClipboardText
GetClipboardText :: sdl.GetClipboardText
strlen :: sdl.strlen
free :: sdl.free

UI_Scale: f32 = 1

Reset_UI_Scale :: proc() {
	when #config(KINE_ANDROID, false) || ODIN_OS == .JS {
		get_ui_scale_from_display()
	} else {
		UI_Scale = 1
	}
}

@(private = "file")
get_ui_scale_from_display :: proc() {
	when #config(KINE_ANDROID, false) {
		UI_SCALE_MULTIPLIER :: 0.6
		UI_SCALE_MIN :: 1
		UI_SCALE_MAX :: 3.5

		content_scale := GetDisplayContentScale(GetPrimaryDisplay())
		if content_scale > 0.0001 {
			UI_Scale = clamp(content_scale * UI_SCALE_MULTIPLIER, UI_SCALE_MIN, UI_SCALE_MAX)
		} else {
			UI_Scale = UI_SCALE_MIN
		}
	} else {
		UI_Scale = 1
	}
}


UI_Safe_Left: f32 = 0
UI_Safe_Top: f32 = 0
UI_Safe_Right: f32 = 0
UI_Safe_Bottom: f32 = 0

@(private = "file")
ui_safe_last: f32 = -1

update_ui_safe_area :: proc(window: ^sdl.Window) {
	when #config(KINE_ANDROID, false) || ODIN_OS == .JS {
		if window == nil {return}
		rect: sdl.Rect
		if sdl.GetWindowSafeArea(window, &rect) {
			UI_Safe_Left = 0
			UI_Safe_Right = 0
			UI_Safe_Bottom = 0
			UI_Safe_Top = max(f32(rect.y), 0)
			if ui_safe_last != UI_Safe_Top {
				ui_safe_last = UI_Safe_Top
				fmt.eprintf("[safe area] top=%.0f\n", UI_Safe_Top)
			}
		}
	} else {
		_ = window
	}
}
