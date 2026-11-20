# Keep symbols in individual object files so parallel MSVC builds do not
# contend for a shared compiler PDB. Do not force symbols into targets which
# otherwise have none (notably Release libraries).
function(kine_msvc_embedded_debug_information directory)
    get_property(targets DIRECTORY "${directory}" PROPERTY BUILDSYSTEM_TARGETS)
    get_property(children DIRECTORY "${directory}" PROPERTY SUBDIRECTORIES)

    # Legacy projects can add /Zi through the directory's language flags
    # rather than through a target property (miniz and RocksDB do this).
    set(legacy_flags "")
    set(configs Debug Release RelWithDebInfo MinSizeRel
        ${CMAKE_CONFIGURATION_TYPES} ${CMAKE_BUILD_TYPE})
    list(REMOVE_DUPLICATES configs)
    foreach(lang IN ITEMS C CXX)
        get_directory_property(flags DIRECTORY "${directory}"
            DEFINITION CMAKE_${lang}_FLAGS)
        string(APPEND legacy_flags " ${flags}")
        foreach(config IN LISTS configs)
            string(TOUPPER "${config}" config_upper)
            get_directory_property(flags DIRECTORY "${directory}"
                DEFINITION CMAKE_${lang}_FLAGS_${config_upper})
            # For single-config generators only inspect the active config.
            if(CMAKE_CONFIGURATION_TYPES OR config STREQUAL CMAKE_BUILD_TYPE)
                string(APPEND legacy_flags " ${flags}")
            endif()
        endforeach()
    endforeach()

    foreach(target IN LISTS targets)
        get_property(type TARGET "${target}" PROPERTY TYPE)
        if(NOT type MATCHES "^(STATIC_LIBRARY|SHARED_LIBRARY|MODULE_LIBRARY|OBJECT_LIBRARY|EXECUTABLE)$")
            continue()
        endif()

        get_property(format TARGET "${target}" PROPERTY MSVC_DEBUG_INFORMATION_FORMAT)
        if(NOT format STREQUAL "")
            string(REPLACE "ProgramDatabase" "Embedded" format "${format}")
            string(REPLACE "EditAndContinue" "Embedded" format "${format}")
            set_property(TARGET "${target}" PROPERTY MSVC_DEBUG_INFORMATION_FORMAT "${format}")
        endif()

        get_property(options TARGET "${target}" PROPERTY COMPILE_OPTIONS)
        get_property(flags TARGET "${target}" PROPERTY COMPILE_FLAGS)
        # Target options come after raw language/target flags in Ninja. Keep
        # /Z7 last if a legacy flag can still select the shared PDB format.
        if(" ${legacy_flags} ${flags} ${options} " MATCHES "[ ;:][-/]Z[iI]([ ;>]|$)")
            list(REMOVE_ITEM options /Zi /ZI -Zi -ZI /Z7 -Z7)
            list(APPEND options /Z7)
            set_property(TARGET "${target}" PROPERTY COMPILE_OPTIONS "${options}")
        endif()

        # Respect the parent-selected compiler cache, not a dependency's
        # independent choice of ccache from PATH (e.g. RocksDB).
        foreach(lang IN ITEMS C CXX)
            if(CMAKE_${lang}_COMPILER_LAUNCHER)
                set_property(TARGET "${target}" PROPERTY
                    ${lang}_COMPILER_LAUNCHER "${CMAKE_${lang}_COMPILER_LAUNCHER}")
            endif()
        endforeach()
    endforeach()

    foreach(child IN LISTS children)
        kine_msvc_embedded_debug_information("${child}")
    endforeach()
endfunction()
