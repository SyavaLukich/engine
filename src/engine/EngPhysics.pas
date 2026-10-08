{ EngPhysics - динамика твёрдых тел.

  Состав:
    - твёрдые тела на основе форм EngConvex (сфера, капсула, бокс, выпуклая оболочка);
    - контакты тел между собой (GJK/EPA) и с плоским полом (точки опор формы);
    - импульсный решатель (sequential impulses): нормальный и трение по кулону, накопление импульсов
      с тёплым стартом между шагами, baumgarte-коррекция проникновения, спекулятивные контакты пола;
    - шарниры: ball (точечное крепление) и hinge (ось с пределами). У шарниров есть PD-привод
      ориентации, реализованный как ограниченный по моменту servo по скорости;
    - эффекторы: пружины к мировой точке на теле и к мировой ориентации тела (для рук, таза, баланса);
    - интегрирование полуявное (semi-implicit Euler), фиксированный шаг (PhysStep).

  Соглашения:
    - нормаль контакта N направлена от тела B к телу A: A += N*глубина разводит тела;
      для пола B = -1, N = нормаль пола;
    - статическое тело (Static = True) имеет нулевые обратные массу и инерцию;
    - единицы СИ: м, кг, с, рад;
    - модуль не знает о рендеринге и анимации: рэгдолл и сцена используют только публичные записи и функции.

  Память: тела, шарниры и эффекторы - динамические массивы, растут при добавлении;
  контакты и кэш импульсов пересоздаются на каждом шаге (без утечек). Классов и объектов нет. }
unit EngPhysics;

{$mode objfpc}{$H+}
{$inline on}

interface

uses
  Math, EngMath, EngConvex;

const
  PHYS_BAUMGARTE = 0.2;                 { доля коррекции проникновения за шаг }
  PHYS_SLOP = 0.001;                    { допустимое проникновение, м }
  PHYS_SPECULATIVE = 0.02;              { зазор, с которого создаются спекулятивные контакты пола, м }
  PHYS_RESTITUTION_THRESHOLD = 1.0;     { м/с: при меньшей скорости сближения отскока нет }
  PHYS_MAX_DRIVE_SPEED = 10.0;          { ограничение целевой угловой скорости привода, рад/с }
  PHYS_MAX_EFFECTOR_SPEED = 20.0;       { ограничение целевой линейной скорости эффектора, м/с }

type
  TRigidBody = record
    Shape: TConvexShape;
    Pos: TVec3;                { центр масс = начало локальной системы формы }
    Rot: TQuat;
    Vel: TVec3;
    AngVel: TVec3;             { мировая система }
    InvMass: Double;
    InvInertiaBody: TVec3;     { диагональ обратного тензора инерции в локальной системе }
    InvInertiaWorld: TMat3;    { обратный тензор инерции в мировой системе, пересчитывается шагом }
    BoundRadius: Double;       { радиус описанной сферы для широкой фазы }
    Restitution: Double;
    Friction: Double;
    LinDamping: Double;        { 1/с: v := v/(1 + c*dt) }
    AngDamping: Double;
    Group: Integer;            { тела одной ненулевой группы не сталкиваются между собой }
    Static: Boolean;
    OnGround: Boolean;         { есть контакт с полом в текущем шаге (выставляет шаг) }
    Force: TVec3;              { внешняя сила на текущий шаг; сбрасывается шагом }
    Torque: TVec3;             { внешний момент на текущий шаг; сбрасывается шагом }
  end;
  PRigidBody = ^TRigidBody;

  TPhysJointKind = (jkBall, jkHinge);

  TPhysJoint = record
    Kind: TPhysJointKind;
    A, B: Integer;             { индексы тел; B - дочернее тело }
    AnchorA, AnchorB: TVec3;   { точки крепления в локальных системах тел }
    Axis: TVec3;               { ось шарнира в локальной системе A (jkHinge) }
    LimitEnabled: Boolean;
    LimitLo, LimitHi: Double;  { пределы угла вокруг оси, рад (0 = прямой сустав, когда TargetRel = I) }
    LimitGain: Double;         { 1/с: скорость возврата внутрь предела }
    DriveEnabled: Boolean;
    TargetRel: TQuat;          { целевая ориентация B относительно A (в системе A) }
    Stiffness: Double;         { Kp, 1/с^2 }
    Damping: Double;           { Kd, 1/с (должен быть > 0) }
    MaxTorque: Double;         { предел момента привода, Н*м }
    Strength: Double;          { 0..1: сила "мышцы" (масштаб жёсткости и момента) }
    Collide: Boolean;          { сталкивать ли соединённые тела друг с другом }
  end;

  TPhysEffector = record
    Body: Integer;
    Local: TVec3;              { точка на теле (локальная система) }
    Target: TVec3;             { мировая цель точки }
    PosStiffness: Double;      { 0 - выключено; иначе Kp, 1/с^2 }
    PosDamping: Double;        { Kd, 1/с }
    PosMaxForce: Double;       { предел силы, Н }
    UseOrient: Boolean;
    TargetRot: TQuat;          { мировая целевая ориентация тела }
    OriStiffness: Double;
    OriDamping: Double;
    OriMaxTorque: Double;      { предел момента, Н*м }
    Enabled: Boolean;
  end;

  { Точка контакта (пересоздаётся каждый шаг). }
  TPhysContact = record
    A, B: Integer;             { B = -1: пол }
    Key: Integer;              { ключ кэширования импульсов в паре (A, B) }
    N: TVec3;                  { нормаль от B к A }
    P: TVec3;                  { точка контакта, мировая система }
    Sep: Double;               { зазор: отрицательный - проникновение }
    T1, T2: TVec3;             { касательный базис }
    RA, RB: TVec3;             { плечи от центров масс }
    MassN, MassT1, MassT2: Double;
    Bias: Double;              { целевая нормальная скорость (A относительно B) }
    Restitution: Double;
    Friction: Double;
    JN, JT1, JT2: Double;      { накопленные импульсы }
  end;

  TCachedContact = record
    A, B, Key: Integer;
    JN, JT1, JT2: Double;
  end;

  { Состояние шарнира на текущий шаг. }
  TJointState = record
    Ra, Rb: TVec3;             { плечи точек крепления, мир }
    PosErr: TVec3;             { рассогласование точек крепления, мир }
    Kinv: TMat3;               { обратная эффективная масса точки крепления }
    KaInv: TMat3;              { обратная угловая эффективная масса (IA + IB)^-1 }
    DriveErr: TVec3;           { ошибка ориентации в мире (вектор поворота) }
    Axis: TVec3;               { ось шарнира, мир }
    T1, T2: TVec3;             { базис, перпендикулярный оси }
    LockInv: array[0..3] of Double; { обратная 2x2 матрица блокировки перпендикулярных осей }
    AxisMass: Double;          { 1/(axis*Ka*axis) }
    Angle: Double;             { текущий угол шарнира вокруг оси, рад }
    AccPos: TVec3;             { накопленный импульс точки крепления (не тёплый старт) }
    AccDrive: TVec3;           { накопленный угловой импульс привода (ball) }
    AccDriveAx: Double;        { то же для hinge: компонента по оси }
    AccLimit: Double;          { накопленный импульс предела по оси }
  end;

  TEffectorState = record
    R: TVec3;                  { плечо точки эффектора, мир }
    P: TVec3;                  { мировая точка эффектора }
    KptInv: TMat3;             { обратная эффективная масса точки }
    AccP: TVec3;               { накопленный импульс точки }
    AccO: TVec3;               { накопленный угловой импульс ориентации }
    OriErr: TVec3;             { ошибка ориентации, мир }
  end;

  TPhysStats = record
    Contacts: Integer;         { контакты последнего шага }
    Pairs: Integer;            { кандидатов пар широкой фазы }
    NarrowTests: Integer;      { вызовов узкой фазы }
  end;

  TPhysWorld = record
    Bodies: array of TRigidBody;
    BodyCount: Integer;
    Joints: array of TPhysJoint;
    JointState: array of TJointState;
    JointCount: Integer;
    Effectors: array of TPhysEffector;
    EffectorState: array of TEffectorState;
    EffectorCount: Integer;
    Contacts: array of TPhysContact;
    ContactCount: Integer;
    Cache: array of TCachedContact;
    CacheCount: Integer;
    Order: array of Integer;   { сортировка по X для широкой фазы (scratch) }
    Gravity: TVec3;
    Iterations: Integer;       { число итераций решателя за шаг }
    HasGround: Boolean;
    GroundN: TVec3;            { нормаль пола (единичная, вверх) }
    GroundD: Double;           { пол: dot(N, X) = D }
    GroundFriction: Double;
    GroundRestitution: Double;
    SimTime: Double;
    Steps: Int64;
    Stats: TPhysStats;
  end;

