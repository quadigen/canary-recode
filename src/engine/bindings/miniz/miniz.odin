/* miniz.c 3.1.2 - public domain deflate/inflate, zlib-subset, ZIP reading/writing/appending, PNG writing
   See "unlicense" statement at the end of this file.
   Rich Geldreich <richgel99@gmail.com>, last updated Oct. 13, 2013
   Implements RFC 1950: http://www.ietf.org/rfc/rfc1950.txt and RFC 1951: http://www.ietf.org/rfc/rfc1951.txt

   Most API's defined in miniz.c are optional. For example, to disable the archive related functions just define
   MINIZ_NO_ARCHIVE_APIS, or to get rid of all stdio usage define MINIZ_NO_STDIO (see the list below for more macros).

   * Low-level Deflate/Inflate implementation notes:

     Compression: Use the "tdefl" API's. The compressor supports raw, static, and dynamic blocks, lazy or
     greedy parsing, match length filtering, RLE-only, and Huffman-only streams. It performs and compresses
     approximately as well as zlib.

     Decompression: Use the "tinfl" API's. The entire decompressor is implemented as a single function
     coroutine: see tinfl_decompress(). It supports decompression into a 32KB (or larger power of 2) wrapping buffer, or into a memory
     block large enough to hold the entire file.

     The low-level tdefl/tinfl API's do not make any use of dynamic memory allocation.

   * zlib-style API notes:

     miniz.c implements a fairly large subset of zlib. There's enough functionality present for it to be a drop-in
     zlib replacement in many apps:
        The z_stream struct, optional memory allocation callbacks
        deflateInit/deflateInit2/deflate/deflateReset/deflateEnd/deflateBound
        inflateInit/inflateInit2/inflate/inflateReset/inflateEnd
        compress, compress2, compressBound, uncompress
        CRC-32, Adler-32 - Using modern, minimal code size, CPU cache friendly routines.
        Supports raw deflate streams or standard zlib streams with adler-32 checking.

     Limitations:
      The callback API's are not implemented yet. No support for gzip headers or zlib static dictionaries.
      I've tried to closely emulate zlib's various flavors of stream flushing and return status codes, but
      there are no guarantees that miniz.c pulls this off perfectly.

   * PNG writing: See the tdefl_write_image_to_png_file_in_memory() function, originally written by
     Alex Evans. Supports 1-4 bytes/pixel images.

   * ZIP archive API notes:

     The ZIP archive API's where designed with simplicity and efficiency in mind, with just enough abstraction to
     get the job done with minimal fuss. There are simple API's to retrieve file information, read files from
     existing archives, create new archives, append new files to existing archives, or clone archive data from
     one archive to another. It supports archives located in memory or the heap, on disk (using stdio.h),
     or you can specify custom file read/write callbacks.

     - Archive reading: Just call this function to read a single file from a disk archive:

      void *mz_zip_extract_archive_file_to_heap(const char *pZip_filename, const char *pArchive_name,
        size_t *pSize, mz_uint zip_flags);

     For more complex cases, use the "mz_zip_reader" functions. Upon opening an archive, the entire central
     directory is located and read as-is into memory, and subsequent file access only occurs when reading individual files.

     - Archives file scanning: The simple way is to use this function to scan a loaded archive for a specific file:

     int mz_zip_reader_locate_file(mz_zip_archive *pZip, const char *pName, const char *pComment, mz_uint flags);

     The locate operation can optionally check file comments too, which (as one example) can be used to identify
     multiple versions of the same file in an archive. This function uses a simple linear search through the central
     directory, so it's not very fast.

     Alternately, you can iterate through all the files in an archive (using mz_zip_reader_get_num_files()) and
     retrieve detailed info on each file by calling mz_zip_reader_file_stat().

     - Archive creation: Use the "mz_zip_writer" functions. The ZIP writer immediately writes compressed file data
     to disk and builds an exact image of the central directory in memory. The central directory image is written
     all at once at the end of the archive file when the archive is finalized.

     The archive writer can optionally align each file's local header and file data to any power of 2 alignment,
     which can be useful when the archive will be read from optical media. Also, the writer supports placing
     arbitrary data blobs at the very beginning of ZIP archives. Archives written using either feature are still
     readable by any ZIP tool.

     - Archive appending: The simple way to add a single file to an archive is to call this function:

      mz_bool mz_zip_add_mem_to_archive_file_in_place(const char *pZip_filename, const char *pArchive_name,
        const void *pBuf, size_t buf_size, const void *pComment, mz_uint16 comment_size, mz_uint level_and_flags);

     The archive will be created if it doesn't already exist, otherwise it'll be appended to.
     Note the appending is done in-place and is not an atomic operation, so if something goes wrong
     during the operation it's possible the archive could be left without a central directory (although the local
     file headers and file data will be fine, so the archive will be recoverable).

     For more complex archive modification scenarios:
     1. The safest way is to use a mz_zip_reader to read the existing archive, cloning only those bits you want to
     preserve into a new archive using using the mz_zip_writer_add_from_zip_reader() function (which compiles the
     compressed file data as-is). When you're done, delete the old archive and rename the newly written archive, and
     you're done. This is safe but requires a bunch of temporary disk space or heap memory.

     2. Or, you can convert an mz_zip_reader in-place to an mz_zip_writer using mz_zip_writer_init_from_reader(),
     append new files as needed, then finalize the archive which will write an updated central directory to the
     original archive. (This is basically what mz_zip_add_mem_to_archive_file_in_place() does.) There's a
     possibility that the archive's central directory could be lost with this method if anything goes wrong, though.

     - ZIP archive support limitations:
     No spanning support. Extraction functions can only handle unencrypted, stored or deflated files.
     Requires streams capable of seeking.

   * This is a header file library, like stb_image.c. To get only a header file, either cut and paste the
     below header, or create miniz.h, #define MINIZ_HEADER_FILE_ONLY, and then include miniz.c from it.

   * Important: For best perf. be sure to customize the below macros for your target platform:
     #define MINIZ_USE_UNALIGNED_LOADS_AND_STORES 1
     #define MINIZ_LITTLE_ENDIAN 1
     #define MINIZ_HAS_64BIT_REGISTERS 1

   * On platforms using glibc, Be sure to "#define _LARGEFILE64_SOURCE 1" before including miniz.c to ensure miniz
     uses the 64-bit variants: fopen64(), stat64(), etc. Otherwise you won't be able to process large files
     (i.e. 32-bit stat() fails for me on files > 0x7FFFFFFF bytes).
*/
package zip

