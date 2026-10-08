# Скриншоты

Все кадры сняты на стенде без GPU (виртуальная машина, 2 vCPU). Файлы лежат в `docs/images/`. PNG пересжаты без потерь: пиксели сверены побайтно с исходным кадром (исходный PNG движка не сжат, по 0.9-2.7 МБ).

## Снимки поз рэгдолла: OpenGL 2.x через osmesa-main

Команда: `./build/examples/PoseSnapshot --osmesa libosmesa.so out`. Кадры рисуются фиксированным конвейером OpenGL 2.0 из osmesa-main и читаются `glReadPixels`. Тени и GGX здесь не используются.

| Файл | Сценарий |
|---|---|
| `pose_standing.png` | Стойка: рэгдолл держит баланс на полу. |
| `pose_push.png` | Толчок 80 Н·с в торс; снимок через 1 с после толчка, фигура снова стоит. |
| `pose_fallen.png` | Толчок 150 Н·с; через 3 с рэгдолл лежит на полу. |
| `pose_reach.png` | Правая кисть тянется к цели (-0.3, 1.05, 0.3) м. |

<table>
<tr>
<td><img src="images/pose_standing.png" width="320"><br>Стойка</td>
<td><img src="images/pose_push.png" width="320"><br>Толчок 80 Н·с, через 1 с</td>
</tr>
<tr>
<td><img src="images/pose_fallen.png" width="320"><br>Падение после толчка 150 Н·с</td>
<td><img src="images/pose_reach.png" width="320"><br>Дотягивание правой кистью</td>
</tr>
</table>

## Рендерер OpenGL 4.3: шейдеры, тени, GGX

Команда (Mesa 21.0.3, softpipe, переопределение версии до 4.3):

```sh
MESA_GL_VERSION_OVERRIDE=4.3 MESA_GLSL_VERSION_OVERRIDE=430 \
  ./build/examples/Demo --offscreen --osmesa /путь/libOSMesa.so.8 --frames 120 --shot docs/images/demo_gl43_softpipe.png
```

`demo_gl43_softpipe.png`: кадр 120 программы Demo, 1280×720. Видны шахматный пол, фигура с PBR-освещением и ACES, мягкая тень фигуры на полу. Кадр программный, на GPU не проверялся. Как собрать Mesa 21, см. [OSMESA.md](OSMESA.md).

<img src="images/demo_gl43_softpipe.png" width="640">

## Что не снято

Окно GLFW не снималось: на стенде нет GPU и дисплея. Кадры выше получены программным OpenGL, а не драйвером видеокарты.
