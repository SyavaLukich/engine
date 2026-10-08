{ EngRender - рендерер OpenGL 4.3 (core profile).

  Проход 1: карта теней направленного источника (глубина 2048x2048, сравнение с PCF в шейдере).
  Проход 2: PBR-освещение (GGX), окружающий полусферический свет, ACES, гамма 2.2.

  Рендерер не знает о физике и анимации: сцена передаётся как список элементов TRenderItem
  (индекс меша, матрица модели, параметры материала). Вызывающая сторона отвечает за создание окна
  и контекста (см. platform/GLFWBind.pas) и за загрузку функций (GLLoadFunctions).

  Требования: контекст OpenGL 4.3 core, GLLoadFunctions выполнен, контекст текущий. Классов нет. }
unit EngRender;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, EngMath, EngMat4, EngMesh, EngScene, GLBind;

const
  RENDER_SHADOW_SIZE = 2048;

type
  PSingle = ^Single;

  TGLMesh = record
    Vao: GLuint;
    Vbo: GLuint;
    Ebo: GLuint;
    IndexCount: Integer;
  end;

  TRenderer = record
    Width: Integer;
    Height: Integer;
    MainProg: GLuint;
    ShadowProg: GLuint;
    ShadowFbo: GLuint;
    ShadowTex: GLuint;
    Meshes: array of TGLMesh;
    MeshCount: Integer;
    LocModel: GLint;
    LocViewProj: GLint;
    LocLightVP: GLint;
    LocCamPos: GLint;
    LocLightDir: GLint;
    LocLightColor: GLint;
    LocSky: GLint;
    LocGround: GLint;
    LocTint: GLint;
    LocMetallic: GLint;
    LocRoughness: GLint;
    LocChecker: GLint;
    LocCheckerScale: GLint;
    LocShadowMap: GLint;
    LocShadowTexel: GLint;
    LocSModel: GLint;
    LocSLightVP: GLint;
    Ready: Boolean;
    Error: string;
  end;

{ Инициализация: компиляция шейдеров из каталога ShaderDir, карта теней. }
function RenderInit(var R: TRenderer; const ShaderDir: string; W, H: Integer): Boolean;
{ Загрузка меша в GPU; возвращает индекс меша или -1. }
function RenderUploadMesh(var R: TRenderer; const M: TMeshData): Integer;
procedure RenderResize(var R: TRenderer; W, H: Integer);
{ Кадр: проход теней и основной проход. }
procedure RenderFrame(var R: TRenderer; const Cam: TRenderCamera; const Light: TRenderLight;
                      const Items: array of TRenderItem);
procedure RenderShutdown(var R: TRenderer);
{ Чтение текстового файла целиком (для шейдеров). }
function ReadTextFile(const Path: string; out Text: string): Boolean;

implementation

function ReadTextFile(const Path: string; out Text: string): Boolean;
var
  F: file;
  Size: Int64;
  Got: Integer;
begin
  Result := False;
  Text := '';
  AssignFile(F, Path);
  {$I-}
  Reset(F, 1);
  {$I+}
  if IOResult <> 0 then Exit;
  Size := FileSize(F);
  SetLength(Text, Size);
  if Size > 0 then
    BlockRead(F, Text[1], Size, Got);
  Close(F);
  Result := True;
end;

function CompileStage(Kind: GLenum; const Src, Name: string; var Err: string): GLuint;
var
  Sh: GLuint;
  P: PChar;
  L, Ok, Len: GLint;
  Buf: array[0..4095] of Char;
begin
  Sh := glCreateShader(Kind);
  P := PChar(Src);
  L := Length(Src);
  glShaderSource(Sh, 1, @P, @L);
  glCompileShader(Sh);
  Ok := 0;
  glGetShaderiv(Sh, GL_COMPILE_STATUS, @Ok);
  if Ok = 0 then
  begin
    Len := 0;
    FillChar(Buf, SizeOf(Buf), 0);
    glGetShaderInfoLog(Sh, SizeOf(Buf) - 1, @Len, @Buf[0]);
    Err := Err + Name + ': ' + string(PChar(@Buf[0])) + LineEnding;
    glDeleteShader(Sh);
    Result := 0;
  end
  else
    Result := Sh;
end;

{ Программа из файлов Name.vert и Name.frag (или только вершинного и фрагментного для теней). }
function BuildProgram(const Dir, VertName, FragName: string; var Err: string): GLuint;
var
  VSrc, FSrc: string;
  VS, FS, Prog: GLuint;
  Ok: GLint;
  Buf: array[0..4095] of Char;
  Len: GLint;
