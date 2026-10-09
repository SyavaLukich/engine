{ GameLayout - содержимое уровня "Полигон": пол, стены, платформа с уступом, перила, балкон с рампой,
  укрытия, колонна турели и точки появления. Данные отделены от логики: другой уровень - другой модуль
  того же вида. Классов нет. }
unit GameLayout;

{$mode objfpc}{$H+}

interface

uses
  Math, EngMath, GameLevel, GameEnemy;

procedure LayoutYard(var L: TLevel; var Info: TLevelInfo);

implementation

procedure LayoutYard(var L: TLevel; var Info: TLevelInfo);
var
  Q: TQuat;
  A, Hx, Hy: Double;
  Wall, Stone, Metal, Crate, Warm: TVec3;
begin
  LevelInit(L);
  L.Lo := V3(-30.0, 0.0, -30.0);
  L.Hi := V3(30.0, 0.0, 30.0);
  Info.EnemyCount := 0;
  SetLength(Info.Enemies, 0);
  Info.PlayerSpawn := V3(0.0, 0.0, -20.0);

  Stone := V3(0.52, 0.53, 0.55);
  Wall := V3(0.42, 0.45, 0.50);
  Metal := V3(0.70, 0.72, 0.76);
  Crate := V3(0.55, 0.42, 0.28);
  Warm := V3(0.60, 0.50, 0.40);

  { Пол арены: верхняя грань на высоте 0. }
  LevelAddBox(L, V3(0.0, -0.5, 0.0), V3(40.0, 0.5, 40.0), QuatIdentity, LVL_KIND_SOLID, Stone);
  { Границы арены. }
  LevelAddBox(L, V3(-31.0, 4.0, 0.0), V3(1.0, 4.0, 31.0), QuatIdentity, LVL_KIND_SOLID, Wall);
  LevelAddBox(L, V3(31.0, 4.0, 0.0), V3(1.0, 4.0, 31.0), QuatIdentity, LVL_KIND_SOLID, Wall);
  LevelAddBox(L, V3(0.0, 4.0, -31.0), V3(31.0, 4.0, 1.0), QuatIdentity, LVL_KIND_SOLID, Wall);
  LevelAddBox(L, V3(0.0, 4.0, 31.0), V3(31.0, 4.0, 1.0), QuatIdentity, LVL_KIND_SOLID, Wall);
  { Стена для бега по стене: плоскость x = 5.6, высота 8 м. }
  LevelAddBox(L, V3(6.0, 4.0, 0.0), V3(0.4, 4.0, 10.0), QuatIdentity, LVL_KIND_SOLID, Warm);
  { Башня с уступом: верх на 2.0 м, грань x = -5. }
  LevelAddBox(L, V3(-8.0, 1.0, 6.0), V3(3.0, 1.0, 3.0), QuatIdentity, LVL_KIND_SOLID, Wall);
  { Перила: верх на 1.08 м, вдоль X от -8 до 4. Тонкая коробка. }
  LevelAddBox(L, V3(-2.0, 1.0, -12.0), V3(6.0, 0.08, 0.12), QuatIdentity, LVL_KIND_RAIL, Metal);
  LevelAddBox(L, V3(-8.0, 0.5, -12.0), V3(0.1, 0.5, 0.1), QuatIdentity, LVL_KIND_SOLID, Metal);
  LevelAddBox(L, V3(4.0, 0.5, -12.0), V3(0.1, 0.5, 0.1), QuatIdentity, LVL_KIND_SOLID, Metal);
  { Балкон на высоте 1.6 м и рампа к нему (наклонная коробка, поворот вокруг Z). }
  LevelAddBox(L, V3(20.0, 0.8, -6.0), V3(3.0, 0.8, 4.0), QuatIdentity, LVL_KIND_SOLID, Warm);
  A := ArcTan2(1.6, 4.0);
  Q := QuatFromAxisAngle(V3(0.0, 0.0, 1.0), A);
  Hx := 2.15;
  Hy := 0.1;
  LevelAddBox(L, V3(15.0 + Sin(A) * 0.1, 0.8 - Cos(A) * 0.1, -6.0), V3(Hx, Hy, 3.0), Q, LVL_KIND_SOLID, Warm);
  { Ящики-укрытия. }
  LevelAddBox(L, V3(-4.0, 0.5, -4.0), V3(0.5, 0.5, 0.5), QuatIdentity, LVL_KIND_SOLID, Crate);
  LevelAddBox(L, V3(3.0, 0.5, 4.0), V3(0.5, 0.5, 0.5), QuatIdentity, LVL_KIND_SOLID, Crate);
  LevelAddBox(L, V3(-12.0, 0.75, -10.0), V3(0.75, 0.75, 0.75), QuatIdentity, LVL_KIND_SOLID, Crate);
  LevelAddBox(L, V3(12.0, 0.5, 10.0), V3(0.5, 0.5, 0.5), QuatIdentity, LVL_KIND_SOLID, Crate);
  { Колонна турели: верх на 2.4 м. }
  LevelAddBox(L, V3(0.0, 1.2, 14.0), V3(0.6, 1.2, 0.6), QuatIdentity, LVL_KIND_SOLID, Stone);

  { Противники. Патрули - по клеткам сетки навигации. }
  LevelAddEnemy(Info, EN_GRUNT, V3(10.0, 0.0, 8.0), V3(10.0, 0.0, 8.0), V3(10.0, 0.0, 22.0));
  LevelAddEnemy(Info, EN_GRUNT, V3(-14.0, 0.0, -2.0), V3(-14.0, 0.0, -2.0), V3(-14.0, 0.0, 6.0));
  LevelAddEnemy(Info, EN_TURRET, V3(0.0, 2.4, 14.0), V3(0.0, 2.4, 14.0), V3(0.0, 2.4, 14.0));
end;

end.
