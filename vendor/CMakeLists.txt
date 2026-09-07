cmake_minimum_required(VERSION 3.25)

project(Kinemium
    VERSION 0.1.0
    DESCRIPTION "KinemiumEngineLibs"
    LANGUAGES C CXX
)

if(APPLE)
    enable_language(OBJC)
    enable_language(OBJCXX)
endif()

include(FetchContent)

# Build external projects as static inputs, then bundle them into one
# static library (KinemiumLibs.lib / KinemiumLibs.a) at the end of this file.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "" FORCE)
if(WIN32)
    set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS OFF CACHE BOOL "" FORCE)
endif()
if(MSVC)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL" CACHE STRING "" FORCE)
endif()

set(KINE_WITH_FILAMENT ON CACHE BOOL "" FORCE)
set(KINE_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(KINE_SKIA_BUILD_SHARED OFF CACHE BOOL "Isolate Skia's VMA implementation from Filament" FORCE)
set(KINE_FILAMENT_BACKEND VULKAN CACHE STRING "Use the unified Vulkan compositor path for Filament and Skia" FORCE)
set(KINE_FILAMENT_VULKAN_READBACK ON CACHE BOOL "Enable offscreen Filament ViewportFrame readback" FORCE)
add_subdirectory(kine_render_shim)
add_subdirectory(kine_skia)
add_subdirectory(kine_vulkan_compositor)

# Luau
set(LUAU_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_WEB OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(LUAU_WERROR OFF CACHE BOOL "" FORCE)

# Important for calling Luau directly from Odin.
set(LUAU_EXTERN_C ON CACHE BOOL "" FORCE)

add_subdirectory(luau)

# Manifold
set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
set(MANIFOLD_DEBUG OFF CACHE BOOL "" FORCE)
set(MANIFOLD_ASSERT OFF CACHE BOOL "" FORCE)
set(MANIFOLD_TIMING OFF CACHE BOOL "" FORCE)
set(MANIFOLD_STRICT OFF CACHE BOOL "" FORCE)
set(MANIFOLD_NO_IOSTREAM OFF CACHE BOOL "" FORCE)
set(MANIFOLD_DOWNLOADS ON CACHE BOOL "" FORCE)
set(MANIFOLD_PAR ON CACHE BOOL "" FORCE)
set(MANIFOLD_OPTIMIZED ON CACHE BOOL "" FORCE)
set(MANIFOLD_TEST OFF CACHE BOOL "" FORCE)
set(MANIFOLD_PYBIND OFF CACHE BOOL "" FORCE)
set(MANIFOLD_CBIND ON CACHE BOOL "" FORCE)
set(MANIFOLD_USE_BUILTIN_TBB ON CACHE BOOL "" FORCE)
set(MANIFOLD_USE_BUILTIN_NANOBIND OFF CACHE BOOL "" FORCE)
set(TRACY_ENABLE OFF CACHE BOOL "" FORCE)
set(TRACY_MEMORY_USAGE OFF CACHE BOOL "" FORCE)
set(MANIFOLD_FUZZ OFF CACHE BOOL "" FORCE)
set(ASSIMP_ENABLE OFF CACHE BOOL "" FORCE)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/manifold")
    add_subdirectory(manifold)
endif()

# Jolt Wrapper
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/kine_jolt")
    add_subdirectory(kine_jolt)
endif()

# One static library target for the engine's native dependency surface.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/kinemium_libs.c" "void kinemium_libs_anchor(void) {}\n")

add_library(KinemiumLibs STATIC
    "${CMAKE_CURRENT_BINARY_DIR}/kinemium_libs.c"
)
target_compile_features(KinemiumLibs PRIVATE cxx_std_20)

if(MSVC)
    get_filename_component(KINE_MSVC_COMPILER_DIR "${CMAKE_CXX_COMPILER}" DIRECTORY)
    get_filename_component(KINE_MSVC_INCLUDE_DIR "${KINE_MSVC_COMPILER_DIR}/../../../include" ABSOLUTE)
    get_filename_component(KINE_MSVC_LIBRARY_DIR "${KINE_MSVC_COMPILER_DIR}/../../../lib/x64" ABSOLUTE)
    target_include_directories(KinemiumLibs PRIVATE "${KINE_MSVC_INCLUDE_DIR}")
    file(GLOB KINE_WINDOWS_UCRT_DIRS "C:/Program Files (x86)/Windows Kits/10/Include/*/ucrt")
    list(SORT KINE_WINDOWS_UCRT_DIRS ORDER DESCENDING)
    list(GET KINE_WINDOWS_UCRT_DIRS 0 KINE_WINDOWS_UCRT_DIR)
    target_include_directories(KinemiumLibs PRIVATE "${KINE_WINDOWS_UCRT_DIR}")
    file(GLOB KINE_WINDOWS_LIBRARY_ROOTS "C:/Program Files (x86)/Windows Kits/10/Lib/*")
    list(SORT KINE_WINDOWS_LIBRARY_ROOTS ORDER DESCENDING)
    list(GET KINE_WINDOWS_LIBRARY_ROOTS 0 KINE_WINDOWS_LIBRARY_ROOT)
    target_link_directories(KinemiumLibs PRIVATE
        "${KINE_MSVC_LIBRARY_DIR}"
        "${KINE_WINDOWS_LIBRARY_ROOT}/ucrt/x64"
        "${KINE_WINDOWS_LIBRARY_ROOT}/um/x64"
    )
endif()

set_target_properties(KinemiumLibs PROPERTIES
    OUTPUT_NAME "KinemiumLibs"
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
)

# List of component targets to link and merge into KinemiumLibs
set(KINE_COMPONENT_TARGETS
    # Renderer
    kine_render_shim
    kine_filament_shim
    matp
    filamat
    filament
    backend
    bluegl
    bluevk
    filabridge
    filaflat
    utils
    geometry
    smol-v
    zstd
    uberarchive
    shaders

    # Skia / Vulkan
    kine_skia
    kine_skia_skiacore
    kine_skia_svg
    kine_skia_skshaper
    kine_skia_skunicode_core
    kine_skia_skunicode_icu
    kine_vulkan_compositor

    # Physics / geometry
    JoltWrapper
    Jolt
    manifold
    manifoldc

    # SDL3 is created by kine_render_shim
    SDL3-static

    # Luau
    Luau.Common
    Luau.Ast
    Luau.Bytecode
    Luau.VM
    Luau.Compiler
    Luau.Config
    Luau.CodeGen
    Luau.Inliner
    Luau.Require
)

foreach(_dep IN LISTS KINE_COMPONENT_TARGETS)
    if(TARGET ${_dep})
        target_link_libraries(KinemiumLibs PUBLIC ${_dep})
    endif()
endforeach()

if(WIN32)
    target_link_libraries(KinemiumLibs PRIVATE
        user32 gdi32 ole32 shell32 opengl32 advapi32 imm32 setupapi version winmm delayimp
    )
elseif(APPLE)
    target_link_libraries(KinemiumLibs PRIVATE
        "-framework AppKit"
        "-framework Cocoa"
        "-framework CoreFoundation"
        "-framework CoreGraphics"
        "-framework CoreServices"
        "-framework CoreText"
        "-framework CoreVideo"
        "-framework IOKit"
        "-framework Metal"
        "-framework MetalKit"
        "-framework OpenGL"
        "-framework QuartzCore"
        "-framework UniformTypeIdentifiers"
    )
else()
    target_link_libraries(KinemiumLibs PRIVATE
        GL
        X11
        dl
        pthread
        m
    )
endif()

# Bundle component static libraries into one big KinemiumLibs archive file
if(MSVC)
    set(_kine_bundle_opts)
    foreach(_dep IN LISTS KINE_COMPONENT_TARGETS)
        list(APPEND _kine_bundle_opts "$<$<TARGET_EXISTS:${_dep}>:$<TARGET_FILE:${_dep}>>")
    endforeach()
    set_target_properties(KinemiumLibs PROPERTIES
        STATIC_LIBRARY_OPTIONS "${_kine_bundle_opts}"
    )
elseif(APPLE)
    set(_kine_libtool_cmd libtool -static -o "$<TARGET_FILE:KinemiumLibs>" "$<TARGET_FILE:KinemiumLibs>")
    foreach(_dep IN LISTS KINE_COMPONENT_TARGETS)
        list(APPEND _kine_libtool_cmd "$<$<TARGET_EXISTS:${_dep}>:$<TARGET_FILE:${_dep}>>")
    endforeach()
    add_custom_command(TARGET KinemiumLibs POST_BUILD
        COMMAND ${_kine_libtool_cmd}
        COMMENT "Bundling component static libraries into KinemiumLibs.a via libtool"
        COMMAND_EXPAND_LISTS
    )
else()
    set(_mri_script "${CMAKE_CURRENT_BINARY_DIR}/bundle_kinemium_libs.mri")
    set(_mri_content "CREATE $<TARGET_FILE:KinemiumLibs>\nADDLIB $<TARGET_FILE:KinemiumLibs>\n")
    foreach(_dep IN LISTS KINE_COMPONENT_TARGETS)
        string(APPEND _mri_content "$<$<TARGET_EXISTS:${_dep}>:ADDLIB $<TARGET_FILE:${_dep}>\n>")
    endforeach()
    string(APPEND _mri_content "SAVE\nEND\n")
    file(GENERATE OUTPUT "${_mri_script}" CONTENT "${_mri_content}")
    add_custom_command(TARGET KinemiumLibs POST_BUILD
        COMMAND ${CMAKE_AR} -M < "${_mri_script}"
        COMMENT "Bundling component static libraries into KinemiumLibs.a via ar MRI script"
    )
endif()
