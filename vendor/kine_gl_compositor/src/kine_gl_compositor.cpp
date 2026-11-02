// kine_gl_compositor.cpp
//
// A desktop OpenGL compositor that mirrors the API shape of
// kine_vulkan_compositor. It owns the SDL OpenGL context, a Skia Ganesh GL
// context that shares it, two offscreen 2D layers (base + overlay) and the
// final compositing pass that blends them with Filament's offscreen 3D texture
// onto the window's default framebuffer.
//
// All OpenGL work lives here so the Odin engine only talks to plain C
// functions. The compositor links SDL3 directly for context management and
// function loading.

#include "kine_gl_compositor.h"

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>

#include <SDL3/SDL.h>

#include "kine_skia.h"

#if defined(KINE_GL_COMPOSITOR_ENABLED)

// ---------------------------------------------------------------------------
// Minimal OpenGL function loader.
//
// We only need the subset used by the compositing pass. Everything is resolved
// at runtime through SDL_GL_GetProcAddress so the compositor does not depend on
// a linked GL loader or on a platform GL header.
// ---------------------------------------------------------------------------

typedef unsigned int  KGLenum;
typedef unsigned int  KGLuint;
typedef int           KGLint;
typedef int           KGLsizei;
typedef float         KGLfloat;
typedef unsigned int  KGLbitfield;
typedef char          KGLchar;
typedef ptrdiff_t     KGLsizeiptr;
typedef unsigned char KGLboolean;

// Enum values are part of the stable GL spec and safe to hardcode.
#define KGL_FALSE                0
#define KGL_TRUE                 1
#define KGL_TRIANGLES            0x0004
#define KGL_ONE                  1
#define KGL_BLEND                0x0BE2
#define KGL_SRC_ALPHA            0x0302
#define KGL_ONE_MINUS_SRC_ALPHA  0x0303
#define KGL_COLOR_BUFFER_BIT     0x4000
#define KGL_FLOAT                0x1406
#define KGL_UNSIGNED_BYTE        0x1401
#define KGL_RGBA                 0x1908
#define KGL_RGBA8                0x8058
#define KGL_TEXTURE_2D           0x0DE1
#define KGL_TEXTURE0             0x84C0
#define KGL_TEXTURE_MIN_FILTER   0x2801
#define KGL_TEXTURE_MAG_FILTER   0x2800
#define KGL_LINEAR               0x2601
#define KGL_TEXTURE_WRAP_S       0x2802
#define KGL_TEXTURE_WRAP_T       0x2803
#define KGL_CLAMP_TO_EDGE        0x812F
#define KGL_ARRAY_BUFFER         0x8892
#define KGL_STATIC_DRAW          0x88E4
#define KGL_VERTEX_SHADER        0x8B31
#define KGL_FRAGMENT_SHADER      0x8B30
#define KGL_COMPILE_STATUS       0x8B81
#define KGL_LINK_STATUS          0x8B82
#define KGL_INFO_LOG_LENGTH      0x8B84
#define KGL_FRAMEBUFFER          0x8D40
#define KGL_COLOR_ATTACHMENT0    0x8CE0
#define KGL_FRAMEBUFFER_COMPLETE 0x8CD5
#define KGL_RENDERER             0x1F01
#define KGL_VERSION              0x1F02

