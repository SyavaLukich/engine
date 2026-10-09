{ GamePlayer - контроллер игрока: конечный автомат движения в духе платформеров типа Super Mario 64.
  Состояния: земля, воздух, бег по стене, висение на уступе, подтягивание, перила, подкат,
  удар сверху, смерть. Приёмы: прыжки (одиночный, двойной, тройной), сальто назад, вперёд и вбок,
  отскок от стены при беге по стене, висение с выстрелом, бег по перилам, подкат с ударом,
  удар сверху с ударной волной. Стрельбу и удары разрешает мир (GameWorld); здесь выставляются
  флаги (FireRequest, KickTime, Landed). Классов нет. }
unit GamePlayer;

{$mode objfpc}{$H+}

interface

uses
  Math, EngMath, GameLevel, GameBody, GameInput;

const
  PL_GRAVITY = 24.0;            { м/с^2 }
  PL_MAX_FALL = 40.0;           { м/с }
  PL_RUN_SPEED = 9.0;           { м/с при полном отклонении стика }
  PL_GROUND_ACCEL = 45.0;       { м/с^2 }
  PL_FRICTION = 30.0;           { м/с^2 при отпущенном стике }
  PL_AIR_ACCEL = 12.0;
  PL_AIR_SPEED = 9.0;
  PL_JUMP_1 = 11.5;             { начальные вертикальные скорости прыжков, м/с }
  PL_JUMP_2 = 12.5;
  PL_JUMP_3 = 15.0;
  PL_CHAIN_WINDOW = 0.3;        { с после приземления, в которые прыжок продлевает цепочку }
  PL_BACKFLIP_UP = 14.5;
  PL_BACKFLIP_BACK = 4.0;
  PL_FRONTFLIP_UP = 12.0;
  PL_FRONTFLIP_FWD = 5.0;
  PL_SIDEFLIP_UP = 13.5;
  PL_SIDEFLIP_SIDE = 5.0;
  PL_FLIP_TIME = 0.85;          { с, за которое совершается сальто }
  PL_WALLRUN_TIME = 1.8;        { с, максимальная длительность бега по стене }
  PL_WALLRUN_GRAVITY = 0.25;    { доля силы тяжести во время бега по стене }
  PL_WALLRUN_SPEED = 9.0;
  PL_WALL_KICK_UP = 12.5;       { отскок от стены: вверх и от стены, м/с }
  PL_WALL_KICK_OUT = 7.5;
  PL_WALL_KICK_LOCK = 0.2;      { с без повторного захвата стены }
  PL_SLIDE_START = 6.0;         { минимальная скорость для подката, м/с }
  PL_SLIDE_SPEED = 14.0;
  PL_SLIDE_TIME = 0.9;
  PL_LONG_UP = 8.0;             { длинный прыжок из подката }
  PL_LONG_FWD = 12.0;
  PL_POUND_SPEED = 30.0;        { скорость падения при ударе сверху, м/с }
  PL_POUND_MIN = 0.12;          { с, минимальная длительность падения }
  PL_CLIMB_TIME = 0.45;         { с, подтягивание на уступ }
  PL_RAIL_SPEED = 9.0;
  PL_RAIL_ACCEL = 40.0;
  PL_SHOT_COOLDOWN = 0.22;      { с между выстрелами }
  PL_KICK_TIME = 0.25;          { с, окно активного удара ногой }
  PL_MAX_HEALTH = 100.0;
  PL_RESPAWN_TIME = 2.0;
  PL_LEDGE_MIN = 0.6;           { высота кромки над подошвами, допустимая для захвата, м }
  PL_LEDGE_MAX = 2.25;
  PL_LEDGE_HOLD = 0.25;         { на сколько подошвы висящего ниже кромки }

  PS_GROUND = 0;
  PS_AIR = 1;
  PS_WALLRUN = 2;
  PS_HANG = 3;
  PS_CLIMB = 4;
  PS_RAIL = 5;
  PS_SLIDE = 6;
  PS_POUND = 7;
  PS_DEAD = 8;

  FLIP_NONE = 0;
  FLIP_BACK = 1;
  FLIP_FRONT = 2;
  FLIP_SIDE = 3;

