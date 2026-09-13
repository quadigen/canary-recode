// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
package luauh

when ODIN_OS == .JS {
	foreign import lib "../../../../build/web-native/lib/kine_luau_web.o"
} else when ODIN_OS == .Windows {
	foreign import lib {
		"../../../../vendor/build/lib/kine_luau.lib",
		"../../../../vendor/build/vendor/luau/Luau.Compiler.lib",
		"../../../../vendor/build/vendor/luau/Luau.VM.lib",
		"../../../../vendor/build/vendor/luau/Luau.Ast.lib",
		"../../../../vendor/build/vendor/luau/Luau.Bytecode.lib",
		"../../../../vendor/build/vendor/luau/Luau.Common.lib",
	}
} else when #config(KINE_ANDROID, false) {
	foreign import lib {
		"../../../../build/android-native/lib/libkine_luau.a",
		"../../../../build/android-native/luau/libLuau.Compiler.a",
		"../../../../build/android-native/luau/libLuau.VM.a",
		"../../../../build/android-native/luau/libLuau.Ast.a",
		"../../../../build/android-native/luau/libLuau.Bytecode.a",
		"../../../../build/android-native/luau/libLuau.Common.a",
	}
} else {
	foreign import lib {
		"../../../../vendor/build/lib/kine_luau.a",
		"../../../../vendor/build/vendor/luau/libLuau.Compiler.a",
		"../../../../vendor/build/vendor/luau/libLuau.VM.a",
		"../../../../vendor/build/vendor/luau/libLuau.Ast.a",
		"../../../../vendor/build/vendor/luau/libLuau.Bytecode.a",
		"../../../../vendor/build/vendor/luau/libLuau.Common.a",
	}
}

// option for multiple returns in `lua_pcall' and `lua_call'
LUA_MULTRET :: (-1)

/*
** pseudo-indices
*/
LUA_REGISTRYINDEX :: (-8000-2000)
LUA_ENVIRONINDEX  :: (-8000-2001)
LUA_GLOBALSINDEX  :: (-8000-2002)

// thread status; 0 is OK
lua_Status :: enum i32 {
	OK        = 0,
	YIELD     = 1,
	ERRRUN    = 2,
	ERRSYNTAX = 3, // legacy error code, preserved for compatibility
	ERRMEM    = 4,
	ERRERR    = 5,
	BREAK     = 6, // yielded for a debug breakpoint
}

lua_CoStatus :: enum i32 {
	RUN = 0, // running
	SUS = 1, // suspended
	NOR = 2, // 'normal' (it resumed another coroutine)
	FIN = 3, // finished
	ERR = 4, // finished with error
}

lua_State        :: struct {}
lua_CFunction    :: proc "c" (L: ^lua_State) -> i32
lua_UserThread_Callback :: proc "c" (
	parent: ^lua_State,
	thread: ^lua_State,
)
lua_Continuation :: proc "c" (L: ^lua_State, status: i32) -> i32

/*
** prototype for memory-allocation functions
*/
lua_Alloc :: proc "c" (ud: rawptr, ptr: rawptr, osize: uintptr, nsize: uintptr) -> rawptr

/*
** basic types
*/
LUA_TNONE :: (-1)

/*
* WARNING: if you change the order of this enumeration,
* grep "ORDER TYPE"
*/
// clang-format off
lua_Type :: enum i32 {
	NIL           = 0, // must be 0 due to lua_isnoneornil
	BOOLEAN       = 1, // must be 1 due to l_isfalse
	LIGHTUSERDATA = 2,
	NUMBER        = 3,
	INTEGER       = 4,
	VECTOR        = 5,
	STRING        = 6, // all types above this must be value types, all types below this must be GC types - see iscollectable
	TABLE         = 7,
	FUNCTION      = 8,
	USERDATA      = 9,
	THREAD        = 10,
	BUFFER        = 11,
	CLASS         = 12,
	OBJECT        = 13,

	// values below this line are used in GCObject tags but may never show up in TValue type tags
	
	// LUA_TDEADKEY is used in TKey to identify Luau table entries that have the value set to nil,
	// so that we can remove the strong reference to the key.
	DEADKEY       = 14,

	// These values should never show up in TValue tag types.
	PROTO         = 15,
	UPVAL         = 16,

	// the count of all Luau types (including those that are never TValue type tags)
	_ALL          = 17,

	// the count of TValue type tags
	_COUNT        = 14,
}

