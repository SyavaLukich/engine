{ GameNav - навигация врагов: сетка высот по верхним поверхностям уровня и поиск пути A*.
  Высота клетки - верхняя поверхность, которую видит луч сверху. Переход между соседними клетками
  возможен, если подъём не больше NAV_STEP. Стены и платформы без рампы непроходимы. Классов нет. }
unit GameNav;

{$mode objfpc}{$H+}

interface

uses
  Math, EngMath, GameLevel;

const
  NAV_STEP = 0.45;            { наибольший подъём между соседними клетками, м (совпадает с BODY_STEP_UP) }
  NAV_BLOCKED = -1.0e9;       { клетка непроходима }
  NAV_MAX_HEIGHT = 3.0;       { верхние поверхности выше этого - стены, а не полы }

type
  TNavGrid = record
    Lo: TVec3;                { угол сетки (координаты X и Z) }
    Cell: Double;             { размер клетки, м }
    W: Integer;
    H: Integer;
    Height: array of Double;  { высота поверхности в центре клетки или NAV_BLOCKED }
    Stamp: array of Integer;  { номер запроса, в котором клетка открыта }
    Closed: array of Integer; { номер запроса, в котором клетка закрыта }
    Parent: array of Integer;
    Cost: array of Double;
    HeapKey: array of Double;
    HeapVal: array of Integer;
    HeapSize: Integer;
    Query: Integer;
  end;

  TNavPath = record
    Count: Integer;
    Points: array of TVec3;   { центры клеток от старта к цели }
    Index: Integer;           { текущая точка для агента }
  end;

procedure NavBuild(var G: TNavGrid; const L: TLevel; Cell: Double);
{ Клетка, ближайшая к точке (в пределах трёх клеток), в которой можно стоять. }
function NavNearestWalkable(const G: TNavGrid; const P: TVec3; out Cx, Cz: Integer): Boolean;
function NavCellCenter(const G: TNavGrid; Cx, Cz: Integer): TVec3;
function NavFindPath(var G: TNavGrid; const FromPos, ToPos: TVec3; var Path: TNavPath): Boolean;
function NavWalkable(const G: TNavGrid; Cx, Cz: Integer): Boolean;

implementation

const
  DIR_X: array[0..7] of Integer = (1, -1, 0, 0, 1, -1, 1, -1);
  DIR_Z: array[0..7] of Integer = (0, 0, 1, -1, 1, 1, -1, -1);

function NavWalkable(const G: TNavGrid; Cx, Cz: Integer): Boolean;
begin
  Result := (Cx >= 0) and (Cz >= 0) and (Cx < G.W) and (Cz < G.H) and
            (G.Height[Cz * G.W + Cx] > NAV_BLOCKED / 2);
end;

function NavCellCenter(const G: TNavGrid; Cx, Cz: Integer): TVec3;
begin
  Result.X := G.Lo.X + (Cx + 0.5) * G.Cell;
  Result.Z := G.Lo.Z + (Cz + 0.5) * G.Cell;
  if NavWalkable(G, Cx, Cz) then
    Result.Y := G.Height[Cz * G.W + Cx]
  else
    Result.Y := 0.0;
end;

procedure NavBuild(var G: TNavGrid; const L: TLevel; Cell: Double);
var
  I, J, K: Integer;
  X, Z: Double;
  Hit: TRayHit;
begin
  G.Cell := Cell;
  G.Lo := L.Lo;
  G.W := Max(1, Trunc((L.Hi.X - L.Lo.X) / Cell + 0.5));
  G.H := Max(1, Trunc((L.Hi.Z - L.Lo.Z) / Cell + 0.5));
  K := G.W * G.H;
  SetLength(G.Height, K);
  SetLength(G.Stamp, K);
  SetLength(G.Closed, K);
  SetLength(G.Parent, K);
  SetLength(G.Cost, K);
  SetLength(G.HeapKey, 8 * K + 8);
  SetLength(G.HeapVal, 8 * K + 8);
  G.HeapSize := 0;
  G.Query := 0;
  for K := 0 to G.W * G.H - 1 do
  begin
    G.Stamp[K] := 0;
    G.Closed[K] := 0;
  end;
  for J := 0 to G.H - 1 do
    for I := 0 to G.W - 1 do
    begin
      X := G.Lo.X + (I + 0.5) * Cell;
      Z := G.Lo.Z + (J + 0.5) * Cell;
      Hit := LevelRayCast(L, V3(X, 40.0, Z), V3(0, -1, 0), 80.0);
      if Hit.Hit and (Hit.Normal.Y >= 0.7) and (Hit.Point.Y <= NAV_MAX_HEIGHT) then
        G.Height[J * G.W + I] := Hit.Point.Y
      else
        G.Height[J * G.W + I] := NAV_BLOCKED;
    end;
end;

function NavNearestWalkable(const G: TNavGrid; const P: TVec3; out Cx, Cz: Integer): Boolean;
var
  Ci, Cj, R, I, J, Best: Integer;
  D, BestD: Double;
  C: TVec3;
begin
  Result := False;
  Ci := Trunc((P.X - G.Lo.X) / G.Cell);
  Cj := Trunc((P.Z - G.Lo.Z) / G.Cell);
  if Ci < 0 then Ci := 0;
  if Cj < 0 then Cj := 0;
  if Ci >= G.W then Ci := G.W - 1;
  if Cj >= G.H then Cj := G.H - 1;
  BestD := 1.0e30;
  Best := -1;
  for R := 0 to 3 do
    for J := Cj - R to Cj + R do
      for I := Ci - R to Ci + R do
        if NavWalkable(G, I, J) and ((Abs(I - Ci) = R) or (Abs(J - Cj) = R)) then
        begin
          C := NavCellCenter(G, I, J);
          D := Sqr(C.X - P.X) + Sqr(C.Z - P.Z);
          if D < BestD then
          begin
            BestD := D;
            Best := J * G.W + I;
          end;
        end;
  if Best >= 0 then
  begin
    Cx := Best mod G.W;
    Cz := Best div G.W;
    Result := True;
  end;
