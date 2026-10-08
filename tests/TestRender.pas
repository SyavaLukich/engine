{ TestRender - проверки матриц, мешей и программного растеризатора (визуальная справка без GPU).

  Регрессия: шахматный пол должен давать несколько уровней яркости в ряду пикселей. Раньше мировые
  атрибуты интерполировались по экрану без перспективной коррекции, и весь ряд имел один уровень. }
unit TestRender;

{$mode objfpc}{$H+}

interface

procedure RunRenderTests;

implementation

uses
  SysUtils, Math, EngMath, EngMat4, EngMesh, EngScene, EngRender, EngFixedGL, TestKit;

procedure TestMatrices;
var
  M, Inv, Prod, Ident, View, Proj: TMat4;
  Q: TQuat;
  Eye, Target, Up, P: TVec3;
  Err, Cz, Cw, D, Yt: Double;
  I: Integer;
begin
  Section('матрицы: обратная, lookAt, перспектива');
  { поворот вокруг Y на 0.8 рад, неравномерный масштаб }
  Q.X := 0;
  Q.Y := Sin(0.4);
  Q.Z := 0;
  Q.W := Cos(0.4);
  M := Mat4FromRT(V3(1.5, -2.0, 3.0), Q, V3(2.0, 0.5, 1.0));
  Inv := Mat4Inverse(M);
  Prod := Mat4Mul(Inv, M);
  Ident := Mat4Identity;
  Err := 0;
  for I := 0 to 15 do
    Err := Max(Err, Abs(Prod.M[I] - Ident.M[I]));
  Check(Err < 1e-9, Format('обратная матрица: M^-1 * M = I (ошибка %.2e)', [Err]));

  Eye := V3(0, 2, 6);
  Target := V3(0, 0, 0);
  Up := V3(0, 1, 0);
  View := Mat4LookAt(Eye, Target, Up);
  P := Mat4MulPoint(View, Eye);
  CheckNear(V3Length(P), 0, 1e-9, 'lookAt: глаз переходит в начало координат');
  P := Mat4MulPoint(View, Target);
  CheckNear(P.X, 0, 1e-9, 'lookAt: цель на оси X');
  CheckNear(P.Y, 0, 1e-9, 'lookAt: цель на оси Y');
  CheckNear(P.Z, -V3Length(V3Sub(Target, Eye)), 1e-9, 'lookAt: цель на -Z на расстоянии взгляда');

  Proj := Mat4Perspective(Pi / 3, 4.0 / 3.0, 0.1, 50.0);
  { точка на ближней плоскости -> NDC z = -1, на дальней -> +1 (соглашение OpenGL) }
  Cz := Proj.M[10] * (-0.1) + Proj.M[14];
  Cw := Proj.M[11] * (-0.1) + Proj.M[15];
  CheckNear(Cz / Cw, -1, 1e-9, 'перспектива: ближняя плоскость -> NDC z = -1');
  Cz := Proj.M[10] * (-50.0) + Proj.M[14];
  Cw := Proj.M[11] * (-50.0) + Proj.M[15];
  CheckNear(Cz / Cw, 1, 1e-9, 'перспектива: дальняя плоскость -> NDC z = +1');
  { верхний край поля зрения на расстоянии 5 -> NDC y = 1 }
  D := 5.0;
  Yt := Tan(Pi / 6) * D;
  Cz := Proj.M[5] * Yt + Proj.M[9] * (-D) + Proj.M[13];
  Cw := Proj.M[7] * Yt + Proj.M[11] * (-D) + Proj.M[15];
  CheckNear(Cz / Cw, 1, 1e-9, 'перспектива: верхний край поля зрения -> NDC y = 1');
end;

procedure CheckMesh(const M: TMeshData; const Name: string);
var
  I, Bad: Integer;
begin
  Bad := 0;
  for I := 0 to M.IndexCount - 1 do
    if Integer(M.Indices[I]) >= M.VertexCount then
      Inc(Bad);
  Check((M.IndexCount > 0) and (M.IndexCount mod 3 = 0) and (Bad = 0),
        Format('меш %s: индексы в пределах вершин, треугольники полные (вершин %d, индексов %d)',
               [Name, M.VertexCount, M.IndexCount]));
end;

procedure TestMeshes;
var
  Col: TVec3;
begin
  Section('меши: индексы и полнота треугольников');
  Col := V3(1, 1, 1);
  CheckMesh(MeshBox(V3(0.5, 0.5, 0.5), Col), 'box');
  CheckMesh(MeshSphere(0.5, 16, 12, Col), 'sphere');
  CheckMesh(MeshCapsule(0.1, 0.3, 16, 6, Col), 'capsule');
  CheckMesh(MeshPlane(12.0, Col), 'plane');
end;

{ Пол через OpenGL 2.x (OSMesa): камера строго сверху, поэтому пиксель -> точка пола - аффинное
  отображение. Клетка пола с чётной суммой индексов (floor(x)+floor(z)) тёмная, с нечётной светлая.
  Проверка ловит ошибку масштаба клетки, переворот строк при чтении кадра и неверные каналы текстуры
  (все три канала RGB должны давать одно и то же отношение светлой и тёмной клетки).
  Если библиотека OSMesa не найдена, проверка пропускается (не считается ошибкой). }
procedure TestFixedFloor;
const
  TW = 320;
  TH = 240;
  DIST = 10.0;
