package physics
import box2d "vendor:box2d"

WorldParams :: struct {
    GravityX: f32,
    GravityY: f32
}

System_Create_2D :: proc(params: WorldParams) {
    // following box2d ex
    worldDef: box2d.WorldDef = box2d.DefaultWorldDef()
    worldDef.gravity = box2d.Vec2{params.GravityX, params.GravityY}

    worldId: box2d.WorldId = box2d.CreateWorld(worldDef)
    defer box2d.DestroyWorld(worldId)
}