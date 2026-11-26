

#include "kine_filament_shim.h"
#include "kine_skia.h"
#include "kine_vulkan_compositor.h"
#include <SDL3/SDL.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <numeric>
#include <vector>

static void require(bool cond, const char *message) {
    if (!cond) { std::fprintf(stderr, "CLOUD_BENCH_FAIL:%s\n", message); std::exit(1); }
}
int main(int argc, char** argv) {
    const int width = argc > 1 ? std::max(320, std::atoi(argv[1])) : 1280;
    const int height = argc > 2 ? std::max(240, std::atoi(argv[2])) : 720;
    const int frames = argc > 3 ? std::max(20, std::atoi(argv[3])) : 100;
    require(SDL_Init(SDL_INIT_VIDEO), "SDL_Init");
    auto *window = SDL_CreateWindow("Cloud GPU benchmark", width, height, SDL_WINDOW_VULKAN | SDL_WINDOW_HIDDEN);
    require(window, "SDL_CreateWindow");
    auto *ctx = Kine_Filament_CreateForVulkanCompositorWindow(window, width, height);
    require(ctx, "CreateForVulkanCompositorWindow");
    auto *compositor = static_cast<KineVulkanCompositor *>(Kine_Filament_GetVulkanCompositor(ctx));
    require(compositor, "GetVulkanCompositor");
    Kine_Filament_SetCameraPerspective(ctx, 70.0, double(width) / height, 0.1, 10000.0);
    Kine_Filament_SetCameraLookAt(ctx, 0, 0, 0, 0, 700, -900, 0, 1, 0);
    std::printf("CLOUD_BENCH_START size=%dx%d frames=%d\n",width,height,frames);
    using Pixel=std::array<uint8_t,4>;
    auto *mesh=Kine_Filament_CreateMesh(ctx,1);
    require(mesh,"create test occluder");
    KineFilamentDrawItem item{};
    item.mesh=mesh;item.materialKind=KINE_MAT_NEON;item.r=1;item.g=0.05f;item.b=0.05f;
    item.transmission=1;item.transform[0]=item.transform[5]=item.transform[10]=30;item.transform[15]=1;
    item.transform[7]=70;item.transform[11]=-90;
    auto render = [&](std::vector<Pixel>* pixels=nullptr,bool block=false,float dt=1.0f/144.0f) {
        auto *surface = static_cast<KineSkiaSurface *>(Kine_VulkanCompositor_BeginFrame(compositor));
        require(surface, "BeginFrame");
        Kine_Skia_Surface_Clear(surface, 120, 175, 205, 255);
        Kine_Filament_Viewport_Begin(ctx);
        if(block) Kine_Filament_DrawMeshListVersioned(ctx,&item,1,123,1);
        Kine_Filament_Viewport_RenderFrame(ctx, dt, true);
        auto* overlay=static_cast<KineSkiaSurface*>(Kine_VulkanCompositor_BeginOverlay(compositor));
        require(overlay,"BeginOverlay");
        if(pixels) {
            for(int y=1;y<=5;++y) for(int x=1;x<=5;++x) {
                Pixel p{};
                Kine_Skia_Surface_GetPixel(overlay,width*x/6,height*y/6,&p[0],&p[1],&p[2],&p[3]);
                pixels->push_back(p);
            }
        }
        require(Kine_VulkanCompositor_EndFrame(compositor)!=0, "EndFrame");
    };
    auto sample = [&](const char *label, bool enabled,float scale,bool moving=false) {
        Kine_Filament_SetCloudResolutionScale(ctx,scale);
        Kine_Filament_SetClouds(ctx, enabled, 0.75f, 0.7f, 700.0f, 250.0f, 1.0f, 1.0f, 1.0f);
        for(int i=0;i<12;++i) render();
        std::vector<double> times;times.reserve(size_t(frames));
        for(int i=0;i<frames;++i) {
            if(moving) {
                const double x=double(i)*0.75;
                Kine_Filament_SetCameraLookAt(ctx,x,0,0,x+double(i)*0.2,700,-900,0,1,0);
            }
            auto start=std::chrono::steady_clock::now();
            render();
            auto end=std::chrono::steady_clock::now();
            times.push_back(std::chrono::duration<double,std::milli>(end-start).count());
        }
        std::sort(times.begin(),times.end());
        double sum=std::accumulate(times.begin(),times.end(),0.0);
        std::printf("CLOUD_BENCH_RESULT,%s,mean_ms=%.3f,median_ms=%.3f,p95_ms=%.3f,fps=%.2f\n",
                    label,sum/frames,times[frames/2],times[size_t(frames)*95/100],1000.0*frames/sum);
        std::fflush(stdout);
    };
    sample("off1",false,1);
    sample("full1",true,1);
    sample("half1",true,0.5f);
    sample("off2",false,1);
    sample("half2",true,0.5f);
    sample("full2",true,1);
    sample("moving_full",true,1,true);
    sample("moving_half",true,0.5f,true);
    Kine_Filament_SetCameraLookAt(ctx,0,0,0,0,700,-900,0,1,0);

    std::vector<Pixel> clear,full,half,foregroundFull,foregroundHalf;
    Kine_Filament_SetClouds(ctx,false,1.0f,1.0f,700,400,1,1,1);
    render(&clear,false,0);
    Kine_Filament_SetClouds(ctx,true,1.0f,1.0f,700,400,1,1,1);
    Kine_Filament_SetCloudResolutionScale(ctx,1);render(&full,false,0);
    Kine_Filament_SetCloudResolutionScale(ctx,0.5f);render(&half,false,0);
    Kine_Filament_SetCloudResolutionScale(ctx,1);render(&foregroundFull,true,0);
    Kine_Filament_SetCloudResolutionScale(ctx,0.5f);render(&foregroundHalf,true,0);
    auto difference=[](const auto &a,const auto &b) {
        double sum=0;
        for(size_t i=0;i<a.size();++i) for(size_t c=0;c<3;++c) sum+=std::abs(int(a[i][c])-int(b[i][c]));
        return sum/(a.size()*3);
    };
    std::printf("CLOUD_VISUAL clear-full=%.3f clear-half=%.3f full-half=%.3f foreground-center-diff=%.3f",difference(clear,full),difference(clear,half),difference(full,half),difference(std::vector<Pixel>{foregroundFull[12]},std::vector<Pixel>{foregroundHalf[12]}));
    std::puts("");
    require(difference(clear,full)>0.25 && difference(clear,half)>0.25,"both paths display clouds");
    require(difference(full,half)<20,"half resolution preserves cloud colors and coverage");
    require(difference(std::vector<Pixel>{foregroundFull[12]},std::vector<Pixel>{foregroundHalf[12]})<4,"foreground occludes clouds");
    Kine_Filament_DestroyMesh(ctx,mesh);
    std::puts("CLOUD_BENCH_PASSED");
    Kine_Filament_Destroy(ctx);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
