cmake_minimum_required(VERSION 3.25)

project(JoltWrapper
    VERSION 1.0.0
    LANGUAGES CXX
)

include(FetchContent)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ---------------------------------------------------------
# Jolt Physics
# ---------------------------------------------------------

set(USE_ASSERTS OFF CACHE BOOL "" FORCE)
set(DOUBLE_PRECISION ON CACHE BOOL "" FORCE)
set(GENERATE_DEBUG_SYMBOLS ON CACHE BOOL "" FORCE)
set(OVERRIDE_CXX_FLAGS OFF CACHE BOOL "" FORCE)
set(USE_STATIC_MSVC_RUNTIME_LIBRARY OFF CACHE BOOL "" FORCE)
set(CROSS_PLATFORM_DETERMINISTIC OFF CACHE BOOL "" FORCE)
set(FLOATING_POINT_EXCEPTIONS_ENABLED OFF CACHE BOOL "" FORCE)
set(CPP_EXCEPTIONS_ENABLED OFF CACHE BOOL "" FORCE)
set(CPP_RTTI_ENABLED OFF CACHE BOOL "" FORCE)

set(OBJECT_LAYER_BITS 32 CACHE STRING "" FORCE)

if(EMSCRIPTEN OR ANDROID OR CMAKE_SYSTEM_PROCESSOR MATCHES "arm|aarch64|ARM64")
    set(USE_SSE4_1 OFF CACHE BOOL "" FORCE)
    set(USE_SSE4_2 OFF CACHE BOOL "" FORCE)
    set(USE_AVX OFF CACHE BOOL "" FORCE)
    set(USE_AVX2 OFF CACHE BOOL "" FORCE)
    set(USE_LZCNT OFF CACHE BOOL "" FORCE)
    set(USE_TZCNT OFF CACHE BOOL "" FORCE)
    set(USE_F16C OFF CACHE BOOL "" FORCE)
    set(USE_FMADD OFF CACHE BOOL "" FORCE)
else()
    set(USE_SSE4_1 ON CACHE BOOL "" FORCE)
    set(USE_SSE4_2 ON CACHE BOOL "" FORCE)
    set(USE_AVX ON CACHE BOOL "" FORCE)
    set(USE_AVX2 ON CACHE BOOL "" FORCE)
    set(USE_LZCNT ON CACHE BOOL "" FORCE)
    set(USE_TZCNT ON CACHE BOOL "" FORCE)
    set(USE_F16C ON CACHE BOOL "" FORCE)
    set(USE_FMADD ON CACHE BOOL "" FORCE)
endif()
set(USE_AVX512 OFF CACHE BOOL "" FORCE)

set(TRACK_BROADPHASE_STATS OFF CACHE BOOL "" FORCE)
set(TRACK_NARROWPHASE_STATS OFF CACHE BOOL "" FORCE)

set(DEBUG_RENDERER_IN_DEBUG_AND_RELEASE OFF CACHE BOOL "" FORCE)
set(DEBUG_RENDERER_IN_DISTRIBUTION OFF CACHE BOOL "" FORCE)
set(PROFILER_IN_DEBUG_AND_RELEASE OFF CACHE BOOL "" FORCE)
set(PROFILER_IN_DISTRIBUTION OFF CACHE BOOL "" FORCE)

set(JPH_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(DISABLE_CUSTOM_ALLOCATOR OFF CACHE BOOL "" FORCE)
set(USE_STD_VECTOR OFF CACHE BOOL "" FORCE)
set(ENABLE_ALL_WARNINGS OFF CACHE BOOL "" FORCE)
set(ENABLE_OBJECT_STREAM OFF CACHE BOOL "" FORCE)

# ---------------------------------------------------------
# Download Jolt
# ---------------------------------------------------------

FetchContent_Declare(
    Jolt
    GIT_REPOSITORY https://github.com/jrouwe/JoltPhysics.git
    GIT_TAG master
    GIT_SHALLOW TRUE
    SOURCE_SUBDIR Build
)

FetchContent_MakeAvailable(Jolt)

# ---------------------------------------------------------
# Jolt Wrapper
# ---------------------------------------------------------

option(KINE_BUILD_SHARED "Build Kinemium native wrappers as shared libraries" OFF)

if(KINE_BUILD_SHARED)
    set(KINE_JOLT_WRAPPER_LIBRARY_TYPE SHARED)
else()
    set(KINE_JOLT_WRAPPER_LIBRARY_TYPE STATIC)
endif()

add_library(JoltWrapper ${KINE_JOLT_WRAPPER_LIBRARY_TYPE}
    src/jolt_wrapper.cpp
)

target_include_directories(JoltWrapper
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(JoltWrapper
    PRIVATE
        Jolt
)

target_compile_definitions(JoltWrapper
    PRIVATE
        JOLT_WRAPPER_EXPORTS
)

if(WIN32)
    target_compile_definitions(JoltWrapper PRIVATE NOMINMAX)
endif()

set_target_properties(JoltWrapper PROPERTIES
    OUTPUT_NAME "JoltWrapper"
)
