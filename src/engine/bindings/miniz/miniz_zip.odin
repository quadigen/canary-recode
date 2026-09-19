package zip

import "core:c/libc"
import "core:c"

MZ_ZIP_MAX_IO_BUF_SIZE               :: 65536
MZ_ZIP_MAX_ARCHIVE_FILENAME_SIZE     :: 512
MZ_ZIP_MAX_ARCHIVE_FILE_COMMENT_SIZE :: 512

mz_zip_archive_file_stat :: struct {
	/* Central directory file index. */
	m_file_index: mz_uint32,

	/* Byte offset of this entry in the archive's central directory. Note we currently only support up to UINT_MAX or less bytes in the central dir. */
	m_central_dir_ofs: mz_uint64,

	/* These fields are copied directly from the zip's central dir. */
	m_version_made_by: mz_uint16,
	m_version_needed:  mz_uint16,
	m_bit_flag:        mz_uint16,
	m_method:          mz_uint16,

	/* CRC-32 of uncompressed data. */
	m_crc32: mz_uint32,

	/* File's compressed size. */
	m_comp_size: mz_uint64,

	/* File's uncompressed size. Note, I've seen some old archives where directory entries had 512 bytes for their uncompressed sizes, but when you try to unpack them you actually get 0 bytes. */
	m_uncomp_size: mz_uint64,

	/* Zip internal and external file attributes. */
	m_internal_attr: mz_uint16,
	m_external_attr: mz_uint32,

	/* Entry's local header file offset in bytes. */
	m_local_header_ofs: mz_uint64,

	/* Size of comment in bytes. */
	m_comment_size: mz_uint32,

	/* MZ_TRUE if the entry appears to be a directory. */
	m_is_directory: mz_bool,

	/* MZ_TRUE if the entry uses encryption/strong encryption (which miniz_zip doesn't support) */
	m_is_encrypted: mz_bool,

	/* MZ_TRUE if the file is not encrypted, a patch file, and if it uses a compression method we support. */
	m_is_supported: mz_bool,

	/* Filename. If string ends in '/' it's a subdirectory entry. */
	/* Guaranteed to be zero terminated, may be truncated to fit. */
	m_filename: [512]i8,

	/* Comment field. */
	/* Guaranteed to be zero terminated, may be truncated to fit. */
	m_comment: [512]i8,
	m_time:    libc.time_t,
}

mz_file_read_func         :: proc "c" (pOpaque: rawptr, file_ofs: mz_uint64, pBuf: rawptr, n: c.size_t) -> c.size_t
mz_file_write_func        :: proc "c" (pOpaque: rawptr, file_ofs: mz_uint64, pBuf: rawptr, n: c.size_t) -> c.size_t
mz_file_needs_keepalive   :: proc "c" (pOpaque: rawptr) -> mz_bool
mz_zip_internal_state_tag :: struct {}
mz_zip_internal_state     :: mz_zip_internal_state_tag

mz_zip_mode :: enum i32 {
	INVALID                    = 0,
	READING                    = 1,
	WRITING                    = 2,
	WRITING_HAS_BEEN_FINALIZED = 3,
}

mz_zip_flags :: enum i32 {
	CASE_SENSITIVE                = 256,
	IGNORE_PATH                   = 512,
	COMPRESSED_DATA               = 1024,
	DO_NOT_SORT_CENTRAL_DIRECTORY = 2048,
	VALIDATE_LOCATE_FILE_FLAG     = 4096,  /* if enabled, mz_zip_reader_locate_file() will be called on each file as its validated to ensure the func finds the file in the central dir (intended for testing) */
	VALIDATE_HEADERS_ONLY         = 8192,  /* validate the local headers, but don't decompress the entire file and check the crc32 */
	WRITE_ZIP64                   = 16384, /* always use the zip64 file format, instead of the original zip file format with automatic switch to zip64. Use as flags parameter with mz_zip_writer_init*_v2 */
	WRITE_ALLOW_READING           = 32768,
	ASCII_FILENAME                = 65536,

	/*After adding a compressed file, seek back
	to local file header and set the correct sizes*/
	WRITE_HEADER_SET_SIZE         = 131072,
	READ_ALLOW_WRITING            = 262144,
}