type
  TPlayerStats = record
    Jumps: Integer;
    DoubleJumps: Integer;
    TripleJumps: Integer;
    Backflips: Integer;
    Frontflips: Integer;
    Sideflips: Integer;
    WallRuns: Integer;
    WallKicks: Integer;
    Ledges: Integer;
    Rails: Integer;
    Slides: Integer;
    Pounds: Integer;
    LongJumps: Integer;
    Deaths: Integer;
  end;

  TPlayer = record
    Center: TVec3;           { центр капсулы }
    Vel: TVec3;
    Yaw: Double;             { направление лица, рад: вектор (sin Yaw, 0, cos Yaw) }
    State: Integer;          { PS_* }
    StateTime: Double;       { с в текущем состоянии }
    Grounded: Boolean;
    GroundBox: Integer;
    WallN: TVec3;            { нормаль стены при беге по стене (от стены к игроку) }
    JumpChain: Integer;      { номер прыжка в цепочке: 1..3 }
    SinceLanding: Double;    { с с последнего приземления }
    FlipKind: Integer;       { FLIP_* }
    FlipTime: Double;
    KickTime: Double;        { > 0 - удар ногой (или подкат) активен }
    KickId: Integer;         { номер удара: каждый удар бьёт каждого врага один раз }
    ShotCooldown: Double;
    Health: Double;
    HurtTime: Double;
    RespawnTime: Double;
    WallLock: Double;        { с без захвата стены }
    Spawn: TVec3;            { подошвы точки появления }
    RailAxis: Integer;       { 0 - перила вдоль X, 1 - вдоль Z }
    RailLine: Double;        { вторая координата линии перил }
    RailTop: Double;         { высота верха перил }
    RailLo: Double;          { пределы вдоль перил }
    RailHi: Double;
    LedgeCenter: TVec3;      { позиция висения }
    LedgeTop: Double;        { высота кромки уступа }
    ClimbFrom: TVec3;
    ClimbTo: TVec3;
    FireRequest: Boolean;    { выстрел разрешён в этом шаге (обрабатывает мир) }
    Landed: Boolean;         { приземление в этом шаге }
    LandFromPound: Boolean;  { приземление после удара сверху }
    LandPos: TVec3;
    Stats: TPlayerStats;
  end;

procedure PlayerInit(var P: TPlayer; const Spawn: TVec3);
procedure PlayerStep(var P: TPlayer; const L: TLevel; const Inp: TGameInput; Dt: Double);
{ Удар по игроку: урон, отбрасывание, смерть. From - точка источника удара. }
procedure PlayerHurt(var P: TPlayer; Damage: Double; const From: TVec3);
function PlayerEye(const P: TPlayer): TVec3;
function PlayerFacing(const P: TPlayer): TVec3;
{ Угол сальто (рад) для отрисовки: 0 вне сальто. }
function PlayerFlipAngle(const P: TPlayer): Double;
function HorizontalSpeed(const V: TVec3): Double;

implementation

function HorizontalSpeed(const V: TVec3): Double;
begin
  Result := Sqrt(V.X * V.X + V.Z * V.Z);
end;

function PlayerEye(const P: TPlayer): TVec3;
begin
  Result := V3(P.Center.X, P.Center.Y + 0.55, P.Center.Z);
end;

function PlayerFacing(const P: TPlayer): TVec3;
begin
  Result := V3(Sin(P.Yaw), 0.0, Cos(P.Yaw));
end;

function PlayerFlipAngle(const P: TPlayer): Double;
begin
  if P.FlipKind = FLIP_NONE then
    Result := 0.0
  else
    Result := 2.0 * Pi * Min(1.0, P.FlipTime / PL_FLIP_TIME);
end;

procedure PlayerInit(var P: TPlayer; const Spawn: TVec3);
begin
  FillChar(P, SizeOf(P), 0);
  P.Spawn := Spawn;
  P.Center := V3(Spawn.X, Spawn.Y + BODY_FEET, Spawn.Z);
  P.State := PS_AIR;
  P.GroundBox := -1;
  P.Health := PL_MAX_HEALTH;
  P.SinceLanding := 10.0;
  P.FlipKind := FLIP_NONE;
end;

