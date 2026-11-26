#include "kinemium_runtime.h"
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <threads.h>

#define W 64
#define H 64

static const char *shader_source =
    "#version 450\n"
    "layout(local_size_x=8,local_size_y=8,local_size_z=1) in;\n"
    "layout(set=0,binding=0,std430) buffer Pixels { uint pixels[]; } outPixels;\n"
    "void main() {\n"
    " uint x=gl_GlobalInvocationID.x,y=gl_GlobalInvocationID.y;\n"
    " if (x>=64 || y>=64) return;\n"
    " vec4 color=vec4(float(x)/63.0,float(y)/63.0,0.25,1.0);\n"
    " outPixels.pixels[y*64+x]=packUnorm4x8(color);\n"
    "}\n";

static void error_message(Kinemium_Runtime *api, Kinemium_Context *ctx,
                          const char *step) {
    char details[1024] = {0};
    if (api->CopyLastError) {
        api->CopyLastError(ctx, details, sizeof(details));
    }
    fprintf(stderr, "%s failed: %s\n", step, details);
}

int main(int argc, char **argv) {
    if (argc < 2 || argc > 3) {
        fprintf(stderr, "Usage: %s <libkinemium.so> [output.ppm]\n", argv[0]);
        return 2;
    }

    Kinemium_Runtime api = {0};
    char error[512] = {0};
    if (!Kinemium_RuntimeOpen(&api, argv[1], error, sizeof(error))) {
        fprintf(stderr, "Runtime load: %s\n", error);
        return 1;
    }
    if (!api.GPUComputeOpen || !api.GPUComputeClose ||
        !api.GPUComputeGetCapabilities || !api.GPUComputeCreateBuffer ||
        !api.GPUComputeCreatePipeline || !api.GPUComputeUsePipeline ||
        !api.GPUComputeBindBuffer || !api.GPUComputeDispatch ||
        !api.GPUComputePoll || !api.GPUComputeReadBuffer) {
        fprintf(stderr, "Library does not expose the GPUCompute API\n");
        Kinemium_RuntimeClose(&api);
        return 1;
    }

    Kinemium_Context *ctx = api.CreateWithMode(KINEMIUM_MODE_STANDALONE);
    if (!ctx) {
        fprintf(stderr, "Kinemium context creation failed\n");
        Kinemium_RuntimeClose(&api);
        return 1;
    }

    int status = 1;
    uint32_t pixels_buffer = 0, pipeline = 0;
    if (!api.GPUComputeOpen(ctx)) {
        error_message(&api, ctx, "GPUComputeOpen");
        goto finish;
    }

    Kinemium_GPUComputeCapabilities caps = {0};
    if (!api.GPUComputeGetCapabilities(ctx, &caps)) {
        error_message(&api, ctx, "GPUComputeGetCapabilities");
        goto finish;
    }
    printf("GPU: %s, workgroup invocations: %u\n", caps.name, caps.max_workgroup_invocations);

    if (!api.GPUComputeCreateBuffer(ctx, W * H * sizeof(uint32_t), &pixels_buffer)) {
        error_message(&api, ctx, "GPUComputeCreateBuffer");
        goto finish;
    }
    const uint32_t binding_kinds[] = {KINEMIUM_GPU_BIND_STORAGE_BUFFER};
    if (!api.GPUComputeCreatePipeline(ctx, shader_source, 1, binding_kinds, &pipeline)) {
        error_message(&api, ctx, "GPUComputeCreatePipeline");
        goto finish;
    }
    if (!api.GPUComputeUsePipeline(ctx, pipeline) ||
        !api.GPUComputeBindBuffer(ctx, 0, pixels_buffer) ||
        !api.GPUComputeDispatch(ctx, W / 8, H / 8, 1)) {
        error_message(&api, ctx, "GPUComputeDispatch");
        goto finish;
    }

    bool completed = false;
    for (int attempt = 0; attempt < 4000; ++attempt) {
        if (!api.GPUComputePoll(ctx, &completed)) {
            error_message(&api, ctx, "GPUComputePoll");
            goto finish;
        }
        if (completed) break;
        struct timespec pause = {0, 1000000L};
        thrd_sleep(&pause, NULL);
    }
    if (!completed) {
        fprintf(stderr, "GPUCompute timed out waiting for the shader\n");
        goto finish;
    }

    uint32_t pixels[W * H] = {0};
    if (!api.GPUComputeReadBuffer(ctx, pixels_buffer, 0, sizeof(pixels),
                                  pixels, sizeof(pixels))) {
        error_message(&api, ctx, "GPUComputeReadBuffer");
        goto finish;
    }

    /* The shader packs R in the least significant byte and A in the highest. */
    uint32_t upper_left = pixels[0];
    uint32_t lower_right = pixels[W * H - 1];
    if ((upper_left & 0xffu) != 0 ||
        ((upper_left >> 8) & 0xffu) != 0 ||
        (lower_right & 0xffu) != 255 ||
        ((lower_right >> 8) & 0xffu) != 255 ||
        ((lower_right >> 24) & 0xffu) != 255) {
        fprintf(stderr, "GPU pixel values mismatch: 0x%08x 0x%08x\n",
                upper_left, lower_right);
        goto finish;
    }

    if (argc == 3) {
        FILE *output = fopen(argv[2], "wb");
        if (!output) {
            perror("fopen");
            goto finish;
        }
        fprintf(output, "P6\n%d %d\n255\n", W, H);
        for (size_t i = 0; i < W * H; ++i) {
            uint32_t color = pixels[i];
            fputc((int)(color & 255u), output);
            fputc((int)((color >> 8) & 255u), output);
            fputc((int)((color >> 16) & 255u), output);
        }
        fclose(output);
        printf("Wrote GPU-rendered 64x64 image to %s\n", argv[2]);
    }
    puts("PASS GPUCompute shader dispatch and offscreen pixel rendering");
    status = 0;

finish:
    if (pipeline) api.GPUComputeDestroyPipeline(ctx, pipeline);
    if (pixels_buffer) api.GPUComputeDestroyBuffer(ctx, pixels_buffer);
    api.GPUComputeClose(ctx);
    api.Destroy(ctx);
    Kinemium_RuntimeClose(&api);
    return status;
}
