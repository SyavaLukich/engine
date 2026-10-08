{ EngConvex - столкновения выпуклых тел: GJK (обнаружение) и EPA (глубина и нормаль).

  Минковский: M = A - B. Если начало координат лежит внутри M, тела проникают.
  GJK ищет симплекс в M, содержащий начало координат (или доказывает разделимость).
  EPA расширяет тетраэдр на границе M до грани, ближайшей к началу координат.

  Результат CollideConvex:
    Contact.Normal - единичная нормаль ОТ B К A; сдвиг A вдоль неё на Depth разводит тела.
    Contact.PointA / PointB - точки контакта на поверхностях A и B (мировые координаты).

  Память: временные структуры GJK/EPA - фиксированные локальные массивы, без кучи.
  Куча используется только для вершин выпуклой оболочки (TConvexShape.Points). }
unit EngConvex;

{$mode objfpc}{$H+}
{$inline on}

interface

uses
  EngMath;

type
  TShapeKind = (skSphere, skBox, skHull);

  TConvexShape = record
    Kind: TShapeKind;
    Radius: Double;           { радиус сферы }
    Half: TVec3;              { полуразмеры бокса }
    Points: array of TVec3;   { вершины выпуклой оболочки в локальных координатах (skHull) }
  end;

  TPose = record
    Pos: TVec3;
    Rot: TQuat;
  end;

  TMinkPoint = record
    W: TVec3;    { PA - PB, точка разности Минковского }
    PA: TVec3;   { опорная точка A (мир) }
    PB: TVec3;   { опорная точка B (мир) }
  end;

  TContact = record
    Normal: TVec3;
    Depth: Double;
    PointA: TVec3;
    PointB: TVec3;
  end;

  TSimplex = record
    P: array[0..3] of TMinkPoint;
    N: Integer;
  end;

  TCollisionStats = record
    GJKIterations: Integer;
    EPAIterations: Integer;
    Fallbacks: Integer;   { сколько раз потребовалась запасная ветка построения тетраэдра }
  end;

function MakeSphereShape(const Radius: Double): TConvexShape;
function MakeBoxShape(const Half: TVec3): TConvexShape;
function MakeHullShape(const Points: array of TVec3): TConvexShape;
function ShapeBoundingRadius(const S: TConvexShape): Double;
{ Опорная точка формы (мировые координаты) для мирового направления Dir. }
function ShapeSupportWorld(const S: TConvexShape; const P: TPose; const Dir: TVec3): TVec3;
{ Столкновение двух выпуклых тел. Возвращает True при проникновении. }
function CollideConvex(const SA: TConvexShape; const PA: TPose;
                       const SB: TConvexShape; const PB: TPose;
                       out Contact: TContact): Boolean;
{ То же, с накоплением статистики (для бенчмарков и отладки). }
function CollideConvexStats(const SA: TConvexShape; const PA: TPose;
                            const SB: TConvexShape; const PB: TPose;
                            out Contact: TContact; var Stats: TCollisionStats): Boolean;
{ Только проверка пересечения (GJK), без EPA. }
function GJKOverlap(const SA: TConvexShape; const PA: TPose;
                    const SB: TConvexShape; const PB: TPose): Boolean;

implementation

const
  GJK_MAX_ITER = 64;
  EPA_MAX_ITER = 64;
  EPA_MAX_VERTS = 128;
  EPA_MAX_FACES = 256;
  EPA_MAX_EDGES = 256;

type
  TEPAFace = record
    I, J, K: Integer;
    N: TVec3;     { внешняя единичная нормаль }
    D: Double;    { расстояние от начала координат до плоскости грани }
    Alive: Boolean;
  end;

  TEdge = record
    A, B: Integer;
  end;

function MakeSphereShape(const Radius: Double): TConvexShape;
begin
  Result.Kind := skSphere;
  Result.Radius := Radius;
  Result.Half := V3Zero;
  SetLength(Result.Points, 0);
end;

