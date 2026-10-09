{ GameBody - движение тела (игрока и врагов) по уровню.
  Тело - вертикальная капсула. Столкновения считаются через GJK/EPA движка (EngConvex.CollideConvex).
  Поддерживаются: разрешение проникновений по нескольким итерациям, пробы у поверхности
  (пол, стена) и подъём на уступы до BODY_STEP_UP. Классов нет. }
unit GameBody;

{$mode objfpc}{$H+}

interface

uses
  Math, EngMath, EngConvex, GameLevel;

const
  BODY_RADIUS = 0.35;
  BODY_HALF_SEG = 0.50;      { капсула: высота 2*(0.35 + 0.50) = 1.7 м }
  BODY_FEET = 0.85;          { расстояние от центра капсулы до подошв }
  BODY_STEP_UP = 0.45;       { высота уступа, который тело проходит без прыжка }
  BODY_SKIN = 0.06;          { дальность проб у поверхности, м }

type
  TBodyTouch = record
    Hit: Boolean;
    Normal: TVec3;           { нормаль поверхности, направлена от неё к телу }
    Box: Integer;
  end;

{ Поворот угла к цели по кратчайшей дуге с ограничением шага (рад). }
function AngleApproach(Cur, Target, MaxStep: Double): Double;
{ Горизонтальная скорость к Target с ограничением ускорения Rate (м/с^2). }
procedure AccelHoriz(var V: TVec3; const Target: TVec3; Rate, Dt: Double);

{ Есть ли пересечение капсулы в позиции Center с какой-либо коробкой. }
function BodyOverlapAny(const L: TLevel; const Center: TVec3): Boolean;
{ Перемещение на Vel*Dt с разрешением столкновений. Скорость гасится о поверхности.
  Ground - касание пола (нормаль вверх), Wall - касание стены (почти горизонтальная нормаль). }
procedure BodyMove(var Center, Vel: TVec3; const L: TLevel; Dt: Double;
                   out Ground, Wall: TBodyTouch);
{ Проба: есть ли касание, если тело сместить на Dist вдоль Dir. Нормаль - от коробки к телу. }
function BodyProbe(const L: TLevel; const Center, Dir: TVec3; Dist: Double;
                   out Touch: TBodyTouch): Boolean;

implementation

var
  GCapsule: TConvexShape;

{ Поворот угла к цели по кратчайшей дуге с ограничением шага. }
function AngleApproach(Cur, Target, MaxStep: Double): Double;
var
  D: Double;
begin
  D := Target - Cur;
  while D > Pi do D := D - 2.0 * Pi;
  while D < -Pi do D := D + 2.0 * Pi;
  if Abs(D) <= MaxStep then
    Result := Target
  else if D > 0.0 then
    Result := Cur + MaxStep
  else
    Result := Cur - MaxStep;
end;

{ Горизонтальная скорость к Target с ограничением ускорения Rate. }
procedure AccelHoriz(var V: TVec3; const Target: TVec3; Rate, Dt: Double);
var
  Dv: TVec3;
  Len, Lim: Double;
begin
  Dv := V3(Target.X - V.X, 0.0, Target.Z - V.Z);
  Len := V3Length(Dv);
  Lim := Rate * Dt;
  if Len > Lim then
    Dv := V3Mul(Dv, Lim / Len);
  V.X := V.X + Dv.X;
  V.Z := V.Z + Dv.Z;
end;

procedure InitTouch(out T: TBodyTouch);
begin
  T.Hit := False;
  T.Normal := V3(0, 1, 0);
  T.Box := -1;
end;

procedure SetTouch(var T: TBodyTouch; const N: TVec3; I: Integer);
begin
  T.Hit := True;
  T.Normal := N;
  T.Box := I;
end;

{ Может ли капсула с центром P задеть коробку I. Сначала грубый отсев по описанной сфере, затем
  расстояние от трёх точек оси капсулы до коробки в её локальной системе (точная проверка с запасом
  0.3 м: ошибка выборки оси не больше четверти её длины). Сфера для большого пола не отсекает
  ничего, поэтому без второй проверки пол проверялся бы GJK/EPA при каждом шаге. }
function Candidate(const L: TLevel; const P: TVec3; I: Integer): Boolean;
var
  K: Integer;
  Pc, Lp: TVec3;
  Dx, Dy, Dz, D2, Best: Double;
  B: TLevelBox;
begin
  Result := False;
  B := L.Boxes[I];
  if V3Distance(P, B.Center) > B.Radius + BODY_RADIUS + BODY_HALF_SEG + 0.02 then Exit;
  Best := 1.0e30;
  for K := 0 to 2 do
  begin
    Pc := V3(P.X, P.Y - BODY_HALF_SEG + K * BODY_HALF_SEG, P.Z);
    Lp := QuatInvRotate(B.Rot, V3Sub(Pc, B.Center));
    Dx := Max(0.0, Abs(Lp.X) - B.Half.X);
    Dy := Max(0.0, Abs(Lp.Y) - B.Half.Y);
    Dz := Max(0.0, Abs(Lp.Z) - B.Half.Z);
    D2 := Dx * Dx + Dy * Dy + Dz * Dz;
    if D2 < Best then Best := D2;
  end;
  Result := Sqrt(Best) <= BODY_RADIUS + 0.3;
end;

{ Контакт капсулы с коробкой I: N - от коробки к капсуле, Depth > 0 при проникновении. }
function Collide(const L: TLevel; const Center: TVec3; I: Integer; out N: TVec3; out Depth: Double): Boolean;
var
  Pa, Pb: TPose;
  Sb: TConvexShape;
  C: TContact;
