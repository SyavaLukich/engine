{ GameScenario - сценарии для запуска без окна (проверка и снимки): начальные условия и ввод по тикам.
  Снимок делается, когда состояние мира совпало с целью сценария (например, игрок на стене),
  а не по времени. Классов нет. }
unit GameScenario;

{$mode objfpc}{$H+}

interface

uses
  Math, EngMath, GameLevel, GameInput, GameWorld, GamePlayer, GameEnemy, GameCamera;

const
  SCENARIO_NAMES = 'wallrun ledge backflip slide pound combat';

{ Проверяет имя сценария. }
function ScenarioKnown(const Name: string): Boolean;
{ Начальные условия сценария. }
procedure ScenarioSetup(const Name: string; var W: TWorld);
{ Ввод на тик Tick. Shot - сделать снимок после этого тика. Возвращает False, когда сценарий окончен. }
function ScenarioStep(const Name: string; var W: TWorld; Tick: Integer; out Inp: TGameInput;
                      out Shot: Boolean): Boolean;

implementation

const
  SCENARIO_LENGTH_WALLRUN = 330;
  SCENARIO_LENGTH_LEDGE = 420;
  SCENARIO_LENGTH_BACKFLIP = 120;
  SCENARIO_LENGTH_SLIDE = 150;
  SCENARIO_LENGTH_POUND = 240;
  SCENARIO_LENGTH_COMBAT = 900;

var
  GShotDone: Integer;     { сколько снимков уже сделано в текущем сценарии }
  GMark: Integer;         { тик, с которого идёт фаза сценария }

function ScenarioKnown(const Name: string): Boolean;
begin
  Result := Pos(' ' + Name + ' ', ' ' + SCENARIO_NAMES + ' ') > 0;
end;

procedure ScenarioSetup(const Name: string; var W: TWorld);
begin
  GShotDone := 0;
  GMark := -1;
  W.FreezeEnemies := Name <> 'combat';
  if Name = 'wallrun' then
  begin
    W.Player.Center := V3(4.6, 3.0, 0.0);
    W.Player.Vel := V3(7.0, 0.0, 0.0);
    W.Player.Yaw := Pi / 2;
    W.Player.State := PS_AIR;
  end
  else if Name = 'ledge' then
  begin
    W.Player.Center := V3(-4.4, 0.85, 6.0);
    W.Player.Yaw := -Pi / 2;
    W.Player.State := PS_GROUND;
    W.Player.Grounded := True;
  end
  else if Name = 'backflip' then
  begin
    W.Player.Center := V3(-20.0, 0.85, -20.0);
    W.Player.Yaw := 0.0;
    W.Player.State := PS_GROUND;
    W.Player.Grounded := True;
  end
  else if Name = 'slide' then
  begin
    W.EnemyCount := 0;
    WorldAddEnemy(W, EN_GRUNT, V3(-19.0, 0.0, 20.0), V3(-19.0, 0.0, 20.0), V3(-19.0, 0.0, 21.0));
    W.Player.Center := V3(-22.0, 0.85, 20.0);
    W.Player.Yaw := Pi / 2;
    W.Player.Vel := V3(10.0, 0.0, 0.0);
    W.Player.State := PS_GROUND;
    W.Player.Grounded := True;
  end
  else if Name = 'pound' then
  begin
    W.EnemyCount := 0;
    WorldAddEnemy(W, EN_GRUNT, V3(-20.0, 0.0, 20.0), V3(-20.0, 0.0, 20.0), V3(-20.0, 0.0, 21.0));
    WorldAddEnemy(W, EN_GRUNT, V3(-17.5, 0.0, 20.0), V3(-17.5, 0.0, 20.0), V3(-17.5, 0.0, 21.0));
    W.Player.Center := V3(-20.0, 4.0, 20.0);
    W.Player.Vel := V3Zero;
    W.Player.Yaw := 0.0;
    W.Player.State := PS_AIR;
    W.Player.StateTime := 0.5;
  end;
  { Камера за спиной игрока, как при обычном управлении. }
  CameraInit(W.Cam, PlayerEye(W.Player), W.Player.Yaw + Pi);
end;

