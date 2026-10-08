#version 430 core
// Вершинный шейдер основного прохода: позиция, нормаль, цвет.
// Матрица нормалей - mat3(uModel): допускаются только жёсткие преобразования и равномерный масштаб.
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec3 aColor;

uniform mat4 uModel;
uniform mat4 uViewProj;
uniform mat4 uLightViewProj;

out vec3 vWorld;
out vec3 vNormal;
out vec3 vColor;
out vec4 vLightPos;

void main()
{
    vec4 world = uModel * vec4(aPos, 1.0);
    vWorld = world.xyz;
    vNormal = mat3(uModel) * aNormal;
    vColor = aColor;
    vLightPos = uLightViewProj * world;
    gl_Position = uViewProj * world;
}
