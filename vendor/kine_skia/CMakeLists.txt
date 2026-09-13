cmake_minimum_required(VERSION 3.25)

project(kine_skia VERSION 0.1.0 LANGUAGES CXX)

include(ExternalProject)

# -----------------------------------------------------------------------------
# Options
# -----------------------------------------------------------------------------

option(
    KINE_BUILD_SHARED
    "Build Kinemium native wrappers as shared libraries"
    OFF
)

option(
    KINE_SKIA_BUILD_SHARED
    "Build the Skia wrapper as an isolated shared library"
    OFF
)

option(
    KINE_SKIA_AUTO_DOWNLOAD
    "Download and build Skia automatically when KINE_SKIA_DIR is not set"
    ON
)

option(
    KINE_SKIA_UPDATE_DISCONNECTED
    "Do not update the downloaded Skia checkout during normal builds"
    ON
)

set(
    KINE_SKIA_BACKEND
    "VULKAN"
    CACHE STRING
    "Skia build backend: VULKAN or RASTER"
)

set_property(
    CACHE KINE_SKIA_BACKEND
    PROPERTY STRINGS
        VULKAN
        RASTER
)

set(
    KINE_SKIA_GIT_TAG
    "main"
    CACHE STRING
    "Skia git tag, branch, or commit to download"
)

set(
    KINE_SKIA_BUILD_NAME
    "Kinemium"
    CACHE STRING
    "Skia GN output directory name under out/"
)

set(
    KINE_SKIA_LIBRARY
    ""
    CACHE FILEPATH
    "Path to an already built Skia core library"
)

set(
    KINE_SKIA_SVG_LIBRARY
    ""
    CACHE FILEPATH
    "Path to an already built Skia SVG library"
)

set(
    KINE_SKIA_SKSHAPER_LIBRARY
    ""
    CACHE FILEPATH
    "Path to an already built Skia SkShaper library"
)

set(
    KINE_SKIA_SKUNICODE_CORE_LIBRARY
    ""
    CACHE FILEPATH
    "Path to an already built Skia Unicode core library"
)

set(
    KINE_SKIA_SKUNICODE_ICU_LIBRARY
    ""
    CACHE FILEPATH
    "Path to an already built Skia Unicode ICU library"
)

set(
    KINE_SKIA_DIR
    ""
    CACHE PATH
    "Path to an existing Skia checkout"
)

set(
    KINE_SKIA_INCLUDE_DIR
    ""
    CACHE PATH
    "Path to Skia headers"
)

# -----------------------------------------------------------------------------
# Backend
# -----------------------------------------------------------------------------

string(
    TOUPPER
    "${KINE_SKIA_BACKEND}"
    KINE_SKIA_BACKEND_UPPER
)

if(
    NOT KINE_SKIA_BACKEND_UPPER STREQUAL "VULKAN"
    AND
    NOT KINE_SKIA_BACKEND_UPPER STREQUAL "RASTER"
)
    message(
        FATAL_ERROR
        "KINE_SKIA_BACKEND must be VULKAN or RASTER"
    )
endif()

# -----------------------------------------------------------------------------
# Determine whether we're using prebuilts
# -----------------------------------------------------------------------------

set(KINE_SKIA_PREBUILT_LIBRARY_PROVIDED OFF)

if(KINE_SKIA_LIBRARY)
    set(KINE_SKIA_PREBUILT_LIBRARY_PROVIDED ON)
endif()

# -----------------------------------------------------------------------------
# Wrapper
# -----------------------------------------------------------------------------

if(KINE_SKIA_BUILD_SHARED)
    set(KINE_SKIA_LIBRARY_TYPE SHARED)
else()
    set(KINE_SKIA_LIBRARY_TYPE STATIC)
endif()

add_library(
    kine_skia
    ${KINE_SKIA_LIBRARY_TYPE}

    src/kine_skia.cpp
)