function MakeBoxShape(const Half: TVec3): TConvexShape;
begin
  Result.Kind := skBox;
  Result.Radius := 0;
  Result.Half := Half;
  SetLength(Result.Points, 0);
end;

function MakeHullShape(const Points: array of TVec3): TConvexShape;
var
  I: Integer;
begin
  Result.Kind := skHull;
  Result.Radius := 0;
  Result.Half := V3Zero;
  SetLength(Result.Points, Length(Points));
  for I := 0 to High(Points) do
    Result.Points[I] := Points[I];
end;

function ShapeBoundingRadius(const S: TConvexShape): Double;
var
  I: Integer;
  L: Double;
begin
  case S.Kind of
    skSphere: Result := S.Radius;
    skBox: Result := V3Length(S.Half);
  else
    begin
      Result := 0;
      for I := 0 to High(S.Points) do
      begin
        L := V3Length(S.Points[I]);
        if L > Result then
          Result := L;
      end;
    end;
  end;
end;

{ Опорная точка в локальных координатах формы для локального направления D. }
function SupportLocal(const S: TConvexShape; const D: TVec3): TVec3;
var
  I, Best: Integer;
  Dot, BestDot, L: Double;
begin
  case S.Kind of
    skSphere:
      begin
        L := V3Length(D);
        if L < ENG_EPS then
          Result := V3(S.Radius, 0, 0)
        else
          Result := V3Mul(D, S.Radius / L);
      end;
    skBox:
      begin
        if D.X >= 0 then Result.X := S.Half.X else Result.X := -S.Half.X;
        if D.Y >= 0 then Result.Y := S.Half.Y else Result.Y := -S.Half.Y;
        if D.Z >= 0 then Result.Z := S.Half.Z else Result.Z := -S.Half.Z;
      end;
  else
    begin
      Best := 0;
      BestDot := V3Dot(S.Points[0], D);
      for I := 1 to High(S.Points) do
      begin
        Dot := V3Dot(S.Points[I], D);
        if Dot > BestDot then
        begin
          BestDot := Dot;
          Best := I;
        end;
      end;
      Result := S.Points[Best];
    end;
  end;
end;

function ShapeSupportWorld(const S: TConvexShape; const P: TPose; const Dir: TVec3): TVec3;
begin
  Result := V3Add(P.Pos, QuatRotate(P.Rot, SupportLocal(S, QuatInvRotate(P.Rot, Dir))));
end;

{ Опорная точка разности Минковского A - B в направлении Dir. }
function MinkSupport(const SA: TConvexShape; const PA: TPose;
                     const SB: TConvexShape; const PB: TPose;
                     const Dir: TVec3): TMinkPoint;
begin
  Result.PA := ShapeSupportWorld(SA, PA, Dir);
  Result.PB := ShapeSupportWorld(SB, PB, V3Neg(Dir));
  Result.W := V3Sub(Result.PA, Result.PB);
end;

{ Ближайшая к началу координат точка треугольника (a, b, c) (алгоритм Эриксона, p = 0).
  Feature - маска признака: 1 вершина a, 2 - b, 4 - c, 3 - ребро ab, 5 - ac, 6 - bc, 7 - внутренность. }
procedure ClosestOnTriangle(const A, B, C: TVec3; out Closest: TVec3; out Feature: Integer);
var
  AB, AC, AP, BP, CP: TVec3;
  D1, D2, D3, D4, D5, D6, Va, Vb, Vc, Denom, T, U, V, W: Double;
