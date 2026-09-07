cmake_minimum_required(VERSION 3.16)
project(Kinemium LANGUAGES CXX C)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# MSVC defines _WIN32 but Filament's utility layer checks WIN32 directly.
# Visual Studio generators add it automatically; Ninja + MSVC does not.
if(WIN32)
	add_compile_definitions(WIN32)
endif()
if(MSVC)
	add_compile_options(/EHsc)
	# Filament deliberately uses the release-compatible MSVC STL ABI in all
	# configurations. Apply the same ABI to the application and dependencies so
	# their C++ types can safely cross static-library boundaries in Debug builds.
	add_compile_definitions(_ITERATOR_DEBUG_LEVEL=0)
endif()

set(LUAU_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_WEB OFF CACHE BOOL "" FORCE)

add_subdirectory(vendor/luau)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
add_subdirectory(vendor/SDL EXCLUDE_FROM_ALL)

# Jolt Physics. Keep its optional tools, installation rules, GPU compute
# backends, and expensive LTO pass out of the application build.
set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(ENABLE_ALL_WARNINGS OFF CACHE BOOL "" FORCE)
set(INTERPROCEDURAL_OPTIMIZATION OFF CACHE BOOL "" FORCE)
set(OVERRIDE_CXX_FLAGS OFF CACHE BOOL "" FORCE)
set(JPH_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(USE_STATIC_MSVC_RUNTIME_LIBRARY OFF CACHE BOOL "" FORCE)
set(JPH_USE_DX12 OFF CACHE BOOL "" FORCE)
set(JPH_USE_VK OFF CACHE BOOL "" FORCE)
set(JPH_USE_MTL OFF CACHE BOOL "" FORCE)
add_subdirectory(vendor/joltphysics/Build EXCLUDE_FROM_ALL)

include(FetchContent)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# ---------------------------------------------------------------------------
# Filament — Google publishes a real CMake build for this, so a plain
# FetchContent + add_subdirectory works.
# ---------------------------------------------------------------------------
FetchContent_Declare(
	filament
	GIT_REPOSITORY https://github.com/google/filament.git
	GIT_TAG        main        # pin to a real release tag, e.g. v1.55.1, for reproducible builds
)
set(FILAMENT_SKIP_SAMPLES ON CACHE BOOL "" FORCE)
set(FILAMENT_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(FILAMENT_SUPPORTS_VULKAN ON CACHE BOOL "" FORCE)
set(FILAMENT_ENABLE_EXCEPTIONS ON CACHE BOOL "" FORCE)
set(FILAMENT_ENABLE_RTTI ON CACHE BOOL "" FORCE)
set(USE_STATIC_CRT OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(filament)

# ---------------------------------------------------------------------------
# Skia — there is NO official CMake build; upstream builds it with their own
# gn + ninja toolchain (via depot_tools). FetchContent can still grab the
# source, but the actual compile step has to shell out to gn/ninja and the
# result gets wrapped as an IMPORTED target.
# ---------------------------------------------------------------------------
FetchContent_Declare(
	skia
	GIT_REPOSITORY https://skia.googlesource.com/skia.git
	GIT_TAG        main
)
FetchContent_GetProperties(skia)
if(NOT skia_POPULATED)
	FetchContent_Populate(skia)
endif()

set(SKIA_OUT_DIR "${skia_SOURCE_DIR}/out/Static")
set(SKIA_LIB "${SKIA_OUT_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}skia${CMAKE_STATIC_LIBRARY_SUFFIX}")

# Skia's Windows GN defaults to the static CRT, while this CMake project and
# Filament use the dynamic CRT. Match the active single-config CMake build.
set(SKIA_MSVC_GN_ARGS "")
if(MSVC)
	if(CMAKE_BUILD_TYPE STREQUAL "Debug")
		set(SKIA_MSVC_GN_ARGS "extra_cflags=[\"/MDd\",\"/D_ITERATOR_DEBUG_LEVEL=0\"]")
	else()
		set(SKIA_MSVC_GN_ARGS "extra_cflags=[\"/MD\",\"/D_ITERATOR_DEBUG_LEVEL=0\"]")
	endif()
endif()

add_custom_command(
	OUTPUT ${SKIA_LIB}
	COMMAND ${CMAKE_COMMAND} -E env GIT_SYNC_DEPS_SKIP_EMSDK=1 ${Python3_EXECUTABLE} tools/git-sync-deps
	COMMAND bin/gn gen ${SKIA_OUT_DIR} "--args=is_official_build=true is_debug=false is_component_build=false skia_enable_tools=false skia_enable_pdf=false skia_enable_ganesh=false skia_enable_graphite=false skia_use_dawn=false skia_use_gl=false skia_use_vulkan=false skia_use_icu=false skia_use_system_expat=false skia_use_system_libjpeg_turbo=false skia_use_system_libpng=false skia_use_system_libwebp=false skia_use_system_zlib=false ${SKIA_MSVC_GN_ARGS}"
	COMMAND ninja -C ${SKIA_OUT_DIR} skia
	WORKING_DIRECTORY ${skia_SOURCE_DIR}
	COMMENT "Building Skia via gn/ninja (first run will take a while)"
	VERBATIM
)
add_custom_target(skia_build DEPENDS ${SKIA_LIB})

add_library(skia STATIC IMPORTED GLOBAL)
set_target_properties(skia PROPERTIES IMPORTED_LOCATION ${SKIA_LIB})
target_include_directories(skia INTERFACE ${skia_SOURCE_DIR} ${skia_SOURCE_DIR}/include)
add_dependencies(skia skia_build)

file(GLOB_RECURSE PROJECT_SRC CONFIGURE_DEPENDS src/*.cpp)

add_executable(${PROJECT_NAME} ${PROJECT_SRC})

# Compile Filament materials once during the build. Compiling them with
# filamat on the application's UI thread makes the SDL window unresponsive and
# can produce a package for the wrong runtime backend.
set(KINEMIUM_MATERIAL_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated/materials")
set(KINEMIUM_PARTS_MATERIAL "${KINEMIUM_MATERIAL_DIR}/parts.inc")
set(KINEMIUM_UI_MATERIAL "${KINEMIUM_MATERIAL_DIR}/ui.inc")

add_custom_command(
	OUTPUT ${KINEMIUM_PARTS_MATERIAL} ${KINEMIUM_UI_MATERIAL}
	COMMAND ${CMAKE_COMMAND} -E make_directory ${KINEMIUM_MATERIAL_DIR}
	COMMAND $<TARGET_FILE:matc> --platform desktop --api opengl --api vulkan
		--output-format header --output ${KINEMIUM_PARTS_MATERIAL}
		${CMAKE_CURRENT_SOURCE_DIR}/assets/materials/parts.mat
	COMMAND $<TARGET_FILE:matc> --platform desktop --api opengl --api vulkan
		--output-format header --output ${KINEMIUM_UI_MATERIAL}
		${CMAKE_CURRENT_SOURCE_DIR}/assets/materials/ui.mat
	DEPENDS
		matc
		${CMAKE_CURRENT_SOURCE_DIR}/assets/materials/parts.mat
		${CMAKE_CURRENT_SOURCE_DIR}/assets/materials/ui.mat
	COMMENT "Compiling embedded Filament materials"
	VERBATIM
)
add_custom_target(kinemium_materials DEPENDS ${KINEMIUM_PARTS_MATERIAL} ${KINEMIUM_UI_MATERIAL})
add_dependencies(${PROJECT_NAME} kinemium_materials)

target_include_directories(${PROJECT_NAME} PRIVATE
	${CMAKE_CURRENT_SOURCE_DIR}/src
	${KINEMIUM_MATERIAL_DIR}
)

target_link_libraries(${PROJECT_NAME} PRIVATE
	SDL3::SDL3
	Luau.Compiler
	Luau.VM
	Jolt::Jolt
	filament
	backend
	filamat
	utils
	filament-iblprefilter
	skia
)

set_target_properties(${PROJECT_NAME} PROPERTIES OUTPUT_NAME "Kinemium")
