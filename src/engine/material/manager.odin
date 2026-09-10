package materialmanager
import renderer "../renderer"
import "vendor:stb/image"
import "../vm"
import util "../util"
import "../services"
import "../signals"
import kineffi "../bindings"

Material :: struct {
    albedo: kineffi.KineFilamentTex,
    height: kineffi.KineFilamentTex,
    normal: kineffi.KineFilamentTex,
    orm: kineffi.KineFilamentTex,
}

import "base:runtime"

create_material :: proc(
    loaded: []runtime.Load_Directory_File,
    renderer: ^renderer.RendererObject,
) -> Material {
    material: Material

    for file in loaded {
        data := util.image_from_mem(file.data)

        tex := kineffi.Kine_Filament_CreateTexFromPixels(
            renderer.Filament,
            data.width,
            data.height,
            data.width * 4,
            data.pixels,
        )

        switch file.name {
        case "albedo.png", "albedo.jpg", "albedo.jpeg":
            material.albedo = tex^

        case "height.png", "height.jpg", "height.jpeg":
            material.height = tex^

        case "normal.png", "normal.jpg", "normal.jpeg":
            material.normal = tex^

        case "orm.png", "orm.jpg", "orm.jpeg":
            material.orm = tex^
        }
    }

    return material
}

init :: proc(renderer: ^renderer.RendererObject) {
    // i would've done a filesystem loop but we are in a compiled state here
    brick := create_material(#load_directory("../assets/materials/compressed/brick"), renderer)
    concrete := create_material(#load_directory("../assets/materials/compressed/concrete"), renderer)
    debug := create_material(#load_directory("../assets/materials/compressed/debug"), renderer)
    glass := create_material(#load_directory("../assets/materials/compressed/glass"), renderer)
    grass := create_material(#load_directory("../assets/materials/compressed/grass"), renderer)
    neon := create_material(#load_directory("../assets/materials/compressed/neon"), renderer)
    slate := create_material(#load_directory("../assets/materials/compressed/slate"), renderer)
    sand := create_material(#load_directory("../assets/materials/compressed/sand"), renderer)
    smoothplastic := create_material(#load_directory("../assets/materials/compressed/smoothplastic"), renderer)
    wood := create_material(#load_directory("../assets/materials/compressed/wood"), renderer)
}