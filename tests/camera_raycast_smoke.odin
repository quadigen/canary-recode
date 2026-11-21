package main


import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

STEP_DT :: f32(1.0 / 60.0)


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

	run_script(
		&script_vm,
		`
local camera = workspace.CurrentCamera
assert(camera and camera:IsA("Camera"), "workspace must provide a CurrentCamera")
-- Identity CFrame looks down -Z, which is the axis every expectation below is
-- written against.
camera.CFrame = CFrame.new(0, 0, 0)
camera.CameraType = Enum.CameraType.Scriptable
`,
		"camera_raycast_setup",
	)


	for _ in 0 ..< 3 {
		engine_runtime.Environment_Render_3D(&environment, &script_vm, STEP_DT)
	}

	run_script(
		&script_vm,
		`
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
	local projected, on_screen = camera:WorldToViewportPoint(world)
	local sx, sy = projected.X, projected.Y
	assert(on_screen == true and typeof(projected) == "Vector3", "expected (Vector3, boolean) for a point inside the frustum")
	assert(math.abs(projected.Z - (-world.Z)) < 1.0e-2, "projection must report camera-space depth")
	assert(
		math.abs(sx - point.X) < 1.0e-2 and math.abs(sy - point.Y) < 1.0e-2,
		"round trip drifted: cast " .. point.X .. "," .. point.Y ..
			" but projected " .. sx .. "," .. sy
	)
end

-- Anything behind the camera, or past the frustum edges, is off screen.
local behind_position, behind = camera:WorldToViewportPoint(Vector3.new(0, 0, 10))
assert(behind == false and behind_position == Vector3.zero, "a point behind the camera must return zero and false")

local far_behind_position, far_behind = camera:WorldToViewportPoint(Vector3.new(0, 0, 1000))
assert(far_behind == false and far_behind_position == Vector3.zero, "a point well behind the camera is off screen")

local wide_off_position, wide_off = camera:WorldToViewportPoint(Vector3.new(10000, 0, -250))
assert(wide_off == false and wide_off_position.X > width, "a point far outside the horizontal frustum is off screen")

local tall_off_position, tall_off = camera:WorldToViewportPoint(Vector3.new(0, 10000, -250))
assert(tall_off == false and tall_off_position.Y < 0, "a point far outside the vertical frustum is off screen")

print("RAYCAST_VIEWPORT_OK")
`,
		"camera_raycast_projection",
	)


	view.ViewportRect = {0, 0, RESIZED_WIDTH, RESIZED_HEIGHT}
	for _ in 0 ..< 3 {
		engine_runtime.Environment_Render_3D(&environment, &script_vm, STEP_DT)
	}

	run_script(
		&script_vm,
		`
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
local projected, on_screen = camera:WorldToViewportPoint(world)
local sx, sy = projected.X, projected.Y
assert(
	on_screen == true and math.abs(projected.Z - 100) < 1.0e-2 and math.abs(sx - 320) < 1.0e-2 and math.abs(sy - 240) < 1.0e-2,
	"round trip drifted after resize: " .. sx .. "," .. sy
)

print("RAYCAST_RESIZE_OK")
`,
		"camera_raycast_resize",
	)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("CAMERA_RAYCAST_SMOKE_PASSED")
}
