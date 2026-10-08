{ BenchMain - бенчмарк движка: столкновения (GJK/EPA), физика, рэгдолл, анимация, PNG.
  Запуск: ./build.sh bench.
  Результаты зависят от железа; программа выводит также число итераций GJK и EPA на пару,
  которое не зависит от машины. Фиксированный RandSeed - прогоны воспроизводимы. }
program BenchMain;

{$mode objfpc}{$H+}

uses
  { EngConvex - последним: его TPose (поза тела) перекрывает TPose из EngAnim (поза скелета);
    в анимационном бенчмарке тип указан явно как EngAnim.TPose }
  SysUtils, EngMath, EngPhysics, EngRagdoll, EngHumanoid, EngAnim, EngPNG, EngConvex;

var
  GSink: Integer;   { не даёт компилятору выбросить результаты }

{ Монотонное время в секундах (разрешение миллисекунды - достаточно для секундных прогонов). }
function NowSeconds: Double;
begin
  Result := GetTickCount64 * 1e-3;
end;

function RandomQuat: TQuat;
var
  U1, U2, U3, S1, S2: Double;
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

procedure Report(const Name: string; const Ops: Integer; const Seconds: Double;
                 const Stats: TCollisionStats);
begin
  WriteLn(Name);
  WriteLn('  pairs: ', Ops, ', time: ', Seconds:0:4, ' s');
  WriteLn('  throughput: ', (Ops / Seconds / 1e6):0:3, ' M pairs/s, ',
          (Seconds / Ops * 1e6):0:4, ' us/pair');
  if Stats.GJKIterations > 0 then
    WriteLn('  GJK iterations/pair: ', (Stats.GJKIterations / Ops):0:2,
            ', EPA iterations/pair: ', (Stats.EPAIterations / Ops):0:2,
            ', fallbacks: ', Stats.Fallbacks);
  WriteLn;
end;

procedure BenchSpheres(const Count: Integer);
var
  I, Hits: Integer;
  SA, SB: TConvexShape;
  PA, PB: TPose;
  C: TContact;
  Stats: TCollisionStats;
  T0, T1: Double;
begin
  SA := MakeSphereShape(0.5);
  SB := MakeSphereShape(0.5);
  Hits := 0;
  FillChar(Stats, SizeOf(Stats), 0);
  PB.Pos := V3(0, 0, 0);
  PB.Rot := QuatIdentity;
  PA.Rot := QuatIdentity;
  T0 := NowSeconds;
  for I := 1 to Count do
  begin
    PA.Pos := V3(Random * 1.4 - 0.7, Random * 1.4 - 0.7, Random * 1.4 - 0.7);
    if CollideConvexStats(SA, PA, SB, PB, C, Stats) then
      Inc(Hits);
  end;
  T1 := NowSeconds;
  GSink := GSink + Hits;
  Report('sphere-sphere (analytic path)', Count, T1 - T0, Stats);
end;

procedure BenchBoxes(const Count: Integer; const UseGJKOnly: Boolean);
var
  I, Hits: Integer;
  BA, BB: TConvexShape;
  PA, PB: TPose;
  C: TContact;
  Stats: TCollisionStats;
  T0, T1: Double;
  Ov: Boolean;
begin
  BA := MakeBoxShape(V3(0.5, 0.6, 0.7));
  BB := MakeBoxShape(V3(0.6, 0.5, 0.4));
  Hits := 0;
  FillChar(Stats, SizeOf(Stats), 0);
  PB.Pos := V3(0, 0, 0);
  PB.Rot := QuatIdentity;
  T0 := NowSeconds;
  for I := 1 to Count do
  begin
    PA.Pos := V3(Random * 1.6 - 0.8, Random * 1.6 - 0.8, Random * 1.6 - 0.8);
    PA.Rot := RandomQuat;
    if UseGJKOnly then
    begin
      Ov := GJKOverlap(BA, PA, BB, PB);
      if Ov then Inc(Hits);
    end
    else if CollideConvexStats(BA, PA, BB, PB, C, Stats) then
      Inc(Hits);
  end;
  T1 := NowSeconds;
  GSink := GSink + Hits;
  if UseGJKOnly then
    Report('box-box GJK overlap only', Count, T1 - T0, Stats)
  else
    Report('box-box GJK + EPA (contact)', Count, T1 - T0, Stats);
end;

procedure BenchHulls(const Count: Integer);
var
  I, K, Hits: Integer;
  PtsA, PtsB: array of TVec3;
  HA, HB: TConvexShape;
  PA, PB: TPose;
  C: TContact;
  Stats: TCollisionStats;
  T0, T1: Double;
  U, V, W: Double;
