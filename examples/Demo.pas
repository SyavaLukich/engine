{ Demo - консольный запуск приложения EngDemo (окно GLFW, OpenGL 4.3 core, рэгдолл).
  Запуск из корня репозитория:
    ./build/examples/Demo                       интерактивно (R - толчок, Esc - выход)
    ./build/examples/Demo --frames 120 --shot out/demo.png
  Код возврата: 0 - успех, 1 - ошибка окна/GL/шейдеров, 2 - GLFW не найдена.
  Логика - в src/app/EngDemo.pas. }
program Demo;

{$mode objfpc}{$H+}

uses
  EngDemo;

begin
  Halt(RunDemo);
end.
