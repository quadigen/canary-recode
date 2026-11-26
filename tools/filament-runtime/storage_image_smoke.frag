#version 450
layout(set = 0, binding = 0) uniform sampler2D generated2;
layout(set = 0, binding = 1) uniform sampler3D generated3;
layout(location = 0) out vec4 color;
void main() {
    vec4 a = texelFetch(generated2, ivec2(2, 3), 0);
    vec4 b = texelFetch(generated3, ivec3(4, 1, 2), 0);
    color = vec4(a.b, b.r, b.b, 1.0);
}