mz_zip_type :: enum i32 {
	YPE_INVALID = 0,
	YPE_USER    = 1,
	YPE_MEMORY  = 2,
	YPE_HEAP    = 3,
	YPE_FILE    = 4,
	YPE_CFILE   = 5,
	OTAL_TYPES  = 6,
}

/* miniz error codes. Be sure to update mz_zip_get_error_string() if you add or modify this enum. */
mz_zip_error :: enum i32 {
	NO_ERROR                     = 0,
	UNDEFINED_ERROR              = 1,
	TOO_MANY_FILES               = 2,
	FILE_TOO_LARGE               = 3,
	UNSUPPORTED_METHOD           = 4,
	UNSUPPORTED_ENCRYPTION       = 5,
	UNSUPPORTED_FEATURE          = 6,
	FAILED_FINDING_CENTRAL_DIR   = 7,
	NOT_AN_ARCHIVE               = 8,
	INVALID_HEADER_OR_CORRUPTED  = 9,
	UNSUPPORTED_MULTIDISK        = 10,
	DECOMPRESSION_FAILED         = 11,
	COMPRESSION_FAILED           = 12,
	UNEXPECTED_DECOMPRESSED_SIZE = 13,
	CRC_CHECK_FAILED             = 14,
	UNSUPPORTED_CDIR_SIZE        = 15,
	ALLOC_FAILED                 = 16,
	FILE_OPEN_FAILED             = 17,
	FILE_CREATE_FAILED           = 18,
	FILE_WRITE_FAILED            = 19,
	FILE_READ_FAILED             = 20,
	FILE_CLOSE_FAILED            = 21,
	FILE_SEEK_FAILED             = 22,
	FILE_STAT_FAILED             = 23,
	INVALID_PARAMETER            = 24,
	INVALID_FILENAME             = 25,
	BUF_TOO_SMALL                = 26,
	INTERNAL_ERROR               = 27,
	FILE_NOT_FOUND               = 28,
	ARCHIVE_TOO_LARGE            = 29,
	VALIDATION_FAILED            = 30,
	WRITE_CALLBACK_FAILED        = 31,
	TOTAL_ERRORS                 = 32,
}

mz_zip_archive :: struct {
	m_archive_size:               mz_uint64,
	m_central_directory_file_ofs: mz_uint64,

	/* We only support up to UINT32_MAX files in zip64 mode. */
	m_total_files:           mz_uint32,
	m_zip_mode:              mz_zip_mode,
	m_zip_type:              mz_zip_type,
	m_last_error:            mz_zip_error,
	m_file_offset_alignment: mz_uint64,
	m_pAlloc:                mz_alloc_func,
	m_pFree:                 mz_free_func,
	m_pRealloc:              mz_realloc_func,
	m_pAlloc_opaque:         rawptr,
	m_pRead:                 mz_file_read_func,
	m_pWrite:                mz_file_write_func,
	m_pNeeds_keepalive:      mz_file_needs_keepalive,
	m_pIO_opaque:            rawptr,
	m_pState:                ^mz_zip_internal_state,
}

mz_zip_reader_extract_iter_state :: struct {
	pZip:                                                                                   ^mz_zip_archive,
	flags:                                                                                  mz_uint,
	status:                                                                                 i32,
	read_buf_size, read_buf_ofs, read_buf_avail, comp_remaining, out_buf_ofs, cur_file_ofs: mz_uint64,
	file_stat:                                                                              mz_zip_archive_file_stat,
	pRead_buf:                                                                              rawptr,
	pWrite_buf:                                                                             rawptr,
	out_blk_remain:                                                                         c.size_t,
	inflator:                                                                               i32,
	file_crc32:                                                                             mz_uint,
}

foreign import lib "../../../vendor/build/vendor/miniz/miniz.lib"

