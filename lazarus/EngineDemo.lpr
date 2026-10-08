{ Проект Lazarus: запуск приложения EngDemo (окно GLFW, OpenGL 4.3 core, рэгдолл).
  Открыть lazarus/EngineDemo.lpi в Lazarus и собрать (Запуск > Собрать). Рабочий каталог запуска -
  корень репозитория: там лежит каталог shaders/ (или укажите --shaders в параметрах запуска).
  Коды возврата: 0 - успех; 1 - ошибка окна, контекста OpenGL 4.3 или шейдеров; 2 - GLFW не найдена.
  Код приложения общий с examples/Demo.pas (юнит src/app/EngDemo.pas). }
program EngineDemo;

{$mode objfpc}{$H+}

uses
  EngDemo;

begin
  Halt(RunDemo);
end.
