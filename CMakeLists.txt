cmake_minimum_required(VERSION 3.25)

project(KinemiumNative
	VERSION 0.1.0
	DESCRIPTION "Native libraries consumed by the Odin runtime"
	LANGUAGES C CXX
)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
if(MSVC)
	set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>" CACHE STRING "" FORCE)
endif()

# The application is written in Odin. CMake owns only the native wrappers and
# their third-party dependencies; there is no C++ executable target here.
add_subdirectory(vendor)
add_subdirectory(vendor/kine_luau)

set_target_properties(kine_luau PROPERTIES
	PREFIX ""
	ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
	LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
	RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# This is the single build target needed before linking the Odin executable.
# KinemiumOdinAliases emits the subsystem archives imported by the bindings
# package, including their transitive Filament, Skia, Vulkan, and Jolt inputs.
add_custom_target(KinemiumOdinLibraries ALL
	DEPENDS
		KinemiumLibs
		KinemiumOdinAliases
		kine_luau
		kine_filament_shim
		kine_skia
		kine_vulkan_compositor
		JoltWrapper
)
