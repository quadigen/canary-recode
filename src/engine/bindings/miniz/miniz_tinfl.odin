package zip

import "core:c"

TINFL_FLAG_PARSE_ZLIB_HEADER             :: 1
TINFL_FLAG_HAS_MORE_INPUT                :: 2
TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF :: 4
TINFL_FLAG_COMPUTE_ADLER32               :: 8

@(default_calling_convention="c")
foreign lib {
	/* High level decompression functions: */
	/* tinfl_decompress_mem_to_heap() decompresses a block in memory to a heap block allocated via malloc(). */
	/* On entry: */
	/*  pSrc_buf, src_buf_len: Pointer and size of the Deflate or zlib source data to decompress. */
	/* On return: */
	/*  Function returns a pointer to the decompressed data, or NULL on failure. */
	/*  *pOut_len will be set to the decompressed data's size, which could be larger than src_buf_len on uncompressible data. */
	/*  The caller must call mz_free() on the returned block when it's no longer needed. */
	tinfl_decompress_mem_to_heap :: proc(pSrc_buf: rawptr, src_buf_len: c.size_t, pOut_len: ^c.size_t, flags: i32) -> rawptr ---
}

/* tinfl_decompress_mem_to_mem() decompresses a block in memory to another block in memory. */
/* Returns TINFL_DECOMPRESS_MEM_TO_MEM_FAILED on failure, or the number of bytes written on success. */
TINFL_DECOMPRESS_MEM_TO_MEM_FAILED :: ((c.size_t)(0))

@(default_calling_convention="c")
foreign lib {
	tinfl_decompress_mem_to_mem :: proc(pOut_buf: rawptr, out_buf_len: c.size_t, pSrc_buf: rawptr, src_buf_len: c.size_t, flags: i32) -> c.size_t ---
}

/* tinfl_decompress_mem_to_callback() decompresses a block in memory to an internal 32KB buffer, and a user provided callback function will be called to flush the buffer. */
/* Returns 1 on success or 0 on failure. */
tinfl_put_buf_func_ptr :: proc "c" (pBuf: rawptr, len: i32, pUser: rawptr) -> i32

@(default_calling_convention="c")
foreign lib {
	tinfl_decompress_mem_to_callback :: proc(pIn_buf: rawptr, pIn_buf_size: ^c.size_t, pPut_buf_func: tinfl_put_buf_func_ptr, pPut_buf_user: rawptr, flags: i32) -> i32 ---
}

tinfl_decompressor :: tinfl_decompressor_tag

@(default_calling_convention="c")
foreign lib {
	/* Allocate the tinfl_decompressor structure in C so that */
	/* non-C language bindings to tinfl_ API don't need to worry about */
	/* structure size and allocation mechanism. */
	tinfl_decompressor_alloc :: proc() -> ^tinfl_decompressor ---
	tinfl_decompressor_free  :: proc(pDecomp: ^tinfl_decompressor) ---
}

/* Max size of LZ dictionary. */
TINFL_LZ_DICT_SIZE :: 32768

