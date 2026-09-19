/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */
package kineffi

import "core:c"

/*******************************************************************************
Introduction

zstd, short for Zstandard, is a fast lossless compression algorithm, targeting
real-time compression scenarios at zlib-level and better compression ratios.
The zstd compression library provides in-memory compression and decompression
functions.

The library supports regular compression levels from 1 up to ZSTD_maxCLevel(),
which is currently 22. Levels >= 20, labeled `--ultra`, should be used with
caution, as they require more memory. The library also offers negative
compression levels, which extend the range of speed vs. ratio preferences.
The lower the level, the faster the speed (at the cost of compression).

Compression can be done in:
- a single step (described as Simple API)
- a single step, reusing a context (described as Explicit context)
- unbounded multiple steps (described as Streaming compression)

The compression ratio achievable on small data can be highly improved using
a dictionary. Dictionary compression can be performed in:
- a single step (described as Simple dictionary API)
- a single step, reusing a dictionary (described as Bulk-processing
dictionary API)

Advanced experimental functions can be accessed using
`#define ZSTD_STATIC_LINKING_ONLY` before including zstd.h.

Advanced experimental APIs should never be used with a dynamically-linked
library. They are not "stable"; their definitions or signatures may change in
the future. Only static linking is allowed.
*******************************************************************************/

foreign import lib "../../../vendor/build/vendor/zstd/build/cmake/lib/zstd_static.lib"

/*------   Version   ------*/
ZSTD_VERSION_MAJOR    :: 1
ZSTD_VERSION_MINOR    :: 6
ZSTD_VERSION_RELEASE  :: 0
ZSTD_VERSION_NUMBER  :: (ZSTD_VERSION_MAJOR*100*100+ZSTD_VERSION_MINOR*100+ZSTD_VERSION_RELEASE)

@(default_calling_convention="c")
foreign lib {
	/*! ZSTD_versionNumber() :
	*  Return runtime library version, the value is (MAJOR*100*100 + MINOR*100 + RELEASE). */
	ZSTD_versionNumber :: proc() -> u32 ---
}

@(default_calling_convention="c")
foreign lib {
	/*! ZSTD_versionString() :
	*  Return runtime library version, like "1.4.5". Requires v1.3.0+. */
	ZSTD_versionString :: proc() -> cstring ---
}

ZSTD_CLEVEL_DEFAULT :: 3

/* *************************************
*  Constants
***************************************/

/* All magic numbers are supposed read/written to/from files/memory using little-endian convention */
ZSTD_MAGICNUMBER            :: 0xFD2FB528    /* valid since v0.8.0 */
ZSTD_MAGIC_DICTIONARY       :: 0xEC30A437    /* valid since v0.7.0 */
ZSTD_MAGIC_SKIPPABLE_START  :: 0x184D2A50    /* all 16 values, from 0x184D2A50 to 0x184D2A5F, signal the beginning of a skippable frame */
ZSTD_MAGIC_SKIPPABLE_MASK   :: 0xFFFFFFF0
ZSTD_BLOCKSIZELOG_MAX      :: 17
ZSTD_BLOCKSIZE_MAX         :: (1<<ZSTD_BLOCKSIZELOG_MAX)

@(default_calling_convention="c")
foreign lib {
	/***************************************
	*  Simple Core API
	***************************************/
	/*! ZSTD_compress() :
	*  Compresses `src` content as a single zstd compressed frame into already allocated `dst`.
	*  NOTE: Providing `dstCapacity >= ZSTD_compressBound(srcSize)` guarantees that zstd will have
	*        enough space to successfully compress the data.
	*  @return : compressed size written into `dst` (<= `dstCapacity),
	*            or an error code if it fails (which can be tested using ZSTD_isError()). */
	ZSTD_compress :: proc(dst: rawptr, dstCapacity: c.size_t, src: rawptr, srcSize: c.size_t, compressionLevel: i32) -> c.size_t ---

	/*! ZSTD_decompress() :
	* `compressedSize` : must be the _exact_ size of some number of compressed and/or skippable frames.
	*  Multiple compressed frames can be decompressed at once with this method.
	*  The result will be the concatenation of all decompressed frames, back to back.
	* `dstCapacity` is an upper bound of originalSize to regenerate.
	*  First frame's decompressed size can be extracted using ZSTD_getFrameContentSize().
	*  If maximum upper bound isn't known, prefer using streaming mode to decompress data.
	* @return : the number of bytes decompressed into `dst` (<= `dstCapacity`),
	*           or an errorCode if it fails (which can be tested using ZSTD_isError()). */
	ZSTD_decompress :: proc(dst: rawptr, dstCapacity: c.size_t, src: rawptr, compressedSize: c.size_t) -> c.size_t ---
}

/*======  Decompression helper functions  ======*/

/*! @brief Returns the decompressed content size stored in a ZSTD frame header.
*
*  @since v1.3.0
*
*  @param src Pointer to the beginning of a ZSTD encoded frame.
*  @param srcSize Size of the buffer pointed to by @p src. It must be at least as large as the frame header.
*                 Any value greater than or equal to `ZSTD_frameHeaderSize_max` is sufficient.
*  @return The decompressed size in bytes when the value is available in the frame header.
*  @retval ZSTD_CONTENTSIZE_UNKNOWN The frame does not encode a decompressed size (typical for streaming).
*  @retval ZSTD_CONTENTSIZE_ERROR An error occurred (e.g. invalid magic number, @p srcSize too small).
*
*  @note The return value is not compatible with `ZSTD_isError()`.
*  @note A return value of 0 denotes a valid but empty frame. Skippable frames also report 0.
*  @note The decompressed size field is optional. When it is absent (the function returns @c ZSTD_CONTENTSIZE_UNKNOWN),
*        the caller must rely on streaming decompression or an application-specific upper bound. `ZSTD_decompress()`
*        only requires an upper bound, so applications may enforce their own block limits (for example 16 KB).
*  @note The decompressed size is guaranteed to be present when compression was performed with single-pass APIs such as
*        `ZSTD_compress()`, `ZSTD_compressCCtx()`, `ZSTD_compress_usingDict()`, or `ZSTD_compress_usingCDict()`.
*  @note The decompressed size is a 64-bit value and may exceed the addressable space of the system. Use streaming
*        decompression when the value is too large to materialize in contiguous memory.
*  @warning When processing untrusted input, validate the returned size against the application's limits; attackers may
*           forge an arbitrarily large value.
*  @note This function replaces `ZSTD_getDecompressedSize()`.
*/
ZSTD_CONTENTSIZE_UNKNOWN :: (0-1)
ZSTD_CONTENTSIZE_ERROR   :: (0-2)

