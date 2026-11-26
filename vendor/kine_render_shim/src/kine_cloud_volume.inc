static uint32_t kine_cloud_lut_hash(int x, int y, int z, uint32_t seed) {
    uint32_t value = uint32_t(x) * 0x8da6b343u ^ uint32_t(y) * 0xd8163841u ^
            uint32_t(z) * 0xcb1ab31fu ^ seed;
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    return value ^ (value >> 16);
}

static float kine_cloud_lut_noise(float x, float y, float z, int frequency, uint32_t seed) {
    const float scale = float(frequency);
    x *= scale;
    y *= scale;
    z *= scale;
    const int ix = int(std::floor(x));
    const int iy = int(std::floor(y));
    const int iz = int(std::floor(z));
    x -= ix;
    y -= iy;
    z -= iz;
    x = x * x * (3.0f - 2.0f * x);
    y = y * y * (3.0f - 2.0f * y);
    z = z * z * (3.0f - 2.0f * z);
    auto sample = [&](int dx, int dy, int dz) {
        return float(kine_cloud_lut_hash((ix + dx) & (frequency - 1),
                (iy + dy) & (frequency - 1), (iz + dz) & (frequency - 1), seed) >> 8) *
                (1.0f / 16777215.0f);
    };
    auto lerp = [](float a, float b, float t) { return a + (b - a) * t; };
    const float a = lerp(sample(0, 0, 0), sample(1, 0, 0), x);
    const float b = lerp(sample(0, 1, 0), sample(1, 1, 0), x);
    const float c = lerp(sample(0, 0, 1), sample(1, 0, 1), x);
    const float d = lerp(sample(0, 1, 1), sample(1, 1, 1), x);
    return lerp(lerp(a, b, y), lerp(c, d, y), z);
}

static Texture* kine_cloud_lut_create(Engine* engine, uint32_t size, bool volume, uint32_t seed, const uint8_t* gpuPixels = nullptr) {
    const size_t slices = volume ? size : 1u;
    const size_t bytes = size_t(size) * size * slices * 4;
    auto* pixels = static_cast<uint8_t*>(std::malloc(bytes));
    if (!pixels) return nullptr;
    auto encode = [](float value) {
        return uint8_t(std::clamp(value, 0.0f, 1.0f) * 255.0f + 0.5f);
    };
    if (gpuPixels) std::memcpy(pixels, gpuPixels, bytes);
    if (!gpuPixels) {
    for (uint32_t z = 0; z < slices; ++z) {
        for (uint32_t y = 0; y < size; ++y) {
            for (uint32_t x = 0; x < size; ++x) {
                const float u = float(x) / size;
                const float v = float(y) / size;
                const float w = float(z) / size;
                float channels[4]{};
                if (volume) {
                    for (uint32_t c = 0; c < 4; ++c) {
                        const uint32_t salt = seed + c * 7919u;
                        const float base = kine_cloud_lut_noise(u, v, w, 4, salt);
                        const float middle = kine_cloud_lut_noise(u, v, w, 8, salt + 17u);
                        const float fine = kine_cloud_lut_noise(u, v, w, 16, salt + 61u);
                        const float micro = kine_cloud_lut_noise(u, v, w, 32, salt + 113u);
                        channels[c] = base * 0.55f + middle * 0.25f +
                                fine * 0.14f + micro * 0.06f;
                    }
                } else {
                    const float e = 1.0f / float(size);
                    const float left = kine_cloud_lut_noise(u - e, v, 0.0f, 8, seed);
                    const float right = kine_cloud_lut_noise(u + e, v, 0.0f, 8, seed);
                    const float bottom = kine_cloud_lut_noise(u, v - e, 0.0f, 8, seed);
                    const float top = kine_cloud_lut_noise(u, v + e, 0.0f, 8, seed);
                    channels[0] = 0.5f + (top - bottom) * 1.6f;
                    channels[1] = 0.5f - (right - left) * 1.6f;
                    channels[2] = kine_cloud_lut_noise(u, v, 0.0f, 8, seed + 163u);
                    channels[3] = 1.0f;
                }
                const size_t offset = ((size_t(z) * size + y) * size + x) * 4;
                for (uint32_t c = 0; c < 4; ++c) pixels[offset + c] = encode(channels[c]);
            }
        }
    }
    }
    auto builder = Texture::Builder().width(size).height(size).levels(uint8_t(1u + std::log2(float(size))))
            .sampler(volume ? Texture::Sampler::SAMPLER_3D : Texture::Sampler::SAMPLER_2D)
            .format(Texture::InternalFormat::RGBA8);
    if (volume) builder.depth(size);
    Texture* texture = builder.build(*engine);
    if (!texture) {
        std::free(pixels);
        return nullptr;
    }
    const uint32_t levels = 1u + uint32_t(std::log2(float(size)));
    uint8_t* current = pixels;
    uint32_t dimension = size;
    for (uint32_t level = 0; level < levels; ++level) {
        const uint32_t nextDimension = std::max(dimension / 2, 1u);
        uint8_t* next = nullptr;
        if (level + 1 < levels) {
            const size_t nextSlices = volume ? nextDimension : 1u;
            next = static_cast<uint8_t*>(std::malloc(
                    size_t(nextDimension) * nextDimension * nextSlices * 4));
            if (!next) {
                std::free(current);
                engine->destroy(texture);
                return nullptr;
            }
            for (uint32_t z = 0; z < nextSlices; ++z)
                for (uint32_t y = 0; y < nextDimension; ++y)
                    for (uint32_t x = 0; x < nextDimension; ++x)
                        for (uint32_t channel = 0; channel < 4; ++channel) {
                            uint32_t sum = 0;
                            const uint32_t samples = volume ? 8u : 4u;
                            for (uint32_t dz = 0; dz < (volume ? 2u : 1u); ++dz)
                                for (uint32_t dy = 0; dy < 2; ++dy)
                                    for (uint32_t dx = 0; dx < 2; ++dx) {
                                        const uint32_t px = std::min(x * 2 + dx, dimension - 1);
                                        const uint32_t py = std::min(y * 2 + dy, dimension - 1);
                                        const uint32_t pz = volume ? std::min(z * 2 + dz, dimension - 1) : 0;
                                        const size_t offset = ((size_t(pz) * dimension + py) *
                                                dimension + px) * 4 + channel;
                                        sum += current[offset];
                                    }
                            next[((size_t(z) * nextDimension + y) * nextDimension + x) * 4 +
                                    channel] = uint8_t((sum + samples / 2) / samples);
                        }
        }
        const size_t currentSlices = volume ? dimension : 1u;
        const size_t currentBytes = size_t(dimension) * dimension * currentSlices * 4;
        Texture::PixelBufferDescriptor descriptor(current, currentBytes,
                Texture::Format::RGBA, Texture::Type::UBYTE,
                [](void* data, size_t, void*) { std::free(data); });
        if (volume)
            texture->setImage(*engine, level, 0, 0, 0, dimension, dimension,
                    uint32_t(currentSlices), std::move(descriptor));
        else
            texture->setImage(*engine, level, std::move(descriptor));
        current = next;
        dimension = nextDimension;
    }
    return texture;
}

