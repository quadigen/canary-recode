#include "kinemium_runtime.h"
#include <stdio.h>
#include <stdlib.h>

/*
 * This executable has NO link-time dependency on libkinemium.
 *
 * Usage:
 *   ./kinemium_sdk_dynamic /absolute/path/to/libkinemium.so
 *   ./kinemium_sdk_dynamic /absolute/path/to/libkinemium.dylib
 *   kinemium_sdk_dynamic.exe C:\path\to\kinemium.dll
 */
int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <path-to-kinemium-shared-library>\n", argv[0]);
        return 2;
    }

    Kinemium_Runtime api = {0};
    char error[1024] = {0};
    if (!Kinemium_RuntimeOpen(&api, argv[1], error, sizeof(error))) {
        fprintf(stderr, "Could not load Kinemium: %s\n", error);
        return 1;
    }

    printf("Runtime-loaded Kinemium ABI v%u (%zu/%u API symbols resolved)\n",
           api.abi_version, api.resolved_count, KINEMIUM_RUNTIME_SYMBOL_COUNT);

    int result = 0;
    Kinemium_Context *ctx = api.CreateWithMode
        ? api.CreateWithMode(KINEMIUM_MODE_STANDALONE)
        : api.Create();

    if (!ctx) {
        fprintf(stderr, "Kinemium context creation failed\n");
        result = 1;
        goto finish;
    }

    if (!api.HandleService || !api.HandleCreateInstance ||
        !api.HandleSetParent || !api.HandleSetDynamicBoolean ||
        !api.HandleSetDynamicVector3 || !api.HandleSetDynamicString ||
        !api.RunLuau || !api.Tick) {
        fprintf(stderr, "This version of Kinemium lacks required scene APIs\n");
        result = 1;
        goto destroy_context;
    }

    Kinemium_Handle workspace = api.HandleService(ctx, "Workspace");
    Kinemium_Handle part = api.HandleCreateInstance(ctx, "Part");
    if (!workspace || !part ||
        !api.HandleSetParent(ctx, part, workspace) ||
        !api.HandleSetDynamicString(ctx, part, "Name", "RuntimeLoadedCube") ||
        !api.HandleSetDynamicBoolean(ctx, part, "Anchored", true) ||
        !api.HandleSetDynamicVector3(ctx, part, "Size", (Kinemium_Vector3){3, 3, 3}) ||
        !api.RunLuau(ctx, "assert(workspace:FindFirstChild('RuntimeLoadedCube') ~= nil)") ||
        !api.Tick(ctx, 1.0f / 60.0f)) {
        char details[512] = {0};
        if (api.CopyLastError) api.CopyLastError(ctx, details, sizeof(details));
        fprintf(stderr, "SDK scene test failed: %s\n", details);
        result = 1;
    } else {
        printf("PASS runtime-loaded SDK: created Part and ran Luau without link-time libkinemium\n");
    }

destroy_context:
    api.Destroy(ctx);
finish:
    Kinemium_RuntimeClose(&api);
    return result;
}
