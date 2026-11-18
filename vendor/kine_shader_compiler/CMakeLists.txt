# Build only the adapter. Do not add_subdirectory glslang or SPIRV-Tools!
set(KINE_FILAMENT_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../filament-compiler-source"
    CACHE PATH "Source tree matching the prebuilt Filament SDK")
set(_glslang "${KINE_FILAMENT_SOURCE_DIR}/third_party/glslang")
set(_filamat "${KINE_FILAMENT_SOURCE_DIR}/libs/filamat/src/sca")
if(NOT EXISTS "${_glslang}/glslang/Public/ShaderLang.h" OR
   NOT EXISTS "${_glslang}/SPIRV/GlslangToSpv.h" OR
   NOT EXISTS "${_filamat}/builtinResource.h")
    message(FATAL_ERROR "Matching Filament source missing: ${KINE_FILAMENT_SOURCE_DIR}!")
endif()
add_library(kine_shader_compiler STATIC shader_compiler.cpp)
target_compile_features(kine_shader_compiler PRIVATE cxx_std_20)
target_include_directories(kine_shader_compiler PRIVATE "${_glslang}" "${_filamat}")
# Match official release SDK: AMD/NV extensions, HLSL disabled. No optimizer
# source is compiled here. Release SDK uses the non-debug C++ ABI.
target_compile_definitions(kine_shader_compiler PRIVATE AMD_EXTENSIONS NV_EXTENSIONS NDEBUG)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        message(FATAL_ERROR "Official Linux Filament SDK requires Clang/libc++ for kine_shader_compiler")
    endif()
    target_compile_options(kine_shader_compiler PRIVATE -stdlib=libc++ -fexceptions -fno-rtti)
elseif(MSVC)
    target_compile_options(kine_shader_compiler PRIVATE /EHsc /GR-)
endif()
set_target_properties(kine_shader_compiler PROPERTIES POSITION_INDEPENDENT_CODE ON)