static void kine_cloud_release_luts(KineFilamentContext* ctx) {
    ctx->cloudNoiseSource = 0;
    for (Texture*& texture : ctx->cloudVolumeTextures) {
        if (texture) ctx->engine->destroy(texture);
        texture = nullptr;
    }
}

static bool kine_cloud_prepare_luts(KineFilamentContext* ctx) {
    if (ctx->cloudVolumeTextures[0] && ctx->cloudVolumeTextures[1] &&
            ctx->cloudVolumeTextures[2]) return true;
    kine_cloud_release_luts(ctx);
    std::array<std::vector<uint8_t>, 3> generated;
    bool gpuGenerated = false;
#if defined(KINE_GPU_CLOUD_NOISE_AVAILABLE) && KINE_FILAMENT_USE_VULKAN && defined(__linux__)
    gpuGenerated = kine_cloud_gpu_generate(ctx, generated);
    std::fprintf(stderr, "[Kine] Cloud noise source: %s\n",
            gpuGenerated ? "Vulkan compute" : "CPU fallback");
#endif
    if (gpuGenerated && std::getenv("KINE_TRACE_CLOUD_NOISE")) {
        double average = 0.0;
        uint32_t buckets[8]{};
        for (size_t i = 0; i < generated[0].size(); i += 4) {
            const uint8_t value = generated[0][i];
            ++buckets[std::min(size_t(value / 32), size_t(7))];
            average += value;
        }
        average /= double(generated[0].size() / 4);
        std::fprintf(stderr, "[Kine] Wicked shape noise mean %.2f distribution",
                average);
        for (auto bucket : buckets)
            std::fprintf(stderr, " %u", bucket);
        std::fprintf(stderr, "\n");
    }
    ctx->cloudNoiseSource = gpuGenerated ? 1 : 0;
    ctx->cloudVolumeTextures[0] = kine_cloud_lut_create(ctx->engine, 64, true, 0x9918u,
            gpuGenerated ? generated[0].data() : nullptr);
    ctx->cloudVolumeTextures[1] = kine_cloud_lut_create(ctx->engine, 32, true, 0x6a31u,
            gpuGenerated ? generated[1].data() : nullptr);
    ctx->cloudVolumeTextures[2] = kine_cloud_lut_create(ctx->engine, 128, false, 0xb112u,
            gpuGenerated ? generated[2].data() : nullptr);
    if (!ctx->cloudVolumeTextures[0] || !ctx->cloudVolumeTextures[1] ||
            !ctx->cloudVolumeTextures[2]) {
        kine_cloud_release_luts(ctx);
        return false;
    }
    return true;
}

static void kine_cloud_bind_luts(KineFilamentContext* ctx, MaterialInstance* instance) {
    TextureSampler sampler(TextureSampler::MinFilter::LINEAR_MIPMAP_LINEAR, TextureSampler::MagFilter::LINEAR,
            TextureSampler::WrapMode::REPEAT);
    instance->setParameter("shapeNoise", ctx->cloudVolumeTextures[0], sampler);
    instance->setParameter("detailNoise", ctx->cloudVolumeTextures[1], sampler);
    instance->setParameter("curlNoise", ctx->cloudVolumeTextures[2], sampler);
}
