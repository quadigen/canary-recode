#version 450
layout(set = 0, binding = 0) uniform sampler3D aerialVolume;
layout(location = 0) out vec4 color;

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(64.0);
    float depth = mix(0.01, 0.98, uv.x);
    vec4 atmosphere = textureLod(aerialVolume, vec3(uv, sqrt(depth)), 0.0);
    vec3 surface = vec3(0.4, 0.28, 0.18);
    vec3 light = surface * (1.0 - atmosphere.a) + atmosphere.rgb;
    color = vec4(vec3(1.0) - exp(-max(light, vec3(0.0))), 1.0);
}
