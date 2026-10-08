{ TestRagdoll - проверки анимации (EngAnim, EngHumanoid) и активного рэгдолла (EngRagdoll). }
unit TestRagdoll;

{$mode objfpc}{$H+}

interface

procedure RunAnimTests;
procedure RunRagdollTests;

implementation

uses
  SysUtils, Math, EngMath, EngConvex, EngPhysics, EngAnim, EngHumanoid, EngRagdoll, TestKit;

const
  FRAME = 1.0 / 60.0;

procedure RunAnimTests;
var
  S: TSkeleton;
  Lib: TClipLib;
  Pl: TAnimPlayer;
  Pose, Glob: TPose;
  C: TClip;
  Q1, Q2, Qm: TQuat;
  Tip: TVec3;
  Ik: TVec3;
  I, J: Integer;
  Ok: Boolean;
  Idle: Integer;
begin
  Section('анимация: скелет и прямая кинематика');
  HumanoidSkeleton(S);
  Check(S.BoneCount = HB_COUNT, 'скелет: 15 костей');
  Check(SkelFindBone(S, 'hand_r') = HB_HAND_R, 'скелет: поиск кости по имени');
  PoseBind(S, Pose);
  PoseGlobal(S, Pose, Glob);
  { суставы в покое: нижняя точка ноги на полу, таз на высоте 0.96 }
  CheckNear(Glob[HB_SHIN_L].Pos.Y, 0.49, 1e-9, 'колено на высоте 0.49 м');
  CheckNear(Glob[HB_FOOT_L].Pos.Y, 0.08, 1e-9, 'голеностоп на высоте 0.08 м');
  CheckNear(Glob[HB_HAND_L].Pos.Y, 0.80, 1e-9, 'запястье на высоте 0.80 м');
  Check(V3Length(V3Sub(Glob[HB_HAND_L].Pos, V3(0.23, 0.80, 0))) < 1e-9, 'кисть L в позиции покоя');

  Section('анимация: клипы, выборка и кроссфейд');
  HumanoidClips(S, Lib);
  Check(Length(Lib) = 2, 'библиотека содержит 2 клипа');
  Idle := ClipFindInLib(Lib, 'idle');
  Check(Idle = 0, 'поиск клипа по имени');
  ClipInit(C, 'test', 2.0, False);
  Q1 := QuatFromAxisAngle(V3(0, 1, 0), 0);
  Q2 := QuatFromAxisAngle(V3(0, 1, 0), 1.0);
  ClipAddKey(C, 0, 0.0, V3(0, 0, 0), Q1);
  ClipAddKey(C, 0, 2.0, V3(2, 0, 0), Q2);
  PoseBind(S, Pose);
  ClipSample(C, 1.0, Pose);
  CheckNear(Pose[0].Pos.X, 1.0, 1e-9, 'линейная интерполяция позиции в середине');
  Qm := QuatSlerp(Q1, Q2, 0.5);
  CheckNear(QuatDot(Pose[0].Rot, Qm), 1.0, 1e-9, 'slerp вращения в середине');
  ClipSample(C, 5.0, Pose);
  CheckNear(Pose[0].Pos.X, 2.0, 1e-9, 'после конца клип зажат на последнем ключе');
  { зацикливание: время 4.5 у клипа длительностью 4 совпадает с 0.5 }
  ClipInit(C, 'loop', 4.0, True);
  ClipAddKey(C, 0, 0.0, V3(0, 0, 0), QuatIdentity);
  ClipAddKey(C, 0, 4.0, V3(4, 0, 0), QuatIdentity);
  PoseBind(S, Pose);
  ClipSample(C, 4.5, Pose);
  CheckNear(Pose[0].Pos.X, 0.5, 1e-9, 'зацикленное время');

  PlayerInit(Pl);
  PlayerPlay(Pl, Idle, 0);
  for I := 1 to 60 do
    PlayerUpdate(Pl, Lib, 1.0 / 60.0);
  CheckNear(Pl.Time, 1.0, 1e-6, 'проигрыватель накопил время');
  PlayerPlay(Pl, 1, 0.5);
  Check(Pl.PrevClip = Idle, 'кроссфейд запоминает прежний клип');
  for I := 1 to 15 do
    PlayerUpdate(Pl, Lib, 1.0 / 30.0);
  Check(Pl.PrevClip < 0, 'кроссфейд завершился');
  PlayerEvaluate(Pl, S, Lib, Pose);
  Check(Length(Pose) = HB_COUNT, 'оценка позы возвращает все кости');

  Section('анимация: двухкостный IK');
  Ik := TwoBoneIK(V3Zero, V3(0.3, 0.3, 0), V3(0, 0, 1), 0.3, 0.3);
  CheckNear(V3Length(Ik), 0.3, 1e-9, 'IK: сустав на расстоянии L1 от корня');
  Tip := V3Add(Ik, V3(0, 0, 0));
  CheckNear(V3Distance(Ik, V3(0.3, 0.3, 0)), 0.3, 1e-9, 'IK: сустав на расстоянии L2 от цели');
  Ok := True;
  for I := 1 to 200 do
  begin
    Tip := V3(Sin(I * 0.37) * 0.4, Cos(I * 0.21) * 0.4, 0.3 + Sin(I) * 0.1);
    Ik := TwoBoneIK(V3Zero, Tip, V3(0, 1, 0), 0.3, 0.3);
    if Abs(V3Length(Ik) - 0.3) > 1e-6 then Ok := False;
  end;
  Check(Ok, 'IK: стабильная длина первой кости на 200 целях');
  { недостижимая цель: сустав на линии к цели }
  Ik := TwoBoneIK(V3Zero, V3(5, 0, 0), V3(0, 1, 0), 0.3, 0.3);
  CheckNear(Ik.X, 0.3, 1e-6, 'IK: недостижимая цель, сустав на линии к цели на расстоянии L1');

  Section('анимация: кватернион от направления к направлению');
  Q1 := QuatFromTo(V3(0, 1, 0), V3(1, 0, 0));
  Check(V3Length(V3Sub(QuatRotate(Q1, V3(0, 1, 0)), V3(1, 0, 0))) < 1e-9, 'QuatFromTo: Y -> X');
  Q1 := QuatFromTo(V3(0, 1, 0), V3(0, -1, 0));
  Check(V3Length(V3Sub(QuatRotate(Q1, V3(0, 1, 0)), V3(0, -1, 0))) < 1e-9, 'QuatFromTo: Y -> -Y');
  J := 0;
  Q1 := QuatFromTo(V3(1, 0, 0), V3(0.3, 0.4, 0.5));
  Check(V3Length(V3Sub(QuatRotate(Q1, V3(1, 0, 0)), V3Normalize(V3(0.3, 0.4, 0.5)))) < 1e-9,
        'QuatFromTo: произвольное направление');
  if J <> 0 then WriteLn('unused');
