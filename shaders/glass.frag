#version 440
// Aero-style glass: samples a pre-blurred copy of the wallpaper at the
// surface's screen position, desaturates it a little, tints it with the
// accent colour and adds soft diagonal light streaks. Corners are rounded
// analytically so no mask texture is needed.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 region;      // x, y, w, h of this item in normalized screen coordinates
    vec4 uTint;        // accent colour
    vec2 itemSize;     // item size in pixels
    float radius;      // corner radius in pixels
    float uIntensity;  // 0..1 colour intensity
    float uSaturation; // 0..1 background saturation
    float uStreaks;    // 0..1 streak strength
    float uBrightness; // additive lift
    float alpha;       // overall glass alpha
};

layout(binding = 1) uniform sampler2D source;

float roundedBox(vec2 p, vec2 b, float r)
{
    vec2 q = abs(p) - b + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main()
{
    vec2 uv = region.xy + qt_TexCoord0 * region.zw;
    vec3 bg = texture(source, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
    float luma = dot(bg, vec3(0.299, 0.587, 0.114));
    vec3 c = mix(vec3(luma), bg, uSaturation);
    c = mix(c, uTint.rgb, uIntensity);
    // Light streaks fixed to the screen so they shimmer as windows move.
    float d = uv.x * 1.6 + uv.y * 0.9;
    float s = smoothstep(0.0, 1.0, 0.5 + 0.5 * sin(d * 11.0)) * smoothstep(0.0, 1.0, 0.5 + 0.5 * sin(d * 3.0 + 1.3));
    c += vec3(s * uStreaks * 0.10);
    c += vec3(uBrightness);

    float cover = 1.0;
    if (radius > 0.0) {
        vec2 p = (qt_TexCoord0 - 0.5) * itemSize;
        float dist = roundedBox(p, itemSize * 0.5, radius);
        cover = clamp(0.5 - dist, 0.0, 1.0);
    }
    float a = alpha * cover;
    fragColor = vec4(clamp(c, 0.0, 1.0) * a, a) * qt_Opacity;
}
