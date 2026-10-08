{ EngAnim - система анимации: скелет, клипы с ключевыми кадрами, позы, прямая кинематика,
  кроссфейд между клипами и двухкостный IK.

  Соглашения:
    - кости хранятся в порядке "родитель раньше потомка" (Parent[i] < i);
    - локальная поза: позиция и вращение кости относительно родителя;
    - глобальная поза: относительно корня скелета (в системе скелета);
    - клипы - массивы ключей по времени, интерполяция: линейная для позиции, slerp для вращения.

  Модуль не зависит от физики и рендеринга: поза - обычный массив записей, его можно использовать
  и для рэгдолла, и для отрисовки скелета, и для тестов. Классов и объектов нет. }
unit EngAnim;

{$mode objfpc}{$H+}
{$inline on}

interface

uses
  Math, EngMath;

type
  TBoneXf = record
    Pos: TVec3;
    Rot: TQuat;
  end;

  TPose = array of TBoneXf;

  TSkeleton = record
    BoneCount: Integer;
    Parent: array of Integer;     { -1 для корня }
    Name: array of string;
    BindPos: array of TVec3;      { локальная позиция в покое (относительно родителя) }
    BindRot: array of TQuat;      { локальное вращение в покое }
  end;

  TClipTrack = record
    Bone: Integer;
    Times: array of Double;       { возрастающие моменты ключей, с }
    Pos: array of TVec3;
    Rot: array of TQuat;
  end;

  TClip = record
    Name: string;
    Duration: Double;             { длительность, с }
    Looping: Boolean;
    Tracks: array of TClipTrack;
    TrackCount: Integer;
  end;

  TClipLib = array of TClip;

  TAnimPlayer = record
    Clip: Integer;                { индекс клипа в библиотеке; -1 - нет }
    Time: Double;
    Speed: Double;
    PrevClip: Integer;            { клип, с которого идёт кроссфейд, -1 - нет }
    PrevTime: Double;
    FadeTotal: Double;            { длительность кроссфейда, с }
    FadeLeft: Double;             { оставшееся время кроссфейда, с }
  end;

{ ---- скелет и позы ---- }
procedure SkelInit(var S: TSkeleton; Count: Integer);
procedure SkelSetBone(var S: TSkeleton; Index, Parent: Integer; const BoneName: string;
                      const LocalPos: TVec3; const LocalRot: TQuat);
function SkelFindBone(const S: TSkeleton; const BoneName: string): Integer;
procedure PoseBind(const S: TSkeleton; var P: TPose);
procedure PoseGlobal(const S: TSkeleton; const Local: TPose; var Global: TPose);
procedure PoseBlend(const A, B: TPose; const T: Double; var Dst: TPose);

{ ---- клипы ---- }
procedure ClipInit(var C: TClip; const ClipName: string; Duration: Double; Looping: Boolean);
procedure ClipAddKey(var C: TClip; Bone: Integer; Time: Double; const Pos: TVec3; const Rot: TQuat);
procedure ClipSample(const C: TClip; Time: Double; var P: TPose);
function ClipAddToLib(var Lib: TClipLib; const C: TClip): Integer;
function ClipFindInLib(const Lib: TClipLib; const ClipName: string): Integer;

{ ---- проигрыватель с кроссфейдом ---- }
procedure PlayerInit(var Pl: TAnimPlayer);
procedure PlayerPlay(var Pl: TAnimPlayer; ClipIndex: Integer; FadeTime: Double);
procedure PlayerUpdate(var Pl: TAnimPlayer; const Lib: TClipLib; Dt: Double);
procedure PlayerEvaluate(const Pl: TAnimPlayer; const S: TSkeleton; const Lib: TClipLib; var P: TPose);

{ ---- вспомогательные ---- }
function QuatFromTo(const A, B: TVec3): TQuat;
{ Двухкостный IK: сустав середины (Mid) для корня Root и конца, достигающего Target.
  L1 - длина от корня до сустава, L2 - от сустава до конца; Pole задаёт сторону изгиба.
  Если цель вне досягаемости, конец ставится на линии к цели на максимальном расстоянии. }
