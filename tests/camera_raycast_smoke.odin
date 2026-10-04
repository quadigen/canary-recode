package main

// Smoke test for Camera screen<->world projection. The camera projection
// helpers are the script-visible counterpart of the render viewport: a ray
// built from ScreenPointToRay has to agree with what the renderer actually
// drew, and WorldToViewportPoint has to invert it.
//
// These used to be broken in three independent ways, all invisible until the
// viewport was non-square or non-default:
//   - viewport_width/viewport_height were never assigned from the renderer, so
//     every projection divided by a clamped half-extent of 1.
//   - the normalized-device offsets were used as raw camera-space deltas,
//     dropping the field-of-view tangent and the aspect ratio.
//   - ScreenPointToRay based its ray on the camera's backward axis, so rays
//     pointed away from whatever the camera was looking at.
//
// The headless environment has no Filament context, so nothing here can assert
// pixels; what it can prove is that the projection contract matches the
// renderer's 60-degree perspective and that the viewport tracks the renderer.

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import renderer "../src/engine/renderer"
import vm "../src/engine/vm"

STEP_DT :: f32(1.0 / 60.0)

// Deliberately non-square: an aspect-blind projection passes at 800x600 and
// fails here.
VIEWPORT_WIDTH :: i32(1600)
VIEWPORT_HEIGHT :: i32(900)