import "core:c"

/* MINIZ_X86_OR_X64_CPU is only used to help set the below macros. */
MINIZ_X86_OR_X64_CPU :: 1

/* Set MINIZ_LITTLE_ENDIAN to 1 if the processor is little endian. */
MINIZ_LITTLE_ENDIAN :: 1

/* Set MINIZ_USE_UNALIGNED_LOADS_AND_STORES to 1 on CPU's that permit efficient integer loads and stores from unaligned addresses. */
MINIZ_USE_UNALIGNED_LOADS_AND_STORES :: 0

/* Set MINIZ_HAS_64BIT_REGISTERS to 1 if operations on 64-bit integers are reasonably fast (and don't involve compiler generated calls to helper functions). */
MINIZ_HAS_64BIT_REGISTERS :: 1

/* For more compatibility with zlib, miniz.c uses unsigned long for some parameters/struct members. Beware: mz_ulong can be either 32 or 64-bits! */
mz_ulong :: c.ulong

foreign import lib "../../../vendor/build/vendor/miniz/miniz.lib"

@(default_calling_convention="c")
foreign lib {
	/* mz_free() internally uses the MZ_FREE() macro (which by default calls free() unless you've modified the MZ_MALLOC macro) to release a block allocated from the heap. */
	mz_free :: proc(p: rawptr) ---
}

MZ_ADLER32_INIT :: (1)

@(default_calling_convention="c")
foreign lib {
	/* mz_adler32() returns the initial adler-32 value to use when called with ptr==NULL. */
	mz_adler32 :: proc(adler: mz_ulong, ptr: ^u8, buf_len: c.size_t) -> mz_ulong ---
}

MZ_CRC32_INIT :: (0)

@(default_calling_convention="c")
foreign lib {
	/* mz_crc32() returns the initial CRC-32 value to use when called with ptr==NULL. */
	mz_crc32 :: proc(crc: mz_ulong, ptr: ^u8, buf_len: c.size_t) -> mz_ulong ---
}

MZ_FILTERED         :: 1
MZ_DEFAULT_STRATEGY :: 0
MZ_FIXED            :: 4
MZ_HUFFMAN_ONLY     :: 2
MZ_RLE              :: 3

/* Method */
MZ_DEFLATED :: 8