begin
  AB := V3Sub(B, A);
  AC := V3Sub(C, A);
  AP := V3Neg(A);
  D1 := V3Dot(AB, AP);
  D2 := V3Dot(AC, AP);
  if (D1 <= 0) and (D2 <= 0) then
  begin
    Closest := A;
    Feature := 1;
    Exit;
  end;
  BP := V3Neg(B);
  D3 := V3Dot(AB, BP);
  D4 := V3Dot(AC, BP);
  if (D3 >= 0) and (D4 <= D3) then
  begin
    Closest := B;
    Feature := 2;
    Exit;
  end;
  Vc := D1 * D4 - D3 * D2;
  if (Vc <= 0) and (D1 >= 0) and (D3 <= 0) then
  begin
    T := D1 / (D1 - D3);
    Closest := V3MulAdd(A, AB, T);
    Feature := 3;
    Exit;
  end;
  CP := V3Neg(C);
  D5 := V3Dot(AB, CP);
  D6 := V3Dot(AC, CP);
  if (D6 >= 0) and (D5 <= D6) then
  begin
    Closest := C;
    Feature := 4;
    Exit;
  end;
  Vb := D5 * D2 - D1 * D6;
  if (Vb <= 0) and (D2 >= 0) and (D6 <= 0) then
  begin
    T := D2 / (D2 - D6);
    Closest := V3MulAdd(A, AC, T);
    Feature := 5;
    Exit;
  end;
  Va := D3 * D6 - D5 * D4;
  if (Va <= 0) and ((D4 - D3) >= 0) and ((D5 - D6) >= 0) then
  begin
    T := (D4 - D3) / ((D4 - D3) + (D5 - D6));
    Closest := V3MulAdd(B, V3Sub(C, B), T);
    Feature := 6;
    Exit;
  end;
  Denom := 1.0 / (Va + Vb + Vc);
  V := Vb * Denom;
  W := Vc * Denom;
  U := 1.0 - V - W;
  Closest := V3Add(V3Mul(A, U), V3Add(V3Mul(B, V), V3Mul(C, W)));
  Feature := 7;
end;

{ Оставляет в симплексе вершины, заданные маской признака (порядок T0, T1, T2). }
procedure KeepByMask(var S: TSimplex; const Mask: Integer;
                     const T0, T1, T2: TMinkPoint);
begin
  S.N := 0;
  if (Mask and 1) <> 0 then
  begin
    S.P[S.N] := T0;
    Inc(S.N);
  end;
  if (Mask and 2) <> 0 then
  begin
    S.P[S.N] := T1;
    Inc(S.N);
  end;
  if (Mask and 4) <> 0 then
  begin
    S.P[S.N] := T2;
    Inc(S.N);
  end;
end;

{ Уменьшает симплекс до минимального подмножества, содержащего ближайшую к началу точку
  (Closest). Возвращает True, если начало координат лежит внутри тетраэдра (тела пересекаются). }
function ReduceSimplex(var S: TSimplex; out Closest: TVec3): Boolean;
var
  A, B, AB, AO: TVec3;
  T, Dist: Double;
  Feature, I, J, K, BestFeature: Integer;
  Tri, BestTri: array[0..2] of TMinkPoint;
  Cand, BestCand, Nrm, Opp: TVec3;
  BestDist: Double;
  Inside: Boolean;
begin
  Result := False;
  case S.N of
    1:
      Closest := S.P[0].W;
    2:
      begin
        A := S.P[0].W;
        B := S.P[1].W;
        AB := V3Sub(B, A);
        AO := V3Neg(A);
        Dist := V3LengthSq(AB);
        if Dist < ENG_EPS then
        begin
          S.N := 1;
          Closest := A;
        end
        else
        begin
          T := V3Dot(AB, AO) / Dist;
          if T <= 0 then
          begin
            S.N := 1;
            Closest := A;
          end
          else if T >= 1 then
          begin
            S.P[0] := S.P[1];
            S.N := 1;
            Closest := B;
          end
          else
            Closest := V3MulAdd(A, AB, T);
        end;
      end;
    3:
      begin
        ClosestOnTriangle(S.P[0].W, S.P[1].W, S.P[2].W, Closest, Feature);
        KeepByMask(S, Feature, S.P[0], S.P[1], S.P[2]);
      end;
  else
    begin
      { Четыре вершины. Грань без вершины I; её внешняя нормаль направлена от вершины I.
        Если начало координат с внешней стороны грани, ищем ближайшую точку на этой грани. }
      Inside := True;
      BestDist := 1e300;
      BestFeature := 0;
      BestCand := V3Zero;
      for I := 0 to 3 do
      begin
        K := 0;
        for J := 0 to 3 do
          if J <> I then
          begin
            Tri[K] := S.P[J];
            Inc(K);
          end;
        Opp := S.P[I].W;
        Nrm := V3Cross(V3Sub(Tri[1].W, Tri[0].W), V3Sub(Tri[2].W, Tri[0].W));
        if V3Dot(Nrm, V3Sub(Opp, Tri[0].W)) > 0 then
          Nrm := V3Neg(Nrm);
        if V3Dot(Nrm, V3Neg(Tri[0].W)) > 0 then
        begin
          Inside := False;
          ClosestOnTriangle(Tri[0].W, Tri[1].W, Tri[2].W, Cand, Feature);
          Dist := V3LengthSq(Cand);
          if Dist < BestDist then
          begin
            BestDist := Dist;
            BestCand := Cand;
            BestFeature := Feature;
            BestTri[0] := Tri[0];
            BestTri[1] := Tri[1];
            BestTri[2] := Tri[2];
          end;
        end;
      end;
      if Inside then
      begin
        Closest := V3Zero;
        Result := True;
      end
      else
      begin
        Closest := BestCand;
        KeepByMask(S, BestFeature, BestTri[0], BestTri[1], BestTri[2]);
      end;
    end;
  end;
