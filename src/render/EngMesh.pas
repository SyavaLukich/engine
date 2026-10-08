{ EngMesh - процедурная геометрия для рендеринга и отладки: коробка, сфера, капсула, плоскость.

  Формат вершин (чередование, 9 значений Single): позиция (3), нормаль (3), цвет (3).
  Индексы - треугольники (LongWord). Геометрия строится в локальной системе (центр в начале координат);
  капсула - отрезок по оси Y длиной 2*HalfSeg и радиус Radius. Классов нет. }
unit EngMesh;

{$mode objfpc}{$H+}

interface

uses
  Math, EngMath;

const
  MESH_FLOATS_PER_VERTEX = 9;

type
  TMeshData = record
    Vertices: array of Single;   { MESH_FLOATS_PER_VERTEX значений на вершину }
    Indices: array of LongWord;
    VertexCount: Integer;
    IndexCount: Integer;
  end;

procedure MeshInit(var M: TMeshData);
procedure MeshAddVertex(var M: TMeshData; const P, N: TVec3; const C: TVec3);
procedure MeshAddTriangle(var M: TMeshData; A, B, C: Integer);
function MeshBox(const Half: TVec3; const Color: TVec3): TMeshData;
function MeshSphere(Radius: Double; Slices, Stacks: Integer; const Color: TVec3): TMeshData;
function MeshCapsule(Radius, HalfSeg: Double; Slices, Rings: Integer; const Color: TVec3): TMeshData;
{ Плоскость Y = 0, квадрат со стороной 2*Half. Клетки рисует шейдер пола. }
function MeshPlane(Half: Double; const Color: TVec3): TMeshData;

implementation

procedure MeshInit(var M: TMeshData);
begin
  SetLength(M.Vertices, 0);
  SetLength(M.Indices, 0);
  M.VertexCount := 0;
  M.IndexCount := 0;
end;

procedure MeshAddVertex(var M: TMeshData; const P, N: TVec3; const C: TVec3);
var
  Base: Integer;
begin
  Base := M.VertexCount * MESH_FLOATS_PER_VERTEX;
  if Length(M.Vertices) < Base + MESH_FLOATS_PER_VERTEX then
    SetLength(M.Vertices, (M.VertexCount + 256) * MESH_FLOATS_PER_VERTEX);
  M.Vertices[Base + 0] := P.X;
  M.Vertices[Base + 1] := P.Y;
  M.Vertices[Base + 2] := P.Z;
  M.Vertices[Base + 3] := N.X;
  M.Vertices[Base + 4] := N.Y;
  M.Vertices[Base + 5] := N.Z;
  M.Vertices[Base + 6] := C.X;
  M.Vertices[Base + 7] := C.Y;
  M.Vertices[Base + 8] := C.Z;
  Inc(M.VertexCount);
end;

procedure MeshAddTriangle(var M: TMeshData; A, B, C: Integer);
begin
  if Length(M.Indices) < M.IndexCount + 3 then
    SetLength(M.Indices, M.IndexCount + 768);
  M.Indices[M.IndexCount] := A;
  M.Indices[M.IndexCount + 1] := B;
  M.Indices[M.IndexCount + 2] := C;
  Inc(M.IndexCount, 3);
end;

function MeshBox(const Half: TVec3; const Color: TVec3): TMeshData;
var
  Face, U, V, Base: Integer;
  N, Ax, Bx, P: TVec3;
  Ua, Va: Double;
begin
  MeshInit(Result);
  for Face := 0 to 5 do
  begin
    { нормаль грани и два касательных направления (по осям) }
    case Face of
      0: begin N := V3(1, 0, 0);  Ax := V3(0, 0, -1); Bx := V3(0, 1, 0); end;
      1: begin N := V3(-1, 0, 0); Ax := V3(0, 0, 1);  Bx := V3(0, 1, 0); end;
      2: begin N := V3(0, 1, 0);  Ax := V3(1, 0, 0);  Bx := V3(0, 0, -1); end;
      3: begin N := V3(0, -1, 0); Ax := V3(1, 0, 0);  Bx := V3(0, 0, 1); end;
      4: begin N := V3(0, 0, 1);  Ax := V3(1, 0, 0);  Bx := V3(0, 1, 0); end;
    else
      begin N := V3(0, 0, -1); Ax := V3(-1, 0, 0); Bx := V3(0, 1, 0); end;
    end;
    Base := Result.VertexCount;
    for V := 0 to 1 do
      for U := 0 to 1 do
      begin
        Ua := U * 2.0 - 1.0;
        Va := V * 2.0 - 1.0;
        { точка грани: полуразмер по нормали и смещения по касательным, покомпонентно }
        P.X := N.X * Half.X + Ax.X * Ua * Half.X + Bx.X * Va * Half.X;
        P.Y := N.Y * Half.Y + Ax.Y * Ua * Half.Y + Bx.Y * Va * Half.Y;
        P.Z := N.Z * Half.Z + Ax.Z * Ua * Half.Z + Bx.Z * Va * Half.Z;
        MeshAddVertex(Result, P, N, Color);
      end;
    MeshAddTriangle(Result, Base, Base + 1, Base + 3);
    MeshAddTriangle(Result, Base, Base + 3, Base + 2);
  end;