end;

{ Двоичная куча (минимум по ключу). Старые записи удаляются лениво. }
procedure HeapPush(var G: TNavGrid; Key: Double; Val: Integer);
var
  I, P: Integer;
  TK: Double;
  TV: Integer;
begin
  I := G.HeapSize;
  G.HeapKey[I] := Key;
  G.HeapVal[I] := Val;
  Inc(G.HeapSize);
  while I > 0 do
  begin
    P := (I - 1) div 2;
    if G.HeapKey[P] <= G.HeapKey[I] then Break;
    TK := G.HeapKey[P];
    G.HeapKey[P] := G.HeapKey[I];
    G.HeapKey[I] := TK;
    TV := G.HeapVal[P];
    G.HeapVal[P] := G.HeapVal[I];
    G.HeapVal[I] := TV;
    I := P;
  end;
end;

function HeapPop(var G: TNavGrid): Integer;
var
  I, C, Last: Integer;
  TK: Double;
  TV: Integer;
begin
  Result := G.HeapVal[0];
  Dec(G.HeapSize);
  Last := G.HeapSize;
  if Last <= 0 then Exit;
  G.HeapKey[0] := G.HeapKey[Last];
  G.HeapVal[0] := G.HeapVal[Last];
  I := 0;
  while True do
  begin
    C := 2 * I + 1;
    if C >= Last then Break;
    if (C + 1 < Last) and (G.HeapKey[C + 1] < G.HeapKey[C]) then Inc(C);
    if G.HeapKey[I] <= G.HeapKey[C] then Break;
    TK := G.HeapKey[C];
    G.HeapKey[C] := G.HeapKey[I];
    G.HeapKey[I] := TK;
    TV := G.HeapVal[C];
    G.HeapVal[C] := G.HeapVal[I];
    G.HeapVal[I] := TV;
    I := C;
  end;
end;

{ Октильная эвристика: точна для восьми направлений. }
function Heuristic(const G: TNavGrid; Idx, Goal: Integer): Double;
var
  DX, DZ: Double;
begin
  DX := Abs((Idx mod G.W) - (Goal mod G.W));
  DZ := Abs((Idx div G.W) - (Goal div G.W));
  Result := Max(DX, DZ) + 0.41421356 * Min(DX, DZ);
end;

function NavFindPath(var G: TNavGrid; const FromPos, ToPos: TVec3; var Path: TNavPath): Boolean;
var
  Sx, Sz, Gx, Gz, Start, Goal, Cur, K, NX, NZ, NI, Count, I: Integer;
  Ng, Step: Double;
  Found: Boolean;
  Rev: array of TVec3;
begin
  Result := False;
  Path.Count := 0;
  Path.Index := 0;
  if not NavNearestWalkable(G, FromPos, Sx, Sz) then Exit;
  if not NavNearestWalkable(G, ToPos, Gx, Gz) then Exit;
  Start := Sz * G.W + Sx;
  Goal := Gz * G.W + Gx;
  Inc(G.Query);
  G.HeapSize := 0;
  G.Stamp[Start] := G.Query;
  G.Cost[Start] := 0.0;
  G.Parent[Start] := -1;
  HeapPush(G, Heuristic(G, Start, Goal), Start);
  Found := False;
  while G.HeapSize > 0 do
  begin
    Cur := HeapPop(G);
    if G.Closed[Cur] = G.Query then Continue;
    G.Closed[Cur] := G.Query;
    if Cur = Goal then
    begin
      Found := True;
      Break;
    end;
    for K := 0 to 7 do
    begin
      NX := (Cur mod G.W) + DIR_X[K];
      NZ := (Cur div G.W) + DIR_Z[K];
      if not NavWalkable(G, NX, NZ) then Continue;
      NI := NZ * G.W + NX;
      if Abs(G.Height[NI] - G.Height[Cur]) > NAV_STEP then Continue;
      if (DIR_X[K] <> 0) and (DIR_Z[K] <> 0) then
      begin
        { По диагонали нельзя срезать угол стены. }
        if not NavWalkable(G, (Cur mod G.W) + DIR_X[K], Cur div G.W) then Continue;
        if not NavWalkable(G, Cur mod G.W, (Cur div G.W) + DIR_Z[K]) then Continue;
      end;
      if G.Closed[NI] = G.Query then Continue;
      if DIR_X[K] * DIR_Z[K] <> 0 then Step := 1.41421356 else Step := 1.0;
      Ng := G.Cost[Cur] + Step;
      if (G.Stamp[NI] <> G.Query) or (Ng < G.Cost[NI]) then
      begin
        G.Stamp[NI] := G.Query;
        G.Cost[NI] := Ng;
        G.Parent[NI] := Cur;
        HeapPush(G, Ng + Heuristic(G, NI, Goal), NI);
      end;
    end;
  end;
  if not Found then Exit;
  Count := 0;
  Cur := Goal;
  while Cur >= 0 do
  begin
    Inc(Count);
    Cur := G.Parent[Cur];
  end;
  SetLength(Rev, Count);
  Cur := Goal;
  I := Count - 1;
  while Cur >= 0 do
  begin
    Rev[I] := NavCellCenter(G, Cur mod G.W, Cur div G.W);
    Dec(I);
    Cur := G.Parent[Cur];
  end;
  SetLength(Path.Points, Count);
  for I := 0 to Count - 1 do
    Path.Points[I] := Rev[I];
  Path.Count := Count;
  Result := True;
end;

end.
