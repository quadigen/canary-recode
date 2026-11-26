#include "kinemium_runtime.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

/* Arguments: real_sdk, wrong_abi.so, no_abi.so, subset_abi2.so */
int main(int argc, char **argv) {
    if (argc != 5) {
        fprintf(stderr, "Usage: %s <real> <wrong-abi> <no-abi> <subset>\n", argv[0]);
        return 2;
    }
    char error[512] = {0};
    Kinemium_Runtime api = {0};

    assert(!Kinemium_RuntimeOpen(&api, "/no/such/kinemium-library-xyz.so", error, sizeof(error)));
    assert(strstr(error, "dlopen") || strstr(error, "LoadLibrary"));
    assert(api.library == NULL && api.Create == NULL);
    assert(!Kinemium_RuntimeOpen(&api, argv[2], error, sizeof(error)));
    assert(strstr(error, "incompatible ABI"));
    assert(api.library == NULL && api.resolved_count == 0);
    assert(!Kinemium_RuntimeOpen(&api, argv[3], error, sizeof(error)));
    assert(strstr(error, "Kinemium_GetABIVersion"));
    assert(api.library == NULL);

    assert(Kinemium_RuntimeOpen(&api, argv[4], error, sizeof(error)));
    assert(api.abi_version == KINEMIUM_ABI_MAJOR);
    assert(api.missing_count == KINEMIUM_RUNTIME_SYMBOL_COUNT - 3);
    assert(api.resolved_count == 3);
    assert(api.Create != NULL && api.Destroy != NULL && api.GetABIVersion != NULL);
    assert(api.RunLuau == NULL);
    assert(Kinemium_RuntimeHasSymbol(&api, "Kinemium_Create"));
    assert(!Kinemium_RuntimeHasSymbol(&api, "Kinemium_RunLuau"));
    assert(!Kinemium_RuntimeHasSymbol(&api, "Create"));
    assert(!Kinemium_RuntimeOpen(&api, argv[1], error, sizeof(error)));
    assert(strstr(error, "close the existing"));
    assert(api.resolved_count == 3);
    Kinemium_RuntimeClose(&api);
    assert(!api.Create && !api.Destroy && !api.library && api.resolved_count == 0);

    assert(!Kinemium_RuntimeOpenStrict(&api, argv[4], error, sizeof(error)));
    assert(strstr(error, "missing symbols"));
    assert(api.library == NULL && api.Create == NULL);

    assert(Kinemium_RuntimeOpenStrict(&api, argv[1], error, sizeof(error)));
    assert(api.GetABIVersion() == KINEMIUM_ABI_MAJOR);
    assert(api.resolved_count == KINEMIUM_RUNTIME_SYMBOL_COUNT && api.missing_count == 0);
    assert(Kinemium_RuntimeHasSymbol(&api, "Kinemium_HandleCreateInstance"));
    assert(!Kinemium_RuntimeHasSymbol(&api, "Kinemium_MadeUpSymbol"));

    Kinemium_Context *ctx = api.Create();
    assert(ctx);
    Kinemium_Handle world = api.HandleService(ctx, "Workspace");
    assert(world != 0);
    Kinemium_Handle part = api.HandleCreateInstance(ctx, "Part");
    assert(part && api.HandleSetParent(ctx, part, world));
    assert(api.RunLuau(ctx, "assert(workspace ~= nil)"));
    assert(api.Tick(ctx, 1.0f / 60.0f));
    api.Destroy(ctx);

    Kinemium_RuntimeClose(&api);
    assert(!Kinemium_RuntimeHasSymbol(&api, "Kinemium_GetABIVersion"));
    Kinemium_RuntimeClose(&api);  /* Safe repeated close. */
    assert(Kinemium_RuntimeOpenStrict(&api, argv[1], error, sizeof(error)));
    Kinemium_RuntimeClose(&api);

    puts("PASS Kinemium runtime loader: all SDK symbols, ABI validation, optional symbols, reload and cleanup");
    return 0;
}