/* Heap allocation callbacks.
Note that mz_alloc_func parameter types purposely differ from zlib's: items/size is size_t, not unsigned long. */
mz_alloc_func   :: proc "c" (opaque: rawptr, items: c.size_t, size: c.size_t) -> rawptr
mz_free_func    :: proc "c" (opaque: rawptr, address: rawptr)
mz_realloc_func :: proc "c" (opaque: rawptr, address: rawptr, items: c.size_t, size: c.size_t) -> rawptr

MZ_DEFAULT_COMPRESSION :: -1
MZ_UBER_COMPRESSION    :: 10
MZ_BEST_COMPRESSION    :: 9
MZ_DEFAULT_LEVEL       :: 6
MZ_NO_COMPRESSION      :: 0
MZ_BEST_SPEED          :: 1
MZ_VERSION             :: "11.3.2"
MZ_VERNUM              :: 0xB302
MZ_VER_MAJOR           :: 11
MZ_VER_MINOR           :: 3
MZ_VER_REVISION        :: 2
MZ_VER_SUBREVISION     :: 0
MZ_SYNC_FLUSH          :: 2
MZ_PARTIAL_FLUSH       :: 1
MZ_FULL_FLUSH          :: 3
MZ_NO_FLUSH            :: 0
MZ_FINISH              :: 4
MZ_BLOCK               :: 5
MZ_PARAM_ERROR         :: -10000
MZ_MEM_ERROR           :: -4
MZ_DATA_ERROR          :: -3
MZ_BUF_ERROR           :: -5
MZ_ERRNO               :: -1
MZ_STREAM_END          :: 1
MZ_OK                  :: 0
MZ_NEED_DICT           :: 2
MZ_STREAM_ERROR        :: -2
MZ_VERSION_ERROR       :: -6

/* Window bits */
MZ_DEFAULT_WINDOW_BITS :: 15

mz_internal_state :: struct {}

/* Compression/decompression stream struct. */
mz_stream_s :: struct {
	next_in:   ^u8,                /* pointer to next byte to read */
	avail_in:  u32,                /* number of bytes available at next_in */
	total_in:  mz_ulong,           /* total number of bytes consumed so far */
	next_out:  ^u8,                /* pointer to next byte to write */
	avail_out: u32,                /* number of bytes that can be written to next_out */
	total_out: mz_ulong,           /* total number of bytes produced so far */
	msg:       cstring,            /* error msg (unused) */
	state:     ^mz_internal_state, /* internal state, allocated by zalloc/zfree */
	zalloc:    mz_alloc_func,      /* optional heap allocation function (defaults to malloc) */
	zfree:     mz_free_func,       /* optional heap free function (defaults to free) */
	opaque:    rawptr,             /* heap alloc function user pointer */
	data_type: i32,                /* data_type (unused) */
	adler:     mz_ulong,           /* adler32 of the source or uncompressed data */
	reserved:  mz_ulong,           /* not used */
}

/* Compression/decompression stream struct. */
mz_stream  :: mz_stream_s
mz_streamp :: ^mz_stream

