{ GameRender - визуальный слой игры: меши уровня и фигур, позы по состоянию игрока и врагов,
  трассеры (с собственным свечением для блума) и интерфейс. Читает состояние мира, ничего в нём
  не меняет. Классов нет. }
unit GameRender;

{$mode objfpc}{$H+}

interface

uses
  Math, EngMath, EngMat4, EngMesh, EngScene, EngRender, EngHud, GameLevel, GameBody, GamePlayer,
  GameEnemy, GameWorld;

type
  TVisual = record
    LevelMesh: array of Integer;   { по коробкам уровня }
    FloorMesh: Integer;            { шахматный рисунок пола }
    Torso: Integer;
    Head: Integer;
    Limb: Integer;                 { капсула: ноги и руки }
    Foot: Integer;
    Gun: Integer;
    TurretBody: Integer;
    TurretBarrel: Integer;
    Streak: Integer;               { трассер: отрезок длиной 2 м }
    Count: Integer;                { число элементов, отправленных в кадр }
  end;

{ Загрузка мешей в GPU. Вызывать после RenderInit. }
procedure VisualInit(var V: TVisual; var R: TRenderer; const W: TWorld);
{ Элементы кадра. Items должен иметь достаточную длину (VisualMaxItems). }
procedure VisualBuild(var V: TVisual; const W: TWorld; var Items: array of TRenderItem);
function VisualMaxItems(const W: TWorld): Integer;
procedure VisualCamera(const W: TWorld; out Cam: TRenderCamera; out Light: TRenderLight);
procedure HudBuild(var H: THud; const W: TWorld; WinW, WinH: Integer);

implementation

const
  TINT_PLAYER_SUIT: TVec3 = (X: 0.20; Y: 0.42; Z: 0.80);
  TINT_PLAYER_SKIN: TVec3 = (X: 0.92; Y: 0.76; Z: 0.62);
  TINT_PLAYER_LEG: TVec3 = (X: 0.14; Y: 0.15; Z: 0.20);
  TINT_ENEMY_SUIT: TVec3 = (X: 0.42; Y: 0.12; Z: 0.10);
  TINT_ENEMY_SKIN: TVec3 = (X: 0.60; Y: 0.58; Z: 0.55);
  TINT_ENEMY_LEG: TVec3 = (X: 0.10; Y: 0.10; Z: 0.11);
  TINT_GUN: TVec3 = (X: 0.08; Y: 0.08; Z: 0.09);

{ Точка в локальной системе фигуры переводится в мировую: поворот корня, затем смещение. }
function RootPoint(const RootPos: TVec3; const RootRot: TQuat; const P: TVec3): TVec3;
begin
  Result := V3Add(RootPos, QuatRotate(RootRot, P));
end;

{ Часть фигуры: сустав Pivot, поворот сустава LocalRot, смещение центра части Offset от сустава. }
procedure PartItem(var It: TRenderItem; Mesh: Integer; const RootPos: TVec3; const RootRot: TQuat;
                   const Pivot: TVec3; const LocalRot: TQuat; const Offset: TVec3; const Tint: TVec3);
var
  Pos: TVec3;
  Rot: TQuat;
begin
  Pos := RootPoint(RootPos, RootRot, V3Add(Pivot, QuatRotate(LocalRot, Offset)));
  Rot := QuatMul(RootRot, LocalRot);
  It.Mesh := Mesh;
  It.Model := Mat4FromRT(Pos, Rot, V3(1.0, 1.0, 1.0));
  It.Tint := Tint;
  It.Emission := V3Zero;
  It.Metallic := 0.0;
  It.Roughness := 0.7;
  It.Checker := False;
  It.CastShadow := True;
end;

procedure SimpleItem(var It: TRenderItem; Mesh: Integer; const Pos: TVec3; const Rot: TQuat;
                     const Tint: TVec3; Roughness: Double; Metallic: Double);
begin
  It.Mesh := Mesh;
  It.Model := Mat4FromRT(Pos, Rot, V3(1.0, 1.0, 1.0));
  It.Tint := Tint;
  It.Emission := V3Zero;
  It.Metallic := Metallic;
  It.Roughness := Roughness;
  It.Checker := False;
  It.CastShadow := True;
end;

function RX(Angle: Double): TQuat;
begin
  Result := QuatFromAxisAngle(V3(1.0, 0.0, 0.0), Angle);
end;

