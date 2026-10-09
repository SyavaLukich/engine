{ GameCamera - камера от третьего лица в духе Super Mario 64: за спиной персонажа, поворот
  вслед за движением, если игрок не вращает камеру сам, столкновение со стенами (луч от цели).
  Классов нет. }
unit GameCamera;

{$mode objfpc}{$H+}

interface

uses
  Math, EngMath, GameLevel;

const
  CAM_DIST = 4.2;            { расстояние до цели, м }
  CAM_AIM_DIST = 2.2;        { расстояние при прицеливании, м }
  CAM_MIN_DIST = 0.6;
  CAM_FOLLOW_RATE = 2.2;     { рад/с: скорость поворота за персонажем }
  CAM_MANUAL_DELAY = 1.0;    { с после ручного поворота до автоматического }

type
  TThirdPerson = record
    Yaw: Double;             { направление от цели к камере: (sin Yaw, ., cos Yaw) }
    Pitch: Double;           { подъём камеры над целью, рад }
    Dist: Double;            { расстояние до камеры после учёта стен }
    Target: TVec3;
    Eye: TVec3;
    Forward: TVec3;          { единичный вектор взгляда }
    ManualTime: Double;      { с с последнего ручного поворота }
  end;

procedure CameraInit(var C: TThirdPerson; const Target: TVec3; Yaw: Double);
{ LookYaw, LookPitch - ручной поворот за шаг (рад). BodyYaw - направление лица персонажа,
  BodySpeed - его горизонтальная скорость, Aim - режим прицеливания. }
procedure CameraUpdate(var C: TThirdPerson; const L: TLevel; const Target: TVec3;
                       LookYaw, LookPitch, BodyYaw, BodySpeed: Double; Aim: Boolean; Dt: Double);
{ Направление взгляда камеры по горизонтали и вправо (единичные векторы в XZ). }
function CameraForwardXZ(const C: TThirdPerson): TVec3;
function CameraRightXZ(const C: TThirdPerson): TVec3;

implementation

procedure CameraInit(var C: TThirdPerson; const Target: TVec3; Yaw: Double);
begin
  FillChar(C, SizeOf(C), 0);
  C.Yaw := Yaw;
  C.Pitch := 0.28;
  C.Dist := CAM_DIST;
  C.Target := Target;
  C.Forward := V3(-Sin(Yaw), 0.0, -Cos(Yaw));
  C.Eye := V3Sub(Target, V3Mul(C.Forward, CAM_DIST));
end;

function CameraForwardXZ(const C: TThirdPerson): TVec3;
begin
  Result := V3Normalize(V3(-Sin(C.Yaw), 0.0, -Cos(C.Yaw)));
end;

function CameraRightXZ(const C: TThirdPerson): TVec3;
begin
  Result := V3Normalize(V3(Cos(C.Yaw), 0.0, -Sin(C.Yaw)));
end;

{ Кратчайший поворот угла к цели с ограничением шага. }
function Approach(Cur, Target, MaxStep: Double): Double;
var
  D: Double;
begin
  D := Target - Cur;
  while D > Pi do D := D - 2.0 * Pi;
  while D < -Pi do D := D + 2.0 * Pi;
  if Abs(D) <= MaxStep then
    Result := Cur + D
  else if D > 0.0 then
    Result := Cur + MaxStep
  else
    Result := Cur - MaxStep;
end;

procedure CameraUpdate(var C: TThirdPerson; const L: TLevel; const Target: TVec3;
                       LookYaw, LookPitch, BodyYaw, BodySpeed: Double; Aim: Boolean; Dt: Double);
var
  Off: TVec3;
  Want, Desired: Double;
  Hit: TRayHit;
  Len: Double;
begin
  if (Abs(LookYaw) > 1.0e-9) or (Abs(LookPitch) > 1.0e-9) then
    C.ManualTime := 0.0
  else
    C.ManualTime := C.ManualTime + Dt;
  C.Yaw := C.Yaw + LookYaw;
  C.Pitch := ClampD(C.Pitch + LookPitch, 0.05, 0.9);
  if (not Aim) and (BodySpeed > 1.5) and (C.ManualTime > CAM_MANUAL_DELAY) then
  begin
    { За спиной персонажа: направление от цели к камере совпадает с направлением назад от лица. }
    Want := BodyYaw + Pi;
    C.Yaw := Approach(C.Yaw, Want, CAM_FOLLOW_RATE * Dt);
  end;
  if Aim then
    Desired := CAM_AIM_DIST
  else
    Desired := CAM_DIST;
  C.Dist := C.Dist + (Desired - C.Dist) * MinD(1.0, 8.0 * Dt);
  Off := V3(Sin(C.Yaw) * Cos(C.Pitch), Sin(C.Pitch), Cos(C.Yaw) * Cos(C.Pitch));
  C.Target := Target;
  Len := C.Dist;
  { Столкновение: если между целью и камерой стена, камера подходит к ней. }
  Hit := LevelRayCast(L, Target, Off, Len);
  if Hit.Hit and (Hit.T < Len) then
    Len := MaxD(CAM_MIN_DIST, Hit.T - 0.25);
  C.Eye := V3MulAdd(Target, Off, Len);
  C.Forward := V3Normalize(V3Sub(Target, C.Eye));
end;

end.
