static constexpr const char *KINE_GRASS_MATERIAL_SOURCE = R"KINE_GRASS_MAT(
material {
    name : "kine_grass",
    shadingModel : lit,
    blending : masked,
    maskThreshold : 0.5,
    alphaToCoverage : false,
    doubleSided : true,
    culling : none,
    instanced : true,
    flipUV : false,
    requires : [uv0, color],
    parameters : [
        { type : float, name : windStrength },
        { type : float, name : fadeStart },
        { type : float, name : fadeEnd },
        { type : float, name : hasGrassAlbedo },
        { type : sampler2d, name : grassAlbedo }
    ]
}

vertex {
    void materialVertex(inout MaterialVertexInputs material) {
        highp float h = clamp(material.uv0.y, 0.0, 1.0);
        highp vec3 p = getPosition().xyz;
        highp float t = getUserTime().x;
        highp float phase = dot(p.xz, vec2(0.19, 0.31));
        highp float gust = sin(t * 1.48 + phase) * 0.72
                         + sin(t * 2.31 + phase * 1.93) * 0.20
                         + sin(t * 0.61 + phase * 0.34) * 0.08;
        highp float bend = h * h * materialParams.windStrength;
        material.worldPosition.xz += bend * vec2(gust, sin(t * 1.22 + phase * 1.37) * 0.68);
    }
}

fragment {
    void material(inout MaterialInputs material) {
        prepareMaterial(material);
        float h = clamp(getUV0().y, 0.0, 1.0);
        vec3 color = getColor().rgb;
        vec3 worldPosition = getWorldPosition();
        vec3 grassTextureColor = texture(materialParams_grassAlbedo, worldPosition.xz * 0.25).rgb;
        color = mix(color, grassTextureColor * vec3(0.86, 1.0, 0.89),
                    0.78 * materialParams.hasGrassAlbedo);
        color *= mix(0.65, 1.14, smoothstep(0.0, 1.0, h));
        float distanceToEye = length(worldPosition - getWorldCameraPosition());
        float visible = 1.0 - smoothstep(materialParams.fadeStart, materialParams.fadeEnd, distanceToEye);
        float dither = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);
        material.baseColor = vec4(color, visible - dither + 0.5);
        material.roughness = 0.87;
        material.metallic = 0.0;
        material.reflectance = 0.035;
    }
}
)KINE_GRASS_MAT";

static bool kine_grass_debug_enabled() {
    static const bool enabled = [] {
        const char *env = std::getenv("KINE_GRASS_DEBUG");
        return env && env[0] != '\0' && env[0] != '0';
    }();
    return enabled;
}

