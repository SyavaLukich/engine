{ TestGame - проверки игры: геометрия лучей, движение, каждый приём, бой, ИИ, навигация,
  детерминизм. Каждый приём проверяется на численном результате (высота, скорость, состояние,
  счётчики). Допуски заданы явно. Запуск: build/tests/test_game (см. build.sh). }
unit TestGame;

{$mode objfpc}{$H+}

interface

procedure RunGameTests;

implementation

uses
  SysUtils, Math, EngMath, TestKit, GameLevel, GameBody, GameNav, GamePlayer, GameEnemy,
  GameCamera, GameInput, GameWorld;

{ Шаги симуляции с одинаковым вводом. }
procedure Run(var W: TWorld; const I: TGameInput; N: Integer);
var
  K: Integer;
begin
  for K := 1 to N do
    WorldStep(W, I);
end;

procedure Teleport(var W: TWorld; const Feet: TVec3; Yaw: Double; State: Integer);
begin
  W.Player.Center := V3(Feet.X, Feet.Y + BODY_FEET, Feet.Z);
  W.Player.Vel := V3Zero;
  W.Player.Yaw := Yaw;
  W.Player.State := State;
  W.Player.StateTime := 0.0;
  W.Player.FlipKind := FLIP_NONE;
  W.Player.Grounded := State = PS_GROUND;
end;

procedure TestGeometry;
var
  W: TWorld;
  H: TRayHit;
  A: Double;
begin
  Section('Геометрия: лучи по уровню');
  WorldInit(W);
  H := LevelRayCast(W.Level, V3(0.0, 5.0, 0.0), V3(0.0, -1.0, 0.0), 10.0);
  Check(H.Hit, 'луч вниз попадает в пол');
  CheckNear(H.T, 5.0, 1e-6, 'расстояние до пола 5 м');
  H := LevelRayCast(W.Level, V3(0.0, 5.0, 0.0), V3(1.0, 0.0, 0.0), 10.0);
  Check(H.Hit and (H.Box >= 0), 'горизонтальный луч попадает в стену для бега');
  CheckNear(H.T, 5.6, 1e-6, 'стена для бега: грань x = 5.6 м от точки (0, 5, 0)');
  H := LevelRayCast(W.Level, V3(0.0, 9.0, 0.0), V3(1.0, 0.0, 0.0), 10.0);
  Check(not H.Hit, 'луч выше стены не попадает на дистанции 10 м');
  A := ArcTan2(1.6, 4.0);
  H := LevelRayCast(W.Level, V3(14.0, 5.0, -6.0), V3(0.0, -1.0, 0.0), 10.0);
  Check(H.Hit, 'луч вниз попадает в наклонную рампу');
  CheckNear(H.Point.Y, 0.4, 0.01, 'высота рампы при x = 14 м: 0.4 м');
  CheckNear(H.Normal.Y, Cos(A), 1e-3, 'нормаль рампы наклонена под углом подъёма');
end;

procedure TestMotion;
var
  W: TWorld;
  I0, IRun, IJump: TGameInput;
  K: Integer;
  Vmax, Apex: Double;
begin
  Section('Движение и прыжок');
  WorldInit(W);
  W.FreezeEnemies := True;
  InputClear(I0);
  Run(W, I0, 120);
  CheckNear(W.Player.Center.Y, BODY_FEET, 0.005, 'стоя на полу центр капсулы на высоте подошв + 0.85');
  Check(W.Player.Grounded, 'стоя на полу игрок на земле');

  InputClear(IRun);
  IRun.Move := V3(0.0, 0.0, 1.0);
  Vmax := 0.0;
  for K := 1 to 120 do
  begin
    WorldStep(W, IRun);
    Vmax := Max(Vmax, HorizontalSpeed(W.Player.Vel));
  end;
  CheckNear(Vmax, PL_RUN_SPEED, 0.2, 'бег: скорость достигает 9 м/с');

  WorldInit(W);
  W.FreezeEnemies := True;
  Run(W, I0, 60);
  InputClear(IJump);
  IJump.Jump := True;
  WorldStep(W, IJump);
  Apex := 0.0;
  for K := 1 to 240 do
  begin
    WorldStep(W, I0);
    Apex := Max(Apex, W.Player.Center.Y - BODY_FEET);
  end;
  CheckNear(Apex, PL_JUMP_1 * PL_JUMP_1 / (2.0 * PL_GRAVITY), 0.08, 'одиночный прыжок: высота v^2/(2g)');
  Check(W.Player.Stats.Jumps = 1, 'одиночный прыжок засчитан');
