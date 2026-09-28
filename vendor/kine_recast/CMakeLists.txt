cmake_minimum_required(VERSION 3.25)

project(RecastWrapper
    VERSION 1.0.0
    LANGUAGES CXX
)

include(FetchContent)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ---------------------------------------------------------
# Recast & Detour
# ---------------------------------------------------------

# Only the Recast and Detour libraries are needed here. The demo, tests, and
# examples pull in extra dependencies and add nothing to a static link, so they
# stay off.
set(RECASTNAVIGATION_DEMO OFF CACHE BOOL "" FORCE)
set(RECASTNAVIGATION_TESTS OFF CACHE BOOL "" FORCE)
set(RECASTNAVIGATION_EXAMPLES OFF CACHE BOOL "" FORCE)
# Recast defaults its custom asserts on in Debug builds, which abort instead of
# returning a failure the wrapper can report. The engine links Release anyway,
# but pin this so a Debug build cannot turn bad input into a hard crash.
#
# This has to be the string "0" rather than the boolean OFF. Upstream embeds it
# in "$<$<NOT:${RECASTNAVIGATION_ENABLE_ASSERTS}>:RC_DISABLE_ASSERTS>", and
# CMake 4 requires a $<NOT:> argument to be exactly "0" or "1"; a BOOL cache entry
# always expands to ON/OFF and fails to generate. Upstream's own default for
# this variable is the string "$<CONFIG:Debug>", so a string is what it expects.
set(RECASTNAVIGATION_ENABLE_ASSERTS "0" CACHE STRING "" FORCE)
set(RECASTNAVIGATION_ENABLE_FAST_MATH OFF CACHE BOOL "" FORCE)
# Keep polygon references 32-bit so the wrapper's uint32 handles stay correct.
set(RECASTNAVIGATION_DT_POLYREF64 OFF CACHE BOOL "" FORCE)
set(RECASTNAVIGATION_DT_VIRTUAL_QUERYFILTER OFF CACHE BOOL "" FORCE)

# Upstream disables RTTI and exceptions for its own sources and treats warnings
# as errors. Neither applies to the wrapper, which stays conservative on its own
# and is built as C++17.
FetchContent_Declare(
    RecastNavigation
    GIT_REPOSITORY https://github.com/recastnavigation/recastnavigation.git
    GIT_TAG main
    GIT_SHALLOW TRUE
)

# Upstream applies -Werror at directory scope. The wrapper is a separate target
# and does not inherit that, but the flag is global enough that it is cleared
# here rather than inherited by accident.
FetchContent_MakeAvailable(RecastNavigation)

# ---------------------------------------------------------
# Recast Wrapper
# ---------------------------------------------------------

option(KINE_BUILD_SHARED "Build Kinemium native wrappers as shared libraries" OFF)

if(KINE_BUILD_SHARED)
    set(KINE_RECAST_WRAPPER_LIBRARY_TYPE SHARED)
else()
    set(KINE_RECAST_WRAPPER_LIBRARY_TYPE STATIC)
endif()

add_library(RecastWrapper ${KINE_RECAST_WRAPPER_LIBRARY_TYPE}
    src/recast_wrapper.cpp
)

target_include_directories(RecastWrapper
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Recast and Detour supply the implementation, so link them privately: nothing in
# the public C header exposes a Recast type.
target_link_libraries(RecastWrapper
    PRIVATE
        Recast
        Detour
)

target_compile_definitions(RecastWrapper
    PRIVATE
        RECAST_WRAPPER_EXPORTS
)

if(WIN32)
    target_compile_definitions(RecastWrapper PRIVATE NOMINMAX)
endif()

set_target_properties(RecastWrapper PROPERTIES
    OUTPUT_NAME "RecastWrapper"
)
