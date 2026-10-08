{ EngDemo - приложение-демонстрация: рэгдолл на полу, контекст OpenGL 4.3 core.
  Два режима: окно GLFW (по умолчанию) и режим без окна через Mesa OSMesa (--offscreen).
  Логика вынесена в юнит, чтобы консольная программа examples/Demo.pas и проект Lazarus
  использовали один и тот же код.

  Управление в окне: R - толчок торса (80 Н·с), Esc - выход.
  Аргументы командной строки:
    --frames N       завершить после N кадров (0 - без ограничения);
    --shot FILE      сохранить последний кадр методом lencerf (glReadPixels, см. EngScreenshot);
                     без --frames снимается кадр 120;
    --shaders DIR    каталог шейдеров (по умолчанию shaders);
    --offscreen      без окна: контекст создаёт OSMesa (программный OpenGL Mesa, без GPU);
    --osmesa FILE    библиотека OSMesa (подразумевает --offscreen). По умолчанию libOSMesa.so.8
                     (Windows: osmesa.dll).
  Коды возврата: 0 - успех; 1 - ошибка окна, контекста OpenGL 4.3 или шейдеров;
                 2 - библиотека GLFW (или OSMesa в режиме --offscreen) не найдена. }
unit EngDemo;

{$mode objfpc}{$H+}

interface

function RunDemo: Integer;

implementation

uses
  SysUtils, Math, EngMath, EngConvex, EngPhysics, EngHumanoid, EngRagdoll,
  EngMat4, EngMesh, EngScene, EngRender, GLBind, GLFWBind, OSMesaBind, EngScreenshot;

const
  WIN_W = 1280;
  WIN_H = 720;
  SIM_DT = 1.0 / 60.0;
  SIM_SUBSTEPS = 4;
  SHOT_FRAME = 120;

type
  TDemoOptions = record
    MaxFrames: Integer;      { 0 - без ограничения (в режиме --offscreen - SHOT_FRAME) }
    ShotFile: string;        { пусто - снимок не делать }
    ShaderDir: string;
    Offscreen: Boolean;      { режим без окна, контекст из OSMesa }
    OSMesaLib: string;       { файл библиотеки OSMesa }
  end;

  TDemoScene = record
    World: TPhysWorld;
    Rag: TRagdoll;
    BodyMesh: array[0..HB_COUNT - 1] of Integer;   { индексы GL-мешей костей }
    Colors: array[0..HB_COUNT - 1] of TVec3;
    GroundMesh: Integer;
  end;

{ Имя библиотеки GLFW для текущей платформы. }
function GlfwLibraryName: string;
begin
{$IFDEF WINDOWS}
  Result := 'glfw3.dll';
{$ELSE}
  Result := 'libglfw.so.3';
{$ENDIF}
end;

{ Имя библиотеки OSMesa для текущей платформы. }
function OSMesaLibraryName: string;
begin
{$IFDEF WINDOWS}
  Result := 'osmesa.dll';
{$ELSE}
  Result := 'libOSMesa.so.8';
{$ENDIF}
end;

procedure ParseOptions(out Opt: TDemoOptions);
var
  I: Integer;
  Arg: string;
begin
  Opt.MaxFrames := 0;
  Opt.ShotFile := '';
  Opt.ShaderDir := 'shaders';
  Opt.Offscreen := False;
  Opt.OSMesaLib := OSMesaLibraryName;
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    if Arg = '--offscreen' then
      Opt.Offscreen := True
    else if ((Arg = '--frames') or (Arg = '--shot') or (Arg = '--shaders') or (Arg = '--osmesa'))
            and (I < ParamCount) then
    begin
      Inc(I);
      if Arg = '--frames' then
        Opt.MaxFrames := StrToIntDef(ParamStr(I), 0)
      else if Arg = '--shot' then
        Opt.ShotFile := ParamStr(I)
      else if Arg = '--osmesa' then
      begin
        Opt.OSMesaLib := ParamStr(I);
        Opt.Offscreen := True;
      end
      else
        Opt.ShaderDir := ParamStr(I);
    end
    else
    begin
      WriteLn(ErrOutput, 'неизвестный или неполный аргумент: ', Arg);
      WriteLn(ErrOutput, 'использование: Demo [--frames N] [--shot файл.png] [--shaders каталог]',
              ' [--offscreen] [--osmesa библиотека]');
      Halt(1);
    end;
    Inc(I);
  end;
  if ((Opt.ShotFile <> '') or Opt.Offscreen) and (Opt.MaxFrames <= 0) then
    Opt.MaxFrames := SHOT_FRAME;
