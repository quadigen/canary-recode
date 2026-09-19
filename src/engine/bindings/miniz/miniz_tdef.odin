package zip

import "core:c"

TDEFL_LESS_MEMORY                   :: 0
TDEFL_HUFFMAN_ONLY                  :: 0
TDEFL_MAX_PROBES_MASK               :: 4095
TDEFL_DEFAULT_MAX_PROBES            :: 128
TDEFL_COMPUTE_ADLER32               :: 8192
TDEFL_GREEDY_PARSING_FLAG           :: 16384
TDEFL_NONDETERMINISTIC_PARSING_FLAG :: 32768
TDEFL_WRITE_ZLIB_HEADER             :: 4096
TDEFL_RLE_MATCHES                   :: 65536
TDEFL_FORCE_ALL_STATIC_BLOCKS       :: 262144
TDEFL_FILTER_MATCHES                :: 131072
TDEFL_FORCE_ALL_RAW_BLOCKS          :: 524288

foreign import lib "../../../vendor/build/vendor/miniz/miniz.lib"

@(default_calling_convention="c")
foreign lib {
	/* High level compression functions: */
	/* tdefl_compress_mem_to_heap() compresses a block in memory to a heap block allocated via malloc(). */
	/* On entry: */
	/*  pSrc_buf, src_buf_len: Pointer and size of source block to compress. */
	/*  flags: The max match finder probes (default is 128) logically OR'd against the above flags. Higher probes are slower but improve compression. */
	/* On return: */
	/*  Function returns a pointer to the compressed data, or NULL on failure. */
	/*  *pOut_len will be set to the compressed data's size, which could be larger than src_buf_len on uncompressible data. */
	/*  The caller must free() the returned block when it's no longer needed. */
	tdefl_compress_mem_to_heap :: proc(pSrc_buf: rawptr, src_buf_len: c.size_t, pOut_len: ^c.size_t, flags: i32) -> rawptr ---

	/* tdefl_compress_mem_to_mem() compresses a block in memory to another block in memory. */
	/* Returns 0 on failure. */
	tdefl_compress_mem_to_mem :: proc(pOut_buf: rawptr, out_buf_len: c.size_t, pSrc_buf: rawptr, src_buf_len: c.size_t, flags: i32) -> c.size_t ---

	/* Compresses an image to a compressed PNG file in memory. */
	/* On entry: */
	/*  pImage, w, h, and num_chans describe the image to compress. num_chans may be 1, 2, 3, or 4. */
	/*  The image pitch in bytes per scanline will be w*num_chans. The leftmost pixel on the top scanline is stored first in memory. */
	/*  level may range from [0,10], use MZ_NO_COMPRESSION, MZ_BEST_SPEED, MZ_BEST_COMPRESSION, etc. or a decent default is MZ_DEFAULT_LEVEL */
	/*  If flip is true, the image will be flipped on the Y axis (useful for OpenGL apps). */
	/* On return: */
	/*  Function returns a pointer to the compressed data, or NULL on failure. */
	/*  *pLen_out will be set to the size of the PNG image file. */
	/*  The caller must mz_free() the returned heap block (which will typically be larger than *pLen_out) when it's no longer needed. */
	tdefl_write_image_to_png_file_in_memory_ex :: proc(pImage: rawptr, w: i32, h: i32, num_chans: i32, pLen_out: ^c.size_t, level: mz_uint, flip: mz_bool) -> rawptr ---
	tdefl_write_image_to_png_file_in_memory    :: proc(pImage: rawptr, w: i32, h: i32, num_chans: i32, pLen_out: ^c.size_t) -> rawptr ---
}

/* Output stream interface. The compressor uses this interface to write compressed data. It'll typically be called TDEFL_OUT_BUF_SIZE at a time. */
tdefl_put_buf_func_ptr :: proc "c" (pBuf: rawptr, len: i32, pUser: rawptr) -> mz_bool

@(default_calling_convention="c")
foreign lib {
	/* tdefl_compress_mem_to_output() compresses a block to an output stream. The above helpers use this function internally. */
	tdefl_compress_mem_to_output :: proc(pBuf: rawptr, buf_len: c.size_t, pPut_buf_func: tdefl_put_buf_func_ptr, pPut_buf_user: rawptr, flags: i32) -> mz_bool ---
}

TDEFL_MAX_HUFF_TABLES       :: 3
TDEFL_MAX_HUFF_SYMBOLS_1    :: 32
TDEFL_MAX_HUFF_SYMBOLS_2    :: 19
TDEFL_LZ_DICT_SIZE          :: 32768
TDEFL_MAX_HUFF_SYMBOLS_0    :: 288
TDEFL_LZ_DICT_SIZE_MASK     :: 32767
TDEFL_MIN_MATCH_LEN         :: 3
TDEFL_MAX_MATCH_LEN         :: 258
TDEFL_LZ_CODE_BUF_SIZE      :: 65536
TDEFL_MAX_HUFF_SYMBOLS      :: 288
TDEFL_OUT_BUF_SIZE          :: 85196
TDEFL_LEVEL1_HASH_SIZE_MASK :: 4095
TDEFL_LZ_HASH_SHIFT         :: 5
TDEFL_LZ_HASH_SIZE          :: 32768
TDEFL_LZ_HASH_BITS          :: 15

