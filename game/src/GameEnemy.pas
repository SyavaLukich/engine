{ GameEnemy - ИИ противников.
  Восприятие: дальность, поле зрения и проверка линии видимости лучом по уровню.
  Память: после появления в поле зрения враг помнит позицию игрока EN_MEMORY секунд.
  Состояния: патруль (по пути A* между двумя точками), тревога (поворот к источнику), погода
  (погоня по пути A*), замах ближнего удара, нокдаун (сбит с ног), смерть. Турель стоит на месте
  и стреляет. Классов нет. }
unit GameEnemy;

{$mode objfpc}{$H+}

interface

uses
  Math, EngMath, GameLevel, GameBody, GameNav, GamePlayer;

const
  EN_GRUNT = 0;
  EN_TURRET = 1;

  ES_PATROL = 0;
  ES_ALERT = 1;
  ES_CHASE = 2;
  ES_WINDUP = 3;
  ES_KNOCK = 4;
  ES_DEAD = 5;

  EN_HEALTH_GRUNT = 100.0;
  EN_HEALTH_TURRET = 80.0;
  EN_SIGHT = 26.0;           { дальность зрения, м }
  EN_FOV_COS = 0.42;         { cos(65 градусов): поле зрения 130 градусов }
  EN_PATROL_SPEED = 2.2;     { м/с }
  EN_CHASE_SPEED = 5.2;
  EN_MELEE_RANGE = 1.8;      { м }
  EN_SHOT_MIN = 4.5;
  EN_SHOT_MAX = 24.0;
  EN_SHOT_COOLDOWN = 1.2;    { с }
  EN_SHOT_DAMAGE = 7.0;
  EN_SHOT_SPREAD = 0.09;     { разброс выстрела, рад }
  EN_MELEE_DAMAGE = 12.0;
  EN_WINDUP_TIME = 0.6;      { с замаха перед ударом: игрок успевает уйти }
  EN_KNOCK_TIME = 1.2;       { с лежания после нокдауна }
  EN_KNOCK_UP = 3.5;         { м/с вверх при нокдауне }
  EN_ALERT_TIME = 0.5;
  EN_MEMORY = 4.0;           { с, сколько помнится последняя позиция игрока }
  EN_TURRET_RANGE = 30.0;
  EN_TURRET_COOLDOWN = 1.4;
  EN_TURRET_SPREAD = 0.02;

type
  TEnemy = record
    Kind: Integer;
    Center: TVec3;
    Vel: TVec3;
    Yaw: Double;
    State: Integer;
    StateTime: Double;
    Health: Double;
    Alive: Boolean;
    PatrolA: TVec3;
    PatrolB: TVec3;
    Goal: TVec3;
    Path: TNavPath;
    RepathTime: Double;
    SeenPos: TVec3;
    SeenTime: Double;
    ShotCooldown: Double;
    MeleeCooldown: Double;
    KickId: Integer;         { последний удар ногой, которым враг уже задет }
    Seed: LongWord;
    StuckTime: Double;
    Frozen: Boolean;         { тесты: ИИ отключён, столкновения работают }
    Sees: Boolean;           { видит игрока в последнем шаге }
    Shots: Integer;
  end;

procedure EnemyInit(var E: TEnemy; Kind: Integer; const Pos, PatrolA, PatrolB: TVec3; Seed: LongWord);
function EnemyEye(const E: TEnemy): TVec3;
{ Попадание: урон, и при Knock > 0 - нокдаун (только пехота). }
procedure EnemyHit(var E: TEnemy; Damage: Double; const From: TVec3; Knock: Double);
{ Расстояние до попадания луча (O, D единичный) в сферы тела врага, или -1. }
function EnemyRayHit(const E: TEnemy; const O, D: TVec3; MaxT: Double): Double;
function EnemySees(const E: TEnemy; const L: TLevel; const P: TPlayer): Boolean;
{ Шаг ИИ. Возвращает True, если враг выстрелил: ShotFrom - ствол, ShotTo - точка попадания. }
function EnemyStep(var E: TEnemy; const L: TLevel; var G: TNavGrid; var P: TPlayer; Dt: Double;
                   out ShotFrom, ShotTo: TVec3): Boolean;

