{ TestMain - набор проверок движка. Запуск: ./build.sh (код возврата 0 = все проверки пройдены).

  Проверки столкновений сверяются с независимым эталоном - теорема разделяющих осей (SAT)
  для боксов, который даёт точную глубину проникновения. }
program TestMain;

{$mode objfpc}{$H+}

uses
  SysUtils, Math, EngMath, EngConvex, TestKit, TestPhysics, TestRagdoll, TestPNG, TestRender;

function NearD(const A, B, Eps: Double): Boolean;
begin
  Result := Abs(A - B) <= Eps;
end;

function NearV(const A, B: TVec3; const Eps: Double): Boolean;
begin
  Result := V3Length(V3Sub(A, B)) <= Eps;
end;

function Pose(const X, Y, Z: Double): TPose;
begin
  Result.Pos := V3(X, Y, Z);
  Result.Rot := QuatIdentity;
end;

function PoseRot(const X, Y, Z: Double; const Rot: TQuat): TPose;
begin
  Result.Pos := V3(X, Y, Z);
  Result.Rot := Rot;
end;

{ Эталон SAT для двух OBB. Normal - от B к A, Depth - минимальное перекрытие по осям. }
function SATBoxes(const HA: TVec3; const PA: TPose; const HB: TVec3; const PB: TPose;
                  out Normal: TVec3; out Depth: Double): Boolean;
var
  AxA, AxB: array[0..2] of TVec3;
  Axes: array[0..14] of TVec3;
  HAa, HBa: array[0..2] of Double;
  I, J, K, NAx: Integer;
  L, Rad, RA, RB, Dist, Overlap, Sgn: Double;
  T: TVec3;
  Best: Double;
begin
  AxA[0] := QuatRotate(PA.Rot, V3(1, 0, 0));
  AxA[1] := QuatRotate(PA.Rot, V3(0, 1, 0));
  AxA[2] := QuatRotate(PA.Rot, V3(0, 0, 1));
  AxB[0] := QuatRotate(PB.Rot, V3(1, 0, 0));
  AxB[1] := QuatRotate(PB.Rot, V3(0, 1, 0));
  AxB[2] := QuatRotate(PB.Rot, V3(0, 0, 1));
  HAa[0] := HA.X; HAa[1] := HA.Y; HAa[2] := HA.Z;
  HBa[0] := HB.X; HBa[1] := HB.Y; HBa[2] := HB.Z;
  NAx := 0;
  for I := 0 to 2 do
  begin
    Axes[NAx] := AxA[I];
    Inc(NAx);
  end;
  for I := 0 to 2 do
  begin
    Axes[NAx] := AxB[I];
    Inc(NAx);
  end;
  for I := 0 to 2 do
    for J := 0 to 2 do
    begin
      Axes[NAx] := V3Cross(AxA[I], AxB[J]);
      Inc(NAx);
    end;
  Best := 1e300;
  Result := True;
  Normal := V3Zero;
  Depth := 0;
  T := V3Sub(PA.Pos, PB.Pos);
  for K := 0 to NAx - 1 do
  begin
    L := V3Length(Axes[K]);
    if L < 1e-9 then
      Continue;
    Axes[K] := V3Mul(Axes[K], 1.0 / L);
    RA := 0;
    RB := 0;
    for I := 0 to 2 do
    begin
      RA := RA + HAa[I] * Abs(V3Dot(AxA[I], Axes[K]));
      RB := RB + HBa[I] * Abs(V3Dot(AxB[I], Axes[K]));
    end;
    Rad := RA + RB;
    Dist := V3Dot(T, Axes[K]);
    Overlap := Rad - Abs(Dist);
    if Overlap < 0 then
    begin
      Result := False;
      Exit;
    end;
    if Overlap < Best then
    begin
      Best := Overlap;
      if Dist >= 0 then Sgn := 1 else Sgn := -1;
      Normal := V3Mul(Axes[K], Sgn);
      Depth := Overlap;
    end;
  end;
