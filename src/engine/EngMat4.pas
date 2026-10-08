{ EngMat4 - матрицы 4x4 (хранение по столбцам, как в OpenGL), камера и проекции.

  Соглашения:
    - M[col*4 + row]; умножение столбцов на вектор: Mul(M, v) = M * v;
    - правосторонняя система координат, камера смотрит вдоль -Z в системе вида;
    - глубина проекции в диапазоне [-1, 1] (OpenGL). }
unit EngMat4;

{$mode objfpc}{$H+}
{$inline on}

interface

uses
  Math, EngMath;

type
  TMat4 = record
    M: array[0..15] of Double;
  end;

  TMat4F = array[0..15] of Single;   { для загрузки в GL }

function Mat4Identity: TMat4;
function Mat4Mul(const A, B: TMat4): TMat4;
function Mat4MulPoint(const A: TMat4; const P: TVec3): TVec3;
function Mat4FromRT(const Pos: TVec3; const Rot: TQuat; const Scale: TVec3): TMat4;
function Mat4Perspective(FovY, Aspect, ZNear, ZFar: Double): TMat4;
function Mat4Ortho(Left, Right, Bottom, Top, ZNear, ZFar: Double): TMat4;
function Mat4LookAt(const Eye, Center, Up: TVec3): TMat4;
function Mat4Inverse(const A: TMat4): TMat4;
function Mat4ToF(const A: TMat4): TMat4F;

implementation

function Mat4Identity: TMat4;
var
  I: Integer;
begin
  for I := 0 to 15 do
    Result.M[I] := 0;
  Result.M[0] := 1;
  Result.M[5] := 1;
  Result.M[10] := 1;
  Result.M[15] := 1;
end;

function Mat4Mul(const A, B: TMat4): TMat4;
var
  C, R: Integer;
  S: Double;
  K: Integer;
begin
  for C := 0 to 3 do
    for R := 0 to 3 do
    begin
      S := 0;
      for K := 0 to 3 do
        S := S + A.M[K * 4 + R] * B.M[C * 4 + K];
      Result.M[C * 4 + R] := S;
    end;
end;

function Mat4MulPoint(const A: TMat4; const P: TVec3): TVec3;
begin
  Result.X := A.M[0] * P.X + A.M[4] * P.Y + A.M[8] * P.Z + A.M[12];
  Result.Y := A.M[1] * P.X + A.M[5] * P.Y + A.M[9] * P.Z + A.M[13];
  Result.Z := A.M[2] * P.X + A.M[6] * P.Y + A.M[10] * P.Z + A.M[14];
end;

function Mat4FromRT(const Pos: TVec3; const Rot: TQuat; const Scale: TVec3): TMat4;
var
  R: TMat3;
begin
  R := QuatToMat3(Rot);
  { столбцы масштабируем по осям }
  Result.M[0] := R.M[0] * Scale.X;
  Result.M[1] := R.M[1] * Scale.X;
  Result.M[2] := R.M[2] * Scale.X;
  Result.M[3] := 0;
  Result.M[4] := R.M[3] * Scale.Y;
  Result.M[5] := R.M[4] * Scale.Y;
  Result.M[6] := R.M[5] * Scale.Y;
  Result.M[7] := 0;
  Result.M[8] := R.M[6] * Scale.Z;
  Result.M[9] := R.M[7] * Scale.Z;
  Result.M[10] := R.M[8] * Scale.Z;
  Result.M[11] := 0;
  Result.M[12] := Pos.X;
  Result.M[13] := Pos.Y;
  Result.M[14] := Pos.Z;
  Result.M[15] := 1;
end;

function Mat4Perspective(FovY, Aspect, ZNear, ZFar: Double): TMat4;
var
  F: Double;
  I: Integer;
begin
  for I := 0 to 15 do
    Result.M[I] := 0;
  F := 1.0 / Tan(FovY * 0.5);
  Result.M[0] := F / Aspect;
  Result.M[5] := F;
  Result.M[10] := (ZFar + ZNear) / (ZNear - ZFar);
  Result.M[11] := -1;
  Result.M[14] := 2.0 * ZFar * ZNear / (ZNear - ZFar);
end;

function Mat4Ortho(Left, Right, Bottom, Top, ZNear, ZFar: Double): TMat4;
var
  I: Integer;
begin
  for I := 0 to 15 do
    Result.M[I] := 0;
  Result.M[0] := 2.0 / (Right - Left);
  Result.M[5] := 2.0 / (Top - Bottom);
  Result.M[10] := -2.0 / (ZFar - ZNear);
  Result.M[12] := -(Right + Left) / (Right - Left);
  Result.M[13] := -(Top + Bottom) / (Top - Bottom);
  Result.M[14] := -(ZFar + ZNear) / (ZFar - ZNear);
  Result.M[15] := 1;
end;

function Mat4LookAt(const Eye, Center, Up: TVec3): TMat4;
var
  F, S, U: TVec3;
  I: Integer;
