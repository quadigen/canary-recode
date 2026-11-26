// Sky atmosphere primitives ported from Wicked Engine.
//
// Source: WickedEngine/shaders/skyAtmosphere.hlsli at revision
// 0208210a27b6dd05cf4684476c40294d29594497, MIT licensed. Wicked derives the
// implementation from Sebastien Hillaire's "A Scalable and Production Ready Sky
// and Atmosphere Rendering Technique" and from the MIT SkyAtmosphere sample at
// https://github.com/sebh/UnrealEngineSkyAtmosphere, whose notice is retained in
// licenses/UnrealEngineSkyAtmosphere-MIT.txt. The transmittance LUT
// parameterisation is from Bruneton 2017,
// https://github.com/ebruneton/precomputed_atmospheric_scattering.
//
// Adaptation notes:
// - Only the transmittance LUT path is ported: the uv/parameter mapping, the
//   exponential Rayleigh/Mie medium with the ozone absorption tent and the
//   optical-depth march. IntegrateScatteredLuminance, multiple scattering, aerial
//   perspective and the cloud shadow coupling are not implemented.
// - The march reproduces Wicked's non-variable sampling (segment offset 0.3) and
//   stops at the first of the atmosphere top and the planet surface, matching the
//   tTop/tBottom clamp in the source. Units are kilometres, as in Wicked.

const float KINE_PI = 3.14159265358979323846;

// Wicked keeps a 1 m offset in sky units to stay away from the planet surface.
const float KINE_PLANET_RADIUS_OFFSET = 0.001;

struct KineAtmosphereParameters {
    float bottomRadius;
    float topRadius;
    float rayleighDensityExpScale;
    float mieDensityExpScale;
    vec3 rayleighScattering;
    vec3 mieScattering;
    vec3 mieExtinction;
    vec3 absorptionExtinction;
    vec3 groundAlbedo;
    float absorptionLayerWidth;
    float absorption0ConstantTerm;
    float absorption0LinearTerm;
    float absorption1ConstantTerm;
    float absorption1LinearTerm;
};

// uv in [0,1]^2, viewHeight is a radius from the planet centre, not an altitude.
void kineUvToLutTransmittanceParams(float bottomRadius, float topRadius, vec2 uv,
        out float viewHeight, out float viewZenithCosAngle) {
    const float x_mu = uv.x;
    const float x_r = uv.y;

    const float H = sqrt(topRadius * topRadius - bottomRadius * bottomRadius);
    const float rho = H * x_r;
    viewHeight = sqrt(rho * rho + bottomRadius * bottomRadius);

    const float dMin = topRadius - viewHeight;
    const float dMax = rho + H;
    const float d = dMin + x_mu * (dMax - dMin);
    viewZenithCosAngle = d == 0.0 ? 1.0 : (H * H - rho * rho - d * d) / (2.0 * viewHeight * d);
    viewZenithCosAngle = clamp(viewZenithCosAngle, -1.0, 1.0);
}

void kineLutTransmittanceParamsToUv(float bottomRadius, float topRadius, float viewHeight,
        float viewZenithCosAngle, out vec2 uv) {
    const float H = sqrt(max(0.0, topRadius * topRadius - bottomRadius * bottomRadius));
    const float rho = sqrt(max(0.0, viewHeight * viewHeight - bottomRadius * bottomRadius));

    const float discriminant = viewHeight * viewHeight * (viewZenithCosAngle * viewZenithCosAngle
            - 1.0) + topRadius * topRadius;
    const float d = max(0.0, -viewHeight * viewZenithCosAngle + sqrt(max(0.0, discriminant)));

    const float dMin = topRadius - viewHeight;
    const float dMax = rho + H;
    uv = vec2((d - dMin) / (dMax - dMin), rho / H);
}

float kineRaySphereNearest(vec3 origin, vec3 direction, float radius) {
    const float b = dot(origin, direction);
    const float c = dot(origin, origin) - radius * radius;
    const float discriminant = b * b - c;
    if (discriminant < 0.0) {
        return -1.0;
    }
    const float t = -b - sqrt(discriminant);
    return t >= 0.0 ? t : -1.0;
}

float kineRaySphereFar(vec3 origin, vec3 direction, float radius) {
    const float b = dot(origin, direction);
    const float c = dot(origin, origin) - radius * radius;
    const float discriminant = b * b - c;
    if (discriminant < 0.0) {
        return 0.0;
    }
    return -b + sqrt(discriminant);
}

