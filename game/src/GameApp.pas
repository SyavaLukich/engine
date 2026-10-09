{ GameApp - приложение игры Gunner (экшн-шутер от третьего лица на движке, OpenGL 4.3).
  Точка входа - RunGunner; программы game/Gunner.pas и lazarus/Gunner.lpr вызывают её.

  Игра - Gunner.

  Запуск:
    ./build/game/Gunner                       окно GLFW (нужна библиотека libglfw.so.3, GL 4.3)
    ./build/game/Gunner --offscreen --osmesa LIB --scenario NAME --shots PREFIX
                                              без окна: сценарий, снимки PREFIX_NAME_TICK.png

  Управление в окне: W A S D - движение относительно камеры, пробел - прыжок (второй и третий
  прыжок в цепочке, сальто при присаде/беге/боковом шаге), C или Ctrl - присед (подкат из бега,
  удар сверху в воздухе), F - выстрел, E - удар ногой, R - прицеливание, стрелки - камера, Esc - выход.

  Коды возврата: 0 - успех, 1 - ошибка аргументов, 2 - нет библиотеки (GLFW или OSMesa), 3 - нет GL 4.3.
  Классов нет. }
unit GameApp;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, EngMath, EngMat4, EngMesh, EngRender, EngHud, EngScene, EngScreenshot,
  GLBind, GLFWBind, OSMesaBind, GameInput, GameWorld, GameRender, GameScenario, GamePlayer, GameCamera;

function RunGunner: Integer;

implementation


const
  WIN_W = 1280;
  WIN_H = 720;
  OFF_W = 960;
  OFF_H = 540;
  KEY_W = 87;
  KEY_A = 65;
  KEY_S = 83;
  KEY_D = 68;
  KEY_E = 69;
  KEY_F = 70;
  KEY_C = 67;
  KEY_R = 82;
  KEY_SPACE = 32;
  KEY_LCTRL = 341;
  KEY_LEFT = 263;
  KEY_RIGHT = 262;
  KEY_UP = 265;
  KEY_DOWN = 264;
  KEY_ESC = 256;
  LOOK_STEP = 0.035;      { рад за кадр при нажатой стрелке }

type
  TItemList = array of TRenderItem;

  TOptions = record
    Offscreen: Boolean;
    OSMesaLib: string;
    ShaderDir: string;
    Scenario: string;
    ShotPrefix: string;
    Width: Integer;
    Height: Integer;
    Frames: Integer;        { окно: ограничение числа кадров, 0 - без ограничения }
  end;

function GlfwLibraryName: string;
begin
{$IFDEF WINDOWS}
  Result := 'glfw3.dll';
{$ELSE}
  Result := 'libglfw.so.3';
{$ENDIF}
end;

function OSMesaLibraryName: string;
begin
{$IFDEF WINDOWS}
  Result := 'osmesa.dll';
{$ELSE}
  Result := 'libOSMesa.so.8';
{$ENDIF}
end;

procedure Usage;
begin
  WriteLn(ErrOutput, 'использование: Gunner [--offscreen] [--osmesa ФАЙЛ] [--scenario ИМЯ] [--shots ПРЕФИКС]');
  WriteLn(ErrOutput, '  [--width N] [--height N] [--frames N] [--shaders КАТАЛОГ]');
  WriteLn(ErrOutput, '  сценарии: ', SCENARIO_NAMES);
end;

{ Разбор аргументов. Ok = False при ошибке (сообщение выведено). }
function ParseOptions(out O: TOptions): Boolean;
var
  I: Integer;
  Arg: string;
begin
  Result := True;
  O.Offscreen := False;
  O.OSMesaLib := OSMesaLibraryName;
  O.ShaderDir := 'shaders';
  O.Scenario := 'combat';
  O.ShotPrefix := 'out/game';
  O.Width := OFF_W;
  O.Height := OFF_H;
  O.Frames := 0;
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    if Arg = '--offscreen' then
      O.Offscreen := True
    else if (Arg = '--osmesa') or (Arg = '--scenario') or (Arg = '--shots') or (Arg = '--shaders') or
            (Arg = '--width') or (Arg = '--height') or (Arg = '--frames') then
    begin
      if I >= ParamCount then
      begin
        WriteLn(ErrOutput, 'не хватает значения для ', Arg);
        Usage;
        Result := False;
        Exit;
      end;
      Inc(I);
      if Arg = '--osmesa' then
      begin
        O.OSMesaLib := ParamStr(I);
        O.Offscreen := True;
      end
      else if Arg = '--scenario' then
        O.Scenario := ParamStr(I)
      else if Arg = '--shots' then
        O.ShotPrefix := ParamStr(I)
      else if Arg = '--shaders' then
        O.ShaderDir := ParamStr(I)
      else if Arg = '--width' then
        O.Width := StrToIntDef(ParamStr(I), OFF_W)
      else if Arg = '--height' then
        O.Height := StrToIntDef(ParamStr(I), OFF_H)
      else
        O.Frames := StrToIntDef(ParamStr(I), 0);
    end
    else
    begin
      WriteLn(ErrOutput, 'неизвестный аргумент: ', Arg);
      Usage;
      Result := False;
      Exit;
    end;
    Inc(I);
  end;
  if O.Offscreen and (not ScenarioKnown(O.Scenario)) then
  begin
    WriteLn(ErrOutput, 'неизвестный сценарий: ', O.Scenario);
    Usage;
    Result := False;
  end;
