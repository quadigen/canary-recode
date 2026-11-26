struct KineDdgiGeometry {
    math::float3 minimum{}, maximum{}, color{};
    float emission = 0.0f;
};

struct KineDdgiLight {
    math::float3 position{}, color{}, direction{};
    float intensity = 0.0f, range = 0.0f, cone = -1.0f;
    bool shadow = false;
};

struct KineDdgiProbe {
    math::float3 coefficients[4]{};
    uint32_t samples = 0;
};

struct KineDdgiState {
    Texture* volumes[4]{};
    std::vector<KineDdgiProbe> probes;
    math::float3 origin{};
    float spacing = 0.0f;
    int count[3]{};
    uint32_t cursor = 0;
    uint64_t updated = 0;
    uint32_t generations = 0;
};

static void kine_destroy_ddgi(KineFilamentContext* ctx) {
    auto* state = ctx->ddgi;
    if (!state) return;
    for (auto*& texture : state->volumes)
        if (texture) {
            ctx->engine->destroy(texture);
            texture = nullptr;
        }
    delete state;
    ctx->ddgi = nullptr;
}

static bool kine_ddgi_ray_box(const math::float3& start, const math::float3& direction,
        const KineDdgiGeometry& geometry, float maximum, float& distance,
        math::float3& normal) {
    float near = -maximum;
    float far = maximum;
    math::float3 nearNormal{}, farNormal{};
    for (int axis = 0; axis < 3; ++axis) {
        if (std::abs(direction[axis]) < 0.000001f) {
            if (start[axis] < geometry.minimum[axis] ||
                    start[axis] > geometry.maximum[axis]) return false;
            continue;
        }
        const float inverted = 1.0f / direction[axis];
        float a = (geometry.minimum[axis] - start[axis]) * inverted;
        float b = (geometry.maximum[axis] - start[axis]) * inverted;
        math::float3 axisNormal{};
        axisNormal[axis] = -1.0f;
        if (a > b) {
            std::swap(a, b);
            axisNormal[axis] = 1.0f;
        }
        if (a > near) {
            near = a;
            nearNormal = axisNormal;
        }
        if (b < far) {
            far = b;
            farNormal = -axisNormal;
        }
        if (far < near) return false;
    }
    distance = near >= 0.01f ? near : far;
    normal = near >= 0.01f ? nearNormal : farNormal;
    return distance >= 0.01f && distance < maximum;
}

static bool kine_ddgi_trace(const std::vector<KineDdgiGeometry>& geometry,
        const math::float3& start, const math::float3& direction, float maximum,
        float& distance, math::float3& normal, size_t& index) {
    bool found = false;
    float nearest = maximum;
    for (size_t i = 0; i < geometry.size(); ++i) {
        float t;
        math::float3 n;
        if (!kine_ddgi_ray_box(start, direction, geometry[i], nearest, t, n)) continue;
        nearest = t;
        normal = n;
        index = i;
        found = true;
    }
    distance = nearest;
    return found;
}