typedef KGLuint (SDLCALL *PFN_glCreateShader)(KGLenum);
typedef void (SDLCALL *PFN_glShaderSource)(KGLuint, KGLsizei, const KGLchar *const *, const KGLint *);
typedef void (SDLCALL *PFN_glCompileShader)(KGLuint);
typedef void (SDLCALL *PFN_glGetShaderiv)(KGLuint, KGLenum, KGLint *);
typedef void (SDLCALL *PFN_glGetShaderInfoLog)(KGLuint, KGLsizei, KGLsizei *, KGLchar *);
typedef void (SDLCALL *PFN_glDeleteShader)(KGLuint);
typedef KGLuint (SDLCALL *PFN_glCreateProgram)(void);
typedef void (SDLCALL *PFN_glAttachShader)(KGLuint, KGLuint);
typedef void (SDLCALL *PFN_glLinkProgram)(KGLuint);
typedef void (SDLCALL *PFN_glGetProgramiv)(KGLuint, KGLenum, KGLint *);
typedef void (SDLCALL *PFN_glGetProgramInfoLog)(KGLuint, KGLsizei, KGLsizei *, KGLchar *);
typedef void (SDLCALL *PFN_glDeleteProgram)(KGLuint);
typedef void (SDLCALL *PFN_glUseProgram)(KGLuint);
typedef KGLint (SDLCALL *PFN_glGetUniformLocation)(KGLuint, const KGLchar *);
typedef void (SDLCALL *PFN_glUniform1i)(KGLint, KGLint);
typedef void (SDLCALL *PFN_glUniform2f)(KGLint, KGLfloat, KGLfloat);
typedef void (SDLCALL *PFN_glUniform4f)(KGLint, KGLfloat, KGLfloat, KGLfloat, KGLfloat);
typedef void (SDLCALL *PFN_glGenVertexArrays)(KGLsizei, KGLuint *);
typedef void (SDLCALL *PFN_glBindVertexArray)(KGLuint);
typedef void (SDLCALL *PFN_glDeleteVertexArrays)(KGLsizei, const KGLuint *);
typedef void (SDLCALL *PFN_glGenBuffers)(KGLsizei, KGLuint *);
typedef void (SDLCALL *PFN_glBindBuffer)(KGLenum, KGLuint);
typedef void (SDLCALL *PFN_glBufferData)(KGLenum, KGLsizeiptr, const void *, KGLenum);
typedef void (SDLCALL *PFN_glDeleteBuffers)(KGLsizei, const KGLuint *);
typedef void (SDLCALL *PFN_glVertexAttribPointer)(KGLuint, KGLint, KGLenum, KGLboolean, KGLsizei, const void *);
typedef void (SDLCALL *PFN_glEnableVertexAttribArray)(KGLuint);
typedef void (SDLCALL *PFN_glDrawArrays)(KGLenum, KGLint, KGLsizei);
typedef void (SDLCALL *PFN_glGenFramebuffers)(KGLsizei, KGLuint *);
typedef void (SDLCALL *PFN_glBindFramebuffer)(KGLenum, KGLuint);
typedef void (SDLCALL *PFN_glDeleteFramebuffers)(KGLsizei, const KGLuint *);
typedef void (SDLCALL *PFN_glFramebufferTexture2D)(KGLenum, KGLenum, KGLenum, KGLuint, KGLint);
typedef KGLenum (SDLCALL *PFN_glCheckFramebufferStatus)(KGLenum);
typedef void (SDLCALL *PFN_glGenTextures)(KGLsizei, KGLuint *);
typedef void (SDLCALL *PFN_glBindTexture)(KGLenum, KGLuint);
typedef void (SDLCALL *PFN_glTexImage2D)(KGLenum, KGLint, KGLint, KGLsizei, KGLsizei, KGLint, KGLenum, KGLenum, const void *);
typedef void (SDLCALL *PFN_glTexParameteri)(KGLenum, KGLenum, KGLint);
typedef void (SDLCALL *PFN_glDeleteTextures)(KGLsizei, const KGLuint *);
typedef void (SDLCALL *PFN_glViewport)(KGLint, KGLint, KGLsizei, KGLsizei);
typedef void (SDLCALL *PFN_glEnable)(KGLenum);
typedef void (SDLCALL *PFN_glDisable)(KGLenum);
typedef void (SDLCALL *PFN_glBlendFunc)(KGLenum, KGLenum);
typedef void (SDLCALL *PFN_glActiveTexture)(KGLenum);
typedef void (SDLCALL *PFN_glUniform1i)(KGLint, KGLint);
typedef void (SDLCALL *PFN_glUniform2f)(KGLint, KGLfloat, KGLfloat);
typedef void (SDLCALL *PFN_glUniform4f)(KGLint, KGLfloat, KGLfloat, KGLfloat, KGLfloat);
typedef const unsigned char *(SDLCALL *PFN_glGetString)(KGLenum);

struct KineGLProcs {
	PFN_glCreateShader CreateShader;
	PFN_glShaderSource ShaderSource;
	PFN_glCompileShader CompileShader;
	PFN_glGetShaderiv GetShaderiv;
	PFN_glGetShaderInfoLog GetShaderInfoLog;
	PFN_glDeleteShader DeleteShader;
	PFN_glCreateProgram CreateProgram;
	PFN_glAttachShader AttachShader;
	PFN_glLinkProgram LinkProgram;
	PFN_glGetProgramiv GetProgramiv;
	PFN_glGetProgramInfoLog GetProgramInfoLog;
	PFN_glDeleteProgram DeleteProgram;
	PFN_glGetUniformLocation GetUniformLocation;
	PFN_glUniform1i Uniform1i;
	PFN_glUniform2f Uniform2f;
	PFN_glUniform4f Uniform4f;
	PFN_glUseProgram UseProgram;
	PFN_glGenVertexArrays GenVertexArrays;
	PFN_glBindVertexArray BindVertexArray;
	PFN_glDeleteVertexArrays DeleteVertexArrays;
	PFN_glGenBuffers GenBuffers;
	PFN_glBindBuffer BindBuffer;
	PFN_glBufferData BufferData;
	PFN_glDeleteBuffers DeleteBuffers;
	PFN_glVertexAttribPointer VertexAttribPointer;
	PFN_glEnableVertexAttribArray EnableVertexAttribArray;
	PFN_glDrawArrays DrawArrays;
	PFN_glGenFramebuffers GenFramebuffers;
	PFN_glBindFramebuffer BindFramebuffer;
	PFN_glDeleteFramebuffers DeleteFramebuffers;
	PFN_glFramebufferTexture2D FramebufferTexture2D;
	PFN_glCheckFramebufferStatus CheckFramebufferStatus;
	PFN_glGenTextures GenTextures;
	PFN_glBindTexture BindTexture;
	PFN_glTexImage2D TexImage2D;
	PFN_glTexParameteri TexParameteri;
	PFN_glDeleteTextures DeleteTextures;
	PFN_glViewport Viewport;
	PFN_glEnable Enable;
	PFN_glDisable Disable;
	PFN_glBlendFunc BlendFunc;
	PFN_glActiveTexture ActiveTexture;
	PFN_glGetString GetString;
	bool loaded;
};