@(default_calling_convention="c")
foreign lib {
	ZSTD_getFrameContentSize :: proc(src: rawptr, srcSize: c.size_t) -> u64 ---

	/*! ZSTD_getDecompressedSize() (obsolete):
	*  This function is now obsolete, in favor of ZSTD_getFrameContentSize().
	*  Both functions work the same way, but ZSTD_getDecompressedSize() blends
	*  "empty", "unknown" and "error" results to the same return value (0),
	*  while ZSTD_getFrameContentSize() gives them separate return values.
	* @return : decompressed size of `src` frame content _if known and not empty_, 0 otherwise. */
	ZSTD_getDecompressedSize :: proc(src: rawptr, srcSize: c.size_t) -> u64 ---

	/*! ZSTD_findFrameCompressedSize() : Requires v1.4.0+
	* `src` should point to the start of a ZSTD frame or skippable frame.
	* `srcSize` must be >= first frame size
	* @return : the compressed size of the first frame starting at `src`,
	*           suitable to pass as `srcSize` to `ZSTD_decompress` or similar,
	*           or an error code if input is invalid
	*  Note 1: this method is called _find*() because it's not enough to read the header,
	*          it may have to scan through the frame's content, to reach its end.
	*  Note 2: this method also works with Skippable Frames. In which case,
	*          it returns the size of the complete skippable frame,
	*          which is always equal to its content size + 8 bytes for headers. */
	ZSTD_findFrameCompressedSize :: proc(src: rawptr, srcSize: c.size_t) -> c.size_t ---
	ZSTD_compressBound           :: proc(srcSize: c.size_t /*!< maximum compressed size in worst case single-pass scenario */) -> c.size_t --- /*!< maximum compressed size in worst case single-pass scenario */

	/*======  Error helper functions  ======*/
	/* ZSTD_isError() :
	* Most ZSTD_* functions returning a size_t value can be tested for error,
	* using ZSTD_isError().
	* @return 1 if error, 0 otherwise
	*/
	ZSTD_isError       :: proc(result: c.size_t /*!< tells if a `size_t` function result is an error code */) -> u32 --- /*!< tells if a `size_t` function result is an error code */
	ZSTD_getErrorCode  :: proc(functionResult: c.size_t /* convert a result into an error code, which can be compared to error enum list */) -> i32 --- /* convert a result into an error code, which can be compared to error enum list */
	ZSTD_getErrorName  :: proc(result: c.size_t /*!< provides readable string from a function result */) -> cstring --- /*!< provides readable string from a function result */
	ZSTD_minCLevel     :: proc() -> i32 --- /*!< minimum negative compression level allowed, requires v1.4.0+ */
	ZSTD_maxCLevel     :: proc() -> i32 --- /*!< maximum compression level available */
	ZSTD_defaultCLevel :: proc() -> i32 --- /*!< default compression level, specified by ZSTD_CLEVEL_DEFAULT, requires v1.5.0+ */
}

/***************************************
*  Explicit context
***************************************/
/*= Compression context
*  When compressing many times,
*  it is recommended to allocate a compression context just once,
*  and reuse it for each successive compression operation.
*  This will make the workload easier for system's memory.
*  Note : re-using context is just a speed / resource optimization.
*         It doesn't change the compression ratio, which remains identical.
*  Note 2: For parallel execution in multi-threaded environments,
*         use one different context per thread .
*/
ZSTD_CCtx   :: ZSTD_CCtx_s
ZSTD_CCtx_s :: struct {}

@(default_calling_convention="c")
foreign lib {
	ZSTD_createCCtx :: proc() -> ^ZSTD_CCtx ---
	ZSTD_freeCCtx   :: proc(cctx: ^ZSTD_CCtx /* compatible with NULL pointer */) -> c.size_t --- /* compatible with NULL pointer */

	/*! ZSTD_compressCCtx() :
	*  Same as ZSTD_compress(), using an explicit ZSTD_CCtx.
	*  Important : in order to mirror `ZSTD_compress()` behavior,
	*  this function compresses at the requested compression level,
	*  __ignoring any other advanced parameter__ .
	*  If any advanced parameter was set using the advanced API,
	*  they will all be reset. Only @compressionLevel remains.
	*/
	ZSTD_compressCCtx :: proc(cctx: ^ZSTD_CCtx, dst: rawptr, dstCapacity: c.size_t, src: rawptr, srcSize: c.size_t, compressionLevel: i32) -> c.size_t ---
}

/*= Decompression context
*  When decompressing many times,
*  it is recommended to allocate a context only once,
*  and reuse it for each successive compression operation.
*  This will make workload friendlier for system's memory.
*  Use one context per thread for parallel execution. */
ZSTD_DCtx   :: ZSTD_DCtx_s
ZSTD_DCtx_s :: struct {}

@(default_calling_convention="c")
foreign lib {
	ZSTD_createDCtx :: proc() -> ^ZSTD_DCtx ---
	ZSTD_freeDCtx   :: proc(dctx: ^ZSTD_DCtx /* accept NULL pointer */) -> c.size_t --- /* accept NULL pointer */

	/*! ZSTD_decompressDCtx() :
	*  Same as ZSTD_decompress(),
	*  requires an allocated ZSTD_DCtx.
	*  Compatible with sticky parameters (see below).
	*/
	ZSTD_decompressDCtx :: proc(dctx: ^ZSTD_DCtx, dst: rawptr, dstCapacity: c.size_t, src: rawptr, srcSize: c.size_t) -> c.size_t ---
}

/* Compression strategies, listed from fastest to strongest */
ZSTD_strategy :: enum i32 {
	/*********************************************
	*  Advanced compression API (Requires v1.4.0+)
	**********************************************/
	
	/* API design :
	*   Parameters are pushed one by one into an existing context,
	*   using ZSTD_CCtx_set*() functions.
	*   Pushed parameters are sticky : they are valid for next compressed frame, and any subsequent frame.
	*   "sticky" parameters are applicable to `ZSTD_compress2()` and `ZSTD_compressStream*()` !
	*   __They do not apply to one-shot variants such as ZSTD_compressCCtx()__ .
	*
	*   It's possible to reset all parameters to "default" using ZSTD_CCtx_reset().
	*
	*   This API supersedes all other "advanced" API entry points in the experimental section.
	*   In the future, we expect to remove API entry points from experimental which are redundant with this API.
	*/
	
	
	/* Compression strategies, listed from fastest to strongest */
	fast     = 1,
	dfast    = 2,
	greedy   = 3,
	lazy     = 4,
	lazy2    = 5,
	btlazy2  = 6,
	btopt    = 7,
	btultra  = 8,
	btultra2 = 9,
}

