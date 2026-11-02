// Cached render-only refinement. Never changes collision or the authored mesh.
static KineMesh *kine_refine_material_mesh(KineFilamentContext *ctx, KineMesh *source, int levels) {
    if (!ctx || !source || levels <= 0 || !source->bones.empty() || source->indices.empty()) return source;
    levels = std::clamp(levels, 0, 4);
    if (auto it = source->refinedMeshes.find(levels); it != source->refinedMeshes.end()) return it->second;
    auto refined = std::make_unique<KineMesh>();
    refined->vertices = source->vertices;
    refined->indices = source->indices;
    refined->vertexColors = source->vertexColors;
    refined->terrainWeights = source->terrainWeights;
    refined->doubleSided = source->doubleSided;
    refined->ownedTex = source->ownedTex;
    refined->ownsTexture = false;
    bool didRefine = false;
    for (int level = 0; level < levels; ++level) {
        // Conservative edge bound limits render-only subdivision cost and
        // prevents terrain/imported meshes from expanding without a budget.
        if (refined->vertices.size() + refined->indices.size() > 60000) break;
        const bool colors = refined->vertexColors.size() == refined->vertices.size();
        const bool terrain = refined->terrainWeights.size() == refined->vertices.size();
        std::unordered_map<uint64_t, uint32_t> edges;
        auto midpoint = [&](uint32_t a, uint32_t b) {
            const uint64_t edge = (uint64_t(std::min(a,b)) << 32) | std::max(a,b);
            if (auto it = edges.find(edge); it != edges.end()) return it->second;
            const auto va = refined->vertices[a], vb = refined->vertices[b];
            math::float3 normal{va.nx + vb.nx, va.ny + vb.ny, va.nz + vb.nz};
            normal = length(normal) > 0.00001f ? normalize(normal) : math::float3{va.nx,va.ny,va.nz};
            const uint32_t index = uint32_t(refined->vertices.size());
            refined->vertices.push_back({(va.px+vb.px)*0.5f,(va.py+vb.py)*0.5f,(va.pz+vb.pz)*0.5f,
                normal.x,normal.y,normal.z,(va.u+vb.u)*0.5f,(va.v+vb.v)*0.5f});
            if (colors) refined->vertexColors.push_back((refined->vertexColors[a]+refined->vertexColors[b])*0.5f);
            if (terrain) {
                KineTerrainWeights weights{};
                for (int i=0;i<8;++i) weights.values[i]=(refined->terrainWeights[a].values[i]+refined->terrainWeights[b].values[i])*0.5f;
                refined->terrainWeights.push_back(weights);
            }
            edges.emplace(edge,index);
            return index;
        };
        std::vector<uint32_t> indices;
        indices.reserve(refined->indices.size()*4);
        for (size_t i=0;i+2<refined->indices.size();i+=3) {
            const uint32_t a=refined->indices[i],b=refined->indices[i+1],c=refined->indices[i+2];
            const uint32_t ab=midpoint(a,b),bc=midpoint(b,c),ca=midpoint(c,a);
            indices.insert(indices.end(),{a,ab,ca,ab,b,bc,ca,bc,c,ab,bc,ca});
        }
        refined->indices=std::move(indices);
        didRefine=true;
    }
    if (!didRefine) {source->refinedMeshes.emplace(levels,source); return source;}
    refined->indexCount=uint32_t(refined->indices.size());
    uploadMesh(refined.get(),ctx->engine);
    if (!refined->vb || !refined->ib) {
        if (refined->vb) ctx->engine->destroy(refined->vb);
        if (refined->ib) ctx->engine->destroy(refined->ib);
        return source;
    }
    auto *mesh=refined.release();
    source->refinedMeshes.emplace(levels,mesh);
    return mesh;
}

static void kine_destroy_refined_meshes(KineFilamentContext *ctx,KineMesh *mesh) {
    auto refined=std::move(mesh->refinedMeshes);
    mesh->refinedMeshes.clear();
    for (const auto &[level,child]:refined)
        if (child && child!=mesh) Kine_Filament_DestroyMesh(ctx,reinterpret_cast<KineFilamentMesh *>(child));
}
