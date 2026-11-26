#version 450
layout(set = 0, binding = 0) uniform sampler2D skyView;
layout(set = 0, binding = 1, std140) uniform ViewParameters {
    vec4 camera;
    vec4 viewport;
    vec4 sun;
} params;
layout(location = 0) out vec4 color;

const float KINE_PI = 3.14159265358979323846;

vec2 skyViewUv(vec3 direction) {
    float bottomRadius = params.viewport.w;
    float viewHeight = bottomRadius + params.camera.w;
    float cosBeta = sqrt(max(0.0, viewHeight * viewHeight - bottomRadius * bottomRadius)) / viewHeight;
    float beta = acos(clamp(cosBeta, 0.0, 1.0));
    float horizon = KINE_PI - beta;
    float zenith = acos(clamp(direction.z, -1.0, 1.0));
    float y;
    if (zenith <= horizon) {
        y = 0.5 * (1.0 - sqrt(max(0.0, 1.0 - zenith / horizon)));
    } else {
        y = 0.5 * (1.0 + sqrt(max(0.0, (zenith - horizon) / beta)));
    }
    vec2 horizontal = direction.xy;
    vec2 sunHorizontal = normalize(params.sun.xy);
    float azimuthCos = dot(horizontal, horizontal) > 1e-8 ?
            dot(normalize(horizontal), sunHorizontal) : 1.0;
    float x = sqrt(clamp(0.5 - 0.5 * azimuthCos, 0.0, 1.0));
    vec2 dimensions = vec2(textureSize(skyView, 0));
    vec2 uv = vec2(x, clamp(y, 0.0, 1.0));
    return (uv + 0.5 / dimensions) * (dimensions / (dimensions + 1.0));
}

void main() {
    float pitch = params.camera.x;
    float yaw = params.camera.y;
    float halfFovTan = params.camera.z;
    float cp = cos(pitch);
    float sp = sin(pitch);
    float cy = cos(yaw);
    float sy = sin(yaw);
    vec3 forward = vec3(cp * cy, cp * sy, sp);
    vec3 right = vec3(-sy, cy, 0.0);
    vec3 up = cross(forward, right);
    vec2 ndc = (gl_FragCoord.xy / params.viewport.xy) * 2.0 - 1.0;
    vec3 direction = normalize(forward +
            right * (ndc.x * halfFovTan * params.viewport.x / params.viewport.y) +
            up * (ndc.y * halfFovTan));
    vec3 radiance = max(textureLod(skyView, skyViewUv(direction), 0.0).rgb, vec3(0.0));
    color = vec4(vec3(1.0) - exp(-radiance * params.viewport.z), 1.0);
}