end;

{ Достраивает симплекс до тетраэдра, если он вырожден (меньше 4 вершин).
  Возвращает False, если невозможно (тела касаются вырожденно). }
function EnsureTetrahedron(const SA: TConvexShape; const PA: TPose;
                           const SB: TConvexShape; const PB: TPose;
                           var S: TSimplex; var Stats: TCollisionStats): Boolean;
const
  Axes: array[0..5] of TVec3 = (
    (X: 1; Y: 0; Z: 0), (X: -1; Y: 0; Z: 0),
    (X: 0; Y: 1; Z: 0), (X: 0; Y: -1; Z: 0),
    (X: 0; Y: 0; Z: 1), (X: 0; Y: 0; Z: -1));

  function TryAdd(const D: TVec3): Boolean;
  var
    Q: TMinkPoint;
    K: Integer;
    Vol: Double;
  begin
    Result := False;
    if V3LengthSq(D) < ENG_EPS then
      Exit;
    Q := MinkSupport(SA, PA, SB, PB, D);
    for K := 0 to S.N - 1 do
      if V3LengthSq(V3Sub(Q.W, S.P[K].W)) < 1e-18 then
        Exit;
    if S.N = 2 then
    begin
      Vol := V3LengthSq(V3Cross(V3Sub(S.P[1].W, S.P[0].W), V3Sub(Q.W, S.P[0].W)));
      if Vol < 1e-18 then
        Exit;
    end
    else if S.N = 3 then
    begin
      Vol := Abs(V3Dot(V3Cross(V3Sub(S.P[1].W, S.P[0].W), V3Sub(S.P[2].W, S.P[0].W)),
                       V3Sub(Q.W, S.P[0].W)));
      if Vol < 1e-12 then
        Exit;
    end;
    S.P[S.N] := Q;
    Inc(S.N);
    Result := True;
  end;

var
  I: Integer;
  Dir, N: TVec3;
begin
  Inc(Stats.Fallbacks);
  for I := 0 to High(Axes) do
    if S.N < 2 then
      TryAdd(Axes[I]);
  if S.N = 2 then
  begin
    Dir := V3Normalize(V3Sub(S.P[1].W, S.P[0].W));
    for I := 0 to High(Axes) do
      if S.N < 3 then
      begin
        N := V3Cross(Dir, Axes[I]);
        if V3LengthSq(N) > ENG_EPS then
        begin
          TryAdd(N);
          if S.N < 3 then
            TryAdd(V3Neg(N));
        end;
      end;
  end;
  if S.N = 3 then
  begin
    N := V3Normalize(V3Cross(V3Sub(S.P[1].W, S.P[0].W), V3Sub(S.P[2].W, S.P[0].W)));
    TryAdd(N);
    if S.N = 3 then
      TryAdd(V3Neg(N));
  end;
  Result := S.N = 4;
