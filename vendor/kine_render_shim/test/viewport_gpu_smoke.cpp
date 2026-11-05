#include "kine_filament_shim.h"
#include "kine_skia.h"
#include "kine_vulkan_compositor.h"
#include <SDL3/SDL.h>
#include <filament/Engine.h>
#include <math/mat4.h>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

static void check(bool ok, const char *message) {if (!ok) {std::fprintf(stderr,"FAIL: %s\n",message); std::exit(1);}}
static std::array<uint8_t,4> pixel(KineSkiaSurface *s, int x,int y) {
    std::array<uint8_t,4> c{}; Kine_Skia_Surface_GetPixel(s,x,y,&c[0],&c[1],&c[2],&c[3]); return c;
}
int main() {
    check(SDL_Init(SDL_INIT_VIDEO),"SDL init");
    auto *window=SDL_CreateWindow("ViewportFrame GPU regression",512,256,SDL_WINDOW_VULKAN|SDL_WINDOW_HIDDEN);
    check(window,"hidden Vulkan window");
    auto *ctx=Kine_Filament_CreateForVulkanCompositorWindow(window,512,256);
    check(ctx,"Filament context");
    auto *engine=static_cast<filament::Engine *>(Kine_Filament_GetEngine(ctx));
    auto *compositor=static_cast<KineVulkanCompositor *>(Kine_Filament_GetVulkanCompositor(ctx));
    check(compositor,"shared compositor");
    size_t baseViews=engine->getViewCount();
    std::vector<KineFilamentViewport *> handles;
    for(int i=0;i<1000;++i) handles.push_back(Kine_Filament_Viewport_Create(ctx));
    check(engine->getViewCount()==baseViews,"creating handles allocates no views");
    uint32_t alive=0,pages=0;uint64_t renders=0;
    Kine_Filament_Viewport_Stats(ctx,&alive,&pages,&renders);
    check(alive==1000 && pages==0,"lazy atlas allocation");
    auto *mesh=Kine_Filament_CreateMesh(ctx,1);
    KineFilamentDrawItem item{}; item.mesh=mesh; item.r=1;item.g=0.05f;item.b=0.05f;item.transmission=1;
    item.transform[0]=item.transform[5]=item.transform[10]=item.transform[15]=1;
    KineViewportSettings settings{};
    settings.camera[0]=settings.camera[5]=settings.camera[10]=settings.camera[15]=1;
    settings.camera[11]=6;settings.fieldOfView=60;settings.width=settings.height=64;
    settings.ambient[0]=settings.ambient[1]=settings.ambient[2]=1;
    auto frame=[&](bool updateAll,bool changed,bool inspect) {
        auto *base=static_cast<KineSkiaSurface *>(Kine_VulkanCompositor_BeginFrame(compositor));
        check(base,"begin GUI frame");Kine_Skia_Surface_Clear(base,20,30,40,255);
        Kine_Filament_Viewport_Begin(ctx);
        if(updateAll) for(int i=0;i<128;++i) check(Kine_Filament_Viewport_Update(handles[i],&settings,&item,1,1),"update preview");
        else if(changed) {
            KineFilamentDrawItem green=item; green.r=0.05f;green.g=1;
            check(Kine_Filament_Viewport_Update(handles[0],&settings,&green,1,2),"animate one preview");
        }
        if(Kine_Filament_Viewport_HasWork(ctx)) Kine_Filament_Viewport_RenderFrame(ctx,1.0f/60.0f,false);
        auto *overlay=static_cast<KineSkiaSurface *>(Kine_VulkanCompositor_BeginOverlay(compositor));
        check(overlay,"begin overlay");
        Kine_Filament_Viewport_Draw(handles[0],overlay,0,0,128,128,1,1,1,1);
        Kine_Filament_Viewport_Draw(handles[1],overlay,128,0,128,128,1,1,1,1);
        if(inspect) {
            auto center=pixel(overlay,64,64),still=pixel(overlay,192,64),outside=pixel(overlay,2,2);
            std::printf("pixels: active=%u,%u,%u static=%u,%u,%u background=%u,%u,%u\n",center[0],center[1],center[2],still[0],still[1],still[2],outside[0],outside[1],outside[2]);
            check(center[1]>center[0]+40,"animated viewport updated to green");
            check(still[0]>still[1]+40,"dirty tile redraw preserved cached red neighbor");
            check(outside[0]<45 && outside[1]<55 && outside[2]<65,"transparent preview background");
        }
        check(Kine_VulkanCompositor_EndFrame(compositor)!=0,"present frame");
    };
    auto start=std::chrono::steady_clock::now();frame(true,false,false);
    Kine_Filament_Viewport_Stats(ctx,&alive,&pages,&renders);
    check(pages==1 && renders==128,"128 previews share one atlas page");
    check(engine->getViewCount()==baseViews+3,"all previews share three additional Views");
    frame(true,false,false);
    Kine_Filament_Viewport_Stats(ctx,&alive,&pages,&renders);check(renders==128,"unchanged previews do not re-render");
    frame(false,true,true);
    Kine_Filament_Viewport_Stats(ctx,&alive,&pages,&renders);check(renders==129,"animation redraws only one tile");
    // Two different camera updates in one batch must keep independent uniforms.
    auto *base=static_cast<KineSkiaSurface *>(Kine_VulkanCompositor_BeginFrame(compositor));
    check(base,"begin camera frame"); Kine_Skia_Surface_Clear(base,20,30,40,255);
    Kine_Filament_Viewport_Begin(ctx);
    auto nearCamera=settings; nearCamera.camera[11]=8;
    auto awayCamera=settings; awayCamera.camera[3]=100;
    KineFilamentDrawItem green=item; green.r=0.05f;green.g=1;
    check(Kine_Filament_Viewport_Update(handles[0],&nearCamera,&green,1,2),"first camera update");
    check(Kine_Filament_Viewport_Update(handles[1],&awayCamera,&item,1,1),"second camera update");
    Kine_Filament_Viewport_RenderFrame(ctx,1.0f/60.0f,false);
    auto *overlay=static_cast<KineSkiaSurface *>(Kine_VulkanCompositor_BeginOverlay(compositor));
    check(overlay,"camera overlay");
    Kine_Filament_Viewport_Draw(handles[0],overlay,0,0,128,128,1,1,1,1);
    Kine_Filament_Viewport_Draw(handles[1],overlay,128,0,128,128,1,1,1,1);
    auto center=pixel(overlay,64,64),empty=pixel(overlay,192,64);
    check(center[1]>center[0]+40,"shared View preserves each preview camera");
    check(empty[0]==20 && empty[1]==30 && empty[2]==40,"camera movement clears the old image");
    check(Kine_VulkanCompositor_EndFrame(compositor)!=0,"present camera frame");
    auto inspectPreview=[&](const KineViewportSettings &configuration,const KineFilamentDrawItem *draws,uint32_t count,uint64_t version,bool grid,int gridStep=16) {
        auto *base=static_cast<KineSkiaSurface *>(Kine_VulkanCompositor_BeginFrame(compositor));
        check(base,"begin resized/effects frame");Kine_Skia_Surface_Clear(base,20,30,40,255);
        Kine_Filament_Viewport_Begin(ctx);
        check(Kine_Filament_Viewport_Update(handles[0],&configuration,draws,count,version),"update resized/effects preview");
        // The GUI base pass can still use the previously published image here.
        Kine_Filament_Viewport_Draw(handles[0],base,0,0,256,256,1,1,1,1);
        if(configuration.width==60 && configuration.camera[3]==0) {
            auto cached=pixel(base,128,128);check(cached[1]>cached[0]+40,"resize retains the old published image coordinates until redraw");
        }
        Kine_Skia_Surface_Clear(base,20,30,40,255);
        if(Kine_Filament_Viewport_HasWork(ctx))Kine_Filament_Viewport_RenderFrame(ctx,1.0f/60.0f,false);
        auto *overlay=static_cast<KineSkiaSurface *>(Kine_VulkanCompositor_BeginOverlay(compositor));
        check(overlay,"resized/effects overlay");Kine_Filament_Viewport_Draw(handles[0],overlay,0,0,256,256,1,1,1,1);
        std::vector<std::array<uint8_t,4>> result;
        result.push_back(pixel(overlay,128,128));
        if(grid) for(int y=gridStep/2;y<256;y+=gridStep)for(int x=gridStep/2;x<256;x+=gridStep)result.push_back(pixel(overlay,x,y));
        check(Kine_VulkanCompositor_EndFrame(compositor)!=0,"present resized/effects preview");return result;
    };
    for(auto size : {std::array<int,2>{60,36},{52,48},{96,80},{44,40},{128,64}}) {
        auto resized=settings;resized.width=size[0];resized.height=size[1];resized.postProcessing=1;
        auto visible=inspectPreview(resized,&green,1,2,false);
        std::printf("resize %dx%d center=%u,%u,%u\n",size[0],size[1],visible[0][0],visible[0][1],visible[0][2]);
        check(visible[0][1]>visible[0][0]+40,"resized preview draws its current object");
        resized.camera[3]=100;
        auto empty=inspectPreview(resized,&green,1,2,true);
        for(auto c:empty) {check(std::abs(int(c[0])-20)<=2 && std::abs(int(c[1])-30)<=2 && std::abs(int(c[2])-40)<=2,"resizing and empty scenes leave no trails (two-level dithering tolerance)");}
    }
    auto effectSettings=settings;effectSettings.width=effectSettings.height=128;effectSettings.postProcessing=1;
    auto bright=inspectPreview(effectSettings,&green,1,2,false);
    effectSettings.effectMask=8;effectSettings.color[0]=1;effectSettings.color[1]=-8;effectSettings.color[2]=effectSettings.color[3]=1;
    effectSettings.color[4]=effectSettings.color[5]=effectSettings.color[6]=1;
    auto dark=inspectPreview(effectSettings,&green,1,2,false);
    std::printf("colour grading: green %u -> %u\n",bright[0][1],dark[0][1]);
    check(dark[0][1]+40<bright[0][1],"local postprocessing changes the rendered pixels");
    // A directional light must cast a real geometric shadow onto another part.
    KineFilamentDrawItem shadowItems[2]={item,item};
    shadowItems[0].r=0.8f;shadowItems[0].g=shadowItems[0].b=0.05f;
    shadowItems[0].transform[0]=shadowItems[0].transform[5]=shadowItems[0].transform[10]=2;shadowItems[0].transform[7]=2;shadowItems[0].flags=KINE_FILAMENT_DRAW_CAST_SHADOWS|KINE_FILAMENT_DRAW_RECEIVE_SHADOWS;
    shadowItems[1].r=shadowItems[1].g=shadowItems[1].b=0.6f;shadowItems[1].flags=KINE_FILAMENT_DRAW_RECEIVE_SHADOWS;
    shadowItems[1].transform[0]=shadowItems[1].transform[10]=8;shadowItems[1].transform[5]=0.1f;shadowItems[1].transform[7]=-1;
    auto shadowSettings=settings;shadowSettings.width=shadowSettings.height=256;shadowSettings.postProcessing=1;
    shadowSettings.ambient[0]=shadowSettings.ambient[1]=shadowSettings.ambient[2]=0.02f;
    shadowSettings.lightColor[0]=shadowSettings.lightColor[1]=shadowSettings.lightColor[2]=1;
    shadowSettings.lightDirection[0]=0;shadowSettings.lightDirection[1]=-1;shadowSettings.lightDirection[2]=0;
    auto pose=filament::math::mat4f::lookAt(filament::math::float3{4,4,6},filament::math::float3{0,0,0},filament::math::float3{0,1,0});
    for(int row=0;row<4;++row)for(int col=0;col<4;++col)shadowSettings.camera[row*4+col]=pose[col][row];
    auto noLight=shadowSettings;noLight.lightColor[0]=noLight.lightColor[1]=noLight.lightColor[2]=0;
    auto ambientOnly=inspectPreview(noLight,shadowItems,2,10,true,4);
    auto unshadowed=inspectPreview(shadowSettings,shadowItems,2,10,true,4);
    int directDelta=0;for(size_t i=0;i<unshadowed.size();++i)directDelta=std::max(directDelta,int(unshadowed[i][0])-int(ambientOnly[i][0]));
    std::printf("direct lighting max=%d\n",directDelta);
    shadowSettings.shadows=1;auto shadowed=inspectPreview(shadowSettings,shadowItems,2,10,true,4);
    int shadowPixels=0,maxDarkening=0;
    for(size_t i=0;i<shadowed.size();++i){int delta=int(unshadowed[i][0])-int(shadowed[i][0]);maxDarkening=std::max(maxDarkening,delta);if(delta>10 && std::abs(int(unshadowed[i][0])-int(unshadowed[i][1]))<5 && std::abs(int(unshadowed[i][1])-int(unshadowed[i][2]))<5)++shadowPixels;}
    std::printf("shadow samples: darkened=%d max=%d\n",shadowPixels,maxDarkening);
    check(shadowPixels>=2,"preview objects cast visible shadows onto a receive-only floor");
    auto bloomSettings=settings;bloomSettings.width=bloomSettings.height=128;bloomSettings.postProcessing=1;bloomSettings.effectMask=1;
    bloomSettings.bloom[1]=0.6f;bloomSettings.bloom[2]=128;bloomSettings.bloom[3]=0;
    auto neon=item;neon.materialKind=KINE_MAT_NEON;neon.param1=6;neon.transmission=0;
    auto withoutBloom=inspectPreview(bloomSettings,&neon,1,20,true,8);
    bloomSettings.bloom[0]=1;auto withBloom=inspectPreview(bloomSettings,&neon,1,20,true,8);
    int haloPixels=0;
    for(size_t i=0;i<withBloom.size();++i)if(std::abs(int(withoutBloom[i][0])-20)<3 && std::abs(int(withoutBloom[i][1])-30)<3 && std::abs(int(withoutBloom[i][2])-40)<3 && int(withBloom[i][0])>int(withoutBloom[i][0])+3)++haloPixels;
    std::printf("Neon bloom halo samples=%d\n",haloPixels);check(haloPixels>0,"Neon bloom extends beyond the object's silhouette");
    effectSettings.effectMask=0;
    auto opaque=inspectPreview(effectSettings,&green,1,21,false);
    auto translucent=green;translucent.transmission=0.5f;
    auto half=inspectPreview(effectSettings,&translucent,1,22,false);
    check(half[0][1]<opaque[0][1],"part transparency attenuates the preview image");
    auto raised=green;raised.transform[7]=1.5f;
    auto positioned=inspectPreview(effectSettings,&raised,1,25,true,4);
    int minX=256,minY=256,maxX=-1,maxY=-1;
    for(size_t i=1;i<positioned.size();++i){auto c=positioned[i];if(std::abs(int(c[0])-20)>3 || std::abs(int(c[1])-30)>3 || std::abs(int(c[2])-40)>3){int x=2+int((i-1)%64)*4,y=2+int((i-1)/64)*4;minX=std::min(minX,x);minY=std::min(minY,y);maxX=std::max(maxX,x);maxY=std::max(maxY,y);}}
    std::printf("positioned object bounds=%d,%d-%d,%d\n",minX,minY,maxX,maxY);
    auto upper=positioned[1+18*64+32],lower=positioned[1+45*64+32];
    std::printf("camera orientation: upper=%u,%u,%u lower=%u,%u,%u\n",upper[0],upper[1],upper[2],lower[0],lower[1],lower[2]);
    check(upper[1]>upper[0]+40 && std::abs(int(lower[0])-20)<=2 && std::abs(int(lower[1])-30)<=2,"positive world Y appears above the preview centre");
    auto reflected=effectSettings;reflected.effectMask=32;reflected.reflections[0]=1;reflected.reflections[1]=0.1f;reflected.reflections[2]=0.01f;reflected.reflections[3]=10;reflected.reflections[4]=1;
    inspectPreview(reflected,&green,1,23,false);
    check(engine->getViewCount()==baseViews+4,"SSR allocates only its own preview history View");
    inspectPreview(reflected,&green,1,23,false);
    Kine_Filament_Viewport_Stats(ctx,&alive,&pages,&renders);const auto settled=renders;
    inspectPreview(reflected,&green,1,23,false);
    Kine_Filament_Viewport_Stats(ctx,&alive,&pages,&renders);check(renders==settled,"static SSR previews cache after warming their own history");
    inspectPreview(effectSettings,&green,1,24,false);
    check(engine->getViewCount()==baseViews+3,"disabling SSR releases private history");
    // Global Lighting changes also invalidate an otherwise unchanged image.
    Kine_Filament_SetColorGrading(ctx,-8,1,1,0,0,0);
    auto inherited=inspectPreview(effectSettings,&green,1,24,false);
    check(inherited[0][1]+40<opaque[0][1],"inherited Lighting grading invalidates a cached preview");
    Kine_Filament_ClearColorGrading(ctx);
    Kine_Filament_Viewport_Stats(ctx,&alive,&pages,&renders);const auto pageHighWater=pages;
    for(auto *handle:handles) Kine_Filament_Viewport_Destroy(handle);
    handles.clear();
    for(int i=0;i<128;++i) handles.push_back(Kine_Filament_Viewport_Create(ctx));
    frame(true,false,false);
    Kine_Filament_Viewport_Stats(ctx,&alive,&pages,&renders);check(pages==pageHighWater,"destroyed slots are recycled");
    for(auto *handle:handles) Kine_Filament_Viewport_Destroy(handle);
    auto *resized=Kine_Filament_Viewport_Create(ctx);
    auto large=settings;large.width=large.height=512;
    Kine_Filament_Viewport_Begin(ctx);
    check(Kine_Filament_Viewport_Update(resized,&large,&item,1,1),"resize into a recycled page");
    Kine_Filament_Viewport_Stats(ctx,&alive,&pages,&renders);check(pages==pageHighWater,"empty atlas pages are recycled across size buckets");
    Kine_Filament_Viewport_Destroy(resized);
    Kine_Filament_DestroyMesh(ctx,mesh);

    // Submit without pixel readbacks so previous frames can still be in flight.
    for (int i = 0; i < 12; ++i) {
        auto *surface = static_cast<KineSkiaSurface *>(Kine_VulkanCompositor_BeginFrame(compositor));
        check(surface, "begin in-flight frame");
        Kine_Skia_Surface_Clear(surface, 20, 30, 40, 255);
        if (i % 2 == 0) {
            Kine_Filament_Viewport_Begin(ctx);
            Kine_Filament_Viewport_RenderFrame(ctx, 1.0f / 60.0f, true);
        }
        if (i % 3 == 0) {
            check(Kine_VulkanCompositor_BeginOverlay(compositor), "begin in-flight overlay");
        }
        check(Kine_VulkanCompositor_EndFrame(compositor), "present in-flight frame");
    }
    check(SDL_SetWindowSize(window, 640, 320), "resize in-flight window");
    SDL_SyncWindow(window);
    Kine_Filament_Resize(ctx, 640, 320);
    compositor = static_cast<KineVulkanCompositor *>(Kine_Filament_GetVulkanCompositor(ctx));
    auto *resizedSurface = static_cast<KineSkiaSurface *>(Kine_VulkanCompositor_BeginFrame(compositor));
    check(resizedSurface, "begin frame after swapchain resize");
    Kine_Skia_Surface_Clear(resizedSurface, 20, 30, 40, 255);
    check(Kine_VulkanCompositor_EndFrame(compositor), "present after swapchain resize");

    double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
    std::printf("VIEWPORT_GPU_SMOKE_PASSED 1000 handles, 128 visible, one page; setup+checks %.2f ms\n",ms);
    Kine_Filament_Destroy(ctx);SDL_DestroyWindow(window);SDL_Quit();return 0;
}
