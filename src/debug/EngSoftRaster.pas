{ EngSoftRaster - программный растеризатор для визуальной проверки без GPU.

  Назначение: получить изображение сцены в PNG там, где OpenGL недоступен (сборка и проверка
  на машине без драйвера). Рисует те же элементы, что EngRender: треугольники мешей, матрицы вида
  и проекции, z-буфер, освещение (Ламберт, блик Блинна-Фонга, полусферический свет), тонемаппинг ACES,
  гамма 2.2 и шахматный пол.

  Конвейер:
  - отсечение по ближней плоскости OpenGL z + w >= 0 в однородных координатах (Sutherland-Hodgman).
    Для стандартной перспективной матрицы этого достаточно: точки за камерой в полупространство
    z + w >= 0 не попадают;
  - растеризация по экранным барицентрическим координатам с перспективно-корректной интерполяцией:
    мировая позиция, нормаль и цвет делятся на w, интерполируются, затем делятся на интерполированное
    1/w. Величина 1/w и глубина z_ndc аффинны по экрану, поэтому их интерполяция линейна.

  НЕ воспроизводит тени и GGX-шейдер GPU: это справочная картинка геометрии, поз и цветов. }
unit EngSoftRaster;

{$mode objfpc}{$H+}

interface

uses
  Math, EngMath, EngMat4, EngMesh, EngRender, EngPNG;

type
  TSoftImage = record
    Width: Integer;
    Height: Integer;
    Rgb: TByteBuf;            { RGB сверху вниз }
    Depth: array of Single;   { глубина в NDC }
  end;

procedure SoftImageInit(var Img: TSoftImage; W, H: Integer; const Bg: TVec3);
procedure SoftDraw(var Img: TSoftImage; const Cam: TRenderCamera; const Light: TRenderLight;
                   const Items: array of TRenderItem; const Meshes: array of TMeshData);

implementation

type
  { Вершина в однородных координатах с атрибутами в мире. }
  TClipV = record
    Cx, Cy, Cz, Cw: Double;
    Wp: TVec3;
    Nv: TVec3;
    Cv: TVec3;
  end;

  { Вершина экрана. Wp, Nv, Cv хранятся, делённые на w; Iw = 1/w. }
  TScreenV = record
    Sx, Sy, Sz: Double;
    Iw: Double;
    Wp: TVec3;
    Nv: TVec3;
    Cv: TVec3;
  end;

procedure SoftImageInit(var Img: TSoftImage; W, H: Integer; const Bg: TVec3);
var
  I: Integer;
begin
  Img.Width := W;
  Img.Height := H;
  SetLength(Img.Rgb, W * H * 3);
  SetLength(Img.Depth, W * H);
  for I := 0 to W * H - 1 do
  begin
    Img.Rgb[I * 3 + 0] := Round(ClampD(Bg.X, 0, 1) * 255);
    Img.Rgb[I * 3 + 1] := Round(ClampD(Bg.Y, 0, 1) * 255);
    Img.Rgb[I * 3 + 2] := Round(ClampD(Bg.Z, 0, 1) * 255);
    Img.Depth[I] := 1.0e30;
  end;
end;

function Aces(X: Double): Double;
begin
  Result := ClampD((X * (2.51 * X + 0.03)) / (X * (2.43 * X + 0.59) + 0.14), 0, 1);
end;

{ Затенение пикселя по мировой позиции, нормали и цвету (как в mesh.frag, без теней). }
procedure Shade(const Cam: TRenderCamera; const Light: TRenderLight; const Item: TRenderItem;
                const P, N0, C0: TVec3; out Result_: TVec3);
var
  N, V, L, H, Albedo: TVec3;
  NdL, NdH, Spec, Shin, Hemi, Rough: Double;
  Amb, Lit: TVec3;
begin
  N := V3Normalize(N0);
  V := V3Normalize(V3Sub(Cam.Eye, P));
  L := V3Normalize(Light.Direction);
  Albedo := V3(C0.X * Item.Tint.X, C0.Y * Item.Tint.Y, C0.Z * Item.Tint.Z);
  if Item.Checker then
  begin
    if Odd(Floor(P.X) + Floor(P.Z)) then
      Albedo := V3Mul(Albedo, 0.55)
    else
      Albedo := V3Mul(Albedo, 0.85);
  end;
  NdL := MaxD(V3Dot(N, L), 0);
  H := V3Normalize(V3Add(L, V));
  NdH := MaxD(V3Dot(N, H), 0);
  Rough := Max(0.04, Item.Roughness);
  Shin := 2.0 / (Rough * Rough) - 2.0;
  Spec := Power(NdH, Shin) * (0.04 + 0.96 * Item.Metallic) * 0.5;
  Hemi := N.Y * 0.5 + 0.5;
  Amb := V3Add(V3Mul(Light.GroundColor, 1 - Hemi), V3Mul(Light.SkyColor, Hemi));
  { диффузная часть Lambert и блик делятся на PI - как в mesh.frag (kd * albedo / PI) }
  Lit := V3Mul(Light.Color, NdL * (1 - Item.Metallic) / PI);
  Result_.X := Power(Aces(Albedo.X * Lit.X + Light.Color.X * Spec / PI + Amb.X * Albedo.X * (1 - 0.5 * Item.Metallic)), 1 / 2.2);
  Result_.Y := Power(Aces(Albedo.Y * Lit.Y + Light.Color.Y * Spec / PI + Amb.Y * Albedo.Y * (1 - 0.5 * Item.Metallic)), 1 / 2.2);
  Result_.Z := Power(Aces(Albedo.Z * Lit.Z + Light.Color.Z * Spec / PI + Amb.Z * Albedo.Z * (1 - 0.5 * Item.Metallic)), 1 / 2.2);
