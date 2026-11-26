#include "kinemium.h"
#include <SDL3/SDL.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

static int fail(Kinemium_Context *ctx, const char *step) {
    char message[512] = {0};
    if (ctx) Kinemium_CopyLastError(ctx, message, sizeof(message));
    fprintf(stderr, "FAIL windowed smoke at %s: %s\n", step, message);
    return 1;
}

int main(void) {
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window *window = SDL_CreateWindow(
        "Kinemium SDK compositor regression",
        960, 640, SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE
    );
    if (!window) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    int width = 0;
    int height = 0;
    SDL_GetWindowSizeInPixels(window, &width, &height);
    Kinemium_Context *ctx = width > 0 && height > 0
        ? Kinemium_CreateForSDLWindow(window, width, height, KINEMIUM_MODE_STANDALONE)
        : NULL;

    if (!ctx) {
        fprintf(stderr, "Kinemium_CreateForSDLWindow failed\n");
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    int result = 0;
    Kinemium_Handle workspace = Kinemium_HandleService(ctx, "Workspace");
    Kinemium_Handle part = Kinemium_HandleCreateInstance(ctx, "Part");
    if (!workspace || !part ||
        !Kinemium_HandleSetParent(ctx, part, workspace) ||
        !Kinemium_HandleSetDynamicBoolean(ctx, part, "Anchored", true) ||
        !Kinemium_HandleSetDynamicVector3(ctx, part, "Size", (Kinemium_Vector3){4, 4, 4}) ||
        !Kinemium_HandleSetDynamicVector3(ctx, part, "Position", (Kinemium_Vector3){0, 5, 0})) {
        result = fail(ctx, "scene");
        goto finish;
    }

    Kinemium_Handle clone = Kinemium_HandleClone(ctx, part);
    if (!clone ||
        !Kinemium_HandleSetDynamicNumber(ctx, clone, "Transparency", 0.15) ||
        !Kinemium_HandleSetDynamicVector3(ctx, clone, "Position", (Kinemium_Vector3){6, 5, 0}) ||
        !Kinemium_HandleSetParent(ctx, clone, workspace)) {
        result = fail(ctx, "clone");
        goto finish;
    }

    if (!Kinemium_RunLuau(
        ctx,
        "local camera = Instance.new('Camera'); "
        "camera.CameraType = Enum.CameraType.Scriptable; "
        "camera.CFrame = CFrame.lookAt(Vector3.new(4,13,27), Vector3.new(3,5,0)); "
        "camera.Parent = workspace; "
        "workspace.CurrentCamera = camera"
    )) {
        result = fail(ctx, "camera");
        goto finish;
    }

    uint64_t previous = SDL_GetTicksNS();
    for (unsigned frame = 0; frame < 120; ++frame) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT ||
                event.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED) {
                result = fail(ctx, "premature window close");
                goto finish;
            }
            if (event.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED &&
                event.window.data1 > 0 && event.window.data2 > 0) {
                if (!Kinemium_ResizeRenderer(ctx, event.window.data1, event.window.data2)) {
                    result = fail(ctx, "resize");
                    goto finish;
                }
            }
            if (!Kinemium_ProcessSDLEvent(ctx, &event)) {
                result = fail(ctx, "event");
                goto finish;
            }
        }

        if (frame == 35) SDL_SetWindowSize(window, 1024, 720);
        if (frame == 75) SDL_SetWindowSize(window, 960, 640);

        uint64_t now = SDL_GetTicksNS();
        float dt = (float)((double)(now - previous) / 1000000000.0);
        previous = now;
        if (dt <= 0) dt = 1.0f / 60.0f;
        if (dt > 0.1f) dt = 0.1f;

        if (!Kinemium_Tick(ctx, dt) || !Kinemium_RenderFrame(ctx, dt)) {
            result = fail(ctx, "frame");
            goto finish;
        }
    }

    printf("PASS windowed SDK compositor: 120 frames, resize, clone, camera, cleanup\n");

finish:
    Kinemium_Destroy(ctx);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return result;
}
