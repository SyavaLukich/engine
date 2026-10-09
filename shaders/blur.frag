#version 430 core
// Разделяемое гауссово размытие: 5 билинейных выборок, веса 9-точечного ядра (sigma около 2.5 текселя).
in vec2 vUv;
layout(location = 0) out vec4 fragColor;

uniform sampler2D uSrc;
uniform vec2 uDir;           // шаг выборки: (1/ширина, 0) или (0, 1/высота) текстуры-источника

void main()
{
    vec3 c = texture(uSrc, vUv).rgb * 0.2270270270;
    c += texture(uSrc, vUv + uDir * 1.3846153846).rgb * 0.3162162162;
    c += texture(uSrc, vUv - uDir * 1.3846153846).rgb * 0.3162162162;
    c += texture(uSrc, vUv + uDir * 3.2307692308).rgb * 0.0702702703;
    c += texture(uSrc, vUv - uDir * 3.2307692308).rgb * 0.0702702703;
    fragColor = vec4(c, 1.0);
}
