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
		run_script(
			script_vm,
			`
if not result then
	local output, err = compute:Poll()
	assert(not err, err)
	result = output
end
`,
		)
		_ = vm.GetGlobal(script_vm.L, "result")
		ready := vm.IsBuffer(script_vm.L, -1)
		vm.Pop(script_vm.L)
		if ready {return}
		time.sleep(time.Millisecond * 2)
	}
	panic("GPUCompute did not return a result")
}

poll_custom :: proc(script_vm: ^vm.VM) {
	for _ in 0 ..< 1000 {
		run_script(
			script_vm,
			`
local done, err = compute:PollShader()
assert(not err, err)
shaderDone = done
`,
		)
		_ = vm.GetGlobal(script_vm.L, "shaderDone")
		ready := vm.ArgBoolean(script_vm.L, -1)
		vm.Pop(script_vm.L)
		if ready {return}
		time.sleep(time.Millisecond * 2)
	}
	panic("GPUCompute shader did not complete")
}

poll_task_id :: proc(script_vm: ^vm.VM) {
	for _ in 0 ..< 1000 {
		run_script(
			script_vm,
			`
local done, err = compute:PollTask(collectID)
assert(not err, err)
taskDone = done
`,
		)
		_ = vm.GetGlobal(script_vm.L, "taskDone")
		ready := vm.ArgBoolean(script_vm.L, -1)
		vm.Pop(script_vm.L)
		if ready {return}
		time.sleep(time.Millisecond * 2)
	}
	panic("GPUCompute task did not complete")
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	defer engine_runtime.Environment_Destroy(&environment)
	defer vm.Close(&script_vm)

	run_script(
		&script_vm,
		`
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
`,
	)
	_ = vm.GetGlobal(script_vm.L, "supported")
	supported := vm.ArgBoolean(script_vm.L, -1)
	vm.Pop(script_vm.L)
	if !supported {
		when #config(KINE_GPU_COMPUTE_ALLOW_SOFTWARE, false) {
			run_script(&script_vm, `error(supportError)`)
		}
		run_script(
			&script_vm,
			`
local ok, err = compute:Dispatch("Add", floats({1}), floats({2}))
assert(not ok and type(err) == "string")
assert(compute:Poll() == nil)
compute:Destroy()
`,
		)
		fmt.println("GPU_COMPUTE_UNAVAILABLE_PATH_PASSED")
		return
	}

	run_script(
		&script_vm,
		`
a, b = buffer.create(65 * 4), buffer.create(65 * 4)
for i = 0, 64 do
	buffer.writef32(a, i * 4, i)
	buffer.writef32(b, i * 4, 0.5)
end
assert(compute:Dispatch("Add", a, b))
assert(not compute:Dispatch("Multiply", a, b), "dispatch must preserve the unread result")
buffer.writef32(a, 0, 1000)
`,
	)
	poll(&script_vm)
	run_script(
		&script_vm,
		`
assert(buffer.len(result) == 65 * 4)
for i = 0, 64 do
	assert(buffer.readf32(result, i * 4) == i + 0.5)
end
assert(compute:Poll() == nil)
result = nil
assert(compute:Dispatch("Subtract", floats({5, -2}), floats({1, 2})))
`,
	)
	poll(&script_vm)
	run_script(
		&script_vm,
		`
assert(buffer.readf32(result, 0) == 4 and buffer.readf32(result, 4) == -4)
result = nil
assert(compute:Dispatch("Multiply", floats({5, -2}), floats({1, 2})))
`,
	)
	poll(&script_vm)
	run_script(
		&script_vm,
		`
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
`,
	)
	poll(&script_vm)
	run_script(
		&script_vm,
		`
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
`,
	)
	for _ in 0 ..< 6 {
		run_script(
			&script_vm,
			`
caseIndex += 1
local case = elementCases[caseIndex]
if case[3] then
	assert(compute:Dispatch(case[1], floats(case[2]), floats(case[3])))
else
	assert(compute:Dispatch(case[1], floats(case[2])))
end
`,
		)
		poll(&script_vm)
		run_script(
			&script_vm,
			`
local case = elementCases[caseIndex]
assert(buffer.len(result) == #case[4] * 4)
for i, value in ipairs(case[4]) do
	assert(buffer.readf32(result, (i - 1) * 4) == value, case[1])
end
result = nil
`,
		)
	}

	run_script(
		&script_vm,
		`
local source = [[
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Result { vec4 result; };
layout(set=0,binding=1) uniform sampler2D tex;
layout(set=0,binding=2,std140) uniform Scale { vec4 scale; };
void main() { result = textureLod(tex, vec2(0.5), 0.0) * scale; }
]]
assert(not compute:CompileShader(source, 3))
assert(compute:CompileShader(source, {[0]="StorageBuffer",[1]="SampledTexture",[2]="UniformBuffer"}))
native = buffer.create(16)
scale = floats({2, 3, 4, 1})
pixel = buffer.create(4)
buffer.writeu32(pixel, 0, 0xff0080ff)
texture = assert(compute:CreateTexture(1, 1, pixel))
assert(compute:BindBuffer(0, native))
assert(not compute:BindBuffer(1, native))
assert(compute:BindTexture(1, texture))
assert(compute:BindBuffer(2, scale))
assert(compute:DispatchShader(1))
assert(not compute:DownloadBuffer(native))
assert(not compute:DestroyTexture(texture))
`,
	)
	poll_custom(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:DownloadBuffer(native))
