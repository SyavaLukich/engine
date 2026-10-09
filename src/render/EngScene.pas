{ EngScene - описание сцены для рендереров: элемент, камера и источник света.

  Общие типы для рендерера OpenGL 4.3 (EngRender) и снимков через OSMesa с фиксированным
  конвейером OpenGL 2.x (EngFixedGL). Так снимки не зависят от шейдерного рендерера.
  Классов нет. }
unit EngScene;

{$mode objfpc}{$H+}

interface

uses
  EngMath, EngMat4;

type
  TRenderItem = record
    Mesh: Integer;            { индекс меша в массиве мешей }
    Model: TMat4;
    Tint: TVec3;              { умножается на цвет вершин }
    Emission: TVec3;          { собственное свечение, линейная яркость (трассеры, вспышки) }
    Metallic: Double;
    Roughness: Double;
    Checker: Boolean;         { шахматный рисунок пола; такие элементы не отбрасывают тень }
    CastShadow: Boolean;
  end;

  TRenderCamera = record
    Eye: TVec3;
    Target: TVec3;
    Up: TVec3;
    FovY: Double;             { рад }
    ZNear: Double;
    ZFar: Double;
  end;

  TRenderLight = record
    Direction: TVec3;         { единичный вектор К источнику света }
    Color: TVec3;             { линейная яркость }
    SkyColor: TVec3;          { окружающий свет сверху }
    GroundColor: TVec3;       { окружающий свет снизу }
    Center: TVec3;            { центр сцены, вокруг которого строится карта теней }
    Extent: Double;           { полуразмер области теней, м }
  end;

implementation

end.
