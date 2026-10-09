{ GameWorld - состояние игры и шаг симуляции: игрок, враги, камера, бой.
  Бой: выстрел лучом из камеры (попадание по врагу или по уровню), удар ногой и подкат (нокдаун в
  конусе перед игроком, один раз на удар), удар сверху (ударная волна). Трассеры - визуальные отрезки.
  Шаг фиксированный: WORLD_DT. Классов нет. }
unit GameWorld;

{$mode objfpc}{$H+}

interface

uses
  Math, EngMath, GameLevel, GameBody, GameNav, GamePlayer, GameEnemy, GameCamera, GameInput,
  GameLayout;

const
  WORLD_DT = 1.0 / 120.0;     { с, шаг симуляции }
  WORLD_MAX_TRACERS = 64;
  WORLD_SHOT_RANGE = 200.0;
  GUN_DAMAGE = 25.0;
  KICK_DAMAGE = 34.0;
  KICK_KNOCK = 7.0;
  KICK_RANGE = 1.6;
  SLIDE_DAMAGE = 40.0;
  SLIDE_KNOCK = 9.0;
  SHOCK_RADIUS = 3.5;         { м, радиус ударной волны }
  SHOCK_DAMAGE = 40.0;
  SHOCK_KNOCK = 6.0;
  SHOCK_CORE = 1.2;           { м: внутри этого радиуса удар сверху убивает }

type
  TTracer = record
    A: TVec3;
    B: TVec3;
    Life: Double;             { с до исчезновения }
    FromEnemy: Boolean;
  end;

  TWorldStats = record
    Shots: Integer;
    ShotHits: Integer;
    Kills: Integer;
    Knockdowns: Integer;
    KickHits: Integer;
    SlideHits: Integer;
    PoundKills: Integer;
    Shockwaves: Integer;
    EnemyShots: Integer;
  end;

  TWorld = record
    Level: TLevel;
    Info: TLevelInfo;
    Nav: TNavGrid;
    Player: TPlayer;
    Enemies: array of TEnemy;
    EnemyCount: Integer;
    Tracers: array of TTracer;
    TracerCount: Integer;
    Cam: TThirdPerson;
    Time: Double;
    Ticks: Int64;
    Stats: TWorldStats;
    HitMarker: Double;        { с, визуальная метка попадания }
    Seed: LongWord;
    FreezeEnemies: Boolean;   { тесты: враги неподвижны, но сталкиваются }
  end;

procedure WorldInit(var W: TWorld);
procedure WorldAddEnemy(var W: TWorld; Kind: Integer; const Pos, PatrolA, PatrolB: TVec3);
procedure WorldStep(var W: TWorld; const Inp: TGameInput);
{ Перевод ввода относительно камеры (вперёд, вправо) в мировое направление XZ. }
function WorldMoveInput(const W: TWorld; RawForward, RawRight: Double): TVec3;
function WorldAliveEnemies(const W: TWorld): Integer;

implementation

procedure AddTracer(var W: TWorld; const A, B: TVec3; FromEnemy: Boolean);
var
  Idx: Integer;
begin
  if W.TracerCount < WORLD_MAX_TRACERS then
  begin
    Idx := W.TracerCount;
    Inc(W.TracerCount);
  end
  else
    Idx := Integer(W.Ticks mod WORLD_MAX_TRACERS);
  if Idx >= Length(W.Tracers) then SetLength(W.Tracers, WORLD_MAX_TRACERS);
  W.Tracers[Idx].A := A;
  W.Tracers[Idx].B := B;
  if FromEnemy then
    W.Tracers[Idx].Life := 0.10
  else
    W.Tracers[Idx].Life := 0.14;
  W.Tracers[Idx].FromEnemy := FromEnemy;
end;

procedure WorldInit(var W: TWorld);
var
  I: Integer;
begin
  LayoutYard(W.Level, W.Info);
  NavBuild(W.Nav, W.Level, 1.0);
  W.EnemyCount := 0;
  SetLength(W.Enemies, 0);
  W.TracerCount := 0;
  SetLength(W.Tracers, WORLD_MAX_TRACERS);
  W.Seed := 12345;
  W.Time := 0.0;
  W.Ticks := 0;
  W.HitMarker := 0.0;
  W.FreezeEnemies := False;
  FillChar(W.Stats, SizeOf(W.Stats), 0);
  for I := 0 to W.Info.EnemyCount - 1 do
    WorldAddEnemy(W, W.Info.Enemies[I].Kind, W.Info.Enemies[I].Pos,
                  W.Info.Enemies[I].PatrolA, W.Info.Enemies[I].PatrolB);
  PlayerInit(W.Player, W.Info.PlayerSpawn);
  W.Player.Yaw := Pi;
  CameraInit(W.Cam, PlayerEye(W.Player), 0.0);