procedure PlayerRespawn(var P: TPlayer);
begin
  P.Center := V3(P.Spawn.X, P.Spawn.Y + BODY_FEET, P.Spawn.Z);
  P.Vel := V3Zero;
  P.State := PS_AIR;
  P.StateTime := 0.0;
  P.Health := PL_MAX_HEALTH;
  P.FlipKind := FLIP_NONE;
  P.ShotCooldown := 0.0;
  P.KickTime := 0.0;
  P.WallLock := 0.0;
  P.Grounded := False;
end;

procedure PlayerHurt(var P: TPlayer; Damage: Double; const From: TVec3);
var
  D: TVec3;
begin
  if P.State = PS_DEAD then Exit;
  P.Health := P.Health - Damage;
  P.HurtTime := 0.5;
  if P.Health <= 0.0 then
  begin
    P.Health := 0.0;
    P.State := PS_DEAD;
    P.RespawnTime := PL_RESPAWN_TIME;
    P.Vel := V3Zero;
    Inc(P.Stats.Deaths);
    Exit;
  end;
  if (P.State = PS_GROUND) or (P.State = PS_AIR) or (P.State = PS_SLIDE) then
  begin
    D := V3(P.Center.X - From.X, 0.0, P.Center.Z - From.Z);
    if V3Length(D) < 1.0e-6 then
      D := V3(0.0, 0.0, 1.0)
    else
      D := V3Normalize(D);
    P.Vel := V3(P.Vel.X + D.X * 4.0, 3.0, P.Vel.Z + D.Z * 4.0);
    P.State := PS_AIR;
    P.StateTime := 0.0;
    P.Grounded := False;
  end;
end;

procedure Land(var P: TPlayer; const L: TLevel; Box: Integer; FromPound: Boolean);
begin
  P.State := PS_GROUND;
  P.StateTime := 0.0;
  P.Grounded := True;
  P.GroundBox := Box;
  P.FlipKind := FLIP_NONE;
  P.SinceLanding := 0.0;
  P.Vel.Y := 0.0;
  P.Landed := True;
  P.LandFromPound := FromPound;
  P.LandPos := P.Center;
end;

{ Вход на перила: вторая координата и пределы вдоль оси берутся из коробки перил. }
procedure EnterRail(var P: TPlayer; const L: TLevel; BoxIndex: Integer);
var
  B: TLevelBox;
begin
  B := L.Boxes[BoxIndex];
  if B.Half.X >= B.Half.Z then
  begin
    P.RailAxis := 0;
    P.RailLine := B.Center.Z;
    P.RailLo := B.Center.X - B.Half.X;
    P.RailHi := B.Center.X + B.Half.X;
  end
  else
  begin
    P.RailAxis := 1;
    P.RailLine := B.Center.X;
    P.RailLo := B.Center.Z - B.Half.Z;
    P.RailHi := B.Center.Z + B.Half.Z;
  end;
  P.RailTop := B.Center.Y + B.Half.Y;
  P.State := PS_RAIL;
  P.StateTime := 0.0;
  P.Grounded := True;
  P.GroundBox := BoxIndex;
  P.FlipKind := FLIP_NONE;
  P.Vel := V3Zero;
  if P.RailAxis = 0 then
  begin
    P.Center.X := ClampD(P.Center.X, P.RailLo, P.RailHi);
    P.Center.Z := P.RailLine;
  end
  else
  begin
    P.Center.Z := ClampD(P.Center.Z, P.RailLo, P.RailHi);
    P.Center.X := P.RailLine;
  end;
  P.Center.Y := P.RailTop + BODY_FEET;
  Inc(P.Stats.Rails);
end;

{ Захват перил в воздухе: тело падает на верх перил в пределах ширины перил. }
function TryRailGrab(var P: TPlayer; const L: TLevel): Boolean;
var
  I: Integer;
  B: TLevelBox;
  Feet, Top: Double;
begin
  Result := False;
  if P.WallLock > 0.0 then Exit;
  Feet := P.Center.Y - BODY_FEET;
  for I := 0 to L.Count - 1 do
  begin
    if L.Boxes[I].Kind <> LVL_KIND_RAIL then Continue;
    B := L.Boxes[I];
    Top := B.Center.Y + B.Half.Y;
    if (Feet < Top - 0.45) or (Feet > Top + 0.25) then Continue;
    if B.Half.X >= B.Half.Z then
    begin
      if (Abs(P.Center.Z - B.Center.Z) <= 0.45) and (Abs(P.Center.X - B.Center.X) <= B.Half.X) then
      begin
        EnterRail(P, L, I);
        Result := True;
        Exit;
      end;
    end
    else if (Abs(P.Center.X - B.Center.X) <= 0.45) and (Abs(P.Center.Z - B.Center.Z) <= B.Half.Z) then
    begin
      EnterRail(P, L, I);
      Result := True;
      Exit;
    end;
  end;
