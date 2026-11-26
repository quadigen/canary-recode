#include "lua.h"
#include "Luau/BuiltinDefinitions.h"
#include "Luau/Frontend.h"
#include "Luau/Parser.h"
#include "Luau/Type.h"
#include "Luau/ConstraintSolver.h"
#include "Luau/TypeInfer.h"
#include "Luau/TypePack.h"
#include "Luau/Scope.h"
#include <algorithm>
#include <span>
#include <cstdio>
#include <memory>
#include "kinemium_api_generated.h"

#include <string_view>
#include <unordered_map>

namespace
{
constexpr std::string_view RootName = "@editor";
constexpr size_t MaxSourceBytes = 512 * 1024;
constexpr size_t MaxTotalBytes = 2 * 1024 * 1024;
constexpr size_t MaxModules = 64;
constexpr size_t MaxResolutions = 512;

const std::string& apiDefinitions()
{
    static const std::string text = [] {
        std::string result;
        for (auto chunk : KinemiumDefinitionChunks)
            result.append(chunk);
        return result;
    }();
    return text;
}

struct KinemiumClassLookup final : Luau::MagicFunction
{
    std::span<const std::string_view> names;
    bool optional;

    KinemiumClassLookup(std::span<const std::string_view> names, bool optional = false)
        : names(names), optional(optional)
    {
    }

    std::optional<Luau::WithPredicate<Luau::TypePackId>> handleOldSolver(
        Luau::TypeChecker&, const Luau::ScopePtr&, const Luau::AstExprCall&, Luau::WithPredicate<Luau::TypePackId>) override
    {
        return std::nullopt;
    }

    bool infer(const Luau::MagicFunctionCallContext& context) override
    {
        if (context.callSite->args.size == 0)
            return false;
        const auto* literal = context.callSite->args.data[0]->as<Luau::AstExprConstantString>();
        if (!literal)
            return false;
        const std::string_view name(literal->value.data, literal->value.size);
        if (!names.empty() && std::find(names.begin(), names.end(), name) == names.end())
            return false;
        auto type = context.solver->rootScope->lookupType(name == "Animated" && !names.empty() ? "AnimatedImageInstance" : std::string(name));
        if (!type || !type->typeParams.empty() || !type->typePackParams.empty())
            return false;
        auto ty = Luau::follow(type->type);
        if (!Luau::get<Luau::ExternType>(ty))
            return false;
        if (optional)
            ty = Luau::makeOption(context.solver->builtinTypes, *context.solver->arena, ty);
        asMutable(context.result)->ty.emplace<Luau::BoundTypePack>(context.solver->arena->addTypePack({ty}));
        return true;
    }
};

void attachClassLookup(Luau::GlobalTypes& globals, const char* className, const char* member,
    std::span<const std::string_view> names, bool optional = false)
{
    auto type = globals.globalScope->lookupType(className);
    if (!type)
        return;
    if (auto* external = Luau::getMutable<Luau::ExternType>(type->type))
    {
        auto property = external->props.find(member);
        if (property != external->props.end() && property->second.readTy && Luau::get<Luau::FunctionType>(*property->second.readTy))
            Luau::attachMagicFunction(*property->second.readTy, std::make_shared<KinemiumClassLookup>(names, optional));
    }
}

bool loadKinemiumApi(Luau::Frontend& frontend)
{
    auto result = frontend.loadDefinitionFile(frontend.globals, frontend.globals.globalScope, apiDefinitions(), "@kinemium", false);
    if (!result.success)
    {
        for (const auto& error : result.parseResult.errors)
            std::fprintf(stderr, "[Luau API] %u: %s\n", error.getLocation().begin.line + 1, error.what());
        if (result.module)
            for (const auto& error : result.module->errors)
                std::fprintf(stderr, "[Luau API] %u: %s\n", error.location.begin.line + 1, Luau::toString(error).c_str());
        return false;
    }
    if (auto binding = Luau::tryGetGlobalBinding(frontend.globals, "Instance"))
        if (const auto* table = Luau::get<Luau::TableType>(binding->typeId))
            if (auto it = table->props.find("new"); it != table->props.end() && it->second.readTy)
                Luau::attachMagicFunction(*it->second.readTy, std::make_shared<KinemiumClassLookup>(CREATABLE_INSTANCES));
    auto& globals = frontend.globals;
    if (auto model = globals.globalScope->lookupType("DataModel"))
        if (auto* external = Luau::getMutable<Luau::ExternType>(model->type))
            for (auto name : SERVICES)
                if (auto type = globals.globalScope->lookupType(std::string(name)))
                    external->props.emplace(std::string(name), Luau::Property::readonly(type->type));
    auto& enumTypes = globals.globalScope->importedTypeBindings["Enum"];
    for (const auto& [name, type] : globals.globalScope->exportedTypeBindings)
        if (name.starts_with("Enum") && name != "Enum" && name != "EnumItem" && !name.ends_with("_INTERNAL"))
            if (Luau::get<Luau::ExternType>(type.type))
                enumTypes.emplace(name.substr(4), type);
    attachClassLookup(frontend.globals, "DataModel", "GetService", SERVICES);
    attachClassLookup(frontend.globals, "DataModel", "FindService", SERVICES, true);
    for (const char* method : {"FindFirstChildOfClass", "FindFirstChildWhichIsA", "FindFirstAncestorOfClass", "FindFirstAncestorWhichIsA", "WaitForChildOfClass"})
        attachClassLookup(frontend.globals, "Instance", method, {}, true);
    return true;
}

struct EditorResolver final : Luau::FileResolver
{
    lua_State* state;
    int callback;
    std::unordered_map<std::string, Luau::SourceCode> sources;
    size_t totalBytes;
    size_t resolutions = 0;