end;

procedure WorldAddEnemy(var W: TWorld; Kind: Integer; const Pos, PatrolA, PatrolB: TVec3);
var
  Idx: Integer;
begin
  if W.EnemyCount >= Length(W.Enemies) then
    SetLength(W.Enemies, Length(W.Enemies) * 2 + 8);
  Idx := W.EnemyCount;
  Inc(W.Seed, 7919);
  EnemyInit(W.Enemies[Idx], Kind, Pos, PatrolA, PatrolB, W.Seed);
  Inc(W.EnemyCount);
end;

function WorldAliveEnemies(const W: TWorld): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to W.EnemyCount - 1 do
    if W.Enemies[I].Alive then Inc(Result);
end;

function WorldMoveInput(const W: TWorld; RawForward, RawRight: Double): TVec3;
var
  F, R: TVec3;
begin
  F := CameraForwardXZ(W.Cam);
  R := CameraRightXZ(W.Cam);
  Result := V3Add(V3Mul(F, RawForward), V3Mul(R, RawRight));
  if V3Length(Result) > 1.0 then Result := V3Normalize(Result);
end;

{ Выстрел из камеры вдоль Dir. Ближайшее попадание: враг или уровень. Трассер идёт от ствола. }
procedure PlayerShoot(var W: TWorld; const Dir: TVec3);
var
  Eye, Gun, Endp: TVec3;
  Best, I: Integer;
  BestT, T, Tw: Double;
  Hit: TRayHit;
begin
  Inc(W.Stats.Shots);
  Eye := W.Cam.Eye;
  Gun := V3Add(PlayerEye(W.Player), V3Mul(PlayerFacing(W.Player), 0.4));
  Best := -1;
  BestT := 1.0e30;
  for I := 0 to W.EnemyCount - 1 do
    if W.Enemies[I].Alive then
    begin
      T := EnemyRayHit(W.Enemies[I], Eye, Dir, WORLD_SHOT_RANGE);
      if (T >= 0.0) and (T < BestT) then
      begin
        BestT := T;
        Best := I;
      end;
    end;
  Hit := LevelRayCast(W.Level, Eye, Dir, WORLD_SHOT_RANGE);
  Tw := WORLD_SHOT_RANGE;
  if Hit.Hit then Tw := Hit.T;
  if (Best >= 0) and (BestT < Tw) then
  begin
    Endp := V3MulAdd(Eye, Dir, BestT);
    Inc(W.Stats.ShotHits);
    W.HitMarker := 0.18;
    EnemyHit(W.Enemies[Best], GUN_DAMAGE, W.Player.Center, 0.0);
    if not W.Enemies[Best].Alive then Inc(W.Stats.Kills);
  end
  else if Hit.Hit then
    Endp := Hit.Point
  else
    Endp := V3MulAdd(Eye, Dir, WORLD_SHOT_RANGE);
  AddTracer(W, Gun, Endp, False);
end;

{ Удар ногой и подкат: враги перед игроком, каждый один раз за удар. }
procedure ApplyKick(var W: TWorld; Slide: Boolean);
var
  I: Integer;
  Dv, F: TVec3;
  Dist, Fd, Dmg, Knock: Double;
  WasKnocked: Boolean;
