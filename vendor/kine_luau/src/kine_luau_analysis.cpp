#include "lua.h"
#include "Luau/BuiltinDefinitions.h"
#include "Luau/Frontend.h"
#include "Luau/Parser.h"
#include "Luau/Type.h"

#include <string_view>
#include <unordered_map>

namespace
{
constexpr std::string_view RootName = "@editor";
constexpr size_t MaxSourceBytes = 512 * 1024;
constexpr size_t MaxTotalBytes = 2 * 1024 * 1024;
constexpr size_t MaxModules = 64;
constexpr size_t MaxResolutions = 512;

struct EditorResolver final : Luau::FileResolver
{
    lua_State* state;
    int callback;
    std::unordered_map<std::string, Luau::SourceCode> sources;
    size_t totalBytes;
    size_t resolutions = 0;

    EditorResolver(lua_State* state, int callback, std::string_view source)
        : state(state), callback(lua_absindex(state, callback)), totalBytes(source.size())
    {
        sources.emplace(RootName, Luau::SourceCode{std::string(source), Luau::SourceCode::Module});
    }

    std::optional<Luau::SourceCode> readSource(const Luau::ModuleName& name) override
    {
        const auto found = sources.find(name);
        if (found == sources.end())
            return std::nullopt;
        return found->second;
    }

    std::optional<Luau::ModuleInfo> resolveModule(
        const Luau::ModuleInfo* context, Luau::AstExpr* expr, const Luau::TypeCheckLimits&) override
    {
        if (!context || lua_type(state, callback) != LUA_TFUNCTION || resolutions++ >= MaxResolutions)
            return std::nullopt;

        std::string_view operation;
        std::string_view argument;
        if (const auto* global = expr->as<Luau::AstExprGlobal>())
        {
            operation = "global";
            argument = global->name.value;
        }
        else if (const auto* member = expr->as<Luau::AstExprIndexName>())
        {
            operation = "member";
            argument = member->index.value;
        }
        else if (const auto* index = expr->as<Luau::AstExprIndexExpr>())
        {
            const auto* name = index->index->as<Luau::AstExprConstantString>();
            if (!name)
                return std::nullopt;
            operation = "member";
            argument = {name->value.data, name->value.size};
        }
        else if (const auto* path = expr->as<Luau::AstExprConstantString>())
        {
            operation = "path";
            argument = {path->value.data, path->value.size};
        }
        else if (const auto* call = expr->as<Luau::AstExprCall>(); call && call->self && call->args.size > 0)
        {
            const auto* method = call->func->as<Luau::AstExprIndexName>();
            const auto* name = call->args.data[0]->as<Luau::AstExprConstantString>();
            if (!method || !name)
                return std::nullopt;
            operation = method->index.value;
            if (operation != "GetService" && operation != "FindFirstChild" && operation != "WaitForChild")
                return std::nullopt;
            argument = {name->value.data, name->value.size};
        }
        else
            return std::nullopt;

        int top = lua_gettop(state);
        lua_pushvalue(state, callback);
        lua_pushlstring(state, context->name.data(), context->name.size());
        lua_pushlstring(state, operation.data(), operation.size());
        lua_pushlstring(state, argument.data(), argument.size());
        std::optional<Luau::ModuleInfo> result;
        if (lua_pcall(state, 3, 2, 0) == 0 && lua_type(state, -2) == LUA_TSTRING)
        {
            size_t nameSize = 0;
            const char* nameData = lua_tolstring(state, -2, &nameSize);
            if (nameSize > 0 && nameSize <= 256)
            {
                std::string name(nameData, nameSize);
                if (sources.contains(name) || lua_type(state, -1) == LUA_TNIL)
                    result = Luau::ModuleInfo{name};
                else if (sources.size() < MaxModules && lua_type(state, -1) == LUA_TSTRING)
                {
                    size_t size = 0;
                    const char* text = lua_tolstring(state, -1, &size);
                    if (size <= MaxSourceBytes && totalBytes + size <= MaxTotalBytes)
                    {
                        sources.emplace(name, Luau::SourceCode{std::string(text, size), Luau::SourceCode::Module});
                        totalBytes += size;
                        result = Luau::ModuleInfo{std::move(name)};
                    }
                }
            }
        }
        lua_settop(state, top);
        return result;
    }
};

void setInteger(lua_State* state, const char* key, unsigned value)
{
    lua_pushinteger(state, int(value));
    lua_setfield(state, -2, key);
}

void pushDiagnostic(lua_State* state, Luau::Location location, const char* kind, std::string_view message)
{
    lua_newtable(state);
    setInteger(state, "Line", location.begin.line + 1);
    setInteger(state, "Column", location.begin.column + 1);
    setInteger(state, "EndLine", location.end.line + 1);
    setInteger(state, "EndColumn", location.end.column + 1);
    lua_pushstring(state, kind);
    lua_setfield(state, -2, "Kind");
    lua_pushlstring(state, message.data(), message.size());
    lua_setfield(state, -2, "Message");
}
} // namespace