end;

procedure TestWallRun;
var
  W: TWorld;
  I: TGameInput;
  K: Integer;
  Got: Boolean;
  MinVy: Double;
begin
  Section('Бег по стене и отскок');
  WorldInit(W);
  W.FreezeEnemies := True;
  W.Player.Center := V3(4.6, 3.0, 0.0);
  W.Player.Vel := V3(7.0, 0.0, 0.0);
  W.Player.Yaw := Pi / 2;
  W.Player.State := PS_AIR;
  InputClear(I);
  I.Move := V3(1.0, 0.0, 0.0);
  Got := False;
  for K := 1 to 120 do
  begin
    WorldStep(W, I);
    if W.Player.State = PS_WALLRUN then
    begin
      Got := True;
      Break;
    end;
  end;
  Check(Got, 'бег по стене начинается у плоскости x = 5.6 при движении в стену');
  if not Got then Exit;
  MinVy := 0.0;
  for K := 1 to 60 do
  begin
    WorldStep(W, I);
    MinVy := Min(MinVy, W.Player.Vel.Y);
  end;
  Check(W.Player.State = PS_WALLRUN, 'бег по стене продолжается полсекунды');
  CheckNear(W.Player.Center.X, 5.6 - BODY_RADIUS, 0.06, 'во время бега по стене тело прижато к стене');
  Check(Abs(W.Player.Center.Z) > 1.5, 'бег по стене идёт вдоль стены (направление вдоль стены)');
  Check(MinVy > -6.1, 'во время бега по стене гравитация ослаблена (скорость падения не больше 6 м/с)');

  InputClear(I);
  I.Move := V3(1.0, 0.0, 0.0);
  I.Jump := True;
  WorldStep(W, I);
  Check(W.Player.State = PS_AIR, 'отскок от стены переводит в воздух');
  Check(W.Player.Vel.X <= -6.5, 'отскок от стены: скорость от стены не меньше 6.5 м/с');
  Check(W.Player.Vel.Y >= 11.9, 'отскок от стены: скорость вверх не меньше 11.9 м/с');
  Check(W.Player.Stats.WallKicks = 1, 'отскок от стены засчитан');
end;

procedure TestLedgeAndShoot;
var
  W: TWorld;
  I0, IJ, IFire: TGameInput;
  K: Integer;
  Got: Boolean;
  Hold: TVec3;
  Shots0: Integer;
begin
  Section('Уступ: захват, висение с выстрелом, подтягивание');
  WorldInit(W);
  W.FreezeEnemies := True;
  Teleport(W, V3(-4.4, 0.0, 6.0), -Pi / 2, PS_GROUND);
  InputClear(I0);
  InputClear(IJ);
  IJ.Jump := True;
  WorldStep(W, IJ);
  Got := False;
  for K := 1 to 180 do
  begin
    WorldStep(W, I0);
    if W.Player.State = PS_HANG then
    begin
      Got := True;
      Break;
    end;
  end;
  Check(Got, 'уступ: захват кромки башни (высота 2 м) при прыжке к грани');
  if not Got then Exit;
  Hold := W.Player.Center;
  Run(W, I0, 120);
  Check(W.Player.State = PS_HANG, 'висение держится две секунды');
  CheckNear(V3Length(V3Sub(W.Player.Center, Hold)), 0.0, 0.01, 'висение: положение не меняется');
  Check(W.Player.Stats.Ledges = 1, 'захват уступа засчитан');

  InputClear(IFire);
  IFire.Fire := True;
  Shots0 := W.Stats.Shots;
  W.Player.ShotCooldown := 0.0;
  WorldStep(W, IFire);
  Check(W.Stats.Shots = Shots0 + 1, 'выстрел из висения засчитан');
  Check(W.Player.State = PS_HANG, 'выстрел из висения не отпускает уступ');

  InputClear(IJ);
  IJ.Jump := True;
  WorldStep(W, IJ);
  Check(W.Player.State = PS_CLIMB, 'прыжок из висения начинает подтягивание');
  Run(W, I0, 60);
  Check(W.Player.State = PS_GROUND, 'подтягивание заканчивается на земле (на верху башни)');
  CheckNear(W.Player.Center.Y, 2.0 + BODY_FEET + 0.05, 0.1, 'после подтягивания подошвы на высоте уступа');
  Check(W.Player.Center.X < -5.0, 'после подтягивания игрок стоит на верху башни');
