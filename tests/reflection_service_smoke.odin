package main

import "core:fmt"

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	ok, err := vm.RunInternal(&script_vm, `
	local ReflectionService = game:GetService("ReflectionService")
	assert(ReflectionService ~= nil)
	assert(ReflectionService:IsA("Service"))

	local allCapabilities = SecurityCapabilities.new(table.unpack(Enum.SecurityCapability:GetEnumItems()))
	local allClasses = ReflectionService:GetClasses({ Security = allCapabilities })
	assert(#allClasses > 0)

	local partClass = ReflectionService:GetClass("Part")
	assert(partClass ~= nil)
	assert(partClass.Name == "Part")
	assert(partClass.Superclass == "BasePart")
	-- Part now sits under BasePart, which is what makes IsA("BasePart")
	-- resolve for every solid-geometry class. The chain above it is unchanged.
	local basePartClass = ReflectionService:GetClass("BasePart")
	assert(basePartClass ~= nil, "BasePart should be a registered class")
	assert(basePartClass.Superclass == "Instance")
	assert(ReflectionService:GetClass("Part", { IsA = "Instance" }) ~= nil)
	assert(partClass.Subclasses ~= nil)
	assert(partClass.Permits ~= nil)
	assert(partClass.Permits.New ~= nil)
	assert(partClass.Display ~= nil)
	assert(partClass.Display.Category == "General")

	-- Unknown classes and IsA mismatches both report as nil.
	assert(ReflectionService:GetClass("NotARealClass") == nil)
	assert(ReflectionService:GetClass("Part", { IsA = "Service" }) == nil)
	assert(ReflectionService:GetClass("Part", { IsA = "Instance" }) ~= nil)

	-- IsA filters the class list.
	local instances = ReflectionService:GetClasses({ IsA = "Instance" })
	assert(#instances > 0)
	for _, entry in ipairs(instances) do
		assert(entry.Superclass ~= nil or entry.Name == "Object")
	end

	local properties = ReflectionService:GetPropertiesOfClass("Part")
	assert(#properties > 0)

	local sawAnchored, sawName = false, false
	for _, property in ipairs(properties) do
		assert(property.Owner ~= nil)
		assert(property.Permits ~= nil)
		if property.Name == "Anchored" then
			sawAnchored = true
			assert(property.Owner == "Part")
		end
		if property.Name == "Name" then
			sawName = true
			-- Inherited from the base Instance class.
			assert(property.Owner == "Instance")
		end
	end
	assert(sawAnchored and sawName)

	-- ExcludeDisplay drops the Studio display block.
	local hidden = ReflectionService:GetPropertiesOfClass("Part", { ExcludeDisplay = true })
	assert(#hidden == #properties)
	for _, property in ipairs(hidden) do
		assert(property.Display == nil)
	end

	-- ExcludeInherited keeps only what the class itself declares.
	local own = ReflectionService:GetPropertiesOfClass("Part", { ExcludeInherited = true })
	assert(#own > 0)
	assert(#own < #properties)
	for _, property in ipairs(own) do
		assert(property.Owner == "Part")
	end

	local methods = ReflectionService:GetMethodsOfClass("Part")
	local sawClone = false
	for _, method in ipairs(methods) do
		assert(method.Owner ~= nil)
		assert(method.CanYield ~= nil)
		assert(method.ReturnType ~= nil)
		if method.Name == "Clone" then
			sawClone = true
			assert(method.Owner == "Instance")
		end
	end
	assert(sawClone)

	local events = ReflectionService:GetEventsOfClass("Part")
	local sawTouched = false
	for _, event in ipairs(events) do
		if event.Name == "Touched" then
			sawTouched = true
			assert(event.Owner == "Part")
			assert(event.Permits ~= nil)
		end
	end
	assert(sawTouched)

	-- Unknown classes yield nil for the member queries too.
	assert(ReflectionService:GetPropertiesOfClass("NotARealClass") == nil)
	assert(ReflectionService:GetMethodsOfClass("NotARealClass") == nil)
	assert(ReflectionService:GetEventsOfClass("NotARealClass") == nil)

	-- Services report a GetService permit; ordinary classes do not.
	local workspaceClass = ReflectionService:GetClass("Workspace")
	assert(workspaceClass ~= nil)
	assert(workspaceClass.Permits ~= nil)
	assert(workspaceClass.Permits.GetService ~= nil)

	-- Restricted services hide their class metadata from a plain script, while
	-- public services stay visible.
	`, "reflection_service_smoke")

	if !ok {
		fmt.eprintln(err)
		delete(err)
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
		panic("ReflectionService smoke test failed")
	}

	ok, err = vm.Run(&script_vm, `
	local ReflectionService = game:GetService("ReflectionService")
	-- ScriptContext is gated behind an internal capability.
	assert(ReflectionService:GetClass("ScriptContext") == nil)
	assert(ReflectionService:GetClasses({ IsA = "Service" }) ~= nil)
	-- Public services and ordinary classes remain visible.
	assert(ReflectionService:GetClass("Workspace") ~= nil)
	assert(ReflectionService:GetClass("Part") ~= nil)
	`, "reflection_service_restricted")

	if !ok {
		fmt.eprintln(err)
		delete(err)
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
		panic("ReflectionService restricted smoke test failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("REFLECTION_SERVICE_SMOKE_PASSED")
}