end;

{ EPA: расширяет политоп до грани, ближайшей к началу координат, и возвращает контакт. }
function EPARun(const SA: TConvexShape; const PA: TPose;
                const SB: TConvexShape; const PB: TPose;
                const S: TSimplex; out Contact: TContact;
                var Stats: TCollisionStats): Boolean;
var
  V: array[0..EPA_MAX_VERTS - 1] of TMinkPoint;
  F: array[0..EPA_MAX_FACES - 1] of TEPAFace;
  Edges: array[0..EPA_MAX_EDGES - 1] of TEdge;
  NV, NF, NE, Iter, I, Best, Slot: Integer;
  Converged, Found: Boolean;
  BestD, Tol, Dist, Den, WJ, WK, D00, D01, D11, D20, D21, Bu, Bv, Bw: Double;
  P: TMinkPoint;
  N, Q, E1, E2, Pt, PointA, PointB, Ref: TVec3;
  Fc: TEPAFace;

  function MakeFace(const A, B, C: Integer): TEPAFace;
  var
    Nn, Cr: TVec3;
  begin
    Cr := V3Cross(V3Sub(V[B].W, V[A].W), V3Sub(V[C].W, V[A].W));
    Result.I := A;
    Result.J := B;
    Result.K := C;
    Result.Alive := True;
    if V3LengthSq(Cr) < 1e-24 then
    begin
      { вырожденная грань (три коллинеарные точки) никогда не должна стать ближайшей }
      Result.N := V3Zero;
      Result.D := 1e300;
      Exit;
    end;
    Nn := V3Normalize(Cr);
    { Ориентация по внутренней точке Ref (центроид начального тетраэдра): она всегда строго
      внутри растущего политопа, в отличие от начала координат, которое может лежать на грани. }
    if V3Dot(Nn, V3Sub(Ref, V[A].W)) > 0 then
    begin
      Nn := V3Neg(Nn);
      Result.J := C;
      Result.K := B;
    end;
    Result.N := Nn;
    Result.D := MaxD(0, V3Dot(Nn, V[A].W));
  end;

  procedure AddFace(const Fa: TEPAFace);
  var
    K: Integer;
  begin
    Slot := -1;
    for K := 0 to NF - 1 do
      if not F[K].Alive then
      begin
        Slot := K;
        Break;
      end;
    if Slot < 0 then
    begin
      if NF >= EPA_MAX_FACES then
        Exit;
      Slot := NF;
      Inc(NF);
    end;
    F[Slot] := Fa;
  end;

  procedure AddEdge(const A, B: Integer);
  var
    K: Integer;
  begin
    { если обратное ребро уже в списке - оно внутреннее для видимой области и удаляется }
    for K := 0 to NE - 1 do
      if (Edges[K].A = B) and (Edges[K].B = A) then
      begin
        Edges[K] := Edges[NE - 1];
        Dec(NE);
        Exit;
      end;
    if NE < EPA_MAX_EDGES then
    begin
      Edges[NE].A := A;
      Edges[NE].B := B;
      Inc(NE);
    end;
  end;