end;

procedure TestFlips;
var
  W: TWorld;
  I0, IB, IFront, ISide: TGameInput;
  K: Integer;
  MaxY, MaxAng: Double;
begin
  Section('Сальто: назад, вперёд, вбок');
  WorldInit(W);
  W.FreezeEnemies := True;
  InputClear(I0);
  Teleport(W, V3(-20.0, 0.0, -20.0), 0.0, PS_GROUND);
  Run(W, I0, 10);
  InputClear(IB);
  IB.Jump := True;
  IB.Crouch := True;
  WorldStep(W, IB);
  MaxY := 0.0;
  MaxAng := 0.0;
  for K := 1 to 150 do
  begin
    WorldStep(W, I0);
    MaxY := Max(MaxY, W.Player.Center.Y - BODY_FEET);
    MaxAng := Max(MaxAng, PlayerFlipAngle(W.Player));
  end;
  Check(W.Player.Stats.Backflips = 1, 'сальто назад засчитано');
  CheckNear(MaxY, PL_BACKFLIP_UP * PL_BACKFLIP_UP / (2.0 * PL_GRAVITY), 0.15, 'сальто назад: высота v^2/(2g)');
  CheckNear(MaxAng, 2.0 * Pi, 1e-6, 'сальто назад: полный оборот за время полёта');
  Check(W.Player.FlipKind = FLIP_NONE, 'после приземления сальто завершено');

  Teleport(W, V3(-20.0, 0.0, -20.0), 0.0, PS_GROUND);
  W.Player.Vel := V3(0.0, 0.0, 8.0);
  InputClear(IFront);
  IFront.Move := V3(0.0, 0.0, 1.0);
  IFront.Jump := True;
  WorldStep(W, IFront);
  Check(W.Player.Stats.Frontflips = 1, 'сальто вперёд засчитано при беге');
  Check(W.Player.FlipKind = FLIP_FRONT, 'сальто вперёд: вид сальто задан');
  Run(W, I0, 200);

  Teleport(W, V3(-20.0, 0.0, -20.0), 0.0, PS_GROUND);
  Run(W, I0, 10);
  InputClear(ISide);
  ISide.Move := V3(1.0, 0.0, 0.0);
  ISide.Jump := True;
  WorldStep(W, ISide);
  Check(W.Player.Stats.Sideflips = 1, 'сальто вбок засчитано при боковом движении');
  Check(W.Player.Vel.X > 4.0, 'сальто вбок: скорость в сторону не меньше 4 м/с');
end;

procedure TestDoubleJump;
var
  W: TWorld;
  I0, IJ: TGameInput;
  K: Integer;
begin
  Section('Цепочка прыжков');
  WorldInit(W);
  W.FreezeEnemies := True;
  InputClear(I0);
  Teleport(W, V3(-20.0, 0.0, -20.0), 0.0, PS_GROUND);
  Run(W, I0, 10);
  InputClear(IJ);
  IJ.Jump := True;
  WorldStep(W, IJ);
  for K := 1 to 300 do
  begin
    WorldStep(W, I0);
    if W.Player.State = PS_GROUND then Break;
  end;
  Check(W.Player.State = PS_GROUND, 'первый прыжок возвращает на землю');
  WorldStep(W, IJ);
  Check(W.Player.Stats.DoubleJumps = 1, 'второй прыжок сразу после приземления - двойной');
end;

procedure TestSlideKick;
var
  W: TWorld;
  I0, ISlide: TGameInput;
  E: Integer;