ZSTD_cParameter :: enum i32 {
	/* compression parameters
	* Note: When compressing with a ZSTD_CDict these parameters are superseded
	* by the parameters used to construct the ZSTD_CDict.
	* See ZSTD_CCtx_refCDict() for more info (superseded-by-cdict). */
	compressionLevel           = 100, /* Set compression parameters according to pre-defined cLevel table.
                              * Note that exact compression parameters are dynamically determined,
                              * depending on both compression level and srcSize (when known).
                              * Default level is ZSTD_CLEVEL_DEFAULT==3.
                              * Special: value 0 means default, which is controlled by ZSTD_CLEVEL_DEFAULT.
                              * Note 1 : it's possible to pass a negative compression level.
                              * Note 2 : setting a level does not automatically set all other compression parameters
                              *   to default. Setting this will however eventually dynamically impact the compression
                              *   parameters which have not been manually set. The manually set
                              *   ones will 'stick'. */

	/* Advanced compression parameters :
	* It's possible to pin down compression parameters to some specific values.
	* In which case, these values are no longer dynamically selected by the compressor */
	windowLog                  = 101, /* Maximum allowed back-reference distance, expressed as power of 2.
                              * This will set a memory budget for streaming decompression,
                              * with larger values requiring more memory
                              * and typically compressing more.
                              * Must be clamped between ZSTD_WINDOWLOG_MIN and ZSTD_WINDOWLOG_MAX.
                              * Special: value 0 means "use default windowLog".
                              * Note: Using a windowLog greater than ZSTD_WINDOWLOG_LIMIT_DEFAULT
                              *       requires explicitly allowing such size at streaming decompression stage. */
	hashLog                    = 102, /* Size of the initial probe table, as a power of 2.
                              * Resulting memory usage is (1 << (hashLog+2)).
                              * Must be clamped between ZSTD_HASHLOG_MIN and ZSTD_HASHLOG_MAX.
                              * Larger tables improve compression ratio of strategies <= dFast,
                              * and improve speed of strategies > dFast.
                              * Special: value 0 means "use default hashLog". */
	chainLog                   = 103, /* Size of the multi-probe search table, as a power of 2.
                              * Resulting memory usage is (1 << (chainLog+2)).
                              * Must be clamped between ZSTD_CHAINLOG_MIN and ZSTD_CHAINLOG_MAX.
                              * Larger tables result in better and slower compression.
                              * This parameter is useless for "fast" strategy.
                              * It's still useful when using "dfast" strategy,
                              * in which case it defines a secondary probe table.
                              * Special: value 0 means "use default chainLog". */
	searchLog                  = 104, /* Number of search attempts, as a power of 2.
                              * More attempts result in better and slower compression.
                              * This parameter is useless for "fast" and "dFast" strategies.
                              * Special: value 0 means "use default searchLog". */
	minMatch                   = 105, /* Minimum size of searched matches.
                              * Note that Zstandard can still find matches of smaller size,
                              * it just tweaks its search algorithm to look for this size and larger.
                              * Larger values increase compression and decompression speed, but decrease ratio.
                              * Must be clamped between ZSTD_MINMATCH_MIN and ZSTD_MINMATCH_MAX.
                              * Note that currently, for all strategies < btopt, effective minimum is 4.
                              *                    , for all strategies > fast, effective maximum is 6.
                              * Special: value 0 means "use default minMatchLength". */
	targetLength               = 106, /* Impact of this field depends on strategy.
                              * For strategies btopt, btultra & btultra2:
                              *     Length of Match considered "good enough" to stop search.
                              *     Larger values make compression stronger, and slower.
                              * For strategy fast:
                              *     Distance between match sampling.
                              *     Larger values make compression faster, and weaker.
                              * Special: value 0 means "use default targetLength". */
	strategy                   = 107, /* See ZSTD_strategy enum definition.
                              * The higher the value of selected strategy, the more complex it is,
                              * resulting in stronger and slower compression.
                              * Special: value 0 means "use default strategy". */
	targetCBlockSize           = 130, /* v1.5.6+
                                  * Attempts to fit compressed block size into approximately targetCBlockSize.
                                  * Bound by ZSTD_TARGETCBLOCKSIZE_MIN and ZSTD_TARGETCBLOCKSIZE_MAX.
                                  * Note that it's not a guarantee, just a convergence target (default:0).
                                  * No target when targetCBlockSize == 0.
                                  * This is helpful in low bandwidth streaming environments to improve end-to-end latency,
                                  * when a client can make use of partial documents (a prominent example being Chrome).
                                  * Note: this parameter is stable since v1.5.6.
                                  * It was present as an experimental parameter in earlier versions,
                                  * but it's not recommended using it with earlier library versions
                                  * due to massive performance regressions.
                                  */

	/* LDM mode parameters */
	enableLongDistanceMatching = 160, /* Enable long distance matching.
                                     * This parameter is designed to improve compression ratio
                                     * for large inputs, by finding large matches at long distance.
                                     * It increases memory usage and window size.
                                     * Note: enabling this parameter increases default ZSTD_c_windowLog to 128 MB
                                     * except when expressly set to a different value.
                                     * Note: will be enabled by default if ZSTD_c_windowLog >= 128 MB and
                                     * compression strategy >= ZSTD_btopt (== compression level 16+) */
	ldmHashLog                 = 161, /* Size of the table for long distance matching, as a power of 2.
                              * Larger values increase memory usage and compression ratio,
                              * but decrease compression speed.
                              * Must be clamped between ZSTD_HASHLOG_MIN and ZSTD_HASHLOG_MAX
                              * default: windowlog - 7.
                              * Special: value 0 means "automatically determine hashlog". */
	ldmMinMatch                = 162, /* Minimum match size for long distance matcher.
                              * Larger/too small values usually decrease compression ratio.
                              * Must be clamped between ZSTD_LDM_MINMATCH_MIN and ZSTD_LDM_MINMATCH_MAX.
                              * Special: value 0 means "use default value" (default: 64). */
	ldmBucketSizeLog           = 163, /* Log size of each bucket in the LDM hash table for collision resolution.
                              * Larger values improve collision resolution but decrease compression speed.
                              * The maximum value is ZSTD_LDM_BUCKETSIZELOG_MAX.
                              * Special: value 0 means "use default value" (default: 3). */
	ldmHashRateLog             = 164, /* Frequency of inserting/looking up entries into the LDM hash table.
                              * Must be clamped between 0 and (ZSTD_WINDOWLOG_MAX - ZSTD_HASHLOG_MIN).
                              * Default is MAX(0, (windowLog - ldmHashLog)), optimizing hash table usage.
                              * Larger values improve compression speed.
                              * Deviating far from default value will likely result in a compression ratio decrease.
                              * Special: value 0 means "automatically determine hashRateLog". */

	/* frame parameters */
	contentSizeFlag            = 200, /* Content size will be written into frame header _whenever known_ (default:1)
                              * Content size must be known at the beginning of compression.
                              * This is automatically the case when using ZSTD_compress2(),
                              * For streaming scenarios, content size must be provided with ZSTD_CCtx_setPledgedSrcSize() */
	checksumFlag               = 201, /* A 32-bits checksum of content is written at end of frame (default:0) */
	dictIDFlag                 = 202, /* When applicable, dictionary's ID is written into frame header (default:1) */

	/* multi-threading parameters */
	/* These parameters are only active if multi-threading is enabled (compiled with build macro ZSTD_MULTITHREAD).
	* Otherwise, trying to set any other value than default (0) will be a no-op and return an error.
	* In a situation where it's unknown if the linked library supports multi-threading or not,
	* setting ZSTD_c_nbWorkers to any value >= 1 and consulting the return value provides a quick way to check this property.
	*/
	nbWorkers                  = 400, /* Select how many threads will be spawned to compress in parallel.
                              * When nbWorkers >= 1, triggers asynchronous mode when invoking ZSTD_compressStream*() :
                              * ZSTD_compressStream*() consumes input and flush output if possible, but immediately gives back control to caller,
                              * while compression is performed in parallel, within worker thread(s).
                              * (note : a strong exception to this rule is when first invocation of ZSTD_compressStream2() sets ZSTD_e_end :
                              *  in which case, ZSTD_compressStream2() delegates to ZSTD_compress2(), which is always a blocking call).
                              * More workers improve speed, but also increase memory usage.
                              * Default value is `0`, aka "single-threaded mode" : no worker is spawned,
                              * compression is performed inside Caller's thread, and all invocations are blocking */
	jobSize                    = 401, /* Size of a compression job. This value is enforced only when nbWorkers >= 1.
                              * Each compression job is completed in parallel, so this value can indirectly impact the nb of active threads.
                              * 0 means default, which is dynamically determined based on compression parameters.
                              * Job size must be a minimum of overlap size, or ZSTDMT_JOBSIZE_MIN (= 512 KB), whichever is largest.
                              * The minimum size is automatically and transparently enforced. */
	overlapLog                 = 402, /* Control the overlap size, as a fraction of window size.
                              * The overlap size is an amount of data reloaded from previous job at the beginning of a new job.
                              * It helps preserve compression ratio, while each job is compressed in parallel.
                              * This value is enforced only when nbWorkers >= 1.
                              * Larger values increase compression ratio, but decrease speed.
                              * Possible values range from 0 to 9 :
                              * - 0 means "default" : value will be determined by the library, depending on strategy
                              * - 1 means "no overlap"
                              * - 9 means "full overlap", using a full window size.
                              * Each intermediate rank increases/decreases load size by a factor 2 :
                              * 9: full window;  8: w/2;  7: w/4;  6: w/8;  5:w/16;  4: w/32;  3:w/64;  2:w/128;  1:no overlap;  0:default
                              * default value varies between 6 and 9, depending on strategy */

	/* note : additional experimental parameters are also available
	* within the experimental section of the API.
	* At the time of this writing, they include :
	* ZSTD_c_rsyncable
	* ZSTD_c_format
	* ZSTD_c_forceMaxWindow
	* ZSTD_c_forceAttachDict
	* ZSTD_c_literalCompressionMode
	* ZSTD_c_srcSizeHint
	* ZSTD_c_enableDedicatedDictSearch
	* ZSTD_c_stableInBuffer
	* ZSTD_c_stableOutBuffer
	* ZSTD_c_blockDelimiters
	* ZSTD_c_validateSequences
	* ZSTD_c_blockSplitterLevel
	* ZSTD_c_splitAfterSequences
	* ZSTD_c_useRowMatchFinder
	* ZSTD_c_prefetchCDictTables
	* ZSTD_c_enableSeqProducerFallback
	* ZSTD_c_maxBlockSize
	* Because they are not stable, it's necessary to define ZSTD_STATIC_LINKING_ONLY to access them.
	* note : never ever use experimentalParam? names directly;
	*        also, the enums values themselves are unstable and can still change.
	*/
	experimentalParam1         = 500,
	experimentalParam2         = 10,
	experimentalParam3         = 1000,
	experimentalParam4         = 1001,
	experimentalParam5         = 1002,

	/* was ZSTD_c_experimentalParam6=1003; is now ZSTD_c_targetCBlockSize */
	experimentalParam7         = 1004,
	experimentalParam8         = 1005,
	experimentalParam9         = 1006,
	experimentalParam10        = 1007,
	experimentalParam11        = 1008,
	experimentalParam12        = 1009,
	experimentalParam13        = 1010,
	experimentalParam14        = 1011,
	experimentalParam15        = 1012,
	experimentalParam16        = 1013,
	experimentalParam17        = 1014,
	experimentalParam18        = 1015,
	experimentalParam19        = 1016,
	experimentalParam20        = 1017,
}