{ ---- мир ---- }
procedure PhysWorldInit(var W: TPhysWorld; const Gravity: TVec3; Iterations: Integer);
procedure PhysSetGround(var W: TPhysWorld; const Normal: TVec3; const Offset, Friction, Restitution: Double);
function PhysAddBody(var W: TPhysWorld; const B: TRigidBody): Integer;
function PhysAddJoint(var W: TPhysWorld; const J: TPhysJoint): Integer;
function PhysAddEffector(var W: TPhysWorld; const E: TPhysEffector): Integer;
procedure PhysStep(var W: TPhysWorld; Dt: Double);
procedure PhysAdvance(var W: TPhysWorld; FrameDt: Double; Substeps: Integer);

{ ---- тела ---- }
function PhysShapeVolume(const S: TConvexShape): Double;
function PhysShapeInertia(const S: TConvexShape; const Mass: Double): TVec3;
function PhysMakeBody(const S: TConvexShape; const Pos: TVec3; const Rot: TQuat; const Mass: Double): TRigidBody;
procedure PhysApplyImpulse(var B: TRigidBody; const Impulse, WorldPoint: TVec3);
function PhysPointVelocity(const B: TRigidBody; const WorldPoint: TVec3): TVec3;
function PhysKineticEnergy(const B: TRigidBody): Double;
function PhysWorldCenterOfMass(const W: TPhysWorld; const Group: Integer; out Mass: Double): TVec3;

{ ---- шарниры и эффекторы: значения по умолчанию ---- }
function PhysDefaultJoint(Kind: TPhysJointKind; A, B: Integer): TPhysJoint;
function PhysDefaultEffector(Body: Integer): TPhysEffector;

implementation

const
  PHYS_EPS = 1e-12;

{ ---------- линейная алгебра вспомогательная ---------- }

{ Кососимметричная матрица: Skew(r) * v = r x v. Столбцы хранятся подряд (M[col*3+row]). }
function Skew(const V: TVec3): TMat3;
begin
  Result.M[0] := 0;    Result.M[3] := -V.Z; Result.M[6] := V.Y;
  Result.M[1] := V.Z;  Result.M[4] := 0;    Result.M[7] := -V.X;
  Result.M[2] := -V.Y; Result.M[5] := V.X;  Result.M[8] := 0;
end;

function Mat3Add(const A, B: TMat3): TMat3;
var
  I: Integer;
begin
  for I := 0 to 8 do
    Result.M[I] := A.M[I] + B.M[I];
end;

function Mat3Sub(const A, B: TMat3): TMat3;
var
  I: Integer;
begin
  for I := 0 to 8 do
    Result.M[I] := A.M[I] - B.M[I];
end;

{ Эффективная матрица точки: m_inv*I - S(r) I^-1 S(r) (для тела с обратной массой и тензором). }
function PointMassMatrix(const MInv: Double; const IInv: TMat3; const R: TVec3): TMat3;
var
  S: TMat3;
begin
  S := Skew(R);
  Result := Mat3Sub(Mat3Diagonal(V3(MInv, MInv, MInv)), Mat3Mul(Mat3Mul(S, IInv), S));
end;

{ Вектор поворота (ось * угол) для единичного кватерниона; кратчайший путь. }
function QuatToRotVec(const Q: TQuat): TVec3;
var
  V: TVec3;
  W, S, Ang: Double;
begin
  V := V3(Q.X, Q.Y, Q.Z);
  W := Q.W;
  if W < 0 then
  begin
    V := V3Neg(V);
    W := -W;
  end;
  S := V3Length(V);
  if S < 1e-12 then
    Result := V3Mul(V, 2.0)
  else
  begin
    Ang := 2.0 * ArcTan2(S, W);
    Result := V3Mul(V, Ang / S);
  end;
end;

function V3ClampLen(const V: TVec3; const MaxLen: Double): TVec3;
var
  L: Double;
begin
  L := V3Length(V);
  if (L > MaxLen) and (L > PHYS_EPS) then
    Result := V3Mul(V, MaxLen / L)
  else
    Result := V;
end;

{ Угол шарнира вокруг локальной оси Axis для относительного поворота Q. }
function HingeAngle(const Q: TQuat; const Axis: TVec3): Double;
var
  W: Double;
  V: TVec3;
begin
  V := V3(Q.X, Q.Y, Q.Z);
  W := Q.W;
  if W < 0 then
  begin
    V := V3Neg(V);
    W := -W;
  end;
  Result := 2.0 * ArcTan2(V3Dot(V, Axis), W);
end;

{ Применить импульс P: тело A получает +P, тело B получает -P (в точках с плечами RA, RB). }
procedure ApplyPairImpulse(PA, PB: PRigidBody; const RA, RB, P: TVec3);
begin
  PA^.Vel := V3MulAdd(PA^.Vel, P, PA^.InvMass);
  PA^.AngVel := V3Add(PA^.AngVel, Mat3MulV(PA^.InvInertiaWorld, V3Cross(RA, P)));
  if PB <> nil then
  begin
    PB^.Vel := V3MulAdd(PB^.Vel, P, -PB^.InvMass);
    PB^.AngVel := V3Sub(PB^.AngVel, Mat3MulV(PB^.InvInertiaWorld, V3Cross(RB, P)));
  end;
end;

{ Скорость точки тела (мир). }
function BodyPointVel(const B: PRigidBody; const R: TVec3): TVec3;
begin
  Result := V3Add(B^.Vel, V3Cross(B^.AngVel, R));
end;

