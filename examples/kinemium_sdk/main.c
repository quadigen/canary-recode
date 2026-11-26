#include "kinemium.h"
#include <SDL3/SDL.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

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
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window *window = SDL_CreateWindow(
        "Kinemium Native SDK",
        1280,
        720,
        SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY
    );
    if (!window) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    int width = 0;
    int height = 0;
    SDL_GetWindowSizeInPixels(window, &width, &height);
    if (width <= 0 || height <= 0) {
        fprintf(stderr, "Invalid window pixel size: %d x %d\n", width, height);
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    Kinemium_Context *ctx = Kinemium_CreateForSDLWindow(
        window, width, height, KINEMIUM_MODE_STANDALONE
    );
    if (!ctx) {
        fprintf(stderr, "Could not attach Kinemium to the SDL window\n");
        SDL_DestroyWindow(window);
        SDL_Quit();
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
        Kinemium_HandleSetDynamicVector3(ctx, clone, "Position", (Kinemium_Vector3){6.0, 5.0, 0.0});
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

    if (!Kinemium_RunLuau(ctx,
        "local camera = Instance.new('Camera'); "
        "camera.Name = 'NativeCamera'; "
        "camera.Parent = workspace; "
        "camera.CameraType = Enum.CameraType.Scriptable; "
        "camera.CFrame = CFrame.lookAt(Vector3.new(4, 13, 27), Vector3.new(3, 5, 0)); "
        "workspace.CurrentCamera = camera"
    )) {
        exit_status = sdk_failed(ctx, "create camera");
        goto finish;
    }

    for (int frame = 0; frame < 4; ++frame) {
        if (!Kinemium_Tick(ctx, 1.0f / 60.0f)) {
            exit_status = sdk_failed(ctx, "initial frame update");
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
    puts("Kinemium SDK native example initialized. Close the window to exit.");

    bool running = true;
    uint64_t previous_time = SDL_GetTicksNS();
    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT ||
                event.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED) {
                running = false;
                break;
            }

            if (event.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED &&
                event.window.data1 > 0 && event.window.data2 > 0) {
                if (!Kinemium_ResizeRenderer(ctx, event.window.data1, event.window.data2)) {
                    exit_status = sdk_failed(ctx, "resize renderer");
                    running = false;
                    break;
                }
            }

            if (!Kinemium_ProcessSDLEvent(ctx, &event)) {
                exit_status = sdk_failed(ctx, "process SDL event");
                running = false;
                break;
            }
        }
        if (!running) break;

        uint64_t now = SDL_GetTicksNS();
        float dt = (float)((double)(now - previous_time) / 1000000000.0);
        previous_time = now;
        if (dt <= 0.0f) dt = 1.0f / 60.0f;
        if (dt > 0.1f) dt = 0.1f;

        if (!Kinemium_Tick(ctx, dt) || !Kinemium_RenderFrame(ctx, dt)) {
            exit_status = sdk_failed(ctx, "frame");
            break;
        }
        uint64_t frame_elapsed = SDL_GetTicksNS() - now;
        if (frame_elapsed < 16666667ULL) {
            SDL_DelayNS(16666667ULL - frame_elapsed);
        }
    }

finish:
    Kinemium_Destroy(ctx);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return exit_status;
}
