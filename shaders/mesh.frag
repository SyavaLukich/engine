#version 430 core
// Фрагментный шейдер: GGX (Cook-Torrance) с диффузной частью Lambert, теневая карта с PCF 3x3,
// полусферический окружающий свет, тонемаппинг ACES (аппроксимация Narkowicz) и гамма 2.2.
in vec3 vWorld;
in vec3 vNormal;
in vec3 vColor;
in vec4 vLightPos;

out vec4 fragColor;

uniform vec3 uCamPos;
uniform vec3 uLightDir;      // единичный вектор К источнику света
uniform vec3 uLightColor;
uniform vec3 uSkyColor;
uniform vec3 uGroundColor;
uniform vec3 uTint;
uniform float uMetallic;
uniform float uRoughness;
uniform int uChecker;        // 1 - шахматный рисунок (пол)
uniform float uCheckerScale;
uniform sampler2DShadow uShadowMap;
uniform float uShadowTexel;

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

float GeometrySmith(float NdV, float NdL, float a)
{
    float k = a * 0.5;
    float gv = NdV / (NdV * (1.0 - k) + k);
    float gl = NdL / (NdL * (1.0 - k) + k);
    return gv * gl;
}

vec3 FresnelSchlick(vec3 f0, float VdH)
{
    return f0 + (1.0 - f0) * pow(1.0 - VdH, 5.0);
}

vec3 AcesFilm(vec3 x)
{
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
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

    vec3 F = FresnelSchlick(f0, VdH);
    float D = DistributionGGX(NdH, a);
    float G = GeometrySmith(NdV, NdL, a);
    vec3 spec = D * G * F / max(4.0 * NdV * NdL, 1e-4);
    vec3 kd = (1.0 - F) * (1.0 - uMetallic);
    vec3 diffuse = kd * albedo / PI;

    float shadow = ShadowFactor(vLightPos, n, l);
    vec3 direct = (diffuse + spec) * uLightColor * NdL * shadow;

    vec3 hemi = mix(uGroundColor, uSkyColor, n.y * 0.5 + 0.5);
    vec3 ambient = hemi * albedo * (1.0 - 0.5 * uMetallic);

    vec3 col = AcesFilm(direct + ambient);
    col = pow(col, vec3(1.0 / 2.2));
    fragColor = vec4(col, 1.0);
}