ZSTD_bounds :: struct {
	error:      c.size_t,
	lowerBound: i32,
	upperBound: i32,
}

@(default_calling_convention="c")
foreign lib {
	/*! ZSTD_cParam_getBounds() :
	*  All parameters must belong to an interval with lower and upper bounds,
	*  otherwise they will either trigger an error or be automatically clamped.
	* @return : a structure, ZSTD_bounds, which contains
	*         - an error status field, which must be tested using ZSTD_isError()
	*         - lower and upper bounds, both inclusive
	*/
	ZSTD_cParam_getBounds :: proc(cParam: ZSTD_cParameter) -> ZSTD_bounds ---

	/*! ZSTD_CCtx_setParameter() :
	*  Set one compression parameter, selected by enum ZSTD_cParameter.
	*  All parameters have valid bounds. Bounds can be queried using ZSTD_cParam_getBounds().
	*  Providing a value beyond bound will either clamp it, or trigger an error (depending on parameter).
	*  Setting a parameter is generally only possible during frame initialization (before starting compression).
	*  Exception : when using multi-threading mode (nbWorkers >= 1),
	*              the following parameters can be updated _during_ compression (within same frame):
	*              => compressionLevel, hashLog, chainLog, searchLog, minMatch, targetLength and strategy.
	*              new parameters will be active for next job only (after a flush()).
	* @return : an error code (which can be tested using ZSTD_isError()).
	*/
	ZSTD_CCtx_setParameter :: proc(cctx: ^ZSTD_CCtx, param: ZSTD_cParameter, value: i32) -> c.size_t ---

	/*! ZSTD_CCtx_setPledgedSrcSize() :
	*  Total input data size to be compressed as a single frame.
	*  Value will be written in frame header, unless if explicitly forbidden using ZSTD_c_contentSizeFlag.
	*  This value will also be controlled at end of frame, and trigger an error if not respected.
	* @result : 0, or an error code (which can be tested with ZSTD_isError()).
	*  Note 1 : pledgedSrcSize==0 actually means zero, aka an empty frame.
	*           In order to mean "unknown content size", pass constant ZSTD_CONTENTSIZE_UNKNOWN.
	*           ZSTD_CONTENTSIZE_UNKNOWN is default value for any new frame.
	*  Note 2 : pledgedSrcSize is only valid once, for the next frame.
	*           It's discarded at the end of the frame, and replaced by ZSTD_CONTENTSIZE_UNKNOWN.
	*  Note 3 : Whenever all input data is provided and consumed in a single round,
	*           for example with ZSTD_compress2(),
	*           or invoking immediately ZSTD_compressStream2(,,,ZSTD_e_end),
	*           this value is automatically overridden by srcSize instead.
	*/
	ZSTD_CCtx_setPledgedSrcSize :: proc(cctx: ^ZSTD_CCtx, pledgedSrcSize: u64) -> c.size_t ---
}

ZSTD_ResetDirective :: enum i32 {
	session_only           = 1,
	parameters             = 2,
	session_and_parameters = 3,
}

@(default_calling_convention="c")
foreign lib {
	/*! ZSTD_CCtx_reset() :
	*  There are 2 different things that can be reset, independently or jointly :
	*  - The session : will stop compressing current frame, and make CCtx ready to start a new one.
	*                  Useful after an error, or to interrupt any ongoing compression.
	*                  Any internal data not yet flushed is cancelled.
	*                  Compression parameters and dictionary remain unchanged.
	*                  They will be used to compress next frame.
	*                  Resetting session never fails.
	*  - The parameters : changes all parameters back to "default".
	*                  This also removes any reference to any dictionary or external sequence producer.
	*                  Parameters can only be changed between 2 sessions (i.e. no compression is currently ongoing)
	*                  otherwise the reset fails, and function returns an error value (which can be tested using ZSTD_isError())
	*  - Both : similar to resetting the session, followed by resetting parameters.
	*/
	ZSTD_CCtx_reset :: proc(cctx: ^ZSTD_CCtx, reset: ZSTD_ResetDirective) -> c.size_t ---

	/*! ZSTD_compress2() :
	*  Behave the same as ZSTD_compressCCtx(), but compression parameters are set using the advanced API.
	*  (note that this entry point doesn't even expose a compression level parameter).
	*  ZSTD_compress2() always starts a new frame.
	*  Should cctx hold data from a previously unfinished frame, everything about it is forgotten.
	*  - Compression parameters are pushed into CCtx before starting compression, using ZSTD_CCtx_set*()
	*  - The function is always blocking, returns when compression is completed.
	*  NOTE: Providing `dstCapacity >= ZSTD_compressBound(srcSize)` guarantees that zstd will have
	*        enough space to successfully compress the data, though it is possible it fails for other reasons.
	* @return : compressed size written into `dst` (<= `dstCapacity),
	*           or an error code if it fails (which can be tested using ZSTD_isError()).
	*/
	ZSTD_compress2 :: proc(cctx: ^ZSTD_CCtx, dst: rawptr, dstCapacity: c.size_t, src: rawptr, srcSize: c.size_t) -> c.size_t ---
}

/* The advanced API pushes parameters one by one into an existing DCtx context.
* Parameters are sticky, and remain valid for all following frames
* using the same DCtx context.
* It's possible to reset parameters to default values using ZSTD_DCtx_reset().
* Note : This API is compatible with existing ZSTD_decompressDCtx() and ZSTD_decompressStream().
*        Therefore, no new decompression function is necessary.
*/
ZSTD_dParameter :: enum i32 {
	windowLogMax       = 100, /* Select a size limit (in power of 2) beyond which
                              * the streaming API will refuse to allocate memory buffer
                              * in order to protect the host from unreasonable memory requirements.
                              * This parameter is only useful in streaming mode, since no internal buffer is allocated in single-pass mode.
                              * By default, a decompression context accepts window sizes <= (1 << ZSTD_WINDOWLOG_LIMIT_DEFAULT).
                              * Special: value 0 means "use default maximum windowLog". */

	/* note : additional experimental parameters are also available
	* within the experimental section of the API.
	* At the time of this writing, they include :
	* ZSTD_d_format
	* ZSTD_d_stableOutBuffer
	* ZSTD_d_forceIgnoreChecksum
	* ZSTD_d_refMultipleDDicts
	* ZSTD_d_disableHuffmanAssembly
	* ZSTD_d_maxBlockSize
	* Because they are not stable, it's necessary to define ZSTD_STATIC_LINKING_ONLY to access them.
	* note : never ever use experimentalParam? names directly
	*/
	experimentalParam1 = 1000,
	experimentalParam2 = 1001,
	experimentalParam3 = 1002,
	experimentalParam4 = 1003,
	experimentalParam5 = 1004,
	experimentalParam6 = 1005,
}