end;

{ Меш кости по её форме в физике; цвет задаётся для каждой кости. }
function BodyGlMesh(const W: TPhysWorld; Body: Integer; const Color: TVec3; var R: TRenderer): Integer;
var
  S: TConvexShape;
  M: TMeshData;
begin
  S := W.Bodies[Body].Shape;
  case S.Kind of
    skBox: M := MeshBox(S.Half, Color);
    skSphere: M := MeshSphere(S.Radius, 16, 12, Color);
    skCapsule: M := MeshCapsule(S.Radius, S.Half.Y, 16, 6, Color);
  else
    M := MeshBox(V3(0.1, 0.1, 0.1), Color);
  end;
  Result := RenderUploadMesh(R, M);
end;

{ Создание сцены: пол, рэгдолл в стойке, GL-меши (загружаются один раз). }
procedure SceneInit(var Sc: TDemoScene; var R: TRenderer);
var
  B: Integer;
begin
  Sc.Colors[HB_PELVIS] := V3(0.16, 0.20, 0.34);
  Sc.Colors[HB_TORSO] := V3(0.22, 0.38, 0.72);
  Sc.Colors[HB_HEAD] := V3(0.90, 0.74, 0.60);
  for B := HB_UARM_L to HB_LARM_R do
    Sc.Colors[B] := V3(0.22, 0.38, 0.72);
  Sc.Colors[HB_HAND_L] := V3(0.90, 0.74, 0.60);
  Sc.Colors[HB_HAND_R] := V3(0.90, 0.74, 0.60);
  for B := HB_THIGH_L to HB_SHIN_R do
    Sc.Colors[B] := V3(0.18, 0.18, 0.22);
  Sc.Colors[HB_FOOT_L] := V3(0.10, 0.10, 0.12);
  Sc.Colors[HB_FOOT_R] := V3(0.10, 0.10, 0.12);

  PhysWorldInit(Sc.World, V3(0, -9.81, 0), 16);
  PhysSetGround(Sc.World, V3(0, 1, 0), 0, 0.8, 0);
  RagdollCreate(Sc.World, Sc.Rag, V3Zero, 0.5, 1);
  for B := 0 to HB_COUNT - 1 do
    Sc.BodyMesh[B] := BodyGlMesh(Sc.World, Sc.Rag.Bodies[B], Sc.Colors[B], R);
  Sc.GroundMesh := RenderUploadMesh(R, MeshPlane(12.0, V3(0.62, 0.64, 0.66)));
end;

{ Камера следит за центром масс рэгдолла; светильник фиксирован (как в PoseSnapshot). }
procedure SetupView(const Sc: TDemoScene; out Cam: TRenderCamera; out Light: TRenderLight);
var
  Com: TVec3;
  Mass: Double;
begin
  Com := PhysWorldCenterOfMass(Sc.World, Sc.Rag.Group, Mass);
  Cam.Target := V3(Com.X, Max(0.5, Com.Y), Com.Z);
  Cam.Eye := V3Add(Cam.Target, V3(2.6, 1.2, 3.4));
  Cam.Up := V3(0, 1, 0);
  Cam.FovY := 40.0 * ENG_PI / 180.0;
  Cam.ZNear := 0.1;
  Cam.ZFar := 50.0;
  Light.Direction := V3Normalize(V3(0.4, 1.0, 0.3));
  Light.Color := V3(2.4, 2.25, 2.0);
  Light.SkyColor := V3(0.45, 0.55, 0.70);
  Light.GroundColor := V3(0.20, 0.18, 0.15);
  Light.Center := Cam.Target;
  Light.Extent := 4.0;
end;

{ Элементы кадра: кости берут позу из физики, пол - шахматный рисунок. }
procedure FillItems(const Sc: TDemoScene; var Items: array of TRenderItem);
var
  B, Body: Integer;