/* The low-level tdefl functions below may be used directly if the above helper functions aren't flexible enough. The low-level functions don't make any heap allocations, unlike the above helper functions. */
tdefl_status :: enum i32 {
	BAD_PARAM      = -2,
	PUT_BUF_FAILED = -1,
	OKAY           = 0,
	DONE           = 1,
}

/* Must map to MZ_NO_FLUSH, MZ_SYNC_FLUSH, etc. enums */
tdefl_flush :: enum i32 {
	NO_FLUSH   = 0,
	SYNC_FLUSH = 2,
	FULL_FLUSH = 3,
	FINISH     = 4,
}

/* tdefl's compression state structure. */
tdefl_compressor :: struct {
	m_pPut_buf_func:                                                                                                                                tdefl_put_buf_func_ptr,
	m_pPut_buf_user:                                                                                                                                rawptr,
	m_flags:                                                                                                                                        mz_uint,
	m_max_probes:                                                                                                                                   [2]mz_uint,
	m_greedy_parsing:                                                                                                                               i32,
	m_adler32, m_lookahead_pos, m_lookahead_size, m_dict_size:                                                                                      mz_uint,
	m_pLZ_code_buf, m_pLZ_flags, m_pOutput_buf, m_pOutput_buf_end:                                                                                  ^mz_uint8,
	m_num_flags_left, m_total_lz_bytes, m_lz_code_buf_dict_pos, m_bits_in, m_bit_buffer:                                                            mz_uint,
	m_saved_match_dist, m_saved_match_len, m_saved_lit, m_output_flush_ofs, m_output_flush_remaining, m_finished, m_block_index, m_wants_to_finish: mz_uint,
	m_prev_return_status:                                                                                                                           tdefl_status,
	m_pIn_buf:                                                                                                                                      rawptr,
	m_pOut_buf:                                                                                                                                     rawptr,
	m_pIn_buf_size, m_pOut_buf_size:                                                                                                                ^c.size_t,
	m_flush:                                                                                                                                        tdefl_flush,
	m_pSrc:                                                                                                                                         ^mz_uint8,
	m_src_buf_left, m_out_buf_ofs:                                                                                                                  c.size_t,
	m_dict:                                                                                                                                         [33025]mz_uint8,
	m_huff_count:                                                                                                                                   [3][288]mz_uint16,
	m_huff_codes:                                                                                                                                   [3][288]mz_uint16,
	m_huff_code_sizes:                                                                                                                              [3][288]mz_uint8,
	m_lz_code_buf:                                                                                                                                  [65536]mz_uint8,
	m_next:                                                                                                                                         [32768]mz_uint16,
	m_hash:                                                                                                                                         [32768]mz_uint16,
	m_output_buf:                                                                                                                                   [85196]mz_uint8,
}

@(default_calling_convention="c")
foreign lib {
	/* Initializes the compressor. */
	/* There is no corresponding deinit() function because the tdefl API's do not dynamically allocate memory. */
	/* pBut_buf_func: If NULL, output data will be supplied to the specified callback. In this case, the user should call the tdefl_compress_buffer() API for compression. */
	/* If pBut_buf_func is NULL the user should always call the tdefl_compress() API. */
	/* flags: See the above enums (TDEFL_HUFFMAN_ONLY, TDEFL_WRITE_ZLIB_HEADER, etc.) */
	tdefl_init :: proc(d: ^tdefl_compressor, pPut_buf_func: tdefl_put_buf_func_ptr, pPut_buf_user: rawptr, flags: i32) -> tdefl_status ---

	/* Compresses a block of data, consuming as much of the specified input buffer as possible, and writing as much compressed data to the specified output buffer as possible. */
	tdefl_compress :: proc(d: ^tdefl_compressor, pIn_buf: rawptr, pIn_buf_size: ^c.size_t, pOut_buf: rawptr, pOut_buf_size: ^c.size_t, flush: tdefl_flush) -> tdefl_status ---

	/* tdefl_compress_buffer() is only usable when the tdefl_init() is called with a non-NULL tdefl_put_buf_func_ptr. */
	/* tdefl_compress_buffer() always consumes the entire input buffer. */
	tdefl_compress_buffer        :: proc(d: ^tdefl_compressor, pIn_buf: rawptr, in_buf_size: c.size_t, flush: tdefl_flush) -> tdefl_status ---
	tdefl_get_prev_return_status :: proc(d: ^tdefl_compressor) -> tdefl_status ---
	tdefl_get_adler32            :: proc(d: ^tdefl_compressor) -> mz_uint32 ---

	/* Create tdefl_compress() flags given zlib-style compression parameters. */
	/* level may range from [0,10] (where 10 is absolute max compression, but may be much slower on some files) */
	/* window_bits may be -15 (raw deflate) or 15 (zlib) */
	/* strategy may be either MZ_DEFAULT_STRATEGY, MZ_FILTERED, MZ_HUFFMAN_ONLY, MZ_RLE, or MZ_FIXED */
	tdefl_create_comp_flags_from_zip_params :: proc(level: i32, window_bits: i32, strategy: i32) -> mz_uint ---

	/* Allocate the tdefl_compressor structure in C so that */
	/* non-C language bindings to tdefl_ API don't need to worry about */
	/* structure size and allocation mechanism. */
	tdefl_compressor_alloc :: proc() -> ^tdefl_compressor ---
	tdefl_compressor_free  :: proc(pComp: ^tdefl_compressor) ---
}

