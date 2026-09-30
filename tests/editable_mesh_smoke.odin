package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	source := `
local function close(a, b, epsilon)
    return math.abs(a - b) <= (epsilon or 1e-5)
end

local function close3(a, b)
    return close(a.X, b.X) and close(a.Y, b.Y) and close(a.Z, b.Z)
end

local mesh = Instance.new("EditableMesh")
assert(mesh.Name == "EditableMesh")
assert(mesh.FixedSize == false)

local v0 = mesh:AddVertex(Vector3.new(0, 0, 0))
local v1 = mesh:AddVertex(Vector3.new(1, 0, 0))
local v2 = mesh:AddVertex(Vector3.new(0, 1, 0))
assert(v0 == 0 and v1 == 1 and v2 == 2)
assert(close3(mesh:GetVertexPosition(v0), Vector3.new(0, 0, 0)))
assert(close3(mesh:GetPosition(v2), Vector3.new(0, 1, 0)))

mesh.FixedSize = true
assert(mesh.FixedSize == true)
assert(mesh:AddVertex(Vector3.new(100, 100, 100)) == -1)
mesh.FixedSize = false

mesh:SetPosition(v2, Vector3.new(0, 2, 0))
assert(close3(mesh:GetVertexPosition(v2), Vector3.new(0, 2, 0)))

local f0 = mesh:AddTriangle(v0, v1, v2)
assert(f0 == 0)
local faceIds = mesh:GetFaceVertexIDs(f0)
assert(#faceIds == 3)
assert(faceIds[1] == 0 and faceIds[2] == 1 and faceIds[3] == 2)

assert(close3(mesh:GetCenter(), Vector3.new(0.5, 1, 0)))
assert(close3(mesh:GetSize(), Vector3.new(1, 2, 0)))

local near = mesh:FindClosestVertex(Vector3.new(0.1, 0.05, 0))
assert(near == v0)
local surfacePoint = mesh:FindClosestPointOnSurface(Vector3.new(0, 0, 0.5))
assert(close3(surfacePoint, Vector3.new(0, 0, 0)))

local fid, point, bar, vids = mesh:RaycastLocal(Vector3.new(0.25, 0.25, 1), Vector3.new(0, 0, -1))
assert(fid >= 0)
assert(vids.X >= 0 and vids.Y >= 0 and vids.Z >= 0)

local cid = mesh:AddColor(Color3.new(1, 0, 0))
assert(cid == 0)
mesh:SetVertexColor(v0, Color3.fromRGB(0, 128, 0))
local vcolor = mesh:GetVertexColor(v0)
assert(close(vcolor.G, 128 / 255))

mesh:SetVertexNormal(v2, Vector3.new(0, 0, 1))
local norms = mesh:GetVertexNormals(v2)
assert(#norms >= 1)
assert(close3(norms[1], Vector3.new(0, 0, 1)))

local uvid = mesh:AddUV(Vector2.new(0.5, 0.5))
assert(uvid == 0)
mesh:SetVertexUV(v1, Vector2.new(1, 0))
local uvs = mesh:GetVertexUVs(v1)
assert(#uvs >= 1)
assert(close(uvs[1].X, 1) and close(uvs[1].Y, 0))

mesh:RemoveVertex(v1)
local within = mesh:FindVerticesWithinSphere(Vector3.new(0, 0, 0), 100)
assert(#within == 2)

mesh:Clear()
within = mesh:FindVerticesWithinSphere(Vector3.new(0, 0, 0), 100)
assert(#within == 0)

local batch = Instance.new("EditableMesh")
batch:BatchAdd(
    { { 0, 1, 2 } },
    {
        Vector3.new(0, 0, 0),
        Vector3.new(1, 0, 0),
        Vector3.new(0, 1, 0),
    },
    {},
    {},
    {}
)
assert(#batch:GetFaceVertexIDs(0) == 3)
assert(close3(batch:GetVertexPosition(2), Vector3.new(0, 1, 0)))
assert(#batch:GetVerticesWithAttribute(0) == 3)

local root = batch:AddBone("root", -1, CFrame.identity, false)
assert(root == 0)
assert(batch:GetBoneByName("root") == 0)
assert(#batch:GetBones() == 1)

local part = Instance.new("MeshPart")
local content = Content.fromObject(mesh)
assert(content.IsObject and not content.IsUri)
part.MeshContent = content
assert(part.MeshContent.IsObject)
assert(part.MeshContent.ObjectId == content.ObjectId)
assert(part:GetMeshContent().ObjectId == content.ObjectId)
part.MeshId = "rbsx://invalid"
assert(not part.MeshContent.IsObject)
assert(not part:GetMeshContent().IsObject)

local plain = Content.fromObject(Vector3.new(1, 2, 3))
assert(not plain.IsObject and not plain.IsUri)
`

	ok, err := vm.Run(&script_vm, source, "editable_mesh_smoke")
	if !ok {
		fmt.eprintln(err)
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
		panic("editable mesh smoke test failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("EDITABLE_MESH_SMOKE_PASSED")
}