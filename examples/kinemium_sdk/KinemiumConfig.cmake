get_filename_component(_KinemiumSDKRoot "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(Kinemium_VERSION "2.0.0")

if(NOT TARGET Kinemium::Headers)
    add_library(Kinemium::Headers INTERFACE IMPORTED)
    set_target_properties(Kinemium::Headers PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${_KinemiumSDKRoot}/include"
    )
endif()

if(NOT TARGET Kinemium::SDK)
    add_library(Kinemium::SDK SHARED IMPORTED)
    if(WIN32)
        set_target_properties(Kinemium::SDK PROPERTIES
            IMPORTED_LOCATION "${_KinemiumSDKRoot}/bin/kinemium.dll"
            IMPORTED_IMPLIB "${_KinemiumSDKRoot}/lib/kinemium.lib"
            INTERFACE_LINK_LIBRARIES Kinemium::Headers
        )
    elseif(APPLE)
        set_target_properties(Kinemium::SDK PROPERTIES
            IMPORTED_LOCATION "${_KinemiumSDKRoot}/lib/libkinemium.dylib"
            INTERFACE_LINK_LIBRARIES Kinemium::Headers
        )
    else()
        set_target_properties(Kinemium::SDK PROPERTIES
            IMPORTED_LOCATION "${_KinemiumSDKRoot}/lib/libkinemium.so"
            INTERFACE_LINK_LIBRARIES Kinemium::Headers
        )
    endif()
endif()

set(Kinemium_FOUND TRUE)