static KineGLProcs g_procs;

static bool kine_gl_load_procs(char *error, size_t errorSize) {
	g_procs = KineGLProcs{};
#define KINE_GL_REQUIRE(member, name)                                            \
	do {                                                                         \
		g_procs.member = (decltype(g_procs.member))SDL_GL_GetProcAddress(name);   \
		if (g_procs.member == nullptr) {                                          \
			std::snprintf(error, errorSize, "missing OpenGL entry point: %s", name); \
			return false;                                                        \
		}                                                                        \
	} while (0)

	KINE_GL_REQUIRE(CreateShader, "glCreateShader");
	KINE_GL_REQUIRE(ShaderSource, "glShaderSource");
	KINE_GL_REQUIRE(CompileShader, "glCompileShader");
	KINE_GL_REQUIRE(GetShaderiv, "glGetShaderiv");
	KINE_GL_REQUIRE(GetShaderInfoLog, "glGetShaderInfoLog");
	KINE_GL_REQUIRE(DeleteShader, "glDeleteShader");
	KINE_GL_REQUIRE(CreateProgram, "glCreateProgram");
	KINE_GL_REQUIRE(AttachShader, "glAttachShader");
	KINE_GL_REQUIRE(LinkProgram, "glLinkProgram");
	KINE_GL_REQUIRE(GetProgramiv, "glGetProgramiv");
	KINE_GL_REQUIRE(GetProgramInfoLog, "glGetProgramInfoLog");
	KINE_GL_REQUIRE(DeleteProgram, "glDeleteProgram");
	KINE_GL_REQUIRE(GetUniformLocation, "glGetUniformLocation");
	KINE_GL_REQUIRE(Uniform1i, "glUniform1i");
	KINE_GL_REQUIRE(Uniform2f, "glUniform2f");
	KINE_GL_REQUIRE(Uniform4f, "glUniform4f");
	KINE_GL_REQUIRE(UseProgram, "glUseProgram");
	KINE_GL_REQUIRE(GenVertexArrays, "glGenVertexArrays");
	KINE_GL_REQUIRE(BindVertexArray, "glBindVertexArray");
	KINE_GL_REQUIRE(DeleteVertexArrays, "glDeleteVertexArrays");
	KINE_GL_REQUIRE(GenBuffers, "glGenBuffers");
	KINE_GL_REQUIRE(BindBuffer, "glBindBuffer");
	KINE_GL_REQUIRE(BufferData, "glBufferData");
	KINE_GL_REQUIRE(DeleteBuffers, "glDeleteBuffers");
	KINE_GL_REQUIRE(VertexAttribPointer, "glVertexAttribPointer");
	KINE_GL_REQUIRE(EnableVertexAttribArray, "glEnableVertexAttribArray");
	KINE_GL_REQUIRE(DrawArrays, "glDrawArrays");
	KINE_GL_REQUIRE(GenFramebuffers, "glGenFramebuffers");
	KINE_GL_REQUIRE(BindFramebuffer, "glBindFramebuffer");
	KINE_GL_REQUIRE(DeleteFramebuffers, "glDeleteFramebuffers");
	KINE_GL_REQUIRE(FramebufferTexture2D, "glFramebufferTexture2D");
	KINE_GL_REQUIRE(CheckFramebufferStatus, "glCheckFramebufferStatus");
	KINE_GL_REQUIRE(GenTextures, "glGenTextures");
	KINE_GL_REQUIRE(BindTexture, "glBindTexture");
	KINE_GL_REQUIRE(TexImage2D, "glTexImage2D");
	KINE_GL_REQUIRE(TexParameteri, "glTexParameteri");
	KINE_GL_REQUIRE(DeleteTextures, "glDeleteTextures");
	KINE_GL_REQUIRE(Viewport, "glViewport");
	KINE_GL_REQUIRE(Enable, "glEnable");
	KINE_GL_REQUIRE(Disable, "glDisable");
	KINE_GL_REQUIRE(BlendFunc, "glBlendFunc");
	KINE_GL_REQUIRE(ActiveTexture, "glActiveTexture");
	KINE_GL_REQUIRE(GetString, "glGetString");
#undef KINE_GL_REQUIRE

	g_procs.loaded = true;
	return true;
}