implementation

function NextRand(var S: LongWord): Double;
begin
  S := S * 1664525 + 1013904223;
  Result := ((S shr 8) / 16777216.0) * 2.0 - 1.0;
end;

function EnemyEye(const E: TEnemy): TVec3;
begin
  Result := V3(E.Center.X, E.Center.Y + 0.5, E.Center.Z);
end;

procedure EnemyInit(var E: TEnemy; Kind: Integer; const Pos, PatrolA, PatrolB: TVec3; Seed: LongWord);
begin
  E.Kind := Kind;
  E.Center := V3(Pos.X, Pos.Y + BODY_FEET, Pos.Z);
  E.Vel := V3Zero;
  E.PatrolA := PatrolA;
  E.PatrolB := PatrolB;
  E.Goal := PatrolB;
  E.Yaw := ArcTan2(PatrolB.X - PatrolA.X, PatrolB.Z - PatrolA.Z);
  if Kind = EN_TURRET then
    E.Health := EN_HEALTH_TURRET
  else
    E.Health := EN_HEALTH_GRUNT;
  E.Alive := True;
  if Kind = EN_TURRET then
    E.State := ES_CHASE
  else
    E.State := ES_PATROL;
  E.StateTime := 0.0;
  E.RepathTime := 0.0;
  E.SeenPos := E.Center;
  E.SeenTime := 0.0;
  E.ShotCooldown := 0.5;
  E.MeleeCooldown := 0.0;
  E.KickId := -1;
  E.Seed := Seed;
  E.StuckTime := 0.0;
  E.Frozen := False;
  E.Sees := False;
  E.Shots := 0;
  SetLength(E.Path.Points, 0);
  E.Path.Count := 0;
  E.Path.Index := 0;
end;

procedure EnemyHit(var E: TEnemy; Damage: Double; const From: TVec3; Knock: Double);
var
  D: TVec3;
begin
  if E.State = ES_DEAD then Exit;
  E.Health := E.Health - Damage;
  E.SeenPos := From;
  E.SeenTime := EN_MEMORY;
  if E.Health <= 0.0 then
  begin
    E.Health := 0.0;
    E.State := ES_DEAD;
    E.Alive := False;
    E.Vel := V3Zero;
    Exit;
  end;
  if (E.Kind = EN_GRUNT) and (Knock > 0.0) then
  begin
    D := V3(E.Center.X - From.X, 0.0, E.Center.Z - From.Z);
    if V3Length(D) < 1.0e-6 then
      D := V3(0.0, 0.0, 1.0)
    else
      D := V3Normalize(D);
    E.Vel := V3(D.X * Knock, EN_KNOCK_UP, D.Z * Knock);
    E.State := ES_KNOCK;
    E.StateTime := 0.0;
  end;
end;

{ Пересечение луча со сферой: расстояние до первого попадания, или -1. }
function RaySphere(const O, D, C: TVec3; R, MaxT: Double): Double;
var
  OC: TVec3;
  B, Cc, Disc, T: Double;
begin
  Result := -1.0;
  OC := V3Sub(O, C);
  B := V3Dot(OC, D);
  Cc := V3Dot(OC, OC) - R * R;
  Disc := B * B - Cc;
  if Disc < 0.0 then Exit;
  T := -B - Sqrt(Disc);
  if T < 0.0 then T := -B + Sqrt(Disc);
  if (T >= 0.0) and (T <= MaxT) then Result := T;
end;

function EnemyRayHit(const E: TEnemy; const O, D: TVec3; MaxT: Double): Double;
var
  T1, T2: Double;
begin
  Result := -1.0;
  if E.State = ES_DEAD then Exit;
  T1 := RaySphere(O, D, V3(E.Center.X, E.Center.Y + 0.1, E.Center.Z), 0.42, MaxT);
  T2 := RaySphere(O, D, V3(E.Center.X, E.Center.Y + 0.55, E.Center.Z), 0.26, MaxT);
  if (T1 >= 0.0) and ((T2 < 0.0) or (T1 < T2)) then
    Result := T1
  else
    Result := T2;