{ Поворот камеры к точке: камера смотрит на цель, если нужно, поворачивается плавно. }
function LookAt(const W: TWorld; const Target: TVec3): Double;
var
  Dv: TVec3;
  Want, D: Double;
begin
  Dv := V3Sub(Target, W.Cam.Eye);
  Want := ArcTan2(-Dv.X, -Dv.Z);
  D := Want - W.Cam.Yaw;
  while D > Pi do D := D - 2.0 * Pi;
  while D < -Pi do D := D + 2.0 * Pi;
  Result := ClampD(D, -0.04, 0.04);
end;

function ScenarioStep(const Name: string; var W: TWorld; Tick: Integer; out Inp: TGameInput;
                      out Shot: Boolean): Boolean;
var
  Target: TVec3;
begin
  InputClear(Inp);
  Shot := False;
  Result := True;
  if Name = 'wallrun' then
  begin
    Inp.Move := V3(1.0, 0.0, 0.0);
    if (W.Player.State = PS_WALLRUN) and (GMark < 0) then GMark := Tick;
    if (GMark >= 0) and (Tick = GMark + 40) then Shot := True;
    if (GMark >= 0) and (Tick = GMark + 90) then Inp.Jump := True;
    if (GMark >= 0) and (Tick = GMark + 100) then Shot := True;
    if Tick >= SCENARIO_LENGTH_WALLRUN then Result := False;
  end
  else if Name = 'ledge' then
  begin
    if Tick = 0 then Inp.Jump := True;
    if (W.Player.State = PS_HANG) and (GMark < 0) then GMark := Tick;
    if (GMark >= 0) and (Tick = GMark + 30) then Shot := True;
    if (GMark >= 0) and (Tick >= GMark + 40) and (Tick < GMark + 60) then Inp.Fire := True;
    if (GMark >= 0) and (Tick = GMark + 90) then Inp.Jump := True;
    if (GMark >= 0) and (Tick = GMark + 150) then Shot := True;
    if Tick >= SCENARIO_LENGTH_LEDGE then Result := False;
  end
  else if Name = 'backflip' then
  begin
    if Tick = 10 then
    begin
      Inp.Jump := True;
      Inp.Crouch := True;
    end;
    if Tick = 10 + 56 then Shot := True;
    if Tick >= SCENARIO_LENGTH_BACKFLIP then Result := False;
  end
  else if Name = 'slide' then
  begin
    if Tick = 0 then
    begin
      Inp.CrouchPressed := True;
      Inp.Crouch := True;
      Inp.Move := V3(1.0, 0.0, 0.0);
    end;
    if (W.Player.State = PS_SLIDE) and (GMark < 0) then GMark := Tick;
    if (GMark >= 0) and (Tick = GMark + 12) then Shot := True;
    if (GMark >= 0) and (Tick = GMark + 90) then Shot := True;
    if Tick >= SCENARIO_LENGTH_SLIDE then Result := False;
  end
  else if Name = 'pound' then
  begin
    if Tick = 0 then
    begin
      Inp.CrouchPressed := True;
      Inp.Crouch := True;
    end;
    if (W.Stats.Shockwaves > 0) and (GMark < 0) then GMark := Tick;
    if (GMark >= 0) and (Tick = GMark + 25) then Shot := True;
    if Tick >= SCENARIO_LENGTH_POUND then Result := False;
  end
  else if Name = 'combat' then
  begin
    { Бег к первому врагу, стрельба по нему, камера наводится на врага. }
    Target := W.Enemies[0].Center;
    if W.Enemies[0].Alive then
    begin
      Inp.LookYaw := LookAt(W, Target);
      Inp.Move := V3Normalize(V3(Target.X - W.Player.Center.X, 0.0, Target.Z - W.Player.Center.Z));
      Inp.Move := V3Mul(Inp.Move, 0.9);
      Inp.Fire := (Tick mod 25) = 0;
      Inp.Aim := True;
    end
    else
      Inp.Move := V3(0.0, 0.0, 0.0);
    if Tick = 250 then Shot := True;
    if Tick = 520 then Shot := True;
    if Tick >= SCENARIO_LENGTH_COMBAT then Result := False;
  end;
end;

end.