begin
  for B := 0 to HB_COUNT - 1 do
  begin
    Body := Sc.Rag.Bodies[B];
    Items[B].Mesh := Sc.BodyMesh[B];
    Items[B].Model := Mat4FromRT(Sc.World.Bodies[Body].Pos, Sc.World.Bodies[Body].Rot, V3(1, 1, 1));
    Items[B].Tint := V3(1, 1, 1);
    Items[B].Metallic := 0;
    Items[B].Roughness := 0.6;
    Items[B].Checker := False;
    Items[B].CastShadow := True;
  end;
  Items[HB_COUNT].Mesh := Sc.GroundMesh;
  Items[HB_COUNT].Model := Mat4Identity;
  Items[HB_COUNT].Tint := V3(1, 1, 1);
  Items[HB_COUNT].Metallic := 0;
  Items[HB_COUNT].Roughness := 0.9;
  Items[HB_COUNT].Checker := True;
  Items[HB_COUNT].CastShadow := False;
end;

{ Один шаг демо: толчок торса (если Push), шаг физики, размер вида и отрисовка в текущий буфер.
  Общий для окна и режима без окна. }
procedure DemoFrame(var Sc: TDemoScene; var R: TRenderer; var Items: array of TRenderItem;
  Push: Boolean; W, H: Integer; var LastW, LastH: Integer);
var
  Cam: TRenderCamera;
  Light: TRenderLight;
begin
  if Push then
    RagdollPush(Sc.World, Sc.Rag, HB_TORSO, V3(0, 0, 80),
                RagdollBodyPos(Sc.World, Sc.Rag, HB_TORSO));
  RagdollAdvance(Sc.World, Sc.Rag, SIM_DT, SIM_SUBSTEPS);
  if (W <> LastW) or (H <> LastH) then
  begin
    RenderResize(R, W, H);
    LastW := W;
    LastH := H;
  end;
  SetupView(Sc, Cam, Light);
  FillItems(Sc, Items);
  RenderFrame(R, Cam, Light, Items);
end;

{ Окно, контекст и цикл кадров. GLFW уже загружена; возвращает код выхода (0 или 1). }
function RunLoaded(const Opt: TDemoOptions): Integer;
var
  Win: Pointer;
  Inited, Ready, ShotOk, RWasDown, PushNow: Boolean;
  R: TRenderer;
  Sc: TDemoScene;
  Items: array of TRenderItem;
  Frame, FbW, FbH, LastW, LastH: Integer;
begin
  Result := 1;
  Win := nil;
  Inited := False;
  Ready := False;
  if glfwInit() = 0 then
    WriteLn(ErrOutput, 'glfwInit не удался: ', GLFWLastError)
  else
  begin
    Inited := True;
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
    glfwWindowHint(GLFW_SAMPLES, 4);
    Win := glfwCreateWindow(WIN_W, WIN_H, 'Engine demo: ragdoll', nil, nil);
    if Win = nil then
      WriteLn(ErrOutput, 'не удалось создать окно с контекстом OpenGL 4.3 core: ', GLFWLastError)
    else
    begin
      glfwMakeContextCurrent(Win);
      glfwSwapInterval(1);
      GLLoadFunctions(glfwGetProcAddress);
      if not GLVersionAtLeast(4, 3) then
        WriteLn(ErrOutput, 'нужен OpenGL 4.3, получено: ', GLVersionString)
      else if not RenderInit(R, Opt.ShaderDir, WIN_W, WIN_H) then
        WriteLn(ErrOutput, 'не удалось загрузить шейдеры из каталога: ', Opt.ShaderDir)
      else
        Ready := True;
    end;
  end;

  if Ready then
  begin
    Result := 0;
    ShotOk := True;
    SceneInit(Sc, R);
    SetLength(Items, HB_COUNT + 1);
    Frame := 0;
    RWasDown := False;
    LastW := -1;
    LastH := -1;
    while (glfwWindowShouldClose(Win) = 0) and ((Opt.MaxFrames = 0) or (Frame < Opt.MaxFrames)) do
    begin
      glfwPollEvents;
      if glfwGetKey(Win, GLFW_KEY_ESCAPE) = GLFW_PRESS then
        glfwSetWindowShouldClose(Win, GLFW_TRUE);
      PushNow := (glfwGetKey(Win, GLFW_KEY_R) = GLFW_PRESS) and (not RWasDown);
      RWasDown := (glfwGetKey(Win, GLFW_KEY_R) = GLFW_PRESS);
      glfwGetFramebufferSize(Win, @FbW, @FbH);
      DemoFrame(Sc, R, Items, PushNow, FbW, FbH, LastW, LastH);
      if (Opt.ShotFile <> '') and (Frame = Opt.MaxFrames - 1) then
      begin
        { снимок до подкачки буферов: читаем задний буфер }
        ShotOk := ScreenshotSave(Opt.ShotFile, FbW, FbH);
        if ShotOk then
          WriteLn('сохранено: ', Opt.ShotFile)
        else
          WriteLn(ErrOutput, 'ошибка записи снимка: ', Opt.ShotFile);
      end;
      glfwSwapBuffers(Win);
      Inc(Frame);
    end;
    if not ShotOk then
      Result := 1;
    RenderShutdown(R);
  end;

  if Win <> nil then
    glfwDestroyWindow(Win);
  if Inited then
    glfwTerminate;
