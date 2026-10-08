{ EngRagdoll - активный рэгдолл человека: тела и шарниры физики, приводы к позе анимации и
  поведения в духе Euphoria (баланс, защитная реакция при падении, дотягивание рукой).

  Идея (описательная, не воспроизводит закрытый код NaturalMotion):
    - каждая кость анимации соответствует телу физики; шарниры приводятся к позе анимации
      ограниченным по моменту PD-приводом (servo по скорости, см. EngPhysics);
    - поведения меняют цели приводов и эффекторы каждый подшаг физики:
        баланс:      наклон туловища (стратегия бедра) и поворот голеностопа (стратегия голеностопа)
                     по ошибке проекции центра масс относительно центра опоры;
        защита:      при наклоне таза больше порога руки выставляются к земле впереди и мышцы ног
                     ослабляются (падение с частичным расслаблением);
        дотягивание: кисть ведётся к мировой точке эффектором;
    - при отсутствии поведения рэгдолл остаётся пассивным (мышцы Muscle = 0).

  Классов нет: состояние - запись TRagdoll, функции принимают мир физики явным параметром. }
unit EngRagdoll;

{$mode objfpc}{$H+}

interface

uses
  Math, EngMath, EngConvex, EngPhysics, EngAnim, EngHumanoid;

type
  TRagdoll = record
    Skel: TSkeleton;
    Clips: TClipLib;
    Player: TAnimPlayer;
    Pose: TPose;                          { локальная поза анимации }
    Global: TPose;                        { глобальная поза анимации (система скелета) }
    Bodies: array[0..HB_COUNT - 1] of Integer;   { индекс тела физики по кости }
    JointOf: array[0..HB_COUNT - 1] of Integer;  { индекс шарнира к родителю; -1 для таза }
    Effector: array[0..2] of Integer;     { 0 - ориентация таза, 1 - левая кисть, 2 - правая кисть }
    Group: Integer;                       { группа столкновений: тела рэгдолла не сталкиваются между собой }
    Heading: Double;                      { поворот вокруг Y, рад }
    HeadingQ: TQuat;
    Origin: TVec3;                        { точка на полу под тазом в момент создания }
    Muscle: Double;                       { общая сила мышц 0..1 }
    BalanceOn: Boolean;
    BalanceKHip: Double;                  { рад на м: наклон туловища по ошибке центра масс }
    BalanceKAnkle: Double;                { рад на м: поворот голеностопа }
    BalanceSign: Double;                  { знак обратной связи баланса (+1 или -1) }
    BraceAuto: Boolean;                   { включать защитную реакцию автоматически }
    Brace: Double;                        { текущий вес защитной реакции 0..1 }
    ReachWeight: array[0..1] of Double;   { вес дотягивания для левой и правой руки }
    ReachTarget: array[0..1] of TVec3;    { мировые цели кистей }
    Support: TVec3;                       { центр опоры (мир), последнее известное значение }
    Tilt: Double;                         { угол наклона таза от вертикали, рад }
    Time: Double;
  end;

{ Создание рэгдолла в мире: тазом на полу в точке Origin, поворот Heading (вокруг Y). }
procedure RagdollCreate(var W: TPhysWorld; var R: TRagdoll; const Origin: TVec3;
                        Heading: Double; Group: Integer);
{ Шаг: анимация, затем FrameDt, разбитый на Substeps подшагов физики с обновлением поведений. }
procedure RagdollAdvance(var W: TPhysWorld; var R: TRagdoll; FrameDt: Double; Substeps: Integer);
{ Импульс в мировой точке на кость (например, толчок). }
procedure RagdollPush(var W: TPhysWorld; const R: TRagdoll; Bone: Integer; const Impulse, WorldPoint: TVec3);
function RagdollBodyPos(const W: TPhysWorld; const R: TRagdoll; Bone: Integer): TVec3;
function RagdollPelvisHeight(const W: TPhysWorld; const R: TRagdoll): Double;
{ Максимальная ошибка совпадения точек шарниров (диагностика качества решения), м. }
function RagdollMaxJointError(const W: TPhysWorld; const R: TRagdoll): Double;