end;

{ Случайный единичный кватернион. }
function RandomQuat: TQuat;
var
  U1, U2, U3: Double;
  S1, S2: Double;
begin
  U1 := Random;
  U2 := Random;
  U3 := Random;
  S1 := Sqrt(1 - U1);
  S2 := Sqrt(U1);
  Result.X := S1 * Sin(2 * ENG_PI * U2);
  Result.Y := S1 * Cos(2 * ENG_PI * U2);
  Result.Z := S2 * Sin(2 * ENG_PI * U3);
  Result.W := S2 * Cos(2 * ENG_PI * U3);
end;

procedure TestMath;
var
  R: TVec3;
  Q: TQuat;
  M, Inv, I3: TMat3;
  K: Integer;
  Ok: Boolean;
begin
  WriteLn('[math]');
  Q := QuatFromAxisAngle(V3(0, 0, 1), ENG_PI / 2);
  R := QuatRotate(Q, V3(1, 0, 0));
  Check(NearV(R, V3(0, 1, 0), 1e-12), 'quat rotate 90 deg around Z');
  R := QuatInvRotate(Q, V3(0, 1, 0));
  Check(NearV(R, V3(1, 0, 0), 1e-12), 'quat inverse rotate');
  M := QuatToMat3(Q);
  R := Mat3MulV(M, V3(1, 0, 0));
  Check(NearV(R, V3(0, 1, 0), 1e-12), 'quat to matrix consistency');
  M.M[0] := 2; M.M[1] := 1; M.M[2] := 0;
  M.M[3] := 0; M.M[4] := 3; M.M[5] := 1;
  M.M[6] := 1; M.M[7] := 0; M.M[8] := 4;
  Inv := Mat3Inverse(M);
  I3 := Mat3Mul(M, Inv);
  Ok := True;
  for K := 0 to 8 do
    if not NearD(I3.M[K], Mat3Identity.M[K], 1e-12) then
      Ok := False;
  Check(Ok, 'mat3 inverse times matrix is identity');
  Q := QuatSlerp(QuatIdentity, QuatFromAxisAngle(V3(0, 1, 0), ENG_PI), 0.5);
  R := QuatRotate(Q, V3(1, 0, 0));
  { 180 градусов вокруг Y переводят X в -Z, половина пути - поворот на 90 градусов }
  Check(NearV(R, V3(0, 0, -1), 1e-9), 'slerp halfway');
  Q := QuatIdentity;
  for K := 0 to 999 do
    Q := QuatIntegrate(Q, V3(0.3, 0.2, 0.1), 0.01);
  Check(NearD(QuatDot(Q, Q), 1, 1e-12), 'integration keeps quaternion unit length');
end;

procedure TestSpheres;
var
  C: TContact;
  Hit: Boolean;
  S: TConvexShape;
begin
  WriteLn('[spheres]');
  S := MakeSphereShape(1.0);
  Hit := CollideConvex(S, Pose(1.5, 0, 0), S, Pose(0, 0, 0), C);
  Check(Hit, 'spheres overlap');
  Check(NearD(C.Depth, 0.5, 1e-12), 'sphere depth 0.5');
  Check(NearV(C.Normal, V3(1, 0, 0), 1e-12), 'sphere normal from B to A');
  Hit := CollideConvex(S, Pose(2.5, 0, 0), S, Pose(0, 0, 0), C);
  Check(not Hit, 'spheres separated');
end;

procedure TestBoxBox;
var
  C: TContact;
  Hit: Boolean;
  BA, BB: TConvexShape;
  Nrm: TVec3;
  Dep: Double;