function RZ(Angle: Double): TQuat;
begin
  Result := QuatFromAxisAngle(V3(0.0, 0.0, 1.0), Angle);
end;

function RY(Angle: Double): TQuat;
begin
  Result := QuatFromAxisAngle(V3(0.0, 1.0, 0.0), Angle);
end;

{ Фигура персонажа или врага. Центр корня - центр капсулы, подошвы на -BODY_FEET.
  Pose: 0 - стоит/идёт, 1 - в воздухе, 2 - висит на уступе, 3 - стреляет, 4 - лежит, 5 - бег по стене,
  6 - подкат, 7 - удар сверху, 8 - замах. Phase - фаза шага. }
procedure BuildFigure(var V: TVisual; var Items: array of TRenderItem; var N: Integer;
                      const CenterPos: TVec3; Yaw, Flip, Lean: Double; FlipAxis: Integer;
                      Pose: Integer; Phase, Swing: Double; Suit, Skin, Leg: TVec3; WithGun: Boolean);
var
  RootRot, FlipQ, LeanQ, YawQ: TQuat;
  LegA, ArmA, ArmB: Double;
  Pivot: TVec3;
begin
  YawQ := RY(Yaw);
  case FlipAxis of
    1: FlipQ := RX(-Flip);
    2: FlipQ := RX(Flip);
    3: FlipQ := RZ(Flip);
  else
    FlipQ := QuatIdentity;
  end;
  LeanQ := RZ(Lean);
  RootRot := QuatMul(YawQ, QuatMul(FlipQ, LeanQ));
  LegA := Sin(Phase) * Swing;
  ArmA := -Sin(Phase) * Swing;
  ArmB := Sin(Phase) * Swing;
  case Pose of
    1:
      begin
        LegA := 0.35;
        ArmA := 2.6;
        ArmB := 2.6;
      end;
    2:
      begin
        LegA := 0.25;
        ArmA := 2.9;
        ArmB := 2.9;
      end;
    3:
      begin
        ArmA := 1.45;
        ArmB := 1.25;
      end;
    5:
      begin
        LegA := Sin(Phase) * Swing * 0.6;
        ArmA := 0.6;
        ArmB := -0.6;
      end;
    6:
      begin
        LegA := 1.1;
        ArmA := 2.2;
        ArmB := 2.2;
      end;
    7:
      begin
        LegA := 0.2;
        ArmA := 2.8;
        ArmB := 2.8;
      end;
    8:
      begin
        ArmA := 2.7;
        ArmB := 1.0;
      end;
  end;
  { Торс, голова, ноги, стопы, руки. }
  PartItem(Items[N], V.Torso, CenterPos, RootRot, V3(0.0, 0.05, 0.0), QuatIdentity, V3Zero, Suit);
  Inc(N);
  PartItem(Items[N], V.Head, CenterPos, RootRot, V3(0.0, 0.6, 0.0), QuatIdentity, V3Zero, Skin);
  Inc(N);
  Pivot := V3(-0.13, -0.45, 0.0);
  PartItem(Items[N], V.Limb, CenterPos, RootRot, Pivot, RX(LegA), V3(0.0, -0.27, 0.0), Leg);
  Inc(N);
  PartItem(Items[N], V.Foot, CenterPos, RootRot, V3(-0.13, -0.8, 0.0), RX(LegA), V3(0.0, 0.0, 0.05), Leg);
  Inc(N);
  Pivot := V3(0.13, -0.45, 0.0);
  PartItem(Items[N], V.Limb, CenterPos, RootRot, Pivot, RX(-LegA), V3(0.0, -0.27, 0.0), Leg);
  Inc(N);
  PartItem(Items[N], V.Foot, CenterPos, RootRot, V3(0.13, -0.8, 0.0), RX(-LegA), V3(0.0, 0.0, 0.05), Leg);
  Inc(N);
  Pivot := V3(-0.33, 0.2, 0.0);
  PartItem(Items[N], V.Limb, CenterPos, RootRot, Pivot, RX(ArmA), V3(0.0, -0.2, 0.0), Suit);
  Inc(N);
  Pivot := V3(0.33, 0.2, 0.0);
  PartItem(Items[N], V.Limb, CenterPos, RootRot, Pivot, RX(ArmB), V3(0.0, -0.2, 0.0), Suit);
  Inc(N);
  if WithGun then
  begin
    PartItem(Items[N], V.Gun, CenterPos, RootRot, V3(0.33, 0.0, 0.0), RX(ArmB), V3(0.0, 0.0, 0.2), TINT_GUN);
    Inc(N);
  end;
