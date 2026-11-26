#version 450
layout(set = 0, binding = 0) uniform sampler2D cloudImage;
layout(location = 0) out vec4 color;
void main() {
    vec2 uv = gl_FragCoord.xy / vec2(64.0, 32.0);
    vec4 cloud = textureLod(cloudImage, uv, 0.0);
    vec3 sky = mix(vec3(0.25, 0.42, 0.65), vec3(0.48, 0.66, 0.91), uv.y);
    vec3 radiance = cloud.rgb + sky * (1.0 - cloud.a);
    color = vec4(vec3(1.0) - exp(-max(radiance, vec3(0.0))), 1.0);
}