end;

function EnemySees(const E: TEnemy; const L: TLevel; const P: TPlayer): Boolean;
var
  Eye, Tgt, Dv, Dir, Fwd, Hz: TVec3;
  Dist: Double;
  Hit: TRayHit;
begin
  Result := False;
  if P.State = PS_DEAD then Exit;
  Eye := EnemyEye(E);
  Tgt := PlayerEye(P);
  Dv := V3Sub(Tgt, Eye);
  Dist := V3Length(Dv);
  if (Dist > EN_SIGHT) or (Dist < 1.0e-6) then Exit;
  Dir := V3Mul(Dv, 1.0 / Dist);
  if E.Kind = EN_GRUNT then
  begin
    Fwd := V3(Sin(E.Yaw), 0.0, Cos(E.Yaw));
    Hz := V3(Dir.X, 0.0, Dir.Z);
    if (Dist > 3.0) and (V3Length(Hz) > 1.0e-6) and (V3Dot(Fwd, V3Normalize(Hz)) < EN_FOV_COS) then Exit;
  end;
  Hit := LevelRayCast(L, Eye, Dir, Dist);
  if Hit.Hit and (Hit.T < Dist - 0.05) then Exit;
  Result := True;
end;

{ Выстрел по игроку с разбросом. Попадание - если луч проходит в 0.45 м от центра игрока
  и путь не перекрыт. }
function FireAt(var E: TEnemy; const L: TLevel; var P: TPlayer; Spread: Double;
                out ShotFrom, ShotTo: TVec3): Boolean;
var
  Eye, Tgt, Dv, Dir: TVec3;
  Dist, T, Perp: Double;
  Ray: TRayHit;
  Hit: Boolean;
begin
  Eye := EnemyEye(E);
  Tgt := PlayerEye(P);
  Dv := V3Sub(Tgt, Eye);
  Dist := V3Length(Dv);
  if Dist < 1.0e-6 then Dist := 1.0e-6;
  Dir := V3Mul(Dv, 1.0 / Dist);
  Dir := V3Normalize(V3(Dir.X + NextRand(E.Seed) * Spread, Dir.Y + NextRand(E.Seed) * Spread,
                        Dir.Z + NextRand(E.Seed) * Spread));
  Ray := LevelRayCast(L, Eye, Dir, 60.0);
  T := V3Dot(V3Sub(Tgt, Eye), Dir);
  Perp := V3Length(V3Sub(V3Sub(Tgt, Eye), V3Mul(Dir, T)));
  Hit := (P.State <> PS_DEAD) and (T > 0.0) and (Perp < 0.45) and ((not Ray.Hit) or (Ray.T > T));
  ShotFrom := Eye;
  if Hit then
  begin
    ShotTo := V3MulAdd(Eye, Dir, T);
    PlayerHurt(P, EN_SHOT_DAMAGE, E.Center);
  end
  else if Ray.Hit then
    ShotTo := Ray.Point
  else
    ShotTo := V3MulAdd(Eye, Dir, 60.0);
  Inc(E.Shots);
  Result := True;
end;

{ Движение к Target по пути A*. Путь пересчитывается раз в 0.6 с. }
procedure FollowTarget(var E: TEnemy; const L: TLevel; var G: TNavGrid; const Target: TVec3;
                       Speed, Dt: Double);
var
  Wp, Dv, Want: TVec3;
  Dist: Double;
