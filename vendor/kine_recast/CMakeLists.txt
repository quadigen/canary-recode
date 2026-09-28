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

# Upstream treats warnings as errors, which the wrapper should not inherit by
# accident. Upstream also disables RTTI and exceptions for its own sources, which
# the wrapper does have to match; see the RecastWrapper target below for why that
# one is not independent.
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

# The wrapper subclasses rcContext, so its RTTI setting is not independent of
# the library it wraps. Upstream compiles Recast with -fno-rtti, and rcContext's
# key function (doResetLog, Recast.cpp) is what the Itanium ABI would use to emit
# the typeinfo for rcContext -- so with RTTI off in Recast, no typeinfo for
# rcContext exists in the library at all. The wrapper still needs a vtable for
# SilentContext, and with RTTI enabled its typeinfo would reference that missing
# symbol, leaving "typeinfo for rcContext" undefined at link time. MSVC hides
# this by emitting typeinfo as a COMDAT in every translation unit that needs it;
# the Itanium ABI targets (macOS, Linux) do not, so this links on Windows and
# fails everywhere else. Matching the library's setting removes the dangling
# reference, and the wrapper has no dynamic_cast, typeid, or exception handling
# of its own, so nothing is lost.
if(MSVC)
    target_compile_options(RecastWrapper PRIVATE /GR-)
else()
    target_compile_options(RecastWrapper PRIVATE -fno-rtti)
endif()

set_target_properties(RecastWrapper PROPERTIES
    OUTPUT_NAME "RecastWrapper"
)