begin
  WriteLn('[box-box]');
  BA := MakeBoxShape(V3(1, 1, 1));
  BB := MakeBoxShape(V3(1, 1, 1));
  Hit := CollideConvex(BA, Pose(0, 0, 0), BB, Pose(1.5, 0, 0), C);
  Check(Hit, 'aligned boxes overlap');
  Check(NearD(C.Depth, 0.5, 1e-9), 'aligned box depth 0.5');
  Check(NearV(C.Normal, V3(-1, 0, 0), 1e-9), 'aligned box normal from B to A');
  Hit := CollideConvex(BA, Pose(0, 0, 0), BB, Pose(2.5, 0, 0), C);
  Check(not Hit, 'aligned boxes separated');
  Hit := CollideConvex(BA, Pose(0, 0, 0), BB, Pose(0, 1.9, 1.9), C);
  Check(Hit, 'boxes overlap diagonally (1.9 < 2)');
  Hit := CollideConvex(BA, Pose(0, 0, 0), BB, Pose(0, 2.1, 2.1), C);
  Check(not Hit, 'boxes separated diagonally (2.1 > 2)');
  { поворот на 45 градусов вокруг Z: эталон SAT }
  Hit := CollideConvex(BA, PoseRot(0, 0, 0, QuatFromAxisAngle(V3(0, 0, 1), ENG_PI / 4)),
                       BB, Pose(2.0, 0, 0), C);
  Check(Hit, 'rotated box overlap');
  Check(SATBoxes(V3(1, 1, 1), PoseRot(0, 0, 0, QuatFromAxisAngle(V3(0, 0, 1), ENG_PI / 4)),
                 V3(1, 1, 1), Pose(2.0, 0, 0), Nrm, Dep), 'rotated box SAT agrees');
  Check(NearD(C.Depth, Dep, 1e-6), 'rotated box depth equals SAT');
end;

{ Сравнение с SAT на случайных парах боксов. }
procedure TestRandomBoxes(const Count: Integer);
var
  I, Agree, Hits, Mismatch: Integer;
  HA, HB: TVec3;
  PA, PB: TPose;
  C: TContact;
  Hit, SatHit: Boolean;
  SatN: TVec3;
  SatD, MaxDepthErr, MinDot: Double;
  BA, BB: TConvexShape;
begin
  WriteLn('[random box pairs vs SAT, n=', Count, ']');
  Agree := 0;
  Hits := 0;
  Mismatch := 0;
  MaxDepthErr := 0;
  MinDot := 1;
  for I := 1 to Count do
  begin
    HA := V3(0.2 + Random, 0.2 + Random, 0.2 + Random);
    HB := V3(0.2 + Random, 0.2 + Random, 0.2 + Random);
    PA.Pos := V3(Random * 3 - 1.5, Random * 3 - 1.5, Random * 3 - 1.5);
    PA.Rot := RandomQuat;
    PB.Pos := V3(Random * 3 - 1.5, Random * 3 - 1.5, Random * 3 - 1.5);
    PB.Rot := RandomQuat;
    BA := MakeBoxShape(HA);
    BB := MakeBoxShape(HB);
    Hit := CollideConvex(BA, PA, BB, PB, C);
    SatHit := SATBoxes(HA, PA, HB, PB, SatN, SatD);
    if Hit = SatHit then
    begin
      Inc(Agree);
      if Hit then
      begin
        Inc(Hits);
        MaxDepthErr := MaxD(MaxDepthErr, Abs(C.Depth - SatD));
        MinDot := MinD(MinDot, V3Dot(C.Normal, SatN));
      end;
    end
    else
      Inc(Mismatch);
  end;
  WriteLn('  agree: ', Agree, ' of ', Count, ', overlapping: ', Hits,
          ', max depth error: ', MaxDepthErr:0:9, ', min normal dot: ', MinDot:0:6);
  Check(Mismatch = 0, 'GJK/EPA overlap decision matches SAT');
  Check(MaxDepthErr < 1e-5, 'EPA depth matches SAT (< 1e-5)');
  Check(MinDot > 0.9999, 'EPA normal matches SAT (dot > 0.9999)');
end;