begin
  SetLength(PtsA, 20);
  SetLength(PtsB, 20);
  for K := 0 to 19 do
  begin
    U := Random * 2 - 1;
    V := Random * 2 * ENG_PI;
    W := Sqrt(1 - U * U);
    PtsA[K] := V3(W * Cos(V) * 0.6, W * Sin(V) * 0.6, U * 0.6);
    U := Random * 2 - 1;
    V := Random * 2 * ENG_PI;
    W := Sqrt(1 - U * U);
    PtsB[K] := V3(W * Cos(V) * 0.6, W * Sin(V) * 0.6, U * 0.6);
  end;
  HA := MakeHullShape(PtsA);
  HB := MakeHullShape(PtsB);
  Hits := 0;
  FillChar(Stats, SizeOf(Stats), 0);
  PB.Pos := V3(0, 0, 0);
  PB.Rot := QuatIdentity;
  T0 := NowSeconds;
  for I := 1 to Count do
  begin
    PA.Pos := V3(Random * 1.0 - 0.5, Random * 1.0 - 0.5, Random * 1.0 - 0.5);
    PA.Rot := RandomQuat;
    if CollideConvexStats(HA, PA, HB, PB, C, Stats) then
      Inc(Hits);
  end;
  T1 := NowSeconds;
  GSink := GSink + Hits;
  Report('convex hull (20 pts) vs hull (20 pts), GJK + EPA', Count, T1 - T0, Stats);
end;

{ ---- физика ---- }

{ Стопка коробок Side x Side x Layers. Соседние коробки перекрываются на 2 см, поэтому идут
  контакты тело-тело (GJK/EPA) и тело-пол. Время включает установку стопки в покой. }
procedure BenchPhysicsStack(const Side, Layers, Steps: Integer);
var
  W: TPhysWorld;
  S: TConvexShape;
  I, J, L, K, N: Integer;
  T0, T1, MaxSpeed, Spd: Double;
  ContactSum: Int64;
begin
  PhysWorldInit(W, V3(0, -9.81, 0), 16);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.8, 0);
  S := MakeBoxShape(V3(0.5, 0.5, 0.5));
  N := 0;
  for L := 0 to Layers - 1 do
    for I := 0 to Side - 1 do
      for J := 0 to Side - 1 do
      begin
        PhysAddBody(W, PhysMakeBody(S, V3((I - (Side - 1) / 2) * 0.98, 0.5 + L * 0.98,
                                          (J - (Side - 1) / 2) * 0.98), QuatIdentity, 5));
        Inc(N);
      end;
  for K := 1 to 240 do
    PhysStep(W, 1.0 / 240.0);
  ContactSum := 0;
  T0 := NowSeconds;
  for K := 1 to Steps do
  begin
    PhysStep(W, 1.0 / 240.0);
    ContactSum := ContactSum + W.ContactCount;
  end;
  T1 := NowSeconds;
  MaxSpeed := 0;
  for I := 0 to W.BodyCount - 1 do
  begin
    Spd := Sqrt(Sqr(W.Bodies[I].Vel.X) + Sqr(W.Bodies[I].Vel.Y) + Sqr(W.Bodies[I].Vel.Z));
    if Spd > MaxSpeed then MaxSpeed := Spd;
  end;
  WriteLn('стопка коробок: ', N, ' тел, ', Steps, ' шагов по 1/240 с');
  WriteLn('  мкс на шаг: ', (T1 - T0) * 1e6 / Steps:0:1,
          ', мкс на тело за шаг: ', (T1 - T0) * 1e6 / Steps / N:0:3);
  WriteLn('  среднее число контактов за шаг: ', ContactSum / Steps:0:1,
          ', макс. скорость тела в конце: ', MaxSpeed:0:3, ' м/с');
  WriteLn;
end;

{ Падение Count шаров радиуса 0.25 м в случайные точки: широкая фаза, контакты тело-тело и тело-пол. }
procedure BenchPhysicsSpheres(const Count, Steps: Integer);
var
  W: TPhysWorld;
  S: TConvexShape;
  I, K: Integer;
  T0, T1: Double;
  ContactSum: Int64;
begin
  PhysWorldInit(W, V3(0, -9.81, 0), 16);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.5, 0.3);
  S := MakeSphereShape(0.25);
  for I := 0 to Count - 1 do
    PhysAddBody(W, PhysMakeBody(S, V3((Random - 0.5) * 4, 0.25 + I * 0.05, (Random - 0.5) * 4),
                                QuatIdentity, 1));
  ContactSum := 0;
  T0 := NowSeconds;
  for K := 1 to Steps do
  begin
    PhysStep(W, 1.0 / 240.0);
    ContactSum := ContactSum + W.ContactCount;
  end;
  T1 := NowSeconds;
  WriteLn('шары: ', Count, ' тел, ', Steps, ' шагов по 1/240 с (включая падение)');
  WriteLn('  мкс на шаг: ', (T1 - T0) * 1e6 / Steps:0:1,
          ', мкс на тело за шаг: ', (T1 - T0) * 1e6 / Steps / Count:0:3);
  WriteLn('  среднее число контактов за шаг: ', ContactSum / Steps:0:1);
  WriteLn;
end;

{ ---- рэгдолл и анимация ---- }

