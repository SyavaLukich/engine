#version 430 core
// Интерфейс (HUD): вершины заданы в пикселях окна, начало в левом верхнем углу.
layout(location = 0) in vec2 aPos;
layout(location = 1) in vec4 aColor;

uniform vec2 uViewport;      // ширина и высота окна, пиксели
out vec4 vColor;

void main()
{
    vColor = aColor;
    gl_Position = vec4(aPos.x / uViewport.x * 2.0 - 1.0, 1.0 - aPos.y / uViewport.y * 2.0, 0.0, 1.0);
}