static std::vector<KineDdgiGeometry> kine_ddgi_geometry(KineFilamentContext* ctx,
        const math::float3& origin, const math::float3& extent, float distance) {
    std::vector<KineDdgiGeometry> geometry;
    geometry.reserve(std::min(ctx->pendingBatches.size(), size_t(128)));
    const math::float3 lower = origin - math::float3{distance};
    const math::float3 upper = origin + extent + math::float3{distance};
    for (const auto& [key, batch] : ctx->pendingBatches) {
        const auto built = ctx->builtBatches.find(key);
        const bool active = batch.lastQueuedFrame == ctx->batchFrame ||
                (built != ctx->builtBatches.end() && !built->second.detached &&
                 built->second.lastUsedFrame == ctx->batchFrame);
        if (!key.mesh || !active ||
                (key.materialKind != KINE_MAT_DEFAULT &&
                 key.materialKind != KINE_MAT_NEON &&
                 key.materialKind != KINE_MAT_TERRAIN)) continue;
        const auto center = key.mesh->localBounds.center;
        const auto half = key.mesh->localBounds.halfExtent;
        for (size_t i = 0; i < batch.transforms.size(); ++i) {
            const auto& t = batch.transforms[i];
            math::float3 position = (t * math::float4{center, 1.0f}).xyz;
            position += math::float3{float(key.originX), float(key.originY), float(key.originZ)};
            const math::float3 h{
                std::abs(t[0].x) * half.x + std::abs(t[1].x) * half.y +
                        std::abs(t[2].x) * half.z,
                std::abs(t[0].y) * half.x + std::abs(t[1].y) * half.y +
                        std::abs(t[2].y) * half.z,
                std::abs(t[0].z) * half.x + std::abs(t[1].z) * half.y +
                        std::abs(t[2].z) * half.z
            };
            if (!(h.x > 0.01f && h.y > 0.01f && h.z > 0.01f) ||
                    h.x > 10000 || h.y > 10000 || h.z > 10000 ||
                    !std::isfinite(position.x) || !std::isfinite(position.y) ||
                    !std::isfinite(position.z)) continue;
            const math::float3 minimum = position - h;
            const math::float3 maximum = position + h;
            if (maximum.x < lower.x || maximum.y < lower.y || maximum.z < lower.z ||
                    minimum.x > upper.x || minimum.y > upper.y || minimum.z > upper.z) continue;
            const auto color = i < batch.colors.size()
                    ? batch.colors[i].rgb : math::float3{1.0f};
            KineDdgiGeometry item;
            item.minimum = minimum;
            item.maximum = maximum;
            item.color = {
                std::clamp(color.x, 0.0f, 16.0f),
                std::clamp(color.y, 0.0f, 16.0f),
                std::clamp(color.z, 0.0f, 16.0f)
            };
            item.emission = key.materialKind == KINE_MAT_NEON
                    ? std::clamp(key.param1, 0.0f, 16.0f) : 0.0f;
            geometry.push_back(item);
            if (geometry.size() == 512) return geometry;
        }
    }
    return geometry;
}

static std::vector<KineDdgiLight> kine_ddgi_collect_lights(KineFilamentContext* ctx,
        const math::float3& origin, const math::float3& extent, float reach) {
    std::vector<KineDdgiLight> results;
    const auto& manager = ctx->engine->getLightManager();
    auto& transforms = ctx->engine->getTransformManager();
    const auto lower = origin - math::float3{reach};
    const auto upper = origin + extent + math::float3{reach};
    for (const auto entity : ctx->lights) {
        if (!ctx->scene->hasEntity(entity)) continue;
        const auto instance = manager.getInstance(entity);
        if (!instance.isValid()) continue;
        const auto type = manager.getType(instance);
        if (type != LightManager::Type::POINT && type != LightManager::Type::SPOT &&
                type != LightManager::Type::FOCUSED_SPOT) continue;
        const auto transform = transforms.getInstance(entity);
        const auto position = transform.isValid()
                ? transforms.getWorldTransformAccurate(transform)[3].xyz
                : math::double3(manager.getPosition(instance));
        const math::float3 world{float(position.x), float(position.y), float(position.z)};
        const float range = std::max(0.01f, manager.getFalloff(instance));
        if (world.x + range < lower.x || world.y + range < lower.y ||
                world.z + range < lower.z || world.x - range > upper.x ||
                world.y - range > upper.y || world.z - range > upper.z) continue;
        KineDdgiLight light;
        light.position = world;
        light.color = manager.getColor(instance);
        light.direction = manager.getDirection(instance);
        light.intensity = manager.getIntensity(instance);
        light.range = range;
        light.cone = type == LightManager::Type::POINT
                ? -1.0f : std::cos(manager.getSpotLightOuterCone(instance));
        light.shadow = manager.isShadowCaster(instance);
        results.push_back(light);
        if (results.size() >= 16) break;
    }
    return results;
}

