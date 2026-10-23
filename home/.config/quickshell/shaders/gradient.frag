#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec2 res;
    vec4 bg;
    vec4 accent;
    vec4 surface;
    vec4 fg;
};
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.0; a *= 0.5; }
    return v;
}
// градиент: медленно поворачивающийся переход между цветами темы — самый лёгкий
void main() {
    vec2 uv = qt_TexCoord0 - 0.5;
    float a = time * 0.03;
    float d = dot(uv, vec2(cos(a), sin(a))) + 0.5;
    vec3 col = mix(bg.rgb, mix(surface.rgb * 1.3, accent.rgb * 0.7, 0.5 + 0.5 * sin(time * 0.05)), smoothstep(0.0, 1.2, d));
    col += (hash(qt_TexCoord0 * res + time) - 0.5) * 0.01;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