// Matches SampleMediumRGB in Wicked for Rayleigh, Mie and ozone, which only absorb light.
vec3 kineAtmosphereExtinction(KineAtmosphereParameters atmosphere, float altitude) {
    const float densityRayleigh = exp(atmosphere.rayleighDensityExpScale * altitude);
    const float densityMie = exp(atmosphere.mieDensityExpScale * altitude);
    const float densityOzone = clamp(altitude < atmosphere.absorptionLayerWidth
            ? atmosphere.absorption0LinearTerm * altitude + atmosphere.absorption0ConstantTerm
            : atmosphere.absorption1LinearTerm * altitude + atmosphere.absorption1ConstantTerm,
            0.0, 1.0);
    return densityRayleigh * atmosphere.rayleighScattering +
            densityMie * atmosphere.mieExtinction + densityOzone * atmosphere.absorptionExtinction;
}

vec3 kineAtmosphereOpticalDepth(KineAtmosphereParameters atmosphere, vec3 position,
        vec3 direction, float tMax, float sampleCount) {
    vec3 opticalDepth = vec3(0.0);
    float t = 0.0;
    for (float s = 0.0; s < sampleCount; s += 1.0) {
        const float newT = tMax * (s + 0.3) / sampleCount;
        const float dt = newT - t;
        t = newT;
        const vec3 samplePosition = position + t * direction;
        const float altitude = length(samplePosition) - atmosphere.bottomRadius;
        opticalDepth += kineAtmosphereExtinction(atmosphere, altitude) * dt;
    }
    return opticalDepth;
}

/////////////////////////////////////////////// LUT sampling ///////////////////////////////////////////////

float kineFromUnitToSubUvs(float u, float resolution) {
    return (u + 0.5 / resolution) * (resolution / (resolution + 1.0));
}

float kineFromSubUvsToUnit(float u, float resolution) {
    return (u - 0.5 / resolution) * (resolution / (resolution - 1.0));
}

/////////////////////////////////////////////// Phase functions ///////////////////////////////////////////////

float kineRayleighPhase(float cosTheta) {
    float factor = 3.0 / (16.0 * KINE_PI);
    return factor * (1.0 + cosTheta * cosTheta);
}

// USE_CornetteShanks is enabled in Wicked, so this is the Mie phase it uses.
float kineCornetteShanksMiePhase(float g, float cosTheta) {
    float k = 3.0 / (8.0 * KINE_PI) * (1.0 - g * g) / (2.0 + g * g);
    return k * (1.0 + cosTheta * cosTheta) /
            pow(max(1.0 + g * g - 2.0 * g * cosTheta, 1e-6), 1.5);
}

float kineUniformPhase() {
    return 1.0 / (4.0 * KINE_PI);
}

/////////////////////////////////////////////// Sphere intersection ///////////////////////////////////////////////

vec2 kineRaySphereIntersect(vec3 origin, vec3 direction, float radius) {
    float b = dot(origin, direction);
    float c = dot(origin, origin) - radius * radius;
    float d = b * b - c;
    if (d < 0.0) {
        return vec2(-1.0);
    }
    d = sqrt(d);
    return vec2(-b - d, -b + d);
}

// Matches RaySphereIntersectNearest in Wicked, including clamping a negative entry point to 0.
float kineRaySphereIntersectNearest(vec3 origin, vec3 direction, float radius) {
    vec2 solutions = kineRaySphereIntersect(origin, direction, radius);
    if (solutions.x < 0.0 && solutions.y < 0.0) {
        return -1.0;
    }
    if (solutions.x < 0.0) {
        return max(0.0, solutions.y);
    }
    if (solutions.y < 0.0) {
        return max(0.0, solutions.x);
    }
    return max(0.0, min(solutions.x, solutions.y));
}

/////////////////////////////////////////////// Medium sampling ///////////////////////////////////////////////

struct KineMediumSample {
    vec3 scattering;
    vec3 extinction;
};

KineMediumSample kineSampleMedium(KineAtmosphereParameters atmosphere, vec3 position) {
    float altitude = length(position) - atmosphere.bottomRadius;
    float densityRayleigh = exp(atmosphere.rayleighDensityExpScale * altitude);
    float densityMie = exp(atmosphere.mieDensityExpScale * altitude);
    float densityOzone = clamp(altitude < atmosphere.absorptionLayerWidth
            ? atmosphere.absorption0LinearTerm * altitude + atmosphere.absorption0ConstantTerm
            : atmosphere.absorption1LinearTerm * altitude + atmosphere.absorption1ConstantTerm,
            0.0, 1.0);

    KineMediumSample medium;
    vec3 scatteringRayleigh = densityRayleigh * atmosphere.rayleighScattering;
    vec3 scatteringMie = densityMie * atmosphere.mieScattering;
    vec3 extinctionMie = densityMie * atmosphere.mieExtinction;
    vec3 extinctionOzone = densityOzone * atmosphere.absorptionExtinction;
    medium.scattering = scatteringRayleigh + scatteringMie;
    medium.extinction = scatteringRayleigh + extinctionMie + extinctionOzone;
    return medium;
}

struct KineScatteringResult {
    vec3 L;
    vec3 opticalDepth;
    vec3 transmittance;
    vec3 multiScatAs1;
};
