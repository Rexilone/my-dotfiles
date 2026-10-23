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
// северное сияние: мягкие колышущиеся полосы цвета акцента над фоном темы
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = vec2(uv.x * res.x / res.y, uv.y);
    float t = time * 0.05;
    vec3 col = bg.rgb;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float y = 0.35 + 0.12 * fi + 0.12 * (fbm(vec2(p.x * 1.2 + t * (1.0 + fi * 0.3), fi * 3.1 + t)) - 0.5);
        float band = exp(-pow((uv.y - y) * (9.0 - fi * 2.0), 2.0));
        float shimmer = 0.6 + 0.4 * fbm(vec2(p.x * 6.0 - t * 2.0, fi));
        vec3 c = mix(accent.rgb, surface.rgb * 1.6 + 0.1, fi / 3.0);
        col += c * band * shimmer * (0.55 - fi * 0.12);
    }
    col += (hash(uv * res + time) - 0.5) * 0.012;   // лёгкое зерно против полос градиента
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