implementation

type
  TJointSpec = record
    Bone: Integer;      { ребёнок }
    Hinge: Boolean;
    LimitLo, LimitHi: Double;
    Stiffness, Damping, MaxTorque: Double;
  end;

const
  { шарниры: по одному на кость кроме таза; жёсткость и предел момента подобраны по массе }
  JOINT_COUNT = 14;
  RD_JOINT_SPECS: array[0..JOINT_COUNT - 1] of TJointSpec = (
    (Bone: HB_TORSO;   Hinge: False; LimitLo: 0; LimitHi: 0; Stiffness: 300; Damping: 30; MaxTorque: 300),
    (Bone: HB_HEAD;    Hinge: False; LimitLo: 0; LimitHi: 0; Stiffness: 80;  Damping: 10; MaxTorque: 60),
    (Bone: HB_UARM_L;  Hinge: False; LimitLo: 0; LimitHi: 0; Stiffness: 150; Damping: 15; MaxTorque: 150),
    (Bone: HB_LARM_L;  Hinge: True;  LimitLo: -2.4; LimitHi: 0.05; Stiffness: 120; Damping: 12; MaxTorque: 120),
    (Bone: HB_HAND_L;  Hinge: False; LimitLo: 0; LimitHi: 0; Stiffness: 40;  Damping: 5;  MaxTorque: 30),
    (Bone: HB_UARM_R;  Hinge: False; LimitLo: 0; LimitHi: 0; Stiffness: 150; Damping: 15; MaxTorque: 150),
    (Bone: HB_LARM_R;  Hinge: True;  LimitLo: -2.4; LimitHi: 0.05; Stiffness: 120; Damping: 12; MaxTorque: 120),
    (Bone: HB_HAND_R;  Hinge: False; LimitLo: 0; LimitHi: 0; Stiffness: 40;  Damping: 5;  MaxTorque: 30),
    (Bone: HB_THIGH_L; Hinge: False; LimitLo: 0; LimitHi: 0; Stiffness: 350; Damping: 35; MaxTorque: 400),
    (Bone: HB_SHIN_L;  Hinge: True;  LimitLo: -0.05; LimitHi: 2.5; Stiffness: 250; Damping: 25; MaxTorque: 300),
    (Bone: HB_FOOT_L;  Hinge: False; LimitLo: 0; LimitHi: 0; Stiffness: 150; Damping: 15; MaxTorque: 150),
    (Bone: HB_THIGH_R; Hinge: False; LimitLo: 0; LimitHi: 0; Stiffness: 350; Damping: 35; MaxTorque: 400),
    (Bone: HB_SHIN_R;  Hinge: True;  LimitLo: -0.05; LimitHi: 2.5; Stiffness: 250; Damping: 25; MaxTorque: 300),
    (Bone: HB_FOOT_R;  Hinge: False; LimitLo: 0; LimitHi: 0; Stiffness: 150; Damping: 15; MaxTorque: 150)
  );

{ Вспомогательно: тип тела по кости. }
type
  TBodySpec = record
    Kind: Integer;      { 0 - бокс, 1 - сфера, 2 - капсула }
    Half: TVec3;        { полуразмеры бокса }
    Radius: Double;     { радиус сферы/капсулы }
    HalfSeg: Double;    { полудлина отрезка капсулы }
    Mass: Double;
  end;

const
  BODY_KIND_BOX = 0;
  BODY_KIND_SPHERE = 1;
  BODY_KIND_CAPSULE = 2;

