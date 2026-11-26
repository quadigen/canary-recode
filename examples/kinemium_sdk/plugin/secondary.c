#include "kinemium_plugin.h"
#include <stddef.h>

static Kinemium_Handle secondary_folder;

static bool secondary_square(void *opaque, uint32_t count,
                             const Kinemium_Value *args, Kinemium_Value *out) {
    (void)opaque;
    if (count != 1 || args[0].kind != KINEMIUM_VALUE_NUMBER || !out) {
        return false;
    }
    out->kind = KINEMIUM_VALUE_NUMBER;
    out->number = args[0].number * args[0].number;
    return true;
}

static bool secondary_load(Kinemium_Context *ctx) {
    Kinemium_Handle workspace = Kinemium_HandleService(ctx, "Workspace");
    if (!workspace) return false;
    secondary_folder = Kinemium_HandleCreateInstance(ctx, "Folder");
    if (!secondary_folder ||
        !Kinemium_HandleSetName(ctx, secondary_folder, "SecondaryPluginFolder") ||
        !Kinemium_HandleSetParent(ctx, secondary_folder, workspace)) {
        return false;
    }
    return Kinemium_RegisterLibraryFunction(ctx, "SecondaryMath", "Square", secondary_square, NULL);
}

static bool secondary_start(Kinemium_Context *ctx) {
    return Kinemium_RunLuau(ctx, "assert(SecondaryMath.Square(6) == 36)");
}

static void secondary_unload(Kinemium_Context *ctx) {
    if (secondary_folder) {
        Kinemium_HandleDestroy(ctx, secondary_folder);
        secondary_folder = 0;
    }
}

static const Kinemium_PluginDescriptor descriptor = {
    .size = sizeof(Kinemium_PluginDescriptor),
    .abi_major = KINEMIUM_PLUGIN_ABI_MAJOR,
    .abi_minor = KINEMIUM_PLUGIN_ABI_MINOR,
    .id = "native.secondary",
    .name = "Secondary Native Plugin",
    .version = "1.0.0",
    .on_load = secondary_load,
    .on_start = secondary_start,
    .on_unload = secondary_unload
};

KINEMIUM_PLUGIN_EXPORT
const Kinemium_PluginDescriptor *Kinemium_PluginEntry(void) {
    return &descriptor;
}
