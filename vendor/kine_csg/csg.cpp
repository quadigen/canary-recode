#include <assimp/Importer.hpp>
#include <assimp/postprocess.h>
#include <assimp/scene.h>
#include <manifold/manifold.h>

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <limits>
#include <locale>
#include <sstream>
#include <vector>

using manifold::Manifold;
using manifold::MeshGL64;
using manifold::OpType;
using manifold::vec3;

extern "C" {
struct CsgInput {
    const void* bytes;
    size_t length;
    const char* hint;
    const char* path;
    uint32_t mesh_index;
    float size[3];
    float transform[12];
    int32_t shape;
    int32_t negative;
};
struct CsgOutput {
    float center[3];
    float size[3];
    unsigned char* data;
    size_t length;
};
}

static void append_meshes(
    MeshGL64& geometry, const aiScene& scene, const aiNode& node,
    const aiMatrix4x4& parent, uint32_t mesh_index, uint32_t& ordinal
) {
    const auto transform = parent * node.mTransformation;
    for (unsigned i = 0; i < node.mNumMeshes; ++i) {
        const aiMesh& mesh = *scene.mMeshes[node.mMeshes[i]];
        if (!mesh.HasPositions() || !mesh.HasFaces() ||
            !(mesh.mPrimitiveTypes & aiPrimitiveType_TRIANGLE)) continue;
        ++ordinal;
        if (mesh_index != 0 && mesh_index != ordinal) continue;
        const size_t base = geometry.vertProperties.size() / 3;
        for (unsigned j = 0; j < mesh.mNumVertices; ++j) {
            const auto p = transform * mesh.mVertices[j];
            geometry.vertProperties.insert(geometry.vertProperties.end(), {p.x, p.y, p.z});
        }
        const bool reflected = transform.Determinant() < 0;
        for (unsigned j = 0; j < mesh.mNumFaces; ++j) {
            const auto& face = mesh.mFaces[j];
            if (face.mNumIndices != 3) continue;
            geometry.triVerts.insert(geometry.triVerts.end(),
                {base + face.mIndices[0], base + face.mIndices[reflected ? 2 : 1],
                 base + face.mIndices[reflected ? 1 : 2]});
        }
    }
    for (unsigned i = 0; i < node.mNumChildren; ++i) {
        append_meshes(geometry, scene, *node.mChildren[i], transform, mesh_index, ordinal);
    }
}

static Manifold import_mesh(const CsgInput& input) {
    Assimp::Importer importer;
    constexpr unsigned flags = aiProcess_Triangulate | aiProcess_JoinIdenticalVertices |
        aiProcess_SortByPType;
    const aiScene* scene = input.bytes
        ? importer.ReadFileFromMemory(input.bytes, input.length, flags, input.hint)
        : input.path ? importer.ReadFile(input.path, flags) : nullptr;
    if (!scene || !scene->mRootNode) return {};

    MeshGL64 geometry;
    geometry.numProp = 3;
    uint32_t ordinal = 0;
    append_meshes(geometry, *scene, *scene->mRootNode, {}, input.mesh_index, ordinal);
    geometry.Merge();
    Manifold solid(geometry);
    if (solid.Status() == Manifold::Error::NoError && solid.Volume() < 0) {
        for (size_t i = 0; i < geometry.triVerts.size(); i += 3) {
            std::swap(geometry.triVerts[i + 1], geometry.triVerts[i + 2]);
        }
        return Manifold(geometry);
    }
    return solid;
}

static Manifold make_solid(const CsgInput& input, vec3 origin) {
    Manifold solid;
    switch (input.shape) {
    case 0: solid = Manifold::Sphere(1, 64); break;
    case 1: solid = Manifold::Cube(vec3(2), true); break;
    case 2: solid = Manifold::Cylinder(2, 1, -1, 64, true).Rotate(90, 0, 0); break;
    default: solid = import_mesh(input); break;
    }
    const float* f = input.transform;
    return solid.Scale({input.size[0] * 0.5, input.size[1] * 0.5, input.size[2] * 0.5})
        .Transform({{f[3], f[6], f[9]}, {f[4], f[7], f[10]}, {f[5], f[8], f[11]},
                    vec3(f[0], f[1], f[2]) - origin});
}

