#include "kine_skia.h"
#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <vector>

static constexpr float fontSize = 36;
static constexpr int width = 520;
static constexpr int height = 100;

static std::vector<uint8_t> pixels(KineSkiaSurface *surface) {
    auto *data = static_cast<uint8_t *>(Kine_Skia_Surface_GetPixels(surface));
    assert(data);
    auto stride = Kine_Skia_Surface_GetRowBytes(surface);
    return {data, data + stride * height};
}

static std::vector<uint8_t> render(KineSkiaSurface *surface, KineSkiaTypeface *face,
                                   const char *text) {
    Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0);
    Kine_Skia_Surface_DrawTextTypeface(surface, text, 12, 65, fontSize, face,
                                      255, 255, 255, 255);
    return pixels(surface);
}

int main() {
    const char *primaryPath = "src/engine/assets/fonts/SourceSans3-Regular.ttf";
    const char *arabicPath = "src/engine/assets/fonts/NotoNaskhArabicUI-Regular.ttf";
    auto *primary = Kine_Skia_Typeface_LoadFromFile(primaryPath);
    std::ifstream arabicFile(arabicPath, std::ios::binary);
    std::vector<uint8_t> arabicBytes((std::istreambuf_iterator<char>(arabicFile)),
                                     std::istreambuf_iterator<char>());
    assert(!arabicBytes.empty());
    auto *arabic = Kine_Skia_Typeface_LoadFromMemory(arabicBytes.data(), arabicBytes.size());
    auto *surface = Kine_Skia_Surface_Create(width, height);
    assert(primary && arabic && surface);
    Kine_Skia_Typeface_SetFallback(arabic);

    const char *word = "سلام";
    auto fallbackPixels = render(surface, primary, word);
    auto arabicPixels = render(surface, arabic, word);
    assert(fallbackPixels == arabicPixels);
    assert(std::any_of(fallbackPixels.begin(), fallbackPixels.end(), [](auto v) { return v != 0; }));
    float joined = Kine_Skia_Typeface_MeasureText(primary, word, fontSize);
    float reference = Kine_Skia_Typeface_MeasureText(arabic, word, fontSize);
    float isolated = 0;
    for (const char *letter : {"س", "ل", "ا", "م"}) {
        isolated += Kine_Skia_Typeface_MeasureText(arabic, letter, fontSize);
    }
    assert(joined > 0 && std::abs(joined - reference) < 0.01f);
    assert(std::abs(joined - isolated) > 1);
    assert(std::abs(joined - Kine_Skia_Surface_MeasureText(word, fontSize, primaryPath)) < 0.01f);
    assert(render(surface, primary, "سلام Studio 123") == render(surface, primary, "Studio 123 سلام"));
    assert(Kine_Skia_Typeface_MeasureText(primary, "سلام Studio 123", fontSize) > joined);
    assert(render(surface, primary, "سلام Studio عالم") ==
           render(surface, primary, "\u200eعالم Studio سلام"));
    assert(render(surface, primary, "سلام Studio عالم") !=
           render(surface, primary, "\u200eسلام Studio عالم"));
    Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0);
    Kine_Skia_Surface_DrawText(surface, word, 12, 65, fontSize, primaryPath, 255, 255, 255, 255);
    assert(pixels(surface) == fallbackPixels);
    Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0);
    Kine_Skia_Surface_DrawTextShadowTypeface(surface, word, 12, 65, fontSize, primary,
                                            0, 0, 0, 0, 255, 255, 255, 255);
    assert(pixels(surface) == fallbackPixels);
    Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0);
    Kine_Skia_Surface_DrawTextBlurredTypeface(surface, word, 12, 65, fontSize, primary,
                                             0, 255, 255, 255, 255);
    assert(pixels(surface) == fallbackPixels);
    assert(render(surface, primary, "abc") != render(surface, primary, "cba"));
    Kine_Skia_Typeface_Destroy(arabic);
    assert(render(surface, primary, word) == fallbackPixels);
    Kine_Skia_Surface_Destroy(surface);
    Kine_Skia_Typeface_Destroy(primary);
    Kine_Skia_Typeface_SetFallback(nullptr);
    std::printf("RTL shaping, fallback, mixed text and measurement passed (%.2f vs %.2f isolated)\n",
                joined, isolated);
}
