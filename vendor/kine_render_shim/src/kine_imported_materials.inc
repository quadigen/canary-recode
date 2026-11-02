// Imported primitives share a vertex/index buffer but keep their material slots.
static uint8_t kine_scene_geometry_layer(int kind) {
    const bool overlay=kind==KINE_MAT_GIZMO || kind==KINE_MAT_OUTLINE ||
        kind==KINE_MAT_OUTLINE_MASK || (kind>=KINE_MAT_HIGHLIGHT_OUTLINE && kind<=KINE_MAT_HIGHLIGHT_FILL_TOP);
    return overlay?2:1;
}

static bool kine_uses_imported_materials(KineFilamentContext *ctx, const KineBatchKey &key, bool inheritGlobalShader = true) {
    return key.mesh && key.mesh->useImportedMaterials && !key.mesh->primitives.empty() && !key.mesh->materials.empty() &&
        key.materialKind == KINE_MAT_DEFAULT && !key.shader && (!inheritGlobalShader || !ctx->globalShader) &&
        (!key.texture || key.texture == key.mesh->ownedTex);
}

static size_t kine_mesh_primitive_count(KineFilamentContext *ctx, const KineBatchKey &key, bool inherit = true) {
    return kine_uses_imported_materials(ctx,key,inherit) ? key.mesh->primitives.size() : 1;
}

static void kine_bind_mesh_geometry(KineFilamentContext *ctx, RenderableManager::Builder &builder,
    const KineBatchKey &key, Material *base, MaterialInstance *primary,
    std::vector<MaterialInstance *> &extra, const math::float4 *colors, const float *uvs,
    size_t count, bool inherit = true) {
    auto *mesh = key.mesh;
    if (!kine_uses_imported_materials(ctx,key,inherit)) {
        builder.material(0,primary).geometry(0,RenderableManager::PrimitiveType::TRIANGLES,mesh->vb,mesh->ib,0,mesh->indexCount);
        return;
    }
    for (size_t i = 0; i < mesh->primitives.size(); ++i) {
        const auto &primitive = mesh->primitives[i];
        auto *mi = i == 0 ? primary : base->createInstance();
        if (i != 0) extra.push_back(mi);
        KineBatchKey materialKey = key;
        if (primitive.material < mesh->materials.size()) {
            const auto &material = mesh->materials[primitive.material];
            materialKey.texture = material.texture;
            materialKey.param1 = material.roughness;
            materialKey.param2 = material.metallic;
            kine_apply_material_params(ctx,mi,materialKey,inherit);
            mi->setParameter("baseColorFactor",material.baseColor);
            mi->setParameter("alphaCutoff",material.alphaCutoff);
            mi->setDoubleSided(material.doubleSided);
            mi->setCullingMode(material.doubleSided ? MaterialInstance::CullingMode::NONE : MaterialInstance::CullingMode::BACK);
        } else {
            kine_apply_material_params(ctx,mi,materialKey,inherit);
        }
        kine_set_chunk_colors(mi,colors,count);
        // Imported UVs already refer to their material texture coordinates.
        std::vector<float> units(count,1.0f);
        kine_set_chunk_uvs(mi,units.data(),count);
        builder.material(i,mi).geometry(i,RenderableManager::PrimitiveType::TRIANGLES,mesh->vb,mesh->ib,primitive.offset,primitive.count);
    }
}

static void kine_destroy_extra_materials(KineFilamentContext *ctx, std::vector<MaterialInstance *> &extra) {
    for (auto *mi : extra) ctx->engine->destroy(mi);
    extra.clear();
}