begin
  Result := False;
  FillChar(Contact, SizeOf(Contact), 0);
  if S.N <> 4 then
    Exit;
  NV := 4;
  for I := 0 to 3 do
    V[I] := S.P[I];
  Ref := V3Mul(V3Add(V3Add(V[0].W, V[1].W), V3Add(V[2].W, V[3].W)), 0.25);
  NF := 0;
  NE := 0;
  AddFace(MakeFace(0, 1, 2));
  AddFace(MakeFace(0, 3, 1));
  AddFace(MakeFace(0, 2, 3));
  AddFace(MakeFace(1, 3, 2));

  Tol := 1e-9;
  Converged := False;
  Best := -1;
  BestD := 0;
  for Iter := 0 to EPA_MAX_ITER - 1 do
  begin
    Inc(Stats.EPAIterations);
    Found := False;
    for I := 0 to NF - 1 do
      if F[I].Alive and ((not Found) or (F[I].D < BestD)) then
      begin
        Found := True;
        BestD := F[I].D;
        Best := I;
      end;
    if not Found then
      Exit;
    Fc := F[Best];
    N := Fc.N;
    P := MinkSupport(SA, PA, SB, PB, N);
    Dist := V3Dot(P.W, N);
    if (Dist - Fc.D < Tol) or (NV >= EPA_MAX_VERTS) then
    begin
      Converged := True;
      Break;
    end;
    { добавляем вершину и перестраиваем политоп по горизонту видимости }
    V[NV] := P;
    I := NV;
    Inc(NV);
    NE := 0;
    { Грань видима, если точка P строго над ней или на её плоскости (с допуском). Компланарные
      соседи тоже удаляются: иначе новые грани оказались бы вырожденными из-за коллинеарности
      точек Минковского при симметричных конфигурациях. }
    Tol := 1e-10 * (1.0 + V3Length(P.W));
    for Best := 0 to NF - 1 do
      if F[Best].Alive and (V3Dot(F[Best].N, V3Sub(P.W, V[F[Best].I].W)) > -Tol) then
      begin
        F[Best].Alive := False;
        AddEdge(F[Best].I, F[Best].J);
        AddEdge(F[Best].J, F[Best].K);
        AddEdge(F[Best].K, F[Best].I);
      end;
    for Best := 0 to NE - 1 do
      AddFace(MakeFace(Edges[Best].A, Edges[Best].B, I));
  end;

  if not Converged then
  begin
    { итерации исчерпаны: используем ближайшую живую грань }
    Found := False;
    for I := 0 to NF - 1 do
      if F[I].Alive and ((not Found) or (F[I].D < BestD)) then
      begin
        Found := True;
        BestD := F[I].D;
        Best := I;
      end;
    if not Found then
      Exit;
  end;

  Fc := F[Best];
  N := Fc.N;
  { барикоординаты проекции начала координат на грань (I, J, K) }
  Q := V3Mul(N, Fc.D);
  E1 := V3Sub(V[Fc.J].W, V[Fc.I].W);
  E2 := V3Sub(V[Fc.K].W, V[Fc.I].W);
  D00 := V3Dot(E1, E1);
  D01 := V3Dot(E1, E2);
  D11 := V3Dot(E2, E2);
  Den := D00 * D11 - D01 * D01;
  Pt := V3Sub(Q, V[Fc.I].W);
  D20 := V3Dot(Pt, E1);
  D21 := V3Dot(Pt, E2);
  if Abs(Den) < ENG_EPS then
  begin
    Bu := 1.0 / 3.0;
    Bv := 1.0 / 3.0;
    Bw := 1.0 / 3.0;
  end
  else
  begin
    WJ := ClampD((D11 * D20 - D01 * D21) / Den, 0, 1);
    WK := ClampD((D00 * D21 - D01 * D20) / Den, 0, 1);
    if WJ + WK > 1 then
    begin
      Dist := WJ + WK;
      WJ := WJ / Dist;
      WK := WK / Dist;
    end;
    Bv := WJ;
    Bw := WK;
    Bu := 1.0 - Bv - Bw;
  end;
  PointA := V3Add(V3Mul(V[Fc.I].PA, Bu), V3Add(V3Mul(V[Fc.J].PA, Bv), V3Mul(V[Fc.K].PA, Bw)));
  PointB := V3Add(V3Mul(V[Fc.I].PB, Bu), V3Add(V3Mul(V[Fc.J].PB, Bv), V3Mul(V[Fc.K].PB, Bw)));

  Contact.Normal := V3Neg(N);   { от B к A }
  Contact.Depth := Fc.D;
  Contact.PointA := PointA;
  Contact.PointB := PointB;
  Result := True;
end;

{ GJK: ищет симплекс, содержащий начало координат. Возвращает True при пересечении. }
function GJKRun(const SA: TConvexShape; const PA: TPose;
                const SB: TConvexShape; const PB: TPose;
                out S: TSimplex; var Stats: TCollisionStats): Boolean;
