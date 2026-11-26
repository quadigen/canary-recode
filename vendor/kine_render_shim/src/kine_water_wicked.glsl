vec4 wickedWaterSurface(vec2 position, float time, float scale, mat2 footprint, float distanceToCamera) {
    vec2 warped;
    mat2 warpGradient;
    waterWaveWarp(position, scale, warped, warpGradient);
    mat2 deformation = mat2(1.0);
    vec2 surfaceGradient = vec2(0.0);
    int count = int(clamp(materialParams.octaves, 1.0, 6.0));
    for (int i = 0; i < count; ++i) {
        vec2 direction;
        float frequency;
        float amplitude;
        float horizontal;
        float phase;
        waterWave(i, warped, time, scale, direction, frequency, amplitude, horizontal, phase);
        vec2 phaseGradient = (warpGradient * direction) * frequency;
        float visibility = 1.0 - smoothstep(0.65, 2.8,
                dot(abs(phaseGradient * footprint), vec2(1.0)));
        float sine = sin(phase);
        float cosine = cos(phase);
        vec2 horizontalDerivative = direction * horizontal * sine * visibility;
        deformation[0] -= horizontalDerivative * phaseGradient.x;
        deformation[1] -= horizontalDerivative * phaseGradient.y;
        surfaceGradient += phaseGradient * amplitude * cosine * visibility;
    }
    float determinant = deformation[0].x * deformation[1].y -
            deformation[0].y * deformation[1].x;
    float folding = clamp(1.0 - determinant, 0.0, 1.0);
    vec2 uv = position / max(scale, 0.25);
    vec2 motion = vec2(-0.06 * time);
    vec2 detailedGradient = vec2(0.0);
    detailedGradient += waterNoise(uv * 1.12 + motion).yz * 1.4 * 1.12;
    detailedGradient += waterNoise(uv * 0.59 + motion).yz * 1.6 * 0.59;
    detailedGradient += waterNoise(uv * 0.23 + motion).yz * 2.2 * 0.23;
    float farFade = smoothstep(0.08, 0.8, clamp(distanceToCamera * 0.005, 0.0, 1.0));
    surfaceGradient = mix(surfaceGradient + detailedGradient * 0.045,
            detailedGradient * 0.012, farFade);
    return vec4(surfaceGradient, folding, farFade);
}

float wickedWaterFoam(float folding, float shore, float noiseValue, float distanceFade) {
    float foldFoam = pow(clamp(folding * 3.0, 0.0, 1.0), 4.0);
    float shoreFoam = clamp(shore, 0.0, 1.0);
    float combined = clamp(foldFoam * (1.0 - distanceFade) + shoreFoam, 0.0, 1.0);
    float patches = smoothstep(0.2, 0.8, noiseValue);
    return clamp(smoothstep(0.4, 0.65, combined + 0.14) * mix(0.65, 1.0, patches), 0.0, 1.0);
}

float wickedWaterAngularRoughness(vec3 normal, vec3 view, float baseRoughness) {
    float facing = clamp(abs(dot(normalize(normal), normalize(view))), 0.0, 1.0);
    return clamp(mix(0.18, max(baseRoughness, 0.025), facing), 0.025, 0.9);
}
