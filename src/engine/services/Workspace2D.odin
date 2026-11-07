package services
// wire:service

import "core:fmt"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"
import box2d "vendor:box2d"

Workspace2D_Class := classes.Class_Info {
	name   = "Workspace2D",
	parent = &Service_Class,
}

Workspace2D :: struct {
	using service: Service,
	call_count:    i64,
	body_map:      map[^classes.Part2D]box2d.BodyId,
	world:         box2d.WorldId,
}

Workspace2D_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Workspace2D)
	service.service = Service_Init(&Workspace2D_Class, "Workspace2D", data_model)
	service.body_map = make(map[^classes.Part2D]box2d.BodyId)

	world_def := box2d.DefaultWorldDef()
	world_def.gravity = [2]f32{0, 130}
	world_def.enableSleep = true
	world_def.workerCount = 4
	service.world = box2d.CreateWorld(world_def)

	return &service.object
}

Workspace2D_Create_Body :: proc(service: ^classes.Object, child: ^classes.Object) {
	workspace := cast(^Workspace2D)service

	if !classes.Is_A(child, "Part2D") {
		return
	}

	part := cast(^classes.Part2D)child

	if _, exists := workspace.body_map[part]; exists {
		return
	}

	size := part.absolute_size
	position := part.absolute_position

	// Create body definition with default values.
	body_def := box2d.DefaultBodyDef()

	if part.anchored {
		body_def.type = box2d.BodyType.staticBody
	} else {
		body_def.type = box2d.BodyType.dynamicBody
	}

	body_def.position = [2]f32{position.X, position.Y}

	// Create rigid body.
	body_id := box2d.CreateBody(workspace.world, body_def)

	// Create rectangular collision shape.
	polygon := box2d.MakeBox(size.X / 2, size.Y / 2)

	shape_def := box2d.DefaultShapeDef()
	shape_def.density = 1.0
	shape_def.material.friction = 0.3

	// Attach shape to body.
	shapeId := box2d.CreatePolygonShape(body_id, shape_def, polygon)

	// Store body reference.
	workspace.body_map[part] = body_id
}


Workspace2D_Render_Child :: proc(
	service: ^classes.Object,
	child: ^classes.Object,
	ctx: ^classes.Class_Step_Context,
) {
	if classes.Is_A(child, "Part2D") {
		classes.Part2D_render(child, ctx)
		Workspace2D_Create_Body(service, child)

		for descendant in child.children {
			Workspace2D_Render_Child(service, descendant, ctx)
		}
	}
}

Workspace2D_Simulate :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	workspace := cast(^Workspace2D)object

	box2d.World_Step(workspace.world, 1.0 / 60.0, 4)

	for part, body_id in workspace.body_map {
		transform := box2d.Body_GetTransform(body_id)

		if part.anchored {
			box2d.Body_SetType(body_id, box2d.BodyType.staticBody)
		} else {
			box2d.Body_SetType(body_id, box2d.BodyType.dynamicBody)
		}

		part.position = datatypes.UDim2 {
			X_Scale  = 0,
			X_Offset = transform.p[0],
			Y_Scale  = 0,
			Y_Offset = transform.p[1],
		}
	}
}

Workspace2D_Render :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	for child in object.children {
		Workspace2D_Render_Child(object, child, ctx)
	}
	Workspace2D_Simulate(object, ctx)
}

Workspace2D_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	workspace := cast(^Workspace2D)object
	box2d.DestroyWorld(workspace.world)
	free(cast(^Workspace2D)object)
}

Register_Workspace2D_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Workspace2D_Class,
		Workspace2D_construct,
		Workspace2D_destroy,
		_step = Workspace2D_Render,
		creatable = false,
	)
}