# The public Odin archive is generated from the aggregate KinemiumLibs target.
# Keep the wrapper archive distinct so incremental aggregation never consumes
# its own previous output through the kine_skia compatibility hard link.
set_target_properties(kine_skia PROPERTIES OUTPUT_NAME "kine_skia_component")

target_compile_features(
    kine_skia
    PRIVATE
        cxx_std_20
)

target_compile_definitions(kine_skia
    PUBLIC
        $<$<NOT:$<BOOL:${KINE_SKIA_BUILD_SHARED}>>:KINE_SKIA_STATIC>
)

target_include_directories(
    kine_skia

    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_compile_definitions(
    kine_skia

    PRIVATE
        KINE_SKIA_BUILD_EXPORTS

    PUBLIC
        $<$<BOOL:${KINE_SKIA_BUILD_SHARED}>:KINE_BUILD_SHARED>
)

set_target_properties(
    kine_skia

    PROPERTIES
        PREFIX ""

        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN ON

        RUNTIME_OUTPUT_DIRECTORY
            "${CMAKE_BINARY_DIR}/bin"

        LIBRARY_OUTPUT_DIRECTORY
            "${CMAKE_BINARY_DIR}/bin"

        ARCHIVE_OUTPUT_DIRECTORY
            "${CMAKE_BINARY_DIR}/lib"
)

if(MSVC)
    set_property(
        TARGET kine_skia

        PROPERTY
            MSVC_RUNTIME_LIBRARY
            "MultiThreaded$<$<CONFIG:Debug>:Debug>"
    )
endif()

# -----------------------------------------------------------------------------
# Skia paths
# -----------------------------------------------------------------------------

if(KINE_SKIA_DIR)
    set(
        KINE_SKIA_SOURCE_DIR
        "${KINE_SKIA_DIR}"
    )
else()
    set(
        KINE_SKIA_SOURCE_DIR
        "${CMAKE_CURRENT_BINARY_DIR}/skia-src"
    )
endif()

file(
    MAKE_DIRECTORY
    "${KINE_SKIA_SOURCE_DIR}"
)

if(
    KINE_SKIA_PREBUILT_LIBRARY_PROVIDED
    AND
    NOT KINE_SKIA_DIR
    AND
    NOT KINE_SKIA_INCLUDE_DIR
)
    message(
        FATAL_ERROR
        "KINE_SKIA_INCLUDE_DIR must be set when using "
        "KINE_SKIA_LIBRARY without KINE_SKIA_DIR"
    )
endif()

if(NOT KINE_SKIA_INCLUDE_DIR)
    set(
        KINE_SKIA_INCLUDE_DIR
        "${KINE_SKIA_SOURCE_DIR}"
    )
endif()

# -----------------------------------------------------------------------------
# Resolve library locations
# -----------------------------------------------------------------------------

if(KINE_SKIA_PREBUILT_LIBRARY_PROVIDED)
    get_filename_component(
        KINE_SKIA_OUTPUT_DIR
        "${KINE_SKIA_LIBRARY}"
        DIRECTORY
    )
else()
    set(
        KINE_SKIA_OUTPUT_DIR
        "${KINE_SKIA_SOURCE_DIR}/out/${KINE_SKIA_BUILD_NAME}"
    )
endif()

if(NOT KINE_SKIA_LIBRARY)
    set(
        KINE_SKIA_LIBRARY
        "${KINE_SKIA_OUTPUT_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}skia${CMAKE_STATIC_LIBRARY_SUFFIX}"
    )
endif()

if(NOT KINE_SKIA_SVG_LIBRARY)
    set(
        KINE_SKIA_SVG_LIBRARY
        "${KINE_SKIA_OUTPUT_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}svg${CMAKE_STATIC_LIBRARY_SUFFIX}"
    )
endif()

if(NOT KINE_SKIA_SKSHAPER_LIBRARY)
    set(
        KINE_SKIA_SKSHAPER_LIBRARY
        "${KINE_SKIA_OUTPUT_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}skshaper${CMAKE_STATIC_LIBRARY_SUFFIX}"
    )
endif()

if(NOT KINE_SKIA_SKUNICODE_CORE_LIBRARY)
    set(
        KINE_SKIA_SKUNICODE_CORE_LIBRARY
        "${KINE_SKIA_OUTPUT_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}skunicode_core${CMAKE_STATIC_LIBRARY_SUFFIX}"
    )
endif()

if(NOT KINE_SKIA_SKUNICODE_ICU_LIBRARY)
    set(
        KINE_SKIA_SKUNICODE_ICU_LIBRARY
        "${KINE_SKIA_OUTPUT_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}skunicode_icu${CMAKE_STATIC_LIBRARY_SUFFIX}"
    )
endif()

# -----------------------------------------------------------------------------
# Imported Skia libraries
# -----------------------------------------------------------------------------

function(kine_skia_import_library target_name library_path)
    add_library(
        ${target_name}
        STATIC
        IMPORTED
        GLOBAL
    )

    set_target_properties(
        ${target_name}

        PROPERTIES
            IMPORTED_LOCATION
                "${library_path}"

            INTERFACE_INCLUDE_DIRECTORIES
                "${KINE_SKIA_INCLUDE_DIR}"
    )
endfunction()

kine_skia_import_library(
    kine_skia_skiacore
    "${KINE_SKIA_LIBRARY}"
)

kine_skia_import_library(
    kine_skia_svg
    "${KINE_SKIA_SVG_LIBRARY}"
)

kine_skia_import_library(
    kine_skia_skshaper
    "${KINE_SKIA_SKSHAPER_LIBRARY}"
)

kine_skia_import_library(
    kine_skia_skunicode_core
    "${KINE_SKIA_SKUNICODE_CORE_LIBRARY}"
)

kine_skia_import_library(
    kine_skia_skunicode_icu
    "${KINE_SKIA_SKUNICODE_ICU_LIBRARY}"
)

# -----------------------------------------------------------------------------
# Vulkan
# -----------------------------------------------------------------------------

if(KINE_SKIA_BACKEND_UPPER STREQUAL "VULKAN")
    find_package(
        Vulkan
        QUIET
    )

    if(NOT Vulkan_FOUND)
        message(
            WARNING
            "Vulkan SDK was not found by CMake. "
            "Skia's vendored Vulkan headers will still be used when possible, "
            "but the final linker may require Vulkan_LIBRARY."
        )
    endif()
endif()

# -----------------------------------------------------------------------------
# Download/build Skia
# -----------------------------------------------------------------------------

if(
    NOT KINE_SKIA_DIR
    AND
    NOT KINE_SKIA_PREBUILT_LIBRARY_PROVIDED
)
    if(NOT KINE_SKIA_AUTO_DOWNLOAD)
        message(
            FATAL_ERROR
            "KINE_SKIA_DIR or KINE_SKIA_LIBRARY must be set when "
            "KINE_SKIA_AUTO_DOWNLOAD is OFF"
        )
    endif()

    find_package(
        Python3
        REQUIRED
        COMPONENTS Interpreter
    )

    # -------------------------------------------------------------------------
    # GN configuration
    # -------------------------------------------------------------------------

    set(
        KINE_SKIA_GN_ARGS

        "is_debug=false"
        "is_official_build=false"
        "is_component_build=false"

        # Ganesh
        "skia_enable_ganesh=true"

        # SVG
        "skia_enable_svg=true"
        "skia_use_expat=true"
        "skia_use_system_expat=false"

        # SVG text shaping
        "skia_enable_skshaper=true"

        "skia_use_harfbuzz=true"
        "skia_use_system_harfbuzz=false"

        "skia_use_icu=true"
        "skia_use_system_icu=false"

        # Fonts
        "skia_use_freetype=true"
        "skia_use_system_freetype2=false"

        # Not needed
        "skia_use_dng_sdk=false"
    )

    # -------------------------------------------------------------------------
    # GPU backend
    # -------------------------------------------------------------------------

    if(KINE_SKIA_BACKEND_UPPER STREQUAL "VULKAN")
        list(
            APPEND
            KINE_SKIA_GN_ARGS

            "skia_use_vulkan=true"
            "skia_use_gl=false"
        )
    else()
        list(
            APPEND
            KINE_SKIA_GN_ARGS

            "skia_use_vulkan=false"
            "skia_use_gl=false"
        )
    endif()

    # -------------------------------------------------------------------------
    # CRT / PIC
    # -------------------------------------------------------------------------

    if(WIN32)
        list(
            APPEND
            KINE_SKIA_GN_ARGS

            "extra_cflags=[\"/MT\"]"
            "extra_cflags_cc=[\"/MT\"]"
        )
    else()
        list(
            APPEND
            KINE_SKIA_GN_ARGS

            "extra_cflags=[\"-fPIC\"]"
            "extra_cflags_cc=[\"-fPIC\"]"
        )
    endif()

    list(
        JOIN
        KINE_SKIA_GN_ARGS
        " "
        KINE_SKIA_GN_ARGS_STRING
    )

    # -------------------------------------------------------------------------
    # Ninja
    # -------------------------------------------------------------------------

    find_program(
        KINE_SKIA_NINJA
        NAMES
            ninja
            ninja-build
    )

    if(KINE_SKIA_NINJA)
        set(
            KINE_SKIA_NINJA_COMMAND
            "${KINE_SKIA_NINJA}"
        )

        set(
            KINE_SKIA_FETCH_NINJA_COMMAND
            ""
        )
    else()
        set(
            KINE_SKIA_NINJA_COMMAND
            "<SOURCE_DIR>/third_party/ninja/ninja${CMAKE_EXECUTABLE_SUFFIX}"
        )

        set(
            KINE_SKIA_FETCH_NINJA_COMMAND

            COMMAND
                "${Python3_EXECUTABLE}"
                "bin/fetch-ninja"
        )
    endif()

    # -------------------------------------------------------------------------
    # ExternalProject
    # -------------------------------------------------------------------------

    ExternalProject_Add(
        kine_skia_external

        GIT_REPOSITORY
            "https://skia.googlesource.com/skia.git"

        GIT_TAG
            "${KINE_SKIA_GIT_TAG}"

        GIT_SHALLOW
            FALSE

        UPDATE_DISCONNECTED
            "${KINE_SKIA_UPDATE_DISCONNECTED}"

        SOURCE_DIR
            "${KINE_SKIA_SOURCE_DIR}"

        BUILD_IN_SOURCE
            TRUE

        CONFIGURE_COMMAND
            git config core.longpaths true

            # Strip the 'dawn' external from DEPS before syncing.
            # We build with skia_use_dawn=false so dawn is never needed,
            # but its Tint test-suite has paths >260 chars that break Windows.
            COMMAND
                "${Python3_EXECUTABLE}"
                -c
                "import re,pathlib; p=pathlib.Path('DEPS'); t=p.read_text(encoding='utf-8'); t=re.sub(r\"[ \\t]*'third_party/externals/dawn'[^,\\n]*,?\\n\",\"\",t); p.write_text(t,encoding='utf-8'); print('Patched DEPS: dawn removed')"

            COMMAND
                "${CMAKE_COMMAND}"
                -E env

                "GIT_SYNC_DEPS_SKIP_EMSDK=1"
                "GIT_CONFIG_COUNT=1"
                "GIT_CONFIG_KEY_0=core.longpaths"
                "GIT_CONFIG_VALUE_0=true"

                "${Python3_EXECUTABLE}"
                "tools/git-sync-deps"

            ${KINE_SKIA_FETCH_NINJA_COMMAND}

            COMMAND
                "<SOURCE_DIR>/bin/gn${CMAKE_EXECUTABLE_SUFFIX}"
                "gen"
                "out/${KINE_SKIA_BUILD_NAME}"
                "--args=${KINE_SKIA_GN_ARGS_STRING}"

        # These are separate complete static libraries in Skia.
        #
        # Do not build/link only svg.lib.
        BUILD_COMMAND
            "${KINE_SKIA_NINJA_COMMAND}"
            "-C"
            "out/${KINE_SKIA_BUILD_NAME}"
            "skia"
            "svg"
            "skshaper"
            "skunicode_core"
            "skunicode_icu"

        INSTALL_COMMAND
            ""

        BUILD_BYPRODUCTS
            "${KINE_SKIA_LIBRARY}"
            "${KINE_SKIA_SVG_LIBRARY}"
            "${KINE_SKIA_SKSHAPER_LIBRARY}"
            "${KINE_SKIA_SKUNICODE_CORE_LIBRARY}"
            "${KINE_SKIA_SKUNICODE_ICU_LIBRARY}"
    )

    add_dependencies(
        kine_skia_skiacore
        kine_skia_external
    )

    add_dependencies(
        kine_skia_svg
        kine_skia_external
    )

    add_dependencies(
        kine_skia_skshaper
        kine_skia_external
    )

    add_dependencies(
        kine_skia_skunicode_core
        kine_skia_external
    )

    add_dependencies(
        kine_skia_skunicode_icu
        kine_skia_external
    )

    add_dependencies(
        kine_skia
        kine_skia_external
    )
endif()

# -----------------------------------------------------------------------------
# Headers
# -----------------------------------------------------------------------------

target_include_directories(
    kine_skia

    PRIVATE
        "${KINE_SKIA_INCLUDE_DIR}"
)

if(KINE_SKIA_BACKEND_UPPER STREQUAL "VULKAN")
    target_include_directories(
        kine_skia

        PRIVATE
            "${KINE_SKIA_SOURCE_DIR}/third_party/externals/vulkan-headers/include"
    )
endif()

# -----------------------------------------------------------------------------
# Skia linkage
#
# Skia's module targets are separate complete static libraries when
# is_component_build=false. They must therefore all be linked into the wrapper.
#
# Order matters especially on Unix:
#
#   SVG
#    -> SkShaper
#       -> SkUnicode ICU
#          -> SkUnicode Core
#             -> Skia
# -----------------------------------------------------------------------------

target_link_libraries(
    kine_skia

    PRIVATE
        kine_skia_svg
        kine_skia_skshaper
        kine_skia_skunicode_icu
        kine_skia_skunicode_core
        kine_skia_skiacore
)

# -----------------------------------------------------------------------------
# Vulkan
# -----------------------------------------------------------------------------

if(KINE_SKIA_BACKEND_UPPER STREQUAL "VULKAN")
    target_compile_definitions(
        kine_skia

        PRIVATE
            KINE_SKIA_BUILD_VULKAN=1
    )

    if(Vulkan_FOUND)
        target_link_libraries(
            kine_skia

            PRIVATE
                Vulkan::Vulkan
        )
    endif()
endif()

# -----------------------------------------------------------------------------
# Platform libraries
# -----------------------------------------------------------------------------

if(WIN32)
    target_link_libraries(
        kine_skia

        PRIVATE
            user32
            gdi32
            ole32
            shell32
            advapi32
    )

elseif(APPLE)
    target_link_libraries(
        kine_skia

        PRIVATE
            "-framework CoreFoundation"
            "-framework CoreGraphics"
            "-framework CoreText"
            "-framework CoreServices"
    )

elseif(ANDROID)
    target_link_libraries(
        kine_skia

        PRIVATE
            dl
            m
    )

else()
    target_link_libraries(
        kine_skia

        PRIVATE
            pthread
            dl
            m
    )
endif()
