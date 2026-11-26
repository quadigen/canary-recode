// Cloud noise primitives ported from Wicked Engine.
//
// Source: WickedEngine/shaders/volumetricCloudsHF.hlsli at revision
// 0208210a27b6dd05cf4684476c40294d29594497, MIT licensed. The MIT notice is
// retained in licenses/WickedEngine-MIT.txt. Wicked in turn credits the Perlin
// code to https://github.com/BrianSharpe/GPU-Noise-Lib and the Worley/cloud work
// to https://github.com/greje656/clouds.
//
// Adaptation notes:
// - HLSL lerp, saturate, frac and rsqrt map to mix, clamp, fract and inversesqrt.
// - HLSL float `%` truncates like fmod while GLSL mod does not, so the truncating
//   behaviour is spelled out in kineFmod.
// - Wicked hard-codes its remap ranges and octave scales in each shader; here they
//   are passed in by the caller. The generator shaders supply Wicked's values.
// - Only the noise primitives are ported. The cloud density model in the same
//   header (weather map, layers, density erosion) is not implemented.

float kineFmod(float x, float y) {
    return x - trunc(x / y) * y;
}

vec3 kineFmod(vec3 x, float y) {
    return x - trunc(x / y) * y;
}

float kineSaturate(float x) {
    return clamp(x, 0.0, 1.0);
}

float kineRemap01(float value, float low, float high) {
    return kineSaturate((value - low) / (high - low));
}

/////////////////////////////////////////////// Perlin noise ///////////////////////////////////////////////

vec3 kineInterpolationC2(vec3 x) {
    return x * x * x * (x * (x * 6.0 - 15.0) + 10.0);
}

void kinePerlinHash(vec3 gridcell, float s, bool tile,
        out vec4 lowz_hash_0, out vec4 lowz_hash_1, out vec4 lowz_hash_2,
        out vec4 highz_hash_0, out vec4 highz_hash_1, out vec4 highz_hash_2) {
    const vec2 OFFSET = vec2(50.0, 161.0);
    const float DOMAIN = 69.0;
    const vec3 SOMELARGEFLOATS = vec3(635.298681, 682.357502, 668.926525);
    const vec3 ZINC = vec3(48.500388, 65.294118, 63.934599);

    gridcell = gridcell - floor(gridcell * (1.0 / DOMAIN)) * DOMAIN;
    float d = DOMAIN - 1.5;
    vec3 gridcell_inc1 = step(gridcell, vec3(d)) * (gridcell + 1.0);

    if (tile) {
        gridcell_inc1 = mod(gridcell_inc1, s);
    }

    vec4 P = vec4(gridcell.xy, gridcell_inc1.xy) + OFFSET.xyxy;
    P *= P;
    P = P.xzxz * P.yyww;
    vec3 lowz_mod = vec3(1.0) / (SOMELARGEFLOATS + gridcell.zzz * ZINC);
    vec3 highz_mod = vec3(1.0) / (SOMELARGEFLOATS + gridcell_inc1.zzz * ZINC);
    lowz_hash_0 = fract(P * lowz_mod.xxxx);
    highz_hash_0 = fract(P * highz_mod.xxxx);
    lowz_hash_1 = fract(P * lowz_mod.yyyy);
    highz_hash_1 = fract(P * highz_mod.yyyy);
    lowz_hash_2 = fract(P * lowz_mod.zzzz);
    highz_hash_2 = fract(P * highz_mod.zzzz);
}

