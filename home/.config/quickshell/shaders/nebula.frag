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
// туманность: медленно плывущие облака и редкие мерцающие звёзды
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = vec2(uv.x * res.x / res.y, uv.y) * 2.2;
    float t = time * 0.02;
    float n = fbm(p + vec2(t, -t * 0.7) + fbm(p * 1.5 - t));
    vec3 col = mix(bg.rgb, accent.rgb * 0.75, smoothstep(0.35, 0.95, n));
    col = mix(col, surface.rgb * 1.4, smoothstep(0.55, 1.0, fbm(p * 2.0 - vec2(t * 1.3, 0.0))) * 0.5);
    vec2 g = floor(uv * res / 3.0);
    float star = step(0.9985, hash(g)) * (0.5 + 0.5 * sin(time * 2.0 + hash(g + 1.0) * 6.28));
    col += fg.rgb * star * 0.8;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
