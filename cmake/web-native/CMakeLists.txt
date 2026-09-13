cmake_minimum_required(VERSION 3.25)

project(KinemiumWebNative LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_EXTENSIONS OFF)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(LUAU_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_WEB OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(LUAU_EXTERN_C ON CACHE BOOL "" FORCE)

add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../vendor/luau" luau)
target_compile_definitions(Luau.VM PRIVATE clock=kine_luau_clock)
target_compile_definitions(Luau.Compiler PRIVATE clock=kine_luau_clock)
target_compile_definitions(Luau.Ast PRIVATE clock=kine_luau_clock)
target_compile_definitions(Luau.Bytecode PRIVATE clock=kine_luau_clock)
target_compile_definitions(Luau.Common PRIVATE clock=kine_luau_clock)
add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../vendor/kine_luau" kine_luau)
add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../vendor/kine_jolt" kine_jolt)

set_target_properties(kine_luau JoltWrapper Jolt PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)
