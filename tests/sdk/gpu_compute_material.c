#include "kinemium_runtime.h"
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>
#include <threads.h>

/* Validate that custom Vulkan compute writes directly into a Filament
 * MaterialVariant sampler without CPU texture readback.
 */
static const char *shader =
    "#version 450\n"
    "layout(local_size_x=8,local_size_y=8,local_size_z=1) in;\n"
    "layout(rgba8,set=0,binding=0) uniform writeonly image2D outputImage;\n"
    "void main(){ivec2 p=ivec2(gl_GlobalInvocationID.xy);"
    "if(all(lessThan(p,imageSize(outputImage))))"
    "imageStore(outputImage,p,vec4(1,0,0,1));}\n";

static const char *init_luau =
    "variant=Instance.new('MaterialVariant',workspace);"
    "variant.Name='SDKComputed';"
    "variant.Source=[[material { name: \"ComputeOutput\", "
    "shadingModel: unlit, requires: [uv0], instanced: true, "
    "parameters: [{type:sampler2d,name:computedMap}] } "
    "fragment { void material(inout MaterialInputs material) { "
    "prepareMaterial(material); "
    "material.baseColor=texture(materialParams_computedMap,getUV0());"
    " } }]];"
    "part=Instance.new('Part',workspace);part.Size=Vector3.new(3,3,3);"
    "part.MaterialVariant='SDKComputed';"
    "workspace.CurrentCamera.CFrame=CFrame.new(0,0,8);"
    "workspace.CurrentCamera.FieldOfView=45";

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    Kinemium_Runtime api = {0};
    char error[512] = {0};
    if (!Kinemium_RuntimeOpenStrict(&api, argv[1], error, sizeof(error))) {
        fprintf(stderr, "Runtime loading failed: %s\n", error);
        return 1;
    }
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        Kinemium_RuntimeClose(&api);
        return 1;
    }
    SDL_Window *window = SDL_CreateWindow("GPUCompute material C test",
        320, 240, SDL_WINDOW_VULKAN | SDL_WINDOW_HIDDEN);
    if (!window) {
        fprintf(stderr, "SDL_CreateWindow: %s\n", SDL_GetError());
        SDL_Quit();
        Kinemium_RuntimeClose(&api);
        return 1;
    }
    int width = 0, height = 0;
    SDL_GetWindowSizeInPixels(window, &width, &height);
    Kinemium_Context *ctx = api.CreateForSDLWindow(window, width, height,
                                                   KINEMIUM_MODE_STANDALONE);
    if (!ctx) {
        fprintf(stderr, "Could not create Vulkan SDK renderer\n");
        SDL_DestroyWindow(window);
        SDL_Quit();
        Kinemium_RuntimeClose(&api);
        return 1;
    }

    int result = 1;
    if (!api.RunLuau(ctx, init_luau)) {
        api.CopyLastError(ctx, error, sizeof(error));
        fprintf(stderr, "Scene init: %s\n", error);
        goto done;
    }
    Kinemium_Handle variant = 0;
    if (!api.GetGlobalInstance(ctx, "variant", &variant) || !variant) {
        fprintf(stderr, "MaterialVariant handle missing\n");
        goto done;
    }

    Kinemium_GPUComputeRenderStats before = {0}, after = {0};
    if (!api.GPUComputeGetRenderStats(&before)) goto done;
    int successes = 0;
    for (int frame = 0; frame < 480; ++frame) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT) goto done;
            if (event.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED &&
                event.window.data1 > 0 && event.window.data2 > 0) {
                api.ResizeRenderer(ctx, event.window.data1, event.window.data2);
            }
            api.ProcessSDLEvent(ctx, &event);
        }
        if (!api.Tick(ctx, 1.0f / 60.0f) || !api.RenderFrame(ctx, 1.0f / 60.0f)) {
            api.CopyLastError(ctx, error, sizeof(error));
            fprintf(stderr, "RenderFrame failure: %s\n", error);
            goto done;
        }
        if (frame > 2 && frame % 4 == 0 && successes == 0) {
            if (api.GPUComputeDispatchMaterialTexture(ctx, variant, "computedMap", shader, 64, 64)) {
                ++successes;
            } else {
                api.CopyLastError(ctx, error, sizeof(error));
                if (strstr(error, "must finish compiling") == NULL) {
                    fprintf(stderr, "DispatchMaterialTexture failed: %s\n", error);
                    goto done;
                }
            }
        }
        if (successes) break;
        struct timespec pause = {0, 2000000L};
        thrd_sleep(&pause, NULL);
    }
    if (successes == 0) {
        fprintf(stderr, "MaterialVariant was not ready to receive GPU output\n");
        goto done;
    }
    if (!api.GPUComputeGetRenderStats(&after) ||
        after.direct_texture_dispatches <= before.direct_texture_dispatches ||
        after.direct_texture_bytes < before.direct_texture_bytes + 64u * 64u * 4u ||
        after.pixel_readback_bytes != before.pixel_readback_bytes) {
        fprintf(stderr, "Direct texture bridge stats did not advance\n");
        goto done;
    }

    printf("PASS GPUCompute native C direct MaterialVariant texture: %llu dispatches, no CPU readback\n",
           (unsigned long long)(after.direct_texture_dispatches - before.direct_texture_dispatches));
    result = 0;

done:
    api.Destroy(ctx);
    SDL_DestroyWindow(window);
    SDL_Quit();
    Kinemium_RuntimeClose(&api);
    return result;
}
