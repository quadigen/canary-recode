float kineCloudCornetteShanks(float g, float cosTheta) {
    float k = 1.5 * (1.0 - g * g) / (2.0 + g * g);
    return k * (1.0 + cosTheta * cosTheta) /
            pow(max(1.0 + g * g - 2.0 * g * cosTheta, 1e-6), 1.5);
}

float kineCloudPhase(float cosTheta) {
    cosTheta = clamp(cosTheta, -1.0, 1.0);
    return mix(kineCloudCornetteShanks(0.5, cosTheta),
            kineCloudCornetteShanks(-0.5, cosTheta), 0.2);
}
