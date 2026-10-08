{ BenchMain - бенчмарк столкновений (GJK/EPA). Запуск: bench/run_bench.sh.
  Результаты зависят от железа; программа выводит также число итераций GJK и EPA на пару,
  которое не зависит от машины. Фиксированный RandSeed - прогоны воспроизводимы. }
program BenchMain;

{$mode objfpc}{$H+}

uses
  SysUtils, EngMath, EngConvex;

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

begin
  RandSeed := 2026;
  GSink := 0;
  WriteLn('EngConvex benchmark (single thread, build: FPC ', {$I %FPCVERSION%}, ' ', {$I %FPCTARGETCPU%}, ')');
  WriteLn;
  BenchSpheres(2000000);
  BenchBoxes(300000, True);
  BenchBoxes(300000, False);
  BenchHulls(50000);
  if GSink < 0 then
    WriteLn('(unreachable)');
end.
