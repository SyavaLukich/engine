{ EngFixedGL - снимки сцены через OpenGL 2.x (фиксированный конвейер) в OSMesa.

  Рисует меши (TMeshData) с камерой, направленным светом и окружающим светом. Шахматный пол
  строится текстурой 2x2 с объектными текстурными координатами: клетка 1 м, чередование
  множителями 0.55 и 0.85, как в шейдере EngRender (uCheckerScale = 1).
  Кадр читается методом lencerf: glReadPixels, выравнивание строк 1, строки переворачиваются.

  Ограничения по сравнению с EngRender (OpenGL 4.3): нет теней (CastShadow не используется),
  нет GGX и металличности (Metallic не используется), блеск - по шероховатости, освещение -
  фиксированный конвейер (Блинн-Фонг). Классов нет. }
unit EngFixedGL;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, EngMath, EngMat4, EngMesh, EngScene, OSMesaBind, GLFixedBind;

type
  TFixedRgb = array of Byte;   { RGB, строки сверху вниз }

{ Загружает OSMesa из LibPath (libosmesa.so или osmesa.dll) и создаёт контекст OpenGL 2.x W x H.
  False - причина в FixedLastError. }
function FixedInit(const LibPath: string; W, H: Integer): Boolean;
procedure FixedShutdown;
function FixedLastError: string;
function FixedVersion: string;
{ Рисует сцену в буфер кадра. Background - фон (линейные значения 0..1). }
procedure FixedRender(const Cam: TRenderCamera; const Light: TRenderLight;
                      const Items: array of TRenderItem; const Meshes: array of TMeshData;
                      const Background: TVec3);
{ Читает буфер кадра (glReadPixels) и возвращает RGB, строки сверху вниз, для PngSave. }
function FixedReadRGB(out Rgb: TFixedRgb): Boolean;

implementation

const
  FLOATS_PER_VERTEX = 9;       { позиция, нормаль, цвет (см. EngMesh) }
  LIGHT_SCALE = 0.36;          { яркость направленного света для фиксированного конвейера без ACES }

var
  FixReady: Boolean = False;
  FixW: Integer = 0;
  FixH: Integer = 0;
  FixChecker: LongWord = 0;
  FixError: string = '';
  FixTint: array of Single;    { вершины с умноженным на Tint цветом, на время одного вызова }

function FixedLastError: string;
begin
  Result := FixError;
end;

function FixedVersion: string;
begin
  if FixReady then
    Result := string(fxGetString(GL_VERSION))
  else
    Result := '';
end;

function FixedInit(const LibPath: string; W, H: Integer): Boolean;
var
  Texels: array[0..11] of Byte;
  Plane: array[0..3] of Single;
  Ver: string;
  Mode: Single;
begin
  Result := False;
  FixReady := False;
  FixError := '';
  if not OSMesaLoad(LibPath) then
  begin
    FixError := OSMesaLastError;
    Exit;
  end;
  if not OSMesaStartLegacy(W, H) then
  begin
    FixError := OSMesaLastError;
    OSMesaUnload;
    Exit;
  end;
  if FixedLoad(@OSMesaGetProc) <> 0 then
  begin
    FixError := 'в OSMesa нет обязательных функций OpenGL 2.x';
    OSMesaUnload;
    Exit;
  end;
  Ver := string(fxGetString(GL_VERSION));
  if (Length(Ver) = 0) or (Ver[1] < '2') then
  begin
    FixError := 'нужен OpenGL 2.0, получено: ' + Ver;
    OSMesaUnload;
    Exit;
  end;
  FixW := W;
  FixH := H;

  fxViewport(0, 0, W, H);
  fxEnable(GL_DEPTH_TEST);
  fxDepthFunc(GL_LEQUAL);
  fxShadeModel(GL_SMOOTH);
  fxEnable(GL_LIGHTING);
  fxEnable(GL_LIGHT0);
  fxEnable(GL_NORMALIZE);
  fxEnable(GL_COLOR_MATERIAL);
  fxColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE);
  fxPixelStorei(GL_PACK_ALIGNMENT, 1);

  { шахматная текстура: строка 0 - клетки с чётной суммой индексов (тёмные) }
  fxGenTextures(1, @FixChecker);
  fxBindTexture(GL_TEXTURE_2D, FixChecker);
  Texels[0] := 140; Texels[1] := 140; Texels[2] := 140;     { (0,0) тёмная }
  Texels[3] := 217; Texels[4] := 217; Texels[5] := 217;     { (1,0) светлая }
  Texels[6] := 217; Texels[7] := 217; Texels[8] := 217;     { (0,1) светлая }
  Texels[9] := 140; Texels[10] := 140; Texels[11] := 140;   { (1,1) тёмная }
  { строки 2x2 RGB занимают 6 байт: без выравнивания 1 GL читает их с шагом 8 байт (по умолчанию 4) }
  fxPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  fxTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 2, 2, 0, GL_RGB, GL_UNSIGNED_BYTE, @Texels[0]);
  fxTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  fxTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  fxTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
  fxTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
  { период текстуры 2 м по каждой оси: одна текстурная клетка = 1 м }
  Plane[0] := 0.5; Plane[1] := 0; Plane[2] := 0; Plane[3] := 0;
  fxTexGenfv(GL_S, GL_OBJECT_PLANE, @Plane[0]);
  fxTexGeni(GL_S, GL_TEXTURE_GEN_MODE, GL_OBJECT_LINEAR);
  Plane[0] := 0; Plane[1] := 0; Plane[2] := 0.5; Plane[3] := 0;
  fxTexGenfv(GL_T, GL_OBJECT_PLANE, @Plane[0]);
  fxTexGeni(GL_T, GL_TEXTURE_GEN_MODE, GL_OBJECT_LINEAR);
  Mode := 0;
  fxMaterialfv(GL_FRONT_AND_BACK, GL_SHININESS, @Mode);

  FixReady := True;
  Result := True;