{ Свойство: после сдвига A на глубину вдоль нормали тела касаются, а на 2% больше - разделены. }
procedure TestSeparationProperty(const Count: Integer);
var
  I, Bad: Integer;
  HA, HB: TVec3;
  PA, PB: TPose;
  C: TContact;
  BA, BB: TConvexShape;
begin
  WriteLn('[separation property, n=', Count, ']');
  Bad := 0;
  for I := 1 to Count do
  begin
    HA := V3(0.3 + Random, 0.3 + Random, 0.3 + Random);
    HB := V3(0.3 + Random, 0.3 + Random, 0.3 + Random);
    PA.Pos := V3(Random * 2 - 1, Random * 2 - 1, Random * 2 - 1);
    PA.Rot := RandomQuat;
    PB.Pos := V3(Random * 2 - 1, Random * 2 - 1, Random * 2 - 1);
    PB.Rot := RandomQuat;
    BA := MakeBoxShape(HA);
    BB := MakeBoxShape(HB);
    if CollideConvex(BA, PA, BB, PB, C) then
    begin
      PA.Pos := V3Add(PA.Pos, V3Mul(C.Normal, C.Depth * 1.02 + 1e-7));
      if GJKOverlap(BA, PA, BB, PB) then
        Inc(Bad);
    end;
  end;
  Check(Bad = 0, 'moving A out by 1.02 * depth separates all pairs');
end;

{ Вырожденные конфигурации: повороты кратные 45 градусам, целые позиции. Здесь GJK-симплекс
  часто оказывается на грани, и именно тут проверяется корректность EPA. }
procedure TestDegenerateGrid;
var
  Ix, Iy, Iz, Rk, Bad, Total: Integer;
  HA, HB: TVec3;
  PA, PB: TPose;
  C: TContact;
  Hit, SatHit: Boolean;
  SatN: TVec3;
  SatD: Double;
  BA, BB: TConvexShape;
begin
  WriteLn('[degenerate grid vs SAT]');
  Bad := 0;
  Total := 0;
  HA := V3(1, 1, 1);
  HB := V3(1, 1, 1);
  BA := MakeBoxShape(HA);
  BB := MakeBoxShape(HB);
  for Ix := -2 to 2 do
    for Iy := -2 to 2 do
      for Iz := -1 to 1 do
        for Rk := 0 to 3 do
        begin
          PA.Pos := V3(0, 0, 0);
          PA.Rot := QuatFromAxisAngle(V3(0, 0, 1), Rk * ENG_PI / 4);
          PB.Pos := V3(Ix * 0.5, Iy * 0.5, Iz * 0.5);
          PB.Rot := QuatIdentity;
          Hit := CollideConvex(BA, PA, BB, PB, C);
          SatHit := SATBoxes(HA, PA, HB, PB, SatN, SatD);
          Inc(Total);
          if Hit <> SatHit then
            Inc(Bad)
          else if Hit and not NearD(C.Depth, SatD, 1e-6) then
            Inc(Bad);
        end;
  WriteLn('  configurations: ', Total, ', mismatches: ', Bad);
  Check(Bad = 0, 'degenerate grid matches SAT');
end;

{ Координатная единичная ось с номером 0..2 }
function AxisX(const Index: Integer): TVec3;
begin
  case Index of
    0: Result := V3(1, 0, 0);
    1: Result := V3(0, 1, 0);
  else
    Result := V3(0, 0, 1);
  end;
end;

{ Минимальное перекрытие по всем осям без раннего выхода (знак важен: < 0 - разделены). }
function SATMinOverlap(const HA: TVec3; const PA: TPose; const HB: TVec3; const PB: TPose;
                       out Normal: TVec3): Double;
var
  AxA, AxB, Axes: array[0..14] of TVec3;
  HAa, HBa: array[0..2] of Double;
  I, J, K, N: Integer;
  L, RA, RB, Dist, Ov, Sgn: Double;
  T: TVec3;
  AA, AB: array[0..2] of TVec3;