// ---------------------------------------------------------------------------
// Compositor
// ---------------------------------------------------------------------------

struct KineGLCompositor {
	SDL_Window *window = nullptr;
	SDL_GLContext glContext = nullptr;
	bool ownsContext = false;

	KineSkiaGLContext *skiaContext = nullptr;

	int width = 0;
	int height = 0;
	bool ready = false;

	char lastError[256] = {};

	// Base 2D layer.
	KGLuint baseFbo = 0;
	KGLuint baseTexture = 0;
	KineSkiaSurface *baseSurface = nullptr;

	// Overlay 2D layer.
	KGLuint overlayFbo = 0;
	KGLuint overlayTexture = 0;
	KineSkiaSurface *overlaySurface = nullptr;

	// Filament offscreen scene texture.
	KGLuint sceneTexture = 0;
	int sceneWidth = 0;
	int sceneHeight = 0;

	// Scene destination rectangle, top-left pixel coordinates.
	int viewportX = 0;
	int viewportY = 0;
	int viewportWidth = 0;
	int viewportHeight = 0;

	// Compositing program.
	KGLuint program = 0;
	KGLint uRect = -1;
	KGLint uSize = -1;
	KGLint uUV = -1;
	KGLint uTex = -1;
	KGLuint vao = 0;
	KGLuint vbo = 0;
};

static void kine_gl_set_error(KineGLCompositor *c, const char *message) {
	if (c == nullptr) {
		return;
	}
	std::snprintf(c->lastError, sizeof(c->lastError), "%s", message ? message : "");
}

static void kine_gl_destroy_layer(KGLuint &fbo, KGLuint &texture, KineSkiaSurface *&surface) {
	if (surface != nullptr) {
		Kine_Skia_Surface_Destroy(surface);
		surface = nullptr;
	}
	if (fbo != 0) {
		KGLuint f = fbo;
		g_procs.DeleteFramebuffers(1, &f);
		fbo = 0;
	}
	if (texture != 0) {
		KGLuint t = texture;
		g_procs.DeleteTextures(1, &t);
		texture = 0;
	}
}

static bool kine_gl_create_layer(
	KineGLCompositor *c,
	int width,
	int height,
	KGLuint &fboOut,
	KGLuint &textureOut,
	KineSkiaSurface *&surfaceOut) {
	g_procs.GenTextures(1, &textureOut);
	if (textureOut == 0) {
		kine_gl_set_error(c, "glGenTextures failed");
		return false;
	}
	g_procs.BindTexture(KGL_TEXTURE_2D, textureOut);
	g_procs.TexImage2D(
		KGL_TEXTURE_2D, 0, KGL_RGBA8, width, height, 0, KGL_RGBA, KGL_UNSIGNED_BYTE, nullptr);
	g_procs.TexParameteri(KGL_TEXTURE_2D, KGL_TEXTURE_MIN_FILTER, KGL_LINEAR);
	g_procs.TexParameteri(KGL_TEXTURE_2D, KGL_TEXTURE_MAG_FILTER, KGL_LINEAR);
	g_procs.TexParameteri(KGL_TEXTURE_2D, KGL_TEXTURE_WRAP_S, KGL_CLAMP_TO_EDGE);
	g_procs.TexParameteri(KGL_TEXTURE_2D, KGL_TEXTURE_WRAP_T, KGL_CLAMP_TO_EDGE);

	g_procs.GenFramebuffers(1, &fboOut);
	if (fboOut == 0) {
		kine_gl_set_error(c, "glGenFramebuffers failed");
		return false;
	}
	g_procs.BindFramebuffer(KGL_FRAMEBUFFER, fboOut);
	g_procs.FramebufferTexture2D(
		KGL_FRAMEBUFFER, KGL_COLOR_ATTACHMENT0, KGL_TEXTURE_2D, textureOut, 0);
	if (g_procs.CheckFramebufferStatus(KGL_FRAMEBUFFER) != KGL_FRAMEBUFFER_COMPLETE) {
		kine_gl_set_error(c, "framebuffer is not complete");
		return false;
	}
	g_procs.BindFramebuffer(KGL_FRAMEBUFFER, 0);

	KineSkiaGLImageInfo info{};
	info.framebufferId = fboOut;
	info.format = KGL_RGBA8;
	info.stencilBits = 0;
	info.sampleCount = 1;
	info.origin = 0; // bottom-left, matching GL texture orientation

	surfaceOut = Kine_Skia_Surface_CreateGLRenderTarget(c->skiaContext, width, height, &info);
	if (surfaceOut == nullptr) {
		kine_gl_set_error(c, "Kine_Skia_Surface_CreateGLRenderTarget failed");
		return false;
	}
	return true;
}

