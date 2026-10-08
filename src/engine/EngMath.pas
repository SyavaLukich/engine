{ EngMath - векторная математика движка (записи и процедуры, без классов).

  Соглашения:
    - Все физические вычисления в Double.
    - Кватернионы хранятся как (X, Y, Z, W), W - скалярная часть, единичные для вращений.
    - Матрицы TMat3 - column-major: элемент (row, col) лежит в M[col * 3 + row].
    - Функции помечены inline; они не выделяют память и не имеют побочных эффектов. }
unit EngMath;

{$mode objfpc}{$H+}
{$inline on}

interface

const
  ENG_PI = 3.14159265358979323846;
  ENG_EPS = 1e-12;

type
  TVec3 = record
    X, Y, Z: Double;
  end;

  TQuat = record
    X, Y, Z, W: Double;
  end;

  TMat3 = record
    M: array[0..8] of Double;
  end;

function V3(const AX, AY, AZ: Double): TVec3; inline;
function V3Zero: TVec3; inline;
function V3Add(const A, B: TVec3): TVec3; inline;
function V3Sub(const A, B: TVec3): TVec3; inline;
function V3Mul(const A: TVec3; const S: Double): TVec3; inline;
{ A + B * S }
function V3MulAdd(const A, B: TVec3; const S: Double): TVec3; inline;
function V3Neg(const A: TVec3): TVec3; inline;
function V3Dot(const A, B: TVec3): Double; inline;
function V3Cross(const A, B: TVec3): TVec3; inline;
function V3LengthSq(const A: TVec3): Double; inline;
function V3Length(const A: TVec3): Double; inline;
{ Возвращает нулевой вектор, если длина меньше ENG_EPS. }
function V3Normalize(const A: TVec3): TVec3; inline;
function V3Lerp(const A, B: TVec3; const T: Double): TVec3; inline;
function V3Min(const A, B: TVec3): TVec3; inline;
function V3Max(const A, B: TVec3): TVec3; inline;
function V3Abs(const A: TVec3): TVec3; inline;
function V3Distance(const A, B: TVec3): Double; inline;
{ Любой единичный вектор, ортогональный единичному N. }
function V3Perpendicular(const N: TVec3): TVec3;

function ClampD(const X, Lo, Hi: Double): Double; inline;
function MinD(const A, B: Double): Double; inline;
function MaxD(const A, B: Double): Double; inline;

function QuatIdentity: TQuat; inline;
function QuatMul(const A, B: TQuat): TQuat; inline;
function QuatConj(const Q: TQuat): TQuat; inline;
function QuatDot(const A, B: TQuat): Double; inline;
function QuatNormalize(const Q: TQuat): TQuat; inline;
{ Ось Axis должна быть единичной. }
function QuatFromAxisAngle(const Axis: TVec3; const Angle: Double): TQuat;
function QuatRotate(const Q: TQuat; const V: TVec3): TVec3; inline;
function QuatInvRotate(const Q: TQuat; const V: TVec3): TVec3; inline;
{ Интегрирование угловой скорости W (мировая система) за время Dt. }
function QuatIntegrate(const Q: TQuat; const W: TVec3; const Dt: Double): TQuat;
function QuatSlerp(const A, B: TQuat; const T: Double): TQuat;
function QuatToMat3(const Q: TQuat): TMat3;

function Mat3Identity: TMat3; inline;
function Mat3Mul(const A, B: TMat3): TMat3;
function Mat3MulV(const A: TMat3; const V: TVec3): TVec3; inline;
function Mat3Transpose(const A: TMat3): TMat3;
function Mat3Inverse(const A: TMat3): TMat3;
function Mat3Diagonal(const D: TVec3): TMat3; inline;

implementation

uses
  Math;

function V3(const AX, AY, AZ: Double): TVec3;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.Z := AZ;
end;

function V3Zero: TVec3;
begin
  Result.X := 0;
  Result.Y := 0;
  Result.Z := 0;
end;

function V3Add(const A, B: TVec3): TVec3;
begin
  Result.X := A.X + B.X;
  Result.Y := A.Y + B.Y;
  Result.Z := A.Z + B.Z;
end;