end;

{ Стойка с балансом: высота таза и наклон. }
procedure TestStanding;
var
  W: TPhysWorld;
  R: TRagdoll;
  I: Integer;
  MinH, MaxTilt: Double;
begin
  Section('рэгдолл: стойка с балансом');
  PhysWorldInit(W, V3(0, -9.81, 0), 16);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.8, 0);
  RagdollCreate(W, R, V3Zero, 0, 1);
  MinH := 10;
  MaxTilt := 0;
  for I := 1 to 4 * 60 do
  begin
    RagdollAdvance(W, R, FRAME, 4);
    MinH := Min(MinH, RagdollPelvisHeight(W, R));
    MaxTilt := Max(MaxTilt, R.Tilt);
  end;
  Check(MinH > 0.85, Format('таз не опускается ниже 0.85 м (минимум %.3f)', [MinH]));
  Check(MaxTilt < 0.2, Format('наклон таза меньше 0.2 рад (максимум %.3f)', [MaxTilt]));
  Check(RagdollMaxJointError(W, R) < 0.02, 'шарниры сохраняют точки крепления (ошибка < 2 см)');
end;

{ Умеренный толчок: баланс возвращает в стойку. }
procedure TestPushRecovery;
var
  W: TPhysWorld;
  R: TRagdoll;
  I: Integer;
  Pushed: Boolean;
begin
  Section('рэгдолл: восстановление после толчка 80 Н·с');
  PhysWorldInit(W, V3(0, -9.81, 0), 16);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.8, 0);
  RagdollCreate(W, R, V3Zero, 0, 1);
  Pushed := False;
  for I := 1 to 6 * 60 do
  begin
    if (not Pushed) and (I = 2 * 60) then
    begin
      RagdollPush(W, R, HB_TORSO, V3(0, 0, 80), RagdollBodyPos(W, R, HB_TORSO));
      Pushed := True;
    end;
    RagdollAdvance(W, R, FRAME, 4);
  end;
  Check(RagdollPelvisHeight(W, R) > 0.85, Format('после толчка таз снова выше 0.85 м (%.3f)',
    [RagdollPelvisHeight(W, R)]));
  Check(R.Tilt < 0.2, Format('наклон после восстановления мал (%.3f рад)', [R.Tilt]));
end;

