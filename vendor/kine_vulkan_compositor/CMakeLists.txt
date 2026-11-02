cmake_minimum_required(VERSION 3.25)

project(kine_vulkan_compositor VERSION 0.1.0 LANGUAGES CXX)

find_package(Vulkan REQUIRED)

if(NOT Vulkan_GLSLC_EXECUTABLE)
    message(FATAL_ERROR "glslc (Vulkan_GLSLC_EXECUTABLE) not found; the terrain mesher shader cannot be built")
endif()

# Compile the GPU terrain mesher compute shader and embed the SPIR-V as a header.
set(KINE_TERRAIN_MC_COMP ${CMAKE_CURRENT_SOURCE_DIR}/src/kine_terrain_mc.comp)
set(KINE_TERRAIN_MC_SPV ${CMAKE_CURRENT_BINARY_DIR}/kine_terrain_mc.spv)
set(KINE_TERRAIN_MC_HEADER ${CMAKE_CURRENT_BINARY_DIR}/kine_terrain_mc_spv.h)

add_custom_command(
    OUTPUT ${KINE_TERRAIN_MC_SPV}
    COMMAND ${Vulkan_GLSLC_EXECUTABLE} -fshader-stage=compute -o ${KINE_TERRAIN_MC_SPV} ${KINE_TERRAIN_MC_COMP}
    DEPENDS ${KINE_TERRAIN_MC_COMP}
    COMMENT "Compiling kine_terrain_mc.comp"
    VERBATIM
)

add_custom_command(
    OUTPUT ${KINE_TERRAIN_MC_HEADER}
    COMMAND ${CMAKE_COMMAND}
        -DINPUT=${KINE_TERRAIN_MC_SPV}
        -DOUTPUT=${KINE_TERRAIN_MC_HEADER}
        -DSYMBOL=kine_terrain_mc_spv
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/embed_spv.cmake
    DEPENDS ${KINE_TERRAIN_MC_SPV} ${CMAKE_CURRENT_SOURCE_DIR}/cmake/embed_spv.cmake
    COMMENT "Embedding terrain mesher SPIR-V"
    VERBATIM
)

add_library(kine_vulkan_compositor STATIC
    src/kine_vulkan_compositor.cpp
    src/kine_terrain_mc.cpp
    ${KINE_TERRAIN_MC_HEADER}
)

target_compile_features(kine_vulkan_compositor PRIVATE cxx_std_20)

target_include_directories(kine_vulkan_compositor
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../kine_skia/include
        ${KINE_SKIA_INCLUDE_DIR}/third_party/externals/vulkan-headers/include
        ${Vulkan_INCLUDE_DIRS}
        ${CMAKE_CURRENT_BINARY_DIR}
)

target_compile_definitions(kine_vulkan_compositor
    PRIVATE
        KINE_VULKAN_COMPOSITOR_BUILD_EXPORTS
)

target_link_libraries(kine_vulkan_compositor
    PRIVATE
        kine_skia
        Vulkan::Vulkan
)

if(ANDROID AND TARGET SDL3::SDL3-shared)
    target_link_libraries(kine_vulkan_compositor PRIVATE SDL3::SDL3-shared)
elseif(TARGET SDL3::SDL3-static)
    target_link_libraries(kine_vulkan_compositor PRIVATE SDL3::SDL3-static)
elseif(TARGET SDL3-static)
    target_link_libraries(kine_vulkan_compositor PRIVATE SDL3-static)
endif()

if(WIN32)
    target_link_libraries(kine_vulkan_compositor PRIVATE user32 gdi32 shell32)
elseif(APPLE)
    target_link_libraries(kine_vulkan_compositor PRIVATE
        "-framework Cocoa"
        "-framework CoreVideo"
        "-framework QuartzCore"
    )
elseif(ANDROID)
    target_link_libraries(kine_vulkan_compositor PRIVATE dl)
else()
    target_link_libraries(kine_vulkan_compositor PRIVATE dl pthread)
endif()

# Headless correctness test for the terrain mesher. Compiled standalone (the
# mesher depends only on Vulkan) so it never drags in the windowing/Skia stack.
add_executable(kine_terrain_mc_test
    test/kine_terrain_mc_test.cpp
    src/kine_terrain_mc.cpp
    ${KINE_TERRAIN_MC_HEADER}
)
target_compile_features(kine_terrain_mc_test PRIVATE cxx_std_20)
target_include_directories(kine_terrain_mc_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_BINARY_DIR}
    ${Vulkan_INCLUDE_DIRS}
)
target_link_libraries(kine_terrain_mc_test PRIVATE Vulkan::Vulkan)