end;

{ Прыжок с земли: сальто при присаде, на бегу, в сторону, иначе цепочка обычных прыжков. }
procedure DoGroundJump(var P: TPlayer; const Inp: TGameInput);
var
  F, Side, Wish: TVec3;
  Sd: Double;
begin
  F := PlayerFacing(P);
  Side := V3(F.Z, 0.0, -F.X);
  Wish := V3(Inp.Move.X, 0.0, Inp.Move.Z);
  Sd := V3Dot(Wish, Side);
  if Inp.Crouch then
  begin
    P.Vel := V3(-F.X * PL_BACKFLIP_BACK, PL_BACKFLIP_UP, -F.Z * PL_BACKFLIP_BACK);
    P.FlipKind := FLIP_BACK;
    P.FlipTime := 0.0;
    Inc(P.Stats.Backflips);
    P.JumpChain := 0;
  end
  else if HorizontalSpeed(P.Vel) >= 6.0 then
  begin
    P.Vel := V3(F.X * PL_FRONTFLIP_FWD, PL_FRONTFLIP_UP, F.Z * PL_FRONTFLIP_FWD);
    P.FlipKind := FLIP_FRONT;
    P.FlipTime := 0.0;
    Inc(P.Stats.Frontflips);
    P.JumpChain := 0;
  end
  else if Abs(Sd) >= 0.5 then
  begin
    if Sd > 0.0 then
      P.Vel := V3(Side.X * PL_SIDEFLIP_SIDE, PL_SIDEFLIP_UP, Side.Z * PL_SIDEFLIP_SIDE)
    else
      P.Vel := V3(-Side.X * PL_SIDEFLIP_SIDE, PL_SIDEFLIP_UP, -Side.Z * PL_SIDEFLIP_SIDE);
    P.FlipKind := FLIP_SIDE;
    P.FlipTime := 0.0;
    Inc(P.Stats.Sideflips);
    P.JumpChain := 0;
  end
  else
  begin
    if P.SinceLanding <= PL_CHAIN_WINDOW then
      P.JumpChain := Min(3, P.JumpChain + 1)
    else
      P.JumpChain := 1;
    case P.JumpChain of
      1:
        begin
          P.Vel.Y := PL_JUMP_1;
          Inc(P.Stats.Jumps);
        end;
      2:
        begin
          P.Vel.Y := PL_JUMP_2;
          Inc(P.Stats.DoubleJumps);
        end;
    else
      P.Vel.Y := PL_JUMP_3;
      Inc(P.Stats.TripleJumps);
    end;
  end;
  P.Grounded := False;
  P.State := PS_AIR;
  P.StateTime := 0.0;
  P.Center.Y := P.Center.Y + 0.03;
end;

procedure StartSlide(var P: TPlayer);
var
  H: TVec3;
begin
  H := V3(P.Vel.X, 0.0, P.Vel.Z);
  if V3Length(H) < 1.0e-6 then H := PlayerFacing(P);
  H := V3Normalize(H);
  P.Vel := V3(H.X * PL_SLIDE_SPEED, 0.0, H.Z * PL_SLIDE_SPEED);
  P.State := PS_SLIDE;
  P.StateTime := 0.0;
  Inc(P.KickId);
  P.KickTime := PL_KICK_TIME;
  Inc(P.Stats.Slides);
end;

procedure StepGround(var P: TPlayer; const L: TLevel; const Inp: TGameInput; Dt: Double);
var
  Wish, Target: TVec3;
  Ground, Wall: TBodyTouch;
