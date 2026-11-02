cmake_minimum_required(VERSION 3.16)
project(kne_sdk C)

option(KNE_BUILD_EXAMPLES "Build the bundled C example extensions" ON)

add_library(kne_sdk INTERFACE)
target_include_directories(kne_sdk INTERFACE ${CMAKE_CURRENT_SOURCE_DIR})

if(KNE_BUILD_EXAMPLES)
	add_library(hello_kne SHARED examples/c/hello_kne.c)
	target_link_libraries(hello_kne PRIVATE kne_sdk)
	set_target_properties(hello_kne PROPERTIES PREFIX "")
endif()
