cmake_minimum_required(VERSION 3.18)
project(kinemium_sdk_example LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(KINEMIUM_SDK_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." CACHE PATH "Kinemium SDK root")
if(NOT EXISTS "${KINEMIUM_SDK_ROOT}/include/kinemium.h")
    set(KINEMIUM_SDK_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." CACHE PATH "Kinemium SDK root" FORCE)
endif()

find_path(KINEMIUM_INCLUDE_DIR
    NAMES kinemium.h
    HINTS "${KINEMIUM_SDK_ROOT}/include"
    REQUIRED
)

find_library(KINEMIUM_LIBRARY
    NAMES kinemium
    HINTS "${KINEMIUM_SDK_ROOT}/lib" "${KINEMIUM_SDK_ROOT}/build" "${KINEMIUM_SDK_ROOT}/dist/kinemium/lib"
)

find_package(SDL3 QUIET CONFIG)

if(KINEMIUM_LIBRARY AND SDL3_FOUND)
add_executable(kinemium_sdk_example main.c)
target_include_directories(kinemium_sdk_example PRIVATE "${KINEMIUM_INCLUDE_DIR}")
target_link_libraries(kinemium_sdk_example PRIVATE "${KINEMIUM_LIBRARY}" SDL3::SDL3)
endif()

if(KINEMIUM_LIBRARY)
add_executable(kinemium_sdk_headless headless.c)
target_include_directories(kinemium_sdk_headless PRIVATE "${KINEMIUM_INCLUDE_DIR}")
target_link_libraries(kinemium_sdk_headless PRIVATE "${KINEMIUM_LIBRARY}")

if(UNIX AND NOT APPLE)
    target_link_options(kinemium_sdk_headless PRIVATE "-Wl,-rpath,$ORIGIN/../lib")
endif()
endif()

if(TARGET kinemium_sdk_example AND UNIX AND NOT APPLE)
    target_link_options(kinemium_sdk_example PRIVATE "-Wl,-rpath,$ORIGIN/../lib")
endif()

option(KINEMIUM_BUILD_WINDOWED_EXAMPLE "Build the SDL3 windowed SDK example" ON)
if(KINEMIUM_BUILD_WINDOWED_EXAMPLE)
    if(KINEMIUM_LIBRARY AND SDL3_FOUND)
        add_executable(kinemium_sdk_windowed windowed.c)
        target_include_directories(kinemium_sdk_windowed PRIVATE "${KINEMIUM_INCLUDE_DIR}")
        target_link_libraries(kinemium_sdk_windowed PRIVATE "${KINEMIUM_LIBRARY}" SDL3::SDL3)
        if(UNIX AND NOT APPLE)
            target_link_options(kinemium_sdk_windowed PRIVATE "-Wl,-rpath,$ORIGIN/../lib")
        endif()
    else()
        message(STATUS "SDL3 not found; skipping the windowed SDK example")
    endif()
endif()

# Runtime loader builds have NO link-time dependency on libkinemium.
set(KINEMIUM_RUNTIME_LOADER_SRC "${CMAKE_CURRENT_LIST_DIR}/../../src/kinemium_runtime.c")
if(NOT EXISTS "${KINEMIUM_RUNTIME_LOADER_SRC}")
    set(KINEMIUM_RUNTIME_LOADER_SRC "${CMAKE_CURRENT_LIST_DIR}/kinemium_runtime.c")
endif()
add_library(kinemium_runtime_loader STATIC "${KINEMIUM_RUNTIME_LOADER_SRC}")
target_include_directories(kinemium_runtime_loader PUBLIC "${KINEMIUM_INCLUDE_DIR}")
target_link_libraries(kinemium_runtime_loader PUBLIC "${CMAKE_DL_LIBS}")

add_executable(kinemium_sdk_dynamic dynamic.c)
target_link_libraries(kinemium_sdk_dynamic PRIVATE kinemium_runtime_loader)

add_executable(kinemium_sdk_gpu_compute gpu_compute.c)
target_link_libraries(kinemium_sdk_gpu_compute PRIVATE kinemium_runtime_loader)

if(SDL3_FOUND)
    add_executable(kinemium_sdk_dynamic_windowed dynamic_windowed.c)
    target_link_libraries(kinemium_sdk_dynamic_windowed PRIVATE kinemium_runtime_loader SDL3::SDL3)
endif()

option(KINEMIUM_BUILD_PLUGIN_EXAMPLE "Build the unified SDK native plugin example" ON)
if(KINEMIUM_BUILD_PLUGIN_EXAMPLE AND (NOT WIN32 OR KINEMIUM_LIBRARY))
    add_library(kinemium_sdk_plugin SHARED plugin/main.c)
    target_include_directories(kinemium_sdk_plugin PRIVATE "${KINEMIUM_INCLUDE_DIR}")
    set_target_properties(kinemium_sdk_plugin PROPERTIES PREFIX "")
    add_library(kinemium_sdk_plugin_secondary SHARED plugin/secondary.c)
    target_include_directories(kinemium_sdk_plugin_secondary PRIVATE "${KINEMIUM_INCLUDE_DIR}")
    set_target_properties(kinemium_sdk_plugin_secondary PROPERTIES PREFIX "")
    if(APPLE)
        target_link_options(kinemium_sdk_plugin_secondary PRIVATE "-Wl,-undefined,dynamic_lookup")
        target_link_options(kinemium_sdk_plugin PRIVATE "-Wl,-undefined,dynamic_lookup")
    endif()
    if(WIN32)
        target_link_libraries(kinemium_sdk_plugin PRIVATE "${KINEMIUM_LIBRARY}")
        target_link_libraries(kinemium_sdk_plugin_secondary PRIVATE "${KINEMIUM_LIBRARY}")
    endif()
endif()