@(default_calling_convention="c")
foreign lib {
	/*! ZSTD_dParam_getBounds() :
	*  All parameters must belong to an interval with lower and upper bounds,
	*  otherwise they will either trigger an error or be automatically clamped.
	* @return : a structure, ZSTD_bounds, which contains
	*         - an error status field, which must be tested using ZSTD_isError()
	*         - both lower and upper bounds, inclusive
	*/
	ZSTD_dParam_getBounds :: proc(dParam: ZSTD_dParameter) -> ZSTD_bounds ---

	/*! ZSTD_DCtx_setParameter() :
	*  Set one compression parameter, selected by enum ZSTD_dParameter.
	*  All parameters have valid bounds. Bounds can be queried using ZSTD_dParam_getBounds().
	*  Providing a value beyond bound will either clamp it, or trigger an error (depending on parameter).
	*  Setting a parameter is only possible during frame initialization (before starting decompression).
	* @return : 0, or an error code (which can be tested using ZSTD_isError()).
	*/
	ZSTD_DCtx_setParameter :: proc(dctx: ^ZSTD_DCtx, param: ZSTD_dParameter, value: i32) -> c.size_t ---

	/*! ZSTD_DCtx_reset() :
	*  Return a DCtx to clean state.
	*  Session and parameters can be reset jointly or separately.
	*  Parameters can only be reset when no active frame is being decompressed.
	* @return : 0, or an error code, which can be tested with ZSTD_isError()
	*/
	ZSTD_DCtx_reset :: proc(dctx: ^ZSTD_DCtx, reset: ZSTD_ResetDirective) -> c.size_t ---
}

/****************************
*  Streaming
****************************/
ZSTD_inBuffer_s :: struct {
	src:  rawptr,   /**< start of input buffer */
	size: c.size_t, /**< size of input buffer */
	pos:  c.size_t, /**< position where reading stopped. Will be updated. Necessarily 0 <= pos <= size */
}

/****************************
*  Streaming
****************************/
ZSTD_inBuffer :: ZSTD_inBuffer_s

ZSTD_outBuffer_s :: struct {
	dst:  rawptr,   /**< start of output buffer */
	size: c.size_t, /**< size of output buffer */
	pos:  c.size_t, /**< position where writing stopped. Will be updated. Necessarily 0 <= pos <= size */
}

ZSTD_outBuffer :: ZSTD_outBuffer_s

/*-***********************************************************************
*  Streaming compression - HowTo
*
*  A ZSTD_CStream object is required to track streaming operation.
*  Use ZSTD_createCStream() and ZSTD_freeCStream() to create/release resources.
*  ZSTD_CStream objects can be reused multiple times on consecutive compression operations.
*  It is recommended to reuse ZSTD_CStream since it will play nicer with system's memory, by re-using already allocated memory.
*
*  For parallel execution, use one separate ZSTD_CStream per thread.
*
*  note : since v1.3.0, ZSTD_CStream and ZSTD_CCtx are the same thing.
*
*  Parameters are sticky : when starting a new compression on the same context,
*  it will reuse the same sticky parameters as previous compression session.
*  When in doubt, it's recommended to fully initialize the context before usage.
*  Use ZSTD_CCtx_reset() to reset the context and ZSTD_CCtx_setParameter(),
*  ZSTD_CCtx_setPledgedSrcSize(), or ZSTD_CCtx_loadDictionary() and friends to
*  set more specific parameters, the pledged source size, or load a dictionary.
*
*  Use ZSTD_compressStream2() with ZSTD_e_continue as many times as necessary to
*  consume input stream. The function will automatically update both `pos`
*  fields within `input` and `output`.
*  Note that the function may not consume the entire input, for example, because
*  the output buffer is already full, in which case `input.pos < input.size`.
*  The caller must check if input has been entirely consumed.
*  If not, the caller must make some room to receive more compressed data,
*  and then present again remaining input data.
*  note: ZSTD_e_continue is guaranteed to make some forward progress when called,
*        but doesn't guarantee maximal forward progress. This is especially relevant
*        when compressing with multiple threads. The call won't block if it can
*        consume some input, but if it can't it will wait for some, but not all,
*        output to be flushed.
* @return : provides a minimum amount of data remaining to be flushed from internal buffers
*           or an error code, which can be tested using ZSTD_isError().
*
*  At any moment, it's possible to flush whatever data might remain stuck within internal buffer,
*  using ZSTD_compressStream2() with ZSTD_e_flush. `output->pos` will be updated.
*  Note that, if `output->size` is too small, a single invocation with ZSTD_e_flush might not be enough (return code > 0).
*  In which case, make some room to receive more compressed data, and call again ZSTD_compressStream2() with ZSTD_e_flush.
*  You must continue calling ZSTD_compressStream2() with ZSTD_e_flush until it returns 0, at which point you can change the
*  operation.
*  note: ZSTD_e_flush will flush as much output as possible, meaning when compressing with multiple threads, it will
*        block until the flush is complete or the output buffer is full.
*  @return : 0 if internal buffers are entirely flushed,
*            >0 if some data still present within internal buffer (the value is minimal estimation of remaining size),
*            or an error code, which can be tested using ZSTD_isError().
*
*  Calling ZSTD_compressStream2() with ZSTD_e_end instructs to finish a frame.
*  It will perform a flush and write frame epilogue.
*  The epilogue is required for decoders to consider a frame completed.
*  flush operation is the same, and follows same rules as calling ZSTD_compressStream2() with ZSTD_e_flush.
*  You must continue calling ZSTD_compressStream2() with ZSTD_e_end until it returns 0, at which point you are free to
*  start a new frame.
*  note: ZSTD_e_end will flush as much output as possible, meaning when compressing with multiple threads, it will
*        block until the flush is complete or the output buffer is full.
*  @return : 0 if frame fully completed and fully flushed,
*            >0 if some data still present within internal buffer (the value is minimal estimation of remaining size),
*            or an error code, which can be tested using ZSTD_isError().
*
* *******************************************************************/
ZSTD_CStream :: ZSTD_CCtx /**< CCtx and CStream are now effectively same object (>= v1.3.0) */

@(default_calling_convention="c")
foreign lib {
	/*===== ZSTD_CStream management functions =====*/
	ZSTD_createCStream :: proc() -> ^ZSTD_CStream ---
	ZSTD_freeCStream   :: proc(zcs: ^ZSTD_CStream /* accept NULL pointer */) -> c.size_t --- /* accept NULL pointer */
}

/*===== Streaming compression functions =====*/
ZSTD_EndDirective :: enum i32 {
	e_continue = 0,
	e_flush    = 1,
	e_end      = 2,
}

