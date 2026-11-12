#include "lua.h"
#include "lualib.h"
#include "luacode.h"
#include "Luau/Lexer.h"
#include "Luau/Parser.h"

#include <cstdlib>
#include <new>
#include <cstring>
#include <string>
#include <unordered_set>

struct kine_luau_token
{
    int type;
    unsigned int begin;
    unsigned int end;
};

namespace
{
struct Kine_Luau_Lexer
{
    Luau::Allocator allocator;
    Luau::AstNameTable names;
    Luau::Lexer lexer;
    const char* text;
    size_t size;

    Kine_Luau_Lexer(const char* text, size_t size)
        : allocator(), names(allocator), lexer(text, size, names), text(text), size(size)
    {
    }
};

// AST locals already carry lexical identity. Only inspect statically known
// call targets; never execute user code or index userdata during diagnostics.
struct CallDefinitions : Luau::AstVisitor
{
    std::unordered_set<std::string> globals;
    bool visit(Luau::AstStatAssign* node) override
    {
        for (auto* var : node->vars)
            if (auto* global = var->as<Luau::AstExprGlobal>()) globals.insert(global->name.value);
        return true;
    }
    bool visit(Luau::AstStatFunction* node) override
    {
        if (auto* global = node->name->as<Luau::AstExprGlobal>()) globals.insert(global->name.value);
        return true;
    }
};

struct CallDiagnostics : Luau::AstVisitor
{
    lua_State* L;
    const CallDefinitions& definitions;
    std::string message;
    unsigned line = 0;

    CallDiagnostics(lua_State* L, const CallDefinitions& definitions) : L(L), definitions(definitions) {}

    Luau::AstExpr* unwrap(Luau::AstExpr* expr)
    {
        for (;;)
            if (auto* group = expr->as<Luau::AstExprGroup>()) expr = group->expr;
            else if (auto* assertion = expr->as<Luau::AstExprTypeAssertion>()) expr = assertion->expr;
            else return expr;
    }

    // Leaves a value only when a target can be resolved without running code.
    bool resolve(Luau::AstExpr* expr, std::string& name)
    {
        expr = unwrap(expr);
        if (auto* global = expr->as<Luau::AstExprGlobal>())
        {
            name = global->name.value;
            if (definitions.globals.count(name)) return false;
            lua_pushstring(L, name.c_str());
            lua_rawget(L, LUA_GLOBALSINDEX);
            return true;
        }
        if (auto* index = expr->as<Luau::AstExprIndexName>())
        {
            if (!resolve(index->expr, name)) return false;
            if (!lua_istable(L, -1))
            {
                // Userdata members require engine reflection; leave them dynamic.
                const bool dynamic = lua_isuserdata(L, -1);
                lua_pop(L, 1);
                if (dynamic) return false;
                name += ".";
                name += index->index.value;
                lua_pushnil(L);
                return true;
            }
            name += ".";
            name += index->index.value;
            lua_pushstring(L, index->index.value);
            lua_rawget(L, -2);
            lua_remove(L, -2);
            return true;
        }
        if (expr->is<Luau::AstExprConstantNil>()) { name = "nil"; lua_pushnil(L); return true; }
        if (expr->is<Luau::AstExprConstantNumber>() || expr->is<Luau::AstExprConstantString>() ||
            expr->is<Luau::AstExprConstantBool>()) { name = "literal"; lua_pushboolean(L, false); return true; }
        return false;
    }

    void check(Luau::AstExpr* expr)
    {
        if (!message.empty()) return;
        std::string name;
        if (!resolve(expr, name)) return;
        const int type = lua_type(L, -1);
        // Tables and userdata may implement __call; their callability is dynamic.
        if (type != LUA_TFUNCTION && type != LUA_TTABLE && type != LUA_TUSERDATA)
        {
            line = expr->location.begin.line + 1;
            message = "Cannot call '" + name + "' (" + lua_typename(L, type) + ")";
        }
        lua_pop(L, 1);
    }

    bool visit(Luau::AstExprCall* node) override
    {
        check(node->func);
        auto* global = unwrap(node->func)->as<Luau::AstExprGlobal>();
        if (global && !definitions.globals.count(global->name.value) &&
            (strcmp(global->name.value, "pcall") == 0 || strcmp(global->name.value, "xpcall") == 0))
        {
            if (node->args.size == 0 && message.empty())
            {
                line = node->location.begin.line + 1;
                message = std::string(global->name.value) + " requires a function argument";
            }
            else if (node->args.size > 0) check(node->args.data[0]);
            if (strcmp(global->name.value, "xpcall") == 0 && message.empty())
            {
                if (node->args.size < 2) {line = node->location.begin.line + 1; message = "xpcall requires an error handler";}
                else check(node->args.data[1]);
            }
        }
        return message.empty();
    }
};
}

