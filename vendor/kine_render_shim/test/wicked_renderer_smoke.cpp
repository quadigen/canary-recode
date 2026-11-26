#include "kine_filament_shim.h"
#include "kine_vulkan_compositor.h"
#include <filament/Engine.h>
#include <filament/Scene.h>
#include <filament/View.h>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>

extern "C" int Kine_OdinCompositor_CopySwapchainBackend(
        uint32_t, KineVulkanSwapchainBackend*) {
    return 0;
}

static void require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "NATIVE_WICKED_FAIL: %s\n", message);
        std::exit(1);
    }
}

int main() {
    constexpr int width = 256;
    constexpr int height = 160;
    using Pixels = std::array<uint8_t, width * height * 4>;
    KineFilamentContext* context = Kine_Filament_Create(width, height);
    require(context, "create Kinemium headless Vulkan renderer");
    auto* engine = static_cast<filament::Engine*>(Kine_Filament_GetEngine(context));
    auto* scene = static_cast<filament::Scene*>(Kine_Filament_GetScene(context));
    require(engine && scene, "engine and scene");
    Kine_Filament_SetCameraPerspective(context, 70.0, double(width) / height, 0.1, 2600.0);
    Kine_Filament_SetCameraLookAt(context, 0.0f, 20.0f, 0.0f,
            0.0f, 250.0f, 300.0f, 0.0f, 1.0f, 0.0f);
    auto atmosphere = [&](float sunY) {
        Kine_Filament_SetSkyAtmosphere(context, 0.65f, sunY, 0.35f,
                0.20f, 0.47f, 0.92f, 0.72f, 0.46f, 0.33f,
                0.04f, 0.06f, 0.1f, 100000.0f);
        require(scene->getSkybox(), "atmosphere installed in native scene");
    };
    bool drawScreenScene = false;
    uint64_t screenVersion = 1;
    uint32_t screenItemCount = 2;
    KineFilamentDrawItem screenItems[3]{};
    auto frame = [&]() {
        Pixels pixels;
        pixels.fill(0xa5);
        Kine_Filament_Viewport_Begin(context);
        if (drawScreenScene)
            Kine_Filament_DrawMeshListVersioned(context, screenItems, screenItemCount, 992, screenVersion);
        Kine_Filament_Viewport_RenderFrame(context, 1.0f / 30.0f, true);
        engine->flushAndWait();
        Kine_Filament_ReadPixels(context, pixels.data());
        bool copied = false;
        for (uint8_t value : pixels) {
            if (value != 0xa5) {
                copied = true;
                break;
            }
        }
        require(copied, "native offscreen color readback");
        return pixels;
    };
    auto difference = [](Pixels const& a, Pixels const& b) {
        uint64_t sum = 0;
        for (size_t i = 0; i < a.size(); i += 4)
            for (size_t c = 0; c < 3; ++c)
                sum += uint64_t(std::abs(int(a[i + c]) - int(b[i + c])));
        return sum;
    };
    auto average = [](Pixels const& a) {
        uint64_t sum = 0;
        for (size_t i = 0; i < a.size(); i += 4)
            sum += uint64_t(a[i]) + a[i + 1] + a[i + 2];
        return double(sum) / (width * height);
    };
    if (const char* checkGtao = std::getenv("KINE_EXPECT_GTAO");
            checkGtao && checkGtao[0] == '1') {
        const float values[9] = {1, 1, 0.001f, 0.10f, 3, 3, 6, 5, 1};
        Kine_Filament_SetAdvancedEffect(context, 14, true, values, 9);
        auto* view = static_cast<filament::View*>(Kine_Filament_GetView(context));
        require(view, "native GTAO view");
        const auto options = view->getAmbientOcclusionOptions();
        require(options.gtao.sampleSliceCount == 6 &&
                options.gtao.sampleStepsPerSlice == 5 &&
                options.gtao.useVisibilityBitmasks && !options.bentNormals &&
                options.resolution == 1.0f,
                "native GTAO high-quality configuration");
        Kine_Filament_SetAdvancedEffect(context, 14, false, values, 9);
        require(view->getAmbientOcclusionOptions().gtao.sampleSliceCount == 4 &&
                !view->getAmbientOcclusionOptions().gtao.useVisibilityBitmasks,
                "native GTAO settings restore defaults");
        std::puts("WICKED_GTAO_OPTIONS_PASSED");
    }
    atmosphere(0.85f);
    if (const char* expectFog = std::getenv("KINE_EXPECT_AERIAL_FOG");
            expectFog && expectFog[0] == '1') {
        auto* view = static_cast<filament::View*>(Kine_Filament_GetView(context));
        require(view && view->getFogOptions().enabled &&
                view->getFogOptions().fogColorFromIbl,
                "procedural atmosphere feeds native depth-aware aerial fog");
        Kine_Filament_SetSunRays(context, false, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, false);
        atmosphere(0.55f);
        require(!view->getFogOptions().enabled,
                "explicit user fog settings take priority over aerial fog");
    }
    Kine_Filament_SetClouds(context, false, 0.7f, 0.7f, 250.0f, 200.0f, 1, 1, 1);
    Pixels baseline = frame();
    auto before = scene->getRenderableCount();
    Kine_Filament_SetClouds(context, true, 0.85f, 0.85f, 250.0f, 200.0f, 1, 1, 1);
    require(scene->getRenderableCount() == before + 1, "native cloud layer attached");
    if (const char* requireGpu = std::getenv("KINE_EXPECT_GPU_CLOUD_NOISE");
            requireGpu && requireGpu[0] == '1')
        require(Kine_Filament_GetCloudNoiseSource(context) == 1,
                "Wicked cloud textures generated on the native Vulkan device");
    std::printf("CLOUD_NOISE_SOURCE=%d\n", Kine_Filament_GetCloudNoiseSource(context));
    Pixels cloudy = frame();
    Pixels repeat = frame();
    atmosphere(-0.8f);
    Pixels night = frame();
    Kine_Filament_SetClouds(context, true, 0.25f, 0.3f, 250.0f, 200.0f, 1, 1, 1);
    Pixels clear = frame();
    Kine_Filament_SetClouds(context, false, 0.0f, 0.0f, 250.0f, 200.0f, 1, 1, 1);
    require(scene->getRenderableCount() == before, "native cloud layer detached");
    Pixels noClouds = frame();
    auto cloudDifference = difference(cloudy, baseline);
    auto nightDifference = difference(night, cloudy);
    auto coverageDifference = difference(clear, night);
    auto disabledDifference = difference(noClouds, clear);
    std::printf("NATIVE_WICKED_RENDER daylight=%.3f clouds=%.3f night=%.3f cloud_delta=%llu night_delta=%llu cover_delta=%llu disabled_delta=%llu repeat_delta=%llu\n",
            average(baseline), average(cloudy), average(night),
            static_cast<unsigned long long>(cloudDifference),
            static_cast<unsigned long long>(nightDifference),
            static_cast<unsigned long long>(coverageDifference),
            static_cast<unsigned long long>(disabledDifference),
            static_cast<unsigned long long>(difference(cloudy, repeat)));
    require(average(baseline) > 0 && average(night) < average(baseline), "day night sky response");
    require(cloudDifference > 1000, "cloud raymarch not visible");
    if (const char* expectGpu = std::getenv("KINE_EXPECT_GPU_CLOUD_NOISE");
            expectGpu && expectGpu[0] == '1')
        require(cloudDifference > 2000000, "native GPU cloud volume missing 3D slices");
    require(nightDifference > 1000, "sun height has no effect");
    require(coverageDifference > 1000, "cloud cover has no effect");
    require(disabledDifference > 1000, "cloud disable has no effect");
    if (const char* path = std::getenv("KINE_CLOUD_CAPTURE"); path && path[0]) {
        Kine_Filament_SetCameraLookAt(context, 0.0f, 20.0f, 0.0f,
                0.0f, 700.0f, 200.0f, 0.0f, 1.0f, 0.0f);
        atmosphere(0.85f);
        const char* coverText = std::getenv("KINE_CLOUD_CAPTURE_COVER");
        const float captureCover = coverText ? std::strtof(coverText, nullptr) : 1.0f;
        Kine_Filament_SetClouds(context, true, captureCover, 1.0f, 700.0f, 200.0f, 1, 1, 1);
        auto capture = frame();
        std::ofstream output(path, std::ios::binary);
        output << "P6\n" << width << " " << height << "\n255\n";
        uint64_t edgeContrast = 0;
        uint32_t highFrequency = 0;
        for (int y = height - 1; y >= 0; --y) {
            for (int x = 0; x < width; ++x) {
                const size_t offset = size_t(y * width + x) * 4;
                const char rgb[3] = {char(capture[offset]), char(capture[offset + 1]),
                        char(capture[offset + 2])};
                output.write(rgb, 3);
                if (x > 0) {
                    uint32_t difference = 0;
                    for (size_t c = 0; c < 3; ++c)
                        difference += unsigned(std::abs(int(capture[offset + c]) -
                                int(capture[offset + c - 4])));
                    edgeContrast += difference;
                    highFrequency += difference > 150 ? 1u : 0u;
                }
            }
        }
        output.close();
        std::printf("CLOUD_QUALITY_CAPTURE edge_contrast=%llu high_frequency=%u\n",
                static_cast<unsigned long long>(edgeContrast), highFrequency);
        require(edgeContrast > 150000 && highFrequency < width * height / 20,
                "cloud coverage or antialiasing quality regression");
        require(output.good(), "write cloud comparison frame");
    }
    const char* screenTests = std::getenv("KINE_EXPECT_SCREEN_EFFECTS");
    const char* giTests = std::getenv("KINE_EXPECT_EMISSIVE_GI");
    const char* ddgiTests = std::getenv("KINE_EXPECT_DDGI");
    const char* cloudShadowTests = std::getenv("KINE_EXPECT_CLOUD_SHADOWS");
    if ((screenTests && screenTests[0] == '1') ||
            (giTests && giTests[0] == '1') ||
            (ddgiTests && ddgiTests[0] == '1') ||
            (cloudShadowTests && cloudShadowTests[0] == '1')) {
        Kine_Filament_SetClouds(context, false, 0, 0, 700, 200, 1, 1, 1);
        Kine_Filament_SetAntiAliasing(context, false, false, false, 1);
        Kine_Filament_SetCameraLookAt(context, 0, 30, 0, 0, 30, 150, 0, 1, 0);
        auto* mesh = Kine_Filament_CreateMesh(context, 1);
        require(mesh, "create screen effect test geometry");
        for (int i = 0; i < 2; ++i) {
            screenItems[i].mesh = mesh;
            screenItems[i].materialKind = KINE_MAT_DEFAULT;
            screenItems[i].r = i == 0 ? 0.7f : 0.2f;
            screenItems[i].g = i == 0 ? 0.4f : 0.8f;
            screenItems[i].b = i == 0 ? 0.2f : 0.9f;
            screenItems[i].transmission = 1.0f;
            screenItems[i].flags = KINE_FILAMENT_DRAW_CULLING | KINE_FILAMENT_DRAW_RECEIVE_SHADOWS;
            screenItems[i].transform[0] = screenItems[i].transform[5] =
                    screenItems[i].transform[10] = i == 0 ? 65.0f : 35.0f;
            screenItems[i].transform[15] = 1.0f;
            screenItems[i].transform[3] = i == 0 ? 0.0f : 25.0f;
            screenItems[i].transform[7] = i == 0 ? 28.0f : 44.0f;
            screenItems[i].transform[11] = i == 0 ? 125.0f : 107.0f;
        }
        drawScreenScene = true;
        const Pixels ordinary = frame();
        const Pixels stableOrdinary = frame();
        const auto ordinaryNoise = difference(ordinary, stableOrdinary);
        std::printf("SCREEN_BASELINE_DELTA=%llu\n",
                static_cast<unsigned long long>(ordinaryNoise));
        const auto captureScreen = [&](const char* name, const Pixels& pixels) {
            const char* prefix = std::getenv("KINE_SCREEN_CAPTURE");
            if (!prefix || !prefix[0]) return;
            std::ofstream file(std::string(prefix) + "-" + name + ".ppm", std::ios::binary);
            file << "P6\n" << width << " " << height << "\n255\n";
            for (int y = height - 1; y >= 0; --y) {
                for (int x = 0; x < width; ++x) {
                    const size_t offset = size_t(y * width + x) * 4;
                    const char rgb[3]{char(pixels[offset]), char(pixels[offset + 1]),
                            char(pixels[offset + 2])};
                    file.write(rgb, 3);
                }
            }
            require(file.good(), "screen-space effect frame capture");
        };
        captureScreen("ordinary", stableOrdinary);
        const float outlineValues[4] = {1.0f, 2.5f, 0.03f, 0.2f};
        Kine_Filament_SetAdvancedEffect(context, 17, true, outlineValues, 4);
        bool effectEnabled = false;
        float returnedValues[4]{};
        require(Kine_Filament_GetAdvancedEffect(context, 17,
                &effectEnabled, returnedValues, 4) && effectEnabled &&
                returnedValues[1] == outlineValues[1], "outline effect settings roundtrip");
        const Pixels outlined = frame();
        captureScreen("outline", outlined);
        const auto outlineDelta = difference(stableOrdinary, outlined);
        std::printf("SCREEN_OUTLINE_DELTA=%llu\n",
                static_cast<unsigned long long>(outlineDelta));
        require(outlineDelta > ordinaryNoise + 1500,
                "screen-space outlines did not affect scene beyond natural frame variation");
        Kine_Filament_SetAdvancedEffect(context, 17, false, outlineValues, 4);
        const Pixels unoutlined = frame();
        const float cavityValues[4] = {4.0f, 5.0f, 0.0f, 250.0f};
        Kine_Filament_SetAdvancedEffect(context, 16, true, cavityValues, 4);
        require(Kine_Filament_GetAdvancedEffect(context, 16,
                &effectEnabled, returnedValues, 4) && effectEnabled &&
                returnedValues[0] == cavityValues[0], "cavity effect settings roundtrip");
        const Pixels cavity = frame();
        captureScreen("cavity", cavity);
        const auto cavityDelta = difference(unoutlined, cavity);
        std::printf("SCREEN_CAVITY_DELTA=%llu\n",
                static_cast<unsigned long long>(cavityDelta));
        require(cavityDelta > ordinaryNoise + 1500,
                "screen-space cavity did not affect scene beyond natural frame variation");
        Kine_Filament_SetAdvancedEffect(context, 16, false, cavityValues, 4);
        if (cloudShadowTests && cloudShadowTests[0] == '1') {
            atmosphere(0.85f);
            Kine_Filament_SetCameraLookAt(context, 0, 90, 0,
                    0, 0, 190, 0, 1, 0);
            screenItemCount = 2;
            screenItems[0].materialKind = KINE_MAT_DEFAULT;
            screenItems[0].r = 0.80f;
            screenItems[0].g = 0.75f;
            screenItems[0].b = 0.62f;
            screenItems[0].transform[0] = 350.0f;
            screenItems[0].transform[5] = 3.0f;
            screenItems[0].transform[10] = 350.0f;
            screenItems[0].transform[3] = 0.0f;
            screenItems[0].transform[7] = -5.0f;
            screenItems[0].transform[11] = 170.0f;
            screenItems[1].materialKind = KINE_MAT_DEFAULT;
            screenItems[1].transform[0] = 30.0f;
            screenItems[1].transform[5] = 45.0f;
            screenItems[1].transform[10] = 30.0f;
            screenItems[1].transform[3] = -45.0f;
            screenItems[1].transform[7] = 20.0f;
            screenItems[1].transform[11] = 150.0f;
            ++screenVersion;
            Kine_Filament_SetClouds(context, true, 1.0f, 1.0f,
                    180.0f, 500.0f, 1, 1, 1);
            frame();
            const Pixels unshadowed = frame();
            const Pixels unshadowedRepeat = frame();
            const auto motionNoise = difference(unshadowed, unshadowedRepeat);
            captureScreen("cloud-shadows-off", unshadowedRepeat);
            Kine_Filament_SetCloudShadowOptions(context, true, 1.0f,
                    0.25f, 0.0f, 0.0f, 1000.0f);
            bool obsoleteEnabled = false;
            float obsoleteValues[5]{};
            require(!Kine_Filament_GetAdvancedEffect(context, 20,
                    &obsoleteEnabled, obsoleteValues, 5),
                    "cloud shadows must not use a standalone lighting effect ID");
            frame();
            const Pixels shadowed = frame();
            captureScreen("cloud-shadows-on", shadowed);
            const auto shadowDelta = difference(unshadowedRepeat, shadowed);
            std::printf("CLOUD_SHADOWS_FRAME_DELTA=%llu baseline=%llu\n",
                    static_cast<unsigned long long>(shadowDelta),
                    static_cast<unsigned long long>(motionNoise));
            uint32_t darkened = 0;
            uint32_t baselineChanged = 0;
            for (size_t i = 0; i < shadowed.size(); i += 4) {
                const int originalBrightness = int(unshadowedRepeat[i]) +
                        int(unshadowedRepeat[i + 1]) + int(unshadowedRepeat[i + 2]);
                const int shadowBrightness = int(shadowed[i]) +
                        int(shadowed[i + 1]) + int(shadowed[i + 2]);
                const int earlierBrightness = int(unshadowed[i]) +
                        int(unshadowed[i + 1]) + int(unshadowed[i + 2]);
                darkened += originalBrightness - shadowBrightness > 18;
                baselineChanged += std::abs(earlierBrightness - originalBrightness) > 18;
            }
            std::printf("CLOUD_SHADOWS_DARK_PIXELS=%u baseline=%u\n",
                    darkened, baselineChanged);
            require(darkened > 100 + baselineChanged * 3,
                    "cloud shadows must darken localized geometry beyond frame variation");
            Kine_Filament_SetCloudShadowOptions(context, false, 1.0f,
                    0.25f, 0.0f, 0.0f, 1000.0f);
            frame();
            const Pixels unshadowedAgain = frame();
            const auto reverted = difference(shadowed, unshadowedAgain);
            std::printf("CLOUD_SHADOWS_DISABLE_DELTA=%llu\n",
                    static_cast<unsigned long long>(reverted));
            uint32_t restored = 0;
            for (size_t i = 0; i < shadowed.size(); i += 4) {
                const int shadowBrightness = int(shadowed[i]) +
                        int(shadowed[i + 1]) + int(shadowed[i + 2]);
                const int restoredBrightness = int(unshadowedAgain[i]) +
                        int(unshadowedAgain[i + 1]) + int(unshadowedAgain[i + 2]);
                restored += restoredBrightness - shadowBrightness > 18;
            }
            std::printf("CLOUD_SHADOWS_RESTORED_PIXELS=%u\n", restored);
            require(restored > 100 + baselineChanged * 3,
                    "disabling cloud shadows must restore localized scene lighting");
            Kine_Filament_SetClouds(context, false, 0.0f, 0.0f,
                    180.0f, 500.0f, 1, 1, 1);
            Kine_Filament_SetCameraLookAt(context, 0, 30, 0,
                    0, 30, 150, 0, 1, 0);
            for (int i = 0; i < 2; ++i) {
                screenItems[i].transform[0] =
                    screenItems[i].transform[5] =
                    screenItems[i].transform[10] = i == 0 ? 65.0f : 35.0f;
                screenItems[i].transform[3] = i == 0 ? 0.0f : 25.0f;
                screenItems[i].transform[7] = i == 0 ? 28.0f : 44.0f;
                screenItems[i].transform[11] = i == 0 ? 125.0f : 107.0f;
                screenItems[i].r = i == 0 ? 0.7f : 0.2f;
                screenItems[i].g = i == 0 ? 0.4f : 0.8f;
                screenItems[i].b = i == 0 ? 0.2f : 0.9f;
            }
            atmosphere(-0.8f);
            ++screenVersion;
            std::puts("CLOUD_SHADOWS_GPU_PASSED");
        }
        if (giTests && giTests[0] == '1') {
            screenItems[1].transform[11] = 95.0f;
            screenItems[2] = screenItems[1];
            screenItems[2].materialKind = KINE_MAT_NEON;
            screenItems[2].r = 1.0f;
            screenItems[2].g = 0.05f;
            screenItems[2].b = 0.02f;
            screenItems[2].param1 = 5.0f;
            screenItems[2].transform[0] = screenItems[2].transform[5] =
                    screenItems[2].transform[10] = 33.0f;
            screenItems[2].transform[11] = 90.0f;
            screenItemCount = 3;
            ++screenVersion;
            frame();
            Pixels giBaseline = frame();
            captureScreen("emissive-gi-off", giBaseline);
            const float giValues[6] = {5.0f, 30.0f, 0.1f, 0.5f, 250.0f, 32};
            Kine_Filament_SetAdvancedEffect(context, 18, true, giValues, 6);
            float returnedGi[6]{};
            require(Kine_Filament_GetAdvancedEffect(context, 18,
                    &effectEnabled, returnedGi, 6) && effectEnabled &&
                    returnedGi[0] == giValues[0] &&
                    returnedGi[5] == giValues[5], "emissive GI property roundtrip");
            frame();
            Pixels giEnabled = frame();
            captureScreen("emissive-gi-on", giEnabled);
            const auto giDelta = difference(giBaseline, giEnabled);
            std::printf("EMISSIVE_GI_FRAME_DELTA=%llu\n",
                    static_cast<unsigned long long>(giDelta));
            require(giDelta > ordinaryNoise + 1500, "emissive GI must change geometry lighting");
            Kine_Filament_SetAdvancedEffect(context, 18, false, giValues, 6);
            Pixels giDisabled = frame();
            const auto giDisabledDelta = difference(giEnabled, giDisabled);
            std::printf("EMISSIVE_GI_DISABLE_DELTA=%llu\n",
                    static_cast<unsigned long long>(giDisabledDelta));
            require(giDisabledDelta > ordinaryNoise + 1500,
                    "disabling emissive GI must remove lighting");
            screenItems[2].param1 = 0.0f;
            ++screenVersion;
            frame();
            const Pixels noEmitter = frame();
            Kine_Filament_SetAdvancedEffect(context, 18, true, giValues, 6);
            frame();
            const Pixels giWithoutEmitter = frame();
            const auto noEmitterDelta = difference(noEmitter, giWithoutEmitter);
            std::printf("EMISSIVE_GI_NO_SOURCE_DELTA=%llu\n",
                    static_cast<unsigned long long>(noEmitterDelta));
            require(noEmitterDelta < ordinaryNoise + 20000,
                    "emissive GI should not generate light without visible emitters");
            Kine_Filament_SetAdvancedEffect(context, 18, false, giValues, 6);
            Kine_Filament_SetCameraLookAt(context, 0.0f, 65.0f, 0.0f,
                    0.0f, 5.0f, 140.0f, 0.0f, 1.0f, 0.0f);
            screenItems[0].transform[0] = 140.0f;
            screenItems[0].transform[5] = 6.0f;
            screenItems[0].transform[10] = 140.0f;
            screenItems[0].transform[3] = 0.0f;
            screenItems[0].transform[7] = -10.0f;
            screenItems[0].transform[11] = 115.0f;
            screenItems[1].transform[0] = 60.0f;
            screenItems[1].transform[5] = 70.0f;
            screenItems[1].transform[10] = 8.0f;
            screenItems[1].transform[3] = 0.0f;
            screenItems[1].transform[7] = 25.0f;
            screenItems[1].transform[11] = 158.0f;
            screenItems[2] = screenItems[1];
            screenItems[2].materialKind = KINE_MAT_NEON;
            screenItems[2].r = 1.0f;
            screenItems[2].g = 0.05f;
            screenItems[2].b = 0.02f;
            screenItems[2].param1 = 5.0f;
            screenItems[2].transform[0] = 55.0f;
            screenItems[2].transform[5] = 65.0f;
            screenItems[2].transform[10] = 3.0f;
            screenItems[2].transform[11] = 151.0f;
            ++screenVersion;
            frame();
            const Pixels ssgiBaseline = frame();
            captureScreen("ssgi-off", ssgiBaseline);
            const float ssgiValues[7] = {5.0f, 30.0f, 0.01f, 48.0f, 250.0f, 1.0f, 5.0f};
            Kine_Filament_SetAdvancedEffect(context, 1, true, ssgiValues, 7);
            float returnedSsgi[7]{};
            require(Kine_Filament_GetAdvancedEffect(context, 1,
                    &effectEnabled, returnedSsgi, 7) && effectEnabled &&
                    returnedSsgi[5] == 1.0f && returnedSsgi[6] == 5.0f,
                    "SSGI visibility and color bleeding settings");
            frame();
            const Pixels ssgiEnabled = frame();
            captureScreen("ssgi-on", ssgiEnabled);
            const auto ssgiDelta = difference(ssgiBaseline, ssgiEnabled);
            std::printf("SSGI_GI_FRAME_DELTA=%llu\n",
                    static_cast<unsigned long long>(ssgiDelta));
            require(ssgiDelta > ordinaryNoise + 1500,
                    "depth-aware SSGI must affect nearby receiver geometry");
            Kine_Filament_SetAdvancedEffect(context, 1, false, ssgiValues, 7);
            const float legacySsgiValues[5] = {1.0f, 3.0f, 0.05f, 16.0f, 100.0f};
            Kine_Filament_SetAdvancedEffect(context, 1, true, legacySsgiValues, 5);
            float restoredSsgi[5]{};
            require(Kine_Filament_GetAdvancedEffect(context, 1,
                    &effectEnabled, restoredSsgi, 5) && effectEnabled &&
                    restoredSsgi[3] == 16.0f, "legacy five-value SSGI compatibility");
            Kine_Filament_SetAdvancedEffect(context, 1, false, legacySsgiValues, 5);
            std::puts("EMISSIVE_GI_GPU_PASSED");
        }
        if (ddgiTests && ddgiTests[0] == '1') {
            Kine_Filament_SetCameraPerspective(context, 45.0,
                    double(width) / height, 0.1, 2600);
            Kine_Filament_SetCameraLookAt(context, 0, 35, 0,
                    0, 30, 125, 0, 1, 0);
            screenItemCount = 2;
            screenItems[0].materialKind = KINE_MAT_DEFAULT;
            screenItems[0].r = 0.5f;
            screenItems[0].g = 0.5f;
            screenItems[0].b = 0.5f;
            screenItems[0].transform[0] = 80;
            screenItems[0].transform[5] = 80;
            screenItems[0].transform[10] = 16;
            screenItems[0].transform[3] = 0;
            screenItems[0].transform[7] = 30;
            screenItems[0].transform[11] = 125;
            screenItems[1] = screenItems[0];
            screenItems[1].materialKind = KINE_MAT_NEON;
            screenItems[1].r = 1.0f;
            screenItems[1].g = 0.1f;
            screenItems[1].b = 0.03f;
            screenItems[1].param1 = 16.0f;
            screenItems[1].transform[0] = 30;
            screenItems[1].transform[5] = 30;
            screenItems[1].transform[10] = 30;
            screenItems[1].transform[3] = 80;
            screenItems[1].transform[7] = 35;
            screenItems[1].transform[11] = 50;
            ++screenVersion;
            frame();
            const Pixels beforeProbes = frame();
            captureScreen("ddgi-off", beforeProbes);
            uint32_t total = 0, filled = 0;
            uint64_t updated = 0;
            const float options[9] = {5, 25, 7, 3, 7, 128, 24, 0, 150};
            Kine_Filament_SetAdvancedEffect(context, 19, true, options, 9);
            frame();
            require(Kine_Filament_GetDDGIStats(context, &total, &filled, &updated) &&
                    total == 147 && filled > 0 && filled <= 24 && updated <= 24,
                    "DDGI initial probe grid and per-frame budget");
            for (int i = 0; i < 7; ++i) frame();
            require(Kine_Filament_GetDDGIStats(context, &total, &filled, &updated) &&
                    filled == total && updated >= total,
                    "DDGI persistent probe updates reached whole spatial grid");
            const Pixels withProbes = frame();
            captureScreen("ddgi-on", withProbes);
            const auto ddgiChange = difference(beforeProbes, withProbes);
            std::printf("DDGI_FRAME_DELTA=%llu\n",
                    static_cast<unsigned long long>(ddgiChange));
            require(ddgiChange > std::max<uint64_t>(150000, ordinaryNoise * 4),
                    "DDGI must illuminate visible receiver beyond frame variation");
            screenItems[1].param1 = 0.0f;
            ++screenVersion;
            for (int i = 0; i < 8; ++i) frame();
            const Pixels darkSource = frame();
            captureScreen("ddgi-emitter-off", darkSource);
            const auto sourceDelta = difference(withProbes, darkSource);
            std::printf("DDGI_OFFSCREEN_SOURCE_DELTA=%llu\n",
                    static_cast<unsigned long long>(sourceDelta));
            require(sourceDelta > std::max<uint64_t>(150000, ordinaryNoise * 4),
                    "DDGI must respond to off-screen emissive geometry");
            const float scrollingOptions[9] = {5, 25, 7, 3, 7, 128, 1, 0, 150};
            Kine_Filament_SetAdvancedEffect(context, 19, true, scrollingOptions, 9);
            Kine_Filament_SetCameraLookAt(context, 25, 35, 0,
                    25, 30, 125, 0, 1, 0);
            frame();
            require(Kine_Filament_GetDDGIStats(context, &total, &filled, &updated) &&
                    total == 147 && filled >= 100 && filled < 147,
                    "DDGI grid scroll retains overlapping probes with one-probe update budget");
            Kine_Filament_SetAdvancedEffect(context, 19, false, scrollingOptions, 9);
            frame();
            require(!Kine_Filament_GetDDGIStats(context, &total, &filled, &updated),
                    "disabling DDGI releases persistent probe textures");
            Kine_Filament_SetCameraLookAt(context, 0, 35, 0,
                    0, 30, 125, 0, 1, 0);
            const Pixels withoutDdgi = frame();
            const auto sourceOnlyDelta = difference(beforeProbes, withoutDdgi);
            std::printf("DDGI_DISABLED_OFFSCREEN_DELTA=%llu\n",
                    static_cast<unsigned long long>(sourceOnlyDelta));
            require(sourceOnlyDelta < std::max<uint64_t>(150000, ordinaryNoise * 4),
                    "source must be off screen without the probe lighting pass");
            const int point = Kine_Filament_CreateLight(context,
                    0.0, 35.0, 80.0, 0.12f, 0.22f, 1.0f, 70000.0f, 130.0f);
            require(point >= 0, "create DDGI off-screen point-light source");
            const Pixels directOnly = frame();
            captureScreen("ddgi-point-direct", directOnly);
            Kine_Filament_SetAdvancedEffect(context, 19, true, options, 9);
            for (int i = 0; i < 9; ++i) frame();
            const Pixels withPointProbes = frame();
            captureScreen("ddgi-point", withPointProbes);
            const auto pointBounce = difference(directOnly, withPointProbes);
            std::printf("DDGI_POINT_BOUNCE_DELTA=%llu\n",
                    static_cast<unsigned long long>(pointBounce));
            require(pointBounce > std::max<uint64_t>(150000, ordinaryNoise * 4),
                    "DDGI must respond to world-space point-light bounce");
            Kine_Filament_SetAdvancedEffect(context, 19, false, options, 9);
            Kine_Filament_RemoveLight(context, point);
            std::puts("DDGI_NATIVE_GPU_PASSED");
        }
        drawScreenScene = false;
        Kine_Filament_DestroyMesh(context, mesh);
        std::puts("SCREEN_EFFECTS_GPU_PASSED");
    }
    Kine_Filament_Destroy(context);
    std::puts("NATIVE_WICKED_RENDERER_PASSED");
}
