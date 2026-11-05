

package luauh

when ODIN_OS == .JS {
	foreign import lib "../../../../build/web-native/lib/kine_luau_web.o"
} else when ODIN_OS == .Windows {
	foreign import lib {"../../../../vendor/build/lib/kine_luau.lib", "../../../../vendor/build/vendor/luau/Luau.Analysis.lib", "../../../../vendor/build/vendor/luau/Luau.Config.lib", "../../../../vendor/build/vendor/luau/Luau.CodeGen.lib", "../../../../vendor/build/vendor/luau/Luau.Compiler.lib", "../../../../vendor/build/vendor/luau/Luau.VM.lib", "../../../../vendor/build/vendor/luau/Luau.Ast.lib", "../../../../vendor/build/vendor/luau/Luau.Bytecode.lib", "../../../../vendor/build/vendor/luau/Luau.Common.lib"}
} else when #config(KINE_ANDROID, false) {
	foreign import lib {"../../../../build/android-native/lib/libkine_luau.a", "../../../../build/android-native/luau/libLuau.CodeGen.a", "../../../../build/android-native/luau/libLuau.Compiler.a", "../../../../build/android-native/luau/libLuau.VM.a", "../../../../build/android-native/luau/libLuau.Ast.a", "../../../../build/android-native/luau/libLuau.Bytecode.a", "../../../../build/android-native/luau/libLuau.Common.a"}
} else {
	foreign import lib {"../../../../vendor/build/lib/kine_luau.a", "../../../../vendor/build/vendor/luau/libLuau.Analysis.a", "../../../../vendor/build/vendor/luau/libLuau.Config.a", "../../../../vendor/build/vendor/luau/libLuau.CodeGen.a", "../../../../vendor/build/vendor/luau/libLuau.Compiler.a", "../../../../vendor/build/vendor/luau/libLuau.VM.a", "../../../../vendor/build/vendor/luau/libLuau.Ast.a", "../../../../vendor/build/vendor/luau/libLuau.Bytecode.a", "../../../../vendor/build/vendor/luau/libLuau.Common.a", "system:stdc++", "system:m"}
}


LUA_MULTRET :: (-1)


LUA_REGISTRYINDEX :: (-8000 - 2000)
LUA_ENVIRONINDEX :: (-8000 - 2001)
LUA_GLOBALSINDEX :: (-8000 - 2002)


lua_Status :: enum i32 {
	OK        = 0,
	YIELD     = 1,
	ERRRUN    = 2,
	ERRSYNTAX = 3,
	ERRMEM    = 4,
	ERRERR    = 5,
	BREAK     = 6,
}

lua_CoStatus :: enum i32 {
	RUN = 0,
	SUS = 1,
	NOR = 2,
	FIN = 3,
	ERR = 4,
}

lua_State :: struct {}
lua_CFunction :: proc "c" (L: ^lua_State) -> i32
lua_UserThread_Callback :: proc "c" (parent: ^lua_State, thread: ^lua_State)
lua_Continuation :: proc "c" (L: ^lua_State, status: i32) -> i32


lua_Alloc :: proc "c" (ud: rawptr, ptr: rawptr, osize: uintptr, nsize: uintptr) -> rawptr


LUA_TNONE :: (-1)


lua_Type :: enum i32 {
	NIL           = 0,
	BOOLEAN       = 1,
	LIGHTUSERDATA = 2,
	NUMBER        = 3,
	INTEGER       = 4,
	VECTOR        = 5,
	STRING        = 6,
	TABLE         = 7,
	FUNCTION      = 8,
	USERDATA      = 9,
	THREAD        = 10,
	BUFFER        = 11,
	CLASS         = 12,
	OBJECT        = 13,
	DEADKEY       = 14,
	PROTO         = 15,
	UPVAL         = 16,
	_ALL          = 17,
	_COUNT        = 14,
}


lua_Number :: f64


lua_Integer :: i32


lua_Unsigned :: u32


@(default_calling_convention = "c")
foreign lib {
	lua_tobuffer :: proc(L: ^lua_State, idx: i32, len: ^uintptr) -> rawptr ---
	@(link_name = "kine_luau_diagnose_calls")
	luau_diagnose_calls :: proc(L: ^lua_State, text: cstring, size: uintptr, line: ^u32) -> cstring ---
}

