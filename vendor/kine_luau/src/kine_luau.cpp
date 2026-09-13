#include "lua.h"
#include "lualib.h"
#include "luacode.h"
#include <cstdlib>

extern "C" {

lua_State* kine_luaL_newstate() { return luaL_newstate(); }
void kine_luaL_openlibs(lua_State* L) { luaL_openlibs(L); }
void kine_lua_close(lua_State* L) { lua_close(L); }
void kine_lua_setfield(lua_State* L, int index, const char* key) { lua_setfield(L, index, key); }
int kine_lua_setmetatable(lua_State* L, int index) { return lua_setmetatable(L, index); }
int kine_lua_setfenv(lua_State* L, int index) { return lua_setfenv(L, index); }
void kine_lua_pushnumber(lua_State* L, double value) { lua_pushnumber(L, value); }
void kine_lua_pushinteger64(lua_State* L, int64_t value) { lua_pushinteger64(L, value); }
void kine_lua_pushvector(lua_State* L, float x, float y, float z) { lua_pushvector(L, x, y, z); }
void kine_lua_pushboolean(lua_State* L, int value) { lua_pushboolean(L, value); }
void kine_lua_pushstring(lua_State* L, const char* value) { lua_pushstring(L, value); }
void kine_lua_pushnil(lua_State* L) { lua_pushnil(L); }
void kine_lua_pushlstring(lua_State* L, const char* value, size_t size) { lua_pushlstring(L, value, size); }
void kine_lua_pushcclosurek(lua_State* L, lua_CFunction function, const char* name, int upvalues, lua_Continuation continuation)
{
    lua_pushcclosurek(L, function, name, upvalues, continuation);
}
double kine_luaL_checknumber(lua_State* L, int index) { return luaL_checknumber(L, index); }
int64_t kine_luaL_checkinteger64(lua_State* L, int index) { return luaL_checkinteger64(L, index); }
int kine_luaL_checkboolean(lua_State* L, int index) { return luaL_checkboolean(L, index); }
const char* kine_luaL_checklstring(lua_State* L, int index, size_t* size) { return luaL_checklstring(L, index, size); }
const float* kine_luaL_checkvector(lua_State* L, int index) { return luaL_checkvector(L, index); }
void kine_lua_pushlightuserdatatagged(lua_State* L, void* value, int tag) { lua_pushlightuserdatatagged(L, value, tag); }
void* kine_lua_tolightuserdata(lua_State* L, int index) { return lua_tolightuserdata(L, index); }
void kine_lua_settop(lua_State* L, int index) { lua_settop(L, index); }
int kine_lua_gettop(lua_State* L) { return lua_gettop(L); }
int kine_lua_objlen(lua_State* L, int index) { return lua_objlen(L, index); }
void kine_lua_pushvalue(lua_State* L, int index) { lua_pushvalue(L, index); }
lua_State* kine_lua_newthread(lua_State* L) { return lua_newthread(L); }
lua_State* kine_lua_tothread(lua_State* L, int index) { return lua_tothread(L, index); }
int kine_lua_pushthread(lua_State* L) { return lua_pushthread(L); }
void kine_lua_xpush(lua_State* from, lua_State* to, int index) { lua_xpush(from, to, index); }
int kine_lua_isyieldable(lua_State* L) { return lua_isyieldable(L); }
int kine_lua_yield(lua_State* L, int results) { return lua_yield(L, results); }
int kine_lua_resume(lua_State* L, lua_State* from, int arguments) { return lua_resume(L, from, arguments); }
void kine_lua_resetthread(lua_State* L) { lua_resetthread(L); }
int kine_lua_type(lua_State* L, int index) { return lua_type(L, index); }
const char* kine_lua_typename(lua_State* L, int type) { return lua_typename(L, type); }
int kine_lua_isnumber(lua_State* L, int index) { return lua_isnumber(L, index); }
int kine_lua_isstring(lua_State* L, int index) { return lua_isstring(L, index); }
double kine_lua_tonumberx(lua_State* L, int index, int* isNumber) { return lua_tonumberx(L, index, isNumber); }
void kine_lua_createtable(lua_State* L, int arraySize, int hashSize) { lua_createtable(L, arraySize, hashSize); }
void kine_lua_setreadonly(lua_State* L, int index, int enabled) { lua_setreadonly(L, index, enabled); }
int kine_lua_getfield(lua_State* L, int index, const char* key) { return lua_getfield(L, index, key); }
void kine_lua_rawseti(lua_State* L, int index, int arrayIndex) { lua_rawseti(L, index, arrayIndex); }
int kine_lua_rawgeti(lua_State* L, int index, int arrayIndex) { return lua_rawgeti(L, index, arrayIndex); }
int kine_lua_ref(lua_State* L, int index) { return lua_ref(L, index); }
int kine_lua_unref(lua_State* L, int reference) { return lua_unref(L, reference); }
int kine_lua_error(lua_State* L)
{
    lua_error(L);
    return 0;
}
int kine_lua_userdatatag(lua_State* L, int index) { return lua_userdatatag(L, index); }
void* kine_lua_touserdata(lua_State* L, int index) { return lua_touserdata(L, index); }
const char* kine_lua_namecallatom(lua_State* L, int* atom) { return lua_namecallatom(L, atom); }
void kine_lua_getuserdatametatable(lua_State* L, int tag) { lua_getuserdatametatable(L, tag); }
void kine_lua_setuserdatametatable(lua_State* L, int tag) { lua_setuserdatametatable(L, tag); }
void kine_lua_setuserdatadtor(lua_State* L, int tag, lua_Destructor destructor) { lua_setuserdatadtor(L, tag, destructor); }
void* kine_lua_newuserdatataggedwithmetatable(lua_State* L, size_t size, int tag)
{
    return lua_newuserdatataggedwithmetatable(L, size, tag);
}
char* kine_luau_compile(const char* source, size_t size, lua_CompileOptions* options, size_t* outSize)
{
    return luau_compile(source, size, options, outSize);
}
void kine_luau_free(void* pointer) { std::free(pointer); }
int kine_luau_load(lua_State* L, const char* chunkName, const char* bytecode, size_t size, int environment)
{
    return luau_load(L, chunkName, bytecode, size, environment);
}
void* kine_lua_getthreaddata(lua_State* L)
{
    return lua_getthreaddata(L);
}

void kine_lua_setthreaddata(lua_State* L, void* data)
{
    lua_setthreaddata(L, data);
}

void kine_lua_setuserthreadcallback(
    lua_State* L,
    void (*callback)(lua_State*, lua_State*)
)
{
    lua_callbacks(L)->userthread = callback;
}
int kine_lua_getmetatable(lua_State* L, int index)
{
    return lua_getmetatable(L, index);
}
int kine_luaL_error(lua_State* L, const char* message)
{
    luaL_error(L, "%s", message);
    return 0;
}
int kine_lua_pcall(lua_State* L, int arguments, int results, int errorFunction)
{
    return lua_pcall(L, arguments, results, errorFunction);
}
const char* kine_lua_tolstring(lua_State* L, int index, size_t* size) { return lua_tolstring(L, index, size); }

}
