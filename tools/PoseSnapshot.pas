{ PoseSnapshot - снимки поз рэгдолла через OpenGL 2.x в OSMesa (osmesa-main, см. docs/OSMESA.md).

  Запуск: ./build/examples/PoseSnapshot [--osmesa библиотека] [каталог_вывода]   (по умолчанию out/)
  Библиотека: аргумент --osmesa, иначе переменная окружения ENGINE_OSMESA, иначе libosmesa.so
  (в Windows - osmesa.dll).
  Сценарии: стойка, толчок с восстановлением, падение, дотягивание правой кистью.
  Файлы: pose_standing.png, pose_push.png, pose_fallen.png, pose_reach.png.
  Коды возврата: 0 - успех; 1 - ошибка записи снимка; 2 - OSMesa не запущена.

  Это визуальная проверка геометрии и поз без GPU. Снимки получены через OpenGL (glReadPixels),
  но фиксированным конвейером, без теней и GGX (см. src/render/EngFixedGL.pas). }
program PoseSnapshot;

{$mode objfpc}{$H+}

uses
  SysUtils, Math, EngMath, EngConvex, EngPhysics, EngAnim, EngHumanoid, EngRagdoll,
  EngMat4, EngMesh, EngScene, EngFixedGL, EngPNG;

const
  STEP = 1.0 / 60.0;
  IMG_W = 640;
  IMG_H = 480;

{ Библиотека OSMesa по умолчанию: переменная окружения, иначе имя для текущей платформы. }
function DefaultOSMesaLibrary: string;
begin
  Result := GetEnvironmentVariable('ENGINE_OSMESA');
  if Result <> '' then
    Exit;
{$IFDEF WINDOWS}
  Result := 'osmesa.dll';
{$ELSE}
  Result := 'libosmesa.so';
{$ENDIF}
end;

{ Меш тела кости по его форме в физике. }
function BodyMesh(const W: TPhysWorld; Body: Integer; const Color: TVec3): TMeshData;
var
  S: TConvexShape;
begin
  S := W.Bodies[Body].Shape;
  case S.Kind of
    skBox: Result := MeshBox(S.Half, Color);
    skSphere: Result := MeshSphere(S.Radius, 16, 12, Color);
    skCapsule: Result := MeshCapsule(S.Radius, S.Half.Y, 16, 6, Color);
  else
    Result := MeshBox(V3(0.1, 0.1, 0.1), Color);
  end;
end;

{ Кадр: камера смотрит на центр масс рэгдолла; светильник и окружение фиксированы.
  Возвращает False, если снимок не записан. }
function Snapshot(const FileName: string; var W: TPhysWorld; var R: TRagdoll): Boolean;
var
  Meshes: array of TMeshData;
  Items: array of TRenderItem;
  Rgb: TFixedRgb;
  Cam: TRenderCamera;
  Light: TRenderLight;
  B, Count: Integer;
  Colors: array[0..HB_COUNT - 1] of TVec3;
  Com: TVec3;
  M: Double;
begin
  Result := False;
  Colors[HB_PELVIS] := V3(0.16, 0.20, 0.34);
  Colors[HB_TORSO] := V3(0.22, 0.38, 0.72);
  Colors[HB_HEAD] := V3(0.90, 0.74, 0.60);
  for B := HB_UARM_L to HB_LARM_R do Colors[B] := V3(0.22, 0.38, 0.72);
  Colors[HB_HAND_L] := V3(0.90, 0.74, 0.60);
  Colors[HB_HAND_R] := V3(0.90, 0.74, 0.60);
  for B := HB_THIGH_L to HB_SHIN_R do Colors[B] := V3(0.18, 0.18, 0.22);
  Colors[HB_FOOT_L] := V3(0.10, 0.10, 0.12);
  Colors[HB_FOOT_R] := V3(0.10, 0.10, 0.12);

  SetLength(Meshes, HB_COUNT + 1);
  for B := 0 to HB_COUNT - 1 do
    Meshes[B] := BodyMesh(W, R.Bodies[B], Colors[B]);
  Meshes[HB_COUNT] := MeshPlane(12.0, V3(0.62, 0.64, 0.66));

  SetLength(Items, HB_COUNT + 1);
  Count := 0;
  for B := 0 to HB_COUNT - 1 do
  begin
    Items[Count].Mesh := B;
    Items[Count].Model := Mat4FromRT(W.Bodies[R.Bodies[B]].Pos, W.Bodies[R.Bodies[B]].Rot, V3(1, 1, 1));
    Items[Count].Tint := V3(1, 1, 1);
    Items[Count].Metallic := 0;
    Items[Count].Roughness := 0.6;
    Items[Count].Checker := False;
    Items[Count].CastShadow := True;
    Inc(Count);
  end;
  Items[Count].Mesh := HB_COUNT;
  Items[Count].Model := Mat4Identity;
  Items[Count].Tint := V3(1, 1, 1);
  Items[Count].Metallic := 0;
  Items[Count].Roughness := 0.9;
  Items[Count].Checker := True;
  Items[Count].CastShadow := False;
  Inc(Count);
  SetLength(Items, Count);

  Com := PhysWorldCenterOfMass(W, R.Group, M);
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

  FixedRender(Cam, Light, Items, Meshes, V3(0.07, 0.08, 0.10));
  if not FixedReadRGB(Rgb) then
  begin
    WriteLn(ErrOutput, 'кадр не прочитан: ', FileName);
    Exit;
  end;
  Result := PngSave(FileName, IMG_W, IMG_H, 3, Rgb);
  if Result then
    WriteLn('сохранено: ', FileName)
  else
    WriteLn(ErrOutput, 'ошибка записи: ', FileName);
