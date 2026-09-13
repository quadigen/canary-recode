foreach(_required_variable IN ITEMS ARCHIVER MRI_SCRIPT OUTPUT_ARCHIVE BUNDLE_ARCHIVE)
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
