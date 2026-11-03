#+build !js
package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	defer {
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
	}

	ok, err := vm.Run(&script_vm, `
local service = game:GetService("LuauService")
local sourceOfModule = "return 1"
local function resolve(context, operation, name)
	if operation == "global" and name == "script" then
		return context
	elseif operation == "member" and name == "Parent" then
		return "folder"
	elseif context == "folder" and name == "Numbers" then
		return "Numbers", sourceOfModule
	elseif context == "folder" and name == "Inner (test)" then
		return "Inner", "return { value = 42 }"
	elseif context == "folder" and name == "Consumer" then
		return "@editor"
	end
end

local function check(source, count)
	local result = service:TypeCheck(source, resolve)
	assert(type(result) == "table")
	local diagnostics = {}
	for _, diagnostic in ipairs(result) do
		if diagnostic.Kind ~= "Lint warning" then
			table.insert(diagnostics, diagnostic)
		end
	end
	assert(#diagnostics == count, ("Expected %d diagnostics, got %d for %s"):format(count, #diagnostics, source))
	return diagnostics
end

local import = "local m = require(script.Parent.Numbers)\n"
local errors = check(import .. "print(m + true)", 1)
assert(errors[1].Line == 2 and errors[1].Column > 0 and errors[1].Kind == "Type error")
assert(errors[1].Message:find("number", 1, true) and errors[1].Message:find("boolean", 1, true))
check(import .. "print(m + 2)", 0)
check("local a: number = true\nlocal b: string = 1", 2)
check("--!nocheck\nlocal a: number = true", 0)
check("--!nonstrict\n" .. import .. "print(m + true)", 0)
assert(check("local function broken(", 1)[1].Kind == "Syntax error")
check('local folder = script.Parent\nlocal m = require(folder:WaitForChild("Inner (test)"))\nprint(m.value + false)', 1)
check('local folder = script.Parent\nlocal function f(folder: any) return require(folder.Numbers) end', 0)
check('local m = require(script.Parent.Unknown)\nprint(m + true)', 0)

sourceOfModule = 'return require(script.Parent["Inner (test)"]).value'
check(import .. "print(m + true)", 1)
sourceOfModule = "return require(script.Parent.Consumer)"
assert(check("return require(script.Parent.Numbers)", 1)[1].Message:find("Cyclic", 1, true))

sourceOfModule = [=[
export type Box<T> = { value: T }
type Private = number
-- export type Fake = boolean
return {}
]=]
local types = service:GetExportedTypes(sourceOfModule)
assert(#types == 1 and types[1] == "Box")
check(import .. "local a: m.Box<number> = { value = 1 }", 0)
check(import .. "local a: m.Box<number> = { value = true }", 1)
check(import .. "local a: m.Private = 1", 1)

local function hasLint(source, rule)
	for _, diagnostic in ipairs(service:TypeCheck(source, resolve)) do
		if diagnostic.Kind == "Lint warning" and diagnostic.Rule == rule then
			return true
		end
	end
	return false
end
assert(table.find(service:GetLintRules(), "LocalUnused"))
assert(hasLint("local unused = 1", "LocalUnused"))
assert(not hasLint("--!nolint LocalUnused\nlocal unused = 1", "LocalUnused"))
assert(not hasLint("--!nolint\nlocal unused = 1", "LocalUnused"))
assert(hasLint("--!optimize 9\nreturn 1", "CommentDirective"))
assert(hasLint("local x = 1\n--!native\nreturn x", "CommentDirective"))
assert(not hasLint("--!strict\n--!optimize 2\n--!native\nreturn 1", "CommentDirective"))
check("--!nolint\nlocal a: number = false", 1)
`, "luau_typecheck_smoke")
	assert(ok, err)
	fmt.println("LUAU_TYPECHECK_SMOKE_PASSED")
}