static bool kine_gl_build_pipeline(KineGLCompositor *c) {
	#if defined(KINE_GL_COMPOSITOR_GLES)
	static const char *kVertexSource =
		"#version 300 es\n"
		"layout(location = 0) in vec2 aPos;\n"
		"uniform vec4 uRect;\n"
		"uniform vec2 uSize;\n"
		"uniform vec4 uUV;\n"
		"out vec2 vUV;\n"
		"void main() {\n"
		"    vec2 p = uRect.xy + aPos * uRect.zw;\n"
		"    vec2 ndc = vec2(p.x / uSize.x, p.y / uSize.y) * 2.0 - 1.0;\n"
		"    gl_Position = vec4(ndc, 0.0, 1.0);\n"
		"    vUV = uUV.xy + aPos * uUV.zw;\n"
		"}\n";

	static const char *kFragmentSource =
		"#version 300 es\n"
		"precision mediump float;\n"
		"in vec2 vUV;\n"
		"uniform sampler2D uTex;\n"
		"out vec4 fragColor;\n"
		"void main() {\n"
		"    fragColor = texture(uTex, vUV);\n"
		"}\n";
#else
	static const char *kVertexSource =
		"#version 330 core\n"
		"layout(location = 0) in vec2 aPos;\n"
		"uniform vec4 uRect;\n"
		"uniform vec2 uSize;\n"
		"uniform vec4 uUV;\n"
		"out vec2 vUV;\n"
		"void main() {\n"
		"    vec2 p = uRect.xy + aPos * uRect.zw;\n"
		"    vec2 ndc = vec2(p.x / uSize.x, p.y / uSize.y) * 2.0 - 1.0;\n"
		"    gl_Position = vec4(ndc, 0.0, 1.0);\n"
		"    vUV = uUV.xy + aPos * uUV.zw;\n"
		"}\n";

	static const char *kFragmentSource =
		"#version 330 core\n"
		"in vec2 vUV;\n"
		"uniform sampler2D uTex;\n"
		"out vec4 fragColor;\n"
		"void main() {\n"
		"    fragColor = texture(uTex, vUV);\n"
		"}\n";
#endif

	auto compile = [c](KGLenum type, const char *source) -> KGLuint {
		KGLuint shader = g_procs.CreateShader(type);
		g_procs.ShaderSource(shader, 1, &source, nullptr);
		g_procs.CompileShader(shader);

		KGLint status = 0;
		g_procs.GetShaderiv(shader, KGL_COMPILE_STATUS, &status);
		if (status != KGL_TRUE) {
			char log[512] = {};
			g_procs.GetShaderInfoLog(shader, sizeof(log), nullptr, log);
			kine_gl_set_error(c, log);
			g_procs.DeleteShader(shader);
			return 0;
		}
		return shader;
	};

	KGLuint vertex = compile(KGL_VERTEX_SHADER, kVertexSource);
	if (vertex == 0) {
		return false;
	}
	KGLuint fragment = compile(KGL_FRAGMENT_SHADER, kFragmentSource);
	if (fragment == 0) {
		g_procs.DeleteShader(vertex);
		return false;
	}

	c->program = g_procs.CreateProgram();
	g_procs.AttachShader(c->program, vertex);
	g_procs.AttachShader(c->program, fragment);
	g_procs.LinkProgram(c->program);
	g_procs.DeleteShader(vertex);
	g_procs.DeleteShader(fragment);

	KGLint linked = 0;
	g_procs.GetProgramiv(c->program, KGL_LINK_STATUS, &linked);
	if (linked != KGL_TRUE) {
		char log[512] = {};
		g_procs.GetProgramInfoLog(c->program, sizeof(log), nullptr, log);
		kine_gl_set_error(c, log);
		g_procs.DeleteProgram(c->program);
		c->program = 0;
		return false;
	}

	c->uRect = g_procs.GetUniformLocation(c->program, "uRect");
	c->uSize = g_procs.GetUniformLocation(c->program, "uSize");
	c->uUV = g_procs.GetUniformLocation(c->program, "uUV");
	c->uTex = g_procs.GetUniformLocation(c->program, "uTex");

	static const KGLfloat kQuad[] = {
		0.0f, 0.0f,
		1.0f, 0.0f,
		1.0f, 1.0f,
		0.0f, 0.0f,
		1.0f, 1.0f,
		0.0f, 1.0f,
	};

	g_procs.GenVertexArrays(1, &c->vao);
	g_procs.BindVertexArray(c->vao);
	g_procs.GenBuffers(1, &c->vbo);
	g_procs.BindBuffer(KGL_ARRAY_BUFFER, c->vbo);
	g_procs.BufferData(KGL_ARRAY_BUFFER, sizeof(kQuad), kQuad, KGL_STATIC_DRAW);
	g_procs.EnableVertexAttribArray(0);
	g_procs.VertexAttribPointer(0, 2, KGL_FLOAT, KGL_FALSE, 2 * sizeof(KGLfloat), nullptr);
	g_procs.BindVertexArray(0);
	return true;
}

