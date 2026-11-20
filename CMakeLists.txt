cmake_minimum_required(VERSION 3.25)

# Dependencies may specify older minimum CMake versions. Keep the modern MSVC
# debug-information abstraction enabled unless they explicitly opt out.
set(CMAKE_POLICY_DEFAULT_CMP0141 NEW)

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
	# Prefer object-embedded debug info for native dependencies with symbols.
	set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT "$<$<CONFIG:Debug,RelWithDebInfo>:Embedded>")
	option(KINE_MSVC_DISABLE_COMPILER_CACHE "Compile native MSVC sources directly" OFF)
	if(KINE_MSVC_DISABLE_COMPILER_CACHE)
		# Some upstream libraries request both /Zi and /Z7. MSVC honors the
		# last option, but sccache still tries to archive the nonexistent PDB.
		set(CMAKE_C_COMPILER_LAUNCHER "")
		set(CMAKE_CXX_COMPILER_LAUNCHER "")
		set(CCACHE_FOUND FALSE) # RocksDB's automatic ccache discovery
	endif()
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

set(KINEMIUM_ODIN_LIBRARY_TARGETS
    KinemiumOdinAliases
    kine_luau
    kine_filament_shim
    kine_skia
    kine_vulkan_compositor
    JoltWrapper
    rocksdb
)
# Bindings for compression and YAML import the consolidated archive on every
# desktop platform, while renderer bindings may still use component aliases.
list(APPEND KINEMIUM_ODIN_LIBRARY_TARGETS KinemiumLibs)

add_custom_target(KinemiumOdinLibraries ALL
    DEPENDS ${KINEMIUM_ODIN_LIBRARY_TARGETS}
)
if(TARGET kine_openxr_probe)
    add_dependencies(KinemiumOdinLibraries kine_openxr_probe)
endif()

# Some upstream projects still hard-code /Zi rather than using CMP0141.
# Apply the final policy after all native and FetchContent targets exist.
if(MSVC)
    include(cmake/msvc_debug_information.cmake)
    kine_msvc_embedded_debug_information("${CMAKE_CURRENT_SOURCE_DIR}")
    if(KINE_MSVC_DISABLE_COMPILER_CACHE OR CMAKE_C_COMPILER_LAUNCHER OR CMAKE_CXX_COMPILER_LAUNCHER)
        set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE "")
        set_property(GLOBAL PROPERTY RULE_LAUNCH_LINK "")
    endif()
endif()