end;

function MeshSphere(Radius: Double; Slices, Stacks: Integer; const Color: TVec3): TMeshData;
var
  I, J, A, B, C, D: Integer;
  Th, Ph: Double;
  N: TVec3;
begin
  MeshInit(Result);
  for I := 0 to Stacks do
    for J := 0 to Slices do
    begin
      Th := ENG_PI * I / Stacks;
      Ph := 2.0 * ENG_PI * J / Slices;
      N := V3(Sin(Th) * Cos(Ph), Cos(Th), Sin(Th) * Sin(Ph));
      MeshAddVertex(Result, V3Mul(N, Radius), N, Color);
    end;
  for I := 0 to Stacks - 1 do
    for J := 0 to Slices - 1 do
    begin
      A := I * (Slices + 1) + J;
      B := A + Slices + 1;
      C := A + 1;
      D := B + 1;
      MeshAddTriangle(Result, A, B, C);
      MeshAddTriangle(Result, C, B, D);
    end;
end;

{ Капсула: верхняя полусфера, цилиндрическая боковина и нижняя полусфера - одна сетка строк. }
function MeshCapsule(Radius, HalfSeg: Double; Slices, Rings: Integer; const Color: TVec3): TMeshData;
var
  I, J, A, B, C, D, Rows: Integer;
  Th, Ph: Double;
  N: TVec3;
begin
  MeshInit(Result);
  { строки 0..Rings - верхняя полусфера от полюса к экватору; строки Rings+1..2*Rings+1 - нижняя }
  Rows := 2 * (Rings + 1);
  for I := 0 to Rings do
  begin
    Th := (ENG_PI / 2.0) * I / Rings;
    for J := 0 to Slices do
    begin
      Ph := 2.0 * ENG_PI * J / Slices;
      N := V3(Cos(Th) * Cos(Ph), Sin(Th), Cos(Th) * Sin(Ph));
      MeshAddVertex(Result, V3Add(V3(0, HalfSeg, 0), V3Mul(N, Radius)), N, Color);
    end;
  end;
  for I := 0 to Rings do
  begin
    Th := (ENG_PI / 2.0) * I / Rings;
    for J := 0 to Slices do
    begin
      Ph := 2.0 * ENG_PI * J / Slices;
      N := V3(Cos(Th) * Cos(Ph), -Sin(Th), Cos(Th) * Sin(Ph));
      MeshAddVertex(Result, V3Add(V3(0, -HalfSeg, 0), V3Mul(N, Radius)), N, Color);
    end;
  end;
  { полосы между соседними строками; полоса между экваторами (Rings и Rings+1) - боковина цилиндра }
  for I := 0 to Rows - 2 do
    for J := 0 to Slices - 1 do
    begin
      A := I * (Slices + 1) + J;
      B := A + Slices + 1;
      C := A + 1;
      D := B + 1;
      MeshAddTriangle(Result, A, B, C);
      MeshAddTriangle(Result, C, B, D);
    end;
end;

function MeshPlane(Half: Double; const Color: TVec3): TMeshData;
begin
  MeshInit(Result);
  MeshAddVertex(Result, V3(-Half, 0, -Half), V3(0, 1, 0), Color);
  MeshAddVertex(Result, V3(Half, 0, -Half), V3(0, 1, 0), Color);
  MeshAddVertex(Result, V3(Half, 0, Half), V3(0, 1, 0), Color);
  MeshAddVertex(Result, V3(-Half, 0, Half), V3(0, 1, 0), Color);
  MeshAddTriangle(Result, 0, 2, 1);
  MeshAddTriangle(Result, 0, 3, 2);
end;

end.
