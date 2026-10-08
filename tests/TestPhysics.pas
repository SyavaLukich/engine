{ TestPhysics - проверки динамики твёрдых тел (EngPhysics). }
unit TestPhysics;

{$mode objfpc}{$H+}

interface

procedure RunPhysicsTests;

implementation

uses
  SysUtils, Math, EngMath, EngConvex, EngPhysics, TestKit;

const
  STEP = 1.0 / 240.0;

procedure Simulate(var W: TPhysWorld; Seconds: Double);
var
  I, N: Integer;
begin
  N := Round(Seconds / STEP);
  for I := 1 to N do
    PhysStep(W, STEP);
end;

function NewWorld(Gravity: Boolean): TPhysWorld;
var
  G: TVec3;
begin
  if Gravity then G := V3(0, -9.81, 0) else G := V3Zero;
  PhysWorldInit(Result, G, 12);
end;

{ Угол между ориентацией относительного поворота и целевым (кратчайший путь). }
function RelAngle(const QA, QB: TQuat; const TargetRel: TQuat): Double;
var
  Qrel, Dq: TQuat;
  V: TVec3;
begin
  Qrel := QuatNormalize(QuatMul(QuatConj(QA), QB));
  Dq := QuatNormalize(QuatMul(TargetRel, QuatConj(Qrel)));
  V := V3(Dq.X, Dq.Y, Dq.Z);
  Result := 2.0 * ArcTan2(V3Length(V), Abs(Dq.W));
end;

procedure TestRestAndBounce;
var
  W: TPhysWorld;
  I: Integer;
  S: TConvexShape;
  Peak, PrevVy: Double;
  Bounced: Boolean;
  B: TRigidBody;
begin
  Section('физика: покой на полу');
  W := NewWorld(True);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.8, 0);
  S := MakeBoxShape(V3(0.5, 0.5, 0.5));
  I := PhysAddBody(W, PhysMakeBody(S, V3(0, 2, 0), QuatIdentity, 10));
  Simulate(W, 3.0);
  B := W.Bodies[I];
  CheckNear(B.Pos.Y, 0.5, 0.01, 'коробка лежит на полу: высота центра');
  Check(V3Length(B.Vel) < 0.05, 'коробка на полу без скорости');
  Check(B.OnGround, 'флаг OnGround выставлен на полу');

  Section('физика: отскок сферы');
  W := NewWorld(True);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.5, 0.5);
  S := MakeSphereShape(0.25);
  PhysAddBody(W, PhysMakeBody(S, V3(0, 2, 0), QuatIdentity, 1));
  Peak := 0;
  Bounced := False;
  PrevVy := 0;
  for I := 1 to 480 do
  begin
    PhysStep(W, STEP);
    B := W.Bodies[0];
    if (not Bounced) and (PrevVy < 0) and (B.Vel.Y > 0) then
      Bounced := True;
    if Bounced then
      Peak := Max(Peak, B.Pos.Y - 0.25);
    PrevVy := B.Vel.Y;
  end;
  Check(Bounced, 'сфера отскочила от пола');
  { падение с 1.75 м, e = 0.5: ожидаемая высота отскока e^2 * 1.75 = 0.44 м }
  Check((Peak > 0.2) and (Peak < 0.7), Format('высота отскока разумна (%.3f м)', [Peak]));
end;

procedure TestBoxStack;
var
  W: TPhysWorld;
  I, K: Integer;
  S: TConvexShape;
  Maxdx, Maxdz: Double;
begin
  Section('физика: стопка коробок');
  W := NewWorld(True);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.8, 0);
  S := MakeBoxShape(V3(0.5, 0.5, 0.5));
  for I := 0 to 2 do
    PhysAddBody(W, PhysMakeBody(S, V3(0.0, 0.5 + I * 1.0, 0.0), QuatIdentity, 5));
  Simulate(W, 4.0);
  Maxdx := 0;
  Maxdz := 0;
  for I := 0 to 2 do
  begin
    Maxdx := Max(Maxdx, Abs(W.Bodies[I].Pos.X));
    Maxdz := Max(Maxdz, Abs(W.Bodies[I].Pos.Z));
  end;
  Check(Maxdx < 0.02, Format('стопка не сползает по X (%.4f)', [Maxdx]));
  Check(Maxdz < 0.02, Format('стопка не сползает по Z (%.4f)', [Maxdz]));
  for I := 0 to 2 do
    CheckNear(W.Bodies[I].Pos.Y, 0.5 + I * 1.0, 0.03, Format('высота коробки %d в стопке', [I]));
  K := 0;
  for I := 0 to 2 do
    if Abs(W.Bodies[I].Vel.Y) > 0.1 then
      Inc(K);
  Check(K = 0, 'стопка в покое');