end;

procedure VisualInit(var V: TVisual; var R: TRenderer; const W: TWorld);
var
  I: Integer;
  White: TVec3;
begin
  White := V3(1.0, 1.0, 1.0);
  SetLength(V.LevelMesh, W.Level.Count);
  for I := 0 to W.Level.Count - 1 do
    V.LevelMesh[I] := RenderUploadMesh(R, MeshBox(W.Level.Boxes[I].Half, W.Level.Boxes[I].Color));
  V.FloorMesh := RenderUploadMesh(R, MeshPlane(40.0, V3(1.0, 1.0, 1.0)));
  V.Torso := RenderUploadMesh(R, MeshBox(V3(0.24, 0.28, 0.16), White));
  V.Head := RenderUploadMesh(R, MeshSphere(0.2, 16, 12, White));
  V.Limb := RenderUploadMesh(R, MeshCapsule(0.1, 0.22, 12, 6, White));
  V.Foot := RenderUploadMesh(R, MeshBox(V3(0.12, 0.06, 0.2), White));
  V.Gun := RenderUploadMesh(R, MeshBox(V3(0.05, 0.05, 0.2), White));
  V.TurretBody := RenderUploadMesh(R, MeshBox(V3(0.5, 0.3, 0.3), White));
  V.TurretBarrel := RenderUploadMesh(R, MeshBox(V3(0.05, 0.05, 0.4), White));
  V.Streak := RenderUploadMesh(R, MeshBox(V3(0.02, 0.02, 1.0), White));
  V.Count := 0;
end;

function VisualMaxItems(const W: TWorld): Integer;
begin
  Result := W.Level.Count + 1 + 12 + W.EnemyCount * 12 + WORLD_MAX_TRACERS + 8;
end;

procedure VisualBuild(var V: TVisual; const W: TWorld; var Items: array of TRenderItem);
var
  I, N: Integer;
  Phase, Speed, Swing: Double;
  Pose: Integer;
  Lean, Flip: Double;
  Dir, Mid: TVec3;
  Ln: Double;
  Q: TQuat;
  Axis: TVec3;
  Ang: Double;
  CenterP: TVec3;
