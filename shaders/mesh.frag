#version 430 core
// Фрагментный шейдер основного прохода. Выход - линейная HDR-яркость без тонемаппинга:
// тонемаппинг делает композит (как в Fox Engine, где тонемаппинг стоит раньше LDR-постобработки).
//
// Диффузная часть (uDiffuseMode): 0 - Lambert, 1 - Burley (Disney, 2012),
// 2 - Oren-Nayar (качественная модель в форме Гоутанды/Фуджи). Формулы совпадают с src/render/EngBRDF.pas.
// Блик: GGX, высотно-коррелированная геометрия Smith (Heitz, 2014), Fresnel Schlick.
// Тени: карта глубины с PCF 3x3. Туман: экспоненциальный, плотность падает с высотой.

in vec3 vWorld;
in vec3 vNormal;
in vec3 vColor;
in vec4 vLightPos;

layout(location = 0) out vec4 fragColor;

uniform vec3 uCamPos;
uniform vec3 uLightDir;      // единичный вектор К источнику света
uniform vec3 uLightColor;
uniform vec3 uSkyColor;
uniform vec3 uGroundColor;
uniform vec3 uTint;
uniform vec3 uEmission;      // собственное свечение (трассеры, вспышки), линейная яркость
uniform float uMetallic;
uniform float uRoughness;
uniform int uChecker;        // 1 - шахматный рисунок (пол)
uniform float uCheckerScale;
uniform sampler2DShadow uShadowMap;
uniform float uShadowTexel;
uniform int uDiffuseMode;    // 0 - Lambert, 1 - Burley, 2 - Oren-Nayar
uniform vec3 uFogColor;
uniform float uFogDensity;   // 0 - тумана нет
uniform float uFogFalloff;   // 1/м

const float PI = 3.14159265358979;

float ShadowFactor(vec4 lp, vec3 n, vec3 l)
{
    vec3 p = lp.xyz / lp.w * 0.5 + 0.5;
    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 || p.z > 1.0)
        return 1.0;
    float bias = max(0.0015 * (1.0 - dot(n, l)), 0.0006);
    float s = 0.0;
    for (int x = -1; x <= 1; ++x)
        for (int y = -1; y <= 1; ++y)
            s += texture(uShadowMap, vec3(p.xy + vec2(x, y) * uShadowTexel, p.z - bias));
    return s / 9.0;
}

float DistributionGGX(float NdH, float a)
{
    float a2 = a * a;
    float d = NdH * NdH * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d);
}

// Высотно-коррелированная видимость Smith; множитель 0.5 уже включает деление на 4 NdL NdV.
float VisibilitySmith(float NdL, float NdV, float a)
{
    float a2 = a * a;
    float gv = NdL * sqrt(NdV * NdV * (1.0 - a2) + a2);
    float gl = NdV * sqrt(NdL * NdL * (1.0 - a2) + a2);
    return 0.5 / max(gv + gl, 1e-5);
}

vec3 FresnelSchlick(vec3 f0, float VdH)
{
    return f0 + (1.0 - f0) * pow(1.0 - VdH, 5.0);
}

// Burley: множитель к albedo, включая 1/PI. Для полувектора LdH = VdH.
float BurleyFactor(float NdL, float NdV, float LdH, float rough)
{
    float fd90 = 0.5 + 2.0 * rough * LdH * LdH;
    float fl = 1.0 + (fd90 - 1.0) * pow(1.0 - NdL, 5.0);
    float fv = 1.0 + (fd90 - 1.0) * pow(1.0 - NdV, 5.0);
    return fl * fv / PI;
}

// Oren-Nayar, качественная модель: множитель к albedo, включая 1/PI. LdV = dot(l, v).
float OrenNayarFactor(float NdL, float NdV, float LdV, float rough)
{
    float s2 = rough * rough;
    float A = 1.0 - 0.5 * s2 / (s2 + 0.33);
    float B = 0.45 * s2 / (s2 + 0.09);
    float s = LdV - NdL * NdV;
    float t = s > 0.0 ? max(NdL, NdV) : 1.0;
    return (A + B * max(s, 0.0) / max(t, 1e-4)) / PI;
}

void main()
{
    vec3 n = normalize(vNormal);
    vec3 v = normalize(uCamPos - vWorld);
    vec3 l = normalize(uLightDir);

    vec3 albedo = vColor * uTint;
    if (uChecker == 1)
    {
        float c = mod(floor(vWorld.x * uCheckerScale) + floor(vWorld.z * uCheckerScale), 2.0);
        albedo *= mix(0.55, 0.85, c);
    }

    float rough = clamp(uRoughness, 0.04, 1.0);
    float a = rough * rough;
    vec3 f0 = mix(vec3(0.04), albedo, uMetallic);

    vec3 h = normalize(l + v);
    float NdL = max(dot(n, l), 0.0);
    float NdV = max(dot(n, v), 1e-4);
    float NdH = max(dot(n, h), 0.0);
    float VdH = max(dot(v, h), 0.0);
    float LdV = dot(l, v);

    vec3 F = FresnelSchlick(f0, VdH);
    vec3 spec = DistributionGGX(NdH, a) * VisibilitySmith(NdL, NdV, a) * F;
    vec3 kd = (1.0 - F) * (1.0 - uMetallic);

    float dif;
    if (uDiffuseMode == 1)
        dif = BurleyFactor(NdL, NdV, VdH, rough);
    else if (uDiffuseMode == 2)
        dif = OrenNayarFactor(NdL, NdV, LdV, rough);
    else
        dif = 1.0 / PI;

    float shadow = ShadowFactor(vLightPos, n, l);
    vec3 direct = (kd * albedo * dif + spec) * uLightColor * NdL * shadow;

    vec3 hemi = mix(uGroundColor, uSkyColor, n.y * 0.5 + 0.5);
    vec3 ambient = hemi * albedo * (1.0 - 0.5 * uMetallic);
    vec3 r = reflect(-v, n);
    vec3 envR = mix(uGroundColor, uSkyColor, r.y * 0.5 + 0.5);
    vec3 ambientSpec = envR * f0 * (1.0 - 0.6 * rough) * 0.35;

    vec3 col = direct + ambient + ambientSpec;
    float dist = length(uCamPos - vWorld);
    float fog = 1.0 - exp(-uFogDensity * dist * exp(-uFogFalloff * max(vWorld.y, 0.0)));
    col = mix(col, uFogColor, clamp(fog, 0.0, 1.0));
    fragColor = vec4(col + uEmission, 1.0);
}