end;

procedure TestCapsuleLying;
var
  W: TPhysWorld;
  I: Integer;
  Cap: TConvexShape;
  Q: TQuat;
begin
  Section('физика: капсула на полу');
  W := NewWorld(True);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.8, 0);
  Cap := MakeCapsuleShape(0.3, 0.5);
  { капсула лежит на боку: ось Y повёрнута в ось X }
  Q := QuatFromAxisAngle(V3(0, 0, 1), ENG_PI / 2);
  I := PhysAddBody(W, PhysMakeBody(Cap, V3(0, 2, 0), Q, 4));
  Simulate(W, 3.0);
  CheckNear(W.Bodies[I].Pos.Y, 0.3, 0.02, 'капсула на боку лежит на радиусе');
  Check(V3Length(W.Bodies[I].Vel) < 0.05, 'капсула в покое');
end;

procedure TestPendulum;
var
  W: TPhysWorld;
  Anc, Bob: Integer;
  J: TPhysJoint;
  Sa, Sb: TConvexShape;
  I: Integer;
  MaxErr, MaxSpeed, MaxH: Double;
  Pa, Pb: TVec3;
begin
  Section('физика: маятник на шарнире ball');
  W := NewWorld(True);
  Sa := MakeBoxShape(V3(0.05, 0.05, 0.05));
  Sb := MakeSphereShape(0.1);
  Anc := PhysAddBody(W, PhysMakeBody(Sa, V3(0, 5, 0), QuatIdentity, 0));
  { боб в точке (1,5,0); точка крепления на бобе - (-1,0,0) локально, то есть (0,5,0) в мире }
  Bob := PhysAddBody(W, PhysMakeBody(Sb, V3(1, 5, 0), QuatIdentity, 1));
  J := PhysDefaultJoint(jkBall, Anc, Bob);
  J.AnchorA := V3Zero;
  J.AnchorB := V3(-1, 0, 0);
  PhysAddJoint(W, J);
  MaxErr := 0;
  MaxSpeed := 0;
  MaxH := 0;
  for I := 1 to 5 * 240 do
  begin
    PhysStep(W, STEP);
    Pa := W.Bodies[Anc].Pos;
    Pb := V3Add(W.Bodies[Bob].Pos, QuatRotate(W.Bodies[Bob].Rot, V3(-1, 0, 0)));
    MaxErr := Max(MaxErr, V3Distance(Pa, Pb));
    MaxSpeed := Max(MaxSpeed, V3Length(W.Bodies[Bob].Vel));
    if I > 2 * 240 then
      MaxH := Max(MaxH, W.Bodies[Bob].Pos.Y);
  end;
  Check(MaxErr < 0.002, Format('точка крепления не расходится (макс. %.6f м)', [MaxErr]));
  Check(MaxSpeed < 12, Format('скорость маятника физична (макс. %.3f м/с)', [MaxSpeed]));
  { энергия: без трения после двух секунд максимум высоты близок к стартовой (5.0) }
  Check(MaxH > 4.85, Format('энергия маятника сохраняется (максимум высоты %.4f)', [MaxH]));
end;

procedure TestHingeLimit;
var
  W: TPhysWorld;
  A, B: Integer;
  J: TPhysJoint;
  Sa, Sb: TConvexShape;
  I: Integer;
  MinAng: Double;
begin
  Section('физика: шарнир hinge с пределами');
  W := NewWorld(True);
  Sa := MakeBoxShape(V3(0.05, 0.05, 0.05));
  { стержень длиной 1 м, левый конец в точке шарнира (0,0,0) }
  Sb := MakeBoxShape(V3(0.5, 0.05, 0.05));
  A := PhysAddBody(W, PhysMakeBody(Sa, V3Zero, QuatIdentity, 0));
  B := PhysAddBody(W, PhysMakeBody(Sb, V3(0.5, 0, 0), QuatIdentity, 1));
  J := PhysDefaultJoint(jkHinge, A, B);
  J.AnchorA := V3Zero;
  J.AnchorB := V3(-0.5, 0, 0);
  J.Axis := V3(0, 0, 1);
  J.LimitEnabled := True;
  J.LimitLo := -0.5;
  J.LimitHi := 0.5;
  PhysAddJoint(W, J);
  MinAng := 0;
  for I := 1 to 3 * 240 do
  begin
    PhysStep(W, STEP);
    MinAng := Min(MinAng, W.JointState[0].Angle);
  end;
  { стержень падает и упирается в нижний предел -0.5 рад }
  CheckNear(W.JointState[0].Angle, -0.5, 0.05, 'угол шарнира остановлен нижним пределом');
  Check(MinAng > -0.6, Format('угол не уходит далеко за предел (мин. %.3f)', [MinAng]));
  Check((Abs(W.Bodies[B].AngVel.X) < 0.5) and (Abs(W.Bodies[B].AngVel.Y) < 0.5),
        'перпендикулярные оси шарнира заблокированы');
