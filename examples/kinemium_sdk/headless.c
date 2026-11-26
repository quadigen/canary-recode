#include "kinemium.h"
#include <stdio.h>
#include <stdint.h>

static int sdk_failed(Kinemium_Context *ctx, const char *step) {
    char error[512] = {0};
    Kinemium_CopyLastError(ctx, error, sizeof(error));
    fprintf(stderr, "%s failed: %s\n", step, error);
    return 1;
}

static bool native_multiply(void *user_data, uint32_t argument_count,
                            const Kinemium_Value *arguments, Kinemium_Value *output) {
    (void)user_data;
    if (argument_count != 2 || !arguments || !output ||
        arguments[0].kind != KINEMIUM_VALUE_NUMBER ||
        arguments[1].kind != KINEMIUM_VALUE_NUMBER) {
        return false;
    }
    output->kind = KINEMIUM_VALUE_NUMBER;
    output->number = arguments[0].number * arguments[1].number;
    return true;
}

int main(void) {
    printf("Kinemium ABI v%u\n", Kinemium_GetABIVersion());
    Kinemium_Context *ctx = Kinemium_CreateWithMode(KINEMIUM_MODE_STANDALONE);
    if (!ctx) {
        fprintf(stderr, "Could not create Kinemium context\n");
        return 1;
    }

    int exit_status = 0;
    Kinemium_Handle workspace = Kinemium_HandleService(ctx, "Workspace");
    Kinemium_Handle part = Kinemium_HandleCreateInstance(ctx, "Part");
    if (!workspace || !part) {
        exit_status = sdk_failed(ctx, "create scene");
        goto finish;
    }

    if (!Kinemium_HandleSetParent(ctx, part, workspace) ||
        !Kinemium_HandleSetDynamicString(ctx, part, "Name", "NativeCube") ||
        !Kinemium_HandleSetDynamicBoolean(ctx, part, "Anchored", true) ||
        !Kinemium_HandleSetDynamicVector3(ctx, part, "Position", (Kinemium_Vector3){0.0, 5.0, 0.0}) ||
        !Kinemium_HandleSetDynamicVector3(ctx, part, "Size", (Kinemium_Vector3){4.0, 4.0, 4.0}) ||
        !Kinemium_HandleSetDynamicNumber(ctx, part, "Transparency", 0.15)) {
        exit_status = sdk_failed(ctx, "set properties");
        goto finish;
    }

    Kinemium_Vector3 position = {0};
    if (!Kinemium_HandleGetDynamicVector3(ctx, part, "Position", &position)) {
        exit_status = sdk_failed(ctx, "read position");
        goto finish;
    }

    char name[128] = {0};
    Kinemium_HandleCopyFullName(ctx, part, name, sizeof(name));
    printf("%s at %.1f %.1f %.1f\n", name, position.x, position.y, position.z);

    Kinemium_Handle clone = Kinemium_HandleClone(ctx, part);
    if (clone) {
        Kinemium_HandleSetDynamicString(ctx, clone, "Name", "NativeCubeCopy");
        Kinemium_HandleSetParent(ctx, clone, workspace);
        printf("Clone created: %llu\n", (unsigned long long)clone);
    }

    if (!Kinemium_PhysicsSetGravity(ctx, 196.2)) {
        exit_status = sdk_failed(ctx, "set gravity");
        goto finish;
    }

    Kinemium_Value invoke_arg = {.kind = KINEMIUM_VALUE_STRING, .text = "Part"};
    Kinemium_Value invoke_result = {0};
    if (!Kinemium_Invoke(ctx, part, "IsA", &invoke_arg, 1, &invoke_result, NULL, 0) ||
        invoke_result.kind != KINEMIUM_VALUE_BOOLEAN || !invoke_result.boolean) {
        exit_status = sdk_failed(ctx, "invoke IsA");
        goto finish;
    }

    if (!Kinemium_RegisterNativeFunction(ctx, "nativeMultiply", native_multiply, NULL) ||
        !Kinemium_SetGlobalInstance(ctx, "nativePart", part) ||
        !Kinemium_RunLuau(ctx, "assert(nativePart.Name == 'NativeCube' and nativeMultiply(6, 7) == 42)")) {
        exit_status = sdk_failed(ctx, "Luau integration");
        goto finish;
    }

    for (int frame = 0; frame < 4; ++frame) {
        if (!Kinemium_Tick(ctx, 1.0f / 60.0f)) {
            exit_status = sdk_failed(ctx, "frame update");
            goto finish;
        }
    }

    Kinemium_RaycastHit hit = {0};
    if (Kinemium_Raycast(ctx,
                       (Kinemium_Vector3){0.0, 25.0, 0.0},
                       (Kinemium_Vector3){0.0, -50.0, 0.0}, &hit)) {
        printf("Ray hit at distance %.2f, instance %llu\n",
               hit.distance, (unsigned long long)hit.instance);
    } else {
        puts("No physics ray hit in current simulation");
    }

    Kinemium_NetworkStats stats = {0};
    if (Kinemium_NetworkGetStats(ctx, &stats)) {
        printf("Network peers: %u\n", stats.peers);
    }
    puts("Kinemium SDK native example passed");

finish:
    Kinemium_Destroy(ctx);
    return exit_status;
}
