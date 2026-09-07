package main

import "core:fmt"
import vector3 "engine/datatypes"
import renderer "engine/renderer"
import classes "engine/classes"
import sdl3 "vendor:sdl3"

main :: proc() {
    rendererObject := renderer.RendererObject{
        KeyDown = proc(scancode: sdl3.Scancode) {
            fmt.println("Key down: ", scancode)
        },
        KeyUp = proc(scancode: sdl3.Scancode) {
            fmt.println("Key up: ", scancode)
        },
        MouseClick = proc(button: sdl3.MouseButtonEvent) {
            fmt.println("Mouse button clicked: ", button.button)
        },
        OnClose = proc() {
            fmt.println("Window closed")
        },
    }
    renderer.init("Kinemium Engine", 800, 600, rendererObject)

    position := vector3.Vector3{
        x = 1.0,
        y = 2.0,
        z = 3.0,
    }
    vector3.Multiply(position, 2.0)
    fmt.println(position)
}