end;

procedure TestDrives;
var
  W: TPhysWorld;
  A, B: Integer;
  J: TPhysJoint;
  Sa, Sb: TConvexShape;
  Q: TQuat;
  Err: Double;
begin
  Section('физика: привод ball доводит ориентацию до цели');
  W := NewWorld(False);
  Sa := MakeBoxShape(V3(0.05, 0.05, 0.05));
  Sb := MakeBoxShape(V3(0.2, 0.2, 0.2));
  A := PhysAddBody(W, PhysMakeBody(Sa, V3Zero, QuatIdentity, 0));
  B := PhysAddBody(W, PhysMakeBody(Sb, V3Zero, QuatIdentity, 2));
  J := PhysDefaultJoint(jkBall, A, B);
  J.DriveEnabled := True;
  Q := QuatFromAxisAngle(V3(0, 1, 0), 0.8);
  J.TargetRel := Q;
  J.Stiffness := 100;
  J.Damping := 20;
  J.MaxTorque := 50;
  PhysAddJoint(W, J);
  Simulate(W, 2.0);
  Err := RelAngle(W.Bodies[A].Rot, W.Bodies[B].Rot, Q);
  Check(Err < 0.02, Format('ball-привод сходится к 0.8 рад (ошибка %.5f рад)', [Err]));

  Section('физика: привод hinge доводит угол до цели');
  W := NewWorld(False);
  A := PhysAddBody(W, PhysMakeBody(Sa, V3Zero, QuatIdentity, 0));
  B := PhysAddBody(W, PhysMakeBody(Sb, V3Zero, QuatIdentity, 2));
  J := PhysDefaultJoint(jkHinge, A, B);
  J.DriveEnabled := True;
  J.Axis := V3(0, 0, 1);
  Q := QuatFromAxisAngle(V3(0, 0, 1), 0.6);
  J.TargetRel := Q;
  J.Stiffness := 100;
  J.Damping := 20;
  J.MaxTorque := 50;
  PhysAddJoint(W, J);
  Simulate(W, 2.0);
  Err := RelAngle(W.Bodies[A].Rot, W.Bodies[B].Rot, Q);
  Check(Err < 0.02, Format('hinge-привод сходится к 0.6 рад (ошибка %.5f рад)', [Err]));
end;

procedure TestEffectors;
var
  W: TPhysWorld;
  I: Integer;
  E: TPhysEffector;
  Sb: TConvexShape;
  Q: TQuat;
  Err: Double;
begin
  Section('физика: эффектор точки и ориентации');
  W := NewWorld(False);
  Sb := MakeBoxShape(V3(0.2, 0.3, 0.1));
  I := PhysAddBody(W, PhysMakeBody(Sb, V3Zero, QuatIdentity, 3));
  E := PhysDefaultEffector(I);
  E.Local := V3(0.2, 0.3, 0);
  E.Target := V3(1, 2, 0);
  E.PosStiffness := 100;
  E.PosDamping := 20;
  E.PosMaxForce := 1000;
  PhysAddEffector(W, E);
  Simulate(W, 3.0);
  Err := V3Distance(V3Add(W.Bodies[I].Pos, QuatRotate(W.Bodies[I].Rot, V3(0.2, 0.3, 0))), V3(1, 2, 0));
  Check(Err < 0.02, Format('точка эффектора приходит к цели (ошибка %.5f м)', [Err]));

  W := NewWorld(False);
  I := PhysAddBody(W, PhysMakeBody(Sb, V3Zero, QuatIdentity, 3));
  E := PhysDefaultEffector(I);
  Q := QuatFromAxisAngle(V3(1, 0, 0), 1.0);
  E.UseOrient := True;
  E.TargetRot := Q;
  E.OriStiffness := 100;
  E.OriDamping := 20;
  E.OriMaxTorque := 200;
  PhysAddEffector(W, E);
  Simulate(W, 3.0);
  Err := RelAngle(QuatIdentity, W.Bodies[I].Rot, Q);
  Check(Err < 0.02, Format('ориентация эффектора приходит к цели (ошибка %.5f рад)', [Err]));