@(default_calling_convention="c")
foreign lib {
	/*! ZSTD_compressStream2() : Requires v1.4.0+
	*  Behaves about the same as ZSTD_compressStream, with additional control on end directive.
	*  - Compression parameters are pushed into CCtx before starting compression, using ZSTD_CCtx_set*()
	*  - Compression parameters cannot be changed once compression is started (save a list of exceptions in multi-threading mode)
	*  - output->pos must be <= dstCapacity, input->pos must be <= srcSize
	*  - output->pos and input->pos will be updated. They are guaranteed to remain below their respective limit.
	*  - endOp must be a valid directive
	*  - When nbWorkers==0 (default), function is blocking : it completes its job before returning to caller.
	*  - When nbWorkers>=1, function is non-blocking : it copies a portion of input, distributes jobs to internal worker threads, flush to output whatever is available,
	*                                                  and then immediately returns, just indicating that there is some data remaining to be flushed.
	*                                                  The function nonetheless guarantees forward progress : it will return only after it reads or write at least 1+ byte.
	*  - Exception : if the first call requests a ZSTD_e_end directive and provides enough dstCapacity, the function delegates to ZSTD_compress2() which is always blocking.
	*  - @return provides a minimum amount of data remaining to be flushed from internal buffers
	*            or an error code, which can be tested using ZSTD_isError().
	*            if @return != 0, flush is not fully completed, there is still some data left within internal buffers.
	*            This is useful for ZSTD_e_flush, since in this case more flushes are necessary to empty all buffers.
	*            For ZSTD_e_end, @return == 0 when internal buffers are fully flushed and frame is completed.
	*  - after a ZSTD_e_end directive, if internal buffer is not fully flushed (@return != 0),
	*            only ZSTD_e_end or ZSTD_e_flush operations are allowed.
	*            Before starting a new compression job, or changing compression parameters,
	*            it is required to fully flush internal buffers.
	*  - note: if an operation ends with an error, it may leave @cctx in an undefined state.
	*          Therefore, it's UB to invoke ZSTD_compressStream2() of ZSTD_compressStream() on such a state.
	*          In order to be re-employed after an error, a state must be reset,
	*          which can be done explicitly (ZSTD_CCtx_reset()),
	*          or is sometimes implied by methods starting a new compression job (ZSTD_initCStream(), ZSTD_compressCCtx())
	*/
	ZSTD_compressStream2 :: proc(cctx: ^ZSTD_CCtx, output: ^ZSTD_outBuffer, input: ^ZSTD_inBuffer, endOp: ZSTD_EndDirective) -> c.size_t ---

	/* These buffer sizes are softly recommended.
	* They are not required : ZSTD_compressStream*() happily accepts any buffer size, for both input and output.
	* Respecting the recommended size just makes it a bit easier for ZSTD_compressStream*(),
	* reducing the amount of memory shuffling and buffering, resulting in minor performance savings.
	*
	* However, note that these recommendations are from the perspective of a C caller program.
	* If the streaming interface is invoked from some other language,
	* especially managed ones such as Java or Go, through a foreign function interface such as jni or cgo,
	* a major performance rule is to reduce crossing such interface to an absolute minimum.
	* It's not rare that performance ends being spent more into the interface, rather than compression itself.
	* In which cases, prefer using large buffers, as large as practical,
	* for both input and output, to reduce the nb of roundtrips.
	*/
	ZSTD_CStreamInSize  :: proc() -> c.size_t --- /**< recommended size for input buffer */
	ZSTD_CStreamOutSize :: proc() -> c.size_t --- /**< recommended size for output buffer. Guarantee to successfully flush at least one complete compressed block. */

	/*!
	* Equivalent to:
	*
	*     ZSTD_CCtx_reset(zcs, ZSTD_reset_session_only);
	*     ZSTD_CCtx_refCDict(zcs, NULL); // clear the dictionary (if any)
	*     ZSTD_CCtx_setParameter(zcs, ZSTD_c_compressionLevel, compressionLevel);
	*
	* Note that ZSTD_initCStream() clears any previously set dictionary. Use the new API
	* to compress with a dictionary.
	*/
	ZSTD_initCStream :: proc(zcs: ^ZSTD_CStream, compressionLevel: i32) -> c.size_t ---

	/*!
	* Alternative for ZSTD_compressStream2(zcs, output, input, ZSTD_e_continue).
	* NOTE: The return value is different. ZSTD_compressStream() returns a hint for
	* the next read size (if non-zero and not an error). ZSTD_compressStream2()
	* returns the minimum nb of bytes left to flush (if non-zero and not an error).
	*/
	ZSTD_compressStream :: proc(zcs: ^ZSTD_CStream, output: ^ZSTD_outBuffer, input: ^ZSTD_inBuffer) -> c.size_t ---

	/*! Equivalent to ZSTD_compressStream2(zcs, output, &emptyInput, ZSTD_e_flush). */
	ZSTD_flushStream :: proc(zcs: ^ZSTD_CStream, output: ^ZSTD_outBuffer) -> c.size_t ---

	/*! Equivalent to ZSTD_compressStream2(zcs, output, &emptyInput, ZSTD_e_end). */
	ZSTD_endStream :: proc(zcs: ^ZSTD_CStream, output: ^ZSTD_outBuffer) -> c.size_t ---
}

/*-***************************************************************************
*  Streaming decompression - HowTo
*
*  A ZSTD_DStream object is required to track streaming operations.
*  Use ZSTD_createDStream() and ZSTD_freeDStream() to create/release resources.
*  ZSTD_DStream objects can be re-employed multiple times.
*
*  Use ZSTD_initDStream() to start a new decompression operation.
* @return : recommended first input size
*  Alternatively, use advanced API to set specific properties.
*
*  Use ZSTD_decompressStream() repetitively to consume your input.
*  The function will update both `pos` fields.
*  If `input.pos < input.size`, some input has not been consumed.
*  It's up to the caller to present again remaining data.
*
*  The function tries to flush all data decoded immediately, respecting output buffer size.
*  If `output.pos < output.size`, decoder has flushed everything it could.
*
*  However, when `output.pos == output.size`, it's more difficult to know.
*  If @return > 0, the frame is not complete, meaning
*  either there is still some data left to flush within internal buffers,
*  or there is more input to read to complete the frame (or both).
*  In which case, call ZSTD_decompressStream() again to flush whatever remains in the buffer.
*  Note : with no additional input provided, amount of data flushed is necessarily <= ZSTD_BLOCKSIZE_MAX.
* @return : 0 when a frame is completely decoded and fully flushed,
*        or an error code, which can be tested using ZSTD_isError(),
*        or any other value > 0, which means there is still some decoding or flushing to do to complete current frame :
*                                the return value is a suggested next input size (just a hint for better latency)
*                                that will never request more than the remaining content of the compressed frame.
* *******************************************************************************/
ZSTD_DStream :: ZSTD_DCtx /**< DCtx and DStream are now effectively same object (>= v1.3.0) */

@(default_calling_convention="c")
foreign lib {
	/*===== ZSTD_DStream management functions =====*/
	ZSTD_createDStream :: proc() -> ^ZSTD_DStream ---
	ZSTD_freeDStream   :: proc(zds: ^ZSTD_DStream /* accept NULL pointer */) -> c.size_t --- /* accept NULL pointer */

	/*! ZSTD_initDStream() :
	* Initialize/reset DStream state for new decompression operation.
	* Call before new decompression operation using same DStream.
	*
	* Note : This function is redundant with the advanced API and equivalent to:
	*     ZSTD_DCtx_reset(zds, ZSTD_reset_session_only);
	*     ZSTD_DCtx_refDDict(zds, NULL);
	*/
	ZSTD_initDStream :: proc(zds: ^ZSTD_DStream) -> c.size_t ---

	/*! ZSTD_decompressStream() :
	* Streaming decompression function.
	* Call repetitively to consume full input updating it as necessary.
	* Function will update both input and output `pos` fields exposing current state via these fields:
	* - `input.pos < input.size`, some input remaining and caller should provide remaining input
	*   on the next call.
	* - `output.pos < output.size`, decoder flushed internal output buffer.
	* - `output.pos == output.size`, unflushed data potentially present in the internal buffers,
	*   check ZSTD_decompressStream() @return value,
	*   if > 0, invoke it again to flush remaining data to output.
	* Note : with no additional input, amount of data flushed <= ZSTD_BLOCKSIZE_MAX.
	*
	* @return : 0 when a frame is completely decoded and fully flushed,
	*           or an error code, which can be tested using ZSTD_isError(),
	*           or any other value > 0, which means there is some decoding or flushing to do to complete current frame.
	*
	* Note: when an operation returns with an error code, the @zds state may be left in undefined state.
	*       It's UB to invoke `ZSTD_decompressStream()` on such a state.
	*       In order to re-use such a state, it must be first reset,
	*       which can be done explicitly (`ZSTD_DCtx_reset()`),
	*       or is implied for operations starting some new decompression job (`ZSTD_initDStream`, `ZSTD_decompressDCtx()`, `ZSTD_decompress_usingDict()`)
	*/
	ZSTD_decompressStream :: proc(zds: ^ZSTD_DStream, output: ^ZSTD_outBuffer, input: ^ZSTD_inBuffer) -> c.size_t ---
	ZSTD_DStreamInSize    :: proc() -> c.size_t --- /*!< recommended size for input buffer */
	ZSTD_DStreamOutSize   :: proc() -> c.size_t --- /*!< recommended size for output buffer. Guarantee to successfully flush at least one complete block in all circumstances. */

	/**************************
	*  Simple dictionary API
	***************************/
	/*! ZSTD_compress_usingDict() :
	*  Compression at an explicit compression level using a Dictionary.
	*  A dictionary can be any arbitrary data segment (also called a prefix),
	*  or a buffer with specified information (see zdict.h).
	*  Note : This function loads the dictionary, resulting in significant startup delay.
	*         It's intended for a dictionary used only once.
	*  Note 2 : When `dict == NULL || dictSize < 8` no dictionary is used. */
	ZSTD_compress_usingDict :: proc(ctx: ^ZSTD_CCtx, dst: rawptr, dstCapacity: c.size_t, src: rawptr, srcSize: c.size_t, dict: rawptr, dictSize: c.size_t, compressionLevel: i32) -> c.size_t ---

	/*! ZSTD_decompress_usingDict() :
	*  Decompression using a known Dictionary.
	*  Dictionary must be identical to the one used during compression.
	*  Note : This function loads the dictionary, resulting in significant startup delay.
	*         It's intended for a dictionary used only once.
	*  Note : When `dict == NULL || dictSize < 8` no dictionary is used. */
	ZSTD_decompress_usingDict :: proc(dctx: ^ZSTD_DCtx, dst: rawptr, dstCapacity: c.size_t, src: rawptr, srcSize: c.size_t, dict: rawptr, dictSize: c.size_t) -> c.size_t ---
}