function V3Sub(const A, B: TVec3): TVec3;
begin
  Result.X := A.X - B.X;
  Result.Y := A.Y - B.Y;
  Result.Z := A.Z - B.Z;
end;

function V3Mul(const A: TVec3; const S: Double): TVec3;
begin
  Result.X := A.X * S;
  Result.Y := A.Y * S;
  Result.Z := A.Z * S;
end;

function V3MulAdd(const A, B: TVec3; const S: Double): TVec3;
begin
  Result.X := A.X + B.X * S;
  Result.Y := A.Y + B.Y * S;
  Result.Z := A.Z + B.Z * S;
end;

function V3Neg(const A: TVec3): TVec3;
begin
  Result.X := -A.X;
  Result.Y := -A.Y;
  Result.Z := -A.Z;
end;

function V3Dot(const A, B: TVec3): Double;
begin
  Result := A.X * B.X + A.Y * B.Y + A.Z * B.Z;
end;

function V3Cross(const A, B: TVec3): TVec3;
begin
  Result.X := A.Y * B.Z - A.Z * B.Y;
  Result.Y := A.Z * B.X - A.X * B.Z;
  Result.Z := A.X * B.Y - A.Y * B.X;
end;

function V3LengthSq(const A: TVec3): Double;
begin
  Result := A.X * A.X + A.Y * A.Y + A.Z * A.Z;
end;

function V3Length(const A: TVec3): Double;
begin
  Result := Sqrt(A.X * A.X + A.Y * A.Y + A.Z * A.Z);
end;

function V3Normalize(const A: TVec3): TVec3;
var
  L2, InvL: Double;
begin
  L2 := A.X * A.X + A.Y * A.Y + A.Z * A.Z;
  if L2 < ENG_EPS then
  begin
    Result.X := 0;
    Result.Y := 0;
    Result.Z := 0;
  end
  else
  begin
    InvL := 1.0 / Sqrt(L2);
    Result.X := A.X * InvL;
    Result.Y := A.Y * InvL;
    Result.Z := A.Z * InvL;
  end;
end;

function V3Lerp(const A, B: TVec3; const T: Double): TVec3;
begin
  Result.X := A.X + (B.X - A.X) * T;
  Result.Y := A.Y + (B.Y - A.Y) * T;
  Result.Z := A.Z + (B.Z - A.Z) * T;
end;

function V3Min(const A, B: TVec3): TVec3;
begin
  Result.X := MinD(A.X, B.X);
  Result.Y := MinD(A.Y, B.Y);
  Result.Z := MinD(A.Z, B.Z);
end;

function V3Max(const A, B: TVec3): TVec3;
begin
  Result.X := MaxD(A.X, B.X);
  Result.Y := MaxD(A.Y, B.Y);
  Result.Z := MaxD(A.Z, B.Z);
end;

function V3Abs(const A: TVec3): TVec3;
begin
  Result.X := Abs(A.X);
  Result.Y := Abs(A.Y);
  Result.Z := Abs(A.Z);
end;

function V3Distance(const A, B: TVec3): Double;
begin
  Result := V3Length(V3Sub(A, B));
end;

function V3Perpendicular(const N: TVec3): TVec3;
var
  Ax: TVec3;
begin
  { Берём ось, наименее параллельную N, и строим перпендикуляр через векторное произведение. }
  if Abs(N.X) < 0.57735026919 then
    Ax := V3(1, 0, 0)
  else if Abs(N.Y) < 0.57735026919 then
    Ax := V3(0, 1, 0)
  else
    Ax := V3(0, 0, 1);
  Result := V3Normalize(V3Cross(N, Ax));
end;

function ClampD(const X, Lo, Hi: Double): Double;
begin
  if X < Lo then
    Result := Lo
  else if X > Hi then
    Result := Hi
  else
    Result := X;
end;

function MinD(const A, B: Double): Double;
begin
  if A < B then Result := A else Result := B;
end;

function MaxD(const A, B: Double): Double;
begin
  if A > B then Result := A else Result := B;
end;

function QuatIdentity: TQuat;
begin
  Result.X := 0;
  Result.Y := 0;
  Result.Z := 0;
  Result.W := 1;
end;