{ ---------- мир ---------- }

procedure PhysWorldInit(var W: TPhysWorld; const Gravity: TVec3; Iterations: Integer);
begin
  W.BodyCount := 0;
  W.JointCount := 0;
  W.EffectorCount := 0;
  W.ContactCount := 0;
  W.CacheCount := 0;
  W.Gravity := Gravity;
  W.Iterations := Iterations;
  W.HasGround := False;
  W.GroundN := V3(0, 1, 0);
  W.GroundD := 0;
  W.GroundFriction := 0.8;
  W.GroundRestitution := 0.0;
  W.SimTime := 0;
  W.Steps := 0;
  W.Stats.Contacts := 0;
  W.Stats.Pairs := 0;
  W.Stats.NarrowTests := 0;
end;

procedure PhysSetGround(var W: TPhysWorld; const Normal: TVec3; const Offset, Friction, Restitution: Double);
begin
  W.HasGround := True;
  W.GroundN := V3Normalize(Normal);
  W.GroundD := Offset;
  W.GroundFriction := Friction;
  W.GroundRestitution := Restitution;
end;

function PhysAddBody(var W: TPhysWorld; const B: TRigidBody): Integer;
begin
  if W.BodyCount >= Length(W.Bodies) then
    SetLength(W.Bodies, Length(W.Bodies) * 2 + 16);
  W.Bodies[W.BodyCount] := B;
  Result := W.BodyCount;
  Inc(W.BodyCount);
end;

function PhysAddJoint(var W: TPhysWorld; const J: TPhysJoint): Integer;
begin
  if W.JointCount >= Length(W.Joints) then
  begin
    SetLength(W.Joints, Length(W.Joints) * 2 + 16);
    SetLength(W.JointState, Length(W.Joints));
  end;
  W.Joints[W.JointCount] := J;
  Result := W.JointCount;
  Inc(W.JointCount);
end;

function PhysAddEffector(var W: TPhysWorld; const E: TPhysEffector): Integer;
begin
  if W.EffectorCount >= Length(W.Effectors) then
  begin
    SetLength(W.Effectors, Length(W.Effectors) * 2 + 16);
    SetLength(W.EffectorState, Length(W.Effectors));
  end;
  W.Effectors[W.EffectorCount] := E;
  Result := W.EffectorCount;
  Inc(W.EffectorCount);
end;

{ ---------- тела ---------- }

function PhysShapeVolume(const S: TConvexShape): Double;
var
  I: Integer;
  Lo, Hi: TVec3;
begin
  case S.Kind of
    skSphere: Result := 4.0 / 3.0 * ENG_PI * S.Radius * S.Radius * S.Radius;
    skBox: Result := 8.0 * S.Half.X * S.Half.Y * S.Half.Z;
    skCapsule: Result := ENG_PI * S.Radius * S.Radius * 2.0 * S.Half.Y
                         + 4.0 / 3.0 * ENG_PI * S.Radius * S.Radius * S.Radius;
  else
    begin
      { выпуклая оболочка: объём описанного бокса (приближение) }
      if Length(S.Points) = 0 then
        Result := 0
      else
      begin
        Lo := S.Points[0];
        Hi := S.Points[0];
        for I := 1 to High(S.Points) do
        begin
          Lo := V3Min(Lo, S.Points[I]);
          Hi := V3Max(Hi, S.Points[I]);
        end;
        Result := (Hi.X - Lo.X) * (Hi.Y - Lo.Y) * (Hi.Z - Lo.Z);
      end;
    end;
  end;
end;

{ Главные моменты инерции (диагональ в локальной системе) для массы Mass. }
{ Полуразмеры AABB выпуклой оболочки (для приближённой инерции). }
function HullHalfExtents(const S: TConvexShape): TVec3;
var
  I: Integer;
  Lo, Hi: TVec3;
begin
  Result := V3Zero;
  if Length(S.Points) = 0 then Exit;
  Lo := S.Points[0];
  Hi := S.Points[0];
  for I := 1 to High(S.Points) do
  begin
    Lo := V3Min(Lo, S.Points[I]);
    Hi := V3Max(Hi, S.Points[I]);
  end;
  Result := V3Mul(V3Sub(Hi, Lo), 0.5);
end;

{ Главные моменты инерции (диагональ в локальной системе) для массы Mass. }
function PhysShapeInertia(const S: TConvexShape; const Mass: Double): TVec3;
var
  R2, Hx, Hy, Hz, R, Hh, Vc, Vs, Vt, Mc, Ms, D, Cm: Double;
begin
  case S.Kind of
    skSphere:
      begin
        R2 := S.Radius * S.Radius;
        Result := V3(0.4 * Mass * R2, 0.4 * Mass * R2, 0.4 * Mass * R2);
      end;
    skBox:
      begin
        Hx := S.Half.X; Hy := S.Half.Y; Hz := S.Half.Z;
        Result := V3(Mass / 3.0 * (Hy * Hy + Hz * Hz),
                     Mass / 3.0 * (Hx * Hx + Hz * Hz),
                     Mass / 3.0 * (Hx * Hx + Hy * Hy));
      end;
    skCapsule:
      begin
        { цилиндр (длина 2h, радиус r) и две полусферы; массы пропорциональны объёму }
        R := S.Radius;
        Hh := S.Half.Y;
        Vc := ENG_PI * R * R * 2.0 * Hh;
        Vs := 4.0 / 3.0 * ENG_PI * R * R * R;
        Vt := Vc + Vs;
        Mc := Mass * Vc / Vt;
        Ms := Mass * Vs / Vt;
        { центры полусфер смещены на h + 3r/8 от центра масс }
        D := Hh + 3.0 * R / 8.0;
        Result.Y := Mc * R * R / 2.0 + Ms * 0.4 * R * R;
        Cm := Mc * (3.0 * R * R + 4.0 * Hh * Hh) / 12.0 + Ms * (0.4 * R * R + D * D);
        Result.X := Cm;
        Result.Z := Cm;
      end;
  else
    { выпуклая оболочка: инерция описанного бокса (приближение) }
    Result := PhysShapeInertia(MakeBoxShape(HullHalfExtents(S)), Mass);
  end;
end;

function PhysMakeBody(const S: TConvexShape; const Pos: TVec3; const Rot: TQuat; const Mass: Double): TRigidBody;
var
  I: TVec3;
begin
  Result.Shape := S;
  Result.Pos := Pos;
  Result.Rot := QuatNormalize(Rot);
  Result.Vel := V3Zero;
  Result.AngVel := V3Zero;
  Result.BoundRadius := ShapeBoundingRadius(S);
  Result.Restitution := 0.1;
  Result.Friction := 0.8;
  Result.LinDamping := 0.0;
  Result.AngDamping := 0.0;
  Result.Group := 0;
  Result.OnGround := False;
  Result.Force := V3Zero;
  Result.Torque := V3Zero;
  Result.InvInertiaWorld := Mat3Diagonal(V3Zero);
  if Mass > 0 then
  begin
    Result.Static := False;
    Result.InvMass := 1.0 / Mass;
    I := PhysShapeInertia(S, Mass);
    { вырожденная форма (нулевой размер) не должна давать бесконечную инерцию }
    if I.X < 1e-12 then I.X := 1e-12;
    if I.Y < 1e-12 then I.Y := 1e-12;
    if I.Z < 1e-12 then I.Z := 1e-12;
    Result.InvInertiaBody := V3(1.0 / I.X, 1.0 / I.Y, 1.0 / I.Z);
  end
  else
  begin
    Result.Static := True;
    Result.InvMass := 0.0;
    Result.InvInertiaBody := V3Zero;
  end;
