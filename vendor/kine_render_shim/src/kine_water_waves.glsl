// Keep the displacement spectrum in sync with datatypes/WaterWaves.odin.
const vec2 waterDirections[6] = vec2[](
    vec2(.940,.342), vec2(-.574,.819), vec2(.259,-.966),
    vec2(-.848,-.530), vec2(.719,.695), vec2(-.196,.981));
const vec3 waterWaves[6] = vec3[](
    vec3(32,.50,.4), vec3(19,.23,2.1), vec3(11,.13,4.7),
    vec3(7,.075,1.3), vec3(4,.04,5.5), vec3(2.5,.025,3.2));

void waterWave(int i, vec2 p, float time, out vec2 direction, out float k,
               out float amplitude, out float horizontal, out float phase) {
    direction = normalize(waterDirections[i]);
    k = 6.28318530718 / (waterWaves[i].x * max(materialParams.waveScale, 0.25));
    amplitude = .65 * materialParams.strength * materialParams.height * waterWaves[i].y;
    horizontal = min(amplitude * .35, .12 / k);
    phase = k * dot(direction, p) - sqrt(9.81 * k) * time + waterWaves[i].z;
}