begin
  if Inp.Jump then
  begin
    DoGroundJump(P, Inp);
    Exit;
  end;
  if Inp.CrouchPressed and (HorizontalSpeed(P.Vel) > PL_SLIDE_START) then
  begin
    StartSlide(P);
    Exit;
  end;
  Wish := V3(Inp.Move.X, 0.0, Inp.Move.Z);
  if V3Length(Wish) > 1.0 then Wish := V3Normalize(Wish);
  Target := V3Mul(Wish, PL_RUN_SPEED);
  if V3Length(Wish) > 0.05 then
    AccelHoriz(P.Vel, Target, PL_GROUND_ACCEL, Dt)
  else
    AccelHoriz(P.Vel, V3Zero, PL_FRICTION, Dt);
  P.Vel.Y := -4.0;
  BodyMove(P.Center, P.Vel, L, Dt, Ground, Wall);
  if not Ground.Hit then
  begin
    P.State := PS_AIR;
    P.StateTime := 0.0;
    P.Grounded := False;
    P.Vel.Y := 0.0;
    Exit;
  end;
  P.Grounded := True;
  P.GroundBox := Ground.Box;
  P.Vel.Y := 0.0;
  if (L.Boxes[Ground.Box].Kind = LVL_KIND_RAIL) and (HorizontalSpeed(P.Vel) > 0.5) then
    EnterRail(P, L, Ground.Box);
end;

procedure EnterWallRun(var P: TPlayer; const N: TVec3);
begin
  P.State := PS_WALLRUN;
  P.StateTime := 0.0;
  P.WallN := V3Normalize(V3(N.X, 0.0, N.Z));
  P.FlipKind := FLIP_NONE;
  P.Grounded := False;
  Inc(P.Stats.WallRuns);
end;

procedure WallKick(var P: TPlayer);
begin
  P.Vel := V3(P.WallN.X * PL_WALL_KICK_OUT, PL_WALL_KICK_UP, P.WallN.Z * PL_WALL_KICK_OUT);
  P.Yaw := ArcTan2(P.WallN.X, P.WallN.Z);
  P.State := PS_AIR;
  P.StateTime := 0.0;
  P.WallLock := PL_WALL_KICK_LOCK;
  P.JumpChain := 0;
  P.Grounded := False;
  Inc(P.Stats.WallKicks);
end;

function TryLedge(var P: TPlayer; const L: TLevel): Boolean; forward;

procedure StepAir(var P: TPlayer; const L: TLevel; const Inp: TGameInput; Dt: Double);
var
  Wish: TVec3;
  Ground, Wall: TBodyTouch;
  Hs: Double;
begin
  Wish := V3(Inp.Move.X, 0.0, Inp.Move.Z);
  if V3Length(Wish) > 1.0 then Wish := V3Normalize(Wish);
  if Inp.Kick then
  begin
    P.KickTime := PL_KICK_TIME;
    Inc(P.KickId);
  end;
  if Inp.CrouchPressed and (P.StateTime > 0.12) then
  begin
    P.State := PS_POUND;
    P.StateTime := 0.0;
    P.Vel := V3(0.0, -PL_POUND_SPEED, 0.0);
    Exit;
  end;
  if (P.Vel.Y <= 0.5) and TryRailGrab(P, L) then Exit;
  AccelHoriz(P.Vel, V3Mul(Wish, PL_AIR_SPEED), PL_AIR_ACCEL, Dt);
  { Скорость до столкновения: BodyMove гасит скорость, направленную в стену. }
  Hs := HorizontalSpeed(P.Vel);
  P.Vel.Y := MaxD(P.Vel.Y - PL_GRAVITY * Dt, -PL_MAX_FALL);
  BodyMove(P.Center, P.Vel, L, Dt, Ground, Wall);
  if Ground.Hit then
  begin
    Land(P, L, Ground.Box, False);
    if (L.Boxes[Ground.Box].Kind = LVL_KIND_RAIL) and (HorizontalSpeed(P.Vel) > 0.5) then
      EnterRail(P, L, Ground.Box);
    Exit;
  end;
  if Wall.Hit and (P.WallLock <= 0.0) and (Abs(Wall.Normal.Y) < 0.3) and
     (Hs >= 3.0) and (V3Dot(Wish, Wall.Normal) < -0.3) then
  begin
    EnterWallRun(P, Wall.Normal);
    Exit;
  end;
  if (P.Vel.Y <= 9.0) and TryLedge(P, L) then
  begin
    P.State := PS_HANG;
    P.StateTime := 0.0;
    P.Vel := V3Zero;
    P.Center := P.LedgeCenter;
    P.FlipKind := FLIP_NONE;
    Inc(P.Stats.Ledges);
  end;