RESIZED_WIDTH :: i32(640)
RESIZED_HEIGHT :: i32(480)

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic(name)
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	view: renderer.RendererObject
	engine_runtime.Environment_Init(&environment, &script_vm, &view)

	view.HasViewportRect = true
	view.ViewportRect = {0, 0, VIEWPORT_WIDTH, VIEWPORT_HEIGHT}

	run_script(&script_vm, `
local camera = workspace.CurrentCamera
assert(camera and camera:IsA("Camera"), "workspace must provide a CurrentCamera")
-- Identity CFrame looks down -Z, which is the axis every expectation below is
-- written against.
camera.CFrame = CFrame.new(0, 0, 0)
camera.CameraType = Enum.CameraType.Scriptable
`, "camera_raycast_setup")

	// The viewport dimensions are refreshed by Camera_Step. Scriptable returns
	// early, but only after the viewport sync, so this still has to take effect.
	for _ in 0 ..< 3 {
		engine_runtime.Environment_Render_3D(&environment, &script_vm, STEP_DT)
	}

	run_script(&script_vm, `
local camera = workspace.CurrentCamera

local TOLERANCE = 1.0e-4
-- math.tan(math.radians(60) / 2). math.radians is absent from this VM's math
-- library, so the renderer-matched constant is written out. The renderer builds
-- its perspective with a fixed 60-degree vertical field of view
-- (Kine_Filament_SetCameraPerspective in src/engine/renderer/main.odin,
-- mirrored by MOUSE_FIELD_OF_VIEW in src/engine/services/Mouse.odin).
local TANGENT = 0.5773502691896258

-- The camera has to know the viewport it is projecting into.
local viewport = camera.ViewportSize
local width, height = viewport.X, viewport.Y
assert(
	width == 1600 and height == 900,
	"ViewportSize must track the renderer, got " .. width .. "x" .. height
)
local aspect = width / height

-- The center of the viewport projects to the camera's forward axis.
local center = camera:ScreenPointToRay(width / 2, height / 2)
assert(
	vector.magnitude(center.Origin) < TOLERANCE,
	"ray origin must be the camera position, got " .. tostring(center.Origin)
)
assert(
	vector.magnitude(center.Direction - Vector3.new(0, 0, -1)) < TOLERANCE,
	"center ray must point down -Z, got " .. tostring(center.Direction)
)

-- Rays must leave the camera forward, never back through it.
local top = camera:ScreenPointToRay(width / 2, 0)
local bottom = camera:ScreenPointToRay(width / 2, height)
local left = camera:ScreenPointToRay(0, height / 2)
local right = camera:ScreenPointToRay(width, height / 2)

for name, ray in pairs({
	top = top, bottom = bottom, left = left, right = right, center = center,
}) do
	assert(ray.Direction.Z < 0, name .. " ray must keep a forward component, got " .. tostring(ray.Direction))
end

assert(top.Direction.Y > 0, "top edge ray must tilt up, got " .. tostring(top.Direction))
assert(bottom.Direction.Y < 0, "bottom edge ray must tilt down")
assert(left.Direction.X < 0, "left edge ray must tilt left, got " .. tostring(left.Direction))
assert(right.Direction.X > 0, "right edge ray must tilt right")

-- The edge rays must land exactly on the perspective frustum boundary: the
-- vertical half-angle is atan(TANGENT), and the horizontal one is widened by
-- the aspect ratio.
local top_slope = top.Direction.Y / -top.Direction.Z
local bottom_slope = -bottom.Direction.Y / -bottom.Direction.Z
local left_slope = -left.Direction.X / -left.Direction.Z
local right_slope = right.Direction.X / -right.Direction.Z

assert(
	math.abs(top_slope - TANGENT) < TOLERANCE and math.abs(bottom_slope - TANGENT) < TOLERANCE,
	"vertical edge slope must equal tan(fov/2), got " .. top_slope .. " and " .. bottom_slope
)
assert(
	math.abs(left_slope - TANGENT * aspect) < TOLERANCE and
	math.abs(right_slope - TANGENT * aspect) < TOLERANCE,
	"horizontal edge slope must equal tan(fov/2) * aspect, got " ..
		left_slope .. " and " .. right_slope
)

-- The diagonal corners must agree with both axes at once.
local corner = camera:ScreenPointToRay(width, 0)
assert(
	math.abs(corner.Direction.X / -corner.Direction.Z - TANGENT * aspect) < TOLERANCE and
	math.abs(corner.Direction.Y / -corner.Direction.Z - TANGENT) < TOLERANCE,
	"corner ray must satisfy both frustum slopes, got " .. tostring(corner.Direction)
)

-- WorldToViewportPoint has to invert ScreenPointToRay.
local sample_points = {
	Vector2.new(width / 2, height / 2),
	Vector2.new(width / 4, height / 4),
	Vector2.new(width * 3 / 4, height * 3 / 4),
	Vector2.new(10, height - 10),
	Vector2.new(width - 10, 20),
}

for _, point in ipairs(sample_points) do
	local ray = camera:ScreenPointToRay(point.X, point.Y)
	local world = ray.Origin + ray.Direction * 250
	local on_screen, sx, sy = camera:WorldToViewportPoint(world)
	assert(on_screen, "a point cast from inside the frustum must project on screen")
	assert(
		math.abs(sx - point.X) < 1.0e-2 and math.abs(sy - point.Y) < 1.0e-2,
		"round trip drifted: cast " .. point.X .. "," .. point.Y ..
			" but projected " .. sx .. "," .. sy
	)
end

-- Anything behind the camera, or past the frustum edges, is off screen.
local behind = camera:WorldToViewportPoint(Vector3.new(0, 0, 10))
assert(not behind, "a point behind the camera must not project on screen")

local far_behind = camera:WorldToViewportPoint(Vector3.new(0, 0, 1000))
assert(not far_behind, "a point well behind the camera is off screen")

local wide_off = camera:WorldToViewportPoint(Vector3.new(10000, 0, -250))
assert(not wide_off, "a point far outside the horizontal frustum is off screen")

local tall_off = camera:WorldToViewportPoint(Vector3.new(0, 10000, -250))
assert(not tall_off, "a point far outside the vertical frustum is off screen")

print("RAYCAST_VIEWPORT_OK")
`, "camera_raycast_projection")

	// Shrink the window and confirm the camera picks the new size up.
	view.ViewportRect = {0, 0, RESIZED_WIDTH, RESIZED_HEIGHT}
	for _ in 0 ..< 3 {
		engine_runtime.Environment_Render_3D(&environment, &script_vm, STEP_DT)
	}

	run_script(&script_vm, `
local camera = workspace.CurrentCamera
local TOLERANCE = 1.0e-4
local TANGENT = 0.5773502691896258

local viewport = camera.ViewportSize
local width, height = viewport.X, viewport.Y
assert(
	width == 640 and height == 480,
	"ViewportSize must follow a resize, got " .. width .. "x" .. height
)
local aspect = width / height

local center = camera:ScreenPointToRay(width / 2, height / 2)
assert(
	vector.magnitude(center.Direction - Vector3.new(0, 0, -1)) < TOLERANCE,
	"center ray must stay down -Z after a resize"
)

-- The new aspect ratio has to take effect, not just the new pixel count.
local right = camera:ScreenPointToRay(width, height / 2)
assert(
	math.abs(right.Direction.X / -right.Direction.Z - TANGENT * aspect) < TOLERANCE,
	"horizontal extent must use the resized aspect ratio"
)

local world = center.Origin + center.Direction * 100
local on_screen, sx, sy = camera:WorldToViewportPoint(world)
assert(
	on_screen and math.abs(sx - 320) < 1.0e-2 and math.abs(sy - 240) < 1.0e-2,
	"round trip drifted after resize: " .. sx .. "," .. sy
)

print("RAYCAST_RESIZE_OK")
`, "camera_raycast_resize")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("CAMERA_RAYCAST_SMOKE_PASSED")
}
