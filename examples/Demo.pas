{ Demo - консольный запуск приложения EngDemo (окно GLFW или OSMesa, OpenGL 4.3 core, рэгдолл).
  Запуск из корня репозитория:
    ./build/examples/Demo                       интерактивно (R - толчок, Esc - выход)
    ./build/examples/Demo --frames 120 --shot out/demo.png
    ./build/examples/Demo --offscreen --shot out/demo_osmesa.png   без окна, через OSMesa
  Код возврата: 0 - успех, 1 - ошибка окна/GL/шейдеров, 2 - GLFW (или OSMesa) не найдена.
  Логика - в src/app/EngDemo.pas. }
program Demo;

{$mode objfpc}{$H+}

uses
  EngDemo;

begin
  Halt(RunDemo);
end.
