{ GameInput - абстрактный ввод игрока на один шаг симуляции. Не зависит от GLFW: клавиши читает
  приложение (game/Gunner.pas) или сценарий в тестах. Классов нет. }
unit GameInput;

{$mode objfpc}{$H+}

interface

uses
  EngMath;

type
  TGameInput = record
    Move: TVec3;             { желаемое движение в мире, по XZ, длина от 0 до 1 }
    Jump: Boolean;           { прыжок нажат в этом шаге }
    Crouch: Boolean;         { присед удерживается }
    CrouchPressed: Boolean;  { присед нажат в этом шаге }
    Fire: Boolean;           { выстрел нажат в этом шаге }
    Kick: Boolean;           { удар ногой нажат в этом шаге }
    Aim: Boolean;            { прицеливание удерживается }
    CamYaw: Double;          { направление взгляда камеры, рад (угол вокруг оси Y) }
    AimDir: TVec3;           { единичный луч прицела: от глаза камеры через перекрестие }
    LookYaw: Double;         { ручной поворот камеры за шаг, рад }
    LookPitch: Double;       { ручной наклон камеры за шаг, рад }
  end;

procedure InputClear(var I: TGameInput);

implementation

procedure InputClear(var I: TGameInput);
begin
  FillChar(I, SizeOf(I), 0);
  I.AimDir := V3(0, 0, -1);
end;

end.