function BodySpecOf(Bone: Integer): TBodySpec;
begin
  Result.Half := V3Zero;
  Result.Radius := 0;
  Result.HalfSeg := 0;
  case Bone of
    HB_PELVIS: begin Result.Kind := BODY_KIND_BOX; Result.Half := V3(0.16, 0.08, 0.11); Result.Mass := 11; end;
    HB_TORSO:  begin Result.Kind := BODY_KIND_BOX; Result.Half := V3(0.17, 0.14, 0.10); Result.Mass := 22; end;
    HB_HEAD:   begin Result.Kind := BODY_KIND_SPHERE; Result.Radius := 0.12; Result.Mass := 5; end;
    HB_UARM_L, HB_UARM_R:
      begin Result.Kind := BODY_KIND_CAPSULE; Result.Radius := 0.05; Result.HalfSeg := 0.09; Result.Mass := 2.2; end;
    HB_LARM_L, HB_LARM_R:
      begin Result.Kind := BODY_KIND_CAPSULE; Result.Radius := 0.045; Result.HalfSeg := 0.08; Result.Mass := 1.6; end;
    HB_HAND_L, HB_HAND_R:
      begin Result.Kind := BODY_KIND_SPHERE; Result.Radius := 0.06; Result.Mass := 0.6; end;
    HB_THIGH_L, HB_THIGH_R:
      begin Result.Kind := BODY_KIND_CAPSULE; Result.Radius := 0.075; Result.HalfSeg := 0.13; Result.Mass := 7.5; end;
    HB_SHIN_L, HB_SHIN_R:
      begin Result.Kind := BODY_KIND_CAPSULE; Result.Radius := 0.06; Result.HalfSeg := 0.145; Result.Mass := 3.5; end;
    HB_FOOT_L, HB_FOOT_R:
      begin Result.Kind := BODY_KIND_BOX; Result.Half := V3(0.06, 0.04, 0.12); Result.Mass := 1.2; end;
  end;
end;

function ShapeOf(const Sp: TBodySpec): TConvexShape;
begin
  case Sp.Kind of
    BODY_KIND_BOX: Result := MakeBoxShape(Sp.Half);
    BODY_KIND_SPHERE: Result := MakeSphereShape(Sp.Radius);
  else
    Result := MakeCapsuleShape(Sp.Radius, Sp.HalfSeg);
  end;
end;

{ Смещение центра тела кости относительно её сустава (в системе скелета, покой). }
function BodyCenter(const J: array of TVec3; Bone: Integer): TVec3;
begin
  case Bone of
    HB_PELVIS: Result := J[HB_PELVIS];
    HB_TORSO: Result := V3Add(J[HB_TORSO], V3(0, 0.14, 0));
    HB_HEAD: Result := V3Add(J[HB_HEAD], V3(0, 0.14, 0));
    HB_UARM_L: Result := V3Mul(V3Add(J[HB_UARM_L], J[HB_LARM_L]), 0.5);
    HB_LARM_L: Result := V3Mul(V3Add(J[HB_LARM_L], J[HB_HAND_L]), 0.5);
    HB_HAND_L: Result := V3Add(J[HB_HAND_L], V3(0, -0.06, 0));
    HB_UARM_R: Result := V3Mul(V3Add(J[HB_UARM_R], J[HB_LARM_R]), 0.5);
    HB_LARM_R: Result := V3Mul(V3Add(J[HB_LARM_R], J[HB_HAND_R]), 0.5);
    HB_HAND_R: Result := V3Add(J[HB_HAND_R], V3(0, -0.06, 0));
    HB_THIGH_L: Result := V3Mul(V3Add(J[HB_THIGH_L], J[HB_SHIN_L]), 0.5);
    HB_SHIN_L: Result := V3Mul(V3Add(J[HB_SHIN_L], J[HB_FOOT_L]), 0.5);
    HB_FOOT_L: Result := V3Add(J[HB_FOOT_L], V3(0, -0.04, 0.06));
    HB_THIGH_R: Result := V3Mul(V3Add(J[HB_THIGH_R], J[HB_SHIN_R]), 0.5);
    HB_SHIN_R: Result := V3Mul(V3Add(J[HB_SHIN_R], J[HB_FOOT_R]), 0.5);
    HB_FOOT_R: Result := V3Add(J[HB_FOOT_R], V3(0, -0.04, 0.06));
  else
    Result := J[Bone];
  end;
end;

{ Вид шарнира по признаку сгиба: hinge (ось) или ball. }
function JOINT_KIND_OF(Hinge: Boolean): TPhysJointKind;
begin
  if Hinge then Result := jkHinge else Result := jkBall;
