{ EngHumanoid - человекоподобный скелет (15 костей) и процедурные клипы анимации.

  Раскладка (покой, персонаж смотрит на +Z, вверх +Y, ноги на полу y=0):
    - все кости в покое имеют единичное вращение, поэтому кость идёт вдоль мировой оси Y;
    - локальные позиции заданы относительно родительского сустава;
    - рост ~1.66 м, масса ~71 кг (см. EngRagdoll).

  Модуль содержит только данные и функции построения клипов - физики здесь нет. }
unit EngHumanoid;

{$mode objfpc}{$H+}

interface

uses
  Math, EngMath, EngAnim;

const
  HB_PELVIS = 0;
  HB_TORSO = 1;
  HB_HEAD = 2;
  HB_UARM_L = 3;
  HB_LARM_L = 4;
  HB_HAND_L = 5;
  HB_UARM_R = 6;
  HB_LARM_R = 7;
  HB_HAND_R = 8;
  HB_THIGH_L = 9;
  HB_SHIN_L = 10;
  HB_FOOT_L = 11;
  HB_THIGH_R = 12;
  HB_SHIN_R = 13;
  HB_FOOT_R = 14;
  HB_COUNT = 15;

{ Скелет в покое: кости и локальные позиции. }
procedure HumanoidSkeleton(var S: TSkeleton);

{ Клипы для библиотеки: 0 - стойка (дыхание), 1 - стойка с лёгким покачиванием рук. }
procedure HumanoidClips(const S: TSkeleton; var Lib: TClipLib);

{ Мировые (в покое) позиции суставов: сустав кости i = глобальная позиция кости i. }
procedure HumanoidBindJoints(const S: TSkeleton; var Joints: array of TVec3);

implementation

procedure HumanoidSkeleton(var S: TSkeleton);
var
  Id: TQuat;
begin
  Id := QuatIdentity;
  SkelInit(S, HB_COUNT);
  SkelSetBone(S, HB_PELVIS, -1, 'pelvis', V3(0, 0.96, 0), Id);
  SkelSetBone(S, HB_TORSO, HB_PELVIS, 'torso', V3(0, 0.10, 0), Id);
  SkelSetBone(S, HB_HEAD, HB_TORSO, 'head', V3(0, 0.32, 0), Id);
  SkelSetBone(S, HB_UARM_L, HB_TORSO, 'upper_arm_l', V3(0.20, 0.27, 0), Id);
  SkelSetBone(S, HB_LARM_L, HB_UARM_L, 'lower_arm_l', V3(0.02, -0.28, 0), Id);
  SkelSetBone(S, HB_HAND_L, HB_LARM_L, 'hand_l', V3(0.01, -0.25, 0), Id);
  SkelSetBone(S, HB_UARM_R, HB_TORSO, 'upper_arm_r', V3(-0.20, 0.27, 0), Id);
  SkelSetBone(S, HB_LARM_R, HB_UARM_R, 'lower_arm_r', V3(-0.02, -0.28, 0), Id);
  SkelSetBone(S, HB_HAND_R, HB_LARM_R, 'hand_r', V3(-0.01, -0.25, 0), Id);
  SkelSetBone(S, HB_THIGH_L, HB_PELVIS, 'thigh_l', V3(0.10, -0.06, 0), Id);
  SkelSetBone(S, HB_SHIN_L, HB_THIGH_L, 'shin_l', V3(0, -0.41, 0), Id);
  SkelSetBone(S, HB_FOOT_L, HB_SHIN_L, 'foot_l', V3(0, -0.41, 0), Id);
  SkelSetBone(S, HB_THIGH_R, HB_PELVIS, 'thigh_r', V3(-0.10, -0.06, 0), Id);
  SkelSetBone(S, HB_SHIN_R, HB_THIGH_R, 'shin_r', V3(0, -0.41, 0), Id);
  SkelSetBone(S, HB_FOOT_R, HB_SHIN_R, 'foot_r', V3(0, -0.41, 0), Id);
end;

procedure HumanoidBindJoints(const S: TSkeleton; var Joints: array of TVec3);
var
  Bind: TPose;
  Glob: TPose;
  I: Integer;
begin
  PoseBind(S, Bind);
  PoseGlobal(S, Bind, Glob);
  for I := 0 to S.BoneCount - 1 do
    if I <= High(Joints) then
      Joints[I] := Glob[I].Pos;
end;

{ Клип 0: стойка с дыханием (длительность 4 с, зацикленный). }
procedure BuildIdle(const S: TSkeleton; var C: TClip);
var
  T: Integer;
  Ang, Phase: Double;
  Q: TQuat;
begin
  ClipInit(C, 'idle', 4.0, True);
  for T := 0 to 4 do
  begin
    Phase := T * 1.0;
    Ang := 0.025 * Sin(Phase * ENG_PI / 2.0);
    Q := QuatFromAxisAngle(V3(1, 0, 0), Ang);
    ClipAddKey(C, HB_TORSO, Phase, V3(0, 0.10, 0), Q);
  end;
  { кости без ключей остаются в покое }
end;

{ Клип 1: стойка с покачиванием рук - плечи и локти колеблются в противофазе. }
procedure BuildSway(const S: TSkeleton; var C: TClip);
var
  T: Integer;
  Ph, Ang: Double;
begin
  ClipInit(C, 'sway', 3.0, True);
  for T := 0 to 6 do
  begin
    Ph := T * 0.5;
    Ang := 0.08 * Sin(Ph * 2.0 * ENG_PI / 3.0);
    ClipAddKey(C, HB_UARM_L, Ph, V3(0.20, 0.27, 0), QuatFromAxisAngle(V3(1, 0, 0), Ang));
    ClipAddKey(C, HB_UARM_R, Ph, V3(-0.20, 0.27, 0), QuatFromAxisAngle(V3(1, 0, 0), -Ang));
  end;
end;

procedure HumanoidClips(const S: TSkeleton; var Lib: TClipLib);
var
  C: TClip;
begin
  SetLength(Lib, 0);
  BuildIdle(S, C);
  ClipAddToLib(Lib, C);
  BuildSway(S, C);
  ClipAddToLib(Lib, C);
end;

end.