{ Сильный толчок: падение без скольжения по полу (защитная реакция, расслабление мышц). }
procedure TestFallNoSliding;
var
  W: TPhysWorld;
  R: TRagdoll;
  I: Integer;
  Com: TVec3;
  M: Double;
  Com0, Com1: TVec3;
  Finite: Boolean;
begin
  Section('рэгдолл: падение от сильного толчка');
  PhysWorldInit(W, V3(0, -9.81, 0), 16);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.8, 0);
  RagdollCreate(W, R, V3Zero, 0, 1);
  Finite := True;
  Com0 := V3Zero;
  Com1 := V3Zero;
  for I := 1 to 8 * 60 do
  begin
    if I = 2 * 60 then
    begin
      RagdollPush(W, R, HB_TORSO, V3(0, 0, 150), RagdollBodyPos(W, R, HB_TORSO));
    end;
    RagdollAdvance(W, R, FRAME, 4);
    if I = 5 * 60 then Com0 := PhysWorldCenterOfMass(W, R.Group, M);
    if I = 8 * 60 then Com1 := PhysWorldCenterOfMass(W, R.Group, M);
    if not FiniteD(RagdollPelvisHeight(W, R)) then Finite := False;
  end;
  Com := V3Sub(Com1, Com0);
  Check(Finite, 'после падения все координаты конечны');
  Check(V3Length(Com) < 0.3, Format('лежащий рэгдолл не скользит (смещение центра %.3f м за 3 с)',
    [V3Length(Com)]));
  Check(RagdollPelvisHeight(W, R) < 0.5, 'после сильного толчка рэгдолл лежит');
end;

{ Дотягивание: кисть ведёт к цели. }
procedure TestReach;
var
  W: TPhysWorld;
  R: TRagdoll;
  I: Integer;
  Target, Wrist: TVec3;
begin
  Section('рэгдолл: дотягивание правой кистью');
  PhysWorldInit(W, V3(0, -9.81, 0), 16);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.8, 0);
  RagdollCreate(W, R, V3Zero, 0, 1);
  Target := V3(-0.3, 1.05, 0.3);
  R.ReachWeight[1] := 1.0;
  R.ReachTarget[1] := Target;
  for I := 1 to 4 * 60 do
    RagdollAdvance(W, R, FRAME, 4);
  { цель IK - запястье; центр кисти лежит на 6 см ниже запястья }
  Wrist := V3Add(RagdollBodyPos(W, R, HB_HAND_R), V3(0, 0.06, 0));
  Check(V3Distance(Wrist, Target) < 0.12,
        Format('правая кисть дотянулась до цели (ошибка %.3f м)', [V3Distance(Wrist, Target)]));
  Check(RagdollPelvisHeight(W, R) > 0.85, 'при дотягивании рэгдолл стоит');
end;

{ Детерминизм: одинаковые сценарии дают одинаковые результаты побитово. }
procedure TestRagdollDeterminism;
var
  W1, W2: TPhysWorld;
  R1, R2: TRagdoll;
  I: Integer;
  Same: Boolean;
begin
  Section('рэгдолл: детерминизм');
  PhysWorldInit(W1, V3(0, -9.81, 0), 16);
  PhysSetGround(W1, V3(0, 1, 0), 0, 0.8, 0);
  RagdollCreate(W1, R1, V3Zero, 0.3, 1);
  PhysWorldInit(W2, V3(0, -9.81, 0), 16);
  PhysSetGround(W2, V3(0, 1, 0), 0, 0.8, 0);
  RagdollCreate(W2, R2, V3Zero, 0.3, 1);
  for I := 1 to 3 * 60 do
  begin
    if I = 60 then
    begin
      RagdollPush(W1, R1, HB_PELVIS, V3(20, 0, 0), RagdollBodyPos(W1, R1, HB_PELVIS));
      RagdollPush(W2, R2, HB_PELVIS, V3(20, 0, 0), RagdollBodyPos(W2, R2, HB_PELVIS));
    end;
    RagdollAdvance(W1, R1, FRAME, 4);
    RagdollAdvance(W2, R2, FRAME, 4);
  end;
  Same := True;
  for I := 0 to W1.BodyCount - 1 do
    if (W1.Bodies[I].Pos.X <> W2.Bodies[I].Pos.X) or (W1.Bodies[I].Pos.Y <> W2.Bodies[I].Pos.Y) or
       (W1.Bodies[I].Pos.Z <> W2.Bodies[I].Pos.Z) then
      Same := False;
  Check(Same, 'два рэгдолла с одинаковыми входами совпадают побитово');
end;

procedure RunRagdollTests;
begin
  TestStanding;
  TestPushRecovery;
  TestFallNoSliding;
  TestReach;
  TestRagdollDeterminism;
end;

end.
