package zip

import "core:c"

/* ------------------- Types and macros */
when ODIN_OS == .Windows do foreign import lib "../../../../vendor/build/lib/KinemiumLibs.lib"
when #config(KINE_ANDROID, false) do foreign import lib "../../../../build/android-native/lib/libKinemiumLibs.a"
when ODIN_OS != .Windows && !#config(KINE_ANDROID, false) do foreign import lib "../../../../vendor/build/lib/KinemiumLibs.a"

mz_uint8  :: u8
mz_int16  :: i16
mz_uint16 :: u16
mz_uint32 :: u32
mz_uint   :: u32
mz_int64  :: i64
mz_uint64 :: u64
mz_bool   :: i32

MZ_FALSE  :: (0)
MZ_TRUE   :: (1)

@(default_calling_convention="c")
foreign lib {
	miniz_def_alloc_func   :: proc(opaque: rawptr, items: c.size_t, size: c.size_t) -> rawptr ---
	miniz_def_free_func    :: proc(opaque: rawptr, address: rawptr) ---
	miniz_def_realloc_func :: proc(opaque: rawptr, address: rawptr, items: c.size_t, size: c.size_t) -> rawptr ---
}

MZ_UINT16_MAX :: (0xFFFF)
MZ_UINT32_MAX :: (0xFFFFFFFF)