begin
  Pa.Pos := Center;
  Pa.Rot := QuatIdentity;
  Pb.Pos := L.Boxes[I].Center;
  Pb.Rot := L.Boxes[I].Rot;
  Sb := MakeBoxShape(L.Boxes[I].Half);
  Result := CollideConvex(GCapsule, Pa, Sb, Pb, C);
  N := C.Normal;
  Depth := C.Depth;
end;

function BodyOverlapAny(const L: TLevel; const Center: TVec3): Boolean;
var
  I: Integer;
  N: TVec3;
  D: Double;
begin
  Result := False;
  for I := 0 to L.Count - 1 do
    if Candidate(L, Center, I) and Collide(L, Center, I, N, D) and (D > 0.0) then
    begin
      Result := True;
      Exit;
    end;
end;

function BodyProbe(const L: TLevel; const Center, Dir: TVec3; Dist: Double;
                   out Touch: TBodyTouch): Boolean;
var
  P: TVec3;
  I: Integer;
  N: TVec3;
  D: Double;
begin
  InitTouch(Touch);
  P := V3MulAdd(Center, V3Normalize(Dir), Dist);
  for I := 0 to L.Count - 1 do
    if Candidate(L, P, I) and Collide(L, P, I, N, D) and (D > 0.0) then
    begin
      SetTouch(Touch, N, I);
      Result := True;
      Exit;
    end;
  Result := False;
end;

{ Подъём на уступ: тело поднимается на BODY_STEP_UP, проходит горизонтально к Desired и опускается,
  пока не коснётся поверхности. Успех, если путь свободен и на конечной точке есть опора. }
function TryStep(const L: TLevel; const Start, Desired: TVec3; out Dst: TVec3): Boolean;
var
  Up, Fwd, Test, Pos: TVec3;
  K: Integer;
  Tc: TBodyTouch;
  Found: Boolean;
begin
  Result := False;
  Up := V3(Start.X, Start.Y + BODY_STEP_UP, Start.Z);
  if BodyOverlapAny(L, Up) then Exit;
  Fwd := V3(Desired.X, Start.Y + BODY_STEP_UP, Desired.Z);
  if BodyOverlapAny(L, Fwd) then Exit;
  Found := False;
  Pos := Fwd;
  for K := 1 to 14 do
  begin
    Test := V3(Fwd.X, Fwd.Y - K * 0.05, Fwd.Z);
    if BodyOverlapAny(L, Test) then
    begin
      Pos := V3(Fwd.X, Fwd.Y - (K - 1) * 0.05, Fwd.Z);
      Found := True;
      Break;
    end;
  end;
  if not Found then Exit;
  if not BodyProbe(L, Pos, V3(0, -1, 0), BODY_SKIN, Tc) then Exit;
  if Tc.Normal.Y < 0.5 then Exit;
  Dst := Pos;
  Result := True;
end;

procedure BodyMove(var Center, Vel: TVec3; const L: TLevel; Dt: Double;
                   out Ground, Wall: TBodyTouch);
var
  Steps, S, It, I: Integer;
  H, D: Double;
  N: TVec3;
  Found, WallNow, WasGround: Boolean;
  Start, Desired, Stepped: TVec3;
  Tp: TBodyTouch;
begin
  InitTouch(Ground);
  InitTouch(Wall);
  WasGround := BodyProbe(L, Center, V3(0, -1, 0), BODY_SKIN, Tp) and (Tp.Normal.Y > 0.5);
  Steps := Trunc(V3Length(Vel) * Dt / 0.07) + 1;
  if Steps > 12 then Steps := 12;
  H := Dt / Steps;
  for S := 1 to Steps do
  begin
    Start := Center;
    Desired := V3MulAdd(Center, Vel, H);
    Center := Desired;
    WallNow := False;
    for It := 1 to 4 do
    begin
      Found := False;
      for I := 0 to L.Count - 1 do
      begin
        if not Candidate(L, Center, I) then Continue;
        if not Collide(L, Center, I, N, D) then Continue;
        if D <= 0.0 then Continue;
        Center := V3MulAdd(Center, N, D + 0.0005);
        Vel := V3Sub(Vel, V3Mul(N, MinD(0.0, V3Dot(Vel, N))));
        Found := True;
        if N.Y > 0.5 then
          SetTouch(Ground, N, I)
        else if N.Y > -0.5 then
        begin
          SetTouch(Wall, N, I);
          WallNow := True;
        end;
      end;
      if not Found then Break;
    end;
    { Горизонтальное движение заблокировано стеной у пола: пробуем уступ. }
    if WallNow and WasGround then
    begin
      Desired := V3(Desired.X, Center.Y, Desired.Z);
      if V3Length(V3(Desired.X - Center.X, 0, Desired.Z - Center.Z)) > 0.02 then
        if TryStep(L, Start, Desired, Stepped) then
        begin
          Center := Stepped;
          Ground.Hit := True;
          Ground.Normal := V3(0, 1, 0);
        end;
    end;
  end;
  if not Ground.Hit then
    if BodyProbe(L, Center, V3(0, -1, 0), BODY_SKIN, Tp) and (Tp.Normal.Y > 0.5) then
      Ground := Tp;
end;

initialization
  GCapsule := MakeCapsuleShape(BODY_RADIUS, BODY_HALF_SEG);

end.