assert(math.abs(buffer.readf32(native,0)-2)<0.0001)
assert(math.abs(buffer.readf32(native,4)-3*128/255)<0.0001)
assert(buffer.readf32(native,8)==0)
buffer.writef32(scale,0,4)
assert(compute:UploadBuffer(scale))
assert(compute:DispatchShader(1))
`,
	)
	poll_custom(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:DownloadBuffer(native))
assert(buffer.readf32(native,0)==4)
assert(compute:ReleaseBuffer(scale))
assert(compute:DestroyTexture(texture))
local writable = assert(compute:CreateTexture(1,1,buffer.create(4),{Storage=true}))
storageTexture = writable
assert(compute:CompileShader([[
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,rgba8) uniform image2D img;
void main() { imageStore(img, ivec2(0,0), vec4(0,1,0,1)); }
]], {[0]="StorageTexture"}))
assert(compute:BindTexture(0,writable))
assert(compute:DispatchShader(1))
`,
	)
	poll_custom(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:CompileShader([[
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Result {vec4 result;};
layout(set=0,binding=1) uniform sampler2D tex;
void main() {result=texelFetch(tex,ivec2(0),0);}
]],{[0]="StorageBuffer",[1]="SampledTexture"}))
assert(compute:BindBuffer(0,native))
assert(compute:BindTexture(1,storageTexture))
assert(compute:DispatchShader(1))
`,
	)
	poll_custom(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:DownloadBuffer(native))
assert(buffer.readf32(native,0)==0 and buffer.readf32(native,4)==1)
assert(compute:DestroyTexture(storageTexture))
local source = [[
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Result { float values[]; };
void main() { values[0] = values[0] + 2; }
]]
first = assert(compute:CreatePipeline(source,1))
second = assert(compute:CreatePipeline(source:gsub("values%[0%] %+ 2","values[0] * 3"),1))
assert(compute:UsePipeline(first))
assert(compute:BindBuffer(0,native))
assert(compute:UsePipeline(second))
assert(compute:BindBuffer(0,native))
assert(compute:BeginCommands())
assert(not compute:Dispatch("Abs",floats({1})))
assert(compute:UsePipeline(first))
assert(compute:DispatchShader(1))
assert(compute:MemoryBarrier())
assert(compute:UsePipeline(second))
assert(compute:DispatchShader(1))
assert(not compute:DestroyPipeline(first))
assert(compute:SubmitCommands())
`,
	)
	poll_custom(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:DownloadBuffer(native))
