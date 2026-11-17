// Keep the displacement spectrum in sync with datatypes/WaterWaves.odin.
const vec2 waterDirections[6] = vec2[](
    vec2(.940,.342), vec2(-.574,.819), vec2(.259,-.966),
    vec2(-.848,-.530), vec2(.719,.695), vec2(-.196,.981));
const vec3 waterWaves[6] = vec3[](
    vec3(24,.50,.4), vec3(14,.23,2.1), vec3(9,.13,4.7),
    vec3(6,.075,1.3), vec3(3.7,.04,5.5), vec3(2.5,.025,3.2));

float waterHash(vec2 cell) {
    uvec2 p = uvec2(ivec2(cell));
    uint h = p.x * 0x8da6b343u ^ p.y * 0xd8163841u;
    h = (h ^ (h >> 16u)) * 0x7feb352du;
    h = (h ^ (h >> 15u)) * 0x846ca68bu;
    return float(h >> 16u) / 65535.0;
}

// Value noise with its exact XZ gradient. Quintic interpolation keeps both the
// slope and its rate of change continuous across the noise cells.
vec3 waterNoise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    vec2 blend = f * f * f * (f * (6.0 * f - 15.0) + 10.0);
    vec2 slope = 30.0 * f * f * (f - 1.0) * (f - 1.0);
    float a = waterHash(cell), b = waterHash(cell + vec2(1, 0));
    float c = waterHash(cell + vec2(0, 1)), d = waterHash(cell + vec2(1, 1));
    float low = mix(a, b, blend.x), high = mix(c, d, blend.x);
    return vec3(mix(low, high, blend.y),
                mix(b - a, d - c, blend.y) * slope.x,
                (high - low) * slope.y);
}

void waterWaveWarp(vec2 p, float scale, out vec2 warped, out mat2 gradient) {
    // Bend the wave fronts at two different spatial scales. The field is
    // fixed in world space and shared by every water mesh and the CPU sampler.
    float frequencyX = 0.034 / scale;
    float frequencyZ = 0.029 / scale;
    vec3 x = waterNoise(p * frequencyX + vec2(13.4, -8.7));
    vec3 z = waterNoise(p * frequencyZ + vec2(-19.1, 5.6));
    warped = p + (vec2(x.x, z.x) - 0.5) * (18.0 * scale);
    gradient = mat2(vec2(1, 0) + x.yz * 0.612, vec2(0, 1) + z.yz * 0.522);
}

void waterWave(int i, vec2 p, float time, float scale, out vec2 direction, out float k,
               out float amplitude, out float horizontal, out float phase) {
    direction = normalize(waterDirections[i]);
    k = 6.28318530718 / (waterWaves[i].x * scale);
    amplitude = .65 * materialParams.strength * materialParams.height * waterWaves[i].y;
    horizontal = min(amplitude * .35, .12 / k);
    phase = k * dot(direction, p) - sqrt(9.81 * k) * time + waterWaves[i].z;
}