begin
  F := PlayerFacing(W.Player);
  for I := 0 to W.EnemyCount - 1 do
  begin
    if (not W.Enemies[I].Alive) or (W.Enemies[I].KickId = W.Player.KickId) then Continue;
    Dv := V3(W.Enemies[I].Center.X - W.Player.Center.X, 0.0, W.Enemies[I].Center.Z - W.Player.Center.Z);
    Dist := V3Length(Dv);
    if Dist > KICK_RANGE + BODY_RADIUS then Continue;
    if Dist > 1.0e-6 then
      Fd := V3Dot(F, V3Mul(Dv, 1.0 / Dist))
    else
      Fd := 1.0;
    if Fd < 0.2 then Continue;
    W.Enemies[I].KickId := W.Player.KickId;
    if Slide then
    begin
      Dmg := SLIDE_DAMAGE;
      Knock := SLIDE_KNOCK;
      Inc(W.Stats.SlideHits);
    end
    else
    begin
      Dmg := KICK_DAMAGE;
      Knock := KICK_KNOCK;
      Inc(W.Stats.KickHits);
    end;
    WasKnocked := W.Enemies[I].State = ES_KNOCK;
    EnemyHit(W.Enemies[I], Dmg, W.Player.Center, Knock);
    if (not WasKnocked) and (W.Enemies[I].State = ES_KNOCK) then Inc(W.Stats.Knockdowns);
    if not W.Enemies[I].Alive then Inc(W.Stats.Kills);
    W.HitMarker := 0.18;
  end;
end;

{ Удар сверху: ударная волна сбивает врагов в радиусе, в ядре - убивает. }
procedure ApplyShockwave(var W: TWorld; const Pos: TVec3);
var
  I: Integer;
  Dv: TVec3;
  Dist: Double;
  WasKnocked: Boolean;
begin
  Inc(W.Stats.Shockwaves);
  for I := 0 to W.EnemyCount - 1 do
  begin
    if not W.Enemies[I].Alive then Continue;
    Dv := V3(W.Enemies[I].Center.X - Pos.X, 0.0, W.Enemies[I].Center.Z - Pos.Z);
    Dist := V3Length(Dv);
    if Dist <= SHOCK_CORE then
    begin
      EnemyHit(W.Enemies[I], 1000.0, Pos, 0.0);
      Inc(W.Stats.PoundKills);
      Inc(W.Stats.Kills);
    end
    else if Dist <= SHOCK_RADIUS then
    begin
      WasKnocked := W.Enemies[I].State = ES_KNOCK;
      EnemyHit(W.Enemies[I], SHOCK_DAMAGE, Pos, SHOCK_KNOCK);
      if (not WasKnocked) and (W.Enemies[I].State = ES_KNOCK) then Inc(W.Stats.Knockdowns);
      if not W.Enemies[I].Alive then Inc(W.Stats.Kills);
    end;
  end;
end;

procedure WorldStep(var W: TWorld; const Inp: TGameInput);
var
  Local: TGameInput;
  I, K: Integer;
  Fired: Boolean;
  ShotF, ShotT: TVec3;
  Fw: TVec3;
begin
  Inc(W.Ticks);
  W.Time := W.Time + WORLD_DT;
  Local := Inp;
  Fw := CameraForwardXZ(W.Cam);
  Local.CamYaw := ArcTan2(Fw.X, Fw.Z);
  Local.AimDir := W.Cam.Forward;
  PlayerStep(W.Player, W.Level, Local, WORLD_DT);
  if W.Player.FireRequest then PlayerShoot(W, W.Cam.Forward);
  if (W.Player.KickTime > 0.0) and ((W.Player.State = PS_GROUND) or (W.Player.State = PS_AIR) or
     (W.Player.State = PS_SLIDE)) then
    ApplyKick(W, W.Player.State = PS_SLIDE);
  if W.Player.Landed and W.Player.LandFromPound then
    ApplyShockwave(W, W.Player.LandPos);
  if not W.FreezeEnemies then
    for I := 0 to W.EnemyCount - 1 do
      if W.Enemies[I].Alive then
      begin
        Fired := EnemyStep(W.Enemies[I], W.Level, W.Nav, W.Player, WORLD_DT, ShotF, ShotT);
        if Fired then
        begin
          Inc(W.Stats.EnemyShots);
          AddTracer(W, ShotF, ShotT, True);
        end;
      end;
  K := 0;
  for I := 0 to W.TracerCount - 1 do
  begin
    W.Tracers[I].Life := W.Tracers[I].Life - WORLD_DT;
    if W.Tracers[I].Life > 0.0 then
    begin
      if K <> I then W.Tracers[K] := W.Tracers[I];
      Inc(K);
    end;
  end;
  W.TracerCount := K;
  if W.HitMarker > 0.0 then W.HitMarker := W.HitMarker - WORLD_DT;
  CameraUpdate(W.Cam, W.Level, PlayerEye(W.Player), Inp.LookYaw, Inp.LookPitch,
               W.Player.Yaw, HorizontalSpeed(W.Player.Vel), Inp.Aim, WORLD_DT);
end;

end.
