foreach(_required_variable IN ITEMS ARCHIVER RANLIB MRI_SCRIPT OUTPUT_ARCHIVE BUNDLE_ARCHIVE)
    if(NOT DEFINED ${_required_variable} OR "${${_required_variable}}" STREQUAL "")
        message(FATAL_ERROR "Missing required variable: ${_required_variable}")
    endif()
endforeach()

execute_process(
    COMMAND "${ARCHIVER}" -M
    INPUT_FILE "${MRI_SCRIPT}"
    RESULT_VARIABLE _archive_result
    ERROR_VARIABLE _archive_error
)

if(NOT _archive_result EQUAL 0)
    message(FATAL_ERROR "Static archive bundling failed: ${_archive_error}")
endif()

file(RENAME "${BUNDLE_ARCHIVE}" "${OUTPUT_ARCHIVE}")

# MRI SAVE does not consistently emit a linker symbol index across archiver
# implementations. Rebuild it explicitly after the merged archive replaces the
# anchor archive so GNU ld can resolve its members.
execute_process(
    COMMAND "${RANLIB}" "${OUTPUT_ARCHIVE}"
    RESULT_VARIABLE _ranlib_result
    ERROR_VARIABLE _ranlib_error
)

if(NOT _ranlib_result EQUAL 0)
    message(FATAL_ERROR "Static archive indexing failed: ${_ranlib_error}")
endif()