assert(buffer.readf32(native,0)==6)
assert(compute:BeginCommands())
assert(compute:DispatchShader(1))
assert(compute:CancelCommands())
assert(compute:DownloadBuffer(native))
assert(buffer.readf32(native,0)==6)
assert(compute:DestroyPipeline(first))
assert(compute:DestroyPipeline(second))
local cap = assert(compute:GetCapabilities())
assert(cap.MaxBufferSize > 0 and cap.DeviceName ~= "")
scratch = assert(compute:AllocateDeviceBuffer(16))
assert(compute:FillGPUBuffer(scratch,0x12345678))
assert(compute:CopyGPUBuffer(scratch,native,4,0,8))
assert(compute:DownloadBuffer(native))
assert(buffer.readu32(native,8)==0x12345678)
assert(compute:DestroyBuffer(scratch))
local vol = buffer.create(8*4)
for i=0,7 do buffer.writef32(vol,i*4,i+0.5) end
volume = assert(compute:CreateTexture({Width=2,Height=2,Depth=2,Dimension="3D",Format="R32F",Usage={"Sampled","Storage"}},vol))
assert(compute:GetTextureInfo(volume).Depth==2)
assert(compute:CompileShader([[
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,r32f) uniform image3D voxels;
void main(){imageStore(voxels,ivec3(1),vec4(42,0,0,1));}
]],{[0]="StorageTexture"}))
assert(compute:BindTexture(0,volume))
assert(compute:DispatchShader(1))
`,
	)
	poll_custom(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:CompileShader([[
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Result {float outData[];};
layout(set=0,binding=1) uniform sampler3D voxels;
void main(){outData[0]=texelFetch(voxels,ivec3(1),0).r;}
]],{[0]="StorageBuffer",[1]="SampledTexture"}))
assert(compute:BindBuffer(0,native))
assert(compute:BindTexture(1,volume))
assert(compute:DispatchShader(1))
`,
	)
	poll_custom(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:DownloadBuffer(native))
assert(buffer.readf32(native,0)==42)
assert(compute:DestroyTexture(volume))
local pixels = buffer.create(16)
for i=0,3 do buffer.writeu32(pixels,i*4,0xff0000ff) end
mipTex = assert(compute:CreateTexture(2,2,pixels,{GenerateMipmaps=true}))
assert(compute:GetTextureInfo(mipTex).MipLevels==2)
assert(compute:CompileShader([[
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Result {vec4 value;};
layout(set=0,binding=1) uniform sampler2D tex;
void main(){value=texelFetch(tex,ivec2(0),1);}
]],{[0]="StorageBuffer",[1]="SampledTexture"}))
assert(compute:BindBuffer(0,native))
assert(compute:BindTexture(1,mipTex))
assert(compute:DispatchShader(1))
`,
	)
	poll_custom(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:DownloadBuffer(native))
assert(buffer.readf32(native,0)==1 and buffer.readf32(native,4)==0)
assert(compute:DestroyTexture(mipTex))

assert(compute:ReleaseBuffer(native))
local grass = assert(compute:GetMaterialTextures(Enum.Material.Grass))
assert(grass.Albedo and grass.Normal and grass.ORM)
assert(compute:DestroyTexture(grass.Albedo))
assert(compute:DestroyTexture(grass.Normal))
assert(compute:DestroyTexture(grass.ORM))
local mesh = assert(compute:LoadMesh("src/engine/assets/shapes/Capsule.glb"))
assert(mesh.VertexCount>0 and mesh.TriangleCount>0)
assert(buffer.len(mesh.Vertices)==mesh.VertexCount*32)
assert(buffer.len(mesh.Indices)==mesh.TriangleCount*12)
local bvh=assert(compute:BuildBVH(mesh,{MaxLeafTriangles=4}))
assert(bvh.TriangleCount==mesh.TriangleCount and bvh.NodeCount>0)
assert(buffer.len(bvh.Nodes)==bvh.NodeCount*32)
local seen={}
for i=0,bvh.TriangleCount-1 do
    local tri=buffer.readu32(bvh.Triangles,i*4)
    assert(tri<mesh.TriangleCount and not seen[tri])
    seen[tri]=true
end
local total=0
for i=0,bvh.NodeCount-1 do
    local first=buffer.readu32(bvh.Nodes,i*32+12)
    local count=buffer.readu32(bvh.Nodes,i*32+28)
    if count==0 then assert(first>i and first+1<bvh.NodeCount)
    else assert(count<=4 and first+count<=bvh.TriangleCount);total+=count end
end
assert(total==mesh.TriangleCount)
`,
	)
	run_script(
		&script_vm,
		`
local caps = assert(compute:GetCapabilities())
assert(caps.ComputeQueueCount >= 1 and caps.ComputeQueueCount <= 4)
assert(caps.MaxPendingTasks == 32)
print("GPU_COMPUTE_QUEUES", caps.DeviceName, caps.ComputeQueueCount)
input = floats({3})
aout,bout,cout = floats({0}),floats({0}),floats({0})
local source = [[
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer InputData {float x;};
layout(set=0,binding=1,std430) buffer Result {float y;};
layout(push_constant) uniform Factor {float k;};
void main(){ y=x*k; }
]]
readpipe=assert(compute:CreatePipeline(source,2))
writepipe=assert(compute:CreatePipeline([[
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Data {float x;};
layout(push_constant) uniform Factor {float k;};
void main(){ x+=k; }
]],1))
assert(compute:UsePipeline(readpipe))
assert(compute:BindBuffer(0,input))
assert(compute:BindBuffer(1,aout))
assert(compute:SetPushConstants(floats({2})))
job1=assert(compute:SubmitTask(1))
assert(compute:BindBuffer(1,bout))
assert(compute:SetPushConstants(floats({3})))
job2=assert(compute:SubmitTask(1))
assert(compute:UsePipeline(writepipe))
assert(compute:BindBuffer(0,input))
assert(compute:SetPushConstants(floats({8})))
job3=assert(compute:SubmitTask(1))
assert(compute:UsePipeline(readpipe))
assert(compute:BindBuffer(1,cout))
assert(compute:SetPushConstants(floats({4})))
job4=assert(compute:SubmitTask(1))
assert(compute:GetPendingTaskCount()==4)
assert(not compute:DownloadBuffer(aout))
assert(not compute:ReleaseBuffer(input))
assert(not compute:DestroyPipeline(readpipe))
assert(not compute:DispatchShader(1))
assert(not compute:Dispatch("Abs",floats({1})))
assert(not compute:BeginCommands())
local lanes={}
for _,id in ipairs({job1,job2,job3,job4}) do
    local info=assert(compute:GetTaskInfo(id))
    assert(info.DispatchCount==1)
    lanes[info.Queue]=true
end
local n=0
for _ in pairs(lanes) do n+=1 end
assert(n==caps.ComputeQueueCount)
collectID=job4
`,
	)

	poll_task_id(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:DownloadBuffer(cout))