end;

{ Наклонная плита: верхняя грань проходит через начало координат, нормаль (sin20, cos20, 0). }
procedure BuildRamp(var W: TPhysWorld; Mu: Double; out Box: Integer; out Start: TVec3);
var
  Ang: Double;
  Qr: TQuat;
  Nrm: TVec3;
  Ramp: Integer;
  Sr, Sb: TConvexShape;
begin
  Ang := 20.0 * ENG_PI / 180.0;
  Qr := QuatFromAxisAngle(V3(0, 0, 1), -Ang);
  Nrm := QuatRotate(Qr, V3(0, 1, 0));
  Sr := MakeBoxShape(V3(10, 0.5, 10));
  Ramp := PhysAddBody(W, PhysMakeBody(Sr, V3Mul(Nrm, -0.5), Qr, 0));
  W.Bodies[Ramp].Friction := Mu;
  Sb := MakeBoxShape(V3(0.25, 0.25, 0.25));
  Start := V3Mul(Nrm, 0.26);
  Box := PhysAddBody(W, PhysMakeBody(Sb, Start, Qr, 1));
  W.Bodies[Box].Friction := Mu;
end;

procedure TestFriction;
var
  W: TPhysWorld;
  Box: Integer;
  Start: TVec3;
  Slide: Double;
begin
  Section('физика: трение на наклонной плоскости (контакт тело-тело, EPA)');
  { сцепление: mu = 0.8 > tg 20 = 0.36 - коробка стоит }
  W := NewWorld(True);
  BuildRamp(W, 0.8, Box, Start);
  Simulate(W, 2.0);
  Slide := V3Distance(W.Bodies[Box].Pos, Start);
  Check(Slide < 0.1, Format('коробка на наклоне с трением 0.8 не скользит (%.3f м)', [Slide]));

  { скольжение: mu = 0.05 < tg 20 - коробка едет вниз по склону }
  W := NewWorld(True);
  BuildRamp(W, 0.05, Box, Start);
  Simulate(W, 2.0);
  Slide := V3Distance(W.Bodies[Box].Pos, Start);
  Check(Slide > 0.5, Format('коробка на скользком наклоне едет (%.3f м)', [Slide]));
end;

procedure BuildPile(var W: TPhysWorld);
var
  I: Integer;
  Seed: LongWord;
  P: TVec3;
  S: TConvexShape;
begin
  W := NewWorld(True);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.6, 0.1);
  S := MakeBoxShape(V3(0.25, 0.25, 0.25));
  Seed := 12345;
  for I := 0 to 39 do
  begin
    Seed := Seed * 1664525 + 1013904223;
    P.X := ((Seed shr 8) and $FFFF) / 65536.0 * 2.0 - 1.0;
    Seed := Seed * 1664525 + 1013904223;
    P.Z := ((Seed shr 8) and $FFFF) / 65536.0 * 2.0 - 1.0;
    P.Y := 1.0 + I * 0.6;
    PhysAddBody(W, PhysMakeBody(S, P, QuatIdentity, 1));
  end;
end;

procedure TestDeterminism;
var
  WA, WB: TPhysWorld;
  I, Bad: Integer;
  Same: Boolean;
begin
  Section('физика: детерминизм и устойчивость кучи');
  BuildPile(WA);
  BuildPile(WB);
  Simulate(WA, 6.0);
  Simulate(WB, 6.0);
  Same := WA.BodyCount = WB.BodyCount;
  for I := 0 to WA.BodyCount - 1 do
    if (WA.Bodies[I].Pos.X <> WB.Bodies[I].Pos.X) or (WA.Bodies[I].Pos.Y <> WB.Bodies[I].Pos.Y) or
       (WA.Bodies[I].Pos.Z <> WB.Bodies[I].Pos.Z) then
      Same := False;
  Check(Same, 'два одинаковых запуска дают побитово одинаковые позиции');
  Bad := 0;
  for I := 0 to WA.BodyCount - 1 do
    if (not FiniteD(WA.Bodies[I].Pos.Y)) or (WA.Bodies[I].Pos.Y < -0.01) or (WA.Bodies[I].Pos.Y > 30) then
      Inc(Bad);
  Check(Bad = 0, 'куча из 40 коробок: все тела конечны и над полом');
end;

procedure RunPhysicsTests;
begin
  TestRestAndBounce;
  TestBoxStack;
  TestCapsuleLying;
  TestPendulum;
  TestHingeLimit;
  TestDrives;
  TestEffectors;
  TestFriction;
  TestDeterminism;
end;

end.