// type of numbers in Luau
lua_Number :: f64

// type for integer functions
lua_Integer :: i32

// unsigned integer type
lua_Unsigned :: u32

@(default_calling_convention="c", link_prefix="kine_")
foreign lib {
	/*
	** state manipulation
	*/
	lua_newstate      :: proc(allocator: lua_Alloc, ud: rawptr) -> ^lua_State ---
	lua_close         :: proc(L: ^lua_State) ---
	lua_newthread     :: proc(L: ^lua_State) -> ^lua_State ---
	lua_mainthread    :: proc(L: ^lua_State) -> ^lua_State ---
	lua_resetthread   :: proc(L: ^lua_State) ---
	lua_isthreadreset :: proc(L: ^lua_State) -> i32 ---
	lua_getthreaddata :: proc(
		L: ^lua_State,
	) -> rawptr ---

	lua_setthreaddata :: proc(
		L: ^lua_State,
		data: rawptr,
	) ---
	luaL_error :: proc "c" (
		L: ^lua_State,
		message: cstring,
	) -> i32 ---

	lua_setuserthreadcallback :: proc(
		L: ^lua_State,
		callback: lua_UserThread_Callback,
	) ---

	/*
	** basic stack manipulation
	*/
	lua_absindex      :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_gettop        :: proc(L: ^lua_State) -> i32 ---
	lua_settop        :: proc(L: ^lua_State, idx: i32) ---
	lua_pushvalue     :: proc(L: ^lua_State, idx: i32) ---
	lua_remove        :: proc(L: ^lua_State, idx: i32) ---
	lua_insert        :: proc(L: ^lua_State, idx: i32) ---
	lua_replace       :: proc(L: ^lua_State, idx: i32) ---
	lua_checkstack    :: proc(L: ^lua_State, sz: i32) -> i32 ---
	lua_rawcheckstack :: proc(L: ^lua_State, sz: i32) --- // allows for unlimited stack frames
	lua_xmove         :: proc(from: ^lua_State, to: ^lua_State, n: i32) ---
	lua_xpush         :: proc(from: ^lua_State, to: ^lua_State, idx: i32) ---

	/*
	** access functions (stack -> C)
	*/
	lua_isnumber              :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_isstring              :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_isinteger64           :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_iscfunction           :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_isLfunction           :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_isuserdata            :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_type                  :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_typename              :: proc(L: ^lua_State, tp: i32) -> cstring ---
	lua_equal                 :: proc(L: ^lua_State, idx1: i32, idx2: i32) -> i32 ---
	lua_rawequal              :: proc(L: ^lua_State, idx1: i32, idx2: i32) -> i32 ---
	lua_lessthan              :: proc(L: ^lua_State, idx1: i32, idx2: i32) -> i32 ---
	lua_tonumberx             :: proc(L: ^lua_State, idx: i32, isnum: ^i32) -> f64 ---
	lua_tointegerx            :: proc(L: ^lua_State, idx: i32, isnum: ^i32) -> i32 ---
	lua_tounsignedx           :: proc(L: ^lua_State, idx: i32, isnum: ^i32) -> u32 ---
	lua_tovector              :: proc(L: ^lua_State, idx: i32) -> ^f32 ---
	lua_toboolean             :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_tointeger64           :: proc(L: ^lua_State, idx: i32, isinteger: ^i32) -> i64 ---
	lua_tolstring             :: proc(L: ^lua_State, idx: i32, len: ^uintptr) -> cstring ---
	lua_tostringatom          :: proc(L: ^lua_State, idx: i32, atom: ^i32) -> cstring ---
	lua_tolstringatom         :: proc(L: ^lua_State, idx: i32, len: ^uintptr, atom: ^i32) -> cstring ---
	lua_namecallatom          :: proc(L: ^lua_State, atom: ^i32) -> cstring ---
	lua_objlen                :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_tocfunction           :: proc(L: ^lua_State, idx: i32) -> lua_CFunction ---
	lua_tolightuserdata       :: proc(L: ^lua_State, idx: i32) -> rawptr ---
	lua_tolightuserdatatagged :: proc(L: ^lua_State, idx: i32, tag: i32) -> rawptr ---
	lua_touserdata            :: proc(L: ^lua_State, idx: i32) -> rawptr ---
	lua_touserdatatagged      :: proc(L: ^lua_State, idx: i32, tag: i32) -> rawptr ---
	lua_userdatatag           :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_lightuserdatatag      :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_tothread              :: proc(L: ^lua_State, idx: i32) -> ^lua_State ---
	lua_tobuffer              :: proc(L: ^lua_State, idx: i32, len: ^uintptr) -> rawptr ---
	lua_topointer             :: proc(L: ^lua_State, idx: i32) -> rawptr ---

	/*
	** push functions (C -> stack)
	*/
	lua_pushnil                        :: proc(L: ^lua_State) ---
	lua_pushnumber                     :: proc(L: ^lua_State, n: f64) ---
	lua_pushinteger                    :: proc(L: ^lua_State, n: i32) ---
	lua_pushinteger64                  :: proc(L: ^lua_State, n: i64) ---
	lua_pushunsigned                   :: proc(L: ^lua_State, n: u32) ---
	lua_pushvector                     :: proc(L: ^lua_State, x: f32, y: f32, z: f32) ---
	lua_pushlstring                    :: proc(L: ^lua_State, s: cstring, l: uintptr) ---
	lua_pushstring                     :: proc(L: ^lua_State, s: cstring) ---
	lua_pushvfstring                   :: proc(L: ^lua_State, fmt: cstring, argp: rawptr) -> cstring ---
	lua_pushfstringL                   :: proc(L: ^lua_State, fmt: cstring, #c_vararg _: ..any) -> cstring ---
	lua_pushcclosurek                  :: proc(L: ^lua_State, fn: lua_CFunction, debugname: cstring, nup: i32, cont: lua_Continuation) ---
	lua_pushboolean                    :: proc(L: ^lua_State, b: i32) ---
	lua_pushthread                     :: proc(L: ^lua_State) -> i32 ---
	lua_pushlightuserdatatagged        :: proc(L: ^lua_State, p: rawptr, tag: i32) ---
	lua_newuserdatatagged              :: proc(L: ^lua_State, sz: uintptr, tag: i32) -> rawptr ---
	lua_newuserdatataggedwithmetatable :: proc(L: ^lua_State, sz: uintptr, tag: i32) -> rawptr --- // metatable fetched with lua_getuserdatametatable
	lua_newuserdatadtor                :: proc(L: ^lua_State, sz: uintptr, dtor: proc "c" (rawptr)) -> rawptr ---
	lua_newbuffer                      :: proc(L: ^lua_State, sz: uintptr) -> rawptr ---

	/*
	** get functions (Lua -> stack)
	*/
	lua_gettable      :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_getfield      :: proc(L: ^lua_State, idx: i32, k: cstring) -> i32 ---
	lua_rawgetfield   :: proc(L: ^lua_State, idx: i32, k: cstring) -> i32 ---
	lua_rawget        :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_rawgeti       :: proc(L: ^lua_State, idx: i32, n: i32) -> i32 ---
	lua_rawgetptagged :: proc(L: ^lua_State, idx: i32, p: rawptr, tag: i32) -> i32 ---
	lua_createtable   :: proc(L: ^lua_State, narr: i32, nrec: i32) ---
	lua_setreadonly   :: proc(L: ^lua_State, idx: i32, enabled: i32) ---
	lua_getreadonly   :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_setsafeenv    :: proc(L: ^lua_State, idx: i32, enabled: i32) ---
	lua_getmetatable  :: proc(L: ^lua_State, objindex: i32) -> i32 ---
	lua_getfenv       :: proc(L: ^lua_State, idx: i32) ---

	/*
	** set functions (stack -> Lua)
	*/
	lua_settable      :: proc(L: ^lua_State, idx: i32) ---
	lua_setfield      :: proc(L: ^lua_State, idx: i32, k: cstring) ---
	lua_rawsetfield   :: proc(L: ^lua_State, idx: i32, k: cstring) ---
	lua_rawset        :: proc(L: ^lua_State, idx: i32) ---
	lua_rawseti       :: proc(L: ^lua_State, idx: i32, n: i32) ---
	lua_rawsetptagged :: proc(L: ^lua_State, idx: i32, p: rawptr, tag: i32) ---
	lua_setmetatable  :: proc(L: ^lua_State, objindex: i32) -> i32 ---
	lua_setfenv       :: proc(L: ^lua_State, idx: i32) -> i32 ---

	/*
	** `load' and `call' functions (load and run Luau bytecode)
	*/
	luau_load  :: proc(L: ^lua_State, chunkname: cstring, data: cstring, size: uintptr, env: i32) -> i32 ---
	lua_call   :: proc(L: ^lua_State, nargs: i32, nresults: i32) ---
	lua_pcall  :: proc(L: ^lua_State, nargs: i32, nresults: i32, errfunc: i32) -> i32 ---
	lua_cpcall :: proc(L: ^lua_State, func: lua_CFunction, ud: rawptr) -> i32 ---

	// wrapper for making calls from yieldable C functions
	lua_callyieldable  :: proc(L: ^lua_State, nargs: i32, nresults: i32) -> i32 ---
	lua_pcallyieldable :: proc(L: ^lua_State, nargs: i32, nresults: i32, errfunc: i32) -> i32 ---

	/*
	** coroutine functions
	*/
	lua_yield         :: proc(L: ^lua_State, nresults: i32) -> i32 ---
	lua_break         :: proc(L: ^lua_State) -> i32 ---
	lua_resume        :: proc(L: ^lua_State, from: ^lua_State, narg: i32) -> i32 ---
	lua_resumeerror   :: proc(L: ^lua_State, from: ^lua_State) -> i32 ---
	lua_status        :: proc(L: ^lua_State) -> i32 ---
	lua_isyieldable   :: proc(L: ^lua_State) -> i32 ---
	lua_costatus      :: proc(L: ^lua_State, co: ^lua_State) -> i32 ---
}

/*
** garbage-collection function and options
*/
lua_GCOp :: enum i32 {
	// stop and resume incremental garbage collection
	STOP        = 0,
	RESTART     = 1,

	// run a full GC cycle; not recommended for latency sensitive applications
	COLLECT     = 2,

	// return the heap size in KB and the remainder in bytes
	COUNT       = 3,
	COUNTB      = 4,

	// return 1 if GC is active (not stopped); note that GC may not be actively collecting even if it's running
	ISRUNNING   = 5,

	/*
	** perform an explicit GC step, with the step size specified in KB
	**
	** garbage collection is handled by 'assists' that perform some amount of GC work matching pace of allocation
	** explicit GC steps allow to perform some amount of work at custom points to offset the need for GC assists
	** note that GC might also be paused for some duration (until bytes allocated meet the threshold)
	** if an explicit step is performed during this pause, it will trigger the start of the next collection cycle
	*/
	STEP        = 6,

	/*
	** tune GC parameters G (goal), S (step multiplier) and step size (usually best left ignored)
	**
	** garbage collection is incremental and tries to maintain the heap size to balance memory and performance overhead
	** this overhead is determined by G (goal) which is the ratio between total heap size and the amount of live data in it
	** G is specified in percentages; by default G=200% which means that the heap is allowed to grow to ~2x the size of live data.
	**
	** collector tries to collect S% of allocated bytes by interrupting the application after step size bytes were allocated.
	** when S is too small, collector may not be able to catch up and the effective goal that can be reached will be larger.
	** S is specified in percentages; by default S=200% which means that collector will run at ~2x the pace of allocations.
	**
	** it is recommended to set S in the interval [100 / (G - 100), 100 + 100 / (G - 100))] with a minimum value of 150%; for example:
	** - for G=200%, S should be in the interval [150%, 200%]
	** - for G=150%, S should be in the interval [200%, 300%]
	** - for G=125%, S should be in the interval [400%, 500%]
	*/
	SETGOAL     = 7,
	SETSTEPMUL  = 8,
	SETSTEPSIZE = 9,

	// return 1 if GC is in a paused state; making a GC step in a paused state will unpause the GC
	ISPAUSED    = 10,
}

@(default_calling_convention="c")
foreign lib {
	lua_gc :: proc(L: ^lua_State, what: i32, data: i32) -> i32 ---
}

lua_CategoryName :: proc "c" (L: ^lua_State, memcat: u8) -> cstring

@(default_calling_convention="c", link_prefix="kine_")
foreign lib {
	// write a Luau memory dump to a FILE in JSON format
	// categoryName callback, when provided, will be called to record a name associated with the category
	lua_memorydump :: proc(L: ^lua_State, file: rawptr, categoryName: lua_CategoryName) ---

	/*
	** memory statistics
	** all allocated bytes are attributed to the memory category of the running thread (0..LUA_MEMORY_CATEGORIES-1)
	*/
	lua_setmemcat  :: proc(L: ^lua_State, category: i32) ---
	lua_totalbytes :: proc(L: ^lua_State, category: i32) -> uintptr ---

	// measure the allocation rate in bytes/sec
	// returns -1 if allocation rate cannot be measured
	lua_allocationrate :: proc(L: ^lua_State) -> i64 ---

	/*
	** miscellaneous functions
	*/
	lua_error               :: proc(L: ^lua_State) -> i32 ---
	lua_next                :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_rawiter             :: proc(L: ^lua_State, idx: i32, iter: i32) -> i32 ---
	lua_concat              :: proc(L: ^lua_State, n: i32) ---
	lua_setpointerencodekey :: proc(L: ^lua_State, a: u64, b: u64, _c: u64, d: u64) ---
	lua_encodepointer       :: proc(L: ^lua_State, p: uintptr) -> uintptr ---
	lua_clock               :: proc() -> f64 ---
	lua_setuserdatatag      :: proc(L: ^lua_State, idx: i32, tag: i32) ---
}

lua_Destructor :: proc "c" (L: ^lua_State, userdata: rawptr)

@(default_calling_convention="c", link_prefix="kine_")
foreign lib {
	lua_setuserdatadtor :: proc(L: ^lua_State, tag: i32, dtor: lua_Destructor) ---
	lua_getuserdatadtor :: proc(L: ^lua_State, tag: i32) -> lua_Destructor ---
}

// Embedder GC integration APIs
//
// Luau -> embedder (lua_setuserdatamark): when the GC marks a tagged userdata,
// the registered callback fires so the embedder can mark the corresponding
// native object as reachable.
//
// Embedder -> Luau (lua_setembeddergc): the GC calls this each cycle.
// Two cases:
// 1. Cycle reset (markref == NULL): clear accumulated information about marked
//      native objects.
// 2. Mark phase (markref != NULL): embedder must call markref for each new ref
//      that is reachable from a marked native object.
//
// Together, these are used to implement a fixed-point reachability algorithm
// across both heaps.
//
// Note: because these functions are called during garbage collection, they
// must not perform any reentrant operations on the lua_State. Only truly
// read-only APIs like lua_getthreaddata are safe to call from here.
lua_UserdataMark :: proc "c" (L: ^lua_State, ud: rawptr)

@(default_calling_convention="c")
foreign lib {
	lua_setuserdatamark :: proc(L: ^lua_State, tag: i32, markfn: lua_UserdataMark) ---
}

lua_EmbedderMark :: proc "c" (L: ^lua_State, ref: i32)
lua_EmbedderGc   :: proc "c" (L: ^lua_State, markref: lua_EmbedderMark)

@(default_calling_convention="c", link_prefix="kine_")
foreign lib {
	lua_setembeddergc :: proc(L: ^lua_State, fn: lua_EmbedderGc) ---

	// APIs for interacting with embedder-managed weak references.
	//
	// Unlike lua_ref, these do not prevent collection on their own; the embedder
	// must call markref(L, ref) inside lua_EmbedderGc to keep them alive. If the
	// lua_getweakref API returns nil when the embedder expects the object to be
	// alive, it indicates a bug in the embedder's logic.
	//
	// Bugs in the embedder's marking logic can manifest in two ways:
	// - the native object owning a ref was not marked (Luau -> embedder), or
	// - if the native object was marked, the ref was not marked (embedder -> Luau).
	//
	// Otherwise, a non-marking-related bug could simply be that the embedder is
	// trying to access a ref that was correctly collected. Specifically, if a
	// native object that logically owns a ref is destroyed, then the embedder
	// should not be trying to access that ref anymore.
	//
	// In any case, asserting on the return value of lua_getweakref is a good way
	// for embedders to catch bugs in their own marking logic.
	lua_weakref    :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_weakunref  :: proc(L: ^lua_State, ref: i32) -> i32 ---
	lua_getweakref :: proc(L: ^lua_State, ref: i32) -> i32 --- // returns the type of the value pushed onto the stack
	

	// alternative access for userdata metatables
	// used by lua_newuserdatataggedwithmetatable to create tagged userdata with the associated metatable assigned
	lua_setuserdatametatable :: proc(L: ^lua_State, tag: i32) ---
	lua_getuserdatametatable :: proc(L: ^lua_State, tag: i32) ---

	// Returns the name of a userdata tag - `__type` from the metatable or "userdata" if it is not set
	lua_getuserdataname :: proc(L: ^lua_State, tag: i32) -> cstring ---
}

// NOTE: experimental API and is subject to breaking changes
// registration of callbacks for direct userdata __index, __newindex and __namecall access with string keys assigned with an atom
// cachedslot is initially 0 and can be set to a custom value to help with data lookup inside the userdata
// IMPORTANT: cachedslot values are shared between all userdata, callbacks function of one userdata tag has to correctly handle values set by another
lua_UserdataDirectAccess   :: proc "c" (L: ^lua_State, data: rawptr, atom: i32, cachedslot: ^u16, utag: i32)
lua_UserdataDirectNamecall :: proc "c" (L: ^lua_State, data: rawptr, atom: i32, cachedslot: ^u16, utag: i32) -> i32

@(default_calling_convention="c")
foreign lib {
	lua_registeruserdatadirectaccess :: proc(L: ^lua_State, tag: i32, get: lua_UserdataDirectAccess, set: lua_UserdataDirectAccess, namecall: lua_UserdataDirectNamecall) -> i32 ---
}

/*
** Direct field API
**
** lua_registeruserdatadirectfieldget registers a per-field, per-userdata-type
** handler that is invoked directly without allocating a Luau call frame.
**
** tag:   userdata tag (0..LUA_UTAG_LIMIT-1)
** field: field name string (will be interned and pinned)
** fn:    handler — receives raw userdata data pointer and result TValue slot
*/
lua_UserdataDirectFieldGet :: proc "c" (ud: rawptr, result: rawptr)

@(default_calling_convention="c")
foreign lib {
	lua_registeruserdatadirectfieldget :: proc(L: ^lua_State, tag: i32, field: cstring, fn: lua_UserdataDirectFieldGet) ---

	// Helpers for writing result values from a direct field handler.
	lua_userdatadirectfield_setnumber    :: proc(result: rawptr, n: f64) ---
	lua_userdatadirectfield_setvector    :: proc(result: rawptr, x: f32, y: f32, z: f32) ---
	lua_userdatadirectfield_setboolean   :: proc(result: rawptr, b: i32) ---
	lua_userdatadirectfield_setinteger64 :: proc(result: rawptr, n: i64) ---
	lua_userdatadirectfield_setnil       :: proc(result: rawptr) ---
	lua_setlightuserdataname             :: proc(L: ^lua_State, tag: i32, name: cstring) ---
	lua_getlightuserdataname             :: proc(L: ^lua_State, tag: i32) -> cstring ---
	lua_clonefunction                    :: proc(L: ^lua_State, idx: i32) ---
	lua_usesexport                       :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_cleartable                       :: proc(L: ^lua_State, idx: i32) ---
	lua_clonetable                       :: proc(L: ^lua_State, idx: i32) ---
	lua_getallocf                        :: proc(L: ^lua_State, ud: ^rawptr) -> lua_Alloc ---
}

/*
** reference system, can be used to pin objects
*/
LUA_NOREF  :: -1
LUA_REFNIL :: 0

@(default_calling_convention="c", link_prefix="kine_")
foreign lib {
	lua_ref   :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_unref :: proc(L: ^lua_State, ref: i32) -> i32 ---
}

// Functions to be called by the debugger in specific events
lua_Hook :: proc "c" (L: ^lua_State, ar: ^lua_Debug)

@(default_calling_convention="c")
foreign lib {
	// invoke a debug hook on a thread in break/yield state
	// userdata is passed to hook through lua_Debug::userdata field
	lua_callhook           :: proc(L: ^lua_State, hook: lua_Hook, userdata: rawptr) ---
	lua_stackdepth         :: proc(L: ^lua_State) -> i32 ---
	lua_getinfo            :: proc(L: ^lua_State, level: i32, what: cstring, ar: ^lua_Debug) -> i32 ---
	lua_getargument        :: proc(L: ^lua_State, level: i32, n: i32) -> i32 ---
	lua_getlocal           :: proc(L: ^lua_State, level: i32, n: i32) -> cstring ---
	lua_setlocal           :: proc(L: ^lua_State, level: i32, n: i32) -> cstring ---
	lua_getupvalue         :: proc(L: ^lua_State, funcindex: i32, n: i32) -> cstring ---
	lua_setupvalue         :: proc(L: ^lua_State, funcindex: i32, n: i32) -> cstring ---
	lua_hascustomexecution :: proc(L: ^lua_State, level: i32) -> i32 --- // function has custom execution data set
	lua_incustomexecution  :: proc(L: ^lua_State, level: i32) -> i32 --- // function is running using custom execution
	lua_singlestep         :: proc(L: ^lua_State, enabled: i32) ---
	lua_breakpoint         :: proc(L: ^lua_State, funcindex: i32, line: i32, enabled: i32) -> i32 ---

	// returns 1 if execution is currently at a breakpoint; should only be called from debug callbacks
	lua_atbreakpoint :: proc(L: ^lua_State) -> i32 ---

	// Warning: this function is not thread-safe since it stores the result in a shared global array! Only use for debugging.
	lua_debugtrace :: proc(L: ^lua_State) -> cstring ---
}

lua_Debug :: struct {
	name:        cstring, // (n)
	what:        cstring, // (s) `Lua', `C', `main', `tail'
	source:      cstring, // (s)
	short_src:   cstring, // (s)
	linedefined: i32,     // (s)
	currentline: i32,     // (l)
	protoid:     i32,     // (p) globally unique (within VM) proto id; 0 for C functions
	bytecodeid:  i32,     // (p) proto index within its bytecode module; -1 for C functions
	nupvals:     u8,      // (u) number of upvalues
	nparams:     u8,      // (a) number of parameters
	isvararg:    i8,      // (a)
	userdata:    rawptr,  // only valid in lua_callhook
	ssbuf:       [256]i8,
}

lua_Coverage :: proc "c" (_context: rawptr, function: cstring, linedefined: i32, depth: i32, hits: ^i32, size: uintptr)

@(default_calling_convention="c")
foreign lib {
	lua_getcoverage :: proc(L: ^lua_State, funcindex: i32, _context: rawptr, callback: lua_Coverage) ---
}

lua_CounterFunction :: proc "c" (_context: rawptr, function: cstring, linedefined: i32)
lua_CounterValue    :: proc "c" (_context: rawptr, kind: i32, line: i32, hits: u64)

@(default_calling_convention="c")
foreign lib {
	// Unlike 'lua_getcoverage', counters are customizable in ways which prevent merging them together
	// 'lua_getcounters' will visit the specified function and all nested functions
	// 'functionvisit' is called first to establish a function, then multiple calls of 'countervisit' are made for each counter in that function
	lua_getcounters :: proc(L: ^lua_State, funcindex: i32, _context: rawptr, functionvisit: lua_CounterFunction, countervisit: lua_CounterValue) ---
}

/* Callbacks that can be used to reconfigure behavior of the VM dynamically.
* These are shared between all coroutines.
*
* Note: interrupt is safe to set from an arbitrary thread but all other callbacks
* can only be changed when the VM is not running any code */
lua_Callbacks :: struct {
	userdata:            rawptr,                                                   // arbitrary userdata pointer that is never overwritten by Luau
	interrupt:           proc "c" (L: ^lua_State, gc: i32),                        // gets called at safepoints (loop back edges, call/ret, gc) if set
	panic:               proc "c" (L: ^lua_State, errcode: i32),                   // gets called when an unprotected error is raised (if longjmp is used)
	userthread:          proc "c" (LP: ^lua_State, L: ^lua_State),                 // gets called when L is created (LP == parent) or destroyed (LP == NULL)
	useratom:            proc "c" (L: ^lua_State, s: cstring, l: uintptr) -> i16, // gets called when a string is created to assign an atom id
	debugbreak:          proc "c" (L: ^lua_State, ar: ^lua_Debug),                 // gets called when BREAK instruction is encountered
	debugstep:           proc "c" (L: ^lua_State, ar: ^lua_Debug),                 // gets called after each instruction in single step mode
	debuginterrupt:      proc "c" (L: ^lua_State, ar: ^lua_Debug),                 // gets called when thread execution is interrupted by break in another thread
	debugprotectederror: proc "c" (L: ^lua_State),                                 // gets called when protected call results in an error

	// gets called after a heap object (or array) is allocated
	onallocate: proc "c" (L: ^lua_State, block: rawptr, osize: uintptr, nsize: uintptr, memcat: u8, tt: i32, tag: i32),
	preresume:  proc "c" (L: ^lua_State), // gets called before lua_resume runs a (co)routine
	postresume: proc "c" (L: ^lua_State), // gets called after lua_resume returns (yield, return, or error)

	// gets called before a heap object (or array) is freed
	onfree: proc "c" (L: ^lua_State, block: rawptr),
}

@(default_calling_convention="c")
foreign lib {
	lua_callbacks :: proc(L: ^lua_State) -> ^lua_Callbacks ---
}