end;

procedure FixedShutdown;
begin
  FixReady := False;
  OSMesaUnload;
end;

{ Вершины элемента с цветом, умноженным на Tint; возвращает указатель на буфер FixTint. }
function TintedVertices(const Mesh: TMeshData; const Tint: TVec3): Pointer;
var
  I, N: Integer;
begin
  N := Mesh.VertexCount * FLOATS_PER_VERTEX;
  SetLength(FixTint, N);
  for I := 0 to Mesh.VertexCount - 1 do
  begin
    FixTint[I * FLOATS_PER_VERTEX + 0] := Mesh.Vertices[I * FLOATS_PER_VERTEX + 0];
    FixTint[I * FLOATS_PER_VERTEX + 1] := Mesh.Vertices[I * FLOATS_PER_VERTEX + 1];
    FixTint[I * FLOATS_PER_VERTEX + 2] := Mesh.Vertices[I * FLOATS_PER_VERTEX + 2];
    FixTint[I * FLOATS_PER_VERTEX + 3] := Mesh.Vertices[I * FLOATS_PER_VERTEX + 3];
    FixTint[I * FLOATS_PER_VERTEX + 4] := Mesh.Vertices[I * FLOATS_PER_VERTEX + 4];
    FixTint[I * FLOATS_PER_VERTEX + 5] := Mesh.Vertices[I * FLOATS_PER_VERTEX + 5];
    FixTint[I * FLOATS_PER_VERTEX + 6] := Mesh.Vertices[I * FLOATS_PER_VERTEX + 6] * Tint.X;
    FixTint[I * FLOATS_PER_VERTEX + 7] := Mesh.Vertices[I * FLOATS_PER_VERTEX + 7] * Tint.Y;
    FixTint[I * FLOATS_PER_VERTEX + 8] := Mesh.Vertices[I * FLOATS_PER_VERTEX + 8] * Tint.Z;
  end;
  Result := @FixTint[0];
end;

procedure DrawItem(const Item: TRenderItem; const Mesh: TMeshData; const View: TMat4);
var
  F: TMat4F;
  Spec: array[0..3] of Single;
  Shine: Single;
  Verts: Pointer;
  Stride: LongInt;
  S: Single;
begin
  if (Mesh.IndexCount = 0) or (Mesh.VertexCount = 0) then
    Exit;
  F := Mat4ToF(Mat4Mul(View, Item.Model));
  fxLoadMatrixf(@F[0]);

  { блеск: пол без блика, остальное - по шероховатости }
  if Item.Checker then
    S := 0.0
  else
    S := 0.4 * (1.0 - Item.Roughness);
  Spec[0] := S; Spec[1] := S; Spec[2] := S; Spec[3] := 1.0;
  fxMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, @Spec[0]);
  Shine := 32.0;
  fxMaterialfv(GL_FRONT_AND_BACK, GL_SHININESS, @Shine);

  if (Item.Tint.X <> 1.0) or (Item.Tint.Y <> 1.0) or (Item.Tint.Z <> 1.0) then
    Verts := TintedVertices(Mesh, Item.Tint)
  else
    Verts := @Mesh.Vertices[0];
  Stride := FLOATS_PER_VERTEX * SizeOf(Single);

  if Item.Checker then
  begin
    fxBindTexture(GL_TEXTURE_2D, FixChecker);
    fxEnable(GL_TEXTURE_2D);
    fxEnable(GL_TEXTURE_GEN_S);
    fxEnable(GL_TEXTURE_GEN_T);
  end;
  fxEnableClientState(GL_VERTEX_ARRAY);
  fxEnableClientState(GL_NORMAL_ARRAY);
  fxEnableClientState(GL_COLOR_ARRAY);
  fxVertexPointer(3, GL_FLOAT, Stride, Verts);
  fxNormalPointer(GL_FLOAT, Stride, Pointer(PtrUInt(Verts) + 3 * SizeOf(Single)));
  fxColorPointer(3, GL_FLOAT, Stride, Pointer(PtrUInt(Verts) + 6 * SizeOf(Single)));
  fxDrawElements(GL_TRIANGLES, Mesh.IndexCount, GL_UNSIGNED_INT, @Mesh.Indices[0]);
  fxDisableClientState(GL_COLOR_ARRAY);
  fxDisableClientState(GL_NORMAL_ARRAY);
  fxDisableClientState(GL_VERTEX_ARRAY);

  if Item.Checker then
  begin
    fxDisable(GL_TEXTURE_GEN_T);
    fxDisable(GL_TEXTURE_GEN_S);
    fxDisable(GL_TEXTURE_2D);
  end;