@(default_calling_convention="c")
foreign lib {
	/* Returns the version string of miniz.c. */
	mz_version :: proc() -> cstring ---

	/* mz_deflateInit() initializes a compressor with default options: */
	/* Parameters: */
	/*  pStream must point to an initialized mz_stream struct. */
	/*  level must be between [MZ_NO_COMPRESSION, MZ_BEST_COMPRESSION]. */
	/*  level 1 enables a specially optimized compression function that's been optimized purely for performance, not ratio. */
	/*  (This special func. is currently only enabled when MINIZ_USE_UNALIGNED_LOADS_AND_STORES and MINIZ_LITTLE_ENDIAN are defined.) */
	/* Return values: */
	/*  MZ_OK on success. */
	/*  MZ_STREAM_ERROR if the stream is bogus. */
	/*  MZ_PARAM_ERROR if the input parameters are bogus. */
	/*  MZ_MEM_ERROR on out of memory. */
	mz_deflateInit :: proc(pStream: mz_streamp, level: i32) -> i32 ---

	/* mz_deflateInit2() is like mz_deflate(), except with more control: */
	/* Additional parameters: */
	/*   method must be MZ_DEFLATED */
	/*   window_bits must be MZ_DEFAULT_WINDOW_BITS (to wrap the deflate stream with zlib header/adler-32 footer) or -MZ_DEFAULT_WINDOW_BITS (raw deflate/no header or footer) */
	/*   mem_level must be between [1, 9] (it's checked but ignored by miniz.c) */
	mz_deflateInit2 :: proc(pStream: mz_streamp, level: i32, method: i32, window_bits: i32, mem_level: i32, strategy: i32) -> i32 ---

	/* Quickly resets a compressor without having to reallocate anything. Same as calling mz_deflateEnd() followed by mz_deflateInit()/mz_deflateInit2(). */
	mz_deflateReset :: proc(pStream: mz_streamp) -> i32 ---

	/* mz_deflate() compresses the input to output, consuming as much of the input and producing as much output as possible. */
	/* Parameters: */
	/*   pStream is the stream to read from and write to. You must initialize/update the next_in, avail_in, next_out, and avail_out members. */
	/*   flush may be MZ_NO_FLUSH, MZ_PARTIAL_FLUSH/MZ_SYNC_FLUSH, MZ_FULL_FLUSH, or MZ_FINISH. */
	/* Return values: */
	/*   MZ_OK on success (when flushing, or if more input is needed but not available, and/or there's more output to be written but the output buffer is full). */
	/*   MZ_STREAM_END if all input has been consumed and all output bytes have been written. Don't call mz_deflate() on the stream anymore. */
	/*   MZ_STREAM_ERROR if the stream is bogus. */
	/*   MZ_PARAM_ERROR if one of the parameters is invalid. */
	/*   MZ_BUF_ERROR if no forward progress is possible because the input and/or output buffers are empty. (Fill up the input buffer or free up some output space and try again.) */
	mz_deflate :: proc(pStream: mz_streamp, flush: i32) -> i32 ---

	/* mz_deflateEnd() deinitializes a compressor: */
	/* Return values: */
	/*  MZ_OK on success. */
	/*  MZ_STREAM_ERROR if the stream is bogus. */
	mz_deflateEnd :: proc(pStream: mz_streamp) -> i32 ---

	/* mz_deflateBound() returns a (very) conservative upper bound on the amount of data that could be generated by deflate(), assuming flush is set to only MZ_NO_FLUSH or MZ_FINISH. */
	mz_deflateBound :: proc(pStream: mz_streamp, source_len: mz_ulong) -> mz_ulong ---

	/* Single-call compression functions mz_compress() and mz_compress2(): */
	/* Returns MZ_OK on success, or one of the error codes from mz_deflate() on failure. */
	mz_compress  :: proc(pDest: ^u8, pDest_len: ^mz_ulong, pSource: ^u8, source_len: mz_ulong) -> i32 ---
	mz_compress2 :: proc(pDest: ^u8, pDest_len: ^mz_ulong, pSource: ^u8, source_len: mz_ulong, level: i32) -> i32 ---

	/* mz_compressBound() returns a (very) conservative upper bound on the amount of data that could be generated by calling mz_compress(). */
	mz_compressBound :: proc(source_len: mz_ulong) -> mz_ulong ---

	/* Initializes a decompressor. */
	mz_inflateInit :: proc(pStream: mz_streamp) -> i32 ---

	/* mz_inflateInit2() is like mz_inflateInit() with an additional option that controls the window size and whether or not the stream has been wrapped with a zlib header/footer: */
	/* window_bits must be MZ_DEFAULT_WINDOW_BITS (to parse zlib header/footer) or -MZ_DEFAULT_WINDOW_BITS (raw deflate). */
	mz_inflateInit2 :: proc(pStream: mz_streamp, window_bits: i32) -> i32 ---

	/* Quickly resets a compressor without having to reallocate anything. Same as calling mz_inflateEnd() followed by mz_inflateInit()/mz_inflateInit2(). */
	mz_inflateReset :: proc(pStream: mz_streamp) -> i32 ---

	/* Decompresses the input stream to the output, consuming only as much of the input as needed, and writing as much to the output as possible. */
	/* Parameters: */
	/*   pStream is the stream to read from and write to. You must initialize/update the next_in, avail_in, next_out, and avail_out members. */
	/*   flush may be MZ_NO_FLUSH, MZ_SYNC_FLUSH, or MZ_FINISH. */
	/*   On the first call, if flush is MZ_FINISH it's assumed the input and output buffers are both sized large enough to decompress the entire stream in a single call (this is slightly faster). */
	/*   MZ_FINISH implies that there are no more source bytes available beside what's already in the input buffer, and that the output buffer is large enough to hold the rest of the decompressed data. */
	/* Return values: */
	/*   MZ_OK on success. Either more input is needed but not available, and/or there's more output to be written but the output buffer is full. */
	/*   MZ_STREAM_END if all needed input has been consumed and all output bytes have been written. For zlib streams, the adler-32 of the decompressed data has also been verified. */
	/*   MZ_STREAM_ERROR if the stream is bogus. */
	/*   MZ_DATA_ERROR if the deflate stream is invalid. */
	/*   MZ_PARAM_ERROR if one of the parameters is invalid. */
	/*   MZ_BUF_ERROR if no forward progress is possible because the input buffer is empty but the inflater needs more input to continue, or if the output buffer is not large enough. Call mz_inflate() again */
	/*   with more input data, or with more room in the output buffer (except when using single call decompression, described above). */
	mz_inflate :: proc(pStream: mz_streamp, flush: i32) -> i32 ---

	/* Deinitializes a decompressor. */
	mz_inflateEnd :: proc(pStream: mz_streamp) -> i32 ---

	/* Single-call decompression. */
	/* Returns MZ_OK on success, or one of the error codes from mz_inflate() on failure. */
	mz_uncompress  :: proc(pDest: ^u8, pDest_len: ^mz_ulong, pSource: ^u8, source_len: mz_ulong) -> i32 ---
	mz_uncompress2 :: proc(pDest: ^u8, pDest_len: ^mz_ulong, pSource: ^u8, pSource_len: ^mz_ulong) -> i32 ---

	/* Returns a string description of the specified error code, or NULL if the error code is invalid. */
	mz_error :: proc(err: i32) -> cstring ---
}

