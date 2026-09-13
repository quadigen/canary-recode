#+build !js
package platform

import sdl "vendor:sdl3"

DebugPhase :: proc(code: i32) {}

Window           :: sdl.Window
Cursor           :: sdl.Cursor
Event            :: sdl.Event
Scancode         :: sdl.Scancode
MouseButtonEvent :: sdl.MouseButtonEvent
MouseButtonFlag  :: sdl.MouseButtonFlag
MouseButtonFlags :: sdl.MouseButtonFlags
SystemCursor     :: sdl.SystemCursor
SystemTheme      :: sdl.SystemTheme
MessageBoxFlags  :: sdl.MessageBoxFlags
MessageBoxFlag   :: sdl.MessageBoxFlag

INIT_VIDEO       :: sdl.INIT_VIDEO
INIT_EVENTS      :: sdl.INIT_EVENTS
WINDOW_RESIZABLE :: sdl.WINDOW_RESIZABLE
WINDOW_VULKAN    :: sdl.WINDOW_VULKAN

BUTTON_LEFT   :: sdl.BUTTON_LEFT
BUTTON_MIDDLE :: sdl.BUTTON_MIDDLE
BUTTON_RIGHT  :: sdl.BUTTON_RIGHT

GetError             :: sdl.GetError
ShowSimpleMessageBox :: sdl.ShowSimpleMessageBox

Init                       :: sdl.Init
Quit                       :: sdl.Quit
CreateWindow               :: sdl.CreateWindow
DestroyWindow              :: sdl.DestroyWindow
GetWindowSizeInPixels      :: sdl.GetWindowSizeInPixels
PollEvent                  :: sdl.PollEvent
GetTicksNS                 :: sdl.GetTicksNS
Delay                      :: sdl.Delay
GetKeyboardFocus           :: sdl.GetKeyboardFocus
GetMouseFocus              :: sdl.GetMouseFocus
GetWindowDisplayScale      :: sdl.GetWindowDisplayScale
GetSystemTheme             :: sdl.GetSystemTheme
GetMouseState              :: sdl.GetMouseState
GetRelativeMouseState      :: sdl.GetRelativeMouseState
GetKeyboardState           :: sdl.GetKeyboardState
GetModState                :: sdl.GetModState
SetWindowRelativeMouseMode :: sdl.SetWindowRelativeMouseMode
ShowCursor                 :: sdl.ShowCursor
HideCursor                 :: sdl.HideCursor
WarpMouseInWindow          :: sdl.WarpMouseInWindow
CreateSystemCursor         :: sdl.CreateSystemCursor
SetCursor                  :: sdl.SetCursor
StartTextInput             :: sdl.StartTextInput
StopTextInput              :: sdl.StopTextInput
SetClipboardText           :: sdl.SetClipboardText
GetClipboardText           :: sdl.GetClipboardText
strlen                     :: sdl.strlen
free                       :: sdl.free