end;

procedure PhysApplyImpulse(var B: TRigidBody; const Impulse, WorldPoint: TVec3);
var
  R: TVec3;
begin
  if B.Static then Exit;
  R := V3Sub(WorldPoint, B.Pos);
  B.Vel := V3MulAdd(B.Vel, Impulse, B.InvMass);
  B.AngVel := V3Add(B.AngVel, Mat3MulV(B.InvInertiaWorld, V3Cross(R, Impulse)));
end;

function PhysPointVelocity(const B: TRigidBody; const WorldPoint: TVec3): TVec3;
begin
  Result := V3Add(B.Vel, V3Cross(B.AngVel, V3Sub(WorldPoint, B.Pos)));
end;

function PhysKineticEnergy(const B: TRigidBody): Double;
var
  Iw: TMat3;
  W: TVec3;
begin
  Result := 0;
  if B.Static then Exit;
  Result := 0.5 * V3Dot(B.Vel, B.Vel) / B.InvMass;
  if Mat3Inverse(B.InvInertiaWorld).M[0] <> 0 then
  begin
    Iw := Mat3Inverse(B.InvInertiaWorld);
    W := Mat3MulV(Iw, B.AngVel);
    Result := Result + 0.5 * V3Dot(B.AngVel, W);
  end;
end;

{ Центр масс динамических тел группы Group (Group < 0 - все тела) и суммарная масса. }
function PhysWorldCenterOfMass(const W: TPhysWorld; const Group: Integer; out Mass: Double): TVec3;
var
  I: Integer;
  M: Double;
  Acc: TVec3;
begin
  Acc := V3Zero;
  Mass := 0;
  for I := 0 to W.BodyCount - 1 do
  begin
    if W.Bodies[I].Static then Continue;
    if (Group >= 0) and (W.Bodies[I].Group <> Group) then Continue;
    M := 1.0 / W.Bodies[I].InvMass;
    Acc := V3MulAdd(Acc, W.Bodies[I].Pos, M);
    Mass := Mass + M;
  end;
  if Mass > 0 then
    Result := V3Mul(Acc, 1.0 / Mass)
  else
    Result := V3Zero;
end;

function PhysDefaultJoint(Kind: TPhysJointKind; A, B: Integer): TPhysJoint;
begin
  Result.Kind := Kind;
  Result.A := A;
  Result.B := B;
  Result.AnchorA := V3Zero;
  Result.AnchorB := V3Zero;
  Result.Axis := V3(1, 0, 0);
  Result.LimitEnabled := False;
  Result.LimitLo := -ENG_PI;
  Result.LimitHi := ENG_PI;
  Result.LimitGain := 30.0;
  Result.DriveEnabled := False;
  Result.TargetRel := QuatIdentity;
  Result.Stiffness := 200.0;
  Result.Damping := 20.0;
  Result.MaxTorque := 100.0;
  Result.Strength := 1.0;
  Result.Collide := False;
end;

function PhysDefaultEffector(Body: Integer): TPhysEffector;
begin
  Result.Body := Body;
  Result.Local := V3Zero;
  Result.Target := V3Zero;
  Result.PosStiffness := 0;
  Result.PosDamping := 1;
  Result.PosMaxForce := 1000;
  Result.UseOrient := False;
  Result.TargetRot := QuatIdentity;
  Result.OriStiffness := 0;
  Result.OriDamping := 1;
  Result.OriMaxTorque := 100;
  Result.Enabled := True;
end;

{ ---------- шаг: интегрирование скоростей ---------- }

procedure IntegrateVelocities(var W: TPhysWorld; Dt: Double);
var
  I: Integer;
  B: PRigidBody;
  R: TMat3;
  Damp: Double;
begin
  for I := 0 to W.BodyCount - 1 do
  begin
    B := @W.Bodies[I];
    R := QuatToMat3(B^.Rot);
    B^.InvInertiaWorld := Mat3Mul(Mat3Mul(R, Mat3Diagonal(B^.InvInertiaBody)), Mat3Transpose(R));
    if B^.Static then Continue;
    B^.Vel := V3MulAdd(B^.Vel, W.Gravity, Dt);
    B^.Vel := V3MulAdd(B^.Vel, B^.Force, B^.InvMass * Dt);
    B^.AngVel := V3MulAdd(B^.AngVel, Mat3MulV(B^.InvInertiaWorld, B^.Torque), Dt);
    Damp := 1.0 / (1.0 + B^.LinDamping * Dt);
    B^.Vel := V3Mul(B^.Vel, Damp);
    Damp := 1.0 / (1.0 + B^.AngDamping * Dt);
    B^.AngVel := V3Mul(B^.AngVel, Damp);
    B^.Force := V3Zero;
    B^.Torque := V3Zero;
  end;
end;

{ ---------- широкая и узкая фаза ---------- }

