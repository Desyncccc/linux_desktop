#version 440
// Procedural default wallpaper "Aurora": deep blue field with luminous ribbons.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec4 baseColor;
    vec4 glowColor;
    float variant;
};

float ribbon(vec2 p, float offset, float freq, float amp, float width)
{
    float y = 0.55 + offset + sin(p.x * freq + offset * 9.0) * amp + sin(p.x * freq * 2.3 + 1.7) * amp * 0.35;
    float d = abs(p.y - y);
    return exp(-d * d / (width * width));
}

void main()
{
    vec2 uv = qt_TexCoord0;
    float aspect = resolution.x / max(resolution.y, 1.0);
    vec2 p = vec2(uv.x * aspect, uv.y);

    // Base vertical gradient with a bright horizon glow.
    vec3 top = baseColor.rgb * 0.35;
    vec3 bottom = baseColor.rgb * 1.05;
    vec3 col = mix(top, bottom, smoothstep(0.0, 1.0, uv.y));
    float horizon = exp(-pow((uv.y - 0.62) * 3.2, 2.0)) * exp(-pow((uv.x - 0.62) * 1.4, 2.0));
    col += glowColor.rgb * horizon * 0.40;

    // Flowing ribbons of light.
    float r = 0.0;
    r += ribbon(p, -0.05 + variant * 0.03, 2.1, 0.10, 0.030) * 0.9;
    r += ribbon(p, 0.02, 1.6, 0.13, 0.055) * 0.55;
    r += ribbon(p, 0.09, 2.7, 0.07, 0.018) * 0.8;
    r += ribbon(p, -0.14, 1.2, 0.16, 0.090) * 0.30;
    float fade = smoothstep(0.0, 0.35, uv.x) * (1.0 - smoothstep(0.75, 1.15, uv.x * 0.9 + 0.1));
    col += mix(glowColor.rgb, vec3(1.0), 0.30) * (1.0 - exp(-r * 1.1)) * (0.30 + 0.55 * fade);

    // Subtle radial vignette.
    float v = 1.0 - 0.35 * pow(length((uv - vec2(0.55, 0.55)) * vec2(1.1, 1.3)), 2.0);
    col *= v;
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