end;

procedure RagdollCreate(var W: TPhysWorld; var R: TRagdoll; const Origin: TVec3;
                        Heading: Double; Group: Integer);
var
  Bi: Integer;
  Joints: array[0..HB_COUNT - 1] of TVec3;
  Centers: array[0..HB_COUNT - 1] of TVec3;
  Sp: TBodySpec;
  Body: TRigidBody;
  Jt: TPhysJoint;
  Ef: TPhysEffector;
  Parent: Integer;
  K: Integer;
begin
  HumanoidSkeleton(R.Skel);
  HumanoidClips(R.Skel, R.Clips);
  PlayerInit(R.Player);
  PlayerPlay(R.Player, 0, 0);
  R.Origin := Origin;
  R.Group := Group;
  R.Heading := Heading;
  R.HeadingQ := QuatFromAxisAngle(V3(0, 1, 0), Heading);
  R.Muscle := 1.0;
  R.BalanceOn := True;
  R.BalanceKHip := 1.0;
  R.BalanceKAnkle := 0.5;
  R.BalanceSign := 1.0;
  R.BraceAuto := True;
  R.Brace := 0;
  R.ReachWeight[0] := 0;
  R.ReachWeight[1] := 0;
  R.ReachTarget[0] := V3Zero;
  R.ReachTarget[1] := V3Zero;
  R.Support := Origin;
  R.Tilt := 0;
  R.Time := 0;

  { тела: центры и формы в покое (в системе скелета) }
  HumanoidBindJoints(R.Skel, Joints);
  for Bi := 0 to HB_COUNT - 1 do
  begin
    Centers[Bi] := BodyCenter(Joints, Bi);
    Sp := BodySpecOf(Bi);
    Body := PhysMakeBody(ShapeOf(Sp), V3Add(Origin, QuatRotate(R.HeadingQ, Centers[Bi])),
                         R.HeadingQ, Sp.Mass);
    Body.Group := Group;
    Body.Friction := 0.8;
    Body.Restitution := 0.0;
    Body.LinDamping := 0.02;
    Body.AngDamping := 0.05;
    R.Bodies[Bi] := PhysAddBody(W, Body);
  end;

  { шарниры: тела соединены в точках сустава, анкеры - в локальных системах тел (тела без поворота в покое) }
  R.JointOf[HB_PELVIS] := -1;
  for K := 0 to JOINT_COUNT - 1 do
  begin
    Bi := RD_JOINT_SPECS[K].Bone;
    Parent := R.Skel.Parent[Bi];
    Jt := PhysDefaultJoint(JOINT_KIND_OF(RD_JOINT_SPECS[K].Hinge), R.Bodies[Parent], R.Bodies[Bi]);
    Jt.AnchorA := V3Sub(Joints[Bi], Centers[Parent]);
    Jt.AnchorB := V3Sub(Joints[Bi], Centers[Bi]);
    Jt.Axis := V3(1, 0, 0);
    Jt.LimitEnabled := RD_JOINT_SPECS[K].Hinge;
    Jt.LimitLo := RD_JOINT_SPECS[K].LimitLo;
    Jt.LimitHi := RD_JOINT_SPECS[K].LimitHi;
    Jt.DriveEnabled := True;
    Jt.TargetRel := QuatIdentity;
    Jt.Stiffness := RD_JOINT_SPECS[K].Stiffness;
    Jt.Damping := RD_JOINT_SPECS[K].Damping;
    Jt.MaxTorque := RD_JOINT_SPECS[K].MaxTorque;
    Jt.Strength := 1.0;
    R.JointOf[Bi] := PhysAddJoint(W, Jt);
  end;

  { эффекторы: таз (ориентация), кисти (дотягивание и защитная реакция) }
  Ef := PhysDefaultEffector(R.Bodies[HB_PELVIS]);
  Ef.UseOrient := True;
  Ef.TargetRot := R.HeadingQ;
  Ef.OriStiffness := 40;
  Ef.OriDamping := 8;
  Ef.OriMaxTorque := 200;
  Ef.PosStiffness := 0;
  R.Effector[0] := PhysAddEffector(W, Ef);

  Ef := PhysDefaultEffector(R.Bodies[HB_HAND_L]);
  Ef.PosStiffness := 0;
  R.Effector[1] := PhysAddEffector(W, Ef);

  Ef := PhysDefaultEffector(R.Bodies[HB_HAND_R]);
  Ef.PosStiffness := 0;
  R.Effector[2] := PhysAddEffector(W, Ef);