begin
  Section('Подкат: нокдаун врага');
  WorldInit(W);
  W.FreezeEnemies := True;
  W.EnemyCount := 0;
  WorldAddEnemy(W, EN_GRUNT, V3(-19.0, 0.0, 20.0), V3(-19.0, 0.0, 20.0), V3(-19.0, 0.0, 21.0));
  E := 0;
  Teleport(W, V3(-22.0, 0.0, 20.0), Pi / 2, PS_GROUND);
  W.Player.Vel := V3(10.0, 0.0, 0.0);
  InputClear(I0);
  InputClear(ISlide);
  ISlide.CrouchPressed := True;
  ISlide.Crouch := True;
  ISlide.Move := V3(1.0, 0.0, 0.0);
  WorldStep(W, ISlide);
  Check(W.Player.State = PS_SLIDE, 'подкат начинается из бега при нажатии присада');
  Run(W, I0, 60);
  Check(W.Enemies[E].State = ES_KNOCK, 'подкат сбивает врага с ног');
  Check(W.Stats.SlideHits >= 1, 'попадание подката засчитано');
  Check(W.Enemies[E].Health < EN_HEALTH_GRUNT, 'подкат наносит урон');
end;

procedure TestGroundPound;
var
  W: TWorld;
  I0, IP: TGameInput;
  K: Integer;
begin
  Section('Удар сверху: ударная волна');
  WorldInit(W);
  W.FreezeEnemies := True;
  W.EnemyCount := 0;
  WorldAddEnemy(W, EN_GRUNT, V3(-20.0, 0.0, 20.0), V3(-20.0, 0.0, 20.0), V3(-20.0, 0.0, 21.0));
  WorldAddEnemy(W, EN_GRUNT, V3(-17.5, 0.0, 20.0), V3(-17.5, 0.0, 20.0), V3(-17.5, 0.0, 21.0));
  W.Player.Center := V3(-20.0, 4.0, 20.0);
  W.Player.Vel := V3Zero;
  W.Player.State := PS_AIR;
  W.Player.StateTime := 0.5;
  W.Player.Yaw := 0.0;
  InputClear(I0);
  InputClear(IP);
  IP.CrouchPressed := True;
  IP.Crouch := True;
  WorldStep(W, IP);
  Check(W.Player.State = PS_POUND, 'удар сверху начинается в воздухе');
  for K := 1 to 300 do
  begin
    WorldStep(W, I0);
    if W.Player.State = PS_GROUND then Break;
  end;
  Check(W.Player.State = PS_GROUND, 'удар сверху заканчивается на земле');
  Check(W.Stats.Shockwaves = 1, 'приземление после удара сверху даёт ударную волну');
  Check(W.Stats.PoundKills = 1, 'враг в ядре волны погибает');
  Check(W.Enemies[1].State = ES_KNOCK, 'враг в радиусе волны сбит с ног');
end;

procedure TestRail;
var
  W: TWorld;
  I0, IR: TGameInput;
  K: Integer;
  Got: Boolean;
  X0: Double;
begin
  Section('Перила: бег и сход с конца');
  WorldInit(W);
  W.FreezeEnemies := True;
  W.Player.Center := V3(-2.0, 2.5, -12.0);
  W.Player.Vel := V3(0.0, -3.0, 0.0);
  W.Player.State := PS_AIR;
  W.Player.Yaw := Pi / 2;
  InputClear(I0);
  Got := False;
  for K := 1 to 180 do
  begin
    WorldStep(W, I0);
    if W.Player.State = PS_RAIL then
    begin
      Got := True;
      Break;
    end;
  end;
  Check(Got, 'перила: падение на верх перил переводит в бег по перилам');
  if not Got then Exit;
  CheckNear(W.Player.Center.Y, 1.08 + BODY_FEET, 0.01, 'на перилах подошвы на высоте верха перил');
  X0 := W.Player.Center.X;
  InputClear(IR);
  IR.Move := V3(1.0, 0.0, 0.0);
  Run(W, IR, 60);
  Check(W.Player.Center.X > X0 + 2.0, 'на перилах игрок бежит вдоль перил');
  CheckNear(W.Player.Center.Z, -12.0, 1e-6, 'на перилах игрок остаётся на линии перил');
  Run(W, IR, 120);
  Check((W.Player.State <> PS_RAIL) and (W.Player.Center.X > W.Player.RailHi), 'дойдя до конца перил, игрок сходит с них');