assert(buffer.readf32(cout,0)==44)
assert(compute:GetPendingTaskCount()==3)
assert(not compute:PollTask(job4))
collectID=job1
`,
	)
	poll_task_id(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:DownloadBuffer(aout))
assert(buffer.readf32(aout,0)==6)
assert(compute:ReleaseBuffer(aout))
collectID=job2
`,
	)
	poll_task_id(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:DownloadBuffer(bout))
assert(buffer.readf32(bout,0)==9)
collectID=job3
`,
	)
	poll_task_id(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:GetPendingTaskCount()==0)
assert(compute:DownloadBuffer(input))
assert(buffer.readf32(input,0)==11)
assert(compute:UsePipeline(writepipe))
assert(compute:BeginTask())
assert(compute:SetPushConstants(floats({2})))
assert(compute:DispatchShader(1))
assert(compute:SetPushConstants(floats({3})))
assert(compute:DispatchShader(1))
assert(not compute:SubmitCommands())
batch=assert(compute:SubmitTaskBatch())
assert(compute:GetTaskInfo(batch).DispatchCount==2)
assert(compute:BeginTask())
assert(compute:DispatchShader(1))
assert(compute:CancelCommands())
collectID=batch
`,
	)
	poll_task_id(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:DownloadBuffer(input))