@(default_calling_convention = "c", link_prefix = "kine_")
foreign lib {

	lua_newstate :: proc(allocator: lua_Alloc, ud: rawptr) -> ^lua_State ---
	lua_close :: proc(L: ^lua_State) ---
	lua_newthread :: proc(L: ^lua_State) -> ^lua_State ---
	lua_mainthread :: proc(L: ^lua_State) -> ^lua_State ---
	lua_resetthread :: proc(L: ^lua_State) ---
	lua_isthreadreset :: proc(L: ^lua_State) -> i32 ---
	lua_getthreaddata :: proc(L: ^lua_State) -> rawptr ---

	lua_setthreaddata :: proc(L: ^lua_State, data: rawptr) ---
	luaL_error :: proc "c" (L: ^lua_State, message: cstring) -> i32 ---

	lua_setuserthreadcallback :: proc(L: ^lua_State, callback: lua_UserThread_Callback) ---


	lua_absindex :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_gettop :: proc(L: ^lua_State) -> i32 ---
	lua_settop :: proc(L: ^lua_State, idx: i32) ---
	lua_pushvalue :: proc(L: ^lua_State, idx: i32) ---
	lua_remove :: proc(L: ^lua_State, idx: i32) ---
	lua_insert :: proc(L: ^lua_State, idx: i32) ---
	lua_replace :: proc(L: ^lua_State, idx: i32) ---
	lua_checkstack :: proc(L: ^lua_State, sz: i32) -> i32 ---
	lua_rawcheckstack :: proc(L: ^lua_State, sz: i32) ---
	lua_xmove :: proc(from: ^lua_State, to: ^lua_State, n: i32) ---
	lua_xpush :: proc(from: ^lua_State, to: ^lua_State, idx: i32) ---


	lua_isnumber :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_isstring :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_isinteger64 :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_iscfunction :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_isLfunction :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_isuserdata :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_type :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_typename :: proc(L: ^lua_State, tp: i32) -> cstring ---
	lua_equal :: proc(L: ^lua_State, idx1: i32, idx2: i32) -> i32 ---
	lua_rawequal :: proc(L: ^lua_State, idx1: i32, idx2: i32) -> i32 ---
	lua_lessthan :: proc(L: ^lua_State, idx1: i32, idx2: i32) -> i32 ---
	lua_tonumberx :: proc(L: ^lua_State, idx: i32, isnum: ^i32) -> f64 ---
	lua_tointegerx :: proc(L: ^lua_State, idx: i32, isnum: ^i32) -> i32 ---
	lua_tounsignedx :: proc(L: ^lua_State, idx: i32, isnum: ^i32) -> u32 ---
	lua_tovector :: proc(L: ^lua_State, idx: i32) -> ^f32 ---
	lua_toboolean :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_tointeger64 :: proc(L: ^lua_State, idx: i32, isinteger: ^i32) -> i64 ---
	lua_tolstring :: proc(L: ^lua_State, idx: i32, len: ^uintptr) -> cstring ---
	lua_tostringatom :: proc(L: ^lua_State, idx: i32, atom: ^i32) -> cstring ---
	lua_tolstringatom :: proc(L: ^lua_State, idx: i32, len: ^uintptr, atom: ^i32) -> cstring ---
	lua_namecallatom :: proc(L: ^lua_State, atom: ^i32) -> cstring ---
	lua_objlen :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_tocfunction :: proc(L: ^lua_State, idx: i32) -> lua_CFunction ---
	lua_tolightuserdata :: proc(L: ^lua_State, idx: i32) -> rawptr ---
	lua_tolightuserdatatagged :: proc(L: ^lua_State, idx: i32, tag: i32) -> rawptr ---
	lua_touserdata :: proc(L: ^lua_State, idx: i32) -> rawptr ---
	lua_touserdatatagged :: proc(L: ^lua_State, idx: i32, tag: i32) -> rawptr ---
	lua_userdatatag :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_lightuserdatatag :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_tothread :: proc(L: ^lua_State, idx: i32) -> ^lua_State ---
	lua_topointer :: proc(L: ^lua_State, idx: i32) -> rawptr ---


	lua_pushnil :: proc(L: ^lua_State) ---
	lua_pushnumber :: proc(L: ^lua_State, n: f64) ---
	lua_pushinteger :: proc(L: ^lua_State, n: i32) ---
	lua_pushinteger64 :: proc(L: ^lua_State, n: i64) ---
	lua_pushunsigned :: proc(L: ^lua_State, n: u32) ---
	lua_pushvector :: proc(L: ^lua_State, x: f32, y: f32, z: f32) ---
	lua_pushlstring :: proc(L: ^lua_State, s: cstring, l: uintptr) ---
	lua_pushstring :: proc(L: ^lua_State, s: cstring) ---
	lua_pushvfstring :: proc(L: ^lua_State, fmt: cstring, argp: rawptr) -> cstring ---
	lua_pushfstringL :: proc(L: ^lua_State, fmt: cstring, #c_vararg _: ..any) -> cstring ---
	lua_pushcclosurek :: proc(L: ^lua_State, fn: lua_CFunction, debugname: cstring, nup: i32, cont: lua_Continuation) ---
	lua_pushboolean :: proc(L: ^lua_State, b: i32) ---
	lua_pushthread :: proc(L: ^lua_State) -> i32 ---
	lua_pushlightuserdatatagged :: proc(L: ^lua_State, p: rawptr, tag: i32) ---
	lua_newuserdatatagged :: proc(L: ^lua_State, sz: uintptr, tag: i32) -> rawptr ---
	lua_newuserdatataggedwithmetatable :: proc(L: ^lua_State, sz: uintptr, tag: i32) -> rawptr ---
	lua_newuserdatadtor :: proc(L: ^lua_State, sz: uintptr, dtor: proc "c" (_: rawptr)) -> rawptr ---
	lua_newbuffer :: proc(L: ^lua_State, sz: uintptr) -> rawptr ---


	lua_gettable :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_getfield :: proc(L: ^lua_State, idx: i32, k: cstring) -> i32 ---
	lua_rawgetfield :: proc(L: ^lua_State, idx: i32, k: cstring) -> i32 ---
	lua_rawget :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_rawgeti :: proc(L: ^lua_State, idx: i32, n: i32) -> i32 ---
	lua_rawgetptagged :: proc(L: ^lua_State, idx: i32, p: rawptr, tag: i32) -> i32 ---
	lua_createtable :: proc(L: ^lua_State, narr: i32, nrec: i32) ---
	lua_setreadonly :: proc(L: ^lua_State, idx: i32, enabled: i32) ---
	lua_getreadonly :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_setsafeenv :: proc(L: ^lua_State, idx: i32, enabled: i32) ---
	lua_getmetatable :: proc(L: ^lua_State, objindex: i32) -> i32 ---
	lua_getfenv :: proc(L: ^lua_State, idx: i32) ---


	lua_settable :: proc(L: ^lua_State, idx: i32) ---
	lua_setfield :: proc(L: ^lua_State, idx: i32, k: cstring) ---
	lua_rawsetfield :: proc(L: ^lua_State, idx: i32, k: cstring) ---
	lua_rawset :: proc(L: ^lua_State, idx: i32) ---
	lua_rawseti :: proc(L: ^lua_State, idx: i32, n: i32) ---
	lua_rawsetptagged :: proc(L: ^lua_State, idx: i32, p: rawptr, tag: i32) ---
	lua_setmetatable :: proc(L: ^lua_State, objindex: i32) -> i32 ---
	lua_setfenv :: proc(L: ^lua_State, idx: i32) -> i32 ---


	luau_load :: proc(L: ^lua_State, chunkname: cstring, data: cstring, size: uintptr, env: i32) -> i32 ---
	lua_call :: proc(L: ^lua_State, nargs: i32, nresults: i32) ---
	lua_pcall :: proc(L: ^lua_State, nargs: i32, nresults: i32, errfunc: i32) -> i32 ---
	lua_cpcall :: proc(L: ^lua_State, func: lua_CFunction, ud: rawptr) -> i32 ---


	lua_callyieldable :: proc(L: ^lua_State, nargs: i32, nresults: i32) -> i32 ---
	lua_pcallyieldable :: proc(L: ^lua_State, nargs: i32, nresults: i32, errfunc: i32) -> i32 ---


	lua_yield :: proc(L: ^lua_State, nresults: i32) -> i32 ---
	lua_break :: proc(L: ^lua_State) -> i32 ---
	lua_resume :: proc(L: ^lua_State, from: ^lua_State, narg: i32) -> i32 ---
	lua_resumeerror :: proc(L: ^lua_State, from: ^lua_State) -> i32 ---
	lua_status :: proc(L: ^lua_State) -> i32 ---
	lua_isyieldable :: proc(L: ^lua_State) -> i32 ---
	lua_costatus :: proc(L: ^lua_State, co: ^lua_State) -> i32 ---
}


lua_GCOp :: enum i32 {
	STOP        = 0,
	RESTART     = 1,
	COLLECT     = 2,
	COUNT       = 3,
	COUNTB      = 4,
	ISRUNNING   = 5,
	STEP        = 6,
	SETGOAL     = 7,
	SETSTEPMUL  = 8,
	SETSTEPSIZE = 9,
	ISPAUSED    = 10,
}

@(default_calling_convention = "c")
foreign lib {
	lua_gc :: proc(L: ^lua_State, what: i32, data: i32) -> i32 ---
	lua_next :: proc(L: ^lua_State, idx: i32) -> i32 ---
}

lua_CategoryName :: proc "c" (L: ^lua_State, memcat: u8) -> cstring

@(default_calling_convention = "c", link_prefix = "kine_")
foreign lib {


	lua_memorydump :: proc(L: ^lua_State, file: rawptr, categoryName: lua_CategoryName) ---


	lua_setmemcat :: proc(L: ^lua_State, category: i32) ---
	lua_totalbytes :: proc(L: ^lua_State, category: i32) -> uintptr ---


	lua_allocationrate :: proc(L: ^lua_State) -> i64 ---


	lua_error :: proc(L: ^lua_State) -> i32 ---
	lua_rawiter :: proc(L: ^lua_State, idx: i32, iter: i32) -> i32 ---
	lua_concat :: proc(L: ^lua_State, n: i32) ---
	lua_setpointerencodekey :: proc(L: ^lua_State, a: u64, b: u64, _c: u64, d: u64) ---
	lua_encodepointer :: proc(L: ^lua_State, p: uintptr) -> uintptr ---
	lua_clock :: proc() -> f64 ---
	lua_setuserdatatag :: proc(L: ^lua_State, idx: i32, tag: i32) ---
}

lua_Destructor :: proc "c" (L: ^lua_State, userdata: rawptr)

@(default_calling_convention = "c", link_prefix = "kine_")
foreign lib {
	lua_setuserdatadtor :: proc(L: ^lua_State, tag: i32, dtor: lua_Destructor) ---
	lua_getuserdatadtor :: proc(L: ^lua_State, tag: i32) -> lua_Destructor ---
}


lua_UserdataMark :: proc "c" (L: ^lua_State, ud: rawptr)

@(default_calling_convention = "c")
foreign lib {
	lua_setuserdatamark :: proc(L: ^lua_State, tag: i32, markfn: lua_UserdataMark) ---
}

lua_EmbedderMark :: proc "c" (L: ^lua_State, ref: i32)
lua_EmbedderGc :: proc "c" (L: ^lua_State, markref: lua_EmbedderMark)

@(default_calling_convention = "c", link_prefix = "kine_")
foreign lib {
	lua_setembeddergc :: proc(L: ^lua_State, fn: lua_EmbedderGc) ---


	lua_weakref :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_weakunref :: proc(L: ^lua_State, ref: i32) -> i32 ---
	lua_getweakref :: proc(L: ^lua_State, ref: i32) -> i32 ---


	lua_setuserdatametatable :: proc(L: ^lua_State, tag: i32) ---
	lua_getuserdatametatable :: proc(L: ^lua_State, tag: i32) ---


	lua_getuserdataname :: proc(L: ^lua_State, tag: i32) -> cstring ---
}


lua_UserdataDirectAccess :: proc "c" (
	L: ^lua_State,
	data: rawptr,
	atom: i32,
	cachedslot: ^u16,
	utag: i32,
)
lua_UserdataDirectNamecall :: proc "c" (
	L: ^lua_State,
	data: rawptr,
	atom: i32,
	cachedslot: ^u16,
	utag: i32,
) -> i32

@(default_calling_convention = "c")
foreign lib {
	lua_registeruserdatadirectaccess :: proc(L: ^lua_State, tag: i32, get: lua_UserdataDirectAccess, set: lua_UserdataDirectAccess, namecall: lua_UserdataDirectNamecall) -> i32 ---
}


lua_UserdataDirectFieldGet :: proc "c" (ud: rawptr, result: rawptr)

@(default_calling_convention = "c")
foreign lib {
	lua_registeruserdatadirectfieldget :: proc(L: ^lua_State, tag: i32, field: cstring, fn: lua_UserdataDirectFieldGet) ---


	lua_userdatadirectfield_setnumber :: proc(result: rawptr, n: f64) ---
	lua_userdatadirectfield_setvector :: proc(result: rawptr, x: f32, y: f32, z: f32) ---
	lua_userdatadirectfield_setboolean :: proc(result: rawptr, b: i32) ---
	lua_userdatadirectfield_setinteger64 :: proc(result: rawptr, n: i64) ---
	lua_userdatadirectfield_setnil :: proc(result: rawptr) ---
	lua_setlightuserdataname :: proc(L: ^lua_State, tag: i32, name: cstring) ---
	lua_getlightuserdataname :: proc(L: ^lua_State, tag: i32) -> cstring ---
	lua_clonefunction :: proc(L: ^lua_State, idx: i32) ---
	lua_usesexport :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_cleartable :: proc(L: ^lua_State, idx: i32) ---
	lua_clonetable :: proc(L: ^lua_State, idx: i32) ---
	lua_getallocf :: proc(L: ^lua_State, ud: ^rawptr) -> lua_Alloc ---
}


LUA_NOREF :: -1
LUA_REFNIL :: 0

@(default_calling_convention = "c", link_prefix = "kine_")
foreign lib {
	lua_ref :: proc(L: ^lua_State, idx: i32) -> i32 ---
	lua_unref :: proc(L: ^lua_State, ref: i32) -> i32 ---
}


lua_Hook :: proc "c" (L: ^lua_State, ar: ^lua_Debug)

@(default_calling_convention = "c")
foreign lib {


	lua_callhook :: proc(L: ^lua_State, hook: lua_Hook, userdata: rawptr) ---
	lua_stackdepth :: proc(L: ^lua_State) -> i32 ---
	lua_getinfo :: proc(L: ^lua_State, level: i32, what: cstring, ar: ^lua_Debug) -> i32 ---
	lua_getargument :: proc(L: ^lua_State, level: i32, n: i32) -> i32 ---
	lua_getlocal :: proc(L: ^lua_State, level: i32, n: i32) -> cstring ---
	lua_setlocal :: proc(L: ^lua_State, level: i32, n: i32) -> cstring ---
	lua_getupvalue :: proc(L: ^lua_State, funcindex: i32, n: i32) -> cstring ---
	lua_setupvalue :: proc(L: ^lua_State, funcindex: i32, n: i32) -> cstring ---
	lua_hascustomexecution :: proc(L: ^lua_State, level: i32) -> i32 ---
	lua_incustomexecution :: proc(L: ^lua_State, level: i32) -> i32 ---
	lua_singlestep :: proc(L: ^lua_State, enabled: i32) ---
	lua_breakpoint :: proc(L: ^lua_State, funcindex: i32, line: i32, enabled: i32) -> i32 ---


	lua_atbreakpoint :: proc(L: ^lua_State) -> i32 ---


	lua_debugtrace :: proc(L: ^lua_State) -> cstring ---
}

lua_Debug :: struct {
	name:        cstring,
	what:        cstring,
	source:      cstring,
	short_src:   cstring,
	linedefined: i32,
	currentline: i32,
	protoid:     i32,
	bytecodeid:  i32,
	nupvals:     u8,
	nparams:     u8,
	isvararg:    i8,
	userdata:    rawptr,
	ssbuf:       [256]i8,
}

lua_Coverage :: proc "c" (
	_context: rawptr,
	function: cstring,
	linedefined: i32,
	depth: i32,
	hits: ^i32,
	size: uintptr,
)

@(default_calling_convention = "c")
foreign lib {
	lua_getcoverage :: proc(L: ^lua_State, funcindex: i32, _context: rawptr, callback: lua_Coverage) ---
}

lua_CounterFunction :: proc "c" (_context: rawptr, function: cstring, linedefined: i32)
lua_CounterValue :: proc "c" (_context: rawptr, kind: i32, line: i32, hits: u64)

@(default_calling_convention = "c")
foreign lib {


	lua_getcounters :: proc(L: ^lua_State, funcindex: i32, _context: rawptr, functionvisit: lua_CounterFunction, countervisit: lua_CounterValue) ---
}


lua_Callbacks :: struct {
	userdata:            rawptr,
	interrupt:           proc "c" (L: ^lua_State, gc: i32),
	panic:               proc "c" (L: ^lua_State, errcode: i32),
	userthread:          proc "c" (LP: ^lua_State, L: ^lua_State),
	useratom:            proc "c" (L: ^lua_State, s: cstring, l: uintptr) -> i16,
	debugbreak:          proc "c" (L: ^lua_State, ar: ^lua_Debug),
	debugstep:           proc "c" (L: ^lua_State, ar: ^lua_Debug),
	debuginterrupt:      proc "c" (L: ^lua_State, ar: ^lua_Debug),
	debugprotectederror: proc "c" (L: ^lua_State),
	onallocate:          proc "c" (
		L: ^lua_State,
		block: rawptr,
		osize: uintptr,
		nsize: uintptr,
		memcat: u8,
		tt: i32,
		tag: i32,
	),
	preresume:           proc "c" (L: ^lua_State),
	postresume:          proc "c" (L: ^lua_State),
	onfree:              proc "c" (L: ^lua_State, block: rawptr),
}

@(default_calling_convention = "c")
foreign lib {
	lua_callbacks :: proc(L: ^lua_State) -> ^lua_Callbacks ---
}