begin
  F := V3Normalize(V3Sub(Center, Eye));
  S := V3Normalize(V3Cross(F, Up));
  if V3Length(S) < 1e-9 then
    S := V3Normalize(V3Cross(F, V3Perpendicular(F)));
  U := V3Cross(S, F);
  for I := 0 to 15 do
    Result.M[I] := 0;
  Result.M[0] := S.X;
  Result.M[4] := S.Y;
  Result.M[8] := S.Z;
  Result.M[1] := U.X;
  Result.M[5] := U.Y;
  Result.M[9] := U.Z;
  Result.M[2] := -F.X;
  Result.M[6] := -F.Y;
  Result.M[10] := -F.Z;
  Result.M[12] := -V3Dot(S, Eye);
  Result.M[13] := -V3Dot(U, Eye);
  Result.M[14] := V3Dot(F, Eye);
  Result.M[15] := 1;
end;

{ Обращение общей матрицы 4x4 (разложение по строкам, метод присоединённых миноров). }
function Mat4Inverse(const A: TMat4): TMat4;
var
  Inv: array[0..15] of Double;
  M: array[0..15] of Double;
  I: Integer;
  Det: Double;
begin
  for I := 0 to 15 do
    M[I] := A.M[I];
  Inv[0] := M[5] * M[10] * M[15] - M[5] * M[11] * M[14] - M[9] * M[6] * M[15] + M[9] * M[7] * M[14] + M[13] * M[6] * M[11] - M[13] * M[7] * M[10];
  Inv[4] := -M[4] * M[10] * M[15] + M[4] * M[11] * M[14] + M[8] * M[6] * M[15] - M[8] * M[7] * M[14] - M[12] * M[6] * M[11] + M[12] * M[7] * M[10];
  Inv[8] := M[4] * M[9] * M[15] - M[4] * M[11] * M[13] - M[8] * M[5] * M[15] + M[8] * M[7] * M[13] + M[12] * M[5] * M[11] - M[12] * M[7] * M[9];
  Inv[12] := -M[4] * M[9] * M[14] + M[4] * M[10] * M[13] + M[8] * M[5] * M[14] - M[8] * M[6] * M[13] - M[12] * M[5] * M[10] + M[12] * M[6] * M[9];
  Inv[1] := -M[1] * M[10] * M[15] + M[1] * M[11] * M[14] + M[9] * M[2] * M[15] - M[9] * M[3] * M[14] - M[13] * M[2] * M[11] + M[13] * M[3] * M[10];
  Inv[5] := M[0] * M[10] * M[15] - M[0] * M[11] * M[14] - M[8] * M[2] * M[15] + M[8] * M[3] * M[14] + M[12] * M[2] * M[11] - M[12] * M[3] * M[10];
  Inv[9] := -M[0] * M[9] * M[15] + M[0] * M[11] * M[13] + M[8] * M[1] * M[15] - M[8] * M[3] * M[13] - M[12] * M[1] * M[11] + M[12] * M[3] * M[9];
  Inv[13] := M[0] * M[9] * M[14] - M[0] * M[10] * M[13] - M[8] * M[1] * M[14] + M[8] * M[2] * M[13] + M[12] * M[1] * M[10] - M[12] * M[2] * M[9];
  Inv[2] := M[1] * M[6] * M[15] - M[1] * M[7] * M[14] - M[5] * M[2] * M[15] + M[5] * M[3] * M[14] + M[13] * M[2] * M[7] - M[13] * M[3] * M[6];
  Inv[6] := -M[0] * M[6] * M[15] + M[0] * M[7] * M[14] + M[4] * M[2] * M[15] - M[4] * M[3] * M[14] - M[12] * M[2] * M[7] + M[12] * M[3] * M[6];
  Inv[10] := M[0] * M[5] * M[15] - M[0] * M[7] * M[13] - M[4] * M[1] * M[15] + M[4] * M[3] * M[13] + M[12] * M[1] * M[7] - M[12] * M[3] * M[5];
  Inv[14] := -M[0] * M[5] * M[14] + M[0] * M[6] * M[13] + M[4] * M[1] * M[14] - M[4] * M[2] * M[13] - M[12] * M[1] * M[6] + M[12] * M[2] * M[5];
  Inv[3] := -M[1] * M[6] * M[11] + M[1] * M[7] * M[10] + M[5] * M[2] * M[11] - M[5] * M[3] * M[10] - M[9] * M[2] * M[7] + M[9] * M[3] * M[6];
  Inv[7] := M[0] * M[6] * M[11] - M[0] * M[7] * M[10] - M[4] * M[2] * M[11] + M[4] * M[3] * M[10] + M[8] * M[2] * M[7] - M[8] * M[3] * M[6];
  Inv[11] := -M[0] * M[5] * M[11] + M[0] * M[7] * M[9] + M[4] * M[1] * M[11] - M[4] * M[3] * M[9] - M[8] * M[1] * M[7] + M[8] * M[3] * M[5];
  Inv[15] := M[0] * M[5] * M[10] - M[0] * M[6] * M[9] - M[4] * M[1] * M[10] + M[4] * M[2] * M[9] + M[8] * M[1] * M[6] - M[8] * M[2] * M[5];
  Det := M[0] * Inv[0] + M[1] * Inv[4] + M[2] * Inv[8] + M[3] * Inv[12];
  if Abs(Det) < 1e-300 then
  begin
    Result := Mat4Identity;
    Exit;
  end;
  Det := 1.0 / Det;
  for I := 0 to 15 do
    Result.M[I] := Inv[I] * Det;
end;

function Mat4ToF(const A: TMat4): TMat4F;
var
  I: Integer;
begin
  for I := 0 to 15 do
    Result[I] := A.M[I];
end;

end.