extern "C" {

char* kine_luau_diagnose_calls(lua_State* L, const char* text, size_t size, unsigned* line)
{
    try
    {
        Luau::Allocator allocator;
        Luau::AstNameTable names(allocator);
        auto result = Luau::Parser::parse(text, size, names, allocator);
        if (!result.root || !result.errors.empty()) return nullptr;
        CallDefinitions definitions;
        result.root->visit(&definitions);
        CallDiagnostics diagnostics(L, definitions);
        result.root->visit(&diagnostics);
        if (diagnostics.message.empty()) return nullptr;
        char* message = static_cast<char*>(malloc(diagnostics.message.size() + 1));
        if (!message) return nullptr;
        memcpy(message, diagnostics.message.c_str(), diagnostics.message.size() + 1);
        *line = diagnostics.line;
        return message;
    }
    catch (...) { return nullptr; }
}

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
int kine_lua_checkstack(lua_State* L, int size) { return lua_checkstack(L, size); }
void kine_lua_pushvalue(lua_State* L, int index) { lua_pushvalue(L, index); }
void kine_lua_remove(lua_State* L, int index) { lua_remove(L, index); }
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
int kine_lua_pcallyieldable(
    lua_State* L,
    int arguments,
    int results,
    int errorFunction
)
{
    return lua_pcallyieldable(L, arguments, results, errorFunction);
}

void kine_luaL_traceback(
    lua_State* L,
    lua_State* L1,
    const char* message,
    int level
)
{
    luaL_traceback(L, L1, message, level);
}

int kine_lua_costatus(
    lua_State* L,
    lua_State* co
)
{
    return lua_costatus(L, co);
}
int kine_lua_error(lua_State* L)

{
    lua_error(L);
    return 0;
}
int kine_lua_userdatatag(lua_State* L, int index) { return lua_userdatatag(L, index); }
void* kine_lua_touserdata(lua_State* L, int index) { return lua_touserdata(L, index); }
// Views a Luau buffer's bytes, which is how raw font data handed over by script
// reaches the engine. The returned pointer is owned by the buffer, so it stays
// valid only while that buffer is reachable.
void* kine_lua_tobuffer(lua_State* L, int index, size_t* size) { return lua_tobuffer(L, index, size); }
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
const char* kine_luaL_tolstring(lua_State* L, int index, size_t* size)
{
    return luaL_tolstring(L, index, size);
}

int kine_lua_absindex(lua_State* L, int index)
{
    return lua_absindex(L, index);
}
int kine_lua_pcall(lua_State* L, int arguments, int results, int errorFunction)
{
    return lua_pcall(L, arguments, results, errorFunction);
}
const char* kine_lua_tolstring(lua_State* L, int index, size_t* size) { return lua_tolstring(L, index, size); }

void kine_luau_visit_string_literals(
    const char* source, size_t size, void (*visit)(const char*, size_t, void*), void* userData)
{
    Kine_Luau_Lexer scan(source, size);
    while (true)
    {
        const Luau::Lexeme& token = scan.lexer.next();
        if (token.type == Luau::Lexeme::Eof)
            break;
        if (token.type != Luau::Lexeme::QuotedString && token.type != Luau::Lexeme::RawString &&
            token.type != Luau::Lexeme::InterpStringSimple)
            continue;

        std::string value(token.data, token.getLength());
        if (token.type == Luau::Lexeme::RawString)
            Luau::Lexer::fixupMultilineString(value);
        else if (!Luau::Lexer::fixupQuotedString(value))
            continue;
        visit(value.data(), value.size(), userData);
    }
}

void* kine_luau_lexer_create(const char* text, size_t size)
{
    try
    {
        return new Kine_Luau_Lexer(text, size);
    }
    catch (...)
    {
        return nullptr;
    }
}

void kine_luau_lexer_destroy(void* handle)
{
    delete static_cast<Kine_Luau_Lexer*>(handle);
}

kine_luau_token kine_luau_lexer_next(void* handle)
{
    kine_luau_token token = {0, 0, 0};
    Kine_Luau_Lexer* lexer = static_cast<Kine_Luau_Lexer*>(handle);
    if (!lexer)
        return token;

    unsigned int cursor = lexer->lexer.getOffset();
    (void)lexer->lexer.next();
    token.type = static_cast<int>(lexer->lexer.current().type);
    token.end = lexer->lexer.getOffset();

    token.begin = cursor;

    // next() consumes leading whitespace before producing a lexeme, so scan
    // past it to find the token's first byte.
    while (token.begin < token.end && token.begin < lexer->size && Luau::isSpace(lexer->text[token.begin]))
        token.begin++;

    return token;
}

}