static void kine_gl_destroy_framebuffers(KineGLCompositor *c) {
	kine_gl_destroy_layer(c->baseFbo, c->baseTexture, c->baseSurface);
	kine_gl_destroy_layer(c->overlayFbo, c->overlayTexture, c->overlaySurface);
}

static bool kine_gl_create_framebuffers(KineGLCompositor *c, int width, int height) {
	kine_gl_destroy_framebuffers(c);

	if (!kine_gl_create_layer(
			c, width, height, c->baseFbo, c->baseTexture, c->baseSurface)) {
		return false;
	}
	if (!kine_gl_create_layer(
			c, width, height, c->overlayFbo, c->overlayTexture, c->overlaySurface)) {
		return false;
	}

	c->width = width;
	c->height = height;
	return true;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

extern "C" void Kine_GL_Compositor_SetDefaultAttributes(void) {
#if defined(KINE_GL_COMPOSITOR_GLES)
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
#else
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);
	SDL_GL_SetAttribute(
		SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
#endif
	SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
	SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
	SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);
	SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 0);
	SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 0);
}

static void *kine_gl_get_proc(void *context, const char *name) {
	(void)context;
	SDL_FunctionPointer fn = SDL_GL_GetProcAddress(name);
	return reinterpret_cast<void *>(reinterpret_cast<uintptr_t>(fn));
}

extern "C" KineGLCompositor *Kine_GL_Compositor_CreateForSDLWindow(
	void *sdlWindow, int width, int height) {
	auto *c = new KineGLCompositor();
	c->window = static_cast<SDL_Window *>(sdlWindow);

	if (c->window == nullptr) {
		kine_gl_set_error(c, "window is null");
		c->ready = false;
		return c;
	}

	c->glContext = SDL_GL_CreateContext(c->window);
	if (c->glContext == nullptr) {
		c->lastError[0] = '\0';
		std::snprintf(
			c->lastError, sizeof(c->lastError),
			"SDL_GL_CreateContext failed: %s", SDL_GetError());
		c->ready = false;
		return c;
	}
	c->ownsContext = true;

	if (!SDL_GL_MakeCurrent(c->window, c->glContext)) {
		std::snprintf(
			c->lastError, sizeof(c->lastError),
			"SDL_GL_MakeCurrent failed: %s", SDL_GetError());
		c->ready = false;
		return c;
	}
	SDL_GL_SetSwapInterval(1);

	if (!kine_gl_load_procs(c->lastError, sizeof(c->lastError))) {
		c->ready = false;
		return c;
	}

	const unsigned char *version = g_procs.GetString(KGL_VERSION);
	const unsigned char *renderer = g_procs.GetString(KGL_RENDERER);
	std::fprintf(
		stderr, "[Kine] GL compositor: version=%s renderer=%s\n",
		version ? reinterpret_cast<const char *>(version) : "?",
		renderer ? reinterpret_cast<const char *>(renderer) : "?");

	KineSkiaGLBackend backend{};
	backend.getProcAddr = reinterpret_cast<void *>(kine_gl_get_proc);
	backend.getProcContext = nullptr;

	c->skiaContext = Kine_Skia_GL_CreateContext(&backend);
	if (c->skiaContext == nullptr) {
		kine_gl_set_error(c, "Kine_Skia_GL_CreateContext failed");
		c->ready = false;
		return c;
	}

	if (!kine_gl_build_pipeline(c)) {
		c->ready = false;
		return c;
	}

	if (!kine_gl_create_framebuffers(c, width > 0 ? width : 1, height > 0 ? height : 1)) {
		c->ready = false;
		return c;
	}

	c->ready = true;
	return c;
}