end;

procedure TestEnemySight;
var
  W: TWorld;
  I0: TGameInput;
  D0, D1: Double;
  Seen: Boolean;
begin
  Section('ИИ: зрение и погоня');
  WorldInit(W);
  W.Enemies[2].Frozen := True;
  W.Enemies[1].Frozen := True;
  Teleport(W, V3(10.0, 0.0, 16.0), Pi, PS_GROUND);
  InputClear(I0);
  D0 := V3Distance(W.Enemies[0].Center, W.Player.Center);
  Run(W, I0, 60);
  Seen := (W.Enemies[0].State = ES_ALERT) or (W.Enemies[0].State = ES_CHASE);
  Check(Seen, 'враг в поле зрения переходит к тревоге или погоне');
  Run(W, I0, 360);
  D1 := V3Distance(W.Enemies[0].Center, W.Player.Center);
  Check((D1 < D0 - 1.0) or (W.Stats.EnemyShots > 0), 'враг приближается или стреляет по игроку');
  Check(W.Enemies[0].Shots > 0, 'враг стреляет по игроку в поле зрения');
end;

procedure TestLineOfSight;
var
  W: TWorld;
  En: TEnemy;
  P: TPlayer;
begin
  Section('ИИ: линия видимости');
  WorldInit(W);
  EnemyInit(En, EN_GRUNT, V3(2.0, 0.0, 0.0), V3(2.0, 0.0, 0.0), V3(2.0, 0.0, 1.0), 99);
  En.Yaw := Pi / 2;
  PlayerInit(P, V3(4.0, 0.0, 1.0));
  Check(EnemySees(En, W.Level, P), 'враг видит игрока перед собой без препятствий');
  PlayerInit(P, V3(9.0, 0.0, 0.0));
  Check(not EnemySees(En, W.Level, P), 'стена между врагом и игроком закрывает обзор');
  PlayerInit(P, V3(-3.0, 0.0, 0.0));
  Check(not EnemySees(En, W.Level, P), 'игрок за спиной вне поля зрения не виден');
end;

procedure TestMelee;
var
  W: TWorld;
  I0: TGameInput;
begin
  Section('ИИ: ближний удар с замахом');
  WorldInit(W);
  W.Enemies[1].Frozen := True;
  W.Enemies[2].Frozen := True;
  Teleport(W, V3(10.0, 0.0, 9.2), 0.0, PS_GROUND);
  InputClear(I0);
  Run(W, I0, 360);
  Check(W.Player.Health <= PL_MAX_HEALTH - EN_MELEE_DAMAGE + 0.5, 'враг наносит ближний удар игроку');
end;

procedure TestShooting;
var
  W: TWorld;
  I0, IFire: TGameInput;
  K: Integer;
  Eye, D: TVec3;
begin
  Section('Стрельба: попадания и смерть врага');
  WorldInit(W);
  W.FreezeEnemies := True;
  Teleport(W, V3(-20.0, 0.0, -20.0), 0.0, PS_GROUND);
  W.Enemies[0].Center := V3(-20.0, 0.85, -12.0);
  InputClear(I0);
  Run(W, I0, 5);
  for K := 1 to 4 do
  begin
    InputClear(IFire);
    IFire.Fire := True;
    Eye := W.Cam.Eye;
    D := V3Normalize(V3Sub(EnemyEye(W.Enemies[0]), Eye));
    W.Cam.Forward := D;
    W.Player.ShotCooldown := 0.0;
    WorldStep(W, IFire);
  end;
  Check(W.Stats.ShotHits >= 4, 'четыре выстрела по врагу попадают');
  Check(not W.Enemies[0].Alive, 'четыре попадания убивают врага');
  Check(W.Stats.Kills = 1, 'убийство засчитано');
end;

procedure TestNavigation;
var
  W: TWorld;
  P: TNavPath;
  I, Bad: Integer;
  Through: Boolean;
