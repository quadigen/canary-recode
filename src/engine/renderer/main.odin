package renderer
import sdl3 "vendor:sdl3"
import "core:strings"
import "core:fmt"
foreign import skia "kine_skia"

RendererObject :: struct {
    KeyDown:    proc(scancode: sdl3.Scancode),
    KeyUp:      proc(scancode: sdl3.Scancode),
    MouseClick: proc(button: sdl3.MouseButtonEvent),
    OnClose:    proc(),
}

init :: proc(windowName: string, width: i32, height: i32, renderer: RendererObject) {
    if !sdl3.Init(sdl3.INIT_VIDEO | sdl3.INIT_EVENTS) {
        panic("Failed to initialize SDL")
    }
    defer sdl3.Quit()

    // i genuinely dont know why this is necessary but it is
    name := strings.clone_to_cstring(windowName)
    defer delete(name)

    window := sdl3.CreateWindow(
        name,
        width,
        height,
        sdl3.WINDOW_RESIZABLE,
    )
	defer sdl3.DestroyWindow(window)

	running := true



	for running {
		event: sdl3.Event

		for sdl3.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				running = false
            case .KEY_DOWN:
                renderer.KeyDown(event.key.scancode)
            case .KEY_UP:
                renderer.KeyUp(event.key.scancode)
            case .WINDOW_DESTROYED:
                renderer.OnClose()
                running = false
            case .MOUSE_BUTTON_DOWN:
                renderer.MouseClick(event.button)
			}
		}
	}
}

close :: proc(renderer: RendererObject, running: ^bool) {
    renderer.OnClose()
    running^ = false
}