end;

function RagdollBodyPos(const W: TPhysWorld; const R: TRagdoll; Bone: Integer): TVec3;
begin
  Result := W.Bodies[R.Bodies[Bone]].Pos;
end;

function RagdollPelvisHeight(const W: TPhysWorld; const R: TRagdoll): Double;
begin
  Result := W.Bodies[R.Bodies[HB_PELVIS]].Pos.Y;
end;

procedure RagdollPush(var W: TPhysWorld; const R: TRagdoll; Bone: Integer; const Impulse, WorldPoint: TVec3);
begin
  PhysApplyImpulse(W.Bodies[R.Bodies[Bone]], Impulse, WorldPoint);
end;

function RagdollMaxJointError(const W: TPhysWorld; const R: TRagdoll): Double;
var
  K, J: Integer;
  Pa, Pb: TVec3;
  Ea: Double;
begin
  Result := 0;
  for K := 0 to JOINT_COUNT - 1 do
  begin
    J := R.JointOf[RD_JOINT_SPECS[K].Bone];
    Pa := V3Add(W.Bodies[W.Joints[J].A].Pos, QuatRotate(W.Bodies[W.Joints[J].A].Rot, W.Joints[J].AnchorA));
    Pb := V3Add(W.Bodies[W.Joints[J].B].Pos, QuatRotate(W.Bodies[W.Joints[J].B].Rot, W.Joints[J].AnchorB));
    Ea := V3Distance(Pa, Pb);
    if Ea > Result then Result := Ea;
  end;
end;

{ Целевая относительная ориентация кости Bone относительно родителя в анимации. }
function AnimRel(const R: TRagdoll; Bone: Integer): TQuat;
var
  P: Integer;
begin
  P := R.Skel.Parent[Bone];
  Result := QuatNormalize(QuatMul(QuatConj(R.Global[P].Rot), R.Global[Bone].Rot));
end;

{ Поза руки для дотягивания: относительные вращения плеча и локтя (в системах туловища и плеча),
  рассчитанные двухкостным IK в системе туловища. Внутренние моменты, без внешней силы. }
procedure ReachRel(var W: TPhysWorld; const R: TRagdoll; Side: Integer; out ShoulderRel, ElbowRel: TQuat);
var
  UBone, LBone, TorsoJ: Integer;
  JU, Torso: PRigidBody;
  Sh, Mid, Tl: TVec3;
  D1, D2: TVec3;
  Gu, Gf: TQuat;
  J: Integer;
begin
  if Side = 0 then UBone := HB_UARM_L else UBone := HB_UARM_R;
  if Side = 0 then LBone := HB_LARM_L else LBone := HB_LARM_R;
  TorsoJ := HB_TORSO;
  Torso := @W.Bodies[R.Bodies[TorsoJ]];
  { цель в системе торса }
  Tl := QuatInvRotate(Torso^.Rot, V3Sub(R.ReachTarget[Side], Torso^.Pos));
  J := R.JointOf[UBone];
  Sh := W.Joints[J].AnchorA;                 { плечо в системе торса }
  { плечо-локоть-запястье: длины из геометрии скелета покоя }
  Mid := TwoBoneIK(Sh, Tl, V3(0, 0, -1), 0.28, 0.25);
  D1 := V3Normalize(V3Sub(Mid, Sh));
  D2 := V3Normalize(V3Sub(Tl, Mid));
  Gu := QuatFromTo(V3(0, -1, 0), D1);
  Gf := QuatFromTo(V3(0, -1, 0), D2);
  ShoulderRel := Gu;
  ElbowRel := QuatNormalize(QuatMul(QuatConj(Gu), Gf));
  JU := nil;