{ Один рэгдолл: балансировка стойкой (как в тестах), кадр 1/60 с, 4 подшага физики. }
procedure BenchRagdoll(const Frames: Integer);
var
  W: TPhysWorld;
  R: TRagdoll;
  K: Integer;
  T0, T1: Double;
begin
  PhysWorldInit(W, V3(0, -9.81, 0), 16);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.8, 0);
  RagdollCreate(W, R, V3Zero, 0, 1);
  for K := 1 to 120 do
    RagdollAdvance(W, R, 1.0 / 60.0, 4);
  T0 := NowSeconds;
  for K := 1 to Frames do
    RagdollAdvance(W, R, 1.0 / 60.0, 4);
  T1 := NowSeconds;
  WriteLn('рэгдолл: стойка, кадр 1/60 с, 4 подшага, 16 итераций решателя');
  WriteLn('  мкс на кадр: ', (T1 - T0) * 1e6 / Frames:0:1,
          ', мкс на подшаг: ', (T1 - T0) * 1e6 / Frames / 4:0:1);
  WriteLn('  высота таза: ', RagdollPelvisHeight(W, R):0:3, ' м, ошибка шарниров: ',
          RagdollMaxJointError(W, R):0:4, ' м');
  WriteLn;
end;

{ Скелет на 15 костей: выборка клипа, кроссфейд каждые 2 с и мировые позы (прямая кинематика). }
procedure BenchAnimation(const Frames: Integer);
var
  S: TSkeleton;
  Lib: TClipLib;
  Pl: TAnimPlayer;
  P, G: EngAnim.TPose;
  K, Idle, Sway: Integer;
  T0, T1: Double;
begin
  HumanoidSkeleton(S);
  HumanoidClips(S, Lib);
  Idle := ClipFindInLib(Lib, 'idle');
  Sway := ClipFindInLib(Lib, 'sway');
  PoseBind(S, P);
  PoseBind(S, G);
  PlayerInit(Pl);
  PlayerPlay(Pl, Idle, 0.2);
  T0 := NowSeconds;
  for K := 1 to Frames do
  begin
    if (K mod 120 = 0) and (Sway >= 0) then
    begin
      if (K div 120) mod 2 = 0 then
        PlayerPlay(Pl, Idle, 0.3)
      else
        PlayerPlay(Pl, Sway, 0.3);
    end;
    PlayerUpdate(Pl, Lib, 1.0 / 60.0);
    PlayerEvaluate(Pl, S, Lib, P);
    PoseGlobal(S, P, G);
  end;
  T1 := NowSeconds;
  WriteLn('анимация: 15 костей, выборка клипа, кроссфейд каждые 2 с, мировые позы');
  WriteLn('  мкс на кадр: ', (T1 - T0) * 1e6 / Frames:0:3);
  WriteLn;
end;

{ ---- PNG ---- }

{ Кодирование Width x Height RGB (deflate stored, без сжатия) и CRC-32 по тому же буферу. }
procedure BenchPng(const Width, Height, Reps: Integer);
var
  Buf, Img: TByteBuf;
  I, K: Integer;
  Crc: LongWord;
  T0, T1, T2: Double;
begin
  SetLength(Buf, Width * Height * 3);
  for I := 0 to High(Buf) do
    Buf[I] := Byte((I * 13 + (I div (Width * 3)) * 7) and 255);
  T0 := NowSeconds;
  for K := 1 to Reps do
  begin
    Img := PngEncode(Width, Height, 3, Buf);
    GSink := GSink + Integer(Length(Img) and 1);
  end;
  T1 := NowSeconds;
  Crc := 0;
  for K := 1 to Reps do
    Crc := Crc32Of(Buf, 0, Length(Buf), $FFFFFFFF);
  T2 := NowSeconds;
  WriteLn('PNG: ', Width, 'x', Height, ' RGB, кодирований: ', Reps);
  WriteLn('  мс на кадр: ', (T1 - T0) * 1e3 / Reps:0:2,
          ', размер файла: ', Length(Img) / 1048576:0:2, ' МБ (без сжатия)');
  GSink := GSink + Integer(Crc and 1);
  WriteLn('  CRC-32: ', (T2 - T1) * 1e3 / Reps:0:2, ' мс на буфер, ',
          Length(Buf) * Reps / (T2 - T1) / 1e6:0:0, ' МБ/с');
  WriteLn;
end;

begin
  RandSeed := 2026;
  GSink := 0;
  WriteLn('EngConvex benchmark (single thread, build: FPC ', {$I %FPCVERSION%}, ' ', {$I %FPCTARGETCPU%}, ')');
  WriteLn;
  BenchSpheres(2000000);
  BenchBoxes(300000, True);
  BenchBoxes(300000, False);
  BenchHulls(50000);
  WriteLn('== физика, рэгдолл, анимация, PNG ==');
  WriteLn;
  BenchPhysicsStack(10, 4, 1200);
  BenchPhysicsSpheres(400, 1200);
  BenchRagdoll(6000);
  BenchAnimation(600000);
  BenchPng(1280, 720, 20);
  if GSink < 0 then
    WriteLn('(unreachable)');
end.