static uint32_t kine_grass_hash(uint32_t x) {
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

static float kine_grass_random(uint32_t &seed) {
    seed = kine_grass_hash(seed + 0x9e3779b9u);
    return float(seed >> 8) * (1.0f / 16777216.0f);
}

static float kine_grass_weight(const KineTerrainWeights &weight, uint32_t mask) {
    float result = 0.0f;
    for (uint32_t i = 0; i < 8; ++i) {
        if ((mask & (1u << i)) != 0)
            result += std::max(0.0f, weight.values[i]);
    }
    return std::clamp(result, 0.0f, 1.0f);
}

static bool kine_grass_is_near(
    const KineFilamentContext *ctx, const KineMesh *terrain, const float *m) {
    if (!ctx || !terrain || !m)
        return false;
    const math::float3 p = terrain->localBounds.center;
    const double x = double(m[0]) * p.x + double(m[1]) * p.y + double(m[2]) * p.z + m[3];
    const double y = double(m[4]) * p.x + double(m[5]) * p.y + double(m[6]) * p.z + m[7];
    const double z = double(m[8]) * p.x + double(m[9]) * p.y + double(m[10]) * p.z + m[11];
    const double sx = std::sqrt(double(m[0]) * m[0] + double(m[4]) * m[4] + double(m[8]) * m[8]);
    const double sy = std::sqrt(double(m[1]) * m[1] + double(m[5]) * m[5] + double(m[9]) * m[9]);
    const double sz = std::sqrt(double(m[2]) * m[2] + double(m[6]) * m[6] + double(m[10]) * m[10]);
    const double scale = std::max({sx, sy, sz});
    const double e = double(terrain->localBounds.halfExtent.x) * terrain->localBounds.halfExtent.x +
                     double(terrain->localBounds.halfExtent.y) * terrain->localBounds.halfExtent.y +
                     double(terrain->localBounds.halfExtent.z) * terrain->localBounds.halfExtent.z;
    const double radius = std::sqrt(e) * scale;
    const double dx = x - ctx->cameraEye.x, dy = y - ctx->cameraEye.y, dz = z - ctx->cameraEye.z;
    const double maxDistance = double(ctx->grassDistance) + radius + 2.0;
    return dx * dx + dy * dy + dz * dz <= maxDistance * maxDistance;
}

static void kine_grass_release(KineFilamentContext *ctx, KineMesh *terrain) {
    if (!ctx || !terrain)
        return;
    ctx->grassOwners.erase(terrain);
    terrain->grassAttempted = false;
    if (!terrain->grassMesh)
        return;
    KineMesh *grass = terrain->grassMesh;
    terrain->grassMesh = nullptr;
    kine_invalidate_batches(ctx, grass, nullptr);
    if (ctx->engine) {
        if (grass->vb) ctx->engine->destroy(grass->vb);
        if (grass->ib) ctx->engine->destroy(grass->ib);
    }
    delete grass;
}

static KineMesh *kine_grass_generate(KineFilamentContext *ctx, KineMesh *terrain) {
    if (!ctx || !terrain || terrain->terrainWeights.size() != terrain->vertices.size() ||
        terrain->indices.size() < 3 || ctx->grassDensity <= 0.0f || ctx->grassLayerMask == 0)
        return nullptr;

    struct Triangle {
        uint32_t a, b, c;
        float area, slope, averageWeight;
    };
    std::vector<Triangle> triangles;
    triangles.reserve(terrain->indices.size() / 3);
    double weightedArea = 0.0;
    for (size_t t = 0; t + 2 < terrain->indices.size(); t += 3) {
        const uint32_t a = terrain->indices[t], b = terrain->indices[t + 1], c = terrain->indices[t + 2];
        if (a >= terrain->vertices.size() || b >= terrain->vertices.size() || c >= terrain->vertices.size())
            continue;
        const KineVertex &v0 = terrain->vertices[a];
        const KineVertex &v1 = terrain->vertices[b];
        const KineVertex &v2 = terrain->vertices[c];
        const math::float3 p0{v0.px, v0.py, v0.pz};
        const math::float3 p1{v1.px, v1.py, v1.pz};
        const math::float3 p2{v2.px, v2.py, v2.pz};
        const math::float3 crossed = cross(p1 - p0, p2 - p0);
        const float twiceArea = length(crossed);
        if (twiceArea <= 0.000001f)
            continue;
        const float slope = std::abs(crossed.y / twiceArea);
        if (slope < 0.67f)
            continue;
        const float weight = (
            kine_grass_weight(terrain->terrainWeights[a], ctx->grassLayerMask) +
            kine_grass_weight(terrain->terrainWeights[b], ctx->grassLayerMask) +
            kine_grass_weight(terrain->terrainWeights[c], ctx->grassLayerMask)) / 3.0f;
        if (weight < 0.06f)
            continue;
        const float area = twiceArea * 0.5f;
        const float slopeFactor = std::clamp((slope - 0.67f) / 0.25f, 0.0f, 1.0f);
        weightedArea += double(area) * weight * slopeFactor;
        triangles.push_back({a, b, c, area, slopeFactor, weight});
    }
    if (weightedArea <= 0.0 || triangles.empty()) {
        if (kine_grass_debug_enabled())
            fprintf(stderr, "[Kine Grass] skipped terrain mesh=%p: no eligible upward-facing triangles on layer mask=0x%02x\n",
                (void *)terrain, (unsigned)ctx->grassLayerMask);
        return nullptr;
    }

    constexpr size_t MAX_CLUMPS = 8192;
    const float density = float(std::min<double>(ctx->grassDensity, double(MAX_CLUMPS) / weightedArea));
    auto *grass = new KineMesh();
    grass->useImportedMaterials = false;
    grass->doubleSided = true;
    grass->vertices.reserve(MAX_CLUMPS * 18);
    grass->vertexColors.reserve(MAX_CLUMPS * 18);
    grass->indices.reserve(MAX_CLUMPS * 36);
    size_t clumps = 0;

    for (size_t index = 0; index < triangles.size() && clumps < MAX_CLUMPS; ++index) {
        const Triangle &tri = triangles[index];
        uint32_t seed = kine_grass_hash(uint32_t(index) ^ uint32_t(tri.a * 73856093u)
                                        ^ uint32_t(tri.b * 19349663u) ^ uint32_t(tri.c * 83492791u));
        const float expected = tri.area * density * tri.averageWeight * tri.slope;
        int candidates = int(expected);
        if (kine_grass_random(seed) < expected - float(candidates))
            ++candidates;
        const KineVertex &v0 = terrain->vertices[tri.a];
        const KineVertex &v1 = terrain->vertices[tri.b];
        const KineVertex &v2 = terrain->vertices[tri.c];
        for (int j = 0; j < candidates && clumps < MAX_CLUMPS; ++j) {
            const float r1 = std::sqrt(kine_grass_random(seed));
            const float r2 = kine_grass_random(seed);
            const float w0 = 1.0f - r1;
            const float w1 = r1 * (1.0f - r2);
            const float w2 = r1 * r2;
            const float mask =
                w0 * kine_grass_weight(terrain->terrainWeights[tri.a], ctx->grassLayerMask) +
                w1 * kine_grass_weight(terrain->terrainWeights[tri.b], ctx->grassLayerMask) +
                w2 * kine_grass_weight(terrain->terrainWeights[tri.c], ctx->grassLayerMask);
            if (mask < 0.30f)
                continue;

            math::float3 origin{
                w0 * v0.px + w1 * v1.px + w2 * v2.px,
                w0 * v0.py + w1 * v1.py + w2 * v2.py + 0.015f,
                w0 * v0.pz + w1 * v1.pz + w2 * v2.pz};
            const float patch = std::sin(origin.x * 0.131f + origin.z * 0.079f) *
                                std::sin(origin.z * 0.163f - origin.x * 0.058f);
            if (patch < -0.67f && kine_grass_random(seed) < 0.50f)
                continue;

            const float h = ctx->grassHeight * (0.52f + kine_grass_random(seed) * 0.68f);
            const float baseAngle = kine_grass_random(seed) * 6.283185307f;
            const float tint = 0.82f + 0.28f * kine_grass_random(seed);
            const float straw = kine_grass_random(seed) < 0.08f ? 0.13f : 0.0f;
            const math::float4 color{
                (0.19f + straw) * tint,
                (0.48f + straw * 0.45f) * tint,
                (0.105f - straw * 0.40f) * tint,
                1.0f};
            for (int blade = 0; blade < 3; ++blade) {
                const float angle = baseAngle + float(blade) * 2.094395102f +
                                    (kine_grass_random(seed) - 0.5f) * 0.35f;
                const math::float3 lateral{std::cos(angle), 0.0f, std::sin(angle)};
                const math::float3 bendDir{-lateral.z, 0.0f, lateral.x};
                const float bladeHeight = h * (0.78f + kine_grass_random(seed) * 0.32f);
                const float bladeWidth = ctx->grassHeight * (0.080f + kine_grass_random(seed) * 0.055f);
                const float lean = (kine_grass_random(seed) - 0.5f) * bladeHeight * 0.60f;
                const uint32_t start = uint32_t(grass->vertices.size());
                for (int level = 0; level < 3; ++level) {
                    const float v = float(level) * 0.5f;
                    const float width = bladeWidth * (level == 0 ? 1.0f : (level == 1 ? 0.65f : 0.025f));
                    const math::float3 at = origin +
                        math::float3{0.0f, bladeHeight * v, 0.0f} +
                        bendDir * (lean * v * v);
                    for (int side = 0; side < 2; ++side) {
                        const math::float3 position = at + lateral * (side == 0 ? -width : width);
                        KineVertex vertex{};
                        vertex.px = position.x;
                        vertex.py = position.y;
                        vertex.pz = position.z;
                        vertex.nx = bendDir.x;
                        vertex.ny = 0.20f;
                        vertex.nz = bendDir.z;
                        vertex.u = float(side);
                        vertex.v = v;
                        grass->vertices.push_back(vertex);
                        grass->vertexColors.push_back(color);
                    }
                }
                for (uint32_t step = 0; step < 2; ++step) {
                    const uint32_t a = start + step * 2;
                    grass->indices.insert(grass->indices.end(), {a, a + 1, a + 2, a + 1, a + 3, a + 2});
                }
            }
            ++clumps;
        }
    }

    if (grass->vertices.empty()) {
        if (kine_grass_debug_enabled())
            fprintf(stderr, "[Kine Grass] skipped terrain mesh=%p: candidate triangles produced zero clumps\n", (void *)terrain);
        delete grass;
        return nullptr;
    }
    if (kine_grass_debug_enabled())
        fprintf(stderr, "[Kine Grass] generated %zu clumps (%zu vertices) for terrain=%p, area=%.1f, mask=0x%02x\n",
            clumps, grass->vertices.size(), (void *)terrain, weightedArea, (unsigned)ctx->grassLayerMask);
    grass->indexCount = uint32_t(grass->indices.size());
    uploadMesh(grass, ctx->engine);
    if (!grass->vb || !grass->ib) {
        if (grass->vb) ctx->engine->destroy(grass->vb);
        if (grass->ib) ctx->engine->destroy(grass->ib);
        delete grass;
        return nullptr;
    }
    // Upload is complete; a grass mesh is render-only and has no CPU-side Ray equivalent.
    std::vector<KineVertex>().swap(grass->vertices);
    std::vector<math::float4>().swap(grass->vertexColors);
    std::vector<uint32_t>().swap(grass->indices);
    return grass;
}

static KineMesh *kine_grass_get(KineFilamentContext *ctx, KineMesh *terrain, const float *transform) {
    if (!ctx || !terrain || !ctx->grassEnabled || !ctx->grassShader ||
        !terrain->vb || !terrain->ib || terrain->terrainWeights.empty() ||
        !kine_grass_is_near(ctx, terrain, transform))
        return nullptr;
    if (!terrain->grassAttempted) {
        terrain->grassAttempted = true;
        ctx->grassOwners.insert(terrain);
        terrain->grassMesh = kine_grass_generate(ctx, terrain);
    }
    return terrain->grassMesh;
}

static void kine_grass_release_all(KineFilamentContext *ctx) {
    while (ctx && !ctx->grassOwners.empty())
        kine_grass_release(ctx, *ctx->grassOwners.begin());
}
