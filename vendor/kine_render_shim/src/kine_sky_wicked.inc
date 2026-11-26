extern "C++" {
static std::array<float, 3> kine_sky_wicked_color(float dx, float dy, float dz,
        float sx, float sy, float sz, float intensity,
        float skyR, float skyG, float skyB,
        float horizonR, float horizonG, float horizonB,
        float groundR, float groundG, float groundB) {
    constexpr float pi = 3.14159265358979323846f;
    constexpr float bottom = 6360.0f;
    constexpr float top = 6460.0f;
    constexpr float rayleigh[3] = {0.005802f, 0.013558f, 0.033100f};
    constexpr float mie[3] = {0.003996f, 0.003996f, 0.003996f};
    constexpr float g = 0.76f;
    const float rayCos = std::clamp(dx * sx + dy * sy + dz * sz, -1.0f, 1.0f);
    const float rayPhase = (3.0f / (16.0f * pi)) * (1.0f + rayCos * rayCos);
    const float miePhase = 1.5f * (1.0f - g * g) / (2.0f + g * g) *
            (1.0f + rayCos * rayCos) /
            std::pow(std::max(1.0f + g * g - 2.0f * g * rayCos, 0.0001f), 1.5f) *
            (1.0f / (4.0f * pi));
    const float radius = bottom + 0.001f;
    const float b = radius * dy;
    const float c = radius * radius - top * top;
    const float skyDist = -b + std::sqrt(std::max(0.0f, b * b - c));
    float distance = skyDist;
    if (dy < 0.0f) {
        const float groundC = radius * radius - bottom * bottom;
        const float discriminant = b * b - groundC;
        if (discriminant >= 0.0f) {
            const float groundDist = -b - std::sqrt(discriminant);
            if (groundDist > 0.0f) distance = std::min(distance, groundDist);
        }
    }
    std::array<float, 3> scattered{}, transmission{1.0f, 1.0f, 1.0f};
    const int count = 12;
    const float dt = distance / float(count);
    const float sunAmount = std::clamp((sy + 0.13f) / 0.20f, 0.0f, 1.0f);
    const float sunScale = std::clamp(intensity / 100000.0f, 0.0f, 2.0f) * sunAmount;
    for (int step = 0; step < count; ++step) {
        const float t = (float(step) + 0.5f) * dt;
        const float height = std::sqrt(radius * radius + t * t + 2.0f * radius * dy * t);
        const float altitude = std::max(height - bottom, 0.0f);
        const float rayDensity = std::exp(-altitude / 8.0f);
        const float mieDensity = std::exp(-altitude / 1.2f);
        const float localSun = (radius * sy + t * rayCos) / height;
        const float opticalPath = 1.0f / std::max(localSun, 0.04f);
        const float sunShadow = std::clamp((localSun + 0.012f) * 60.0f, 0.0f, 1.0f);
        for (int channel = 0; channel < 3; ++channel) {
            const float scatter = rayleigh[channel] * rayDensity + mie[channel] * mieDensity;
            const float extinction = scatter + 0.0003f * rayDensity;
            const float sunlight = std::exp(-opticalPath * (
                    rayleigh[channel] * 8.0f + mie[channel] * 1.2f));
            scattered[channel] += transmission[channel] * dt * (
                    rayleigh[channel] * rayDensity * rayPhase +
                    mie[channel] * mieDensity * miePhase) *
                    sunlight * sunShadow * sunScale;
            transmission[channel] *= std::exp(-extinction * dt);
        }
    }
    const float horizon = std::clamp((dy + 0.02f) * 3.5f, 0.0f, 1.0f);
    const float topBlend = std::pow(horizon, 0.45f);
    const float night = std::clamp((sy + 0.16f) * 5.0f, 0.0f, 1.0f);
    const std::array<float, 3> artistic = {
        horizonR + (skyR - horizonR) * topBlend,
        horizonG + (skyG - horizonG) * topBlend,
        horizonB + (skyB - horizonB) * topBlend
    };
    const std::array<float, 3> ground = {groundR, groundG, groundB};
    std::array<float, 3> result;
    for (int channel = 0; channel < 3; ++channel) {
        const float physicallyScattered = 1.0f - std::exp(-scattered[channel] * 18.0f);
        const float background = dy < -0.04f ?
                ground[channel] * 0.32f : artistic[channel];
        result[channel] = std::clamp(
                physicallyScattered * 0.85f + background *
                (0.15f + night * 0.25f), 0.0f, 1.0f);
    }
    if (sy < -0.14f && dy > 0.02f) {
        const float starVisibility = std::clamp((-sy - 0.14f) * 4.0f, 0.0f, 1.0f);
        const uint32_t ix = uint32_t(std::floor((dx + 1.0f) * 8192.0f));
        const uint32_t iy = uint32_t(std::floor((dy + 1.0f) * 8192.0f));
        const uint32_t iz = uint32_t(std::floor((dz + 1.0f) * 8192.0f));
        uint32_t hash = (ix * 0x9e3779b9u) ^ (iy * 0x85ebca6bu) ^ (iz * 0xc2b2ae35u);
        hash ^= hash >> 16;
        hash *= 0x7feb352du;
        hash ^= hash >> 15;
        if ((hash & 0x3fffu) == 0x3fffu) {
            for (auto& color : result) color = std::min(1.0f, color + starVisibility * 0.62f);
        }
    }
    return result;
}
}
