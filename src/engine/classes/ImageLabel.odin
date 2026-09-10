package classes

import "core:image"
import "core:fmt"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import kineffi "../bindings"
import strings "core:strings"
import guilib "../gui"

ImageLabel_Class := Class_Info{
    name   = "ImageLabel",
    parent = &GuiObject_Class,
}

ImageLabel :: struct {
    using gui_object: GuiObject,

    image:        string,
    stored_image: ^kineffi.KineSkiaImage,
}

ImageLabel_Init :: proc() -> ImageLabel {
    gui := GuiObject_Init()
    gui.object.class = &ImageLabel_Class

    return ImageLabel{
        gui_object = gui,
        image      = "",
        stored_image = kineffi.Kine_Skia_Image_LoadFromFile(
            strings.clone_to_cstring("C:/Users/devco/Pictures/Screenshots/Screenshot 2026-04-16 132902.png"),
        )
    }
}

ImageLabel_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
    image_label := new(ImageLabel)
    image_label^ = ImageLabel_Init()
    image_label.name = "ImageLabel"

    return &image_label.object
}

ImageLabel_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
    Object_Destroy(object)
    free(cast(^ImageLabel)object)
}

ImageLabel_get :: proc(
    L: ^vm.State,
    object: ^Object,
    datatype_registry: ^datatypes.Registry,
    enum_registry: ^enums.Registry,
    key: string,
) -> bool {
    image_label := cast(^ImageLabel)object

    switch key {
    case "Image":
        vm.PushString(L, image_label.image)

    case:
        return GuiObject_get(
            L,
            object,
            datatype_registry,
            enum_registry,
            key,
        )
    }

    return true
}

ImageLabel_set :: proc(
    L: ^vm.State,
    object: ^Object,
    datatype_registry: ^datatypes.Registry,
    enum_registry: ^enums.Registry,
    key: string,
    value_index: int,
) -> bool {
    image_label := cast(^ImageLabel)object

    switch key {
    case "Image":
        image_label.image = vm.ArgString(L, value_index)
        image_label.stored_image = kineffi.Kine_Skia_Image_LoadFromFile(
            strings.clone_to_cstring(image_label.image),
        )

    case:
        return GuiObject_set(
            L,
            object,
            datatype_registry,
            enum_registry,
            key,
            value_index,
        )
    }

    return true
}

ImageLabel_render :: proc(
    object: ^Object,
    ctx: ^Class_Step_Context,
) {
    rect, visible := GuiObject_get_rect(object, ctx)
    if !visible {
        return
    }

    // render background (does calculations a second time, TODO: fix)
    GuiObject_render(object, ctx)

    image_label := cast(^ImageLabel)object

    if image_label.stored_image != nil {
        guilib.drawImageSized(ctx.renderer.SkiaSurface, image_label.stored_image, rect)
    }
}

Register_ImageLabel :: proc(registry: ^Registry) {
    Register_Class(
        registry,
        &ImageLabel_Class,
        ImageLabel_construct,
        ImageLabel_destroy,
        get = ImageLabel_get,
        set = ImageLabel_set,
    )
}