float kinePerlin(vec3 P, float s, bool tile) {
    P *= s;

    vec3 Pi = floor(P);
    vec3 Pi2 = floor(P);
    vec3 Pf = P - Pi;
    vec3 Pf_min1 = Pf - 1.0;

    vec4 hashx0, hashy0, hashz0, hashx1, hashy1, hashz1;
    kinePerlinHash(Pi2, s, tile, hashx0, hashy0, hashz0, hashx1, hashy1, hashz1);

    vec4 grad_x0 = hashx0 - 0.49999;
    vec4 grad_y0 = hashy0 - 0.49999;
    vec4 grad_z0 = hashz0 - 0.49999;
    vec4 grad_x1 = hashx1 - 0.49999;
    vec4 grad_y1 = hashy1 - 0.49999;
    vec4 grad_z1 = hashz1 - 0.49999;
    vec4 grad_results_0 = inversesqrt(grad_x0 * grad_x0 + grad_y0 * grad_y0 +
            grad_z0 * grad_z0) * (vec4(Pf.x, Pf_min1.x, Pf.x, Pf_min1.x) * grad_x0 +
            vec4(Pf.y, Pf.y, Pf_min1.y, Pf_min1.y) * grad_y0 + Pf.zzzz * grad_z0);
    vec4 grad_results_1 = inversesqrt(grad_x1 * grad_x1 + grad_y1 * grad_y1 +
            grad_z1 * grad_z1) * (vec4(Pf.x, Pf_min1.x, Pf.x, Pf_min1.x) * grad_x1 +
            vec4(Pf.y, Pf.y, Pf_min1.y, Pf_min1.y) * grad_y1 + Pf_min1.zzzz * grad_z1);

    vec3 blend = kineInterpolationC2(Pf);
    vec4 res0 = mix(grad_results_0, grad_results_1, blend.z);
    vec4 blend2 = vec4(blend.xy, 1.0 - blend.xy);
    float result = dot(res0, blend2.zxzx * blend2.wwyy);
    result *= 1.0 / sqrt(0.75);
    return ((result * 1.5) + 1.0) * 0.5;
}

// Wicked's cumulative-domain variant, used by the curl noise generator.
float kineGetPerlin5Octaves(vec3 p, bool tile) {
    vec3 xyz = p;
    const float amplitudeFactor = 0.5;
    const float frequencyFactor = 2.0;

    float a = 1.0;
    float value = 0.0;
    value += a * kinePerlin(xyz, 1.0, tile);
    a *= amplitudeFactor;
    xyz *= (frequencyFactor + 0.02);
    value += a * kinePerlin(xyz, 1.0, tile);
    a *= amplitudeFactor;
    xyz *= (frequencyFactor + 0.03);
    value += a * kinePerlin(xyz, 1.0, tile);
    a *= amplitudeFactor;
    xyz *= (frequencyFactor + 0.01);
    value += a * kinePerlin(xyz, 1.0, tile);
    a *= amplitudeFactor;
    xyz *= (frequencyFactor + 0.01);
    value += a * kinePerlin(xyz, 1.0, tile);

    return value;
}

float kineGetPerlin7Octaves(vec3 p, float s, bool tile) {
    vec3 xyz = p;
    float f = 1.0;
    float a = 1.0;

    float value = 0.0;
    value += a * kinePerlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    value += a * kinePerlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    value += a * kinePerlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    value += a * kinePerlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    value += a * kinePerlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    value += a * kinePerlin(xyz, s * f, tile);
    a *= 0.5;
    f *= 2.0;
    value += a * kinePerlin(xyz, s * f, tile);

    return value;
}

/////////////////////////////////////////////// Worley noise ///////////////////////////////////////////////

vec3 kineVoronoiHash(vec3 x, float s) {
    x = kineFmod(x, s);
    x = vec3(dot(x, vec3(127.1, 311.7, 74.7)),
            dot(x, vec3(269.5, 183.3, 246.1)),
            dot(x, vec3(113.5, 271.9, 124.6)));

    return fract(sin(x) * 43758.5453123);
}

