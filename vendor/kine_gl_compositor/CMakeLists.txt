cmake_minimum_required(VERSION 3.25)

project(kine_gl_compositor VERSION 0.1.0 LANGUAGES CXX)

add_library(kine_gl_compositor STATIC
    src/kine_gl_compositor.cpp
)

target_compile_features(kine_gl_compositor PRIVATE cxx_std_20)

target_include_directories(kine_gl_compositor
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../kine_skia/include
)

target_compile_definitions(kine_gl_compositor
    PRIVATE
        KINE_GL_COMPOSITOR_BUILD_EXPORTS
)

if(ANDROID)
    target_compile_definitions(kine_gl_compositor PRIVATE KINE_GL_COMPOSITOR_GLES=1)
endif()

# The compositor can only call into Skia's Ganesh GL entry points when kine_skia
# was itself configured for the OpenGL backend. Otherwise it compiles to a
# linkable stub so the Odin library alias always resolves.
string(TOUPPER "${KINE_SKIA_BACKEND}" KINE_GL_SKIA_BACKEND_UPPER)
if(KINE_GL_SKIA_BACKEND_UPPER STREQUAL "OPENGL")
    target_compile_definitions(kine_gl_compositor PRIVATE KINE_GL_COMPOSITOR_ENABLED=1)
endif()

target_link_libraries(kine_gl_compositor
    PRIVATE
        kine_skia
)

if(ANDROID AND TARGET SDL3::SDL3-shared)
    target_link_libraries(kine_gl_compositor PRIVATE SDL3::SDL3-shared)
elseif(TARGET SDL3::SDL3-static)
    target_link_libraries(kine_gl_compositor PRIVATE SDL3::SDL3-static)
elseif(TARGET SDL3-static)
    target_link_libraries(kine_gl_compositor PRIVATE SDL3-static)
endif()

if(WIN32)
    target_link_libraries(kine_gl_compositor PRIVATE user32 gdi32 shell32 opengl32)
elseif(APPLE)
    target_link_libraries(kine_gl_compositor PRIVATE
        "-framework Cocoa"
        "-framework CoreVideo"
        "-framework QuartzCore"
        "-framework OpenGL"
    )
elseif(ANDROID)
    target_link_libraries(kine_gl_compositor PRIVATE dl EGL GLESv3)
else()
    target_link_libraries(kine_gl_compositor PRIVATE dl GL)
endif()