end;

procedure DrawTriangle(var Img: TSoftImage; const Cam: TRenderCamera; const Light: TRenderLight;
                       const Item: TRenderItem; const A, B, C: TScreenV);
var
  MinX, MaxX, MinY, MaxY, X, Y: Integer;
  Area, W0, W1, W2, Z, Iw, Inv: Double;
  Pix: Integer;
  Pw, Nw, Cw, Col: TVec3;
begin
  Area := (B.Sx - A.Sx) * (C.Sy - A.Sy) - (B.Sy - A.Sy) * (C.Sx - A.Sx);
  if Abs(Area) < 1e-12 then Exit;
  MinX := Max(0, Floor(MinD(A.Sx, MinD(B.Sx, C.Sx))));
  MaxX := Min(Img.Width - 1, Ceil(MaxD(A.Sx, MaxD(B.Sx, C.Sx))));
  MinY := Max(0, Floor(MinD(A.Sy, MinD(B.Sy, C.Sy))));
  MaxY := Min(Img.Height - 1, Ceil(MaxD(A.Sy, MaxD(B.Sy, C.Sy))));
  for Y := MinY to MaxY do
    for X := MinX to MaxX do
    begin
      { барицентрические координаты экранного треугольника в центре пикселя }
      W0 := ((B.Sx - X - 0.5) * (C.Sy - Y - 0.5) - (B.Sy - Y - 0.5) * (C.Sx - X - 0.5)) / Area;
      W1 := ((C.Sx - X - 0.5) * (A.Sy - Y - 0.5) - (C.Sy - Y - 0.5) * (A.Sx - X - 0.5)) / Area;
      W2 := 1.0 - W0 - W1;
      if (W0 < -1e-9) or (W1 < -1e-9) or (W2 < -1e-9) then Continue;
      Z := W0 * A.Sz + W1 * B.Sz + W2 * C.Sz;
      Pix := Y * Img.Width + X;
      if Z >= Img.Depth[Pix] then Continue;
      Img.Depth[Pix] := Z;
      { перспективно-корректная интерполяция атрибутов: sum(w_i * a_i / w_i) / sum(w_i / w_i) }
      Iw := W0 * A.Iw + W1 * B.Iw + W2 * C.Iw;
      Inv := 1.0 / Iw;
      Pw := V3Mul(V3Add(V3Add(V3Mul(A.Wp, W0), V3Mul(B.Wp, W1)), V3Mul(C.Wp, W2)), Inv);
      Nw := V3Mul(V3Add(V3Add(V3Mul(A.Nv, W0), V3Mul(B.Nv, W1)), V3Mul(C.Nv, W2)), Inv);
      Cw := V3Mul(V3Add(V3Add(V3Mul(A.Cv, W0), V3Mul(B.Cv, W1)), V3Mul(C.Cv, W2)), Inv);
      Shade(Cam, Light, Item, Pw, Nw, Cw, Col);
      Img.Rgb[Pix * 3 + 0] := Round(ClampD(Col.X, 0, 1) * 255);
      Img.Rgb[Pix * 3 + 1] := Round(ClampD(Col.Y, 0, 1) * 255);
      Img.Rgb[Pix * 3 + 2] := Round(ClampD(Col.Z, 0, 1) * 255);
    end;
end;

{ Отсечение по ближней плоскости z + w >= 0 (Sutherland-Hodgman). Треугольник -> до 4 вершин. }
procedure ClipNear(const Inp: array of TClipV; NIn: Integer; var Outp: array of TClipV; var NOut: Integer);
var
  I: Integer;
  A, B, P: TClipV;
  Da, Db, T: Double;