end;

{ Кадр: элементы мира, рендер, интерфейс. Items - достаточной длины для VisualMaxItems. }
procedure DrawFrame(var R: TRenderer; var W: TWorld; var V: TVisual; var Items: TItemList;
                    var H: THud; FbW, FbH: Integer);
var
  Cam: TRenderCamera;
  Light: TRenderLight;
begin
  VisualBuild(V, W, Items);
  { В кадр идут только собранные элементы: хвост массива не инициализирован. }
  SetLength(Items, V.Count);
  VisualCamera(W, Cam, Light);
  RenderResize(R, FbW, FbH);
  RenderFrame(R, Cam, Light, Items);
  HudBuild(H, W, FbW, FbH);
  HudFlush(H);
end;

{ Ввод с клавиатуры: фронт нажатия отслеживается между кадрами. }
procedure ReadWindowInput(Win: Pointer; var W: TWorld; var Inp: TGameInput;
                          var JumpWas, CrouchWas, KickWas: Boolean);
var
  Fwd, Right: Double;
  Jump, Crouch, Kick: Boolean;
begin
  InputClear(Inp);
  Fwd := 0.0;
  Right := 0.0;
  if glfwGetKey(Win, KEY_W) = GLFW_PRESS then Fwd := Fwd + 1.0;
  if glfwGetKey(Win, KEY_S) = GLFW_PRESS then Fwd := Fwd - 1.0;
  if glfwGetKey(Win, KEY_D) = GLFW_PRESS then Right := Right + 1.0;
  if glfwGetKey(Win, KEY_A) = GLFW_PRESS then Right := Right - 1.0;
  Inp.Move := WorldMoveInput(W, Fwd, Right);
  Jump := glfwGetKey(Win, KEY_SPACE) = GLFW_PRESS;
  Crouch := (glfwGetKey(Win, KEY_C) = GLFW_PRESS) or (glfwGetKey(Win, KEY_LCTRL) = GLFW_PRESS);
  Kick := glfwGetKey(Win, KEY_E) = GLFW_PRESS;
  Inp.Jump := Jump and (not JumpWas);
  Inp.Crouch := Crouch;
  Inp.CrouchPressed := Crouch and (not CrouchWas);
  Inp.Kick := Kick and (not KickWas);
  Inp.Fire := glfwGetKey(Win, KEY_F) = GLFW_PRESS;
  Inp.Aim := glfwGetKey(Win, KEY_R) = GLFW_PRESS;
  if glfwGetKey(Win, KEY_LEFT) = GLFW_PRESS then Inp.LookYaw := Inp.LookYaw + LOOK_STEP;
  if glfwGetKey(Win, KEY_RIGHT) = GLFW_PRESS then Inp.LookYaw := Inp.LookYaw - LOOK_STEP;
  if glfwGetKey(Win, KEY_UP) = GLFW_PRESS then Inp.LookPitch := Inp.LookPitch + LOOK_STEP;
  if glfwGetKey(Win, KEY_DOWN) = GLFW_PRESS then Inp.LookPitch := Inp.LookPitch - LOOK_STEP;
  JumpWas := Jump;
  CrouchWas := Crouch;
  KickWas := Kick;
end;

{ Режим без окна: сценарий, снимки в нужные моменты. }
function RunOffscreen(const O: TOptions): Integer;
var
  R: TRenderer;
  W: TWorld;
  H: THud;
  V: TVisual;
  Items: TItemList;
  Inp: TGameInput;
  Tick: Integer;
  Shot: Boolean;
  FileName: string;
