cmake_minimum_required(VERSION 3.16)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
	project(KinemiumLuauBridge LANGUAGES CXX)
	set(CMAKE_CXX_STANDARD 20)
	set(CMAKE_CXX_STANDARD_REQUIRED ON)
	set(LUAU_BUILD_CLI OFF CACHE BOOL "" FORCE)
	set(LUAU_BUILD_TESTS OFF CACHE BOOL "" FORCE)
	set(LUAU_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
	set(LUAU_BUILD_WEB OFF CACHE BOOL "" FORCE)
	add_subdirectory(../luau luau)
endif()

# Native double vectors (including the VM's altered GC/type-tag layout).
target_compile_definitions(Luau.VM PUBLIC LUA_VECTOR_DOUBLE=1)
if(TARGET Luau.CodeGen)
    target_compile_definitions(Luau.CodeGen PUBLIC LUA_VECTOR_DOUBLE=1)
endif()

add_library(kine_luau STATIC src/kine_luau.cpp)
target_include_directories(kine_luau PRIVATE
	${CMAKE_CURRENT_SOURCE_DIR}/../luau/VM/include
	${CMAKE_CURRENT_SOURCE_DIR}/../luau/Compiler/include
	${CMAKE_CURRENT_SOURCE_DIR}/../luau/Ast/include
	${CMAKE_CURRENT_SOURCE_DIR}/../luau/Common/include
)
target_link_libraries(kine_luau PUBLIC Luau.Compiler Luau.VM Luau.Ast)

if(NOT ANDROID AND NOT EMSCRIPTEN)
    find_package(Python3 REQUIRED COMPONENTS Interpreter)
    get_filename_component(KINE_SOURCE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
    file(GLOB_RECURSE KINE_API_SOURCES CONFIGURE_DEPENDS "${KINE_SOURCE_ROOT}/src/engine/classes/*.odin" "${KINE_SOURCE_ROOT}/src/engine/services/*.odin" "${KINE_SOURCE_ROOT}/src/engine/datatypes/*.odin" "${KINE_SOURCE_ROOT}/src/engine/enum/*.odin")
    file(GLOB KINE_API_GENERATORS CONFIGURE_DEPENDS "${KINE_SOURCE_ROOT}/tools/vscode-kinemium/*.py")
    set(KINE_API_HEADER "${CMAKE_CURRENT_BINARY_DIR}/kinemium_api_generated.h")
    add_custom_command(
        OUTPUT "${KINE_API_HEADER}"
        COMMAND "${Python3_EXECUTABLE}" "${KINE_SOURCE_ROOT}/tools/vscode-kinemium/generate_definitions.py" --studio-header --output "${KINE_API_HEADER}"
        DEPENDS ${KINE_API_SOURCES} ${KINE_API_GENERATORS}
        VERBATIM
    )
    target_sources(kine_luau PRIVATE "${KINE_API_HEADER}")
    target_include_directories(kine_luau PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
	target_sources(kine_luau PRIVATE src/kine_luau_analysis.cpp)
	target_link_libraries(kine_luau PUBLIC Luau.Analysis)
endif()