begin
  N := 0;
  for I := 0 to W.Level.Count - 1 do
  begin
    SimpleItem(Items[N], V.LevelMesh[I], W.Level.Boxes[I].Center, W.Level.Boxes[I].Rot, V3(1.0, 1.0, 1.0),
               0.55, 0.0);
    if W.Level.Boxes[I].Kind = LVL_KIND_RAIL then
      SimpleItem(Items[N], V.LevelMesh[I], W.Level.Boxes[I].Center, W.Level.Boxes[I].Rot, V3(1.0, 1.0, 1.0),
                 0.25, 0.9);
    Inc(N);
  end;
  SimpleItem(Items[N], V.FloorMesh, V3(0.0, 0.003, 0.0), QuatIdentity, V3(0.9, 0.9, 0.9), 0.85, 0.0);
  Items[N].Checker := True;
  Items[N].CastShadow := False;
  Inc(N);

  { Игрок: поза по состоянию. }
  Speed := HorizontalSpeed(W.Player.Vel);
  Phase := W.Time * (7.0 + Speed * 0.6);
  Swing := Min(0.9, 0.2 + Speed * 0.08);
  Lean := 0.0;
  Pose := 0;
  case W.Player.State of
    PS_AIR: Pose := 1;
    PS_HANG: Pose := 2;
    PS_CLIMB: Pose := 2;
    PS_WALLRUN:
      begin
        Pose := 5;
        if V3Cross(V3(0.0, 1.0, 0.0), V3(W.Player.WallN.X, 0.0, W.Player.WallN.Z)).Z > 0.0 then
          Lean := -0.3
        else
          Lean := 0.3;
      end;
    PS_SLIDE: Pose := 6;
    PS_POUND: Pose := 7;
    PS_RAIL: Pose := 0;
  end;
  if W.Player.ShotCooldown > 0.12 then
    if (Pose = 0) or (Pose = 1) then Pose := 3;
  Flip := PlayerFlipAngle(W.Player);
  CenterP := W.Player.Center;
  if W.Player.State <> PS_DEAD then
  begin
    if W.Player.FlipKind = FLIP_SIDE then
      BuildFigure(V, Items, N, CenterP, W.Player.Yaw, Flip, Lean, 3, Pose, Phase, Swing,
                  TINT_PLAYER_SUIT, TINT_PLAYER_SKIN, TINT_PLAYER_LEG, True)
    else if W.Player.FlipKind = FLIP_BACK then
      BuildFigure(V, Items, N, CenterP, W.Player.Yaw, Flip, Lean, 1, Pose, Phase, Swing,
                  TINT_PLAYER_SUIT, TINT_PLAYER_SKIN, TINT_PLAYER_LEG, True)
    else if W.Player.FlipKind = FLIP_FRONT then
      BuildFigure(V, Items, N, CenterP, W.Player.Yaw, Flip, Lean, 2, Pose, Phase, Swing,
                  TINT_PLAYER_SUIT, TINT_PLAYER_SKIN, TINT_PLAYER_LEG, True)
    else
      BuildFigure(V, Items, N, CenterP, W.Player.Yaw, 0.0, Lean, 0, Pose, Phase, Swing,
                  TINT_PLAYER_SUIT, TINT_PLAYER_SKIN, TINT_PLAYER_LEG, True);
  end;

  { Враги. }
  for I := 0 to W.EnemyCount - 1 do
  begin
    if not W.Enemies[I].Alive then
    begin
      { Павший враг лежит на боку. }
      BuildFigure(V, Items, N, V3(W.Enemies[I].Center.X, 0.2, W.Enemies[I].Center.Z), W.Enemies[I].Yaw,
                  1.45, 0.0, 3, 4, 0.0, 0.0, TINT_ENEMY_SUIT, TINT_ENEMY_SKIN, TINT_ENEMY_LEG, False);
      Continue;
    end;
    if W.Enemies[I].Kind = EN_TURRET then
    begin
      SimpleItem(Items[N], V.TurretBody, V3(W.Enemies[I].Center.X, W.Enemies[I].Center.Y - 0.4, W.Enemies[I].Center.Z),
                 RY(W.Enemies[I].Yaw), V3(0.25, 0.27, 0.3), 0.5, 0.4);
      Inc(N);
      SimpleItem(Items[N], V.TurretBarrel,
                 V3Add(V3(W.Enemies[I].Center.X, W.Enemies[I].Center.Y - 0.4, W.Enemies[I].Center.Z),
                       QuatRotate(RY(W.Enemies[I].Yaw), V3(0.0, 0.0, 0.45))),
                 RY(W.Enemies[I].Yaw), V3(0.1, 0.1, 0.1), 0.5, 0.6);
      Inc(N);
      Continue;
    end;
    Speed := HorizontalSpeed(W.Enemies[I].Vel);
    Phase := W.Time * (7.0 + Speed * 0.6) + I;
    Swing := Min(0.8, 0.1 + Speed * 0.1);
    if W.Enemies[I].State = ES_WINDUP then
      Pose := 8
    else if W.Enemies[I].State = ES_KNOCK then
      Pose := 4
    else if (W.Enemies[I].State = ES_CHASE) and W.Enemies[I].Sees and (W.Enemies[I].ShotCooldown > 0.9) then
      Pose := 3
    else
      Pose := 0;
    if W.Enemies[I].State = ES_KNOCK then
      BuildFigure(V, Items, N, V3(W.Enemies[I].Center.X, 0.3, W.Enemies[I].Center.Z), W.Enemies[I].Yaw,
                  1.45, 0.0, 3, 4, 0.0, 0.0, TINT_ENEMY_SUIT, TINT_ENEMY_SKIN, TINT_ENEMY_LEG, False)
    else
      BuildFigure(V, Items, N, W.Enemies[I].Center, W.Enemies[I].Yaw, 0.0, 0.0, 0, Pose, Phase, Swing,
                  TINT_ENEMY_SUIT, TINT_ENEMY_SKIN, TINT_ENEMY_LEG, True);
  end;

  { Трассеры: светящиеся отрезки 2 м. Игрок - белый, враг - оранжевый. }
  for I := 0 to W.TracerCount - 1 do
  begin
    Dir := V3Sub(W.Tracers[I].B, W.Tracers[I].A);
    Ln := V3Length(Dir);
    if Ln < 1.0e-6 then Continue;
    Dir := V3Mul(Dir, 1.0 / Ln);
    Mid := V3MulAdd(W.Tracers[I].A, Dir, Min(Ln, 2.0) * 0.5);
    Axis := V3Cross(V3(0.0, 0.0, 1.0), Dir);
    Ang := ArcCos(ClampD(V3Dot(V3(0.0, 0.0, 1.0), Dir), -1.0, 1.0));
    if V3Length(Axis) < 1.0e-6 then
      Q := QuatIdentity
    else
      Q := QuatFromAxisAngle(V3Normalize(Axis), Ang);
    SimpleItem(Items[N], V.Streak, Mid, Q, V3(1.0, 1.0, 1.0), 0.3, 0.0);
    if W.Tracers[I].FromEnemy then
      Items[N].Emission := V3(5.0, 1.4, 0.4)
    else
      Items[N].Emission := V3(6.0, 5.6, 3.4);
    Items[N].CastShadow := False;
    Inc(N);
  end;
  V.Count := N;
