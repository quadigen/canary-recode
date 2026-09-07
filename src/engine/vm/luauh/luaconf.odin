// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
package luauh

LUA_USE_LONGJMP                :: 0
LUA_IDSIZE                     :: 256
LUA_MINSTACK                   :: 20
LUAI_MAXCSTACK                 :: 8000
LUAI_MAXCALLS                  :: 20000
LUAI_MAXCCALLS                 :: 200
LUA_BUFFERSIZE                 :: 512
LUA_UTAG_LIMIT                 :: 128
LUA_LUTAG_LIMIT                :: 128
LUA_SIZECLASSES                :: 40
LUA_MEMORY_CATEGORIES          :: 256
LUA_EXECUTION_CALLBACK_STORAGE :: 512
LUA_MINSTRTABSIZE              :: 32
LUA_MAXCAPTURES                :: 32
LUA_VECTOR_SIZE                :: 3 // must be 3 or 4
LUA_VECTOR_DOUBLE              :: 0
LUA_EXTRA_SIZE                 :: (LUA_VECTOR_SIZE-2)

