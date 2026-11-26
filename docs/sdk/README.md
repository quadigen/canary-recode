# Kinemium Native SDK

## Runtime linking: dlopen / LoadLibrary without -lkinemium

The SDK also provides a **type-safe runtime loader**. Add `src/kinemium_runtime.c` to a C11/C++ application and include `include/kinemium_runtime.h`. The library is loaded using `dlopen` (Linux/macOS) or `LoadLibraryA` (Windows) when your application runs, not when it is linked.

```c
Kinemium_Runtime sdk = {0};
char error[512] = {0};
if (!Kinemium_RuntimeOpen(&sdk, "./dist/kinemium/lib/libkinemium.so", error, sizeof(error))) {
    fprintf(stderr, "Load error: %s\n", error);
    return 1;
}
Kinemium_Context *ctx = sdk.Create();
/* sdk.HandleCreateInstance(ctx, "Part"), sdk.RunLuau(ctx, ...), etc. */
sdk.Destroy(ctx);
Kinemium_RuntimeClose(&sdk);
```

The generated `kinemium_runtime_symbols.h` includes type-safe pointers for all **248 public C exports**. The runtime loader enforces ABI major v2 and checks required entry points. `Kinemium_RuntimeOpen` permits missing optional functions (NULL pointers), and `Kinemium_RuntimeOpenStrict` requires all 248. Use `Kinemium_RuntimeHasSymbol` to test optional functions before calling them. The generation script is `tools/generate_kinemium_runtime_loader.py`; rerun it after editing `kinemium.h`.

```sh
cc -std=c11 -Iinclude src/kinemium_runtime.c \
  examples/kinemium_sdk/dynamic.c -ldl -o build/kinemium_sdk_dynamic
./build/kinemium_sdk_dynamic "$PWD/dist/kinemium/lib/libkinemium.so"
```

`kinemium_sdk_dynamic_windowed` is a second example that uses SDL3 but **never links to libkinemium at build time**. The loader and both examples are included in the packaged SDK. Native libraries execute trusted in-process code, not sandboxed code. Always destroy contexts and stop callbacks before unloading the shared library; never use cached function pointers after close.

To check runtime loading, build and run the `kinemium_sdk_dynamic` example above. Verify ABI compatibility and optional exports against the library you plan to distribute.