extern "C" int kine_luau_typecheck(lua_State* state, const char* text, size_t size, int callback)
{
    if (size > MaxSourceBytes)
        return 0;

    const int top = lua_gettop(state);
    try
    {
        EditorResolver resolver(state, callback, std::string_view(text, size));
        Luau::NullConfigResolver config;
        config.defaultConfig.mode = Luau::Mode::Strict;
        Luau::FrontendOptions options;
        options.moduleTimeLimitSec = 0.1;
        options.runLintChecks = true;
        Luau::Frontend frontend(Luau::SolverMode::New, &resolver, &config, options);
        Luau::registerBuiltinGlobals(frontend, frontend.globals);
        for (const char* name : {"game", "workspace", "script", "Instance", "Enum", "shared", "task",
                 "Vector2", "Vector3", "CFrame", "Color3", "BrickColor", "UDim", "UDim2", "TweenInfo",
                 "Ray", "Region3", "Rect", "Random", "DateTime", "NumberRange", "NumberSequence",
                 "ColorSequence", "PhysicalProperties", "RaycastParams", "OverlapParams", "warn", "typeof",
                 "IsClient", "IsServer", "IsPlaytest"})
            if (!Luau::tryGetGlobalBinding(frontend.globals, name))
                Luau::addGlobalBinding(frontend.globals, name, frontend.builtinTypes->anyType, "Kinemium");
        Luau::freeze(frontend.globals.globalTypes);

        Luau::CheckResult result = frontend.check(std::string(RootName));
        lua_newtable(state);
        int index = 0;
        for (const Luau::TypeError& error : result.errors)
        {
            if (error.moduleName != RootName || Luau::get<Luau::UnknownRequire>(error) || index >= 100)
                continue;

            pushDiagnostic(state, error.location, Luau::get<Luau::SyntaxError>(error) ? "Syntax error" : "Type error",
                Luau::toString(error));
            lua_rawseti(state, -2, ++index);
        }
        for (const Luau::LintWarning& warning : result.lintResult.warnings)
        {
            if (index >= 100)
                break;
            pushDiagnostic(state, warning.location, "Lint warning", warning.text);
            lua_pushstring(state, Luau::LintWarning::getName(warning.code));
            lua_setfield(state, -2, "Rule");
            lua_rawseti(state, -2, ++index);
        }
        return 1;
    }
    catch (...)
    {
        lua_settop(state, top);
        return 0;
    }
}

extern "C" int kine_luau_exported_types(lua_State* state, const char* text, size_t size)
{
    if (size > MaxSourceBytes)
        return 0;
    const int top = lua_gettop(state);
    try
    {
        Luau::Allocator allocator;
        Luau::AstNameTable names(allocator);
        auto parsed = Luau::Parser::parse(text, size, names, allocator);
        lua_newtable(state);
        int index = 0;
        if (parsed.root)
        {
            for (const Luau::AstStat* statement : parsed.root->body)
            {
                const char* name = nullptr;
                if (const auto* alias = statement->as<Luau::AstStatTypeAlias>(); alias && alias->exported)
                    name = alias->name.value;
                else if (const auto* fn = statement->as<Luau::AstStatTypeFunction>(); fn && fn->exported && !fn->hasErrors)
                    name = fn->name.value;
                if (!name)
                    continue;
                lua_pushstring(state, name);
                lua_rawseti(state, -2, ++index);
            }
        }
        return 1;
    }
    catch (...)
    {
        lua_settop(state, top);
        return 0;
    }
}

extern "C" int kine_luau_lint_rules(lua_State* state)
{
    lua_newtable(state);
    for (int i = 1; i < Luau::LintWarning::Code__Count; ++i)
    {
        lua_pushstring(state, Luau::LintWarning::getName(static_cast<Luau::LintWarning::Code>(i)));
        lua_rawseti(state, -2, i);
    }
    return 1;
}