Byte   :: u8
uInt   :: u32
uLong  :: mz_ulong
Bytef  :: Byte
uIntf  :: uInt
charf  :: i8
intf   :: i32
voidpf :: rawptr
uLongf :: uLong
voidp  :: rawptr
voidpc :: rawptr

Z_NULL                :: 0
Z_NO_FLUSH            :: MZ_NO_FLUSH
Z_PARTIAL_FLUSH       :: MZ_PARTIAL_FLUSH
Z_SYNC_FLUSH          :: MZ_SYNC_FLUSH
Z_FULL_FLUSH          :: MZ_FULL_FLUSH
Z_FINISH              :: MZ_FINISH
Z_BLOCK               :: MZ_BLOCK
Z_OK                  :: MZ_OK
Z_STREAM_END          :: MZ_STREAM_END
Z_NEED_DICT           :: MZ_NEED_DICT
Z_ERRNO               :: MZ_ERRNO
Z_STREAM_ERROR        :: MZ_STREAM_ERROR
Z_DATA_ERROR          :: MZ_DATA_ERROR
Z_MEM_ERROR           :: MZ_MEM_ERROR
Z_BUF_ERROR           :: MZ_BUF_ERROR
Z_VERSION_ERROR       :: MZ_VERSION_ERROR
Z_PARAM_ERROR         :: MZ_PARAM_ERROR
Z_NO_COMPRESSION      :: MZ_NO_COMPRESSION
Z_BEST_SPEED          :: MZ_BEST_SPEED
Z_BEST_COMPRESSION    :: MZ_BEST_COMPRESSION
Z_DEFAULT_COMPRESSION :: MZ_DEFAULT_COMPRESSION
Z_DEFAULT_STRATEGY    :: MZ_DEFAULT_STRATEGY
Z_FILTERED            :: MZ_FILTERED
Z_HUFFMAN_ONLY        :: MZ_HUFFMAN_ONLY
Z_RLE                 :: MZ_RLE
Z_FIXED               :: MZ_FIXED
Z_DEFLATED            :: MZ_DEFLATED
Z_DEFAULT_WINDOW_BITS :: MZ_DEFAULT_WINDOW_BITS

/* See mz_alloc_func */
alloc_func :: proc "c" (opaque: rawptr, items: c.size_t, size: c.size_t) -> rawptr

/* See mz_free_func */
free_func :: proc "c" (opaque: rawptr, address: rawptr)

internal_state       :: mz_internal_state
z_stream             :: mz_stream
MAX_WBITS            :: 15
MAX_MEM_LEVEL        :: 9
ZLIB_VERSION         :: MZ_VERSION
ZLIB_VERNUM          :: MZ_VERNUM
ZLIB_VER_MAJOR       :: MZ_VER_MAJOR
ZLIB_VER_MINOR       :: MZ_VER_MINOR
ZLIB_VER_REVISION    :: MZ_VER_REVISION
ZLIB_VER_SUBREVISION :: MZ_VER_SUBREVISION
zlibVersion          :: mz_version