end;

procedure StepWallRun(var P: TPlayer; const L: TLevel; const Inp: TGameInput; Dt: Double);
var
  T, Wish, Dir, H: TVec3;
  Speed: Double;
  Ground, Wall, Tp: TBodyTouch;
begin
  if Inp.Jump then
  begin
    WallKick(P);
    Exit;
  end;
  if (not BodyProbe(L, P.Center, V3Neg(P.WallN), 0.08, Tp)) or (P.StateTime >= PL_WALLRUN_TIME) then
  begin
    P.State := PS_AIR;
    P.StateTime := 0.0;
    P.WallLock := 0.3;
    Exit;
  end;
  Wish := V3(Inp.Move.X, 0.0, Inp.Move.Z);
  if V3Dot(Wish, P.WallN) > 0.3 then
  begin
    P.State := PS_AIR;
    P.StateTime := 0.0;
    P.WallLock := 0.2;
    Exit;
  end;
  T := V3Normalize(V3Cross(V3(0.0, 1.0, 0.0), P.WallN));
  H := V3(P.Vel.X, 0.0, P.Vel.Z);
  Dir := T;
  if V3Length(Wish) > 0.1 then
  begin
    if V3Dot(Wish, T) < 0.0 then Dir := V3Neg(T);
  end
  else if V3Dot(H, T) < 0.0 then
    Dir := V3Neg(T);
  Speed := PL_WALLRUN_SPEED * (1.0 - 0.15 * Min(1.0, P.StateTime / PL_WALLRUN_TIME));
  P.Vel.X := Dir.X * Speed;
  P.Vel.Z := Dir.Z * Speed;
  P.Vel.Y := MaxD(P.Vel.Y - PL_GRAVITY * PL_WALLRUN_GRAVITY * Dt, -6.0);
  P.Yaw := ArcTan2(Dir.X, Dir.Z);
  BodyMove(P.Center, P.Vel, L, Dt, Ground, Wall);
  if Wall.Hit and (Abs(Wall.Normal.Y) < 0.3) then
    P.WallN := V3Normalize(V3(Wall.Normal.X, 0.0, Wall.Normal.Z));
  if Ground.Hit then
    Land(P, L, Ground.Box, False);
end;

{ Уступ перед лицом: вертикальная грань в пределах досягаемости, сверху ровная поверхность,
  тело помещается у грани без пересечений. }
function TryLedge(var P: TPlayer; const L: TLevel): Boolean;
var
  F, O, C: TVec3;
  Face, Top: TRayHit;
  Rise: Double;
begin
  Result := False;
  F := PlayerFacing(P);
  { Луч на высоте подошв + 0.5 м: грудь тела поднимается выше кромки раньше, чем нужно для захвата. }
  O := V3(P.Center.X, P.Center.Y - BODY_FEET + 0.5, P.Center.Z);
  Face := LevelRayCast(L, O, F, BODY_RADIUS + 0.35);
  if (not Face.Hit) or (Abs(Face.Normal.Y) > 0.3) or (V3Dot(Face.Normal, F) > -0.5) then Exit;
  { F смотрит внутрь коробки: луч сверху ставится чуть внутри грани, на верхней поверхности. }
  O := V3(Face.Point.X + F.X * 0.05, P.Center.Y + 2.5, Face.Point.Z + F.Z * 0.05);
  Top := LevelRayCast(L, O, V3(0.0, -1.0, 0.0), 3.0);
  if (not Top.Hit) or (Top.Normal.Y < 0.9) then Exit;
  Rise := Top.Point.Y - (P.Center.Y - BODY_FEET);
  if (Rise < PL_LEDGE_MIN) or (Rise > PL_LEDGE_MAX) then Exit;
  C := V3(Face.Point.X - F.X * (BODY_RADIUS + 0.02),
          Top.Point.Y - PL_LEDGE_HOLD + BODY_FEET,
          Face.Point.Z - F.Z * (BODY_RADIUS + 0.02));
  if BodyOverlapAny(L, C) then Exit;
  P.LedgeCenter := C;
  P.LedgeTop := Top.Point.Y;
  Result := True;
end;

procedure StepHang(var P: TPlayer; const Inp: TGameInput);
var
  F: TVec3;
