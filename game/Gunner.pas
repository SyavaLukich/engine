{ Gunner - экшн-шутер от третьего лица: тонкая программа, вся логика в GameApp (game/src).
  Запуск и параметры - см. game/src/GameApp.pas и docs/GAME.md. Классов нет. }
program Gunner;

{$mode objfpc}{$H+}

uses
  GameApp;

begin
  Halt(RunGunner);
end.
