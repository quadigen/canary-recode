#ifndef KINE_GL_COMPOSITOR_H
#define KINE_GL_COMPOSITOR_H

#include <stdint.h>

#if defined(_WIN32) && (defined(KINE_BUILD_SHARED) || defined(KINE_GL_COMPOSITOR_BUILD_SHARED))
  #if defined(KINE_GL_COMPOSITOR_BUILD_EXPORTS)
    #define KINE_GL_COMPOSITOR_API __declspec(dllexport)
  #else
    #define KINE_GL_COMPOSITOR_API __declspec(dllimport)
  #endif
#elif defined(__GNUC__) && (defined(KINE_BUILD_SHARED) || defined(KINE_GL_COMPOSITOR_BUILD_SHARED))
  #define KINE_GL_COMPOSITOR_API __attribute__((visibility("default")))
#else
  #define KINE_GL_COMPOSITOR_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KineGLCompositor KineGLCompositor;


KINE_GL_COMPOSITOR_API void
Kine_GL_Compositor_SetDefaultAttributes(void);


KINE_GL_COMPOSITOR_API KineGLCompositor*
Kine_GL_Compositor_CreateForSDLWindow(void* sdlWindow, int width, int height);

KINE_GL_COMPOSITOR_API void
Kine_GL_Compositor_Destroy(KineGLCompositor* compositor);

KINE_GL_COMPOSITOR_API int
Kine_GL_Compositor_Resize(KineGLCompositor* compositor, int width, int height);

KINE_GL_COMPOSITOR_API int
Kine_GL_Compositor_IsReady(const KineGLCompositor* compositor);

KINE_GL_COMPOSITOR_API const char*
Kine_GL_Compositor_GetLastError(const KineGLCompositor* compositor);


KINE_GL_COMPOSITOR_API void
Kine_GL_Compositor_SetSceneTexture(
    KineGLCompositor* compositor,
    uint32_t textureId,
    int width,
    int height);

KINE_GL_COMPOSITOR_API void
Kine_GL_Compositor_SetViewportRect(
    KineGLCompositor* compositor,
    int x,
    int y,
    int width,
    int height);


KINE_GL_COMPOSITOR_API void*
Kine_GL_Compositor_BeginFrame(KineGLCompositor* compositor);


KINE_GL_COMPOSITOR_API void*
Kine_GL_Compositor_BeginOverlay(KineGLCompositor* compositor);


KINE_GL_COMPOSITOR_API int
Kine_GL_Compositor_EndFrame(KineGLCompositor* compositor);


KINE_GL_COMPOSITOR_API void*
Kine_GL_Compositor_GetSkiaContext(KineGLCompositor* compositor);

#ifdef __cplusplus
}
#endif

#endif