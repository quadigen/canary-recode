#+build !js
package kineffi

when ODIN_OS == .Windows {
	foreign import kine_gl {"../../../vendor/build/lib/kine_gl.lib", "system:opengl32.lib", "system:user32.lib", "system:gdi32.lib", "system:shell32.lib"}
} else when #config(KINE_ANDROID, false) {
	foreign import kine_gl "../../../build/android-native/lib/libkine_gl_compositor.a"
} else when ODIN_OS == .Darwin {
	foreign import kine_gl {"../../../vendor/build/lib/KinemiumLibs.a", "system:c++", "system:OpenGL.framework", "system:Cocoa.framework", "system:CoreVideo.framework", "system:QuartzCore.framework"}
} else {
	foreign import kine_gl {"../../../vendor/build/lib/KinemiumLibs.a", "system:c++", "system:GL", "system:dl"}
}

KineGLCompositor :: struct {}

@(default_calling_convention = "c")
foreign kine_gl {
	Kine_GL_Compositor_SetDefaultAttributes :: proc() ---
	Kine_GL_Compositor_CreateForSDLWindow :: proc(sdlWindow: rawptr, width, height: i32) -> ^KineGLCompositor ---
	Kine_GL_Compositor_Destroy :: proc(compositor: ^KineGLCompositor) ---
	Kine_GL_Compositor_Resize :: proc(compositor: ^KineGLCompositor, width, height: i32) -> i32 ---
	Kine_GL_Compositor_IsReady :: proc(compositor: ^KineGLCompositor) -> i32 ---
	Kine_GL_Compositor_GetLastError :: proc(compositor: ^KineGLCompositor) -> cstring ---
	Kine_GL_Compositor_SetSceneTexture :: proc(compositor: ^KineGLCompositor, textureId: u32, width, height: i32) ---
	Kine_GL_Compositor_SetViewportRect :: proc(compositor: ^KineGLCompositor, x, y, width, height: i32) ---
	Kine_GL_Compositor_BeginFrame :: proc(compositor: ^KineGLCompositor) -> rawptr ---
	Kine_GL_Compositor_BeginOverlay :: proc(compositor: ^KineGLCompositor) -> rawptr ---
	Kine_GL_Compositor_EndFrame :: proc(compositor: ^KineGLCompositor) -> i32 ---
	Kine_GL_Compositor_GetSkiaContext :: proc(compositor: ^KineGLCompositor) -> rawptr ---
}