function JointLinked(const W: TPhysWorld; A, B: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to W.JointCount - 1 do
    if (not W.Joints[I].Collide) and (((W.Joints[I].A = A) and (W.Joints[I].B = B)) or
       ((W.Joints[I].A = B) and (W.Joints[I].B = A))) then
    begin
      Result := True;
      Exit;
    end;
end;

procedure AddContact(var W: TPhysWorld; BodyA, BodyB, PairKey: Integer; const Nrm, Pt: TVec3; SepDist: Double);
var
  C: ^TPhysContact;
begin
  if W.ContactCount >= Length(W.Contacts) then
    SetLength(W.Contacts, Length(W.Contacts) * 2 + 64);
  C := @W.Contacts[W.ContactCount];
  C^.A := BodyA;
  C^.B := BodyB;
  C^.Key := PairKey;
  C^.N := Nrm;
  C^.P := Pt;
  C^.Sep := SepDist;
  C^.JN := 0;
  C^.JT1 := 0;
  C^.JT2 := 0;
  Inc(W.ContactCount);
end;

{ Контакт опорной точки формы с полом: точка p с радиусом rs (0 для вершины). }
procedure AddPlaneSample(var W: TPhysWorld; BodyIndex, Key: Integer; const P: TVec3; Rs: Double);
var
  Dist: Double;
begin
  Dist := V3Dot(W.GroundN, P) - W.GroundD - Rs;
  if Dist < PHYS_SPECULATIVE then
  begin
    AddContact(W, BodyIndex, -1, Key, W.GroundN, V3MulAdd(P, W.GroundN, -Rs), Dist);
    W.Bodies[BodyIndex].OnGround := True;
  end;
end;

procedure CollideWithGround(var W: TPhysWorld; BodyIndex: Integer);
var
  B: PRigidBody;
  I, C: Integer;
  Ax: TVec3;
  Sx, Sy, Sz: Double;
  Loc: TVec3;
begin
  B := @W.Bodies[BodyIndex];
  case B^.Shape.Kind of
    skSphere:
      AddPlaneSample(W, BodyIndex, 0, B^.Pos, B^.Shape.Radius);
    skCapsule:
      begin
        Ax := QuatRotate(B^.Rot, V3(0, B^.Shape.Half.Y, 0));
        AddPlaneSample(W, BodyIndex, 0, V3Add(B^.Pos, Ax), B^.Shape.Radius);
        AddPlaneSample(W, BodyIndex, 1, V3Sub(B^.Pos, Ax), B^.Shape.Radius);
      end;
    skBox:
      for C := 0 to 7 do
      begin
        if (C and 1) <> 0 then Sx := 1 else Sx := -1;
        if (C and 2) <> 0 then Sy := 1 else Sy := -1;
        if (C and 4) <> 0 then Sz := 1 else Sz := -1;
        Loc := V3(Sx * B^.Shape.Half.X, Sy * B^.Shape.Half.Y, Sz * B^.Shape.Half.Z);
        AddPlaneSample(W, BodyIndex, C, V3Add(B^.Pos, QuatRotate(B^.Rot, Loc)), 0);
      end;
    skHull:
      for I := 0 to High(B^.Shape.Points) do
        AddPlaneSample(W, BodyIndex, I, V3Add(B^.Pos, QuatRotate(B^.Rot, B^.Shape.Points[I])), 0);
  end;
end;

procedure GenerateContacts(var W: TPhysWorld);
var
  I, K, A, B, J: Integer;
  PA, PB: PRigidBody;
  Ca: TConvexShape;
  Cont: TContact;
  Stats: TCollisionStats;
  PoseA, PoseB: TPose;
  MaxX, MinX: Double;
  Hit: Boolean;
begin
  W.ContactCount := 0;
  W.Stats.Pairs := 0;
  W.Stats.NarrowTests := 0;
  for I := 0 to W.BodyCount - 1 do
    W.Bodies[I].OnGround := False;

  if W.HasGround then
    for I := 0 to W.BodyCount - 1 do
      if not W.Bodies[I].Static then
        CollideWithGround(W, I);

  { сортировка по min X (сортировка вставками: массив почти отсортирован между шагами) }
  if Length(W.Order) < W.BodyCount then
    SetLength(W.Order, W.BodyCount + 16);
  for I := 0 to W.BodyCount - 1 do
    W.Order[I] := I;
  for I := 1 to W.BodyCount - 1 do
  begin
    J := I;
    while (J > 0) and (W.Bodies[W.Order[J - 1]].Pos.X - W.Bodies[W.Order[J - 1]].BoundRadius >
                       W.Bodies[W.Order[J]].Pos.X - W.Bodies[W.Order[J]].BoundRadius) do
    begin
      K := W.Order[J - 1];
      W.Order[J - 1] := W.Order[J];
      W.Order[J] := K;
      Dec(J);
    end;
  end;

  for I := 0 to W.BodyCount - 1 do
  begin
    A := W.Order[I];
    PA := @W.Bodies[A];
    MaxX := PA^.Pos.X + PA^.BoundRadius;
    for K := I + 1 to W.BodyCount - 1 do
    begin
      B := W.Order[K];
      PB := @W.Bodies[B];
      MinX := PB^.Pos.X - PB^.BoundRadius;
      if MinX > MaxX then Break;
      if PA^.Static and PB^.Static then Continue;
      if (PA^.Group <> 0) and (PA^.Group = PB^.Group) then Continue;
      Inc(W.Stats.Pairs);
      if V3Distance(PA^.Pos, PB^.Pos) > PA^.BoundRadius + PB^.BoundRadius then Continue;
      if JointLinked(W, A, B) then Continue;
      PoseA.Pos := PA^.Pos; PoseA.Rot := PA^.Rot;
      PoseB.Pos := PB^.Pos; PoseB.Rot := PB^.Rot;
      Inc(W.Stats.NarrowTests);
      Hit := CollideConvexStats(PA^.Shape, PoseA, PB^.Shape, PoseB, Cont, Stats);
      if Hit then
        AddContact(W, A, B, 0, Cont.Normal, V3Mul(V3Add(Cont.PointA, Cont.PointB), 0.5), -Cont.Depth);
    end;
  end;
  W.Stats.Contacts := W.ContactCount;
end;

{ ---------- подготовка контактов: плечи, массы, цели, тёплый старт ---------- }

function FindCached(const W: TPhysWorld; A, B, Key: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to W.CacheCount - 1 do
    if (W.Cache[I].A = A) and (W.Cache[I].B = B) and (W.Cache[I].Key = Key) then
    begin
      Result := I;
      Exit;
    end;
end;

procedure PrepareContacts(var W: TPhysWorld; Dt: Double);
var
  I, C: Integer;
  Ct: ^TPhysContact;
  PA, PB: PRigidBody;
  InvA, InvB: Double;
  IA, IB: TMat3;
  Vrel, Va, Vb: TVec3;
  Vn, Kn, Kt1, Kt2: Double;
  Cu, Cr: TVec3;
  Idx: Integer;
  Mu, E, Bias: Double;
  Imp: TVec3;
  GroundFr, GroundRes: Double;
begin
  for I := 0 to W.ContactCount - 1 do
  begin
    Ct := @W.Contacts[I];
    PA := @W.Bodies[Ct^.A];
    if Ct^.B >= 0 then PB := @W.Bodies[Ct^.B] else PB := nil;
    Ct^.RA := V3Sub(Ct^.P, PA^.Pos);
    if PB <> nil then
      Ct^.RB := V3Sub(Ct^.P, PB^.Pos)
    else
      Ct^.RB := V3Zero;

    { касательный базис }
    Ct^.T1 := V3Perpendicular(Ct^.N);
    Ct^.T2 := V3Cross(Ct^.N, Ct^.T1);

    InvA := PA^.InvMass;
    IA := PA^.InvInertiaWorld;
    if PB <> nil then
    begin
      InvB := PB^.InvMass;
      IB := PB^.InvInertiaWorld;
    end
    else
    begin
      InvB := 0;
      IB := Mat3Diagonal(V3Zero);
    end;

    { эффективные массы по нормали и касательным }
    Cu := V3Cross(Ct^.RA, Ct^.N);
    Cr := V3Cross(Ct^.RB, Ct^.N);
    Kn := InvA + InvB + V3Dot(Cu, Mat3MulV(IA, Cu)) + V3Dot(Cr, Mat3MulV(IB, Cr));
    if Kn > PHYS_EPS then Ct^.MassN := 1.0 / Kn else Ct^.MassN := 0;

    Cu := V3Cross(Ct^.RA, Ct^.T1);
    Cr := V3Cross(Ct^.RB, Ct^.T1);
    Kt1 := InvA + InvB + V3Dot(Cu, Mat3MulV(IA, Cu)) + V3Dot(Cr, Mat3MulV(IB, Cr));
    if Kt1 > PHYS_EPS then Ct^.MassT1 := 1.0 / Kt1 else Ct^.MassT1 := 0;

    Cu := V3Cross(Ct^.RA, Ct^.T2);
    Cr := V3Cross(Ct^.RB, Ct^.T2);
    Kt2 := InvA + InvB + V3Dot(Cu, Mat3MulV(IA, Cu)) + V3Dot(Cr, Mat3MulV(IB, Cr));
    if Kt2 > PHYS_EPS then Ct^.MassT2 := 1.0 / Kt2 else Ct^.MassT2 := 0;

    { относительная скорость до решения }
    Va := BodyPointVel(PA, Ct^.RA);
    if PB <> nil then Vb := BodyPointVel(PB, Ct^.RB) else Vb := V3Zero;
    Vrel := V3Sub(Va, Vb);
    Vn := V3Dot(Vrel, Ct^.N);

    { цель нормальной скорости: проникновение - коррекция; зазор - допуск сближения; отскок }
    if Ct^.Sep < 0 then
    begin
      Bias := PHYS_BAUMGARTE * (-Ct^.Sep - PHYS_SLOP) / Dt;
      if Bias < 0 then Bias := 0;
    end
    else
      Bias := -Ct^.Sep / Dt;

    { материалы }
    if PB <> nil then
    begin
      E := MaxD(PA^.Restitution, PB^.Restitution);
      Mu := Sqrt(PA^.Friction * PB^.Friction);
    end
    else
    begin
      GroundFr := W.GroundFriction;
      GroundRes := W.GroundRestitution;
      E := MaxD(PA^.Restitution, GroundRes);
      Mu := Sqrt(PA^.Friction * GroundFr);
    end;
    if (E > 0) and (Vn < -PHYS_RESTITUTION_THRESHOLD) then
      if -E * Vn > Bias then Bias := -E * Vn;
    Ct^.Bias := Bias;
    Ct^.Restitution := E;
    Ct^.Friction := Mu;

    { тёплый старт: импульсы прошлого шага для той же пары и того же ключа }
    Idx := FindCached(W, Ct^.A, Ct^.B, Ct^.Key);
    if Idx >= 0 then
    begin
      Ct^.JN := W.Cache[Idx].JN;
      Ct^.JT1 := W.Cache[Idx].JT1;
      Ct^.JT2 := W.Cache[Idx].JT2;
      Imp := V3Add(V3Mul(Ct^.N, Ct^.JN), V3Add(V3Mul(Ct^.T1, Ct^.JT1), V3Mul(Ct^.T2, Ct^.JT2)));
      ApplyPairImpulse(PA, PB, Ct^.RA, Ct^.RB, Imp);
    end
    else
    begin
      Ct^.JN := 0;
      Ct^.JT1 := 0;
      Ct^.JT2 := 0;
    end;
  end;
end;

{ ---------- подготовка шарниров и эффекторов ---------- }

procedure PrepareJoints(var W: TPhysWorld; Dt: Double);
var
  J: Integer;
  JT: ^TPhysJoint;
  ST: ^TJointState;
  PA, PB: PRigidBody;
  Ka, Kk, Ima, Imb: TMat3;
  Mi: Double;
  Qrel, Dq: TQuat;
  Axis, T1, T2, Wa, Wb: TVec3;
  M11, M12, M21, M22, Det: Double;
begin
  for J := 0 to W.JointCount - 1 do
  begin
    JT := @W.Joints[J];
    ST := @W.JointState[J];
    PA := @W.Bodies[JT^.A];
    PB := @W.Bodies[JT^.B];

    ST^.Ra := QuatRotate(PA^.Rot, JT^.AnchorA);
    ST^.Rb := QuatRotate(PB^.Rot, JT^.AnchorB);
    ST^.PosErr := V3Sub(V3Add(PB^.Pos, ST^.Rb), V3Add(PA^.Pos, ST^.Ra));

    { эффективная масса точки крепления: K = (mA I - S(ra) IA S(ra)) + (mB I - S(rb) IB S(rb)) }
    Ima := PA^.InvInertiaWorld;
    Imb := PB^.InvInertiaWorld;
    Kk := Mat3Add(PointMassMatrix(PA^.InvMass, Ima, ST^.Ra), PointMassMatrix(PB^.InvMass, Imb, ST^.Rb));
    ST^.Kinv := Mat3Inverse(Kk);

    { угловая эффективная масса }
    Ka := Mat3Add(Ima, Imb);
    ST^.KaInv := Mat3Inverse(Ka);

    { ошибка ориентации привода: dq = Target * conj(qrel), в мире - поворот qA }
    Qrel := QuatNormalize(QuatMul(QuatConj(PA^.Rot), PB^.Rot));
    Dq := QuatNormalize(QuatMul(JT^.TargetRel, QuatConj(Qrel)));
    ST^.DriveErr := QuatRotate(PA^.Rot, QuatToRotVec(Dq));

    { накопители обнуляются на каждом шаге (тёплого старта для приводов нет) }
    ST^.AccPos := V3Zero;
    ST^.AccDrive := V3Zero;
    ST^.AccDriveAx := 0;
    ST^.AccLimit := 0;

    if JT^.Kind = jkHinge then
    begin
      Axis := V3Normalize(QuatRotate(PA^.Rot, JT^.Axis));
      ST^.Axis := Axis;
      ST^.Angle := HingeAngle(Qrel, JT^.Axis);
      T1 := V3Perpendicular(Axis);
      T2 := V3Cross(Axis, T1);
      ST^.T1 := T1;
      ST^.T2 := T2;
      { M_ij = t_i * Ka * t_j, обращение 2x2 }
      Wa := Mat3MulV(Ka, T1);
      Wb := Mat3MulV(Ka, T2);
      M11 := V3Dot(T1, Wa);
      M12 := V3Dot(T1, Wb);
      M21 := V3Dot(T2, Wa);
      M22 := V3Dot(T2, Wb);
      Det := M11 * M22 - M12 * M21;
      if Abs(Det) > PHYS_EPS then
      begin
        ST^.LockInv[0] := M22 / Det;
        ST^.LockInv[1] := -M12 / Det;
        ST^.LockInv[2] := -M21 / Det;
        ST^.LockInv[3] := M11 / Det;
      end
      else
      begin
        ST^.LockInv[0] := 0;
        ST^.LockInv[1] := 0;
        ST^.LockInv[2] := 0;
        ST^.LockInv[3] := 0;
      end;
      Mi := V3Dot(Axis, Mat3MulV(Ka, Axis));
      if Mi > PHYS_EPS then ST^.AxisMass := 1.0 / Mi else ST^.AxisMass := 0;
    end;
  end;
end;

procedure PrepareEffectors(var W: TPhysWorld);
var
  E: Integer;
  ET: ^TPhysEffector;
  ES: ^TEffectorState;
  B: PRigidBody;
  Pm: TMat3;
begin
  for E := 0 to W.EffectorCount - 1 do
  begin
    ET := @W.Effectors[E];
    ES := @W.EffectorState[E];
    B := @W.Bodies[ET^.Body];
    ES^.AccP := V3Zero;
    ES^.AccO := V3Zero;
    ES^.R := QuatRotate(B^.Rot, ET^.Local);
    ES^.P := V3Add(B^.Pos, ES^.R);
    if (not ET^.Enabled) or B^.Static then Continue;
    if ET^.PosStiffness > 0 then
    begin
      Pm := PointMassMatrix(B^.InvMass, B^.InvInertiaWorld, ES^.R);
      ES^.KptInv := Mat3Inverse(Pm);
    end;
    if ET^.UseOrient then
      ES^.OriErr := QuatRotate(QuatIdentity, QuatToRotVec(QuatNormalize(QuatMul(ET^.TargetRot, QuatConj(B^.Rot)))));
  end;
end;

{ ---------- итерации решателя ---------- }

procedure SolveJoints(var W: TPhysWorld; Dt: Double);
var
  J: Integer;
  JT: ^TPhysJoint;
  ST: ^TJointState;
  PA, PB: PRigidBody;
  Cdot, Lam, Target, Wrel, Dw, Lvec, NewVec: TVec3;
  Bias, Kp, Maxt, Tgt, Wax, Ld, Newacc, Applied, Lim: Double;
  P1, P2, A1, A2: Double;
begin
  Bias := PHYS_BAUMGARTE / Dt;
  for J := 0 to W.JointCount - 1 do
  begin
    JT := @W.Joints[J];
    ST := @W.JointState[J];
    PA := @W.Bodies[JT^.A];
    PB := @W.Bodies[JT^.B];

    { 1. точка крепления: K * lambda = -(Cdot + bias*C). ApplyPairImpulse прикладывает +P к A, поэтому P = -lambda... }
    Cdot := V3Sub(BodyPointVel(PB, ST^.Rb), BodyPointVel(PA, ST^.Ra));
    Lam := Mat3MulV(ST^.Kinv, V3Add(Cdot, V3Mul(ST^.PosErr, Bias)));
    ApplyPairImpulse(PA, PB, ST^.Ra, ST^.Rb, Lam);

    { 2. привод ориентации: servo по скорости, накопление импульса и предел момента }
    if JT^.DriveEnabled and (JT^.Strength > 0) and (JT^.Damping > 0) then
    begin
      Kp := JT^.Stiffness / JT^.Damping * JT^.Strength;
      Maxt := JT^.MaxTorque * JT^.Strength * Dt;
      Wrel := V3Sub(PB^.AngVel, PA^.AngVel);
      if JT^.Kind = jkBall then
      begin
        Target := V3ClampLen(V3Mul(ST^.DriveErr, Kp), PHYS_MAX_DRIVE_SPEED);
        Dw := V3Sub(Target, Wrel);
        NewVec := V3ClampLen(V3Add(ST^.AccDrive, Mat3MulV(ST^.KaInv, Dw)), Maxt);
        Lvec := V3Sub(NewVec, ST^.AccDrive);
        ST^.AccDrive := NewVec;
        PA^.AngVel := V3Sub(PA^.AngVel, Mat3MulV(PA^.InvInertiaWorld, Lvec));
        PB^.AngVel := V3Add(PB^.AngVel, Mat3MulV(PB^.InvInertiaWorld, Lvec));
      end
      else
      begin
        { hinge: привод только вокруг оси }
        Tgt := ClampD(V3Dot(ST^.DriveErr, ST^.Axis) * Kp, -PHYS_MAX_DRIVE_SPEED, PHYS_MAX_DRIVE_SPEED);
        Wax := V3Dot(Wrel, ST^.Axis);
        Ld := (Tgt - Wax) * ST^.AxisMass;
        Newacc := ClampD(ST^.AccDriveAx + Ld, -Maxt, Maxt);
        Applied := Newacc - ST^.AccDriveAx;
        ST^.AccDriveAx := Newacc;
        Lvec := V3Mul(ST^.Axis, Applied);
        PA^.AngVel := V3Sub(PA^.AngVel, Mat3MulV(PA^.InvInertiaWorld, Lvec));
        PB^.AngVel := V3Add(PB^.AngVel, Mat3MulV(PB^.InvInertiaWorld, Lvec));
      end;
    end;

    if JT^.Kind = jkHinge then
    begin
      { 3. блокировка перпендикулярных осей: относительная скорость в них равна нулю }
      Wrel := V3Sub(PB^.AngVel, PA^.AngVel);
      P1 := V3Dot(Wrel, ST^.T1);
      P2 := V3Dot(Wrel, ST^.T2);
      A1 := -(ST^.LockInv[0] * P1 + ST^.LockInv[1] * P2);
      A2 := -(ST^.LockInv[2] * P1 + ST^.LockInv[3] * P2);
      Lvec := V3Add(V3Mul(ST^.T1, A1), V3Mul(ST^.T2, A2));
      PA^.AngVel := V3Sub(PA^.AngVel, Mat3MulV(PA^.InvInertiaWorld, Lvec));
      PB^.AngVel := V3Add(PB^.AngVel, Mat3MulV(PB^.InvInertiaWorld, Lvec));

      { 4. пределы угла вокруг оси: импульс накапливается одностороннее }
      if JT^.LimitEnabled then
      begin
        Lim := ST^.Angle;
        Newacc := 0;
        if Lim < JT^.LimitLo then
        begin
          Tgt := JT^.LimitGain * (JT^.LimitLo - Lim);
          Wrel := V3Sub(PB^.AngVel, PA^.AngVel);
          Wax := V3Dot(Wrel, ST^.Axis);
          Ld := (Tgt - Wax) * ST^.AxisMass;
          Newacc := ClampD(ST^.AccLimit + Ld, 0, 1e30);
        end
        else if Lim > JT^.LimitHi then
        begin
          Tgt := JT^.LimitGain * (JT^.LimitHi - Lim);
          Wrel := V3Sub(PB^.AngVel, PA^.AngVel);
          Wax := V3Dot(Wrel, ST^.Axis);
          Ld := (Tgt - Wax) * ST^.AxisMass;
          Newacc := ClampD(ST^.AccLimit + Ld, -1e30, 0);
        end;
        Applied := Newacc - ST^.AccLimit;
        ST^.AccLimit := Newacc;
        Lvec := V3Mul(ST^.Axis, Applied);
        PA^.AngVel := V3Sub(PA^.AngVel, Mat3MulV(PA^.InvInertiaWorld, Lvec));
        PB^.AngVel := V3Add(PB^.AngVel, Mat3MulV(PB^.InvInertiaWorld, Lvec));
      end;
    end;
  end;
end;

procedure SolveEffectors(var W: TPhysWorld; Dt: Double);
var
  E: Integer;
  ET: ^TPhysEffector;
  ES: ^TEffectorState;
  B: PRigidBody;
  Vpt, Tv, Dv, Lam, NewAcc, Applied: TVec3;
  Wt, Dw, Ldl: TVec3;
  Ib: TMat3;
  Maxf, Maxt: Double;
begin
  for E := 0 to W.EffectorCount - 1 do
  begin
    ET := @W.Effectors[E];
    ES := @W.EffectorState[E];
    if (not ET^.Enabled) then Continue;
    B := @W.Bodies[ET^.Body];
    if B^.Static then Continue;

    if ET^.PosStiffness > 0 then
    begin
      { точка эффектора: servo по скорости к цели, накопление и предел силы }
      ES^.R := QuatRotate(B^.Rot, ET^.Local);
      ES^.P := V3Add(B^.Pos, ES^.R);
      Vpt := BodyPointVel(B, ES^.R);
      Tv := V3ClampLen(V3Mul(V3Sub(ET^.Target, ES^.P), ET^.PosStiffness / ET^.PosDamping),
                       PHYS_MAX_EFFECTOR_SPEED);
      Dv := V3Sub(Tv, Vpt);
      Lam := Mat3MulV(ES^.KptInv, Dv);
      NewAcc := V3Add(ES^.AccP, Lam);
      Maxf := ET^.PosMaxForce * Dt;
      NewAcc := V3ClampLen(NewAcc, Maxf);
      Applied := V3Sub(NewAcc, ES^.AccP);
      ES^.AccP := NewAcc;
      B^.Vel := V3MulAdd(B^.Vel, Applied, B^.InvMass);
      B^.AngVel := V3Add(B^.AngVel, Mat3MulV(B^.InvInertiaWorld, V3Cross(ES^.R, Applied)));
    end;

    if ET^.UseOrient and (ET^.OriStiffness > 0) then
    begin
      Ib := B^.InvInertiaWorld;
      Wt := V3ClampLen(V3Mul(ES^.OriErr, ET^.OriStiffness / ET^.OriDamping), PHYS_MAX_DRIVE_SPEED);
      Dw := V3Sub(Wt, B^.AngVel);
      { импульс, дающий изменение угловой скорости Dw: L = I * Dw, I = (Ib)^-1 }
      Ldl := Mat3MulV(Mat3Inverse(Ib), Dw);
      NewAcc := V3Add(ES^.AccO, Ldl);
      Maxt := ET^.OriMaxTorque * Dt;
      NewAcc := V3ClampLen(NewAcc, Maxt);
      Applied := V3Sub(NewAcc, ES^.AccO);
      ES^.AccO := NewAcc;
      B^.AngVel := V3Add(B^.AngVel, Mat3MulV(Ib, Applied));
    end;
  end;
end;

procedure SolveContacts(var W: TPhysWorld);
var
  I: Integer;
  Ct: ^TPhysContact;
  PA, PB: PRigidBody;
  Vrel, Va, Vb: TVec3;
  Lam, NewAcc, Vn, Vt1, Vt2, MaxF: Double;
begin
  for I := 0 to W.ContactCount - 1 do
  begin
    Ct := @W.Contacts[I];
    PA := @W.Bodies[Ct^.A];
    if Ct^.B >= 0 then PB := @W.Bodies[Ct^.B] else PB := nil;

    { нормальный импульс }
    Va := BodyPointVel(PA, Ct^.RA);
    if PB <> nil then Vb := BodyPointVel(PB, Ct^.RB) else Vb := V3Zero;
    Vrel := V3Sub(Va, Vb);
    Vn := V3Dot(Vrel, Ct^.N);
    Lam := Ct^.MassN * (Ct^.Bias - Vn);
    NewAcc := Ct^.JN + Lam;
    if NewAcc < 0 then NewAcc := 0;
    Lam := NewAcc - Ct^.JN;
    Ct^.JN := NewAcc;
    if Lam <> 0 then
      ApplyPairImpulse(PA, PB, Ct^.RA, Ct^.RB, V3Mul(Ct^.N, Lam));

    { трение: два касательных направления, ограничение конусом Кулона }
    Va := BodyPointVel(PA, Ct^.RA);
    if PB <> nil then Vb := BodyPointVel(PB, Ct^.RB) else Vb := V3Zero;
    Vrel := V3Sub(Va, Vb);
    MaxF := Ct^.Friction * Ct^.JN;

    Vt1 := V3Dot(Vrel, Ct^.T1);
    Lam := -Ct^.MassT1 * Vt1;
    NewAcc := ClampD(Ct^.JT1 + Lam, -MaxF, MaxF);
    Lam := NewAcc - Ct^.JT1;
    Ct^.JT1 := NewAcc;
    if Lam <> 0 then
      ApplyPairImpulse(PA, PB, Ct^.RA, Ct^.RB, V3Mul(Ct^.T1, Lam));

    Va := BodyPointVel(PA, Ct^.RA);
    if PB <> nil then Vb := BodyPointVel(PB, Ct^.RB) else Vb := V3Zero;
    Vrel := V3Sub(Va, Vb);
    Vt2 := V3Dot(Vrel, Ct^.T2);
    Lam := -Ct^.MassT2 * Vt2;
    NewAcc := ClampD(Ct^.JT2 + Lam, -MaxF, MaxF);
    Lam := NewAcc - Ct^.JT2;
    Ct^.JT2 := NewAcc;
    if Lam <> 0 then
      ApplyPairImpulse(PA, PB, Ct^.RA, Ct^.RB, V3Mul(Ct^.T2, Lam));
  end;
end;

procedure IntegratePositions(var W: TPhysWorld; Dt: Double);
var
  I: Integer;
  B: PRigidBody;
begin
  for I := 0 to W.BodyCount - 1 do
  begin
    B := @W.Bodies[I];
    if B^.Static then Continue;
    B^.Pos := V3MulAdd(B^.Pos, B^.Vel, Dt);
    B^.Rot := QuatIntegrate(B^.Rot, B^.AngVel, Dt);
  end;
end;

procedure StoreCache(var W: TPhysWorld);
var
  I: Integer;
begin
  if Length(W.Cache) < W.ContactCount then
    SetLength(W.Cache, W.ContactCount + 64);
  W.CacheCount := 0;
  for I := 0 to W.ContactCount - 1 do
  begin
    W.Cache[W.CacheCount].A := W.Contacts[I].A;
    W.Cache[W.CacheCount].B := W.Contacts[I].B;
    W.Cache[W.CacheCount].Key := W.Contacts[I].Key;
    W.Cache[W.CacheCount].JN := W.Contacts[I].JN;
    W.Cache[W.CacheCount].JT1 := W.Contacts[I].JT1;
    W.Cache[W.CacheCount].JT2 := W.Contacts[I].JT2;
    Inc(W.CacheCount);
  end;
end;

procedure PhysStep(var W: TPhysWorld; Dt: Double);
var
  Iter: Integer;
begin
  if Dt <= 0 then Exit;
  IntegrateVelocities(W, Dt);
  GenerateContacts(W);
  PrepareContacts(W, Dt);
  PrepareJoints(W, Dt);
  PrepareEffectors(W);
  for Iter := 1 to W.Iterations do
  begin
    SolveJoints(W, Dt);
    SolveEffectors(W, Dt);
    SolveContacts(W);
  end;
  IntegratePositions(W, Dt);
  StoreCache(W);
  Inc(W.Steps);
  W.SimTime := W.SimTime + Dt;
end;

procedure PhysAdvance(var W: TPhysWorld; FrameDt: Double; Substeps: Integer);
var
  I: Integer;
  H: Double;
begin
  if Substeps < 1 then Substeps := 1;
  H := FrameDt / Substeps;
  for I := 1 to Substeps do
    PhysStep(W, H);
end;

end.