extern "C" int32_t Kine_Csg_Apply(
    const CsgInput* inputs, uint32_t count, uint32_t operation, CsgOutput* output
) {
    *output = {};
    if (!count || operation > 3 || (operation == 3 && count != 1)) return 1;
    const float* first = inputs[0].transform;
    const vec3 origin(first[0], first[1], first[2]);
    const manifold::mat3x4 world_to_local{
        {first[3], first[4], first[5]}, {first[6], first[7], first[8]},
        {first[9], first[10], first[11]}, vec3(0.0)
    };
    try {
        std::vector<Manifold> solids;
        std::vector<Manifold> cutters;
        for (uint32_t i = 0; i < count; ++i) {
            const auto& input = inputs[i];
            for (float size : input.size) if (!std::isfinite(size) || size <= 0) return 1;
            for (float value : input.transform) if (!std::isfinite(value)) return 1;
            Manifold solid = make_solid(input, origin).Transform(world_to_local);
            if (solid.Status() != Manifold::Error::NoError || solid.IsEmpty()) return 1;
            if ((operation == 0 && input.negative) || (operation == 1 && i != 0)) {
                cutters.push_back(std::move(solid));
            } else {
                solids.push_back(std::move(solid));
            }
        }
        if (solids.empty()) return 2;
        Manifold result = Manifold::BatchBoolean(solids, operation == 2 ? OpType::Intersect : OpType::Add);
        if (!cutters.empty()) result = result - Manifold::BatchBoolean(cutters, OpType::Add);
        if (result.Status() != Manifold::Error::NoError) return 3;
        if (result.IsEmpty()) return 2;

        const auto bounds = result.BoundingBox();
        const vec3 center = (bounds.min + bounds.max) * 0.5;
        const vec3 size = bounds.max - bounds.min;
        for (int axis = 0; axis < 3; ++axis) {
            const auto offset = linalg::dot(world_to_local[axis], center);
            output->center[axis] = static_cast<float>(offset + origin[axis]);
            output->size[axis] = static_cast<float>(size[axis]);
            if (!std::isfinite(output->center[axis]) || !std::isfinite(output->size[axis]) ||
                output->size[axis] <= 0) return 3;
        }
        // Keep hard edges on planar solids and smooth the curved sections.
        const auto mesh = result.CalculateNormals(0, 45).GetMeshGL64();
        if (mesh.numProp < 6) return 3;
        std::ostringstream obj;
        obj.imbue(std::locale::classic());
        obj << std::setprecision(std::numeric_limits<float>::max_digits10);
        for (size_t i = 0; i < mesh.vertProperties.size(); i += mesh.numProp) {
            obj << "v";
            for (int axis = 0; axis < 3; ++axis) {
                obj << ' ' << static_cast<float>(2 * (mesh.vertProperties[i + axis] - center[axis]) / size[axis]);
            }
            obj << '\n';
        }
        for (size_t i = 0; i < mesh.vertProperties.size(); i += mesh.numProp) {
            const vec3 normal = linalg::normalize(vec3(
                mesh.vertProperties[i + 3] * size[0],
                mesh.vertProperties[i + 4] * size[1],
                mesh.vertProperties[i + 5] * size[2]));
            obj << "vn " << normal[0] << ' ' << normal[1] << ' ' << normal[2] << '\n';
        }
        for (size_t i = 0; i < mesh.triVerts.size(); i += 3) {
            obj << "f";
            for (size_t corner = 0; corner < 3; ++corner) {
                const auto index = mesh.triVerts[i + corner] + 1;
                obj << ' ' << index << "//" << index;
            }
            obj << '\n';
        }
        const auto bytes = obj.view();
        output->data = static_cast<unsigned char*>(std::malloc(bytes.size()));
        if (!output->data) return 3;
        std::memcpy(output->data, bytes.data(), bytes.size());
        output->length = bytes.size();
        return 0;
    } catch (...) {
        return 3;
    }
}

extern "C" void Kine_Csg_Free(CsgOutput* output) {
    std::free(output->data);
    *output = {};
}