begin
  for I := 0 to 2 do
  begin
    AA[I] := QuatRotate(PA.Rot, AxisX(I));
    AB[I] := QuatRotate(PB.Rot, AxisX(I));
  end;
  HAa[0] := HA.X; HAa[1] := HA.Y; HAa[2] := HA.Z;
  HBa[0] := HB.X; HBa[1] := HB.Y; HBa[2] := HB.Z;
  N := 0;
  for I := 0 to 2 do begin Axes[N] := AA[I]; Inc(N); end;
  for I := 0 to 2 do begin Axes[N] := AB[I]; Inc(N); end;
  for I := 0 to 2 do
    for J := 0 to 2 do
    begin
      Axes[N] := V3Cross(AA[I], AB[J]);
      Inc(N);
    end;
  T := V3Sub(PA.Pos, PB.Pos);
  Result := 1e300;
  Normal := V3Zero;
  for K := 0 to N - 1 do
  begin
    L := V3Length(Axes[K]);
    if L < 1e-9 then
      Continue;
    Axes[K] := V3Mul(Axes[K], 1.0 / L);
    RA := 0;
    RB := 0;
    for I := 0 to 2 do
    begin
      RA := RA + HAa[I] * Abs(V3Dot(AA[I], Axes[K]));
      RB := RB + HBa[I] * Abs(V3Dot(AB[I], Axes[K]));
    end;
    Dist := V3Dot(T, Axes[K]);
    Ov := RA + RB - Abs(Dist);
    if Ov < Result then
    begin
      Result := Ov;
      if Dist >= 0 then Sgn := 1 else Sgn := -1;
      Normal := V3Mul(Axes[K], Sgn);
    end;
  end;
end;

{ Случайные вырожденные пары: позиции на полуцелой сетке, повороты обоих боксов кратны 45 градусам.
  Пары с касанием (минимальное перекрытие в пределах 1e-7) не сравниваются: там классификация
  пересечения определяется округлением. }
procedure TestDegenerateRandom(const Count: Integer);
var
  I, Bad, Skipped: Integer;
  HA, HB: TVec3;
  PA, PB: TPose;
  C: TContact;
  Hit: Boolean;
  SatN: TVec3;
  Ov: Double;
  BA, BB: TConvexShape;
begin
  WriteLn('[random degenerate pairs vs SAT, n=', Count, ']');
  Bad := 0;
  Skipped := 0;
  HA := V3(1, 1, 1);
  HB := V3(0.5, 1, 1.5);
  BA := MakeBoxShape(HA);
  BB := MakeBoxShape(HB);
  for I := 1 to Count do
  begin
    PA.Pos := V3((Random(9) - 4) * 0.5, (Random(9) - 4) * 0.5, (Random(9) - 4) * 0.5);
    PB.Pos := V3((Random(9) - 4) * 0.5, (Random(9) - 4) * 0.5, (Random(9) - 4) * 0.5);
    { оси только единичные (координатные), углы кратны 45 градусам }
    PA.Rot := QuatFromAxisAngle(AxisX(Random(3)), Random(4) * ENG_PI / 4);
    PB.Rot := QuatFromAxisAngle(AxisX(Random(3)), Random(4) * ENG_PI / 4);
    Hit := CollideConvex(BA, PA, BB, PB, C);
    Ov := SATMinOverlap(HA, PA, HB, PB, SatN);
    if Abs(Ov) <= 1e-7 then
    begin
      Inc(Skipped);
      Continue;
    end;
    if (Hit <> (Ov > 0)) or (Hit and not NearD(C.Depth, Ov, 1e-6)) then
      Inc(Bad);
  end;
  WriteLn('  touching (skipped): ', Skipped, ', mismatches: ', Bad);
  Check(Bad = 0, 'random degenerate pairs match SAT');
end;

procedure TestHulls;
var
  Pts: array of TVec3;
  Hull, Box: TConvexShape;
  C: TContact;
  Hit: Boolean;
  SHull, SBox: TConvexShape;
  Shift: TVec3;
