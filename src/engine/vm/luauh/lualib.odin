// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
package luauh

import "core:c"

when ODIN_OS == .Windows {
	foreign import lib {
		"../../../../vendor/build/lib/kine_luau.lib",
		"../../../../build/vendor/luau/Luau.VM.lib",
	}
} else {
	foreign import lib "system:Luau.VM"
}

luaL_Reg :: struct {
	name: cstring,
	func: lua_CFunction,
}

@(default_calling_convention="c", link_prefix="kine_")
foreign lib {
	luaL_register         :: proc(L: ^lua_State, libname: cstring, l: ^luaL_Reg) ---
	luaL_getmetafield     :: proc(L: ^lua_State, obj: i32, e: cstring) -> i32 ---
	luaL_callmeta         :: proc(L: ^lua_State, obj: i32, e: cstring) -> i32 ---
	luaL_typeerrorL       :: proc(L: ^lua_State, narg: i32, tname: cstring) ---
	luaL_argerrorL        :: proc(L: ^lua_State, narg: i32, extramsg: cstring) ---
	luaL_checklstring     :: proc(L: ^lua_State, numArg: i32, l: ^c.size_t) -> cstring ---
	luaL_optlstring       :: proc(L: ^lua_State, numArg: i32, def: cstring, l: ^c.size_t) -> cstring ---
	luaL_checknumber      :: proc(L: ^lua_State, numArg: i32) -> f64 ---
	luaL_optnumber        :: proc(L: ^lua_State, nArg: i32, def: f64) -> f64 ---
	luaL_checkboolean     :: proc(L: ^lua_State, narg: i32) -> i32 ---
	luaL_optboolean       :: proc(L: ^lua_State, narg: i32, def: i32) -> i32 ---
	luaL_checkinteger     :: proc(L: ^lua_State, numArg: i32) -> i32 ---
	luaL_checkinteger64   :: proc(L: ^lua_State, numArg: i32) -> i64 ---
	luaL_optinteger       :: proc(L: ^lua_State, nArg: i32, def: i32) -> i32 ---
	luaL_optinteger64     :: proc(L: ^lua_State, nArg: i32, def: i64) -> i64 ---
	luaL_checkunsigned    :: proc(L: ^lua_State, numArg: i32) -> u32 ---
	luaL_optunsigned      :: proc(L: ^lua_State, numArg: i32, def: u32) -> u32 ---
	luaL_checkvector      :: proc(L: ^lua_State, narg: i32) -> ^f32 ---
	luaL_optvector        :: proc(L: ^lua_State, narg: i32, def: ^f32) -> ^f32 ---
	luaL_checkstack       :: proc(L: ^lua_State, sz: i32, msg: cstring) ---
	luaL_checktype        :: proc(L: ^lua_State, narg: i32, t: i32) ---
	luaL_checkany         :: proc(L: ^lua_State, narg: i32) ---
	luaL_newmetatable     :: proc(L: ^lua_State, tname: cstring) -> i32 ---
	luaL_checkudata       :: proc(L: ^lua_State, ud: i32, tname: cstring) -> rawptr ---
	luaL_checkudatatagged :: proc(L: ^lua_State, ud: i32, tag: i32) -> rawptr ---
	luaL_checkbuffer      :: proc(L: ^lua_State, narg: i32, len: ^c.size_t) -> rawptr ---
	luaL_where            :: proc(L: ^lua_State, lvl: i32) ---
	luaL_errorL           :: proc(L: ^lua_State, fmt: cstring, #c_vararg _: ..any) ---
	luaL_checkoption      :: proc(L: ^lua_State, narg: i32, def: cstring, lst: [^]cstring) -> i32 ---
	luaL_tolstring        :: proc(L: ^lua_State, idx: i32, len: ^c.size_t) -> cstring ---
	luaL_newstate         :: proc() -> ^lua_State ---
	luaL_findtable        :: proc(L: ^lua_State, idx: i32, fname: cstring, szhint: i32) -> cstring ---
	luaL_typename         :: proc(L: ^lua_State, idx: i32) -> cstring ---
	luaL_traceback        :: proc(L: ^lua_State, L1: ^lua_State, msg: cstring, level: i32) ---
}

// generic buffer manipulation
luaL_Strbuf :: struct {
	p:       cstring, // current position in buffer
	end:     cstring, // end of the current buffer
	L:       ^lua_State,
	storage: ^TString,
	buffer:  [512]i8,
}

TString :: struct {}

// compatibility typedef: this type is called luaL_Buffer in Lua headers
// renamed to luaL_Strbuf to reduce confusion with internal VM buffer type
luaL_Buffer :: luaL_Strbuf

@(default_calling_convention="c")
foreign lib {
	luaL_buffinit       :: proc(L: ^lua_State, B: ^luaL_Strbuf) ---
	luaL_buffinitsize   :: proc(L: ^lua_State, B: ^luaL_Strbuf, size: c.size_t) -> cstring ---
	luaL_prepbuffsize   :: proc(B: ^luaL_Buffer, size: c.size_t) -> cstring ---
	luaL_addlstring     :: proc(B: ^luaL_Strbuf, s: cstring, l: c.size_t) ---
	luaL_addvalue       :: proc(B: ^luaL_Strbuf) ---
	luaL_addvalueany    :: proc(B: ^luaL_Strbuf, idx: i32) ---
	luaL_pushresult     :: proc(B: ^luaL_Strbuf) ---
	luaL_pushresultsize :: proc(B: ^luaL_Strbuf, size: c.size_t) ---

	// builtin libraries
	luaopen_base :: proc(L: ^lua_State) -> i32 ---
}

LUA_COLIBNAME :: "coroutine"

@(default_calling_convention="c")
foreign lib {
	luaopen_coroutine :: proc(L: ^lua_State) -> i32 ---
}

LUA_TABLIBNAME :: "table"

@(default_calling_convention="c")
foreign lib {
	luaopen_table :: proc(L: ^lua_State) -> i32 ---
}

LUA_OSLIBNAME :: "os"

@(default_calling_convention="c")
foreign lib {
	luaopen_os :: proc(L: ^lua_State) -> i32 ---
}

LUA_STRLIBNAME :: "string"

@(default_calling_convention="c")
foreign lib {
	luaopen_string :: proc(L: ^lua_State) -> i32 ---
}

LUA_BITLIBNAME :: "bit32"

@(default_calling_convention="c")
foreign lib {
	luaopen_bit32 :: proc(L: ^lua_State) -> i32 ---
}

LUA_BUFFERLIBNAME :: "buffer"

@(default_calling_convention="c")
foreign lib {
	luaopen_buffer :: proc(L: ^lua_State) -> i32 ---
}

LUA_UTF8LIBNAME :: "utf8"

@(default_calling_convention="c")
foreign lib {
	luaopen_utf8 :: proc(L: ^lua_State) -> i32 ---
}

LUA_CLASSLIBNAME :: "class"

@(default_calling_convention="c")
foreign lib {
	luaopen_class :: proc(L: ^lua_State) -> i32 ---
}

LUA_MATHLIBNAME :: "math"

@(default_calling_convention="c")
foreign lib {
	luaopen_math :: proc(L: ^lua_State) -> i32 ---
}

LUA_DBLIBNAME :: "debug"

@(default_calling_convention="c")
foreign lib {
	luaopen_debug :: proc(L: ^lua_State) -> i32 ---
}

LUA_VECLIBNAME :: "vector"

@(default_calling_convention="c")
foreign lib {
	luaopen_vector :: proc(L: ^lua_State) -> i32 ---
}

LUA_INTLIBNAME :: "integer"

@(default_calling_convention="c", link_prefix="kine_")
foreign lib {
	luaopen_integer :: proc(L: ^lua_State) -> i32 ---

	// open all builtin libraries
	luaL_openlibs :: proc(L: ^lua_State) ---

	// sandbox libraries and globals
	luaL_sandbox       :: proc(L: ^lua_State) ---
	luaL_sandboxthread :: proc(L: ^lua_State) ---
}