begin
  Result := 0;
  if not ReadTextFile(Dir + '/' + VertName, VSrc) then
  begin
    Err := Err + 'нет файла ' + Dir + '/' + VertName + LineEnding;
    Exit;
  end;
  if not ReadTextFile(Dir + '/' + FragName, FSrc) then
  begin
    Err := Err + 'нет файла ' + Dir + '/' + FragName + LineEnding;
    Exit;
  end;
  VS := CompileStage(GL_VERTEX_SHADER, VSrc, VertName, Err);
  FS := CompileStage(GL_FRAGMENT_SHADER, FSrc, FragName, Err);
  if (VS = 0) or (FS = 0) then
  begin
    if VS <> 0 then glDeleteShader(VS);
    if FS <> 0 then glDeleteShader(FS);
    Exit;
  end;
  Prog := glCreateProgram();
  glAttachShader(Prog, VS);
  glAttachShader(Prog, FS);
  glLinkProgram(Prog);
  glDeleteShader(VS);
  glDeleteShader(FS);
  Ok := 0;
  glGetProgramiv(Prog, GL_LINK_STATUS, @Ok);
  if Ok = 0 then
  begin
    Len := 0;
    FillChar(Buf, SizeOf(Buf), 0);
    glGetProgramInfoLog(Prog, SizeOf(Buf) - 1, @Len, @Buf[0]);
    Err := Err + 'линковка ' + VertName + '+' + FragName + ': ' + string(PChar(@Buf[0])) + LineEnding;
    glDeleteProgram(Prog);
    Exit;
  end;
  Result := Prog;
end;

function Loc(Prog: GLuint; const Name: string): GLint;
begin
  Result := glGetUniformLocation(Prog, PChar(Name));
end;

procedure CreateShadowTarget(var R: TRenderer);
var
  Status: GLenum;
begin
  glGenTextures(1, @R.ShadowTex);
  glBindTexture(GL_TEXTURE_2D, R.ShadowTex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24, RENDER_SHADOW_SIZE, RENDER_SHADOW_SIZE, 0,
               GL_DEPTH_COMPONENT, GL_FLOAT, nil);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL);
  glGenFramebuffers(1, @R.ShadowFbo);
  glBindFramebuffer(GL_FRAMEBUFFER, R.ShadowFbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, R.ShadowTex, 0);
  glDrawBuffer(GL_NONE);
  glReadBuffer(GL_NONE);
  Status := glCheckFramebufferStatus(GL_FRAMEBUFFER);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  if Status <> GL_FRAMEBUFFER_COMPLETE then
    R.Error := R.Error + 'кадровый буфер теней не полон' + LineEnding;
end;

function RenderInitGL(var R: TRenderer; const ShaderDir: string; W, H: Integer): Boolean;
var
  Err: string;
begin
  Err := '';
  R.Error := '';
  R.Ready := False;
  R.Width := W;
  R.Height := H;
  R.MeshCount := 0;
  SetLength(R.Meshes, 0);
  R.MainProg := BuildProgram(ShaderDir, 'mesh.vert', 'mesh.frag', Err);
  R.ShadowProg := BuildProgram(ShaderDir, 'shadow.vert', 'shadow.frag', Err);
  if (R.MainProg = 0) or (R.ShadowProg = 0) then
  begin
    R.Error := Err;
    Result := False;
    Exit;
  end;
  R.LocModel := Loc(R.MainProg, 'uModel');
  R.LocViewProj := Loc(R.MainProg, 'uViewProj');
  R.LocLightVP := Loc(R.MainProg, 'uLightViewProj');
  R.LocCamPos := Loc(R.MainProg, 'uCamPos');
  R.LocLightDir := Loc(R.MainProg, 'uLightDir');
  R.LocLightColor := Loc(R.MainProg, 'uLightColor');
  R.LocSky := Loc(R.MainProg, 'uSkyColor');
  R.LocGround := Loc(R.MainProg, 'uGroundColor');
  R.LocTint := Loc(R.MainProg, 'uTint');
  R.LocMetallic := Loc(R.MainProg, 'uMetallic');
  R.LocRoughness := Loc(R.MainProg, 'uRoughness');
  R.LocChecker := Loc(R.MainProg, 'uChecker');
  R.LocCheckerScale := Loc(R.MainProg, 'uCheckerScale');
  R.LocShadowMap := Loc(R.MainProg, 'uShadowMap');
  R.LocShadowTexel := Loc(R.MainProg, 'uShadowTexel');
  R.LocSModel := Loc(R.ShadowProg, 'uModel');
  R.LocSLightVP := Loc(R.ShadowProg, 'uLightViewProj');

  CreateShadowTarget(R);
  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_LEQUAL);
  R.Ready := R.Error = '';
  Result := R.Ready;