ZSTD_CDict_s :: struct {}

/***********************************
*  Bulk processing dictionary API
**********************************/
ZSTD_CDict :: ZSTD_CDict_s

@(default_calling_convention="c")
foreign lib {
	/*! ZSTD_createCDict() :
	*  When compressing multiple messages or blocks using the same dictionary,
	*  it's recommended to digest the dictionary only once, since it's a costly operation.
	*  ZSTD_createCDict() will create a state from digesting a dictionary.
	*  The resulting state can be used for future compression operations with very limited startup cost.
	*  ZSTD_CDict can be created once and shared by multiple threads concurrently, since its usage is read-only.
	* @dictBuffer can be released after ZSTD_CDict creation, because its content is copied within CDict.
	*  Note 1 : Consider experimental function `ZSTD_createCDict_byReference()` if you prefer to not duplicate @dictBuffer content.
	*  Note 2 : A ZSTD_CDict can be created from an empty @dictBuffer,
	*      in which case the only thing that it transports is the @compressionLevel.
	*      This can be useful in a pipeline featuring ZSTD_compress_usingCDict() exclusively,
	*      expecting a ZSTD_CDict parameter with any data, including those without a known dictionary. */
	ZSTD_createCDict :: proc(dictBuffer: rawptr, dictSize: c.size_t, compressionLevel: i32) -> ^ZSTD_CDict ---

	/*! ZSTD_freeCDict() :
	*  Function frees memory allocated by ZSTD_createCDict().
	*  If a NULL pointer is passed, no operation is performed. */
	ZSTD_freeCDict :: proc(CDict: ^ZSTD_CDict) -> c.size_t ---

	/*! ZSTD_compress_usingCDict() :
	*  Compression using a digested Dictionary.
	*  Recommended when same dictionary is used multiple times.
	*  Note : compression level is _decided at dictionary creation time_,
	*     and frame parameters are hardcoded (dictID=yes, contentSize=yes, checksum=no) */
	ZSTD_compress_usingCDict :: proc(cctx: ^ZSTD_CCtx, dst: rawptr, dstCapacity: c.size_t, src: rawptr, srcSize: c.size_t, cdict: ^ZSTD_CDict) -> c.size_t ---
}

ZSTD_DDict_s :: struct {}
ZSTD_DDict   :: ZSTD_DDict_s

