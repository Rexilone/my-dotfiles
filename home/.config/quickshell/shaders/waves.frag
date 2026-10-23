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
// волны: несколько слоёв плавных волн снизу, от поверхности темы к акценту
void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = res.x / res.y;
    float t = time * 0.25;
    vec3 col = mix(bg.rgb, surface.rgb, uv.y * 0.6);
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float h = 0.55 + fi * 0.08 + 0.035 * sin(uv.x * aspect * (2.0 + fi * 0.7) + t * (1.0 + fi * 0.35) + fi * 1.7)
                  + 0.02 * sin(uv.x * aspect * 5.3 - t * 0.8 + fi);
        float edge = smoothstep(h, h + 0.004, uv.y);
        vec3 c = mix(surface.rgb, accent.rgb, 0.25 + fi * 0.15);
        col = mix(col, c * (0.55 + fi * 0.1), edge * 0.55);
    }
    col += (hash(uv * res + time) - 0.5) * 0.01;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