var
  Dir, Closest: TVec3;
  P: TMinkPoint;
  Iter, K: Integer;
  Lsq, Prog: Double;
begin
  Result := False;
  S.N := 1;
  Dir := V3Sub(PB.Pos, PA.Pos);
  if V3LengthSq(Dir) < ENG_EPS then
    Dir := V3(1, 0, 0);
  S.P[0] := MinkSupport(SA, PA, SB, PB, Dir);
  Closest := S.P[0].W;
  for Iter := 0 to GJK_MAX_ITER - 1 do
  begin
    Inc(Stats.GJKIterations);
    Lsq := V3LengthSq(Closest);
    if Lsq < ENG_EPS * ENG_EPS then
    begin
      Result := True;
      Break;
    end;
    Dir := V3Neg(Closest);
    P := MinkSupport(SA, PA, SB, PB, Dir);
    { прогресс: если опорная точка не уходит дальше ближайшей, тела разделены }
    Prog := Lsq - V3Dot(P.W, Closest);
    if (Prog <= 1e-12 * (1.0 + Lsq)) or (S.N >= 4) then
      Exit;
    for K := S.N downto 1 do
      S.P[K] := S.P[K - 1];
    S.P[0] := P;
    Inc(S.N);
    if ReduceSimplex(S, Closest) then
    begin
      Result := True;
      Break;
    end;
  end;
  if Result and (S.N < 4) then
    Result := EnsureTetrahedron(SA, PA, SB, PB, S, Stats);
end;

function CollideSpheres(const SA: TConvexShape; const PA: TPose;
                        const SB: TConvexShape; const PB: TPose;
                        out Contact: TContact): Boolean;
var
  D: TVec3;
  Dist, SumR: Double;
begin
  D := V3Sub(PA.Pos, PB.Pos);
  Dist := V3Length(D);
  SumR := SA.Radius + SB.Radius;
  Result := Dist < SumR;
  if not Result then
    Exit;
  if Dist < ENG_EPS then
  begin
    Contact.Normal := V3(0, 1, 0);
    Dist := 0;
  end
  else
    Contact.Normal := V3Mul(D, 1.0 / Dist);
  Contact.Depth := SumR - Dist;
  Contact.PointA := V3MulAdd(PA.Pos, Contact.Normal, -SA.Radius);
  Contact.PointB := V3MulAdd(PB.Pos, Contact.Normal, SB.Radius);
end;

function CollideConvexStats(const SA: TConvexShape; const PA: TPose;
                            const SB: TConvexShape; const PB: TPose;
                            out Contact: TContact; var Stats: TCollisionStats): Boolean;
var
  S: TSimplex;
begin
  FillChar(Contact, SizeOf(Contact), 0);
  if (SA.Kind = skSphere) and (SB.Kind = skSphere) then
  begin
    Result := CollideSpheres(SA, PA, SB, PB, Contact);
    Exit;
  end;
  Result := GJKRun(SA, PA, SB, PB, S, Stats);
  if Result then
    Result := EPARun(SA, PA, SB, PB, S, Contact, Stats);
end;

function CollideConvex(const SA: TConvexShape; const PA: TPose;
                       const SB: TConvexShape; const PB: TPose;
                       out Contact: TContact): Boolean;
var
  Stats: TCollisionStats;
begin
  FillChar(Stats, SizeOf(Stats), 0);
  Result := CollideConvexStats(SA, PA, SB, PB, Contact, Stats);
end;

function GJKOverlap(const SA: TConvexShape; const PA: TPose;
                    const SB: TConvexShape; const PB: TPose): Boolean;
var
  S: TSimplex;
  Stats: TCollisionStats;
begin
  if (SA.Kind = skSphere) and (SB.Kind = skSphere) then
  begin
    Result := V3Distance(PA.Pos, PB.Pos) < SA.Radius + SB.Radius;
    Exit;
  end;
  FillChar(Stats, SizeOf(Stats), 0);
  Result := GJKRun(SA, PA, SB, PB, S, Stats);
end;

end.
