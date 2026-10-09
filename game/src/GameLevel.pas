{ GameLevel - данные уровня: коробки (статические коллайдеры), точки появления и луч по коробкам.
  Модуль не знает об игроке, врагах и рендерере. Классов нет. }
unit GameLevel;

{$mode objfpc}{$H+}

interface

uses
  Math, EngMath, EngConvex;

const
  LVL_KIND_SOLID = 0;      { блок: пол, стены, платформы, ящики }
  LVL_KIND_RAIL = 1;       { перила: по верху можно бежать }

type
  TLevelBox = record
    Center: TVec3;
    Half: TVec3;             { полуразмеры в локальной системе коробки }
    Rot: TQuat;              { поворот (наклонные рампы) }
    Kind: Integer;           { LVL_KIND_* }
    Color: TVec3;
    Radius: Double;          { радиус описанной сферы, для отсечения кандидатов }
  end;

  TLevel = record
    Boxes: array of TLevelBox;
    Count: Integer;
    Lo: TVec3;               { границы арены (для навигации) }
    Hi: TVec3;
  end;

  TRayHit = record
    Hit: Boolean;
    T: Double;               { расстояние вдоль луча, м }
    Point: TVec3;
    Normal: TVec3;           { наружная нормаль грани }
    Box: Integer;
  end;

  TEnemySpawn = record
    Kind: Integer;           { EN_GRUNT или EN_TURRET (см. GameEnemy) }
    Pos: TVec3;              { положение подошв }
    PatrolA: TVec3;
    PatrolB: TVec3;
  end;

  TLevelInfo = record
    PlayerSpawn: TVec3;
    Enemies: array of TEnemySpawn;
    EnemyCount: Integer;
  end;

procedure LevelInit(var L: TLevel);
function LevelAddBox(var L: TLevel; const Center, Half: TVec3; const Rot: TQuat;
                     Kind: Integer; const Color: TVec3): Integer;
{ Ближайшее пересечение луча с коробками на расстоянии не больше MaxT. Dir не обязан быть единичным. }
function LevelRayCast(const L: TLevel; const Origin, Dir: TVec3; MaxT: Double): TRayHit;
procedure LevelAddEnemy(var Info: TLevelInfo; Kind: Integer; const Pos, PatrolA, PatrolB: TVec3);

implementation

procedure LevelInit(var L: TLevel);
begin
  L.Count := 0;
  SetLength(L.Boxes, 0);
  L.Lo := V3(0, 0, 0);
  L.Hi := V3(0, 0, 0);
end;

function LevelAddBox(var L: TLevel; const Center, Half: TVec3; const Rot: TQuat;
                     Kind: Integer; const Color: TVec3): Integer;
begin
  if L.Count >= Length(L.Boxes) then
    SetLength(L.Boxes, Length(L.Boxes) * 2 + 16);
  L.Boxes[L.Count].Center := Center;
  L.Boxes[L.Count].Half := Half;
  L.Boxes[L.Count].Rot := Rot;
  L.Boxes[L.Count].Kind := Kind;
  L.Boxes[L.Count].Color := Color;
  L.Boxes[L.Count].Radius := V3Length(Half);
  Result := L.Count;
  Inc(L.Count);
end;

procedure LevelAddEnemy(var Info: TLevelInfo; Kind: Integer; const Pos, PatrolA, PatrolB: TVec3);
begin
  if Info.EnemyCount >= Length(Info.Enemies) then
    SetLength(Info.Enemies, Length(Info.Enemies) * 2 + 8);
  Info.Enemies[Info.EnemyCount].Kind := Kind;
  Info.Enemies[Info.EnemyCount].Pos := Pos;
  Info.Enemies[Info.EnemyCount].PatrolA := PatrolA;
  Info.Enemies[Info.EnemyCount].PatrolB := PatrolB;
  Inc(Info.EnemyCount);
end;

{ Пересечение луча с ориентированной коробкой: переход в локальную систему и тест по плитам (slab). }
function LevelRayCast(const L: TLevel; const Origin, Dir: TVec3; MaxT: Double): TRayHit;
var
  I, K, Axis, SignN: Integer;
  D0, Dl0: TVec3;
  Ol, Dl, Hl: array[0..2] of Double;
  TMin, TMax, T1, T2, Tmp, THit: Double;
  Ok: Boolean;
  Q: TQuat;
  Nl: TVec3;
  Dn: TVec3;
  Inside: Boolean;
begin
  Result.Hit := False;
  Result.T := MaxT;
  Result.Point := Origin;
  Result.Normal := V3(0, 1, 0);
  Result.Box := -1;
  Dn := V3Normalize(Dir);
  if V3Length(Dn) < 0.5 then Exit;
  for I := 0 to L.Count - 1 do
  begin
    { Отсечение по описанной сфере: отрезок луча длиной MaxT лежит внутри сферы радиуса MaxT от начала. }
    if V3Distance(Origin, L.Boxes[I].Center) > L.Boxes[I].Radius + MaxT then Continue;
    Q := L.Boxes[I].Rot;
    D0 := QuatInvRotate(Q, V3Sub(Origin, L.Boxes[I].Center));
    Dl0 := QuatInvRotate(Q, Dn);
    Ol[0] := D0.X;
    Ol[1] := D0.Y;
    Ol[2] := D0.Z;
    Dl[0] := Dl0.X;
    Dl[1] := Dl0.Y;
    Dl[2] := Dl0.Z;
    Hl[0] := L.Boxes[I].Half.X;
    Hl[1] := L.Boxes[I].Half.Y;
    Hl[2] := L.Boxes[I].Half.Z;
    TMin := -1.0e30;
    TMax := 1.0e30;
    Axis := -1;
    SignN := 0;
    Ok := True;
    for K := 0 to 2 do
    begin
      if Abs(Dl[K]) < 1.0e-12 then
      begin
        if (Ol[K] < -Hl[K]) or (Ol[K] > Hl[K]) then
        begin
          Ok := False;
          Break;
        end;
      end
      else
      begin
        T1 := (-Hl[K] - Ol[K]) / Dl[K];
        T2 := (Hl[K] - Ol[K]) / Dl[K];
        if T1 > T2 then
        begin
          Tmp := T1;
          T1 := T2;
          T2 := Tmp;
        end;
        if T1 > TMin then
        begin
          TMin := T1;
          Axis := K;
          if Dl[K] > 0.0 then SignN := -1 else SignN := 1;
        end;
        if T2 < TMax then TMax := T2;
        if TMin > TMax then
        begin
          Ok := False;
          Break;
        end;
      end;
    end;
    if (not Ok) or (TMax < 0.0) then Continue;
    Inside := Axis < 0;
    if Inside then
      THit := 0.0
    else
      THit := TMin;
    if THit > MaxT then Continue;
    if Result.Hit and (THit >= Result.T) then Continue;
    Result.Hit := True;
    Result.T := THit;
    Result.Point := V3MulAdd(Origin, Dn, THit);
    Result.Box := I;
    if Inside then
      Result.Normal := V3Neg(Dn)
    else
    begin
      Nl := V3(0, 0, 0);
      case Axis of
        0: Nl.X := SignN;
        1: Nl.Y := SignN;
      else
        Nl.Z := SignN;
      end;
      Result.Normal := QuatRotate(Q, Nl);
    end;
  end;
end;

end.