end;

function RenderUploadMesh(var R: TRenderer; const M: TMeshData): Integer;
var
  G: TGLMesh;
begin
  Result := -1;
  if (M.VertexCount = 0) or (M.IndexCount = 0) then Exit;
  glGenVertexArrays(1, @G.Vao);
  glGenBuffers(1, @G.Vbo);
  glGenBuffers(1, @G.Ebo);
  glBindVertexArray(G.Vao);
  glBindBuffer(GL_ARRAY_BUFFER, G.Vbo);
  glBufferData(GL_ARRAY_BUFFER, M.VertexCount * MESH_FLOATS_PER_VERTEX * SizeOf(Single), @M.Vertices[0], GL_STATIC_DRAW);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, G.Ebo);
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, M.IndexCount * SizeOf(LongWord), @M.Indices[0], GL_STATIC_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, MESH_FLOATS_PER_VERTEX * SizeOf(Single), nil);
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, MESH_FLOATS_PER_VERTEX * SizeOf(Single), Pointer(PtrUInt(3 * SizeOf(Single))));
  glEnableVertexAttribArray(2);
  glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, MESH_FLOATS_PER_VERTEX * SizeOf(Single), Pointer(PtrUInt(6 * SizeOf(Single))));
  glBindVertexArray(0);
  G.IndexCount := M.IndexCount;
  if R.MeshCount >= Length(R.Meshes) then
    SetLength(R.Meshes, Length(R.Meshes) * 2 + 8);
  R.Meshes[R.MeshCount] := G;
  Result := R.MeshCount;
  Inc(R.MeshCount);
end;

procedure RenderResize(var R: TRenderer; W, H: Integer);
begin
  R.Width := W;
  R.Height := H;
end;

{ Матрицы источника света: ортографическая проекция, охватывающая сферу сцены. }
procedure LightMatrices(const Light: TRenderLight; out LightVP: TMat4);
var
  View, Proj: TMat4;
  Dir, Up, Eye: TVec3;
  E: Double;
begin
  Dir := V3Normalize(Light.Direction);
  E := Light.Extent;
  if Abs(Dir.Y) > 0.99 then
    Up := V3(0, 0, 1)
  else
    Up := V3(0, 1, 0);
  { Dir - единичный вектор К источнику света: глаз карты теней стоит со стороны света,
    иначе тени оказываются на противоположной стороне и на полу не видны. }
  Eye := V3Add(Light.Center, V3Mul(Dir, 2.0 * E));
  View := Mat4LookAt(Eye, Light.Center, Up);
  Proj := Mat4Ortho(-E, E, -E, E, 0.1, 4.0 * E);
  LightVP := Mat4Mul(Proj, View);
end;

procedure RenderFrameGL(var R: TRenderer; const Cam: TRenderCamera; const Light: TRenderLight;
                        const Items: array of TRenderItem);
var
  View, Proj, ViewProj, LightVP: TMat4;
  I: Integer;
  F: TMat4F;
  LightF: TMat4F;
  Dir: TVec3;
  G: TGLMesh;