begin
  P.Center := P.LedgeCenter;
  P.Vel := V3Zero;
  P.Grounded := False;
  if Inp.Jump then
  begin
    F := PlayerFacing(P);
    P.ClimbFrom := P.Center;
    P.ClimbTo := V3(P.Center.X + F.X * 0.6, P.LedgeTop + BODY_FEET + 0.05, P.Center.Z + F.Z * 0.6);
    P.State := PS_CLIMB;
    P.StateTime := 0.0;
  end
  else if Inp.CrouchPressed then
  begin
    P.State := PS_AIR;
    P.StateTime := 0.0;
    P.WallLock := 0.3;
    P.Vel := V3(0.0, -1.0, 0.0);
  end;
end;

procedure StepClimb(var P: TPlayer; Dt: Double);
var
  T: Double;
begin
  T := P.StateTime / PL_CLIMB_TIME;
  if T >= 1.0 then
  begin
    P.Center := P.ClimbTo;
    P.Vel := V3Zero;
    P.State := PS_GROUND;
    P.StateTime := 0.0;
    P.Grounded := True;
    P.SinceLanding := 10.0;
    Exit;
  end;
  T := T * T * (3.0 - 2.0 * T);
  P.Center := V3Lerp(P.ClimbFrom, P.ClimbTo, T);
  P.Center.Y := P.Center.Y + 0.3 * Sin(Pi * P.StateTime / PL_CLIMB_TIME);
  P.Vel := V3Zero;
end;

procedure StepRail(var P: TPlayer; const L: TLevel; const Inp: TGameInput; Dt: Double);
var
  Ax, Wish: TVec3;
  Axis, Coord, Target, S: Double;
begin
  Wish := V3(Inp.Move.X, 0.0, Inp.Move.Z);
  if P.RailAxis = 0 then
  begin
    Ax := V3(1.0, 0.0, 0.0);
    S := P.Vel.X;
  end
  else
  begin
    Ax := V3(0.0, 0.0, 1.0);
    S := P.Vel.Z;
  end;
  Axis := ClampD(V3Dot(Wish, Ax), -1.0, 1.0);
  Target := Axis * PL_RAIL_SPEED;
  if S < Target then
    S := Min(Target, S + PL_RAIL_ACCEL * Dt)
  else
    S := Max(Target, S - PL_RAIL_ACCEL * Dt);
  if P.RailAxis = 0 then
  begin
    Coord := P.Center.X + S * Dt;
    P.Vel := V3(S, 0.0, 0.0);
  end
  else
  begin
    Coord := P.Center.Z + S * Dt;
    P.Vel := V3(0.0, 0.0, S);
  end;
  if (Coord < P.RailLo - 0.2) or (Coord > P.RailHi + 0.2) then
  begin
    { Конец перил: соскальзывание и падение. }
    P.State := PS_AIR;
    P.StateTime := 0.0;
    P.Grounded := False;
    P.Vel := V3(Ax.X * S * 0.8, 3.0, Ax.Z * S * 0.8);
    P.WallLock := 0.2;
    Exit;
  end;
  if P.RailAxis = 0 then
    P.Center.X := Coord
  else
    P.Center.Z := Coord;
  if P.RailAxis = 0 then
    P.Center.Z := P.RailLine
  else
    P.Center.X := P.RailLine;
  P.Center.Y := P.RailTop + BODY_FEET;
  if Inp.Jump then
  begin
    P.State := PS_AIR;
    P.StateTime := 0.0;
    P.Grounded := False;
    P.Vel := V3(Ax.X * S * 0.9, PL_JUMP_1, Ax.Z * S * 0.9);
    P.JumpChain := 0;
    P.WallLock := 0.1;
  end
  else if Inp.CrouchPressed then
  begin
    P.State := PS_AIR;
    P.StateTime := 0.0;
    P.Grounded := False;
    P.Vel := V3(Ax.X * S * 0.5, 0.0, Ax.Z * S * 0.5);
    P.WallLock := 0.2;
  end;
end;

procedure StepSlide(var P: TPlayer; const L: TLevel; const Inp: TGameInput; Dt: Double);
var
  H: TVec3;
  Sp, NewSp: Double;
  Ground, Wall: TBodyTouch;