function TwoBoneIK(const Root, Target, Pole: TVec3; const L1, L2: Double): TVec3;

implementation

procedure SkelInit(var S: TSkeleton; Count: Integer);
begin
  S.BoneCount := Count;
  SetLength(S.Parent, Count);
  SetLength(S.Name, Count);
  SetLength(S.BindPos, Count);
  SetLength(S.BindRot, Count);
end;

procedure SkelSetBone(var S: TSkeleton; Index, Parent: Integer; const BoneName: string;
                      const LocalPos: TVec3; const LocalRot: TQuat);
begin
  if Parent >= Index then
  begin
    WriteLn(ErrOutput, 'EngAnim: кость ', BoneName, ' должна идти после родителя');
    Halt(2);
  end;
  S.Parent[Index] := Parent;
  S.Name[Index] := BoneName;
  S.BindPos[Index] := LocalPos;
  S.BindRot[Index] := QuatNormalize(LocalRot);
end;

function SkelFindBone(const S: TSkeleton; const BoneName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to S.BoneCount - 1 do
    if S.Name[I] = BoneName then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

procedure PoseBind(const S: TSkeleton; var P: TPose);
var
  I: Integer;
begin
  SetLength(P, S.BoneCount);
  for I := 0 to S.BoneCount - 1 do
  begin
    P[I].Pos := S.BindPos[I];
    P[I].Rot := S.BindRot[I];
  end;
end;

procedure PoseGlobal(const S: TSkeleton; const Local: TPose; var Global: TPose);
var
  I, Pa: Integer;
begin
  SetLength(Global, S.BoneCount);
  for I := 0 to S.BoneCount - 1 do
  begin
    Pa := S.Parent[I];
    if Pa < 0 then
    begin
      Global[I].Pos := Local[I].Pos;
      Global[I].Rot := Local[I].Rot;
    end
    else
    begin
      Global[I].Pos := V3Add(Global[Pa].Pos, QuatRotate(Global[Pa].Rot, Local[I].Pos));
      Global[I].Rot := QuatNormalize(QuatMul(Global[Pa].Rot, Local[I].Rot));
    end;
  end;
end;

procedure PoseBlend(const A, B: TPose; const T: Double; var Dst: TPose);
var
  I, N: Integer;
begin
  N := Length(A);
  SetLength(Dst, N);
  for I := 0 to N - 1 do
  begin
    Dst[I].Pos := V3Lerp(A[I].Pos, B[I].Pos, T);
    Dst[I].Rot := QuatSlerp(A[I].Rot, B[I].Rot, T);
  end;
end;

procedure ClipInit(var C: TClip; const ClipName: string; Duration: Double; Looping: Boolean);
begin
  C.Name := ClipName;
  C.Duration := Duration;
  C.Looping := Looping;
  C.TrackCount := 0;
  SetLength(C.Tracks, 0);
end;

{ Трек для кости; создаётся при первом ключе. }
function TrackFor(var C: TClip; Bone: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to C.TrackCount - 1 do
    if C.Tracks[I].Bone = Bone then
    begin
      Result := I;
      Exit;
    end;
  if C.TrackCount >= Length(C.Tracks) then
    SetLength(C.Tracks, Length(C.Tracks) * 2 + 4);
  Result := C.TrackCount;
  C.Tracks[Result].Bone := Bone;
  SetLength(C.Tracks[Result].Times, 0);
  SetLength(C.Tracks[Result].Pos, 0);
  SetLength(C.Tracks[Result].Rot, 0);
  Inc(C.TrackCount);
end;

procedure ClipAddKey(var C: TClip; Bone: Integer; Time: Double; const Pos: TVec3; const Rot: TQuat);
var
  T, N: Integer;
begin
  T := TrackFor(C, Bone);
  N := Length(C.Tracks[T].Times);
  if (N > 0) and (Time <= C.Tracks[T].Times[N - 1]) then
  begin
    WriteLn(ErrOutput, 'EngAnim: ключи клипа ', C.Name, ' должны идти по возрастанию времени');
    Halt(2);
  end;
  SetLength(C.Tracks[T].Times, N + 1);
  SetLength(C.Tracks[T].Pos, N + 1);
  SetLength(C.Tracks[T].Rot, N + 1);
  C.Tracks[T].Times[N] := Time;
  C.Tracks[T].Pos[N] := Pos;
  C.Tracks[T].Rot[N] := QuatNormalize(Rot);
  if Time > C.Duration then
    C.Duration := Time;
end;

{ Выборка трека в момент T: бинарный поиск ключа. }
procedure SampleTrack(const Tr: TClipTrack; T: Double; out Pos: TVec3; out Rot: TQuat);
var
  Lo, Hi, Mid, N: Integer;
  F: Double;
begin
  N := Length(Tr.Times);
  if N = 0 then
  begin
    Pos := V3Zero;
    Rot := QuatIdentity;
    Exit;
  end;
  if T <= Tr.Times[0] then
  begin
    Pos := Tr.Pos[0];
    Rot := Tr.Rot[0];
    Exit;
  end;
  if T >= Tr.Times[N - 1] then
  begin
    Pos := Tr.Pos[N - 1];
    Rot := Tr.Rot[N - 1];
    Exit;
  end;
  Lo := 0;
  Hi := N - 1;
  while Hi - Lo > 1 do
  begin
    Mid := (Lo + Hi) div 2;
    if Tr.Times[Mid] <= T then Lo := Mid else Hi := Mid;
  end;
  F := (T - Tr.Times[Lo]) / (Tr.Times[Hi] - Tr.Times[Lo]);
  Pos := V3Lerp(Tr.Pos[Lo], Tr.Pos[Hi], F);
  Rot := QuatSlerp(Tr.Rot[Lo], Tr.Rot[Hi], F);
end;

procedure ClipSample(const C: TClip; Time: Double; var P: TPose);
var
  I: Integer;
  T: Double;
  Pos: TVec3;
  Rot: TQuat;
begin
  T := Time;
  if C.Looping and (C.Duration > 0) then
  begin
    T := T - Floor(T / C.Duration) * C.Duration;
  end
  else
  begin
    if T < 0 then T := 0;
    if T > C.Duration then T := C.Duration;
  end;
  for I := 0 to C.TrackCount - 1 do
  begin
    SampleTrack(C.Tracks[I], T, Pos, Rot);
    P[C.Tracks[I].Bone].Pos := Pos;
    P[C.Tracks[I].Bone].Rot := Rot;
  end;
end;

function ClipAddToLib(var Lib: TClipLib; const C: TClip): Integer;
begin
  SetLength(Lib, Length(Lib) + 1);
  Lib[High(Lib)] := C;
  Result := High(Lib);
end;

function ClipFindInLib(const Lib: TClipLib; const ClipName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Lib) do
    if Lib[I].Name = ClipName then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

procedure PlayerInit(var Pl: TAnimPlayer);
begin
  Pl.Clip := -1;
  Pl.Time := 0;
  Pl.Speed := 1;
  Pl.PrevClip := -1;
  Pl.PrevTime := 0;
  Pl.FadeTotal := 0;
  Pl.FadeLeft := 0;
end;

procedure PlayerPlay(var Pl: TAnimPlayer; ClipIndex: Integer; FadeTime: Double);
begin
  if (Pl.Clip >= 0) and (FadeTime > 0) then
  begin
    Pl.PrevClip := Pl.Clip;
    Pl.PrevTime := Pl.Time;
    Pl.FadeTotal := FadeTime;
    Pl.FadeLeft := FadeTime;
  end
  else
  begin
    Pl.PrevClip := -1;
    Pl.FadeLeft := 0;
  end;
  Pl.Clip := ClipIndex;
  Pl.Time := 0;
end;

procedure PlayerUpdate(var Pl: TAnimPlayer; const Lib: TClipLib; Dt: Double);
begin
  if Pl.Clip >= 0 then
    Pl.Time := Pl.Time + Dt * Pl.Speed;
  if Pl.PrevClip >= 0 then
  begin
    Pl.PrevTime := Pl.PrevTime + Dt * Pl.Speed;
    Pl.FadeLeft := Pl.FadeLeft - Dt;
    if Pl.FadeLeft <= 0 then
    begin
      Pl.PrevClip := -1;
      Pl.FadeLeft := 0;
    end;
  end;
end;

procedure PlayerEvaluate(const Pl: TAnimPlayer; const S: TSkeleton; const Lib: TClipLib; var P: TPose);
var
  Cur, Prv: TPose;
  W: Double;
begin
  PoseBind(S, P);
  if Pl.Clip < 0 then Exit;
  PoseBind(S, Cur);
  ClipSample(Lib[Pl.Clip], Pl.Time, Cur);
  if Pl.PrevClip >= 0 then
  begin
    PoseBind(S, Prv);
    ClipSample(Lib[Pl.PrevClip], Pl.PrevTime, Prv);
    { вес текущего клипа растёт от 0 до 1 за время кроссфейда (плавная полиномиальная кривая) }
    W := 1.0 - Pl.FadeLeft / Pl.FadeTotal;
    W := W * W * (3.0 - 2.0 * W);
    PoseBlend(Prv, Cur, W, P);
  end
  else
    P := Cur;
end;

function QuatFromTo(const A, B: TVec3): TQuat;
var
  Na, Nb, Axis: TVec3;
  D: Double;
begin
  Na := V3Normalize(A);
  Nb := V3Normalize(B);
  D := V3Dot(Na, Nb);
  if D >= 1 - 1e-12 then
  begin
    Result := QuatIdentity;
    Exit;
  end;
  if D <= -1 + 1e-12 then
  begin
    Axis := V3Perpendicular(Na);
    Result := QuatFromAxisAngle(V3Normalize(Axis), ENG_PI);
    Exit;
  end;
  Axis := V3Cross(Na, Nb);
  Result.X := Axis.X;
  Result.Y := Axis.Y;
  Result.Z := Axis.Z;
  Result.W := 1.0 + D;
  Result := QuatNormalize(Result);
end;

function TwoBoneIK(const Root, Target, Pole: TVec3; const L1, L2: Double): TVec3;
var
  D, Cosa, Sina, H, DistAlong: Double;
  Dir, Perp, PoleDir: TVec3;
  Dist: Double;
begin
  Dir := V3Sub(Target, Root);
  Dist := V3Length(Dir);
  { ограничиваем досягаемость }
  if Dist > L1 + L2 - 1e-9 then Dist := L1 + L2 - 1e-9;
  if Dist < Abs(L1 - L2) + 1e-9 then Dist := Abs(L1 - L2) + 1e-9;
  if V3Length(Dir) > 1e-12 then
    Dir := V3Normalize(Dir)
  else
    Dir := V3(0, -1, 0);
  { угол в корне между направлением на цель и костью L1 (теорема косинусов) }
  Cosa := (L1 * L1 + Dist * Dist - L2 * L2) / (2.0 * L1 * Dist);
  Cosa := ClampD(Cosa, -1, 1);
  Sina := Sqrt(1.0 - Cosa * Cosa);
  { сторона изгиба: ортогонализируем полюс относительно Dir }
  PoleDir := V3Sub(Pole, V3Mul(Dir, V3Dot(Pole, Dir)));
  if V3Length(PoleDir) < 1e-9 then
    PoleDir := V3Perpendicular(Dir)
  else
    PoleDir := V3Normalize(PoleDir);
  Perp := PoleDir;
  DistAlong := L1 * Cosa;
  H := L1 * Sina;
  Result := V3Add(Root, V3Add(V3Mul(Dir, DistAlong), V3Mul(Perp, H)));
end;

end.