end;

{ Поведения: вычисляют цели приводов и эффекторов для текущего состояния. }
procedure RagdollControl(var W: TPhysWorld; var R: TRagdoll; Dt: Double);
var
  K, J, Bi, S: Integer;
  Pelvis: PRigidBody;
  ReachShoulder, ReachElbow: array[0..1] of TQuat;
  Up: TVec3;
  Com, Sup, E: TVec3;
  Mass: Double;
  Fwd, Right: TVec3;
  ErrF, El, Phi, Rho, Kap, WBrace: Double;
  Tgt, Off: TQuat;
  FootL, FootR, Ca, Cb: Boolean;
  Strength, Legs: Double;
  PosBase, Target: TVec3;
  Ef2: ^TPhysEffector;
begin
  Pelvis := @W.Bodies[R.Bodies[HB_PELVIS]];

  { 1. наклон таза от вертикали }
  Up := QuatRotate(Pelvis^.Rot, V3(0, 1, 0));
  R.Tilt := ArcCos(ClampD(V3Dot(Up, V3(0, 1, 0)), -1, 1));

  { 2. защитная реакция: включается при сильном наклоне }
  if R.BraceAuto and (R.Tilt > 0.9) then WBrace := 1.0 else WBrace := 0.0;
  R.Brace := R.Brace + (WBrace - R.Brace) * MinD(1.0, Dt * 4.0);

  { 3. центр опоры по стопам, касающимся пола }
  FootL := W.Bodies[R.Bodies[HB_FOOT_L]].OnGround;
  FootR := W.Bodies[R.Bodies[HB_FOOT_R]].OnGround;
  Ca := FootL;
  Cb := FootR;
  if Ca and Cb then
    Sup := V3Mul(V3Add(W.Bodies[R.Bodies[HB_FOOT_L]].Pos, W.Bodies[R.Bodies[HB_FOOT_R]].Pos), 0.5)
  else if Ca then
    Sup := W.Bodies[R.Bodies[HB_FOOT_L]].Pos
  else if Cb then
    Sup := W.Bodies[R.Bodies[HB_FOOT_R]].Pos
  else
    Sup := R.Support;
  Sup.Y := 0;
  R.Support := Sup;

  { 4. ошибка баланса: проекция центра масс относительно опоры на направления тела }
  Com := PhysWorldCenterOfMass(W, R.Group, Mass);
  E := V3Sub(Com, Sup);
  E.Y := 0;
  Fwd := QuatRotate(R.HeadingQ, V3(0, 0, 1));
  Right := QuatRotate(R.HeadingQ, V3(1, 0, 0));
  ErrF := V3Dot(E, Fwd);
  El := V3Dot(E, Right);

  { 5. цели шарниров: поза анимации + поправки баланса }
  { при падении ноги расслабляются (как при реакции catch-fall), иначе приводы тянут тело в позу стойки по полу }
  Legs := 1.0 - R.Brace;
  for S := 0 to 1 do
    if R.ReachWeight[S] > 0 then
      ReachRel(W, R, S, ReachShoulder[S], ReachElbow[S]);
  for K := 0 to JOINT_COUNT - 1 do
  begin
    Bi := RD_JOINT_SPECS[K].Bone;
    J := R.JointOf[Bi];
    Tgt := AnimRel(R, Bi);
    { дотягивание: плечо и локоть смешиваются с позой IK, кисть выравнивается по предплечью }
    if (Bi = HB_UARM_L) and (R.ReachWeight[0] > 0) then
      Tgt := QuatSlerp(Tgt, ReachShoulder[0], R.ReachWeight[0])
    else if (Bi = HB_LARM_L) and (R.ReachWeight[0] > 0) then
      Tgt := QuatSlerp(Tgt, ReachElbow[0], R.ReachWeight[0])
    else if (Bi = HB_UARM_R) and (R.ReachWeight[1] > 0) then
      Tgt := QuatSlerp(Tgt, ReachShoulder[1], R.ReachWeight[1])
    else if (Bi = HB_LARM_R) and (R.ReachWeight[1] > 0) then
      Tgt := QuatSlerp(Tgt, ReachElbow[1], R.ReachWeight[1]);
    if R.BalanceOn then
    begin
      if Bi = HB_TORSO then
      begin
        { стратегия бедра: наклон туловища против смещения центра масс }
        Phi := ClampD(R.BalanceSign * R.BalanceKHip * ErrF * (-1.0), -0.6, 0.6);
        Rho := ClampD(R.BalanceSign * R.BalanceKHip * El * (-1.0), -0.4, 0.4);
        Off := QuatMul(QuatFromAxisAngle(V3(0, 0, 1), Rho), QuatFromAxisAngle(V3(1, 0, 0), Phi));
        Tgt := QuatMul(Off, Tgt);
      end
      else if (Bi = HB_SHIN_L) or (Bi = HB_SHIN_R) then
      begin
        { стратегия голеностопа: поворот стопы по ошибке }
        Kap := ClampD(R.BalanceSign * R.BalanceKAnkle * ErrF, -0.5, 0.5);
        Tgt := QuatMul(QuatFromAxisAngle(V3(1, 0, 0), Kap), Tgt);
      end;
    end;
    if (Bi = HB_UARM_L) or (Bi = HB_UARM_R) then
      { защитная реакция: плечи уходят вперёд (приводами, внутренний момент) }
      Tgt := QuatMul(QuatFromAxisAngle(V3(1, 0, 0), -1.2 * R.Brace), Tgt);
    Tgt := QuatNormalize(Tgt);
    W.Joints[J].TargetRel := Tgt;
    if (Bi = HB_THIGH_L) or (Bi = HB_THIGH_R) or (Bi = HB_SHIN_L) or (Bi = HB_SHIN_R) or
       (Bi = HB_FOOT_L) or (Bi = HB_FOOT_R) then
      Strength := R.Muscle * Legs
    else if (Bi = HB_UARM_L) or (Bi = HB_LARM_L) or (Bi = HB_HAND_L) or
            (Bi = HB_UARM_R) or (Bi = HB_LARM_R) or (Bi = HB_HAND_R) then
      { руки при защите остаются частично активными, но не тянут назад к позе стойки }
      Strength := R.Muscle * (1.0 - 0.7 * R.Brace)
    else
      Strength := R.Muscle * (1.0 - R.Brace);
    W.Joints[J].Strength := Strength;
  end;

  { 6. эффекторы: ориентация таза и кисти }
  Ef2 := @W.Effectors[R.Effector[0]];
  Ef2^.TargetRot := QuatMul(R.HeadingQ, R.Global[HB_PELVIS].Rot);
  Ef2^.OriStiffness := 40 * R.Muscle * (1.0 - R.Brace);

  { дотягивание: кисть ведётся к мировой цели слабой силой (внешняя сила ограничена) }
  for S := 0 to 1 do
  begin
    Ef2 := @W.Effectors[R.Effector[S + 1]];
    if R.ReachWeight[S] <= 0 then
    begin
      Ef2^.PosStiffness := 0;
      Continue;
    end;
    Ef2^.Target := R.ReachTarget[S];
    Ef2^.PosStiffness := 150 * R.ReachWeight[S];
    Ef2^.PosDamping := 15;
    Ef2^.PosMaxForce := 60 * R.ReachWeight[S];
    Ef2^.Local := V3Zero;
    Ef2^.Enabled := True;
  end;
end;

procedure RagdollAdvance(var W: TPhysWorld; var R: TRagdoll; FrameDt: Double; Substeps: Integer);
var
  I: Integer;
  H: Double;
begin
  PlayerUpdate(R.Player, R.Clips, FrameDt);
  PlayerEvaluate(R.Player, R.Skel, R.Clips, R.Pose);
  PoseGlobal(R.Skel, R.Pose, R.Global);
  if Substeps < 1 then Substeps := 1;
  H := FrameDt / Substeps;
  for I := 1 to Substeps do
  begin
    RagdollControl(W, R, H);
    PhysStep(W, H);
  end;
  R.Time := R.Time + FrameDt;
end;

end.