// Returns (F1, F2, cell id); only the distance channels are used by the cloud noise.
vec3 kineVoronoi(vec3 x, float s, float seed, bool inverted) {
    x *= s;
    x += 0.5;
    vec3 p = floor(x);
    vec3 f = fract(x);

    float id = 0.0;
    vec2 res = vec2(1.0, 1.0);
    for (int k = -1; k <= 1; k++) {
        for (int j = -1; j <= 1; j++) {
            for (int i = -1; i <= 1; i++) {
                vec3 b = vec3(float(i), float(j), float(k));
                vec3 r = b - f + kineVoronoiHash(p + b + seed * 10.0, s);
                float d = dot(r, r);

                if (d < res.x) {
                    id = dot(p + b, vec3(1.0, 57.0, 113.0));
                    res = vec2(d, res.x);
                } else if (d < res.y) {
                    res.y = d;
                }
            }
        }
    }

    vec2 result = res;
    id = abs(id);

    if (inverted) {
        return vec3(1.0 - result, id);
    }
    return vec3(result, id);
}

float kineGetWorley3Octaves(vec3 p, float s, float seed) {
    vec3 xyz = p;

    float worley_value1 = kineVoronoi(xyz, 1.0 * s, seed, true).r;
    float worley_value2 = kineVoronoi(xyz, 2.0 * s, seed, false).r;
    float worley_value3 = kineVoronoi(xyz, 4.0 * s, seed, false).r;

    worley_value1 = kineSaturate(worley_value1);
    worley_value2 = kineSaturate(worley_value2);
    worley_value3 = kineSaturate(worley_value3);

    float worley_value = worley_value1;
    worley_value = worley_value - worley_value2 * 0.3;
    worley_value = worley_value - worley_value3 * 0.3;

    return worley_value;
}

float kineGetWorley3Octaves(vec3 p, float s) {
    return kineGetWorley3Octaves(p, s, 0.0);
}

/////////////////////////////////////////////// Curl noise ///////////////////////////////////////////////

vec3 kineCurlNoise(vec3 pos) {
    const float e = 0.05;
    float n1, n2, a, b;
    vec3 c;

    n1 = kineGetPerlin5Octaves(pos + vec3(0.0, e, 0.0), false);
    n2 = kineGetPerlin5Octaves(pos + vec3(0.0, -e, 0.0), false);
    a = (n1 - n2) / (2.0 * e);
    n1 = kineGetPerlin5Octaves(pos + vec3(0.0, 0.0, e), false);
    n2 = kineGetPerlin5Octaves(pos + vec3(0.0, 0.0, -e), false);
    b = (n1 - n2) / (2.0 * e);
    c.x = a - b;

    n1 = kineGetPerlin5Octaves(pos + vec3(0.0, 0.0, e), false);
    n2 = kineGetPerlin5Octaves(pos + vec3(0.0, 0.0, -e), false);
    a = (n1 - n2) / (2.0 * e);
    n1 = kineGetPerlin5Octaves(pos + vec3(e, 0.0, 0.0), false);
    n2 = kineGetPerlin5Octaves(pos + vec3(-e, 0.0, 0.0), false);
    b = (n1 - n2) / (2.0 * e);
    c.y = a - b;

    n1 = kineGetPerlin5Octaves(pos + vec3(e, 0.0, 0.0), false);
    n2 = kineGetPerlin5Octaves(pos + vec3(-e, 0.0, 0.0), false);
    a = (n1 - n2) / (2.0 * e);
    n1 = kineGetPerlin5Octaves(pos + vec3(0.0, e, 0.0), false);
    n2 = kineGetPerlin5Octaves(pos + vec3(0.0, -e, 0.0), false);
    b = (n1 - n2) / (2.0 * e);
    c.z = a - b;

    return c;
}

vec3 kineEncodeCurlNoise(vec3 c) {
    return (c + 1.0) * 0.5;
}

vec3 kineDecodeCurlNoise(vec3 c) {
    return (c - 0.5) * 2.0;
}

/////////////////////////////////////////////// Shape noise blend ///////////////////////////////////////////////

float kineDilatePerlinWorley(float p, float w, float x) {
    const float curve = 0.75;
    if (x < 0.5) {
        x = x / 0.5;
        float n = p + w * x;
        return n * mix(1.0, 0.5, pow(x, curve));
    }
    x = (x - 0.5) / 0.5;
    float n = w + p * (1.0 - x);
    return n * mix(0.5, 1.0, pow(x, 1.0 / curve));
}
