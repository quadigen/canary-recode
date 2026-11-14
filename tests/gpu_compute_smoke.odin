package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"

run_script :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "gpu_compute_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("GPUCompute smoke failed")
	}
}

poll :: proc(script_vm: ^vm.VM) {
	for _ in 0 ..< 500 {
		run_script(script_vm, `
if not result then
	local output, err = compute:Poll()
	assert(not err, err)
	result = output
end
`)
		_ = vm.GetGlobal(script_vm.L, "result")
		ready := vm.IsBuffer(script_vm.L, -1)
		vm.Pop(script_vm.L)
		if ready {return}
		time.sleep(time.Millisecond * 2)
	}
	panic("GPUCompute did not return a result")
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	defer engine_runtime.Environment_Destroy(&environment)
	defer vm.Close(&script_vm)

	run_script(&script_vm, `
compute = Instance.new("GPUCompute")
assert(compute:IsA("Instance"))
assert(compute:Poll() == nil)
function floats(values)
	local data = buffer.create(#values * 4)
	for i, value in ipairs(values) do
		buffer.writef32(data, (i - 1) * 4, value)
	end
	return data
end
assert(not compute:Dispatch("Unknown", buffer.create(4), buffer.create(4)))
assert(not compute:Dispatch("Add", buffer.create(1), buffer.create(1)))
assert(not compute:Dispatch("Add", buffer.create(4), buffer.create(8)))
assert(not compute:Dispatch("Min", buffer.create(4), buffer.create(8)))
assert(not compute:Dispatch("Sqrt", buffer.create(0)))
assert(not compute:Dispatch("Abs", buffer.create(4), buffer.create(4)))
assert(not pcall(function() compute:Dispatch("Divide", buffer.create(4)) end))
assert(not pcall(function()
	compute:Dispatch("MatrixMultiply", buffer.create(4), buffer.create(4), 1.5, 1, 1)
end))
assert(not compute:Dispatch("MatrixMultiply", buffer.create(4), buffer.create(4), 2, 1, 1))
supported, supportError = compute:IsSupported()
`)
	_ = vm.GetGlobal(script_vm.L, "supported")
	supported := vm.ArgBoolean(script_vm.L, -1)
	vm.Pop(script_vm.L)
	if !supported {
		when #config(KINE_GPU_COMPUTE_ALLOW_SOFTWARE, false) {
			run_script(&script_vm, `error(supportError)`)
		}
		run_script(&script_vm, `
local ok, err = compute:Dispatch("Add", floats({1}), floats({2}))
assert(not ok and type(err) == "string")
assert(compute:Poll() == nil)
compute:Destroy()
`)
		fmt.println("GPU_COMPUTE_UNAVAILABLE_PATH_PASSED")
		return
	}

	run_script(&script_vm, `
a, b = buffer.create(65 * 4), buffer.create(65 * 4)
for i = 0, 64 do
	buffer.writef32(a, i * 4, i)
	buffer.writef32(b, i * 4, 0.5)
end
assert(compute:Dispatch("Add", a, b))
assert(not compute:Dispatch("Multiply", a, b), "dispatch must preserve the unread result")
buffer.writef32(a, 0, 1000)
`)
	poll(&script_vm)
	run_script(&script_vm, `
assert(buffer.len(result) == 65 * 4)
for i = 0, 64 do
	assert(buffer.readf32(result, i * 4) == i + 0.5)
end
assert(compute:Poll() == nil)
result = nil
assert(compute:Dispatch("Subtract", floats({5, -2}), floats({1, 2})))
`)
	poll(&script_vm)
	run_script(&script_vm, `
assert(buffer.readf32(result, 0) == 4 and buffer.readf32(result, 4) == -4)
result = nil
assert(compute:Dispatch("Multiply", floats({5, -2}), floats({1, 2})))
`)
	poll(&script_vm)
	run_script(&script_vm, `
assert(buffer.readf32(result, 0) == 5 and buffer.readf32(result, 4) == -4)
result = nil
local a, b = {}, {}
for i = 1, 3 * 11 do a[i] = i % 7 - 3 end
for i = 1, 11 * 10 do b[i] = i % 5 - 2 end
expected = {}
for row = 0, 2 do
	for column = 0, 9 do
		local sum = 0
		for k = 0, 10 do
			sum += a[row * 11 + k + 1] * b[k * 10 + column + 1]
		end
		table.insert(expected, sum)
	end
end
assert(compute:Dispatch("MatrixMultiply", floats(a), floats(b), 3, 11, 10))
`)
	poll(&script_vm)
	run_script(&script_vm, `
assert(buffer.len(result) == #expected * 4)
for i, value in ipairs(expected) do
	assert(buffer.readf32(result, (i - 1) * 4) == value, "incorrect matrix product")
end
result = nil
elementCases = {
	{"Divide", {12, -4, 3}, {3, 2, -2}, {4, -2, -1.5}},
	{"Min", {12, -4, 3}, {3, 2, -2}, {3, -4, -2}},
	{"Max", {12, -4, 3}, {3, 2, -2}, {12, 2, 3}},
	{"Abs", {-12, 0, 3}, nil, {12, 0, 3}},
	{"Negate", {-12, 0, 3}, nil, {12, 0, -3}},
	{"Sqrt", {4, 0, 2.25}, nil, {2, 0, 1.5}},
}
caseIndex = 0
`)
	for _ in 0 ..< 6 {
		run_script(&script_vm, `
caseIndex += 1
local case = elementCases[caseIndex]
if case[3] then
	assert(compute:Dispatch(case[1], floats(case[2]), floats(case[3])))
else
	assert(compute:Dispatch(case[1], floats(case[2])))
end
`)
		poll(&script_vm)
		run_script(&script_vm, `
local case = elementCases[caseIndex]
assert(buffer.len(result) == #case[4] * 4)
for i, value in ipairs(case[4]) do
	assert(buffer.readf32(result, (i - 1) * 4) == value, case[1])
end
result = nil
`)
	}
	run_script(&script_vm, `
assert(compute:Dispatch("Negate", floats({1})))
compute:Destroy()
`)
	fmt.println("GPU_COMPUTE_SMOKE_PASSED")
}
