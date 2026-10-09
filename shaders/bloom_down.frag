#version 430 core
// Понижение разрешения блума: среднее из 2x2 текселей источника (четыре билинейные выборки).
// При uMode = 0 (первый уровень, исходная HDR-сцена) сначала отбрасывается всё ниже порога яркости.
in vec2 vUv;
layout(location = 0) out vec4 fragColor;

uniform sampler2D uSrc;
uniform vec2 uSrcTexel;      // 1 / размер текстуры-источника
uniform float uThreshold;
uniform int uMode;

void main()
{
    vec2 o = uSrcTexel * 0.5;
    vec3 c = texture(uSrc, vUv + vec2(-o.x, -o.y)).rgb;
    c += texture(uSrc, vUv + vec2(o.x, -o.y)).rgb;
    c += texture(uSrc, vUv + vec2(-o.x, o.y)).rgb;
    c += texture(uSrc, vUv + vec2(o.x, o.y)).rgb;
    c *= 0.25;
    if (uMode == 0)
    {
        float l = max(c.r, max(c.g, c.b));
        c *= max(l - uThreshold, 0.0) / max(l, 1e-4);
    }
    fragColor = vec4(c, 1.0);
}