begin
  if not R.Ready then Exit;
  LightMatrices(Light, LightVP);
  LightF := Mat4ToF(LightVP);
  Dir := V3Normalize(Light.Direction);

  { --- проход теней --- }
  glBindFramebuffer(GL_FRAMEBUFFER, R.ShadowFbo);
  glViewport(0, 0, RENDER_SHADOW_SIZE, RENDER_SHADOW_SIZE);
  glClear(GL_DEPTH_BUFFER_BIT);
  glUseProgram(R.ShadowProg);
  glUniformMatrix4fv(R.LocSLightVP, 1, GL_FALSE, PSingle(@LightF[0]));
  for I := 0 to High(Items) do
  begin
    if (not Items[I].CastShadow) or (Items[I].Mesh < 0) or (Items[I].Mesh >= R.MeshCount) then Continue;
    F := Mat4ToF(Items[I].Model);
    glUniformMatrix4fv(R.LocSModel, 1, GL_FALSE, PSingle(@F[0]));
    G := R.Meshes[Items[I].Mesh];
    glBindVertexArray(G.Vao);
    glDrawElements(GL_TRIANGLES, G.IndexCount, GL_UNSIGNED_INT, nil);
  end;
  glBindVertexArray(0);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);

  { --- основной проход --- }
  View := Mat4LookAt(Cam.Eye, Cam.Target, Cam.Up);
  Proj := Mat4Perspective(Cam.FovY, R.Width / Max(1, R.Height), Cam.ZNear, Cam.ZFar);
  ViewProj := Mat4Mul(Proj, View);
  glViewport(0, 0, R.Width, R.Height);
  glClearColor(0.07, 0.08, 0.10, 1.0);
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
  glEnable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glUseProgram(R.MainProg);
  F := Mat4ToF(ViewProj);
  glUniformMatrix4fv(R.LocViewProj, 1, GL_FALSE, PSingle(@F[0]));
  glUniformMatrix4fv(R.LocLightVP, 1, GL_FALSE, PSingle(@LightF[0]));
  glUniform3f(R.LocCamPos, Cam.Eye.X, Cam.Eye.Y, Cam.Eye.Z);
  glUniform3f(R.LocLightDir, Dir.X, Dir.Y, Dir.Z);
  glUniform3f(R.LocLightColor, Light.Color.X, Light.Color.Y, Light.Color.Z);
  glUniform3f(R.LocSky, Light.SkyColor.X, Light.SkyColor.Y, Light.SkyColor.Z);
  glUniform3f(R.LocGround, Light.GroundColor.X, Light.GroundColor.Y, Light.GroundColor.Z);
  glUniform1f(R.LocShadowTexel, 1.0 / RENDER_SHADOW_SIZE);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, R.ShadowTex);
  glUniform1i(R.LocShadowMap, 0);
  for I := 0 to High(Items) do
  begin
    if (Items[I].Mesh < 0) or (Items[I].Mesh >= R.MeshCount) then Continue;
    F := Mat4ToF(Items[I].Model);
    glUniformMatrix4fv(R.LocModel, 1, GL_FALSE, PSingle(@F[0]));
    glUniform3f(R.LocTint, Items[I].Tint.X, Items[I].Tint.Y, Items[I].Tint.Z);
    glUniform1f(R.LocMetallic, Items[I].Metallic);
    glUniform1f(R.LocRoughness, Items[I].Roughness);
    if Items[I].Checker then
    begin
      glUniform1i(R.LocChecker, 1);
      glUniform1f(R.LocCheckerScale, 1.0);
    end
    else
      glUniform1i(R.LocChecker, 0);
    G := R.Meshes[Items[I].Mesh];
    glBindVertexArray(G.Vao);
    glDrawElements(GL_TRIANGLES, G.IndexCount, GL_UNSIGNED_INT, nil);
  end;
  glBindVertexArray(0);
end;

{ Вызовы OpenGL выполняются с замаскированными исключениями FPU. Драйверы (Mesa и часть GPU)
  делают деления, дающие inf/NaN, а FPC по умолчанию прерывает такие операции как EZeroDivide.
  Прежняя маска восстанавливается, поэтому ошибки в расчётах Паскаля по-прежнему видны. }
function RenderInit(var R: TRenderer; const ShaderDir: string; W, H: Integer): Boolean;
var
  Saved: TFPUExceptionMask;
begin
  Saved := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  Result := RenderInitGL(R, ShaderDir, W, H);
  SetExceptionMask(Saved);
end;

procedure RenderFrame(var R: TRenderer; const Cam: TRenderCamera; const Light: TRenderLight;
                      const Items: array of TRenderItem);
var
  Saved: TFPUExceptionMask;
begin
  Saved := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  RenderFrameGL(R, Cam, Light, Items);
  SetExceptionMask(Saved);
end;

procedure RenderShutdown(var R: TRenderer);
var
  I: Integer;
begin
  if not R.Ready and (R.MeshCount = 0) then Exit;
  for I := 0 to R.MeshCount - 1 do
  begin
    glDeleteBuffers(1, @R.Meshes[I].Vbo);
    glDeleteBuffers(1, @R.Meshes[I].Ebo);
    glDeleteVertexArrays(1, @R.Meshes[I].Vao);
  end;
  R.MeshCount := 0;
  if R.ShadowFbo <> 0 then glDeleteFramebuffers(1, @R.ShadowFbo);
  if R.ShadowTex <> 0 then glDeleteTextures(1, @R.ShadowTex);
  if R.MainProg <> 0 then glDeleteProgram(R.MainProg);
  if R.ShadowProg <> 0 then glDeleteProgram(R.ShadowProg);
  R.Ready := False;
end;

end.