@(default_calling_convention="c")
foreign lib {
	/*! ZSTD_createDDict() :
	*  Create a digested dictionary, ready to start decompression operation without startup delay.
	*  dictBuffer can be released after DDict creation, as its content is copied inside DDict. */
	ZSTD_createDDict :: proc(dictBuffer: rawptr, dictSize: c.size_t) -> ^ZSTD_DDict ---

	/*! ZSTD_freeDDict() :
	*  Function frees memory allocated with ZSTD_createDDict()
	*  If a NULL pointer is passed, no operation is performed. */
	ZSTD_freeDDict :: proc(ddict: ^ZSTD_DDict) -> c.size_t ---

	/*! ZSTD_decompress_usingDDict() :
	*  Decompression using a digested Dictionary.
	*  Recommended when same dictionary is used multiple times. */
	ZSTD_decompress_usingDDict :: proc(dctx: ^ZSTD_DCtx, dst: rawptr, dstCapacity: c.size_t, src: rawptr, srcSize: c.size_t, ddict: ^ZSTD_DDict) -> c.size_t ---

	/*! ZSTD_getDictID_fromDict() : Requires v1.4.0+
	*  Provides the dictID stored within dictionary.
	*  if @return == 0, the dictionary is not conformant with Zstandard specification.
	*  It can still be loaded, but as a content-only dictionary. */
	ZSTD_getDictID_fromDict :: proc(dict: rawptr, dictSize: c.size_t) -> u32 ---

	/*! ZSTD_getDictID_fromCDict() : Requires v1.5.0+
	*  Provides the dictID of the dictionary loaded into `cdict`.
	*  If @return == 0, the dictionary is not conformant to Zstandard specification, or empty.
	*  Non-conformant dictionaries can still be loaded, but as content-only dictionaries. */
	ZSTD_getDictID_fromCDict :: proc(cdict: ^ZSTD_CDict) -> u32 ---

	/*! ZSTD_getDictID_fromDDict() : Requires v1.4.0+
	*  Provides the dictID of the dictionary loaded into `ddict`.
	*  If @return == 0, the dictionary is not conformant to Zstandard specification, or empty.
	*  Non-conformant dictionaries can still be loaded, but as content-only dictionaries. */
	ZSTD_getDictID_fromDDict :: proc(ddict: ^ZSTD_DDict) -> u32 ---

	/*! ZSTD_getDictID_fromFrame() : Requires v1.4.0+
	*  Provides the dictID required to decompressed the frame stored within `src`.
	*  If @return == 0, the dictID could not be decoded.
	*  This could for one of the following reasons :
	*  - The frame does not require a dictionary to be decoded (most common case).
	*  - The frame was built with dictID intentionally removed. Whatever dictionary is necessary is a hidden piece of information.
	*    Note : this use case also happens when using a non-conformant dictionary.
	*  - `srcSize` is too small, and as a result, the frame header could not be decoded (only possible if `srcSize < ZSTD_FRAMEHEADERSIZE_MAX`).
	*  - This is not a Zstandard frame.
	*  When identifying the exact failure cause, it's possible to use ZSTD_getFrameHeader(), which will provide a more precise error code. */
	ZSTD_getDictID_fromFrame :: proc(src: rawptr, srcSize: c.size_t) -> u32 ---

	/*! ZSTD_CCtx_loadDictionary() : Requires v1.4.0+
	*  Create an internal CDict from `dict` buffer.
	*  Decompression will have to use same dictionary.
	* @result : 0, or an error code (which can be tested with ZSTD_isError()).
	*  Special: Loading a NULL (or 0-size) dictionary invalidates previous dictionary,
	*           meaning "return to no-dictionary mode".
	*  Note 1 : Dictionary is sticky, it will be used for all future compressed frames,
	*           until parameters are reset, a new dictionary is loaded, or the dictionary
	*           is explicitly invalidated by loading a NULL dictionary.
	*  Note 2 : Loading a dictionary involves building tables.
	*           It's also a CPU consuming operation, with non-negligible impact on latency.
	*           Tables are dependent on compression parameters, and for this reason,
	*           compression parameters can no longer be changed after loading a dictionary.
	*  Note 3 :`dict` content will be copied internally.
	*           Use experimental ZSTD_CCtx_loadDictionary_byReference() to reference content instead.
	*           In such a case, dictionary buffer must outlive its users.
	*  Note 4 : Use ZSTD_CCtx_loadDictionary_advanced()
	*           to precisely select how dictionary content must be interpreted.
	*  Note 5 : This method does not benefit from LDM (long distance mode).
	*           If you want to employ LDM on some large dictionary content,
	*           prefer employing ZSTD_CCtx_refPrefix() described below.
	*/
	ZSTD_CCtx_loadDictionary :: proc(cctx: ^ZSTD_CCtx, dict: rawptr, dictSize: c.size_t) -> c.size_t ---

	/*! ZSTD_CCtx_refCDict() : Requires v1.4.0+
	*  Reference a prepared dictionary, to be used for all future compressed frames.
	*  Note that compression parameters are enforced from within CDict,
	*  and supersede any compression parameter previously set within CCtx.
	*  The parameters ignored are labelled as "superseded-by-cdict" in the ZSTD_cParameter enum docs.
	*  The ignored parameters will be used again if the CCtx is returned to no-dictionary mode.
	*  The dictionary will remain valid for future compressed frames using same CCtx.
	* @result : 0, or an error code (which can be tested with ZSTD_isError()).
	*  Special : Referencing a NULL CDict means "return to no-dictionary mode".
	*  Note 1 : Currently, only one dictionary can be managed.
	*           Referencing a new dictionary effectively "discards" any previous one.
	*  Note 2 : CDict is just referenced, its lifetime must outlive its usage within CCtx. */
	ZSTD_CCtx_refCDict :: proc(cctx: ^ZSTD_CCtx, cdict: ^ZSTD_CDict) -> c.size_t ---

	/*! ZSTD_CCtx_refPrefix() : Requires v1.4.0+
	*  Reference a prefix (single-usage dictionary) for next compressed frame.
	*  A prefix is **only used once**. Tables are discarded at end of frame (ZSTD_e_end).
	*  Decompression will need same prefix to properly regenerate data.
	*  Compressing with a prefix is similar in outcome as performing a diff and compressing it,
	*  but performs much faster, especially during decompression (compression speed is tunable with compression level).
	*  This method is compatible with LDM (long distance mode).
	* @result : 0, or an error code (which can be tested with ZSTD_isError()).
	*  Special: Adding any prefix (including NULL) invalidates any previous prefix or dictionary
	*  Note 1 : Prefix buffer is referenced. It **must** outlive compression.
	*           Its content must remain unmodified during compression.
	*  Note 2 : If the intention is to diff some large src data blob with some prior version of itself,
	*           ensure that the window size is large enough to contain the entire source.
	*           See ZSTD_c_windowLog.
	*  Note 3 : Referencing a prefix involves building tables, which are dependent on compression parameters.
	*           It's a CPU consuming operation, with non-negligible impact on latency.
	*           If there is a need to use the same prefix multiple times, consider loadDictionary instead.
	*  Note 4 : By default, the prefix is interpreted as raw content (ZSTD_dct_rawContent).
	*           Use experimental ZSTD_CCtx_refPrefix_advanced() to alter dictionary interpretation. */
	ZSTD_CCtx_refPrefix :: proc(cctx: ^ZSTD_CCtx, prefix: rawptr, prefixSize: c.size_t) -> c.size_t ---

	/*! ZSTD_DCtx_loadDictionary() : Requires v1.4.0+
	*  Create an internal DDict from dict buffer, to be used to decompress all future frames.
	*  The dictionary remains valid for all future frames, until explicitly invalidated, or
	*  a new dictionary is loaded.
	* @result : 0, or an error code (which can be tested with ZSTD_isError()).
	*  Special : Adding a NULL (or 0-size) dictionary invalidates any previous dictionary,
	*            meaning "return to no-dictionary mode".
	*  Note 1 : Loading a dictionary involves building tables,
	*           which has a non-negligible impact on CPU usage and latency.
	*           It's recommended to "load once, use many times", to amortize the cost
	*  Note 2 :`dict` content will be copied internally, so `dict` can be released after loading.
	*           Use ZSTD_DCtx_loadDictionary_byReference() to reference dictionary content instead.
	*  Note 3 : Use ZSTD_DCtx_loadDictionary_advanced() to take control of
	*           how dictionary content is loaded and interpreted.
	*/
	ZSTD_DCtx_loadDictionary :: proc(dctx: ^ZSTD_DCtx, dict: rawptr, dictSize: c.size_t) -> c.size_t ---

	/*! ZSTD_DCtx_refDDict() : Requires v1.4.0+
	*  Reference a prepared dictionary, to be used to decompress next frames.
	*  The dictionary remains active for decompression of future frames using same DCtx.
	*
	*  If called with ZSTD_d_refMultipleDDicts enabled, repeated calls of this function
	*  will store the DDict references in a table, and the DDict used for decompression
	*  will be determined at decompression time, as per the dict ID in the frame.
	*  The memory for the table is allocated on the first call to refDDict, and can be
	*  freed with ZSTD_freeDCtx().
	*
	*  If called with ZSTD_d_refMultipleDDicts disabled (the default), only one dictionary
	*  will be managed, and referencing a dictionary effectively "discards" any previous one.
	*
	* @result : 0, or an error code (which can be tested with ZSTD_isError()).
	*  Special: referencing a NULL DDict means "return to no-dictionary mode".
	*  Note 2 : DDict is just referenced, its lifetime must outlive its usage from DCtx.
	*/
	ZSTD_DCtx_refDDict :: proc(dctx: ^ZSTD_DCtx, ddict: ^ZSTD_DDict) -> c.size_t ---

	/*! ZSTD_DCtx_refPrefix() : Requires v1.4.0+
	*  Reference a prefix (single-usage dictionary) to decompress next frame.
	*  This is the reverse operation of ZSTD_CCtx_refPrefix(),
	*  and must use the same prefix as the one used during compression.
	*  Prefix is **only used once**. Reference is discarded at end of frame.
	*  End of frame is reached when ZSTD_decompressStream() returns 0.
	* @result : 0, or an error code (which can be tested with ZSTD_isError()).
	*  Note 1 : Adding any prefix (including NULL) invalidates any previously set prefix or dictionary
	*  Note 2 : Prefix buffer is referenced. It **must** outlive decompression.
	*           Prefix buffer must remain unmodified up to the end of frame,
	*           reached when ZSTD_decompressStream() returns 0.
	*  Note 3 : By default, the prefix is treated as raw content (ZSTD_dct_rawContent).
	*           Use ZSTD_CCtx_refPrefix_advanced() to alter dictMode (Experimental section)
	*  Note 4 : Referencing a raw content prefix has almost no cpu nor memory cost.
	*           A full dictionary is more costly, as it requires building tables.
	*/
	ZSTD_DCtx_refPrefix :: proc(dctx: ^ZSTD_DCtx, prefix: rawptr, prefixSize: c.size_t) -> c.size_t ---

	/*! ZSTD_sizeof_*() : Requires v1.4.0+
	*  These functions give the _current_ memory usage of selected object.
	*  Note that object memory usage can evolve (increase or decrease) over time. */
	ZSTD_sizeof_CCtx    :: proc(cctx: ^ZSTD_CCtx) -> c.size_t ---
	ZSTD_sizeof_DCtx    :: proc(dctx: ^ZSTD_DCtx) -> c.size_t ---
	ZSTD_sizeof_CStream :: proc(zcs: ^ZSTD_CStream) -> c.size_t ---
	ZSTD_sizeof_DStream :: proc(zds: ^ZSTD_DStream) -> c.size_t ---
	ZSTD_sizeof_CDict   :: proc(cdict: ^ZSTD_CDict) -> c.size_t ---
	ZSTD_sizeof_DDict   :: proc(ddict: ^ZSTD_DDict) -> c.size_t ---
}

