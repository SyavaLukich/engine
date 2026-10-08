{ TestRender - проверки матриц, мешей и программного растеризатора (визуальная справка без GPU).

  Регрессия: шахматный пол должен давать несколько уровней яркости в ряду пикселей. Раньше мировые
  атрибуты интерполировались по экрану без перспективной коррекции, и весь ряд имел один уровень. }
unit TestRender;

{$mode objfpc}{$H+}

interface

procedure RunRenderTests;

implementation

uses
  SysUtils, Math, EngMath, EngMat4, EngMesh, EngRender, EngSoftRaster, TestKit;

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

procedure TestSoftRasterFloor;
var
  Img: TSoftImage;
  Cam: TRenderCamera;
  Light: TRenderLight;
  Items: array of TRenderItem;
  Meshes: array of TMeshData;
  X, Y, Lev, Levels, Covered: Integer;
  Seen: array[0..255] of Boolean;
  Fwd, Rt, UpV, Dir, Pw: TVec3;
  Tn, Asp, Nx, Ny, T: Double;
  Mn, Mx, Mid, Bad, Samples: Integer;
  Dark, WantDark: Boolean;
begin
  Section('растеризатор: шахматный пол, перспективно-корректная интерполяция');
  SetLength(Meshes, 1);
  Meshes[0] := MeshPlane(12.0, V3(0.62, 0.64, 0.66));
  SetLength(Items, 1);
  Items[0].Mesh := 0;
  Items[0].Model := Mat4Identity;
  Items[0].Tint := V3(1, 1, 1);
  Items[0].Metallic := 0;
  Items[0].Roughness := 0.9;
  Items[0].Checker := True;
  Items[0].CastShadow := False;
  Cam.Eye := V3(0, 3, 6);
  Cam.Target := V3(0, 0, 0);
  Cam.Up := V3(0, 1, 0);
  Cam.FovY := 0.7;
  Cam.ZNear := 0.1;
  Cam.ZFar := 50.0;
  Light.Direction := V3Normalize(V3(0.4, 1.0, 0.3));
  Light.Color := V3(2.4, 2.25, 2.0);
  Light.SkyColor := V3(0.45, 0.55, 0.70);
  Light.GroundColor := V3(0.20, 0.18, 0.15);
  Light.Center := V3Zero;
  Light.Extent := 4.0;
  SoftImageInit(Img, 320, 240, V3(0.07, 0.08, 0.10));
  SoftDraw(Img, Cam, Light, Items, Meshes);

  FillChar(Seen, SizeOf(Seen), 0);
  Levels := 0;
  for X := 0 to 319 do
  begin
    Lev := Img.Rgb[(200 * 320 + X) * 3];
    if not Seen[Lev] then
    begin
      Seen[Lev] := True;
      Inc(Levels);
    end;
  end;
  Check(Levels >= 2, Format('шахматка: в ряду 200 несколько уровней яркости (%d)', [Levels]));

  { нижняя половина кадра целиком занята полом: горизонт выше середины }
  Covered := 0;
  for Y := 120 to 239 do
    for X := 0 to 319 do
      if Img.Depth[Y * 320 + X] < 1.0e29 then
        Inc(Covered);
  Check(Covered >= (320 * 120) * 99 div 100,
        Format('пол покрывает нижнюю половину кадра (%d из %d пикселей)', [Covered, 320 * 120]));

  { аналитический эталон: луч через центр пикселя пересекает плоскость пола y = 0;
    тёмная клетка (альбедо 0.55) соответствует нечётной сумме floor(x) + floor(z) }
  Fwd := V3Normalize(V3Sub(Cam.Target, Cam.Eye));
  Rt := V3Normalize(V3(Fwd.Y * Cam.Up.Z - Fwd.Z * Cam.Up.Y,
                       Fwd.Z * Cam.Up.X - Fwd.X * Cam.Up.Z,
                       Fwd.X * Cam.Up.Y - Fwd.Y * Cam.Up.X));
  UpV := V3(Rt.Y * Fwd.Z - Rt.Z * Fwd.Y,
            Rt.Z * Fwd.X - Rt.X * Fwd.Z,
            Rt.X * Fwd.Y - Rt.Y * Fwd.X);
  Tn := Tan(Cam.FovY / 2);
  Asp := 320 / 240;
  Mn := 255;
  Mx := 0;
  for Y := 130 to 230 do
    for X := 0 to 319 do
    begin
      Lev := Img.Rgb[(Y * 320 + X) * 3];
      if Lev < Mn then Mn := Lev;
      if Lev > Mx then Mx := Lev;
    end;
  Mid := (Mn + Mx) div 2;
  Samples := 0;
  Bad := 0;
  for Y := 130 to 230 do
    for X := 0 to 319 do
    begin
      Nx := (X + 0.5) / 320 * 2 - 1;
      Ny := 1 - (Y + 0.5) / 240 * 2;
      Dir := V3Normalize(V3Add(V3Add(Fwd, V3Mul(Rt, Nx * Tn * Asp)), V3Mul(UpV, Ny * Tn)));
      T := -Cam.Eye.Y / Dir.Y;
      Pw := V3Add(Cam.Eye, V3Mul(Dir, T));
      WantDark := Odd(Floor(Pw.X) + Floor(Pw.Z));
      Dark := Img.Rgb[(Y * 320 + X) * 3] < Mid;
      Inc(Samples);
      if Dark <> WantDark then
        Inc(Bad);
    end;
  Check(Bad * 100 <= Samples * 2,
        Format('шахматка совпадает с аналитической разметкой пола (несовпадений %d из %d)',
               [Bad, Samples]));
end;

procedure RunRenderTests;
begin
  TestMatrices;
  TestMeshes;
  TestSoftRasterFloor;
end;

end.
