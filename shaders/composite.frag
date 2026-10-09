#version 430 core
// Композит: сложение блума, экспозиция, тонемаппинг (кривая Hable / Uncharted 2), гамма sRGB,
// цветокоррекция (насыщенность, контраст, разделение тонов) и виньетка. Результат - LDR-буфер.
in vec2 vUv;
layout(location = 0) out vec4 fragColor;

uniform sampler2D uScene;
uniform sampler2D uBloom0;
uniform sampler2D uBloom1;
uniform sampler2D uBloom2;
uniform sampler2D uBloom3;
uniform float uExposure;
uniform float uBloomStrength;
uniform float uSaturation;
uniform float uContrast;
uniform float uVignette;

vec3 Hable(vec3 x)
{
    const float A = 0.15;
    const float B = 0.50;
    const float C = 0.10;
    const float D = 0.20;
    const float E = 0.02;
    const float F = 0.30;
    return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
}

void main()
{
    vec3 bloom = texture(uBloom0, vUv).rgb * 0.8
               + texture(uBloom1, vUv).rgb * 0.9
               + texture(uBloom2, vUv).rgb
               + texture(uBloom3, vUv).rgb;
    vec3 hdr = (texture(uScene, vUv).rgb + bloom * uBloomStrength) * uExposure;

    vec3 c = Hable(hdr * 2.0) / Hable(vec3(11.2));
    c = pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2));

    float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
    c = mix(vec3(luma), c, uSaturation);
    c = (c - 0.5) * uContrast + 0.5;
    c += (1.0 - luma) * vec3(-0.010, 0.000, 0.012) + luma * vec3(0.012, 0.004, -0.010);

    vec2 d = vUv - 0.5;
    c *= 1.0 - uVignette * dot(d, d) * 2.0;
    fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