See the Fumadocs [runtime-loading guide](https://kinemium.docs.quadigen.com/docs/native-sdk/runtime-loading) for instructions and constraints.

## Main example: visible SDL3 window

`examples/kinemium_sdk/main.c` is the **default windowed example**. It uses `Kinemium_CreateForSDLWindow()` to attach to an SDL3 Vulkan window using the Filament-owned Vulkan compositor (the same presentation model as Kinemium's editor), creates Parts and a camera, forwards SDL events, handles resizing, and calls `Kinemium_Tick()` and `Kinemium_RenderFrame()` until the window is closed. It retains the existing C API demonstrations for cloning, Luau, physics, and networking.

Build and launch on Linux (SDL3 development files required):

```sh
cmake -S examples/kinemium_sdk -B build/sdk-example
cmake --build build/sdk-example
./build/sdk-example/kinemium_sdk_example
```

For non-GUI tests use `examples/kinemium_sdk/headless.c` or `build/sdk-example/kinemium_sdk_headless`; both terminate automatically. The windowed loop caps updates to 60 FPS while letting slow frames run without an additional delay. The smaller `windowed.c` sample is still available. Always destroy the Kinemium context before destroying the SDL window.

To verify windowed rendering, build the CMake examples above and launch `kinemium_sdk_example` in a desktop session. The offscreen GPUCompute example is also included in the packaged SDK.

The Kinemium shared library exposes the Kinemium engine, instance tree, Luau runtime, physics, renderer, and networking to C and C++ applications. All functions are prefixed `Kinemium_`. The public header is `include/kinemium.h`, and `Kinemium_GetABIVersion()` currently returns `2`.

The SDK is **experimental**. The Linux build has been compiled and integration-tested against the current source tree. The macOS build recipe is provided but has not been tested here. Windows binary packaging, browser/WASM exports, and ABI freeze are not implemented or verified.

## Build and package on Linux

Prerequisites: the repo's Odin compiler, vendor libraries built under `vendor/build/lib`, a C11 compiler, SDL3 development files for the windowed main example, Python 3, Vulkan/graphics drivers for rendering, and the existing Kinemium Linux runtime dependencies.

From the repository root:

```sh
python3 tools/build_kinemium_sdk.py
```

The generated `dist/kinemium/` contains:

- `include/kinemium.h`
- `include/kinemium_plugin.h`
- `include/kinemium_runtime.h` and `include/kinemium_runtime_symbols.h`
- `lib/libkinemium.so`
- `lib/libGameNetworkingSockets.so`
- `examples/main.c` (visible SDL3 window), `examples/dynamic.c`, `examples/dynamic_windowed.c` and `examples/gpu_compute.c` (runtime linking), `examples/headless.c`, and `examples/plugin/{main,secondary}.c`
- `plugins/native.{example,secondary}/` native plugin sample binaries/manifests
- `lib/pkgconfig/kinemium.pc` and `lib/cmake/Kinemium/KinemiumConfig.cmake`
- `bin/kinemium_sdk_gpu_compute` (offscreen Vulkan GPU-renderer example)
- `bin/kinemium_sdk_dynamic` (runtime link, no -lkinemium) and `bin/kinemium_sdk_dynamic_windowed` (when SDL3 is available)
- `bin/kinemium_sdk_example` (windowed, when SDL3 is available) and `bin/kinemium_sdk_headless`

The packaging script strips debug data from the packaged binary by default. Set `KINEMIUM_SDK_KEEP_SYMBOLS=1` to retain it. The package **is not a fully self-contained Linux runtime**: system libraries such as Vulkan, SDL3, GTK, and OpenSSL remain dynamic dependencies. Inspect them with `ldd dist/kinemium/lib/libkinemium.so`.

Run the packaged example:

```sh
dist/kinemium/bin/kinemium_sdk_example
```

For command-line/CI smoke tests without a display, run `dist/kinemium/bin/kinemium_sdk_headless`.

Build the example via CMake (SDL3 is required):

```sh
cmake -S examples/kinemium_sdk -B build/sdk-example
cmake --build build/sdk-example
./build/sdk-example/kinemium_sdk_example
```

To use a package elsewhere, pass `-DKINEMIUM_SDK_ROOT=/path/to/dist/kinemium` to CMake. Link your program to `kinemium` and include `kinemium.h`.

## Essential C workflow

```c
#include "kinemium.h"

int main(void) {
    Kinemium_Context *ctx = Kinemium_CreateWithMode(KINEMIUM_MODE_STANDALONE);
    if (!ctx) return 1;

    Kinemium_Handle workspace = Kinemium_HandleService(ctx, "Workspace");
    Kinemium_Handle cube = Kinemium_HandleCreateInstance(ctx, "Part");

    Kinemium_HandleSetParent(ctx, cube, workspace);
    Kinemium_HandleSetDynamicString(ctx, cube, "Name", "Cube");
    Kinemium_HandleSetDynamicBoolean(ctx, cube, "Anchored", true);
    Kinemium_HandleSetDynamicVector3(ctx, cube, "Position", (Kinemium_Vector3){0, 5, 0});
    Kinemium_HandleSetColor3(ctx, cube, "Color", (Kinemium_Color3){1, 0, 0});

    Kinemium_SetGlobalInstance(ctx, "nativeCube", cube);
    Kinemium_RunLuau(ctx, "assert(nativeCube.Name == 'Cube')");

    Kinemium_Tick(ctx, 1.0f / 60.0f);
    Kinemium_Destroy(ctx);
    return 0;
}
```

The `examples/kinemium_sdk/main.c` program demonstrates cloning, raycasting, method invocation, Luau callbacks, and network statistics as well.

## API coverage

### Runtime and scripting

- `Create`, `CreateWithMode`, `Destroy`, `Update`, `Render`, `Tick`, and mode getters/setters.
- `RunLuau` executes Luau source in the context's VM. Errors are available through `GetLastErrorLength` and `CopyLastError`.
- `EvaluateLuau` executes Luau source and optionally returns its first typed result through `Kinemium_Value`; a caller-owned string buffer receives string results. It preserves VM stack balance and reports errors through the same error APIs.
- Native globals for booleans, numbers, strings, Vector3, and instance handles are available with `SetGlobal*` and `GetGlobal*`.
- `RegisterNativeFunction` installs a C function callable from Luau as a global; `UnregisterNativeFunction` clears the global.

### Scene graph and reflection

- `HandleService`, `HandleCreateInstance`, `HandleGetParent`, `HandleSetParent`, `HandleFindChild`, `HandleGetChildCount`, `HandleGetChildAt`, `HandleCopyName`, `HandleCopyClassName`, `HandleCopyFullName`, `HandleIsA`, `HandleClone`, `HandleDestroy`, and `HandleRelease`.
- `GetClassCount`, `CopyClassName`, `ClassExists`, `ClassIsCreatable`, `ClassGetPropertyCount`, and `ClassCopyPropertyName` enumerate registered engine types.
- `HandleGetPropertyType`, `HandleGetPropertyCount`, `HandleCopyPropertyName`, and `HandleHasProperty` describe instance properties.
- `HandleGetMethodCount`, `HandleCopyMethodName`, and `HandleHasMethod` enumerate inherited methods; `HandleGetExportCount`, `HandleCopyExportName`, and `HandleHasExport` enumerate native class exports. These reflect registry metadata rather than guessing method names.
- `ClassCopyParentName` and `ClassIsA` expose inheritance. `ClassGetMethodCount`, `ClassCopyMethodName`, `ClassHasMethod`, `ClassGetEventCount`, `ClassCopyEventName`, and `ClassHasEvent` enumerate inherited methods and events by class name.
- `HandleGetEventCount`, `HandleCopyEventName`, and `HandleHasEvent` enumerate inherited event metadata for a live Instance.
- `HandleFindDescendant`, `HandleFindDescendantOfClass`, `HandleGetDescendantAt`, `HandleCountTaggedDescendants`, and `HandleFindTaggedDescendant` traverse the subtree beneath an Instance. Queries exclude the ancestor itself; enumeration is breadth-first.
- `HandleGetAttributeCount`, `HandleCopyAttributeName`, `HandleHasAttribute`, `HandleGetAttribute`, `HandleSetAttribute`, and `HandleRemoveAttribute` expose Luau-compatible Instance attributes. The supported C `Kinemium_Value` kinds are nil, boolean, number, string, and Vector3. A missing attribute returns a nil value; unsupported kinds are rejected.
- `HandleGetTagCount`, `HandleCopyTagName`, `HandleHasTag`, `HandleAddTag`, and `HandleRemoveTag` expose Instance tags; `HandleGetMetadataRevision` detects attribute and tag changes without enumerating them every frame.
- Typed dynamic property access covers booleans, numbers, strings, Vector3, Instance, Color3, and CFrame. Property handlers use protected Luau calls, so class-specific validation and side effects are respected.
- `Kinemium_Invoke` calls a supported instance method or registered native export with up to 32 typed arguments. `Kinemium_InvokeExport` exclusively calls registered class export handlers and native methods, without exposing raw Lua stack operations. Results may be nil, boolean, number, string, Vector3, Instance, or an unsupported type. For string results, pass a caller-owned text buffer; `output.text_length` reports the full required length.

### Example: attributes, tags, and discovery

```c
Kinemium_Value health = { .kind = KINEMIUM_VALUE_NUMBER, .number = 100.0 };
Kinemium_HandleSetAttribute(ctx, cube, "Health", &health);
Kinemium_HandleAddTag(ctx, cube, "Enemy");

Kinemium_Value current_health = {0};
if (Kinemium_HandleGetAttribute(ctx, cube, "Health", &current_health, NULL, 0) &&
    current_health.kind == KINEMIUM_VALUE_NUMBER) {
    printf("Health: %.1f\n", current_health.number);
}

Kinemium_Handle first_enemy = Kinemium_HandleFindTaggedDescendant(ctx, workspace, "Enemy");
uint64_t enemy_count = Kinemium_HandleCountTaggedDescendants(ctx, workspace, "Enemy");
```

String attributes are copied into the caller's buffer through `HandleGetAttribute` just as with `Kinemium_Invoke`, with `output.text_length` reporting the untruncated length. Name-copy functions return the required byte length or `-1` for an invalid index. All native handles remain tied to the context and become invalid when the owning Instance is destroyed.

### Player and Part physics APIs

Use the C SDK for direct Player lookup and character operations: `PlayersGetCount`, `PlayersGetAt`, `PlayersGetLocalPlayer`, `PlayersFindByUserId`, `PlayersFindByCharacter`, `PlayerGetUserId`, `PlayerGetCharacter`, `PlayerLoadCharacter`, `PlayerGetPing`, `PlayerGetWalkSpeed`, `PlayerSetWalkSpeed`, `PlayerGetJumpPower`, and `PlayerSetJumpPower`.

Native Part helpers use existing physics bodies: `PhysicsGetLinearVelocity`, `PhysicsSetLinearVelocity`, `PhysicsGetAngularVelocity`, `PhysicsSetAngularVelocity`, `PhysicsGetPartMass`, `PhysicsGetVelocityAtPosition`, and `PhysicsApplyImpulseAtPosition`. The velocity setters reject NaN/infinity. All handles are validated against the caller context; movement value setters use existing Luau validation. Character spawning follows the engine's server/client rules.

```c
uint32_t user_id = 0;
Kinemium_Handle player = Kinemium_PlayersGetAt(ctx, 0);
if (player && Kinemium_PlayerGetUserId(ctx, player, &user_id)) {
    Kinemium_PlayerSetWalkSpeed(ctx, player, 22.5);
}
Kinemium_Vector3 velocity = {0};
Kinemium_PhysicsGetLinearVelocity(ctx, cube, &velocity);
```

For the public physics and Player API, see the [players and physics guide](/docs/native-sdk/players-and-physics).

### GPUCompute for custom C/C++ renderers

Use Kinemium's Vulkan GPUCompute directly from C or C++: open a context-owned GPUCompute device, query hardware limits, allocate/read/write/fill/copy GPU buffers, compile GLSL 450 shaders, bind storage/uniform buffers and sampled/storage textures, set push constants, dispatch compute workgroups, poll completion, record command batches and schedule asynchronous tasks.

```c
Kinemium_GPUComputeOpen(ctx);
uint32_t buffer_id = 0, pipeline_id = 0;
uint32_t kinds[] = { KINEMIUM_GPU_BIND_STORAGE_BUFFER };
Kinemium_GPUComputeCreateBuffer(ctx, 64 * 64 * 4, &buffer_id);
Kinemium_GPUComputeCreatePipeline(ctx, glsl_source, 1, kinds, &pipeline_id);
Kinemium_GPUComputeUsePipeline(ctx, pipeline_id);
Kinemium_GPUComputeBindBuffer(ctx, 0, buffer_id);
Kinemium_GPUComputeDispatch(ctx, 8, 8, 1);
// Poll Kinemium_GPUComputePoll before GPUComputeReadBuffer.
```

For GPU-written **MaterialVariant sampler textures with no CPU pixel readback**, use `Kinemium_GPUComputeDispatchMaterialTexture`. It validates a GLSL image2D compute shader against the compiled material and uses the existing shared Vulkan/Filament renderer. `Kinemium_GPUComputeGetRenderStats` tracks direct dispatches and readback/upload counters. Internal GPUCompute textures live on a separate Vulkan device and cannot be passed directly into Filament; use storage buffers for CPU output or the direct material bridge for presentation.

The sample `examples/kinemium_sdk/gpu_compute.c` performs an offscreen 64×64 GPU gradient render, optionally saving a PPM image. It uses the runtime loader and does not link libkinemium at build time:

```sh
cmake -S examples/kinemium_sdk -B build/sdk-example
cmake --build build/sdk-example --target kinemium_sdk_gpu_compute
./build/sdk-example/kinemium_sdk_gpu_compute "$PWD/dist/kinemium/lib/libkinemium.so" /tmp/gpu-output.ppm
```

You can verify GPU output using the packaged `kinemium_sdk_gpu_compute` example. See the [GPUCompute C SDK](https://kinemium.docs.quadigen.com/docs/native-sdk/gpu-compute) for supported operations and limitations.

### Physics and rendering

- `PhysicsGetGravity`, `PhysicsSetGravity`, `HandleApplyImpulse`, `HandleApplyAngularImpulse`, and `Raycast` use the existing engine simulation.
- `CreateHeadlessRenderer`, `RenderFrame`, `ResizeRenderer`, `GetRendererSize`, and `GetNativeRenderer` expose headless Filament/Vulkan rendering.
- `CreateForSDLWindow` can attach to a caller-owned SDL3 window; `ProcessSDLEvent` passes an SDL3 event to Kinemium. The native host retains responsibility for creating/destroying the SDL window, pumping events, presenting any additional UI, and managing its own application loop.
- `RenderFrame` returns whether a frame request was accepted, not confirmation that Filament successfully presented pixels. This SDK does not expose reliable GPU readback; the Vulkan readback shim may be disabled at build time.

### Networking

- `NetworkStartServer`, `NetworkConnect`, `NetworkStop`, `NetworkSendStringEvent`, `NetworkSetSendRate`, and `NetworkGetStats` wrap Kinemium's existing SteamNetworkingSockets-backed replicator.
- Use server or client mode when creating the respective context, drive both contexts with `Tick`, and stop networking before destruction.
- `NetworkGetMode`, `NetworkGetProtocolVersion`, and `NetworkGetDiagnostics` expose runtime state, protocol version, handshake status and detailed rejection/traffic diagnostics. The additive `Kinemium_NetworkDiagnostics` struct does not alter `Kinemium_NetworkStats` or ABI-v2 layouts.
- `NetworkGetSetting` and `NetworkSetSetting` expose validated `ReplicatorService` numeric settings: `SnapshotRate`, `BandwidthBudget`, `SendRate`, `InterpolationDelayTicks`, `TeleportThreshold`, `RelevancyDistance`, `LODNearFraction`, and `LODFarInterval`. Invalid names and values are rejected by the engine's existing property handlers.
- `NetworkGetPeerCount`, `NetworkGetPeerPlayer`, and `NetworkGetPeerUserId` enumerate server-connected peers and their Player Instances. Client contexts do not enumerate server peers.
- `NetworkConnectEvent` connects a C callback to `ReplicatorService.EventReceived`; disconnect using `Kinemium_DisconnectSignal`. `NetworkSendStringEventTo` sends a named string event to one connected Player on the server; `NetworkSetClientEventAllowed` controls which named client-originated events the server accepts.
- `NetworkRegisterInstance`, `NetworkGetInstanceId`, and `NetworkUnregisterInstance` control server-side replication of existing Instances; `NetworkSetJoinToken` and `NetworkSetRequireJoinToken` configure handshake policy without exposing the token through a getter.

### Networking and service example

```c
Kinemium_Value value = {0};
Kinemium_ServiceGetProperty(ctx, "ReplicatorService", "SnapshotRate", &value, NULL, 0);

Kinemium_NetworkSetSetting(ctx, "SnapshotRate", 30.0);

Kinemium_NetworkDiagnostics diagnostics = {0};
Kinemium_NetworkGetDiagnostics(ctx, &diagnostics);

for (uint64_t i = 0; i < Kinemium_NetworkGetPeerCount(ctx); ++i) {
    Kinemium_Handle player = Kinemium_NetworkGetPeerPlayer(ctx, i);
    if (player) {
        Kinemium_NetworkSendStringEventTo(ctx, player, "Greeting", "Hello!", true);
    }
}
```

These APIs preserve existing per-service property validation and support the same standalone and borrowed-plugin contexts. For callback lifetimes, join-token restrictions, service metadata and tested server/client behavior, see the [networking and services guide](/docs/native-sdk/networking-and-services).

## Stability: native Instance creation and Luau stack balance

The SDK must leave Luau's VM stack at the same height after an exported C call. Earlier SDK builds accidentally left a userdata value on the Lua stack on every `Kinemium_HandleCreateInstance` or legacy `Kinemium_CreateInstance` call. After thousands of native creations the Luau C stack exhausted its slots and could terminate the process with SIGABRT from `lua_pushlstring` even if the created Parts were immediately destroyed.

Both creation paths restore the pre-call stack height and reject near-full Lua stacks before attempting Instance allocation. Dynamic property get/set helpers also detect insufficient stack capacity and return an SDK error instead of overflowing the Lua stack. These checks do not guarantee recovery from operating-system OOM or arbitrary corrupt memory.

Validate native handles and property operations under the workload you intend to ship, and monitor Luau stack stability when invoking exported functions repeatedly.

## Native plugins

The unified SDK also supports plugins loaded inside an existing editor, server or game runtime. Both embedding and plugins use the **same** `Kinemium_*` functions; the plugin receives a borrowed view of the existing context, so it must not call `Kinemium_Destroy`.

Include `kinemium_plugin.h` for the tiny `Kinemium_PluginDescriptor` entry-point contract and convenience builders. A plugin exports `Kinemium_PluginEntry` and returns a static descriptor with `abi_major=2` and `abi_minor=0`. The host invokes `on_load`, `on_start`, `on_update`, `on_stop`, and `on_unload` when provided. Native plugin classes, services, datatypes, signal connections, and retained callbacks are cleaned up on unload.

See `examples/kinemium_sdk/plugin/main.c` for a complete native plugin that registers a custom Instance class, singleton service, serializable datatype, and Luau function. Its manifest uses `{ "api": 2, "api_minor": 0, "entry": "Kinemium_PluginEntry" }`.

You can load and unload a plugin from an embedded application with `Kinemium_PluginLoad(ctx, directory, &plugin)` and `Kinemium_PluginUnload(ctx, plugin)`; the engine's plugin manager shares the same context.

Native class descriptors can optionally provide `on_get` and `on_set` for computed properties and validated writes in addition to fixed offset properties. An ABI-size check preserves compatibility with earlier descriptor layouts. `on_step` and `on_batch_step` provide per-instance or batched updates.

Signal subscriptions may invoke C callbacks through `Kinemium_ConnectSignal`, or an existing retained Luau callback through `Kinemium_ConnectLuauSignal`. Check retained callback validity with `Kinemium_LuauCallbackIsValid`, and release callbacks with `Kinemium_ReleaseLuauCallback`.

The plugin API includes `Kinemium_RegisterClass`, `Kinemium_RegisterService`, `Kinemium_RegisterDatatype`, `Kinemium_ConnectSignal`, `Kinemium_ConnectLuauSignal`, `Kinemium_RetainLuauCallback`, `Kinemium_CallLuauCallback`, `Kinemium_EvaluateLuau`, and `Kinemium_PluginReload`.

The unified API also includes `Kinemium_Log`, service discovery (`Kinemium_GetServiceCount`, `Kinemium_CopyServiceName`, `Kinemium_ServiceExists`), `Kinemium_CopyEngineVersion` and namespaced `Kinemium_RegisterLibraryFunction` for Luau libraries. The [KNE migration guide](https://kinemium.docs.quadigen.com/docs/native-sdk/migrating-from-kne) explains compatibility differences and the migration path. Native datatype descriptors also support optional arithmetic, equality, string conversion, and encode/decode hooks.

The KNE 3.x loader supports legacy plugins. Use the unified SDK for plugin authoring.

## Native callback example

```c
static bool add_numbers(void *user_data, uint32_t count,
                        const Kinemium_Value *args, Kinemium_Value *result) {
    (void)user_data;
    if (count != 2 || args[0].kind != KINEMIUM_VALUE_NUMBER ||
        args[1].kind != KINEMIUM_VALUE_NUMBER) return false;
    result->kind = KINEMIUM_VALUE_NUMBER;
    result->number = args[0].number + args[1].number;
    return true;
}

Kinemium_RegisterNativeFunction(ctx, "nativeAdd", add_numbers, NULL);
Kinemium_RunLuau(ctx, "assert(nativeAdd(5, 7) == 12)");
```

You can route Luau engine events into a C function by registering a native function and connecting a Luau signal handler that calls it.

## Ownership, threading, and errors

Every `Kinemium_Handle` is a 64-bit, generation-checked token owned by one context. A released or destroyed instance handle becomes invalid. Do not use handles from another context, after `Destroy`, or across asynchronously executing threads without your own synchronization. In particular, SDK calls to one context and its Luau VM should be performed on its owning thread.

`Kinemium_HandleRelease` invalidates the caller's token; it does **not** destroy the underlying instance. `Kinemium_HandleDestroy` destroys a creatable instance hierarchy; engine-owned services cannot be destroyed through this function. A failed call generally returns `false`, a zero handle, or `-1` for length-copy APIs. Read `CopyLastError` when an error is reported.

String-copy APIs return required byte length, write at most `capacity - 1` bytes, and add a trailing NUL when a non-null buffer has nonzero capacity. A null buffer can be used to query length. Registered native callbacks receive ephemeral argument pointers; a callback must not keep them after it returns. Callback output strings must remain readable until the callback returns. Avoid recursive VM operations from a native callback unless that reentrancy is explicitly supported by the relevant engine subsystem.

The legacy raw-pointer functions (`Kinemium_GetService`, `Kinemium_CreateInstance`, `Kinemium_SetParent`, and similar) are retained for compatibility, but **may become dangling after instance destruction**. Prefer the handle-based functions.

## Build verification

Use the SDK packaging tool and compiled C examples rather than the old Python smoke-test suite:

```sh
python3 tools/build_kinemium_sdk.py
python3 tests/sdk/verify_exports.py include/kinemium.h dist/kinemium/lib/libkinemium.so
cmake -S examples/kinemium_sdk -B build/sdk-example
cmake --build build/sdk-example
dist/kinemium/bin/kinemium_sdk_headless
```

For GPU verification on Linux with Vulkan installed, run `dist/kinemium/bin/kinemium_sdk_gpu_compute` with the full path to the SDK shared library and an optional output PPM file. Test windowed rendering separately in a desktop session.

## Current limitations

This is a broad native SDK surface, not a one-to-one C wrapper for every Odin class and service. There is no general C ABI for arbitrary custom userdata, all enum/datatype variants, asset-import pipelines, audio mixing, input-device management, full Skia/2D compositor control, native script debugging, or every network event callback. Those remain accessible where exposed by the existing Luau runtime or engine's other native interfaces. The SDK has not been ABI-frozen or validated on all target platforms.