begin
  Section('Навигация: A* по сетке высот');
  WorldInit(W);
  Check(NavFindPath(W.Nav, V3(-20.0, 0.0, -20.0), V3(20.0, 0.0, 20.0), P), 'путь через арену существует');
  Check(P.Count >= 2, 'путь содержит точки');
  Bad := 0;
  Through := False;
  for I := 1 to P.Count - 1 do
  begin
    if V3Distance(P.Points[I - 1], P.Points[I]) > 1.5 then Inc(Bad);
    if Abs(P.Points[I].Y - P.Points[I - 1].Y) > NAV_STEP + 1e-6 then Inc(Bad);
  end;
  for I := 0 to P.Count - 1 do
    if (P.Points[I].X > 5.5) and (P.Points[I].X < 6.5) and (Abs(P.Points[I].Z) < 10.5) then
      Through := True;
  Check(Bad = 0, 'шаги пути короче диагонали клетки, подъём не больше NAV_STEP');
  Check(not Through, 'путь обходит стену для бега');
  Check(NavFindPath(W.Nav, V3(8.0, 0.0, -6.0), V3(20.0, 1.6, -6.0), P), 'путь на балкон существует (по рампе)');
  Check(not NavFindPath(W.Nav, V3(-4.0, 0.0, 6.0), V3(-8.0, 2.0, 6.0), P), 'путь на башню без рампы не существует');
end;

procedure TestCamera;
var
  W: TWorld;
  C: TThirdPerson;
  Tgt: TVec3;
begin
  Section('Камера: столкновение со стеной');
  WorldInit(W);
  Tgt := V3(5.0, 1.5, 0.0);
  CameraInit(C, Tgt, Pi / 2);
  CameraUpdate(C, W.Level, Tgt, 0.0, 0.0, 0.0, 0.0, False, 1.0 / 120.0);
  Check(C.Eye.X < 5.6, 'камера не проходит сквозь стену');
  Check(V3Distance(C.Eye, Tgt) < CAM_DIST - 1.0, 'камера подошла к стене, а не осталась на полной дистанции');
end;

procedure TestDeterminism;
var
  A, B: TWorld;
  I: TGameInput;
  K: Integer;
  Same: Boolean;
begin
  Section('Детерминизм');
  WorldInit(A);
  WorldInit(B);
  Same := True;
  for K := 0 to 599 do
  begin
    InputClear(I);
    I.Move := V3(Sin(K * 0.07), 0.0, Cos(K * 0.05));
    I.Move := V3Mul(I.Move, 0.8);
    I.Jump := (K mod 90) = 0;
    I.CrouchPressed := (K mod 150) = 75;
    I.Fire := (K mod 30) = 0;
    WorldStep(A, I);
    WorldStep(B, I);
    if (A.Player.Center.X <> B.Player.Center.X) or (A.Player.Center.Y <> B.Player.Center.Y) or
       (A.Player.Center.Z <> B.Player.Center.Z) then
      Same := False;
  end;
  Check(Same, 'одинаковый ввод даёт побитово одинаковое состояние игрока');
  Check(A.Stats.Shots = B.Stats.Shots, 'одинаковый ввод даёт одинаковые выстрелы');
end;

procedure TestRespawn;
var
  W: TWorld;
  I0: TGameInput;
begin
  Section('Смерть и возрождение');
  WorldInit(W);
  W.FreezeEnemies := True;
  PlayerHurt(W.Player, 150.0, V3(0.0, 0.0, 0.0));
  Check(W.Player.State = PS_DEAD, 'урон выше здоровья переводит в смерть');
  InputClear(I0);
  Run(W, I0, 260);
  Check(W.Player.State <> PS_DEAD, 'через две секунды игрок возрождается');
  CheckNear(W.Player.Health, PL_MAX_HEALTH, 1e-9, 'после возрождения здоровье полное');
end;

procedure RunGameTests;
begin
  TestGeometry;
  TestMotion;
  TestWallRun;
  TestLedgeAndShoot;
  TestFlips;
  TestDoubleJump;
  TestSlideKick;
  TestGroundPound;
  TestRail;
  TestEnemySight;
  TestLineOfSight;
  TestMelee;
  TestShooting;
  TestNavigation;
  TestCamera;
  TestDeterminism;
  TestRespawn;
end;

end.
