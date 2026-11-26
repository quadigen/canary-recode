#include "kinemium_runtime.h"
#include <SDL3/SDL.h>
#include <stdbool.h>
#include <stdio.h>

/* Dynamically loads the Kinemium engine after SDL creates a window.
 * Build without -lkinemium. The engine can be replaced independently
 * while the executable is not running.
 */
int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <path-to-kinemium-shared-library>\n", argv[0]);
        return 2;
    }

    Kinemium_Runtime api = {0};
    char error[1024] = {0};
    if (!Kinemium_RuntimeOpen(&api, argv[1], error, sizeof(error))) {
        fprintf(stderr, "Kinemium runtime load failed: %s\n", error);
        return 1;
    }

    if (!api.CreateForSDLWindow || !api.ProcessSDLEvent || !api.ResizeRenderer ||
        !api.Tick || !api.RenderFrame || !api.RunLuau ||
        !api.HandleCreateInstance || !api.HandleService ||
        !api.HandleSetParent || !api.HandleSetDynamicBoolean) {
        fprintf(stderr, "This Kinemium library lacks the windowed SDK APIs\n");
        Kinemium_RuntimeClose(&api);
        return 1;
    }

    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "SDL initialization failed: %s\n", SDL_GetError());
        Kinemium_RuntimeClose(&api);
        return 1;
    }

    SDL_Window *window = SDL_CreateWindow("Kinemium (runtime loaded)",
        1280, 720, SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE);
    if (!window) {
        fprintf(stderr, "SDL window creation failed: %s\n", SDL_GetError());
        SDL_Quit();
        Kinemium_RuntimeClose(&api);
        return 1;
    }
    int width = 0, height = 0;
    SDL_GetWindowSizeInPixels(window, &width, &height);
    Kinemium_Context *ctx = width > 0 && height > 0
        ? api.CreateForSDLWindow(window, width, height, KINEMIUM_MODE_STANDALONE)
        : NULL;
    if (!ctx) {
        fprintf(stderr, "Creating Kinemium window context failed\n");
        SDL_DestroyWindow(window);
        SDL_Quit();
        Kinemium_RuntimeClose(&api);
        return 1;
    }

    int result = 0;
    Kinemium_Handle workspace = api.HandleService(ctx, "Workspace");
    Kinemium_Handle part = api.HandleCreateInstance(ctx, "Part");
    if (!workspace || !part ||
        !api.HandleSetParent(ctx, part, workspace) ||
        !api.HandleSetDynamicBoolean(ctx, part, "Anchored", true) ||
        !api.RunLuau(ctx,
            "local camera=Instance.new('Camera'); "
            "camera.CameraType=Enum.CameraType.Scriptable; "
            "camera.CFrame=CFrame.lookAt(Vector3.new(8,8,18), Vector3.new(0,0,0)); "
            "camera.Parent=workspace; workspace.CurrentCamera=camera")) {
        fprintf(stderr, "Preparing the Kinemium scene failed\n");
        result = 1;
        goto cleanup;
    }

    bool running = true;
    uint64_t previous = SDL_GetTicksNS();
    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT ||
                event.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED) {
                running = false;
                break;
            }
            if (event.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED &&
                event.window.data1 > 0 && event.window.data2 > 0 &&
                !api.ResizeRenderer(ctx, event.window.data1, event.window.data2)) {
                running = false;
                result = 1;
                break;
            }
            if (!api.ProcessSDLEvent(ctx, &event)) {
                running = false;
                result = 1;
                break;
            }
        }
        if (!running) break;

        uint64_t now = SDL_GetTicksNS();
        float dt = (float)((double)(now - previous) / 1000000000.0);
        previous = now;
        if (dt <= 0.0f) dt = 1.0f / 60.0f;
        if (dt > 0.1f) dt = 0.1f;

        if (!api.Tick(ctx, dt) || !api.RenderFrame(ctx, dt)) {
            fprintf(stderr, "Kinemium render/update failed\n");
            result = 1;
            break;
        }
        uint64_t elapsed = SDL_GetTicksNS() - now;
        if (elapsed < 16666667ULL) SDL_DelayNS(16666667ULL - elapsed);
    }

cleanup:
    api.Destroy(ctx);       /* Destroy engine objects before unloading code. */
    SDL_DestroyWindow(window);
    SDL_Quit();
    Kinemium_RuntimeClose(&api);
    return result;
}