function QuatMul(const A, B: TQuat): TQuat;
begin
  Result.W := A.W * B.W - A.X * B.X - A.Y * B.Y - A.Z * B.Z;
  Result.X := A.W * B.X + A.X * B.W + A.Y * B.Z - A.Z * B.Y;
  Result.Y := A.W * B.Y - A.X * B.Z + A.Y * B.W + A.Z * B.X;
  Result.Z := A.W * B.Z + A.X * B.Y - A.Y * B.X + A.Z * B.W;
end;

function QuatConj(const Q: TQuat): TQuat;
begin
  Result.X := -Q.X;
  Result.Y := -Q.Y;
  Result.Z := -Q.Z;
  Result.W := Q.W;
end;

function QuatDot(const A, B: TQuat): Double;
begin
  Result := A.X * B.X + A.Y * B.Y + A.Z * B.Z + A.W * B.W;
end;

function QuatNormalize(const Q: TQuat): TQuat;
var
  L2, InvL: Double;
begin
  L2 := Q.X * Q.X + Q.Y * Q.Y + Q.Z * Q.Z + Q.W * Q.W;
  if L2 < ENG_EPS then
    Result := QuatIdentity
  else
  begin
    InvL := 1.0 / Sqrt(L2);
    Result.X := Q.X * InvL;
    Result.Y := Q.Y * InvL;
    Result.Z := Q.Z * InvL;
    Result.W := Q.W * InvL;
  end;
end;

function QuatFromAxisAngle(const Axis: TVec3; const Angle: Double): TQuat;
var
  S, C: Double;
begin
  S := Sin(Angle * 0.5);
  C := Cos(Angle * 0.5);
  Result.X := Axis.X * S;
  Result.Y := Axis.Y * S;
  Result.Z := Axis.Z * S;
  Result.W := C;
end;

function QuatRotate(const Q: TQuat; const V: TVec3): TVec3;
var
  U, T: TVec3;
