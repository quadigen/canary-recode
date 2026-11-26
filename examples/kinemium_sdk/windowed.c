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

int main(void) {
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

    Kinemium_Context *ctx = Kinemium_CreateForSDLWindow(
        window, width, height, KINEMIUM_MODE_STANDALONE
    );

    if (!ctx) {
        fprintf(stderr, "Kinemium_CreateForSDLWindow failed\n");
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    int exit_status = 0;
    Kinemium_Handle workspace = Kinemium_HandleService(ctx, "Workspace");
    Kinemium_Handle part = Kinemium_HandleCreateInstance(ctx, "Part");

    if (!workspace || !part ||
        !Kinemium_HandleSetParent(ctx, part, workspace) ||
        !Kinemium_HandleSetDynamicString(ctx, part, "Name", "NativeCube") ||
        !Kinemium_HandleSetDynamicBoolean(ctx, part, "Anchored", true) ||
        !Kinemium_HandleSetDynamicVector3(ctx, part, "Position", (Kinemium_Vector3){0.0, 5.0, 0.0}) ||
        !Kinemium_HandleSetDynamicVector3(ctx, part, "Size", (Kinemium_Vector3){4.0, 4.0, 4.0}) ||
        !Kinemium_HandleSetDynamicNumber(ctx, part, "Transparency", 0.15)) {
        exit_status = sdk_failed(ctx, "create scene");
        goto finish;
    }

    if (!Kinemium_RunLuau(
        ctx,
        "local camera = Instance.new('Camera'); "
        "camera.Name = 'NativeCamera'; "
        "camera.Parent = workspace; "
        "camera.CameraType = Enum.CameraType.Scriptable; "
        "camera.CFrame = CFrame.lookAt(Vector3.new(0, 11, 24), Vector3.new(0, 5, 0)); "
        "workspace.CurrentCamera = camera"
    )) {
        exit_status = sdk_failed(ctx, "set camera");
        goto finish;
    }

    bool running = true;
    uint64_t previous_time = SDL_GetTicksNS();

    while (running) {
        SDL_Event event;

        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT ||
                event.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED) {
                running = false;
            }

            if (event.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED &&
                event.window.data1 > 0 && event.window.data2 > 0) {
                if (!Kinemium_ResizeRenderer(ctx, event.window.data1, event.window.data2)) {
                    exit_status = sdk_failed(ctx, "resize renderer");
                    running = false;
                }
            }

            if (!Kinemium_ProcessSDLEvent(ctx, &event)) {
                exit_status = sdk_failed(ctx, "process SDL event");
                running = false;
            }
        }

        if (!running) {
            break;
        }

        uint64_t current_time = SDL_GetTicksNS();
        float dt = (float)((double)(current_time - previous_time) / 1000000000.0);
        previous_time = current_time;

        if (dt <= 0.0f) dt = 1.0f / 60.0f;
        if (dt > 0.1f) dt = 0.1f;

        if (!Kinemium_Tick(ctx, dt) ||
            !Kinemium_RenderFrame(ctx, dt)) {
            exit_status = sdk_failed(ctx, "frame");
            break;
        }

        uint64_t frame_elapsed = SDL_GetTicksNS() - current_time;
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