extern "C" void Kine_GL_Compositor_Destroy(KineGLCompositor *c) {
	if (c == nullptr) {
		return;
	}

	if (c->glContext != nullptr) {
		SDL_GL_MakeCurrent(c->window, c->glContext);
	}

	kine_gl_destroy_framebuffers(c);

	if (c->vao != 0) {
		g_procs.DeleteVertexArrays(1, &c->vao);
		c->vao = 0;
	}
	if (c->vbo != 0) {
		g_procs.DeleteBuffers(1, &c->vbo);
		c->vbo = 0;
	}
	if (c->program != 0) {
		g_procs.DeleteProgram(c->program);
		c->program = 0;
	}
	if (c->skiaContext != nullptr) {
		Kine_Skia_GL_DestroyContext(c->skiaContext);
		c->skiaContext = nullptr;
	}
	if (c->ownsContext && c->glContext != nullptr) {
		SDL_GL_DestroyContext(c->glContext);
		c->glContext = nullptr;
	}
	delete c;
}

extern "C" int Kine_GL_Compositor_Resize(
	KineGLCompositor *c, int width, int height) {
	if (c == nullptr || !c->ready) {
		return 0;
	}
	if (width <= 0 || height <= 0) {
		return 0;
	}
	if (width == c->width && height == c->height) {
		return 1;
	}

	SDL_GL_MakeCurrent(c->window, c->glContext);
	if (!kine_gl_create_framebuffers(c, width, height)) {
		c->ready = false;
		return 0;
	}
	return 1;
}

extern "C" int Kine_GL_Compositor_IsReady(const KineGLCompositor *c) {
	return (c != nullptr && c->ready) ? 1 : 0;
}

extern "C" const char *Kine_GL_Compositor_GetLastError(const KineGLCompositor *c) {
	return c != nullptr ? c->lastError : "";
}

extern "C" void Kine_GL_Compositor_SetSceneTexture(
	KineGLCompositor *c, uint32_t textureId, int width, int height) {
	if (c == nullptr) {
		return;
	}
	c->sceneTexture = static_cast<KGLuint>(textureId);
	c->sceneWidth = width;
	c->sceneHeight = height;
}

extern "C" void Kine_GL_Compositor_SetViewportRect(
	KineGLCompositor *c, int x, int y, int width, int height) {
	if (c == nullptr) {
		return;
	}
	c->viewportX = x;
	c->viewportY = y;
	c->viewportWidth = width;
	c->viewportHeight = height;
}

extern "C" void *Kine_GL_Compositor_BeginFrame(KineGLCompositor *c) {
	if (c == nullptr || !c->ready) {
		return nullptr;
	}
	SDL_GL_MakeCurrent(c->window, c->glContext);
	// Filament and the final composite pass issue raw GL on this shared
	// context, so Skia's cached state is stale at the start of every frame.
	Kine_Skia_GL_ResetContext(c->skiaContext);
	g_procs.BindFramebuffer(KGL_FRAMEBUFFER, c->baseFbo);
	g_procs.Viewport(0, 0, c->width, c->height);
	return c->baseSurface;
}

extern "C" void *Kine_GL_Compositor_BeginOverlay(KineGLCompositor *c) {
	if (c == nullptr || !c->ready) {
		return nullptr;
	}
	SDL_GL_MakeCurrent(c->window, c->glContext);
	// Filament rendered since the base layer flush, so re-sync Skia's GL cache.
	Kine_Skia_GL_ResetContext(c->skiaContext);
	g_procs.BindFramebuffer(KGL_FRAMEBUFFER, c->overlayFbo);
	g_procs.Viewport(0, 0, c->width, c->height);

	// The renderer draws the overlay assuming a transparent starting canvas.
	Kine_Skia_Surface_Clear(c->overlaySurface, 0, 0, 0, 0);
	return c->overlaySurface;
}