assert(buffer.readf32(input,0)==16)
assert(compute:DispatchShader(1))
`,
	)
	poll_custom(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:DownloadBuffer(input))
assert(buffer.readf32(input,0)==19)
assert(compute:ReleaseBuffer(input))
assert(compute:ReleaseBuffer(bout))
assert(compute:ReleaseBuffer(cout))
assert(compute:DestroyPipeline(readpipe))
assert(compute:DestroyPipeline(writepipe))
-- Bounded backpressure, even when jobs have already finished but are not collected.
assert(compute:CompileShader([[
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Data {uint x;};
void main(){x+=1;}
]],1))
counter=buffer.create(4)
assert(compute:BindBuffer(0,counter))
many={}
for i=1,32 do many[i]=assert(compute:SubmitTask(1)) end
assert(not compute:SubmitTask(1))
assert(compute:GetPendingTaskCount()==32)
`,
	)
	for i in 0 ..< 32 {
		vm.PushNumber(script_vm.L, f64(i + 1))
		vm.SetGlobal(script_vm.L, "taskIndex")
		run_script(&script_vm, `collectID=many[taskIndex]`)
		poll_task_id(&script_vm)
	}
	run_script(
		&script_vm,
		`
assert(compute:DownloadBuffer(counter))
assert(buffer.readu32(counter,0)==32)
assert(compute:ReleaseBuffer(counter))
`,
	)
	run_script(
		&script_vm,
		`
assert(compute:CompileShader([[
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) buffer Data {float values[];};
void main() {
    uint i=gl_GlobalInvocationID.x;
    if(i<uint(values.length())) values[i]=values[i]*2.0+1.0;
}
]],1))
chunkSize=262144
largeTasks={}
largeBuffers={}
for chunk=1,4 do
    local b=buffer.create(chunkSize*4)
    for i=0,chunkSize-1 do buffer.writef32(b,i*4,chunk+i) end
    assert(compute:BindBuffer(0,b))
    largeTasks[chunk]=assert(compute:SubmitTask(chunkSize/64))
    largeBuffers[chunk]=b
end
assert(compute:GetPendingTaskCount()==4)
`,
	)
	for i in 0 ..< 4 {
		vm.PushNumber(script_vm.L, f64(i + 1))
		vm.SetGlobal(script_vm.L, "taskIndex")
		run_script(&script_vm, `collectID=largeTasks[taskIndex]`)
		poll_task_id(&script_vm)
		run_script(
			&script_vm,
			`
local b=largeBuffers[taskIndex]
assert(compute:DownloadBuffer(b))
for i=0,chunkSize-1 do
    assert(buffer.readf32(b,i*4)==2*(taskIndex+i)+1)
end
assert(compute:ReleaseBuffer(b))
`,
		)
	}

	run_script(
		&script_vm,
		`
local pixel = buffer.create(4)
buffer.writeu32(pixel,0,0xff0000ff)
asyncTexture=assert(compute:CreateTexture(1,1,pixel,{Storage=true}))
texOut=buffer.create(16)
samplerPipe=assert(compute:CreatePipeline([[
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0) uniform sampler2D image;
layout(set=0,binding=1,std430) buffer Result {vec4 value;};
void main(){value=texelFetch(image,ivec2(0),0);}
]],{[0]="SampledTexture",[1]="StorageBuffer"}))
imagePipe=assert(compute:CreatePipeline([[
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,rgba8) uniform image2D image;
void main(){imageStore(image,ivec2(0),vec4(0,1,0,1));}
]],{[0]="StorageTexture"}))
assert(compute:UsePipeline(samplerPipe))
assert(compute:BindTexture(0,asyncTexture))
assert(compute:BindBuffer(1,texOut))
sampleFirst=assert(compute:SubmitTask(1))
assert(compute:UsePipeline(imagePipe))
assert(compute:BindTexture(0,asyncTexture))
imageJob=assert(compute:SubmitTask(1))
assert(not compute:DestroyTexture(asyncTexture))
collectID=sampleFirst
`,
	)
	poll_task_id(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:DownloadBuffer(texOut))
assert(buffer.readf32(texOut,0)==1 and buffer.readf32(texOut,4)==0)
assert(compute:UsePipeline(samplerPipe))
collectID=assert(compute:SubmitTask(1))
`,
	)
	poll_task_id(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:DownloadBuffer(texOut))
assert(buffer.readf32(texOut,0)==0 and buffer.readf32(texOut,4)==1)
collectID=imageJob
`,
	)
	poll_task_id(&script_vm)
	run_script(
		&script_vm,
		`
assert(compute:DestroyTexture(asyncTexture))
assert(compute:ReleaseBuffer(texOut))
assert(compute:DestroyPipeline(samplerPipe))
assert(compute:DestroyPipeline(imagePipe))
assert(compute:CompileShader([[
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Result {uint value;};
void main(){value=100;}
]],1))
local final=buffer.create(4)
assert(compute:BindBuffer(0,final))
assert(compute:SubmitTask(1))
local drop=Instance.new("GPUCompute")
assert(drop:IsSupported())
drop:Destroy()
`,
	)

	run_script(&script_vm, `compute:Destroy()`)
	fmt.println("GPU_COMPUTE_PARALLEL_SMOKE_PASSED")

	run_script(
		&script_vm,
		`
compute=Instance.new("GPUCompute")
assert(compute:Dispatch("Negate", floats({1})))
compute:Destroy()
`,
	)
	fmt.println("GPU_COMPUTE_SMOKE_PASSED")
}