begin
  NOut := 0;
  for I := 0 to NIn - 1 do
  begin
    A := Inp[I];
    B := Inp[(I + 1) mod NIn];
    Da := A.Cz + A.Cw;
    Db := B.Cz + B.Cw;
    if Da >= 0 then
    begin
      Outp[NOut] := A;
      Inc(NOut);
    end;
    if (Da >= 0) <> (Db >= 0) then
    begin
      T := Da / (Da - Db);
      P.Cx := A.Cx + (B.Cx - A.Cx) * T;
      P.Cy := A.Cy + (B.Cy - A.Cy) * T;
      P.Cz := A.Cz + (B.Cz - A.Cz) * T;
      P.Cw := A.Cw + (B.Cw - A.Cw) * T;
      P.Wp := V3Lerp(A.Wp, B.Wp, T);
      P.Nv := V3Lerp(A.Nv, B.Nv, T);
      P.Cv := V3Lerp(A.Cv, B.Cv, T);
      Outp[NOut] := P;
      Inc(NOut);
    end;
  end;
end;

{ Перевод однородной вершины в экранную с перспективным делением. False, если вершина не перед камерой. }
function ToScreen(const C: TClipV; Width, Height: Integer; out S: TScreenV): Boolean;
begin
  Result := C.Cw > 1e-9;
  if not Result then Exit;
  S.Iw := 1.0 / C.Cw;
  S.Sx := (C.Cx * S.Iw * 0.5 + 0.5) * Width;
  S.Sy := (1.0 - (C.Cy * S.Iw * 0.5 + 0.5)) * Height;
  S.Sz := C.Cz * S.Iw;
  S.Wp := V3Mul(C.Wp, S.Iw);
  S.Nv := V3Mul(C.Nv, S.Iw);
  S.Cv := V3Mul(C.Cv, S.Iw);
end;

procedure SoftDraw(var Img: TSoftImage; const Cam: TRenderCamera; const Light: TRenderLight;
                   const Items: array of TRenderItem; const Meshes: array of TMeshData);
var
  View, Proj, VP, Pm: TMat4;
  I, T, K, Mi, Base, NPoly, F: Integer;
  Tri: array[0..2] of TClipV;
  Poly: array[0..5] of TClipV;
  S0, S1, S2: TScreenV;
  Loc: TVec3;
  Wp, Nv: TVec3;
  M: TMeshData;
begin
  View := Mat4LookAt(Cam.Eye, Cam.Target, Cam.Up);
  Proj := Mat4Perspective(Cam.FovY, Img.Width / Max(1, Img.Height), Cam.ZNear, Cam.ZFar);
  VP := Mat4Mul(Proj, View);
  for I := 0 to High(Items) do
  begin
    Mi := Items[I].Mesh;
    if (Mi < 0) or (Mi > High(Meshes)) then Continue;
    M := Meshes[Mi];
    Pm := Items[I].Model;
    for T := 0 to M.IndexCount div 3 - 1 do
    begin
      for K := 0 to 2 do
      begin
        Base := Integer(M.Indices[T * 3 + K]) * MESH_FLOATS_PER_VERTEX;
        Loc := V3(M.Vertices[Base], M.Vertices[Base + 1], M.Vertices[Base + 2]);
        Wp := Mat4MulPoint(Pm, Loc);
        { нормаль: матрица модели без переноса (жёсткие преобразования) }
        Nv := V3(Pm.M[0] * M.Vertices[Base + 3] + Pm.M[4] * M.Vertices[Base + 4] + Pm.M[8] * M.Vertices[Base + 5],
                 Pm.M[1] * M.Vertices[Base + 3] + Pm.M[5] * M.Vertices[Base + 4] + Pm.M[9] * M.Vertices[Base + 5],
                 Pm.M[2] * M.Vertices[Base + 3] + Pm.M[6] * M.Vertices[Base + 4] + Pm.M[10] * M.Vertices[Base + 5]);
        Tri[K].Wp := Wp;
        Tri[K].Nv := Nv;
        Tri[K].Cv := V3(M.Vertices[Base + 6], M.Vertices[Base + 7], M.Vertices[Base + 8]);
        Tri[K].Cx := VP.M[0] * Wp.X + VP.M[4] * Wp.Y + VP.M[8] * Wp.Z + VP.M[12];
        Tri[K].Cy := VP.M[1] * Wp.X + VP.M[5] * Wp.Y + VP.M[9] * Wp.Z + VP.M[13];
        Tri[K].Cz := VP.M[2] * Wp.X + VP.M[6] * Wp.Y + VP.M[10] * Wp.Z + VP.M[14];
        Tri[K].Cw := VP.M[3] * Wp.X + VP.M[7] * Wp.Y + VP.M[11] * Wp.Z + VP.M[15];
      end;
      ClipNear(Tri, 3, Poly, NPoly);
      if NPoly < 3 then Continue;
      if not ToScreen(Poly[0], Img.Width, Img.Height, S0) then Continue;
      for F := 1 to NPoly - 2 do
      begin
        if not ToScreen(Poly[F], Img.Width, Img.Height, S1) then Continue;
        if not ToScreen(Poly[F + 1], Img.Width, Img.Height, S2) then Continue;
        DrawTriangle(Img, Cam, Light, Items[I], S0, S1, S2);
      end;
    end;
  end;
end;

end.