extern "C" int Kine_GL_Compositor_EndFrame(KineGLCompositor *c) {
	if (c == nullptr || !c->ready) {
		return 0;
	}

	SDL_GL_MakeCurrent(c->window, c->glContext);

	g_procs.BindFramebuffer(KGL_FRAMEBUFFER, 0);
	g_procs.Viewport(0, 0, c->width, c->height);
	g_procs.UseProgram(c->program);
	g_procs.BindVertexArray(c->vao);
	g_procs.ActiveTexture(KGL_TEXTURE0);

	if (c->uTex >= 0) {
		g_procs.Uniform1i(c->uTex, 0);
	}
	g_procs.Uniform2f(c->uSize, static_cast<KGLfloat>(c->width),
					  static_cast<KGLfloat>(c->height));

	const float fullW = static_cast<float>(c->width);
	const float fullH = static_cast<float>(c->height);

	// Pass 1: base 2D layer, opaque, full screen.
	g_procs.Disable(KGL_BLEND);
	g_procs.BindTexture(KGL_TEXTURE_2D, c->baseTexture);
	g_procs.Uniform4f(c->uRect, 0.0f, 0.0f, fullW, fullH);
	g_procs.Uniform4f(c->uUV, 0.0f, 0.0f, 1.0f, 1.0f);
	g_procs.DrawArrays(KGL_TRIANGLES, 0, 6);

	// Pass 2: Filament scene texture. The scene is rendered by Filament into a
	// full-window texture with the 3D confined to the viewport rectangle, so
	// sample only that sub-rectangle and place it back at the same location.
	if (c->sceneTexture != 0 && c->viewportWidth > 0 && c->viewportHeight > 0) {
		const float gx = static_cast<float>(c->viewportX);
		const float gy =
			static_cast<float>(c->height - (c->viewportY + c->viewportHeight));
		const float vw = static_cast<float>(c->viewportWidth);
		const float vh = static_cast<float>(c->viewportHeight);
		g_procs.BindTexture(KGL_TEXTURE_2D, c->sceneTexture);
		g_procs.Uniform4f(c->uRect, gx, gy, vw, vh);
		g_procs.Uniform4f(c->uUV, gx / fullW, gy / fullH, vw / fullW, vh / fullH);
		g_procs.DrawArrays(KGL_TRIANGLES, 0, 6);
	}

	// Pass 3: overlay layer, premultiplied alpha, full screen.
	g_procs.Enable(KGL_BLEND);
	g_procs.BlendFunc(KGL_ONE, KGL_ONE_MINUS_SRC_ALPHA);
	g_procs.BindTexture(KGL_TEXTURE_2D, c->overlayTexture);
	g_procs.Uniform4f(c->uRect, 0.0f, 0.0f, fullW, fullH);
	g_procs.Uniform4f(c->uUV, 0.0f, 0.0f, 1.0f, 1.0f);
	g_procs.DrawArrays(KGL_TRIANGLES, 0, 6);

	g_procs.BindVertexArray(0);
	g_procs.BindTexture(KGL_TEXTURE_2D, 0);
	g_procs.Disable(KGL_BLEND);

	SDL_GL_SwapWindow(c->window);
	return 1;
}

extern "C" void *Kine_GL_Compositor_GetSkiaContext(KineGLCompositor *c) {
	return c != nullptr ? c->skiaContext : nullptr;
}

#else // !KINE_GL_COMPOSITOR_ENABLED

// ---------------------------------------------------------------------------
// Stub build: kine_skia was not compiled with the OpenGL backend. Every entry
// point still exists so the Odin library alias links, but creation always
// fails cleanly.
// ---------------------------------------------------------------------------

struct KineGLCompositor {
	char lastError[256] = "kine_gl_compositor built without the OpenGL backend";
};

extern "C" void Kine_GL_Compositor_SetDefaultAttributes(void) {}

extern "C" KineGLCompositor *Kine_GL_Compositor_CreateForSDLWindow(
	void *sdlWindow, int width, int height) {
	(void)sdlWindow;
	(void)width;
	(void)height;
	return new KineGLCompositor();
}

extern "C" void Kine_GL_Compositor_Destroy(KineGLCompositor *c) {
	delete c;
}

extern "C" int Kine_GL_Compositor_Resize(KineGLCompositor *c, int width, int height) {
	(void)c;
	(void)width;
	(void)height;
	return 0;
}

extern "C" int Kine_GL_Compositor_IsReady(const KineGLCompositor *c) {
	(void)c;
	return 0;
}

extern "C" const char *Kine_GL_Compositor_GetLastError(const KineGLCompositor *c) {
	return c != nullptr ? c->lastError : "";
}

extern "C" void Kine_GL_Compositor_SetSceneTexture(
	KineGLCompositor *c, uint32_t textureId, int width, int height) {
	(void)c;
	(void)textureId;
	(void)width;
	(void)height;
}

extern "C" void Kine_GL_Compositor_SetViewportRect(
	KineGLCompositor *c, int x, int y, int width, int height) {
	(void)c;
	(void)x;
	(void)y;
	(void)width;
	(void)height;
}

extern "C" void *Kine_GL_Compositor_BeginFrame(KineGLCompositor *c) {
	(void)c;
	return nullptr;
}

extern "C" void *Kine_GL_Compositor_BeginOverlay(KineGLCompositor *c) {
	(void)c;
	return nullptr;
}

extern "C" int Kine_GL_Compositor_EndFrame(KineGLCompositor *c) {
	(void)c;
	return 0;
}

extern "C" void *Kine_GL_Compositor_GetSkiaContext(KineGLCompositor *c) {
	(void)c;
	return nullptr;
}

#endif // KINE_GL_COMPOSITOR_ENABLED