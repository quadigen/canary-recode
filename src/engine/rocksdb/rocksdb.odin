#+build !js

package rocksdb

when ODIN_OS == .Windows {
	foreign import rocksdb_lib {"../../../vendor/build/lib/kine_rocksdb.lib", "system:shlwapi.lib", "system:rpcrt4.lib"}
} else when #config(KINE_ANDROID, false) {
	foreign import rocksdb_lib "../../../build/android-native/lib/librocksdb.a"
} else {
	foreign import rocksdb_lib "../../../vendor/build/lib/KinemiumLibs.a"
}

rocksdb_t :: struct {}
rocksdb_options_t :: struct {}
rocksdb_readoptions_t :: struct {}
rocksdb_writeoptions_t :: struct {}
rocksdb_writebatch_t :: struct {}
rocksdb_iterator_t :: struct {}

foreign rocksdb_lib {
	rocksdb_open :: proc(options: ^rocksdb_options_t, name: cstring, errptr: ^cstring) -> ^rocksdb_t ---
	rocksdb_close :: proc(db: ^rocksdb_t) ---

	rocksdb_options_create :: proc() -> ^rocksdb_options_t ---
	rocksdb_options_destroy :: proc(options: ^rocksdb_options_t) ---
	rocksdb_options_set_create_if_missing :: proc(options: ^rocksdb_options_t, value: u8) ---

	rocksdb_readoptions_create :: proc() -> ^rocksdb_readoptions_t ---
	rocksdb_readoptions_destroy :: proc(options: ^rocksdb_readoptions_t) ---

	rocksdb_writeoptions_create :: proc() -> ^rocksdb_writeoptions_t ---
	rocksdb_writeoptions_destroy :: proc(options: ^rocksdb_writeoptions_t) ---
	rocksdb_writeoptions_set_sync :: proc(options: ^rocksdb_writeoptions_t, value: u8) ---

	rocksdb_get :: proc(db: ^rocksdb_t, options: ^rocksdb_readoptions_t, key: [^]u8, keylen: uint, vallen: ^uint, errptr: ^cstring) -> [^]u8 ---
	rocksdb_put :: proc(db: ^rocksdb_t, options: ^rocksdb_writeoptions_t, key: [^]u8, keylen: uint, val: [^]u8, vallen: uint, errptr: ^cstring) ---
	rocksdb_delete :: proc(db: ^rocksdb_t, options: ^rocksdb_writeoptions_t, key: [^]u8, keylen: uint, errptr: ^cstring) ---
	rocksdb_write :: proc(db: ^rocksdb_t, options: ^rocksdb_writeoptions_t, batch: ^rocksdb_writebatch_t, errptr: ^cstring) ---

	rocksdb_writebatch_create :: proc() -> ^rocksdb_writebatch_t ---
	rocksdb_writebatch_destroy :: proc(batch: ^rocksdb_writebatch_t) ---
	rocksdb_writebatch_put :: proc(batch: ^rocksdb_writebatch_t, key: [^]u8, keylen: uint, val: [^]u8, vallen: uint) ---
	rocksdb_writebatch_delete :: proc(batch: ^rocksdb_writebatch_t, key: [^]u8, keylen: uint) ---
	rocksdb_writebatch_delete_range :: proc(batch: ^rocksdb_writebatch_t, start_key: [^]u8, start_key_len: uint, end_key: [^]u8, end_key_len: uint) ---

	rocksdb_create_iterator :: proc(db: ^rocksdb_t, options: ^rocksdb_readoptions_t) -> ^rocksdb_iterator_t ---
	rocksdb_iter_destroy :: proc(iter: ^rocksdb_iterator_t) ---
	rocksdb_iter_valid :: proc(iter: ^rocksdb_iterator_t) -> u8 ---
	rocksdb_iter_seek :: proc(iter: ^rocksdb_iterator_t, key: [^]u8, keylen: uint) ---
	rocksdb_iter_seek_to_first :: proc(iter: ^rocksdb_iterator_t) ---
	rocksdb_iter_seek_to_last :: proc(iter: ^rocksdb_iterator_t) ---
	rocksdb_iter_seek_for_prev :: proc(iter: ^rocksdb_iterator_t, key: [^]u8, keylen: uint) ---
	rocksdb_iter_next :: proc(iter: ^rocksdb_iterator_t) ---
	rocksdb_iter_prev :: proc(iter: ^rocksdb_iterator_t) ---
	rocksdb_iter_key :: proc(iter: ^rocksdb_iterator_t, klen: ^uint) -> [^]u8 ---
	rocksdb_iter_value :: proc(iter: ^rocksdb_iterator_t, vlen: ^uint) -> [^]u8 ---
	rocksdb_iter_get_error :: proc(iter: ^rocksdb_iterator_t, errptr: ^cstring) ---

	rocksdb_free :: proc(ptr: rawptr) ---
}
