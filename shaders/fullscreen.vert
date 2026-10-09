#version 430 core
// Полноэкранный треугольник без буферов вершин: вершины (0,0), (2,0), (0,2) в UV.
// Видимая часть экрана покрывает UV в [0,1]x[0,1]. Вызов: glDrawArrays(GL_TRIANGLES, 0, 3) с пустым VAO.
out vec2 vUv;

void main()
{
    vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
    vUv = p;
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