begin
  E.RepathTime := E.RepathTime - Dt;
  if E.RepathTime <= 0.0 then
  begin
    if not NavFindPath(G, E.Center, Target, E.Path) then
      E.Path.Count := 0;
    E.RepathTime := 0.6;
  end;
  Wp := Target;
  if E.Path.Count > 0 then
  begin
    while (E.Path.Index < E.Path.Count - 1) and
          (V3Length(V3(E.Path.Points[E.Path.Index].X - E.Center.X, 0.0,
                       E.Path.Points[E.Path.Index].Z - E.Center.Z)) < 0.5) do
      Inc(E.Path.Index);
    Wp := E.Path.Points[E.Path.Index];
  end;
  Dv := V3(Wp.X - E.Center.X, 0.0, Wp.Z - E.Center.Z);
  Dist := V3Length(Dv);
  if Dist > 1.0e-4 then
  begin
    Want := V3Mul(V3Normalize(Dv), Speed);
    E.Yaw := ArcTan2(Dv.X, Dv.Z);
  end
  else
    Want := V3Zero;
  if E.Vel.X < Want.X then E.Vel.X := Min(Want.X, E.Vel.X + 20.0 * Dt) else E.Vel.X := Max(Want.X, E.Vel.X - 20.0 * Dt);
  if E.Vel.Z < Want.Z then E.Vel.Z := Min(Want.Z, E.Vel.Z + 20.0 * Dt) else E.Vel.Z := Max(Want.Z, E.Vel.Z - 20.0 * Dt);
end;

procedure FaceTo(var E: TEnemy; const Target: TVec3; Rate, Dt: Double);
var
  Dv: TVec3;
  Want: Double;
  D: Double;
begin
  Dv := V3(Target.X - E.Center.X, 0.0, Target.Z - E.Center.Z);
  if V3Length(Dv) < 1.0e-6 then Exit;
  Want := ArcTan2(Dv.X, Dv.Z);
  D := Want - E.Yaw;
  while D > Pi do D := D - 2.0 * Pi;
  while D < -Pi do D := D + 2.0 * Pi;
  if Abs(D) <= Rate * Dt then
    E.Yaw := Want
  else if D > 0.0 then
    E.Yaw := E.Yaw + Rate * Dt
  else
    E.Yaw := E.Yaw - Rate * Dt;
end;

function EnemyStep(var E: TEnemy; const L: TLevel; var G: TNavGrid; var P: TPlayer; Dt: Double;
                   out ShotFrom, ShotTo: TVec3): Boolean;
var
  Sees: Boolean;
  Dv, Eye: TVec3;
  Dist: Double;
  Ground, Wall: TBodyTouch;
  Moved: Double;
  Prev: TVec3;