begin
  if Inp.Jump then
  begin
    H := V3(P.Vel.X, 0.0, P.Vel.Z);
    if V3Length(H) < 1.0e-6 then H := PlayerFacing(P);
    H := V3Normalize(H);
    P.Vel := V3(H.X * PL_LONG_FWD, PL_LONG_UP, H.Z * PL_LONG_FWD);
    P.State := PS_AIR;
    P.StateTime := 0.0;
    P.Grounded := False;
    P.FlipKind := FLIP_NONE;
    Inc(P.Stats.LongJumps);
    Exit;
  end;
  P.KickTime := PL_KICK_TIME;
  Sp := HorizontalSpeed(P.Vel);
  NewSp := MaxD(0.0, Sp - 6.0 * Dt);
  if Sp > 1.0e-6 then
  begin
    P.Vel.X := P.Vel.X * NewSp / Sp;
    P.Vel.Z := P.Vel.Z * NewSp / Sp;
  end;
  P.Vel.Y := -4.0;
  BodyMove(P.Center, P.Vel, L, Dt, Ground, Wall);
  if not Ground.Hit then
  begin
    P.State := PS_AIR;
    P.StateTime := 0.0;
    P.Grounded := False;
    P.Vel.Y := 0.0;
    Exit;
  end;
  P.Vel.Y := 0.0;
  P.GroundBox := Ground.Box;
  if (NewSp < 1.5) or (P.StateTime >= PL_SLIDE_TIME) then
  begin
    P.State := PS_GROUND;
    P.StateTime := 0.0;
    P.Grounded := True;
  end;
end;

procedure StepPound(var P: TPlayer; const L: TLevel; Dt: Double);
var
  Ground, Wall: TBodyTouch;
begin
  P.Vel := V3(0.0, -PL_POUND_SPEED, 0.0);
  BodyMove(P.Center, P.Vel, L, Dt, Ground, Wall);
  if Ground.Hit and (P.StateTime >= PL_POUND_MIN) then
  begin
    Inc(P.Stats.Pounds);
    Land(P, L, Ground.Box, True);
    P.Vel := V3Zero;
  end;
end;

procedure PlayerStep(var P: TPlayer; const L: TLevel; const Inp: TGameInput; Dt: Double);
var
  Wish: TVec3;
begin
  P.FireRequest := False;
  P.Landed := False;
  P.LandFromPound := False;
  P.StateTime := P.StateTime + Dt;
  P.ShotCooldown := P.ShotCooldown - Dt;
  P.HurtTime := P.HurtTime - Dt;
  P.KickTime := P.KickTime - Dt;
  P.WallLock := P.WallLock - Dt;
  P.SinceLanding := P.SinceLanding + Dt;
  if P.FlipKind <> FLIP_NONE then P.FlipTime := P.FlipTime + Dt;
  if P.State = PS_DEAD then
  begin
    P.RespawnTime := P.RespawnTime - Dt;
    if P.RespawnTime <= 0.0 then PlayerRespawn(P);
    Exit;
  end;
  Wish := V3(Inp.Move.X, 0.0, Inp.Move.Z);
  if Inp.Aim then
    P.Yaw := AngleApproach(P.Yaw, Inp.CamYaw, 12.0 * Dt)
  else if ((P.State = PS_GROUND) or (P.State = PS_AIR)) and (V3Length(Wish) > 0.1) then
    P.Yaw := AngleApproach(P.Yaw, ArcTan2(Wish.X, Wish.Z), 10.0 * Dt);
  if Inp.Fire and (P.ShotCooldown <= 0.0) and (P.State <> PS_POUND) and (P.State <> PS_CLIMB) then
  begin
    P.FireRequest := True;
    P.ShotCooldown := PL_SHOT_COOLDOWN;
  end;
  case P.State of
    PS_GROUND: StepGround(P, L, Inp, Dt);
    PS_AIR: StepAir(P, L, Inp, Dt);
    PS_WALLRUN: StepWallRun(P, L, Inp, Dt);
    PS_HANG: StepHang(P, Inp);
    PS_CLIMB: StepClimb(P, Dt);
    PS_RAIL: StepRail(P, L, Inp, Dt);
    PS_SLIDE: StepSlide(P, L, Inp, Dt);
    PS_POUND: StepPound(P, L, Dt);
  end;
end;

end.