end;

procedure FixedRender(const Cam: TRenderCamera; const Light: TRenderLight;
                      const Items: array of TRenderItem; const Meshes: array of TMeshData;
                      const Background: TVec3);
var
  View, Proj: TMat4;
  F: TMat4F;
  Pos, Diff, Spec, Amb: array[0..3] of Single;
  I: Integer;
begin
  if not FixReady then
    Exit;
  fxClearColor(Background.X, Background.Y, Background.Z, 1.0);
  fxClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);

  Proj := Mat4Perspective(Cam.FovY, FixW / FixH, Cam.ZNear, Cam.ZFar);
  View := Mat4LookAt(Cam.Eye, Cam.Target, Cam.Up);
  F := Mat4ToF(Proj);
  fxMatrixMode(GL_PROJECTION);
  fxLoadMatrixf(@F[0]);
  fxMatrixMode(GL_MODELVIEW);
  F := Mat4ToF(View);
  fxLoadMatrixf(@F[0]);

  { направленный свет: w = 0 - направление К источнику; задаётся под видовой матрицей }
  Pos[0] := Light.Direction.X; Pos[1] := Light.Direction.Y; Pos[2] := Light.Direction.Z; Pos[3] := 0.0;
  fxLightfv(GL_LIGHT0, GL_POSITION, @Pos[0]);
  Diff[0] := Light.Color.X * LIGHT_SCALE;
  Diff[1] := Light.Color.Y * LIGHT_SCALE;
  Diff[2] := Light.Color.Z * LIGHT_SCALE;
  Diff[3] := 1.0;
  fxLightfv(GL_LIGHT0, GL_DIFFUSE, @Diff[0]);
  Spec[0] := 0.25; Spec[1] := 0.25; Spec[2] := 0.25; Spec[3] := 1.0;
  fxLightfv(GL_LIGHT0, GL_SPECULAR, @Spec[0]);
  { окружающий свет: среднее сверху и снизу }
  Amb[0] := 0.6 * 0.5 * (Light.SkyColor.X + Light.GroundColor.X);
  Amb[1] := 0.6 * 0.5 * (Light.SkyColor.Y + Light.GroundColor.Y);
  Amb[2] := 0.6 * 0.5 * (Light.SkyColor.Z + Light.GroundColor.Z);
  Amb[3] := 1.0;
  fxLightModelfv(GL_LIGHT_MODEL_AMBIENT, @Amb[0]);

  for I := 0 to High(Items) do
    if (Items[I].Mesh >= 0) and (Items[I].Mesh <= High(Meshes)) then
      DrawItem(Items[I], Meshes[Items[I].Mesh], View);
  fxFinish;
end;

function FixedReadRGB(out Rgb: TFixedRgb): Boolean;
var
  Raw: array of Byte;
  X, Y, Src, Dst: Integer;
begin
  Result := False;
  SetLength(Rgb, 0);
  if not FixReady then
    Exit;
  SetLength(Raw, FixW * FixH * 4);
  fxPixelStorei(GL_PACK_ALIGNMENT, 1);
  fxReadPixels(0, 0, FixW, FixH, GL_RGBA, GL_UNSIGNED_BYTE, @Raw[0]);
  SetLength(Rgb, FixW * FixH * 3);
  { glReadPixels отдаёт строки снизу вверх (y = 0 - нижний ряд); PNG хранит сверху вниз }
  for Y := 0 to FixH - 1 do
    for X := 0 to FixW - 1 do
    begin
      Src := ((FixH - 1 - Y) * FixW + X) * 4;
      Dst := (Y * FixW + X) * 3;
      Rgb[Dst] := Raw[Src];
      Rgb[Dst + 1] := Raw[Src + 1];
      Rgb[Dst + 2] := Raw[Src + 2];
    end;
  Result := True;
end;

end.
