cmake_minimum_required(VERSION 3.25)

project(kine_vulkan_compositor VERSION 0.1.0 LANGUAGES CXX)

find_package(Vulkan REQUIRED)

add_library(kine_vulkan_compositor STATIC
    src/kine_vulkan_compositor.cpp
)

target_compile_features(kine_vulkan_compositor PRIVATE cxx_std_20)

target_include_directories(kine_vulkan_compositor
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../kine_skia/include
        ${KINE_SKIA_INCLUDE_DIR}/third_party/externals/vulkan-headers/include
        ${Vulkan_INCLUDE_DIRS}
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