begin
  Result := 2;
  if not OSMesaLoad(O.OSMesaLib) then
  begin
    WriteLn(ErrOutput, 'OSMesa не загружена: ', OSMesaLastError);
    WriteLn(ErrOutput, 'укажите библиотеку через --osmesa ФАЙЛ (Linux: libOSMesa.so.8)');
    Exit;
  end;
  if not OSMesaStart(O.Width, O.Height) then
  begin
    WriteLn(ErrOutput, 'контекст OSMesa не создан: ', OSMesaLastError);
    Exit;
  end;
  if GLLoadFunctions(@OSMesaGetProc) <> 0 then
  begin
    WriteLn(ErrOutput, 'в OSMesa не хватает обязательных функций OpenGL');
    Exit;
  end;
  if not GLVersionAtLeast(4, 3) then
  begin
    WriteLn(ErrOutput, 'нужен OpenGL 4.3, получено: ', GLVersionString);
    Result := 3;
    Exit;
  end;
  if not RenderInit(R, O.ShaderDir, O.Width, O.Height) then
  begin
    WriteLn(ErrOutput, 'не удалось загрузить шейдеры из каталога: ', O.ShaderDir);
    Exit;
  end;
  if not HudInit(H, O.ShaderDir) then
  begin
    WriteLn(ErrOutput, 'не удалось загрузить шейдеры интерфейса: ', H.Error);
    Exit;
  end;
  Result := 0;
  WorldInit(W);
  ScenarioSetup(O.Scenario, W);
  VisualInit(V, R, W);
  SetLength(Items, VisualMaxItems(W));
  Tick := 0;
  while ScenarioStep(O.Scenario, W, Tick, Inp, Shot) do
  begin
    WorldStep(W, Inp);
    if Shot then
    begin
      FileName := Format('%s_%s_%d.png', [O.ShotPrefix, O.Scenario, Tick]);
      SetLength(Items, VisualMaxItems(W));
      DrawFrame(R, W, V, Items, H, O.Width, O.Height);
      if ScreenshotSave(FileName, O.Width, O.Height) then
        WriteLn('сохранено: ', FileName)
      else
        WriteLn(ErrOutput, 'ошибка записи снимка: ', FileName);
    end;
    Inc(Tick);
  end;
  WriteLn(Format('сценарий %s: %d тиков, убийств %d, выстрелов %d, попаданий %d',
                 [O.Scenario, Tick, W.Stats.Kills, W.Stats.Shots, W.Stats.ShotHits]));
  RenderShutdown(R);
  HudShutdown(H);
  OSMesaStop;
end;

{ Режим окна: фиксированный шаг симуляции, кадр на каждый проход цикла. }
function RunWindow(const O: TOptions): Integer;
var
  Win: Pointer;
  R: TRenderer;
  W: TWorld;
  H: THud;
  V: TVisual;
  Items: TItemList;
  Inp: TGameInput;
  JumpWas, CrouchWas, KickWas: Boolean;
  Now, Last, Acc: Double;
  Steps, Frame, FbW, FbH: Integer;
begin
  Result := 2;
  if not GLFWLoad(GlfwLibraryName) then
  begin
    WriteLn(ErrOutput, 'GLFW не загружена: ', GLFWLastError);
    WriteLn(ErrOutput, 'установите GLFW 3 (Linux: libglfw.so.3, Windows: glfw3.dll) или запустите с --offscreen');
    Exit;
  end;
  if glfwInit() = 0 then
  begin
    WriteLn(ErrOutput, 'glfwInit не удался: ', GLFWLastError);
    Exit;
  end;
  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
  glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
  glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
  Win := glfwCreateWindow(WIN_W, WIN_H, 'Gunner', nil, nil);
  if Win = nil then
  begin
    WriteLn(ErrOutput, 'окно не создано: ', GLFWLastError);
    glfwTerminate;
    Exit;
  end;
  glfwMakeContextCurrent(Win);
  glfwSwapInterval(1);
  GLLoadFunctions(glfwGetProcAddress);
  if not GLVersionAtLeast(4, 3) then
  begin
    WriteLn(ErrOutput, 'нужен OpenGL 4.3, получено: ', GLVersionString);
    Result := 3;
  end
  else if (not RenderInit(R, O.ShaderDir, WIN_W, WIN_H)) or (not HudInit(H, O.ShaderDir)) then
    WriteLn(ErrOutput, 'не удалось загрузить шейдеры из каталога: ', O.ShaderDir)
  else
  begin
    Result := 0;
    WorldInit(W);
    VisualInit(V, R, W);
    SetLength(Items, VisualMaxItems(W));
    JumpWas := False;
    CrouchWas := False;
    KickWas := False;
    Frame := 0;
    Acc := 0.0;
    Last := glfwGetTime();
    while (glfwWindowShouldClose(Win) = 0) and ((O.Frames = 0) or (Frame < O.Frames)) do
    begin
      glfwPollEvents;
      if glfwGetKey(Win, KEY_ESC) = GLFW_PRESS then
        glfwSetWindowShouldClose(Win, GLFW_TRUE);
      Now := glfwGetTime();
      Acc := Acc + (Now - Last);
      Last := Now;
      Steps := 0;
      while (Acc >= WORLD_DT) and (Steps < 8) do
      begin
        ReadWindowInput(Win, W, Inp, JumpWas, CrouchWas, KickWas);
        WorldStep(W, Inp);
        Acc := Acc - WORLD_DT;
        Inc(Steps);
      end;
      if Steps = 8 then Acc := 0.0;
      glfwGetFramebufferSize(Win, @FbW, @FbH);
      SetLength(Items, VisualMaxItems(W));
      DrawFrame(R, W, V, Items, H, Max(1, FbW), Max(1, FbH));
      glfwSwapBuffers(Win);
      Inc(Frame);
    end;
    RenderShutdown(R);
    HudShutdown(H);
  end;
  glfwDestroyWindow(Win);
  glfwTerminate;
end;

function RunGunner: Integer;
var
  Opts: TOptions;
begin
  if not ParseOptions(Opts) then
    Exit(1);
  if Opts.Offscreen then
    Result := RunOffscreen(Opts)
  else
    Result := RunWindow(Opts);
end;

end.
