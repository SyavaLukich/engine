{ BenchGame - бенчмарк игры: лучи по уровню, движение капсулы (GJK/EPA), A* по сетке высот,
  шаг мира с разным числом врагов и сборка элементов кадра (без вызовов GL).
  Запуск: ./build.sh bench. Время - GetTickCount64, каждый замер не короче 0.5 с. }
program BenchGame;

{$mode objfpc}{$H+}

uses
  SysUtils, Math, EngMath, EngScene, EngRender, GameLevel, GameBody, GameNav, GamePlayer, GameEnemy, GameInput,
  GameWorld, GameRender;

const
  MIN_MS = 500;

procedure Report(const Name: string; Ms: Int64; Ops: Int64);
begin
  WriteLn(Format('%-52s %10.3f us/op  (%d ops, %d ms)', [Name, Ms * 1000.0 / Ops, Ops, Ms]));
end;

var
  W: TWorld;
  Inp: TGameInput;
  V: TVisual;
  Items: array of TRenderItem;
  Hit: TRayHit;
  Path: TNavPath;
  Touch: TBodyTouch;
  Center, Vel: TVec3;
  Ops, I, K: Integer;
  T0, Ms: Int64;
  Gr, Ground, Wall: TBodyTouch;
  Ok: Boolean;
  Count: Integer;
begin
  WriteLn('BenchGame: одно ядро, FreePascal ', {$I %FPCVERSION%}, ', ', {$I %DATE%});
  WorldInit(W);
  InputClear(Inp);

  { Лучи по уровню. }
  Ops := 0;
  T0 := GetTickCount64;
  repeat
    for I := 0 to 999 do
      Hit := LevelRayCast(W.Level, V3(-20.0 + (I mod 40), 4.0, -15.0 + (I mod 30)), V3(0.3, -1.0, 0.2), 30.0);
    Inc(Ops, 1000);
    Ms := GetTickCount64 - T0;
  until Ms >= MIN_MS;
  Report('луч по уровню (' + IntToStr(W.Level.Count) + ' коробок)', Ms, Ops);

  { Движение капсулы: шаг с разрешением столкновений на полу. }
  Center := V3(0.0, BODY_FEET, -10.0);
  Vel := V3(3.0, 0.0, 6.0);
  Ops := 0;
  T0 := GetTickCount64;
  repeat
    for I := 0 to 999 do
    begin
      BodyMove(Center, Vel, W.Level, WORLD_DT, Gr, Ground);
      if Center.Z > 20.0 then Center.Z := -10.0;
    end;
    Inc(Ops, 1000);
    Ms := GetTickCount64 - T0;
  until Ms >= MIN_MS;
  Report('шаг капсулы BodyMove (GJK/EPA, 1/120 с)', Ms, Ops);

  { Пробы у поверхности. }
  Ops := 0;
  T0 := GetTickCount64;
  repeat
    for I := 0 to 999 do
      Ok := BodyProbe(W.Level, V3(0.0, BODY_FEET + 0.02, -10.0), V3(0.0, -1.0, 0.0), BODY_SKIN, Touch);
    Inc(Ops, 1000);
    Ms := GetTickCount64 - T0;
  until Ms >= MIN_MS;
  Report('проба у поверхности BodyProbe', Ms, Ops);

  { A* по сетке высот. }
  Ops := 0;
  T0 := GetTickCount64;
  repeat
    for I := 0 to 99 do
    begin
      K := (I * 7) mod 30;
      Ok := NavFindPath(W.Nav, V3(-25.0 + K * 0.3, 0.0, -25.0), V3(20.0 - K * 0.2, 0.0, 22.0), Path);
    end;
    Inc(Ops, 100);
    Ms := GetTickCount64 - T0;
  until Ms >= MIN_MS;
  Report('поиск пути A*, сетка ' + IntToStr(W.Nav.W) + 'x' + IntToStr(W.Nav.H) + ' клеток', Ms, Ops);

  { Шаг мира: игрок бежит, враги патрулируют и стреляют. }
  W.FreezeEnemies := False;
  Ops := 0;
  T0 := GetTickCount64;
  repeat
    for I := 0 to 99 do
    begin
      Inp.Move := V3(Sin(Ops * 0.01), 0.0, Cos(Ops * 0.01));
      Inp.Fire := (Ops mod 40) = 0;
      WorldStep(W, Inp);
      Inc(Ops);
    end;
    Ms := GetTickCount64 - T0;
  until Ms >= MIN_MS;
  Report('шаг мира, игрок и 3 врага (1/120 с)', Ms, Ops);

  { Шаг мира с 16 врагами: добавляем патрульных на свободной части арены. }
  WorldInit(W);
  for I := 0 to 12 do
    WorldAddEnemy(W, EN_GRUNT, V3(-26.0 + I * 4.0, 0.0, 26.0), V3(-26.0 + I * 4.0, 0.0, 26.0),
                  V3(-26.0 + I * 4.0, 0.0, 16.0));
  Ops := 0;
  T0 := GetTickCount64;
  repeat
    for I := 0 to 99 do
    begin
      Inp.Move := V3(Sin(Ops * 0.01), 0.0, Cos(Ops * 0.01));
      WorldStep(W, Inp);
      Inc(Ops);
    end;
    Ms := GetTickCount64 - T0;
  until Ms >= MIN_MS;
  Report('шаг мира, игрок и ' + IntToStr(W.EnemyCount) + ' врагов (1/120 с)', Ms, Ops);

  { Сборка элементов кадра на процессоре (без GL). }
  SetLength(V.LevelMesh, W.Level.Count);
  for I := 0 to W.Level.Count - 1 do
    V.LevelMesh[I] := I;
  V.FloorMesh := 0;
  V.Torso := 0;
  V.Head := 0;
  V.Limb := 0;
  V.Foot := 0;
  V.Gun := 0;
  V.TurretBody := 0;
  V.TurretBarrel := 0;
  V.Streak := 0;
  SetLength(Items, VisualMaxItems(W));
  Ops := 0;
  T0 := GetTickCount64;
  repeat
    for I := 0 to 99 do
    begin
      VisualBuild(V, W, Items);
      Inc(Ops);
    end;
    Ms := GetTickCount64 - T0;
  until Ms >= MIN_MS;
  Count := V.Count;
  Report('сборка элементов кадра (' + IntToStr(Count) + ' шт.)', Ms, Ops);
end.