static math::float3 kine_ddgi_ray_lighting(KineFilamentContext* ctx,
        const std::vector<KineDdgiGeometry>& geometry,
        const std::vector<KineDdgiLight>& lights, const math::float3& position,
        const math::float3& direction, float distanceLimit) {
    float hitDistance = distanceLimit;
    math::float3 surfaceNormal{};
    size_t geometryIndex = 0;
    if (!kine_ddgi_trace(geometry, position, direction, distanceLimit,
            hitDistance, surfaceNormal, geometryIndex)) return {};
    const auto& hit = geometry[geometryIndex];
    if (hit.emission > 0.0f) return hit.color * hit.emission;
    const float daylight = std::clamp((ctx->sunDirection.y + 0.1f) * 4.0f, 0.0f, 1.0f);
    const float diffuseSun = std::max(dot(surfaceNormal, ctx->sunDirection), 0.0f) *
            daylight * std::clamp(ctx->sunIntensity / 100000.0f, 0.0f, 2.0f);
    float visibility = 1.0f;
    if (diffuseSun > 0.001f) {
        float shadowDistance = distanceLimit;
        math::float3 shadowNormal{};
        size_t shadowIndex = 0;
        const math::float3 location = position + direction * hitDistance +
                surfaceNormal * 0.04f;
        if (kine_ddgi_trace(geometry, location, ctx->sunDirection, distanceLimit,
                shadowDistance, shadowNormal, shadowIndex))
            visibility = 0.0f;
    }
    const float illumination = daylight * 0.035f + diffuseSun * visibility * 0.5f;
    math::float3 incoming{illumination};
    const math::float3 location = position + direction * hitDistance;
    for (const auto& light : lights) {
        const auto delta = light.position - location;
        const float squared = dot(delta, delta);
        if (squared < 0.001f || squared >= light.range * light.range) continue;
        const float distance = std::sqrt(squared);
        const auto toward = delta / distance;
        const float cosine = std::max(0.0f, dot(surfaceNormal, toward));
        if (cosine < 0.001f) continue;
        if (light.cone > -0.5f &&
                dot(-toward, light.direction) < light.cone) continue;
        if (light.shadow) {
            float blocker = distance - 0.05f;
            math::float3 blockerNormal{};
            size_t blockerIndex = 0;
            if (kine_ddgi_trace(geometry, location + surfaceNormal * 0.05f,
                    toward, blocker, blocker, blockerNormal, blockerIndex))
                continue;
        }
        const float attenuation = 1.0f - squared / (light.range * light.range);
        const float power = std::clamp(light.intensity * 0.08f /
                (squared + 1.0f), 0.0f, 6.0f);
        incoming += light.color * (cosine * power * attenuation * attenuation);
    }
    return hit.color * incoming;
}

static bool kine_ddgi_upload(KineFilamentContext* ctx, KineDdgiState* state) {
    const uint32_t x = uint32_t(state->count[0]);
    const uint32_t y = uint32_t(state->count[1]);
    const uint32_t z = uint32_t(state->count[2]);
    const size_t texelCount = size_t(x) * y * z;
    const size_t byteCount = texelCount * 4 * sizeof(math::half);
    for (size_t volume = 0; volume < 4; ++volume) {
        auto* pixels = static_cast<math::half*>(std::malloc(byteCount));
        if (!pixels) return false;
        for (size_t i = 0; i < texelCount; ++i) {
            const auto& color = state->probes[i].coefficients[volume];
            for (size_t channel = 0; channel < 3; ++channel)
                pixels[i * 4 + channel] = math::half(
                    std::clamp(color[channel], -64.0f, 64.0f));
            pixels[i * 4 + 3] = math::half(state->probes[i].samples > 0 ? 1.0f : 0.0f);
        }
        Texture::PixelBufferDescriptor descriptor(pixels, byteCount,
                Texture::Format::RGBA, Texture::Type::HALF,
                [](void* data, size_t, void*) { std::free(data); });
        state->volumes[volume]->setImage(*ctx->engine, 0, 0, 0, 0,
                x, y, z, std::move(descriptor));
    }
    return true;
}

