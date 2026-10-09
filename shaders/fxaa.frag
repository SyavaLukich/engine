#version 430 core
// Сглаживание краёв FXAA (упрощённая схема FXAA 3, пороги 1/8 и 1/32 как в исходной работе Lottes).
// Работает на LDR-изображении после композита. uFxaa = 0 - копия без изменений.
in vec2 vUv;
layout(location = 0) out vec4 fragColor;

uniform sampler2D uLdr;
uniform vec2 uTexel;         // 1 / размер LDR-буфера
uniform int uFxaa;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

void main()
{
    vec3 rgbM = texture(uLdr, vUv).rgb;
    if (uFxaa == 0)
    {
        fragColor = vec4(rgbM, 1.0);
        return;
    }
    vec3 rgbNW = texture(uLdr, vUv + vec2(-1.0, -1.0) * uTexel).rgb;
    vec3 rgbNE = texture(uLdr, vUv + vec2(1.0, -1.0) * uTexel).rgb;
    vec3 rgbSW = texture(uLdr, vUv + vec2(-1.0, 1.0) * uTexel).rgb;
    vec3 rgbSE = texture(uLdr, vUv + vec2(1.0, 1.0) * uTexel).rgb;
    float lNW = dot(rgbNW, LUMA);
    float lNE = dot(rgbNE, LUMA);
    float lSW = dot(rgbSW, LUMA);
    float lSE = dot(rgbSE, LUMA);
    float lM = dot(rgbM, LUMA);

    float lMin = min(lM, min(min(lNW, lNE), min(lSW, lSE)));
    float lMax = max(lM, max(max(lNW, lNE), max(lSW, lSE)));
    if (lMax - lMin < max(0.0312, lMax * 0.125))
    {
        fragColor = vec4(rgbM, 1.0);
        return;
    }

    vec2 dir;
    dir.x = -((lNW + lNE) - (lSW + lSE));
    dir.y = ((lNW + lSW) - (lNE + lSE));
    float dirReduce = max((lNW + lNE + lSW + lSE) * (0.25 * 0.125), 1.0 / 128.0);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = clamp(dir * rcpDirMin, vec2(-8.0), vec2(8.0)) * uTexel;

    vec3 rgbA = 0.5 * (texture(uLdr, vUv + dir * (1.0 / 3.0 - 0.5)).rgb
                     + texture(uLdr, vUv + dir * (2.0 / 3.0 - 0.5)).rgb);
    vec3 rgbB = rgbA * 0.5 + 0.25 * (texture(uLdr, vUv - dir * 0.5).rgb
                                     + texture(uLdr, vUv + dir * 0.5).rgb);
    float lB = dot(rgbB, LUMA);
    fragColor = vec4((lB < lMin || lB > lMax) ? rgbA : rgbB, 1.0);
}