begin
  Result := False;
  ShotFrom := E.Center;
  ShotTo := E.Center;
  if E.State = ES_DEAD then Exit;
  E.StateTime := E.StateTime + Dt;
  E.ShotCooldown := E.ShotCooldown - Dt;
  E.MeleeCooldown := E.MeleeCooldown - Dt;
  E.SeenTime := E.SeenTime - Dt;
  if E.Frozen then
  begin
    E.Vel := V3Zero;
    E.Vel.Y := -4.0;
    BodyMove(E.Center, E.Vel, L, Dt, Ground, Wall);
    E.Vel := V3Zero;
    Exit;
  end;
  Sees := EnemySees(E, L, P);
  E.Sees := Sees;
  if Sees then
  begin
    E.SeenPos := P.Center;
    E.SeenTime := EN_MEMORY;
  end;
  Eye := EnemyEye(E);
  Dv := V3Sub(PlayerEye(P), Eye);
  Dist := V3Length(Dv);

  if E.Kind = EN_TURRET then
  begin
    if Sees then
    begin
      E.Yaw := AngleApproach(E.Yaw, ArcTan2(Dv.X, Dv.Z), 3.0 * Dt);
      if (E.ShotCooldown <= 0.0) and (Dist <= EN_TURRET_RANGE) then
      begin
        Result := FireAt(E, L, P, EN_TURRET_SPREAD, ShotFrom, ShotTo);
        E.ShotCooldown := EN_TURRET_COOLDOWN;
      end;
    end;
    E.Vel := V3Zero;
    Exit;
  end;

  case E.State of
    ES_KNOCK:
      begin
        AccelHoriz(E.Vel, V3Zero, 6.0, Dt);
        E.Vel.Y := MaxD(E.Vel.Y - PL_GRAVITY * Dt, -40.0);
        BodyMove(E.Center, E.Vel, L, Dt, Ground, Wall);
        if Ground.Hit then E.Vel.Y := 0.0;
        if (E.StateTime >= EN_KNOCK_TIME) and Ground.Hit then
        begin
          E.State := ES_ALERT;
          E.StateTime := 0.0;
        end;
        Exit;
      end;
    ES_PATROL:
      begin
        if Sees then
        begin
          E.State := ES_ALERT;
          E.StateTime := 0.0;
          E.Vel := V3Zero;
        end
        else
        begin
          if V3Length(V3(E.Goal.X - E.Center.X, 0.0, E.Goal.Z - E.Center.Z)) < 1.0 then
          begin
            if (E.Goal.X = E.PatrolB.X) and (E.Goal.Z = E.PatrolB.Z) then
              E.Goal := E.PatrolA
            else
              E.Goal := E.PatrolB;
            E.RepathTime := 0.0;
          end;
          FollowTarget(E, L, G, E.Goal, EN_PATROL_SPEED, Dt);
        end;
      end;
    ES_ALERT:
      begin
        FaceTo(E, E.SeenPos, 4.0, Dt);
        AccelHoriz(E.Vel, V3Zero, 20.0, Dt);
        if E.StateTime >= EN_ALERT_TIME then
        begin
          E.StateTime := 0.0;
          if E.SeenTime > 0.0 then
            E.State := ES_CHASE
          else
            E.State := ES_PATROL;
        end;
      end;
    ES_CHASE:
      begin
        if E.SeenTime <= 0.0 then
        begin
          E.State := ES_PATROL;
          E.StateTime := 0.0;
          E.RepathTime := 0.0;
        end
        else if (E.MeleeCooldown <= 0.0) and Sees and
                (V3Length(V3(Dv.X, 0.0, Dv.Z)) <= EN_MELEE_RANGE) then
        begin
          E.State := ES_WINDUP;
          E.StateTime := 0.0;
          E.Vel := V3Zero;
        end
        else if Sees and (E.ShotCooldown <= 0.0) and (Dist >= EN_SHOT_MIN) and (Dist <= EN_SHOT_MAX) then
        begin
          Result := FireAt(E, L, P, EN_SHOT_SPREAD, ShotFrom, ShotTo);
          E.ShotCooldown := EN_SHOT_COOLDOWN;
          E.Vel := V3Zero;
          FaceTo(E, P.Center, 6.0, Dt);
        end
        else if Sees then
          FollowTarget(E, L, G, P.Center, EN_CHASE_SPEED, Dt)
        else
          FollowTarget(E, L, G, E.SeenPos, EN_CHASE_SPEED, Dt);
      end;
    ES_WINDUP:
      begin
        E.Vel := V3Zero;
        FaceTo(E, P.Center, 8.0, Dt);
        if E.StateTime >= EN_WINDUP_TIME then
        begin
          E.MeleeCooldown := 1.4;
          E.State := ES_CHASE;
          E.StateTime := 0.0;
          if (P.State <> PS_DEAD) and (V3Length(V3(Dv.X, 0.0, Dv.Z)) <= EN_MELEE_RANGE + 0.5) then
            PlayerHurt(P, EN_MELEE_DAMAGE, E.Center);
        end;
      end;
  end;

  { Пехота без прыжков: прижимается к полу, гравитация учтена стабильно. }
  E.Vel.Y := -4.0;
  Prev := E.Center;
  BodyMove(E.Center, E.Vel, L, Dt, Ground, Wall);
  E.Vel.Y := 0.0;
  Moved := V3Length(V3(E.Center.X - Prev.X, 0.0, E.Center.Z - Prev.Z));
  if (E.State = ES_PATROL) or (E.State = ES_CHASE) then
  begin
    if Moved < 0.2 * Dt then
    begin
      E.StuckTime := E.StuckTime + Dt;
      if E.StuckTime > 1.5 then
      begin
        E.StuckTime := 0.0;
        E.RepathTime := 0.0;
      end;
    end
    else
      E.StuckTime := 0.0;
  end;
end;

end.