static math::float3 kine_ddgi_direction(uint32_t sample, uint32_t rays,
        uint32_t generation, uint32_t probe) {
    const float z = 1.0f - 2.0f * (float(sample) + 0.5f) / float(rays);
    const float radius = std::sqrt(std::max(0.0f, 1.0f - z * z));
    const float angle = float(sample) * 2.39996322973f +
            float(generation * 17u + probe * 13u) * 0.38196601125f;
    return {radius * std::cos(angle), z, radius * std::sin(angle)};
}

static void kine_update_ddgi(KineFilamentContext* ctx) {
    const auto& options = ctx->advancedEffects[19];
    if (!ctx->renderWorld || !ctx->camera || !options.enabled ||
            !(options.values[0] > 0.0f)) {
        if (ctx->ddgi) kine_destroy_ddgi(ctx);
        return;
    }
    const float spacing = std::clamp(options.values[1], 1.0f, 100.0f);
    const int counts[3] = {
        std::clamp(int(options.values[2]), 2, 9),
        std::clamp(int(options.values[3]), 2, 7),
        std::clamp(int(options.values[4]), 2, 9)
    };
    const uint32_t rays = uint32_t(std::clamp(int(options.values[5]), 4, 128));
    const uint32_t budget = uint32_t(std::clamp(int(options.values[6]), 1, 24));
    const float history = std::clamp(options.values[7], 0.0f, 0.99f);
    const float reach = std::clamp(options.values[8], 1.0f, 500.0f);
    const auto model = ctx->camera->getModelMatrix();
    const math::float3 eye = math::float3(model[3].xyz);
    const math::float3 forward = -math::float3(model[2].xyz);
    const math::float3 focus = eye + forward * spacing *
            float(std::max(counts[2] / 2, 1));
    math::float3 origin{};
    for (int axis = 0; axis < 3; ++axis)
        origin[axis] = std::floor(focus[axis] / spacing + 0.5f) * spacing -
                float(counts[axis] / 2) * spacing;
    const bool changed = !ctx->ddgi || ctx->ddgi->spacing != spacing ||
            ctx->ddgi->count[0] != counts[0] ||
            ctx->ddgi->count[1] != counts[1] ||
            ctx->ddgi->count[2] != counts[2];
    if (changed) {
        kine_destroy_ddgi(ctx);
        auto* state = new KineDdgiState();
        state->origin = origin;
        state->spacing = spacing;
        for (int axis = 0; axis < 3; ++axis) state->count[axis] = counts[axis];
        const size_t total = size_t(counts[0]) * counts[1] * counts[2];
        state->probes.resize(total);
        for (auto*& volume : state->volumes) {
            volume = Texture::Builder().width(counts[0]).height(counts[1])
                    .depth(counts[2]).levels(1)
                    .sampler(Texture::Sampler::SAMPLER_3D)
                    .format(Texture::InternalFormat::RGBA16F)
                    .usage(Texture::Usage::UPLOADABLE | Texture::Usage::SAMPLEABLE)
                    .build(*ctx->engine);
            if (!volume) {
                for (auto* allocated : state->volumes)
                    if (allocated) ctx->engine->destroy(allocated);
                delete state;
                return;
            }
        }
        ctx->ddgi = state;
    }
    auto* state = ctx->ddgi;
    if (length2(state->origin - origin) > 0.00001f) {
        const int shift[3] = {
            int(std::lround((origin.x - state->origin.x) / spacing)),
            int(std::lround((origin.y - state->origin.y) / spacing)),
            int(std::lround((origin.z - state->origin.z) / spacing))
        };
        std::vector<KineDdgiProbe> previous(state->probes.size());
        for (int z = 0; z < counts[2]; ++z)
            for (int y = 0; y < counts[1]; ++y)
                for (int x = 0; x < counts[0]; ++x) {
                    const int ox = x + shift[0];
                    const int oy = y + shift[1];
                    const int oz = z + shift[2];
                    if (ox < 0 || ox >= counts[0] || oy < 0 || oy >= counts[1] ||
                            oz < 0 || oz >= counts[2]) continue;
                    const size_t destination = (size_t(z) * counts[1] + y) *
                            counts[0] + x;
                    const size_t source = (size_t(oz) * counts[1] + oy) *
                            counts[0] + ox;
                    previous[destination] = state->probes[source];
                }
        state->probes.swap(previous);
        state->origin = origin;
        state->cursor = 0;
    }
    const math::float3 extent{float(counts[0] - 1) * spacing,
            float(counts[1] - 1) * spacing, float(counts[2] - 1) * spacing};
    const auto geometry = kine_ddgi_geometry(ctx, origin, extent, reach);
    const auto lights = kine_ddgi_collect_lights(ctx, origin, extent, reach);
    for (uint32_t updated = 0; updated < budget; ++updated) {
        uint32_t probeIndex = state->cursor;
        for (uint32_t index = 0; index < state->probes.size(); ++index) {
            const uint32_t candidate = (state->cursor + index) %
                    uint32_t(state->probes.size());
            if (state->probes[candidate].samples == 0) {
                probeIndex = candidate;
                break;
            }
        }
        state->cursor = (probeIndex + 1) % uint32_t(state->probes.size());
        const int px = int(probeIndex % uint32_t(counts[0]));
        const int py = int((probeIndex / uint32_t(counts[0])) % uint32_t(counts[1]));
        const int pz = int(probeIndex / uint32_t(counts[0] * counts[1]));
        const math::float3 position = origin +
                math::float3{float(px), float(py), float(pz)} * spacing;
        math::float3 measured[4]{};
        for (uint32_t ray = 0; ray < rays; ++ray) {
            const auto direction = kine_ddgi_direction(ray, rays,
                    state->generations, probeIndex);
            const auto radiance = kine_ddgi_ray_lighting(ctx, geometry, lights,
                    position, direction, reach);
            measured[0] += radiance;
            measured[1] += radiance * direction.x * 1.5f;
            measured[2] += radiance * direction.y * 1.5f;
            measured[3] += radiance * direction.z * 1.5f;
        }
        auto& probe = state->probes[probeIndex];
        const float alpha = probe.samples ? 1.0f - history : 1.0f;
        for (size_t i = 0; i < 4; ++i) {
            measured[i] /= float(rays);
            probe.coefficients[i] = probe.coefficients[i] * (1.0f - alpha) +
                    measured[i] * alpha;
        }
        ++probe.samples;
        ++state->updated;
        if (state->cursor == 0) ++state->generations;
    }
    if (std::getenv("KINE_TRACE_DDGI") &&
            (state->updated == budget || (state->updated >= state->probes.size() &&
             state->updated < state->probes.size() + budget))) {
        double energy = 0.0, maximum = 0.0;
        size_t positive = 0;
        for (const auto& probe : state->probes) {
            const auto& l0 = probe.coefficients[0];
            const double sum = double(l0.x + l0.y + l0.z);
            energy += sum;
            maximum = std::max(maximum, sum);
            positive += sum > 0.00001;
        }
        std::fprintf(stderr,
                "[Kine] DDGI geometry=%zu lights=%zu origin=(%.1f %.1f %.1f) probes=%zu positive=%zu energy=%.4f peak=%.4f updates=%llu\n",
                geometry.size(), lights.size(), origin.x, origin.y, origin.z,
                state->probes.size(), positive, energy, maximum,
                static_cast<unsigned long long>(state->updated));
    }
    if (!kine_ddgi_upload(ctx, state)) kine_destroy_ddgi(ctx);
}


KINE_API bool Kine_Filament_GetDDGIStats(KineFilamentContext* ctx,
        uint32_t* total, uint32_t* initialized, uint64_t* updated) {
    if (!ctx || !ctx->ddgi || !total || !initialized || !updated) return false;
    const auto& probes = ctx->ddgi->probes;
    *total = uint32_t(probes.size());
    *initialized = uint32_t(std::count_if(probes.begin(), probes.end(),
            [](const KineDdgiProbe& probe) { return probe.samples > 0; }));
    *updated = ctx->ddgi->updated;
    return true;
}