begin
  { v' = v + 2w(u x v) + 2 u x (u x v), u = xyz(q) }
  U := V3(Q.X, Q.Y, Q.Z);
  T := V3Mul(V3Cross(U, V), 2.0);
  Result := V3Add(V3Add(V, V3Mul(T, Q.W)), V3Cross(U, T));
end;

function QuatInvRotate(const Q: TQuat; const V: TVec3): TVec3;
begin
  Result := QuatRotate(QuatConj(Q), V);
end;

function QuatIntegrate(const Q: TQuat; const W: TVec3; const Dt: Double): TQuat;
var
  WQ, D: TQuat;
  H: Double;
begin
  WQ.X := W.X;
  WQ.Y := W.Y;
  WQ.Z := W.Z;
  WQ.W := 0;
  D := QuatMul(WQ, Q);
  H := 0.5 * Dt;
  Result.X := Q.X + D.X * H;
  Result.Y := Q.Y + D.Y * H;
  Result.Z := Q.Z + D.Z * H;
  Result.W := Q.W + D.W * H;
  Result := QuatNormalize(Result);
end;

function QuatSlerp(const A, B: TQuat; const T: Double): TQuat;
var
  Cs, Theta, S0, S1, SinT: Double;
  Bq: TQuat;
begin
  Bq := B;
  Cs := QuatDot(A, B);
  if Cs < 0 then
  begin
    Cs := -Cs;
    Bq.X := -B.X;
    Bq.Y := -B.Y;
    Bq.Z := -B.Z;
    Bq.W := -B.W;
  end;
  if Cs > 0.9995 then
  begin
    { Почти параллельны: линейная интерполяция с нормализацией. }
    Result.X := A.X + (Bq.X - A.X) * T;
    Result.Y := A.Y + (Bq.Y - A.Y) * T;
    Result.Z := A.Z + (Bq.Z - A.Z) * T;
    Result.W := A.W + (Bq.W - A.W) * T;
    Result := QuatNormalize(Result);
    Exit;
  end;
  Theta := ArcCos(Cs);
  SinT := Sin(Theta);
  S0 := Sin((1.0 - T) * Theta) / SinT;
  S1 := Sin(T * Theta) / SinT;
  Result.X := A.X * S0 + Bq.X * S1;
  Result.Y := A.Y * S0 + Bq.Y * S1;
  Result.Z := A.Z * S0 + Bq.Z * S1;
  Result.W := A.W * S0 + Bq.W * S1;
end;

function QuatToMat3(const Q: TQuat): TMat3;
var
  X2, Y2, Z2, XX, XY, XZ, YY, YZ, ZZ, WX, WY, WZ: Double;
begin
  X2 := Q.X + Q.X;
  Y2 := Q.Y + Q.Y;
  Z2 := Q.Z + Q.Z;
  XX := Q.X * X2;
  XY := Q.X * Y2;
  XZ := Q.X * Z2;
  YY := Q.Y * Y2;
  YZ := Q.Y * Z2;
  ZZ := Q.Z * Z2;
  WX := Q.W * X2;
  WY := Q.W * Y2;
  WZ := Q.W * Z2;
  { column-major: M[col*3+row] }
  Result.M[0] := 1.0 - (YY + ZZ);
  Result.M[1] := XY + WZ;
  Result.M[2] := XZ - WY;
  Result.M[3] := XY - WZ;
  Result.M[4] := 1.0 - (XX + ZZ);
  Result.M[5] := YZ + WX;
  Result.M[6] := XZ + WY;
  Result.M[7] := YZ - WX;
  Result.M[8] := 1.0 - (XX + YY);
end;

function Mat3Identity: TMat3;
begin
  FillChar(Result.M, SizeOf(Result.M), 0);
  Result.M[0] := 1;
  Result.M[4] := 1;
  Result.M[8] := 1;
end;

function Mat3Mul(const A, B: TMat3): TMat3;
var
  R, C: Integer;
begin
  for C := 0 to 2 do
    for R := 0 to 2 do
      Result.M[C * 3 + R] := A.M[0 * 3 + R] * B.M[C * 3 + 0]
                           + A.M[1 * 3 + R] * B.M[C * 3 + 1]
                           + A.M[2 * 3 + R] * B.M[C * 3 + 2];
end;

function Mat3MulV(const A: TMat3; const V: TVec3): TVec3;
begin
  Result.X := A.M[0] * V.X + A.M[3] * V.Y + A.M[6] * V.Z;
  Result.Y := A.M[1] * V.X + A.M[4] * V.Y + A.M[7] * V.Z;
  Result.Z := A.M[2] * V.X + A.M[5] * V.Y + A.M[8] * V.Z;
end;

function Mat3Transpose(const A: TMat3): TMat3;
var
  R, C: Integer;
begin
  for C := 0 to 2 do
    for R := 0 to 2 do
      Result.M[R * 3 + C] := A.M[C * 3 + R];
end;

function Mat3Inverse(const A: TMat3): TMat3;
var
  M: array[0..8] of Double;
  Det, InvDet: Double;
begin
  M := A.M;
  { Строки матрицы: a(r,c) = M[c*3+r] }
  Det := M[0] * (M[4] * M[8] - M[7] * M[5])
       - M[3] * (M[1] * M[8] - M[7] * M[2])
       + M[6] * (M[1] * M[5] - M[4] * M[2]);
  if Abs(Det) < ENG_EPS then
  begin
    Result := Mat3Identity;
    Exit;
  end;
  InvDet := 1.0 / Det;
  Result.M[0] := (M[4] * M[8] - M[7] * M[5]) * InvDet;
  Result.M[1] := (M[7] * M[2] - M[1] * M[8]) * InvDet;
  Result.M[2] := (M[1] * M[5] - M[4] * M[2]) * InvDet;
  Result.M[3] := (M[6] * M[5] - M[3] * M[8]) * InvDet;
  Result.M[4] := (M[0] * M[8] - M[6] * M[2]) * InvDet;
  Result.M[5] := (M[3] * M[2] - M[0] * M[5]) * InvDet;
  Result.M[6] := (M[3] * M[7] - M[6] * M[4]) * InvDet;
  Result.M[7] := (M[6] * M[1] - M[0] * M[7]) * InvDet;
  Result.M[8] := (M[0] * M[4] - M[3] * M[1]) * InvDet;
end;

function Mat3Diagonal(const D: TVec3): TMat3;
begin
  FillChar(Result.M, SizeOf(Result.M), 0);
  Result.M[0] := D.X;
  Result.M[4] := D.Y;
  Result.M[8] := D.Z;
end;

end.
