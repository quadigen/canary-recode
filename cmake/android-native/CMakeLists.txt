cmake_minimum_required(VERSION 3.25)
project(KinemiumAndroidNative LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "Do not build third-party test targets" FORCE)

if(NOT FILAMENT_DIR OR NOT KINE_SKIA_DIR OR NOT FILAMENT_HOST_TOOLS_DIR)
    message(FATAL_ERROR "FILAMENT_DIR, KINE_SKIA_DIR, and FILAMENT_HOST_TOOLS_DIR are required")
endif()

set(KINE_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(KINE_WITH_FILAMENT ON CACHE BOOL "" FORCE)
set(KINE_WITH_ASSIMP OFF CACHE BOOL "" FORCE)
set(KINE_FILAMENT_BACKEND VULKAN CACHE STRING "" FORCE)
set(KINE_FILAMENT_VULKAN_READBACK OFF CACHE BOOL "" FORCE)
set(FILAMENT_LIB_ARCH arm64-v8a CACHE STRING "" FORCE)

set(KINE_SKIA_AUTO_DOWNLOAD OFF CACHE BOOL "" FORCE)
set(KINE_SKIA_BACKEND VULKAN CACHE STRING "" FORCE)
set(KINE_SKIA_BUILD_NAME KinemiumAndroid CACHE STRING "" FORCE)
set(KINE_SKIA_LIBRARY "${KINE_SKIA_DIR}/out/KinemiumAndroid/libskia.a" CACHE FILEPATH "" FORCE)
set(KINE_SKIA_SVG_LIBRARY "${KINE_SKIA_DIR}/out/KinemiumAndroid/libsvg.a" CACHE FILEPATH "" FORCE)
set(KINE_SKIA_SKSHAPER_LIBRARY "${KINE_SKIA_DIR}/out/KinemiumAndroid/libskshaper.a" CACHE FILEPATH "" FORCE)
set(KINE_SKIA_SKUNICODE_CORE_LIBRARY "${KINE_SKIA_DIR}/out/KinemiumAndroid/libskunicode_core.a" CACHE FILEPATH "" FORCE)
set(KINE_SKIA_SKUNICODE_ICU_LIBRARY "${KINE_SKIA_DIR}/out/KinemiumAndroid/libskunicode_icu.a" CACHE FILEPATH "" FORCE)

set(SDL_SHARED ON CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)

add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../vendor/kine_render_shim" kine_render_shim)
add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../vendor/kine_skia" kine_skia)
add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../vendor/kine_vulkan_compositor" kine_vulkan_compositor)
target_link_libraries(kine_filament_shim PUBLIC kine_vulkan_compositor)

set(LUAU_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_WEB OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(LUAU_EXTERN_C ON CACHE BOOL "" FORCE)
add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../vendor/luau" luau)
add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../vendor/kine_luau" kine_luau)
add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../vendor/kine_jolt" kine_jolt)

set(ZSTD_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_STATIC ON CACHE BOOL "" FORCE)
add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../vendor/zstd" zstd)
add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../vendor/miniz" miniz)
add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../vendor/libyaml" libyaml)

file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/kinemium_libs.c" "void kinemium_libs_anchor(void) {}\n")
add_library(KinemiumLibs STATIC "${CMAKE_CURRENT_BINARY_DIR}/kinemium_libs.c")
target_link_libraries(KinemiumLibs PUBLIC libzstd_static miniz yaml)
set_target_properties(KinemiumLibs PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

set_target_properties(kine_render_shim kine_filament_shim kine_skia kine_vulkan_compositor
    kine_luau JoltWrapper Jolt PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)

# Odin emits one ELF object per package for Android.  Link those objects here
# through CMake so the complete static dependency graph is resolved as a group.
set(KINE_ODIN_OBJECT_DIR "${CMAKE_CURRENT_LIST_DIR}/../../build/android" CACHE PATH "Directory containing Odin Android objects")
set(KINE_ANDROID_JNI_DIR "${CMAKE_CURRENT_LIST_DIR}/../../build/android-jni/arm64-v8a" CACHE PATH "APK JNI output directory")
set(KINE_ANDROID_VENDOR_DIR "${CMAKE_CURRENT_LIST_DIR}/../../build/android-vendor" CACHE PATH "NDK-built Odin vendor archives")
set(KINE_ANDROID_BOX2D_LIBRARY "${CMAKE_CURRENT_LIST_DIR}/../../build/android-box2d/src/libbox2d.a" CACHE FILEPATH "Android Box2D archive")
set(KINE_ANDROID_VCPKG_DIR "${CMAKE_CURRENT_LIST_DIR}/../../build/vcpkg-installed/arm64-android" CACHE PATH "vcpkg Android dependency prefix")

file(GLOB KINE_ODIN_OBJECTS CONFIGURE_DEPENDS "${KINE_ODIN_OBJECT_DIR}/kinemium-*.o")
if(KINE_ODIN_OBJECTS)
    set_source_files_properties(${KINE_ODIN_OBJECTS} PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
    file(GLOB KINE_SKIA_ANDROID_ARCHIVES "${KINE_SKIA_DIR}/out/KinemiumAndroid/*.a")
    list(FILTER KINE_SKIA_ANDROID_ARCHIVES EXCLUDE REGEX "/liballocator_shim\\.a$")
    list(FILTER KINE_SKIA_ANDROID_ARCHIVES EXCLUDE REGEX "/libwebp_sse41\\.a$")

    set(KINE_ANDROID_LINK_LIBS
        kine_filament_shim
        kine_vulkan_compositor
        kine_skia
        JoltWrapper
        Jolt
        kine_luau
        Luau.CodeGen
        Luau.Compiler
        Luau.VM
        Luau.Ast
        Luau.Bytecode
        Luau.Common
        KinemiumLibs
        libzstd_static
        miniz
        yaml
        ${KINE_SKIA_ANDROID_ARCHIVES}
        SDL3::SDL3-shared
        "${KINE_ANDROID_VENDOR_DIR}/miniaudio.a"
        "${KINE_ANDROID_VENDOR_DIR}/stb_image.a"
        "${KINE_ANDROID_VENDOR_DIR}/stb_image_resize.a"
        "${KINE_ANDROID_VENDOR_DIR}/stb_image_write.a"
        "${KINE_ANDROID_BOX2D_LIBRARY}"
        "${KINE_ANDROID_VCPKG_DIR}/lib/libenet.a"
        "${KINE_ANDROID_VCPKG_DIR}/lib/libssl.a"
        "${KINE_ANDROID_VCPKG_DIR}/lib/libcrypto.a"
    )
    list(JOIN KINE_ANDROID_LINK_LIBS "," KINE_ANDROID_LINK_GROUP)

    add_library(kinemium_android SHARED
        ${KINE_ODIN_OBJECTS}
        "${CMAKE_CURRENT_LIST_DIR}/android_jni.cpp"
    )
    set_target_properties(kinemium_android PROPERTIES
        OUTPUT_NAME main
        LIBRARY_OUTPUT_DIRECTORY "${KINE_ANDROID_JNI_DIR}"
    )
    target_link_libraries(kinemium_android PRIVATE
        "$<LINK_GROUP:RESCAN,${KINE_ANDROID_LINK_GROUP}>"
        android log EGL GLESv3 vulkan dl aaudio OpenSLES m
    )
    target_link_options(kinemium_android PRIVATE "LINKER:--no-undefined")
    add_custom_command(TARGET kinemium_android POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "$<TARGET_FILE:SDL3-shared>"
            "${KINE_ANDROID_JNI_DIR}/libSDL3.so"
    )
endif()