end;

function Run(const OutDir: string): Boolean;
var
  W: TPhysWorld;
  R: TRagdoll;
  I: Integer;
begin
  Result := True;

  { стойка }
  PhysWorldInit(W, V3(0, -9.81, 0), 16);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.8, 0);
  RagdollCreate(W, R, V3Zero, 0.5, 1);
  for I := 1 to 180 do RagdollAdvance(W, R, STEP, 4);
  Result := Snapshot(OutDir + '/pose_standing.png', W, R) and Result;

  { толчок 80 Н·с, восстановление через 2 с }
  PhysWorldInit(W, V3(0, -9.81, 0), 16);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.8, 0);
  RagdollCreate(W, R, V3Zero, 0.5, 1);
  for I := 1 to 120 do RagdollAdvance(W, R, STEP, 4);
  RagdollPush(W, R, HB_TORSO, V3(0, 0, 80), RagdollBodyPos(W, R, HB_TORSO));
  for I := 1 to 60 do RagdollAdvance(W, R, STEP, 4);
  Result := Snapshot(OutDir + '/pose_push.png', W, R) and Result;

  { падение: толчок 150 Н·с, через 3 с рэгдолл лежит }
  PhysWorldInit(W, V3(0, -9.81, 0), 16);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.8, 0);
  RagdollCreate(W, R, V3Zero, 0.5, 1);
  for I := 1 to 120 do RagdollAdvance(W, R, STEP, 4);
  RagdollPush(W, R, HB_TORSO, V3(0, 0, 150), RagdollBodyPos(W, R, HB_TORSO));
  for I := 1 to 180 do RagdollAdvance(W, R, STEP, 4);
  Result := Snapshot(OutDir + '/pose_fallen.png', W, R) and Result;

  { дотягивание правой кистью }
  PhysWorldInit(W, V3(0, -9.81, 0), 16);
  PhysSetGround(W, V3(0, 1, 0), 0, 0.8, 0);
  RagdollCreate(W, R, V3Zero, 0.5, 1);
  R.ReachWeight[1] := 1.0;
  R.ReachTarget[1] := V3(-0.3, 1.05, 0.3);
  for I := 1 to 240 do RagdollAdvance(W, R, STEP, 4);
  Result := Snapshot(OutDir + '/pose_reach.png', W, R) and Result;
end;

var
  OutDir, LibPath: string;
  I: Integer;
  Ok: Boolean;
begin
  OutDir := 'out';
  LibPath := DefaultOSMesaLibrary;
  I := 1;
  while I <= ParamCount do
  begin
    if (ParamStr(I) = '--osmesa') and (I < ParamCount) then
    begin
      Inc(I);
      LibPath := ParamStr(I);
    end
    else
      OutDir := ParamStr(I);
    Inc(I);
  end;

  if not FixedInit(LibPath, IMG_W, IMG_H) then
  begin
    WriteLn(ErrOutput, 'OpenGL через OSMesa не запущен: ', FixedLastError);
    WriteLn(ErrOutput, 'укажите библиотеку: --osmesa путь/libosmesa.so (сборка: docs/OSMESA.md)');
    Halt(2);
  end;
  WriteLn('OpenGL: ', FixedVersion);
  ForceDirectories(OutDir);
  Ok := Run(OutDir);
  FixedShutdown;
  if not Ok then
    Halt(1);
end.