begin
  WriteLn('[hull vs box]');
  SetLength(Pts, 4);
  Pts[0] := V3(1, 0, 0);
  Pts[1] := V3(-1, 0, 0);
  Pts[2] := V3(0, 1, 0);
  Pts[3] := V3(0, 0, 1);
  Hull := MakeHullShape(Pts);
  Box := MakeBoxShape(V3(0.5, 0.5, 0.5));
  { куб с центром в (0.9, 0, 0): вершины тетраэдра при x=1 внутри куба при x in [0.4,1.4] }
  Hit := CollideConvex(Hull, Pose(0, 0, 0), Box, Pose(0.9, 0, 0), C);
  Check(Hit, 'tetra hull overlaps box');
  Check(C.Depth > 0, 'tetra hull penetration depth positive');
  Hit := CollideConvex(Hull, Pose(0, 0, 0), Box, Pose(3, 0, 0), C);
  Check(not Hit, 'tetra hull separated from box');
  SHull := Hull;
  SBox := Box;
  Hit := CollideConvex(SHull, Pose(0, 0, 0), SBox, Pose(0.9, 0.0, 0.0), C);
  { Минимальная глубина 0.5 (эталон SAT по нормалям граней и рёбрам). Несколько осей дают
    одинаковую минимальную глубину, поэтому проверяем глубину и свойство разделения. }
  Check(Hit and NearD(C.Depth, 0.5, 1e-9), 'hull-box minimal depth 0.5');
  Shift := V3Mul(C.Normal, C.Depth * 1.02 + 1e-7);
  Check(Hit and not GJKOverlap(SHull, PoseRot(Shift.X, Shift.Y, Shift.Z, QuatIdentity),
                               SBox, Pose(0.9, 0.0, 0.0)),
        'hull-box separated along contact normal by depth');
end;

procedure BenchPairs(const Count: Integer);
var
  I, Hits: Integer;
  HA, HB: TVec3;
  PA, PB: TPose;
  C: TContact;
  BA, BB: TConvexShape;
  Stats: TCollisionStats;
  T0, T1: TDateTime;
  Seconds: Double;
begin
  WriteLn('[timing sanity, n=', Count, ']');
  Hits := 0;
  FillChar(Stats, SizeOf(Stats), 0);
  T0 := Now;
  for I := 1 to Count do
  begin
    HA := V3(0.5, 0.5, 0.5);
    HB := V3(0.5, 0.5, 0.5);
    PA.Pos := V3(Random * 1.5 - 0.75, Random * 1.5 - 0.75, Random * 1.5 - 0.75);
    PA.Rot := RandomQuat;
    PB.Pos := V3(0, 0, 0);
    PB.Rot := QuatIdentity;
    BA := MakeBoxShape(HA);
    BB := MakeBoxShape(HB);
    if CollideConvexStats(BA, PA, BB, PB, C, Stats) then
      Inc(Hits);
  end;
  T1 := Now;
  Seconds := (T1 - T0) * 86400.0;
  Check(Hits > 0, 'timing run produced contacts');
  WriteLn('  ', Hits, ' contacts, GJK iterations/pair: ',
          (Stats.GJKIterations / Count):0:2, ', EPA iterations/pair: ',
          (Stats.EPAIterations / Count):0:2, ', time: ', Seconds:0:3, ' s');
end;

begin
  GPassed := 0;
  GFailed := 0;
  Randomize;
  RandSeed := 12345;
  TestMath;
  TestSpheres;
  TestBoxBox;
  TestHulls;
  TestRandomBoxes(2000);
  TestDegenerateGrid;
  TestDegenerateRandom(50000);
  TestSeparationProperty(2000);
  BenchPairs(20000);
  RunPhysicsTests;
  RunAnimTests;
  RunRagdollTests;
  RunPngTests;
  RunRenderTests;
  WriteLn;
  WriteLn('passed: ', GPassed, ', failed: ', GFailed);
  if GFailed > 0 then
    Halt(1);
end.
