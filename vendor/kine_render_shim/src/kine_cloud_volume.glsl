float kineCloudVolumeDensity(vec3 p, vec3 q, float threshold,
        float detailWeight, float inverseHeight, float noiseMip) {
    float height = abs(p.y - materialParams.slabCentre.y) * inverseHeight;
    if (height >= 1.0) return 0.0;
    vec2 curl = textureLod(materialParams_curlNoise, fract(q.xz * 0.27), noiseMip).xy * 2.0 - 1.0;
    vec3 position = q + vec3(curl.x, 0.0, curl.y) * (0.08 * detailWeight);
    vec4 shape = textureLod(materialParams_shapeNoise, fract(position), noiseMip);
    float weather = textureLod(materialParams_shapeNoise,
            fract(position * vec3(0.21, 0.10, 0.21) + vec3(0.11, 0.35, 0.17)),
            min(noiseMip + 1.0, 5.0)).r;
    float base = mix(shape.r, weather, 0.38);
    if (base <= threshold) return 0.0;
    vec4 detail = textureLod(materialParams_detailNoise,
            fract(position * 2.0 + vec3(0.05)), min(noiseMip, 4.0));
    float erosion = dot(detail.rgb, vec3(0.5, 0.3, 0.2));
    float vertical = 1.0 - smoothstep(0.84, 1.0, height);
    return smoothstep(threshold, threshold + 0.18, base) *
            mix(1.0, erosion, 0.16 * detailWeight) * vertical;
}

float kineCloudVolumeShadow(vec3 p, vec3 q, vec3 sun, float threshold,
        float detailWeight, float inverseHeight, float noiseMip) {
    float extinction = 0.0;
    vec3 stepNoise = sun * materialParams.halfThickness *
            (0.23 / max(materialParams.noiseScale, 1.0));
    for (int step = 0; step < 2; ++step) {
        vec3 nextPosition = p + sun * materialParams.halfThickness * (0.23 * float(step + 1));
        float height = abs(nextPosition.y - materialParams.slabCentre.y) * inverseHeight;
        if (height >= 1.0) continue;
        vec3 nextNoise = fract(q + stepNoise * float(step + 1));
        vec4 shape = textureLod(materialParams_shapeNoise, nextNoise, noiseMip);
        float base = mix(shape.r, dot(shape.gba, vec3(0.5, 0.3, 0.2)), 0.15);
        extinction += smoothstep(threshold, threshold + 0.32, base) *
                (1.0 - smoothstep(0.84, 1.0, height)) * (1.0 - 0.25 * float(step));
    }
    return 1.0 - exp(-extinction * materialParams.absorption * 0.85);
}
