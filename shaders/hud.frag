#version 430 core
// Интерфейс (HUD): плоский цвет с альфой, смешивание включает вызывающая сторона.
in vec4 vColor;
layout(location = 0) out vec4 fragColor;

void main()
{
    fragColor = vColor;
}