@(default_calling_convention="c")
foreign lib {
	/* Inits a ZIP archive reader. */
	/* These functions read and validate the archive's central directory. */
	mz_zip_reader_init     :: proc(pZip: ^mz_zip_archive, size: mz_uint64, flags: mz_uint) -> mz_bool ---
	mz_zip_reader_init_mem :: proc(pZip: ^mz_zip_archive, pMem: rawptr, size: c.size_t, flags: mz_uint) -> mz_bool ---

	/* Read a archive from a disk file. */
	/* file_start_ofs is the file offset where the archive actually begins, or 0. */
	/* actual_archive_size is the true total size of the archive, which may be smaller than the file's actual size on disk. If zero the entire file is treated as the archive. */
	mz_zip_reader_init_file    :: proc(pZip: ^mz_zip_archive, pFilename: cstring, flags: mz_uint32) -> mz_bool ---
	mz_zip_reader_init_file_v2 :: proc(pZip: ^mz_zip_archive, pFilename: cstring, flags: mz_uint, file_start_ofs: mz_uint64, archive_size: mz_uint64) -> mz_bool ---

	/* Read an archive from an already opened FILE, beginning at the current file position. */
	/* The archive is assumed to be archive_size bytes long. If archive_size is 0, then the entire rest of the file is assumed to contain the archive. */
	/* The FILE will NOT be closed when mz_zip_reader_end() is called. */
	mz_zip_reader_init_cfile :: proc(pZip: ^mz_zip_archive, pFile: ^libc.FILE, archive_size: mz_uint64, flags: mz_uint) -> mz_bool ---

	/* Ends archive reading, freeing all allocations, and closing the input archive file if mz_zip_reader_init_file() was used. */
	mz_zip_reader_end :: proc(pZip: ^mz_zip_archive) -> mz_bool ---

	/* Clears a mz_zip_archive struct to all zeros. */
	/* Important: This must be done before passing the struct to any mz_zip functions. */
	mz_zip_zero_struct :: proc(pZip: ^mz_zip_archive) ---
	mz_zip_get_mode    :: proc(pZip: ^mz_zip_archive) -> mz_zip_mode ---
	mz_zip_get_type    :: proc(pZip: ^mz_zip_archive) -> mz_zip_type ---

	/* Returns the total number of files in the archive. */
	mz_zip_reader_get_num_files          :: proc(pZip: ^mz_zip_archive) -> mz_uint ---
	mz_zip_get_archive_size              :: proc(pZip: ^mz_zip_archive) -> mz_uint64 ---
	mz_zip_get_archive_file_start_offset :: proc(pZip: ^mz_zip_archive) -> mz_uint64 ---
	mz_zip_get_cfile                     :: proc(pZip: ^mz_zip_archive) -> ^libc.FILE ---

	/* Reads n bytes of raw archive data, starting at file offset file_ofs, to pBuf. */
	mz_zip_read_archive_data :: proc(pZip: ^mz_zip_archive, file_ofs: mz_uint64, pBuf: rawptr, n: c.size_t) -> c.size_t ---

	/* All mz_zip funcs set the m_last_error field in the mz_zip_archive struct. These functions retrieve/manipulate this field. */
	/* Note that the m_last_error functionality is not thread safe. */
	mz_zip_set_last_error   :: proc(pZip: ^mz_zip_archive, err_num: mz_zip_error) -> mz_zip_error ---
	mz_zip_peek_last_error  :: proc(pZip: ^mz_zip_archive) -> mz_zip_error ---
	mz_zip_clear_last_error :: proc(pZip: ^mz_zip_archive) -> mz_zip_error ---
	mz_zip_get_last_error   :: proc(pZip: ^mz_zip_archive) -> mz_zip_error ---
	mz_zip_get_error_string :: proc(mz_err: mz_zip_error) -> cstring ---

	/* MZ_TRUE if the archive file entry is a directory entry. */
	mz_zip_reader_is_file_a_directory :: proc(pZip: ^mz_zip_archive, file_index: mz_uint) -> mz_bool ---

	/* MZ_TRUE if the file is encrypted/strong encrypted. */
	mz_zip_reader_is_file_encrypted :: proc(pZip: ^mz_zip_archive, file_index: mz_uint) -> mz_bool ---

	/* MZ_TRUE if the compression method is supported, and the file is not encrypted, and the file is not a compressed patch file. */
	mz_zip_reader_is_file_supported :: proc(pZip: ^mz_zip_archive, file_index: mz_uint) -> mz_bool ---

	/* Retrieves the filename of an archive file entry. */
	/* Returns the number of bytes written to pFilename, or if filename_buf_size is 0 this function returns the number of bytes needed to fully store the filename. */
	mz_zip_reader_get_filename :: proc(pZip: ^mz_zip_archive, file_index: mz_uint, pFilename: cstring, filename_buf_size: mz_uint) -> mz_uint ---

	/* Attempts to locates a file in the archive's central directory. */
	/* Valid flags: MZ_ZIP_FLAG_CASE_SENSITIVE, MZ_ZIP_FLAG_IGNORE_PATH */
	/* Returns -1 if the file cannot be found. */
	mz_zip_reader_locate_file    :: proc(pZip: ^mz_zip_archive, pName: cstring, pComment: cstring, flags: mz_uint) -> i32 ---
	mz_zip_reader_locate_file_v2 :: proc(pZip: ^mz_zip_archive, pName: cstring, pComment: cstring, flags: mz_uint, file_index: ^mz_uint32) -> mz_bool ---

	/* Returns detailed information about an archive file entry. */
	mz_zip_reader_file_stat :: proc(pZip: ^mz_zip_archive, file_index: mz_uint, pStat: ^mz_zip_archive_file_stat) -> mz_bool ---

	/* MZ_TRUE if the file is in zip64 format. */
	/* A file is considered zip64 if it contained a zip64 end of central directory marker, or if it contained any zip64 extended file information fields in the central directory. */
	mz_zip_is_zip64 :: proc(pZip: ^mz_zip_archive) -> mz_bool ---

	/* Returns the total central directory size in bytes. */
	/* The current max supported size is <= MZ_UINT32_MAX. */
	mz_zip_get_central_dir_size :: proc(pZip: ^mz_zip_archive) -> c.size_t ---

	/* Extracts a archive file to a memory buffer using no memory allocation. */
	/* There must be at least enough room on the stack to store the inflator's state (~34KB or so). */
	mz_zip_reader_extract_to_mem_no_alloc      :: proc(pZip: ^mz_zip_archive, file_index: mz_uint, pBuf: rawptr, buf_size: c.size_t, flags: mz_uint, pUser_read_buf: rawptr, user_read_buf_size: c.size_t) -> mz_bool ---
	mz_zip_reader_extract_file_to_mem_no_alloc :: proc(pZip: ^mz_zip_archive, pFilename: cstring, pBuf: rawptr, buf_size: c.size_t, flags: mz_uint, pUser_read_buf: rawptr, user_read_buf_size: c.size_t) -> mz_bool ---

	/* Extracts a archive file to a memory buffer. */
	mz_zip_reader_extract_to_mem      :: proc(pZip: ^mz_zip_archive, file_index: mz_uint, pBuf: rawptr, buf_size: c.size_t, flags: mz_uint) -> mz_bool ---
	mz_zip_reader_extract_file_to_mem :: proc(pZip: ^mz_zip_archive, pFilename: cstring, pBuf: rawptr, buf_size: c.size_t, flags: mz_uint) -> mz_bool ---

	/* Extracts a archive file to a dynamically allocated heap buffer. */
	/* The memory will be allocated via the mz_zip_archive's alloc/realloc functions. */
	/* Returns NULL and sets the last error on failure. */
	mz_zip_reader_extract_to_heap      :: proc(pZip: ^mz_zip_archive, file_index: mz_uint, pSize: ^c.size_t, flags: mz_uint) -> rawptr ---
	mz_zip_reader_extract_file_to_heap :: proc(pZip: ^mz_zip_archive, pFilename: cstring, pSize: ^c.size_t, flags: mz_uint) -> rawptr ---

	/* Extracts a archive file using a callback function to output the file's data. */
	mz_zip_reader_extract_to_callback      :: proc(pZip: ^mz_zip_archive, file_index: mz_uint, pCallback: mz_file_write_func, pOpaque: rawptr, flags: mz_uint) -> mz_bool ---
	mz_zip_reader_extract_file_to_callback :: proc(pZip: ^mz_zip_archive, pFilename: cstring, pCallback: mz_file_write_func, pOpaque: rawptr, flags: mz_uint) -> mz_bool ---

	/* Extract a file iteratively */
	mz_zip_reader_extract_iter_new      :: proc(pZip: ^mz_zip_archive, file_index: mz_uint, flags: mz_uint) -> ^mz_zip_reader_extract_iter_state ---
	mz_zip_reader_extract_file_iter_new :: proc(pZip: ^mz_zip_archive, pFilename: cstring, flags: mz_uint) -> ^mz_zip_reader_extract_iter_state ---
	mz_zip_reader_extract_iter_read     :: proc(pState: ^mz_zip_reader_extract_iter_state, pvBuf: rawptr, buf_size: c.size_t) -> c.size_t ---
	mz_zip_reader_extract_iter_free     :: proc(pState: ^mz_zip_reader_extract_iter_state) -> mz_bool ---

	/* Extracts a archive file to a disk file and sets its last accessed and modified times. */
	/* This function only extracts files, not archive directory records. */
	mz_zip_reader_extract_to_file      :: proc(pZip: ^mz_zip_archive, file_index: mz_uint, pDst_filename: cstring, flags: mz_uint) -> mz_bool ---
	mz_zip_reader_extract_file_to_file :: proc(pZip: ^mz_zip_archive, pArchive_filename: cstring, pDst_filename: cstring, flags: mz_uint) -> mz_bool ---

	/* Extracts a archive file starting at the current position in the destination FILE stream. */
	mz_zip_reader_extract_to_cfile      :: proc(pZip: ^mz_zip_archive, file_index: mz_uint, File: ^libc.FILE, flags: mz_uint) -> mz_bool ---
	mz_zip_reader_extract_file_to_cfile :: proc(pZip: ^mz_zip_archive, pArchive_filename: cstring, pFile: ^libc.FILE, flags: mz_uint) -> mz_bool ---

	/* This function compares the archive's local headers, the optional local zip64 extended information block, and the optional descriptor following the compressed data vs. the data in the central directory. */
	/* It also validates that each file can be successfully uncompressed unless the MZ_ZIP_FLAG_VALIDATE_HEADERS_ONLY is specified. */
	mz_zip_validate_file :: proc(pZip: ^mz_zip_archive, file_index: mz_uint, flags: mz_uint) -> mz_bool ---

	/* Validates an entire archive by calling mz_zip_validate_file() on each file. */
	mz_zip_validate_archive :: proc(pZip: ^mz_zip_archive, flags: mz_uint) -> mz_bool ---

	/* Misc utils/helpers, valid for ZIP reading or writing */
	mz_zip_validate_mem_archive  :: proc(pMem: rawptr, size: c.size_t, flags: mz_uint, pErr: ^mz_zip_error) -> mz_bool ---
	mz_zip_validate_file_archive :: proc(pFilename: cstring, flags: mz_uint, pErr: ^mz_zip_error) -> mz_bool ---

	/* Universal end function - calls either mz_zip_reader_end() or mz_zip_writer_end(). */
	mz_zip_end :: proc(pZip: ^mz_zip_archive) -> mz_bool ---

	/* Inits a ZIP archive writer. */
	/*Set pZip->m_pWrite (and pZip->m_pIO_opaque) before calling mz_zip_writer_init or mz_zip_writer_init_v2*/
	/*The output is streamable, i.e. file_ofs in mz_file_write_func always increases only by n*/
	mz_zip_writer_init         :: proc(pZip: ^mz_zip_archive, existing_size: mz_uint64) -> mz_bool ---
	mz_zip_writer_init_v2      :: proc(pZip: ^mz_zip_archive, existing_size: mz_uint64, flags: mz_uint) -> mz_bool ---
	mz_zip_writer_init_heap    :: proc(pZip: ^mz_zip_archive, size_to_reserve_at_beginning: c.size_t, initial_allocation_size: c.size_t) -> mz_bool ---
	mz_zip_writer_init_heap_v2 :: proc(pZip: ^mz_zip_archive, size_to_reserve_at_beginning: c.size_t, initial_allocation_size: c.size_t, flags: mz_uint) -> mz_bool ---
	mz_zip_writer_init_file    :: proc(pZip: ^mz_zip_archive, pFilename: cstring, size_to_reserve_at_beginning: mz_uint64) -> mz_bool ---
	mz_zip_writer_init_file_v2 :: proc(pZip: ^mz_zip_archive, pFilename: cstring, size_to_reserve_at_beginning: mz_uint64, flags: mz_uint) -> mz_bool ---
	mz_zip_writer_init_cfile   :: proc(pZip: ^mz_zip_archive, pFile: ^libc.FILE, flags: mz_uint) -> mz_bool ---

	/* Converts a ZIP archive reader object into a writer object, to allow efficient in-place file appends to occur on an existing archive. */
	/* For archives opened using mz_zip_reader_init_file, pFilename must be the archive's filename so it can be reopened for writing. If the file can't be reopened, mz_zip_reader_end() will be called. */
	/* For archives opened using mz_zip_reader_init_mem, the memory block must be growable using the realloc callback (which defaults to realloc unless you've overridden it). */
	/* Finally, for archives opened using mz_zip_reader_init, the mz_zip_archive's user provided m_pWrite function cannot be NULL. */
	/* Note: In-place archive modification is not recommended unless you know what you're doing, because if execution stops or something goes wrong before */
	/* the archive is finalized the file's central directory will be hosed. */
	mz_zip_writer_init_from_reader    :: proc(pZip: ^mz_zip_archive, pFilename: cstring) -> mz_bool ---
	mz_zip_writer_init_from_reader_v2 :: proc(pZip: ^mz_zip_archive, pFilename: cstring, flags: mz_uint) -> mz_bool ---

	/* Adds the contents of a memory buffer to an archive. These functions record the current local time into the archive. */
	/* To add a directory entry, call this method with an archive name ending in a forwardslash with an empty buffer. */
	/* level_and_flags - compression level (0-10, see MZ_BEST_SPEED, MZ_BEST_COMPRESSION, etc.) logically OR'd with zero or more mz_zip_flags, or just set to MZ_DEFAULT_COMPRESSION. */
	mz_zip_writer_add_mem :: proc(pZip: ^mz_zip_archive, pArchive_name: cstring, pBuf: rawptr, buf_size: c.size_t, level_and_flags: mz_uint) -> mz_bool ---

	/* Like mz_zip_writer_add_mem(), except you can specify a file comment field, and optionally supply the function with already compressed data. */
	/* uncomp_size/uncomp_crc32 are only used if the MZ_ZIP_FLAG_COMPRESSED_DATA flag is specified. */
	mz_zip_writer_add_mem_ex    :: proc(pZip: ^mz_zip_archive, pArchive_name: cstring, pBuf: rawptr, buf_size: c.size_t, pComment: rawptr, comment_size: mz_uint16, level_and_flags: mz_uint, uncomp_size: mz_uint64, uncomp_crc32: mz_uint32) -> mz_bool ---
	mz_zip_writer_add_mem_ex_v2 :: proc(pZip: ^mz_zip_archive, pArchive_name: cstring, pBuf: rawptr, buf_size: c.size_t, pComment: rawptr, comment_size: mz_uint16, level_and_flags: mz_uint, uncomp_size: mz_uint64, uncomp_crc32: mz_uint32, last_modified: ^libc.time_t, user_extra_data_local: cstring, user_extra_data_local_len: mz_uint, user_extra_data_central: cstring, user_extra_data_central_len: mz_uint) -> mz_bool ---

	/* Adds the contents of a file to an archive. This function also records the disk file's modified time into the archive. */
	/* File data is supplied via a read callback function. User mz_zip_writer_add_(c)file to add a file directly.*/
	mz_zip_writer_add_read_buf_callback :: proc(pZip: ^mz_zip_archive, pArchive_name: cstring, read_callback: mz_file_read_func, callback_opaque: rawptr, max_size: mz_uint64, pFile_time: ^libc.time_t, pComment: rawptr, comment_size: mz_uint16, level_and_flags: mz_uint, user_extra_data_local: cstring, user_extra_data_local_len: mz_uint, user_extra_data_central: cstring, user_extra_data_central_len: mz_uint) -> mz_bool ---

	/* Adds the contents of a disk file to an archive. This function also records the disk file's modified time into the archive. */
	/* level_and_flags - compression level (0-10, see MZ_BEST_SPEED, MZ_BEST_COMPRESSION, etc.) logically OR'd with zero or more mz_zip_flags, or just set to MZ_DEFAULT_COMPRESSION. */
	mz_zip_writer_add_file :: proc(pZip: ^mz_zip_archive, pArchive_name: cstring, pSrc_filename: cstring, pComment: rawptr, comment_size: mz_uint16, level_and_flags: mz_uint) -> mz_bool ---

	/* Like mz_zip_writer_add_file(), except the file data is read from the specified FILE stream. */
	mz_zip_writer_add_cfile :: proc(pZip: ^mz_zip_archive, pArchive_name: cstring, pSrc_file: ^libc.FILE, max_size: mz_uint64, pFile_time: ^libc.time_t, pComment: rawptr, comment_size: mz_uint16, level_and_flags: mz_uint, user_extra_data_local: cstring, user_extra_data_local_len: mz_uint, user_extra_data_central: cstring, user_extra_data_central_len: mz_uint) -> mz_bool ---

	/* Adds a file to an archive by fully cloning the data from another archive. */
	/* This function fully clones the source file's compressed data (no recompression), along with its full filename, extra data (it may add or modify the zip64 local header extra data field), and the optional descriptor following the compressed data. */
	mz_zip_writer_add_from_zip_reader :: proc(pZip: ^mz_zip_archive, pSource_zip: ^mz_zip_archive, src_file_index: mz_uint) -> mz_bool ---

	/* Finalizes the archive by writing the central directory records followed by the end of central directory record. */
	/* After an archive is finalized, the only valid call on the mz_zip_archive struct is mz_zip_writer_end(). */
	/* An archive must be manually finalized by calling this function for it to be valid. */
	mz_zip_writer_finalize_archive :: proc(pZip: ^mz_zip_archive) -> mz_bool ---

	/* Finalizes a heap archive, returning a pointer to the heap block and its size. */
	/* The heap block will be allocated using the mz_zip_archive's alloc/realloc callbacks. */
	mz_zip_writer_finalize_heap_archive :: proc(pZip: ^mz_zip_archive, ppBuf: ^rawptr, pSize: ^c.size_t) -> mz_bool ---

	/* Ends archive writing, freeing all allocations, and closing the output file if mz_zip_writer_init_file() was used. */
	/* Note for the archive to be valid, it *must* have been finalized before ending (this function will not do it for you). */
	mz_zip_writer_end :: proc(pZip: ^mz_zip_archive) -> mz_bool ---

	/* mz_zip_add_mem_to_archive_file_in_place() efficiently (but not atomically) appends a memory blob to a ZIP archive. */
	/* Note this is NOT a fully safe operation. If it crashes or dies in some way your archive can be left in a screwed up state (without a central directory). */
	/* level_and_flags - compression level (0-10, see MZ_BEST_SPEED, MZ_BEST_COMPRESSION, etc.) logically OR'd with zero or more mz_zip_flags, or just set to MZ_DEFAULT_COMPRESSION. */
	/* TODO: Perhaps add an option to leave the existing central dir in place in case the add dies? We could then truncate the file (so the old central dir would be at the end) if something goes wrong. */
	mz_zip_add_mem_to_archive_file_in_place    :: proc(pZip_filename: cstring, pArchive_name: cstring, pBuf: rawptr, buf_size: c.size_t, pComment: rawptr, comment_size: mz_uint16, level_and_flags: mz_uint) -> mz_bool ---
	mz_zip_add_mem_to_archive_file_in_place_v2 :: proc(pZip_filename: cstring, pArchive_name: cstring, pBuf: rawptr, buf_size: c.size_t, pComment: rawptr, comment_size: mz_uint16, level_and_flags: mz_uint, pErr: ^mz_zip_error) -> mz_bool ---

	/* Reads a single file from an archive into a heap block. */
	/* If pComment is not NULL, only the file with the specified comment will be extracted. */
	/* Returns NULL on failure. */
	mz_zip_extract_archive_file_to_heap    :: proc(pZip_filename: cstring, pArchive_name: cstring, pSize: ^c.size_t, flags: mz_uint) -> rawptr ---
	mz_zip_extract_archive_file_to_heap_v2 :: proc(pZip_filename: cstring, pArchive_name: cstring, pComment: cstring, pSize: ^c.size_t, flags: mz_uint, pErr: ^mz_zip_error) -> rawptr ---
}

