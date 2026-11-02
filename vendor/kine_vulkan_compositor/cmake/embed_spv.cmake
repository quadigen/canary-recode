# Embed a SPIR-V binary as a C uint32_t array.
#
#   cmake -DINPUT=<file.spv> -DOUTPUT=<file.h> -DSYMBOL=<name> -P embed_spv.cmake
#
# The words are emitted in little-endian order so the array can be handed
# straight to vkCreateShaderModule.pCode. The element type is uint32_t, so the
# compiler aligns the array to four bytes as the API requires.
file(READ "${INPUT}" _hex HEX)
string(REGEX REPLACE "(..)(..)(..)(..)" "0x\\4\\3\\2\\1, " _words "${_hex}")
file(WRITE "${OUTPUT}"
    "// Generated from ${INPUT}. Do not edit.\n"
    "#pragma once\n"
    "#include <stdint.h>\n"
    "static const uint32_t ${SYMBOL}[] = {\n${_words}\n};\n"
)