    EditorResolver() : state(nullptr), callback(0), totalBytes(0)
    {
    }

    void reset(lua_State* nextState, int nextCallback, std::string_view source)
    {
        state = nextState;
        callback = lua_absindex(state, nextCallback);
        sources.clear();
        totalBytes = source.size();
        resolutions = 0;
        sources.emplace(RootName, Luau::SourceCode{std::string(source), Luau::SourceCode::Module});
    }

    void clear()
    {
        sources.clear();
        state = nullptr;
        callback = 0;
        totalBytes = 0;
        resolutions = 0;
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

Luau::FrontendOptions analysisOptions()
{
    Luau::FrontendOptions options;
    options.moduleTimeLimitSec = 0.1;
    options.runLintChecks = true;
    options.retainFullTypeGraphs = true;
    return options;
}

struct AnalysisSession
{
    EditorResolver resolver;
    Luau::NullConfigResolver config;
    Luau::Frontend frontend;
    bool initialized;

    AnalysisSession()
        : frontend(Luau::SolverMode::New, &resolver, &config, analysisOptions())
    {
        config.defaultConfig.mode = Luau::Mode::Strict;
        Luau::registerBuiltinGlobals(frontend, frontend.globals);
        initialized = loadKinemiumApi(frontend);
        for (const char* name : {"game", "workspace", "script", "Instance", "Enum", "shared", "task",
                 "Vector2", "Vector3", "CFrame", "Color3", "BrickColor", "UDim", "UDim2", "TweenInfo",
                 "Ray", "Region3", "Rect", "Random", "DateTime", "NumberRange", "NumberSequence",
                 "ColorSequence", "PhysicalProperties", "RaycastParams", "OverlapParams", "warn", "typeof",
                 "IsClient", "IsServer", "IsPlaytest"})
            if (!Luau::tryGetGlobalBinding(frontend.globals, name))
                Luau::addGlobalBinding(frontend.globals, name, frontend.builtinTypes->anyType, "Kinemium");
        Luau::freeze(frontend.globals.globalTypes);
    }

    void clear()
    {
        frontend.clear();
        frontend.clearStats();
        resolver.clear();
    }
};

thread_local std::unique_ptr<AnalysisSession> cachedAnalysis;

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
}

extern "C" int kine_luau_typecheck(lua_State* state, const char* text, size_t size, int callback)
{
    if (size > MaxSourceBytes)
        return 0;

    const int top = lua_gettop(state);
    try
    {
        auto analysis = std::move(cachedAnalysis);
        if (!analysis)
            analysis = std::make_unique<AnalysisSession>();
        if (!analysis->initialized)
            return 0;
        analysis->resolver.reset(state, callback, std::string_view(text, size));
        auto& frontend = analysis->frontend;
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
        analysis->clear();
        cachedAnalysis = std::move(analysis);
        return 1;
    }
    catch (...)
    {
        lua_settop(state, top);
        return 0;
    }
}

extern "C" int kine_luau_api_definitions(lua_State* state)
{
    const auto& text = apiDefinitions();
    lua_pushlstring(state, text.data(), text.size());
    return 1;
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