var
  Cam: TRenderCamera;
  Light: TRenderLight;
  Items: array of TRenderItem;
  Meshes: array of TMeshData;
  Rgb: TFixedRgb;
  Lib: string;
  X, Y, C, Bad, Samples, Pix, Sum, MinS, MaxS, Mid: Integer;
  MinC, MaxC: array[0..2] of Integer;
  HalfH, HalfW, Nx, Ny, Wx, Wz, Fx, Fz, Dx, Dz: Double;
  RR, GR, BR: Double;
  WantLight, IsLight, Skip: Boolean;
begin
  Section('OpenGL 2.x через OSMesa: шахматный пол и порядок строк кадра');
  Lib := GetEnvironmentVariable('ENGINE_OSMESA');
  if Lib = '' then
  begin
{$IFDEF WINDOWS}
    Lib := 'osmesa.dll';
{$ELSE}
    Lib := 'libosmesa.so';
{$ENDIF}
  end;
  if not FixedInit(Lib, TW, TH) then
  begin
    WriteLn('  пропущено: ', FixedLastError);
    WriteLn('  (укажите библиотеку переменной ENGINE_OSMESA; сборка osmesa-main: docs/OSMESA.md)');
    Exit;
  end;
  WriteLn('  OpenGL: ', FixedVersion);

  SetLength(Meshes, 1);
  Meshes[0] := MeshPlane(12.0, V3(0.8, 0.8, 0.8));
  SetLength(Items, 1);
  Items[0].Mesh := 0;
  Items[0].Model := Mat4Identity;
  Items[0].Tint := V3(1, 1, 1);
  Items[0].Metallic := 0;
  Items[0].Roughness := 0.9;
  Items[0].Checker := True;
  Items[0].CastShadow := False;

  Cam.Eye := V3(0, DIST, 0);
  Cam.Target := V3Zero;
  Cam.Up := V3(0, 0, -1);
  Cam.FovY := 0.7;
  Cam.ZNear := 0.1;
  Cam.ZFar := 50.0;
  Light.Direction := V3(0, 1, 0);
  Light.Color := V3(1, 1, 1);
  Light.SkyColor := V3(0.3, 0.3, 0.3);
  Light.GroundColor := V3(0.3, 0.3, 0.3);
  Light.Center := V3Zero;
  Light.Extent := 4.0;

  FixedRender(Cam, Light, Items, Meshes, V3(0.07, 0.08, 0.10));
  Check(FixedReadRGB(Rgb), 'кадр прочитан через glReadPixels');
  if Length(Rgb) <> TW * TH * 3 then
  begin
    FixedShutdown;
    Exit;
  end;

  { уровни: тёмная и светлая клетки - минимум и максимум кадра (пол закрывает весь кадр) }
  for C := 0 to 2 do
  begin
    MinC[C] := 255;
    MaxC[C] := 0;
  end;
  MinS := 765;
  MaxS := 0;
  for Pix := 0 to TW * TH - 1 do
  begin
    Sum := 0;
    for C := 0 to 2 do
    begin
      if Rgb[Pix * 3 + C] < MinC[C] then MinC[C] := Rgb[Pix * 3 + C];
      if Rgb[Pix * 3 + C] > MaxC[C] then MaxC[C] := Rgb[Pix * 3 + C];
      Sum := Sum + Rgb[Pix * 3 + C];
    end;
    if Sum < MinS then MinS := Sum;
    if Sum > MaxS then MaxS := Sum;
  end;
  Mid := (MinS + MaxS) div 2;
  RR := MaxC[0] / Max(1, MinC[0]);
  GR := MaxC[1] / Max(1, MinC[1]);
  BR := MaxC[2] / Max(1, MinC[2]);
  Check((Abs(RR - 217.0 / 140.0) < 0.03) and (Abs(GR - 217.0 / 140.0) < 0.03) and
        (Abs(BR - 217.0 / 140.0) < 0.03),
        Format('каналы R,G,B: отношение светлой и тёмной клетки %.3f / %.3f / %.3f (ожидается %.3f)',
               [RR, GR, BR, 217.0 / 140.0]));

  HalfH := DIST * Tan(Cam.FovY / 2);
  HalfW := HalfH * TW / TH;
  Dx := 2 * HalfW / TW;
  Dz := 2 * HalfH / TH;
  Bad := 0;
  Samples := 0;
  for Y := 0 to TH - 1 do
    for X := 0 to TW - 1 do
    begin
      { центр пикселя; строка Y = 0 - верхняя (камера: верх кадра - это -z) }
      Nx := (X + 0.5) / TW * 2 - 1;
      Ny := 1 - (Y + 0.5) / TH * 2;
      Wx := Nx * HalfW;
      Wz := -Ny * HalfH;
      Fx := Wx - Floor(Wx);
      Fz := Wz - Floor(Wz);
      Skip := (Fx < Dx) or (Fx > 1 - Dx) or (Fz < Dz) or (Fz > 1 - Dz);
      if Skip then
        Continue;
      WantLight := Odd(Floor(Wx) + Floor(Wz));
      Sum := Rgb[(Y * TW + X) * 3] + Rgb[(Y * TW + X) * 3 + 1] + Rgb[(Y * TW + X) * 3 + 2];
      IsLight := Sum > Mid;
      Inc(Samples);
      if IsLight <> WantLight then
        Inc(Bad);
    end;
  Check((Bad = 0) and (Samples > 0),
        Format('клетки пола совпадают с аналитической разметкой (несовпадений %d из %d)',
               [Bad, Samples]));
  FixedShutdown;
end;

procedure RunRenderTests;
begin
  TestMatrices;
  TestMeshes;
  TestFixedFloor;
end;

end.