end;

procedure VisualCamera(const W: TWorld; out Cam: TRenderCamera; out Light: TRenderLight);
begin
  Cam.Eye := W.Cam.Eye;
  Cam.Target := W.Cam.Target;
  Cam.Up := V3(0.0, 1.0, 0.0);
  Cam.FovY := 60.0 * Pi / 180.0;
  Cam.ZNear := 0.1;
  Cam.ZFar := 150.0;
  Light.Direction := V3Normalize(V3(0.45, 0.85, 0.35));
  Light.Color := V3(2.6, 2.35, 2.05);
  Light.SkyColor := V3(0.30, 0.38, 0.52);
  Light.GroundColor := V3(0.14, 0.12, 0.10);
  Light.Center := W.Player.Center;
  Light.Extent := 14.0;
end;

procedure HudBuild(var H: THud; const W: TWorld; WinW, WinH: Integer);
var
  Frac: Double;
  I, Alive: Integer;
  Cx, Cy: Double;
begin
  HudBegin(H, WinW, WinH);
  Cx := WinW * 0.5;
  Cy := WinH * 0.5;
  { Здоровье. }
  HudRect(H, 24.0, WinH - 40.0, 240.0, 14.0, 0.05, 0.05, 0.06, 0.6);
  Frac := W.Player.Health / PL_MAX_HEALTH;
  HudRect(H, 24.0, WinH - 40.0, 240.0 * Frac, 14.0, 0.85, 0.2, 0.15, 0.9);
  { Прицел. }
  HudRect(H, Cx - 7.0, Cy - 1.0, 14.0, 2.0, 1.0, 1.0, 1.0, 0.85);
  HudRect(H, Cx - 1.0, Cy - 7.0, 2.0, 14.0, 1.0, 1.0, 1.0, 0.85);
  if W.HitMarker > 0.0 then
  begin
    HudRect(H, Cx - 12.0, Cy - 12.0, 8.0, 2.0, 1.0, 0.9, 0.3, 0.9);
    HudRect(H, Cx + 4.0, Cy + 10.0, 8.0, 2.0, 1.0, 0.9, 0.3, 0.9);
    HudRect(H, Cx + 4.0, Cy - 12.0, 8.0, 2.0, 1.0, 0.9, 0.3, 0.9);
    HudRect(H, Cx - 12.0, Cy + 10.0, 8.0, 2.0, 1.0, 0.9, 0.3, 0.9);
  end;
  { Счётчик: убитые (красные квадраты) и живые (серые). }
  Alive := 0;
  for I := 0 to W.EnemyCount - 1 do
    if W.Enemies[I].Alive then Inc(Alive);
  for I := 0 to W.EnemyCount - 1 do
    if I < W.Stats.Kills then
      HudRect(H, WinW - 24.0 - I * 18.0, 24.0, 12.0, 12.0, 0.85, 0.2, 0.15, 0.9)
    else
      HudRect(H, WinW - 24.0 - I * 18.0, 24.0, 12.0, 12.0, 0.4, 0.42, 0.46, 0.7);
  { Урон и смерть. }
  if W.Player.HurtTime > 0.0 then
    HudRect(H, 0.0, 0.0, WinW, WinH, 0.8, 0.0, 0.0, 0.18 * Min(1.0, W.Player.HurtTime * 2.0));
  if W.Player.State = PS_DEAD then
    HudRect(H, 0.0, 0.0, WinW, WinH, 0.0, 0.0, 0.0, 0.6);
end;

end.
