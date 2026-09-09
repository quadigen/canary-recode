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

add_library(kine_luau STATIC src/kine_luau.cpp)
target_include_directories(kine_luau PRIVATE
	${CMAKE_CURRENT_SOURCE_DIR}/../luau/VM/include
	${CMAKE_CURRENT_SOURCE_DIR}/../luau/Compiler/include
)
target_link_libraries(kine_luau PUBLIC Luau.Compiler Luau.VM)