/* Return status. */
tinfl_status :: enum i32 {
	/* This flags indicates the inflator needs 1 or more input bytes to make forward progress, but the caller is indicating that no more are available. The compressed data */
	/* is probably corrupted. If you call the inflator again with more bytes it'll try to continue processing the input but this is a BAD sign (either the data is corrupted or you called it incorrectly). */
	/* If you call it again with no input you'll just get TINFL_STATUS_FAILED_CANNOT_MAKE_PROGRESS again. */
	FAILED_CANNOT_MAKE_PROGRESS = -4,

	/* This flag indicates that one or more of the input parameters was obviously bogus. (You can try calling it again, but if you get this error the calling code is wrong.) */
	BAD_PARAM                   = -3,

	/* This flags indicate the inflator is finished but the adler32 check of the uncompressed data didn't match. If you call it again it'll return TINFL_STATUS_DONE. */
	ADLER32_MISMATCH            = -2,

	/* This flags indicate the inflator has somehow failed (bad code, corrupted input, etc.). If you call it again without resetting via tinfl_init() it it'll just keep on returning the same status failure code. */
	FAILED                      = -1,

	/* Any status code less than TINFL_STATUS_DONE must indicate a failure. */
	
	/* This flag indicates the inflator has returned every byte of uncompressed data that it can, has consumed every byte that it needed, has successfully reached the end of the deflate stream, and */
	/* if zlib headers and adler32 checking enabled that it has successfully checked the uncompressed data's adler32. If you call it again you'll just get TINFL_STATUS_DONE over and over again. */
	DONE                        = 0,

	/* This flag indicates the inflator MUST have more input data (even 1 byte) before it can make any more forward progress, or you need to clear the TINFL_FLAG_HAS_MORE_INPUT */
	/* flag on the next call if you don't have any more source data. If the source data was somehow corrupted it's also possible (but unlikely) for the inflator to keep on demanding input to */
	/* proceed, so be sure to properly set the TINFL_FLAG_HAS_MORE_INPUT flag. */
	NEEDS_MORE_INPUT            = 1,

	/* This flag indicates the inflator definitely has 1 or more bytes of uncompressed data available, but it cannot write this data into the output buffer. */
	/* Note if the source compressed data was corrupted it's possible for the inflator to return a lot of uncompressed data to the caller. I've been assuming you know how much uncompressed data to expect */
	/* (either exact or worst case) and will stop calling the inflator and fail after receiving too much. In pure streaming scenarios where you have no idea how many bytes to expect this may not be possible */
	/* so I may need to add some code to address this. */
	HAS_MORE_OUTPUT             = 2,
}

foreign import lib "../../../vendor/build/vendor/miniz/miniz.lib"

@(default_calling_convention="c")
foreign lib {
	/* Main low-level decompressor coroutine function. This is the only function actually needed for decompression. All the other functions are just high-level helpers for improved usability. */
	/* This is a universal API, i.e. it can be used as a building block to build any desired higher level decompression API. In the limit case, it can be called once per every byte input or output. */
	tinfl_decompress :: proc(r: ^tinfl_decompressor, pIn_buf_next: ^mz_uint8, pIn_buf_size: ^c.size_t, pOut_buf_start: ^mz_uint8, pOut_buf_next: ^mz_uint8, pOut_buf_size: ^c.size_t, decomp_flags: mz_uint32) -> tinfl_status ---
}

TINFL_MAX_HUFF_SYMBOLS_1 :: 32
TINFL_MAX_HUFF_TABLES    :: 3
TINFL_MAX_HUFF_SYMBOLS_0 :: 288
TINFL_FAST_LOOKUP_SIZE   :: 1024
TINFL_FAST_LOOKUP_BITS   :: 10
TINFL_MAX_HUFF_SYMBOLS_2 :: 19
TINFL_USE_64BIT_BITBUF   :: 0

tinfl_bit_buf_t :: mz_uint32

TINFL_BITBUF_SIZE :: (32)

tinfl_decompressor_tag :: struct {
	m_state, m_num_bits, m_zhdr0, m_zhdr1, m_z_adler32, m_final, m_type, m_check_adler32, m_dist, m_counter, m_num_extra: mz_uint32,
	m_table_sizes:                                                                                                        [3]mz_uint32,
	m_bit_buf:                                                                                                            tinfl_bit_buf_t,
	m_dist_from_out_buf_start:                                                                                            c.size_t,
	m_look_up:                                                                                                            [3][1024]mz_int16,
	m_tree_0:                                                                                                             [576]mz_int16,
	m_tree_1:                                                                                                             [64]mz_int16,
	m_tree_2:                                                                                                             [38]mz_int16,
	m_code_size_0:                                                                                                        [288]mz_uint8,
	m_code_size_1:                                                                                                        [32]mz_uint8,
	m_code_size_2:                                                                                                        [19]mz_uint8,
	m_raw_header:                                                                                                         [4]mz_uint8,
	m_len_codes:                                                                                                          [457]mz_uint8,
}