end;

{ Режим без окна: контекст OpenGL 4.3 создаёт OSMesa; кадры и снимок - тот же код, что и в окне.
  Толчок по клавише недоступен (нет ввода), рэгдолл стоит под собственной балансировкой. }
function RunOffscreen(const Opt: TDemoOptions): Integer;
var
  R: TRenderer;
  Sc: TDemoScene;
  Items: array of TRenderItem;
  Frame, LastW, LastH: Integer;
  ShotOk: Boolean;
begin
  Result := 1;
  if not OSMesaLoad(Opt.OSMesaLib) then
  begin
    WriteLn(ErrOutput, 'OSMesa не загружена: ', OSMesaLastError);
    WriteLn(ErrOutput, 'укажите библиотеку через --osmesa ФАЙЛ (Linux: libOSMesa.so.8)');
    Result := 2;
    Exit;
  end;
  if not OSMesaStart(WIN_W, WIN_H) then
    WriteLn(ErrOutput, 'контекст OSMesa не создан: ', OSMesaLastError)
  else if GLLoadFunctions(@OSMesaGetProc) <> 0 then
    WriteLn(ErrOutput, 'в OSMesa не хватает обязательных функций OpenGL')
  else if not GLVersionAtLeast(4, 3) then
    WriteLn(ErrOutput, 'нужен OpenGL 4.3, получено: ', GLVersionString)
  else if not RenderInit(R, Opt.ShaderDir, WIN_W, WIN_H) then
    WriteLn(ErrOutput, 'не удалось загрузить шейдеры из каталога: ', Opt.ShaderDir)
  else
  begin
    Result := 0;
    ShotOk := True;
    SceneInit(Sc, R);
    SetLength(Items, HB_COUNT + 1);
    LastW := -1;
    LastH := -1;
    for Frame := 0 to Opt.MaxFrames - 1 do
    begin
      DemoFrame(Sc, R, Items, False, WIN_W, WIN_H, LastW, LastH);
      if (Opt.ShotFile <> '') and (Frame = Opt.MaxFrames - 1) then
      begin
        ShotOk := ScreenshotSave(Opt.ShotFile, WIN_W, WIN_H);
        if ShotOk then
          WriteLn('сохранено: ', Opt.ShotFile)
        else
          WriteLn(ErrOutput, 'ошибка записи снимка: ', Opt.ShotFile);
      end;
    end;
    if not ShotOk then
      Result := 1;
    RenderShutdown(R);
  end;
  OSMesaUnload;
end;

function RunDemo: Integer;
var
  Opt: TDemoOptions;
begin
  ParseOptions(Opt);
  if Opt.Offscreen then
  begin
    Result := RunOffscreen(Opt);
    Exit;
  end;
  if not GLFWLoad(GlfwLibraryName) then
  begin
    WriteLn(ErrOutput, 'библиотека GLFW 3 не найдена: ', GLFWLastError);
    WriteLn(ErrOutput, 'установите GLFW 3 (libglfw.so.3 или glfw3.dll) и повторите запуск');
    Result := 2;
    Exit;
  end;
  Result := RunLoaded(Opt);
  GLFWUnload;
end;

end.
