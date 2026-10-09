{ EngRender - рендерер OpenGL 4.3 (core profile), конвейер в стиле Fox Engine.

  Проход 1: карта теней направленного источника (глубина 2048x2048, сравнение с PCF в шейдере).
  Проход 2: основная сцена в HDR (RGBA16F): PBR с выбираемой диффузной моделью (Lambert, Burley,
            Oren-Nayar), GGX-блик, полусферический окружающий свет, экспоненциальный туман.
  Проход 3: блум - выделение ярких пикселей, четыре уровня понижения и разделяемое размытие.
  Проход 4: композит - сложение блума, экспозиция, тонемаппинг Hable, гамма sRGB, цветокоррекция,
            виньетка; результат в LDR (RGBA8).
  Проход 5: FXAA на экран.

  Рендерер не знает о физике и анимации: сцена передаётся как список элементов TRenderItem
  (индекс меша, матрица модели, параметры материала). Вызывающая сторона отвечает за окно
  и контекст (platform/GLFWBind.pas или platform/OSMesaBind.pas) и за GLLoadFunctions.

  Требования: контекст OpenGL 4.3 core, GLLoadFunctions выполнен, контекст текущий. Классов нет. }
unit EngRender;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, EngMath, EngMat4, EngMesh, EngScene, EngShader, GLBind;

const
  RENDER_SHADOW_SIZE = 2048;
  RENDER_BLOOM_LEVELS = 4;
  RENDER_DIFFUSE_LAMBERT = 0;
  RENDER_DIFFUSE_BURLEY = 1;
  RENDER_DIFFUSE_OREN_NAYAR = 2;

type
  PSingle = ^Single;

  TGLMesh = record
    Vao: GLuint;
    Vbo: GLuint;
    Ebo: GLuint;
    IndexCount: Integer;
  end;

  { Постобработка после основного прохода. }
  TRenderPost = record
    Exposure: Double;          { множитель яркости перед тонемаппингом }
    BloomStrength: Double;     { вклад блума; 0 - блум не считается }
    BloomThreshold: Double;    { порог яркости блума, линейные единицы }
    Saturation: Double;        { 1 - без изменений, 0 - монохром }
    Contrast: Double;          { 1 - без изменений }
    Vignette: Double;          { 0 - выключена }
    Fxaa: Boolean;             { сглаживание краёв на LDR-изображении }
  end;

  { Экспоненциальный туман; плотность падает с высотой. Density = 0 - тумана нет. }
  TRenderFog = record
    Color: TVec3;              { цвет тумана и фон (линейный HDR) }
    Density: Double;           { 1/м }
    Falloff: Double;           { 1/м по высоте }
  end;

  TRenderer = record
    Width: Integer;
    Height: Integer;
    MainProg: GLuint;
    ShadowProg: GLuint;
    CompositeProg: GLuint;
    BloomDownProg: GLuint;
    BlurProg: GLuint;
    FxaaProg: GLuint;
    ShadowFbo: GLuint;
    ShadowTex: GLuint;
    SceneFbo: GLuint;          { HDR-цель: цвет RGBA16F и глубина }
    SceneTex: GLuint;
    SceneDepth: GLuint;
    WorkFbo: GLuint;           { общий FBO постобработки: цель переключается присоединением }
    LdrTex: GLuint;            { LDR после композита, RGBA8 }
    BloomTex: array[0..RENDER_BLOOM_LEVELS - 1] of GLuint;
    BloomTmp: array[0..RENDER_BLOOM_LEVELS - 1] of GLuint;
    EmptyVao: GLuint;          { пустой VAO для полноэкранного треугольника }
    Meshes: array of TGLMesh;
    MeshCount: Integer;
    DiffuseMode: Integer;      { RENDER_DIFFUSE_* }
    Post: TRenderPost;
    Fog: TRenderFog;
    LocModel: GLint;
    LocViewProj: GLint;
    LocLightVP: GLint;
    LocCamPos: GLint;
    LocLightDir: GLint;
    LocLightColor: GLint;
    LocSky: GLint;
    LocGround: GLint;
    LocTint: GLint;
    LocEmission: GLint;
    LocMetallic: GLint;
    LocRoughness: GLint;
    LocChecker: GLint;
    LocCheckerScale: GLint;
    LocShadowMap: GLint;
    LocShadowTexel: GLint;
    LocDiffuseMode: GLint;
    LocFogColor: GLint;
    LocFogDensity: GLint;
    LocFogFalloff: GLint;
    LocSModel: GLint;
    LocSLightVP: GLint;
    LocCompScene: GLint;
    LocCompBloom: array[0..RENDER_BLOOM_LEVELS - 1] of GLint;
    LocCompExposure: GLint;
    LocCompBloomStrength: GLint;
    LocCompSaturation: GLint;
    LocCompContrast: GLint;
    LocCompVignette: GLint;
    LocDownSrc: GLint;
    LocDownTexel: GLint;
    LocDownThreshold: GLint;
    LocDownMode: GLint;
    LocBlurSrc: GLint;
    LocBlurDir: GLint;
    LocFxaaLdr: GLint;
    LocFxaaTexel: GLint;
    LocFxaaOn: GLint;
    Ready: Boolean;
    Error: string;
  end;

{ Инициализация: программы из каталога ShaderDir, карта теней, цели постобработки. }
function RenderInit(var R: TRenderer; const ShaderDir: string; W, H: Integer): Boolean;
{ Загрузка меша в GPU; возвращает индекс меша или -1. }
function RenderUploadMesh(var R: TRenderer; const M: TMeshData): Integer;
{ Новый размер окна: пересоздаёт цели HDR, блума и LDR. }
procedure RenderResize(var R: TRenderer; W, H: Integer);
{ Кадр: тени, HDR-сцена, блум, композит, FXAA. Результат - в текущий буфер кадра (default FB). }
procedure RenderFrame(var R: TRenderer; const Cam: TRenderCamera; const Light: TRenderLight;
                      const Items: array of TRenderItem);
procedure RenderShutdown(var R: TRenderer);
{ Значения по умолчанию: Fox-подобная цветокоррекция, умеренный блум, FXAA, туман выключен. }
procedure RenderDefaultPost(out P: TRenderPost);
procedure RenderDefaultFog(out F: TRenderFog);
{ Диффузная модель: RENDER_DIFFUSE_LAMBERT, RENDER_DIFFUSE_BURLEY или RENDER_DIFFUSE_OREN_NAYAR. }
procedure RenderSetDiffuseMode(var R: TRenderer; Mode: Integer);
function RenderDiffuseName(Mode: Integer): string;

implementation

function Loc(Prog: GLuint; const Name: string): GLint;
begin
  Result := glGetUniformLocation(Prog, PChar(Name));
end;

function LevelW(const R: TRenderer; Level: Integer): Integer;
begin
  Result := Max(1, R.Width shr (Level + 1));
end;

function LevelH(const R: TRenderer; Level: Integer): Integer;
begin
  Result := Max(1, R.Height shr (Level + 1));
end;

procedure BindTexture(Unit_: Integer; Tex: GLuint);
begin
  glActiveTexture(GLenum(GL_TEXTURE0 + Cardinal(Unit_)));
  glBindTexture(GL_TEXTURE_2D, Tex);
end;

procedure DrawFullscreen(const R: TRenderer);
begin
  glBindVertexArray(R.EmptyVao);
  glDrawArrays(GL_TRIANGLES, 0, 3);
end;

procedure CreateTexture2D(var Tex: GLuint; W, H: Integer; Internal, Fmt, Kind: GLenum; Filter: GLint);
begin
  glGenTextures(1, @Tex);
  glBindTexture(GL_TEXTURE_2D, Tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GLint(Internal), W, H, 0, Fmt, Kind, nil);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, Filter);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, Filter);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
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

procedure DestroyTargets(var R: TRenderer);
var
  I: Integer;
begin
  if R.SceneFbo <> 0 then glDeleteFramebuffers(1, @R.SceneFbo);
  if R.WorkFbo <> 0 then glDeleteFramebuffers(1, @R.WorkFbo);
  if R.SceneTex <> 0 then glDeleteTextures(1, @R.SceneTex);
  if R.SceneDepth <> 0 then glDeleteTextures(1, @R.SceneDepth);
  if R.LdrTex <> 0 then glDeleteTextures(1, @R.LdrTex);
  for I := 0 to RENDER_BLOOM_LEVELS - 1 do
  begin
    if R.BloomTex[I] <> 0 then glDeleteTextures(1, @R.BloomTex[I]);
    if R.BloomTmp[I] <> 0 then glDeleteTextures(1, @R.BloomTmp[I]);
    R.BloomTex[I] := 0;
    R.BloomTmp[I] := 0;
  end;
  R.SceneFbo := 0;
  R.WorkFbo := 0;
  R.SceneTex := 0;
  R.SceneDepth := 0;
  R.LdrTex := 0;
end;

{ Цели, зависящие от размера окна. }
procedure CreateTargets(var R: TRenderer);
var
  I: Integer;
  Status: GLenum;
begin
  CreateTexture2D(R.SceneTex, R.Width, R.Height, GL_RGBA16F, GL_RGBA, GL_FLOAT, GL_LINEAR);
  CreateTexture2D(R.SceneDepth, R.Width, R.Height, GL_DEPTH_COMPONENT24, GL_DEPTH_COMPONENT, GL_FLOAT, GL_NEAREST);
  CreateTexture2D(R.LdrTex, R.Width, R.Height, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, GL_LINEAR);
  for I := 0 to RENDER_BLOOM_LEVELS - 1 do
  begin
    CreateTexture2D(R.BloomTex[I], LevelW(R, I), LevelH(R, I), GL_RGBA16F, GL_RGBA, GL_FLOAT, GL_LINEAR);
    CreateTexture2D(R.BloomTmp[I], LevelW(R, I), LevelH(R, I), GL_RGBA16F, GL_RGBA, GL_FLOAT, GL_LINEAR);
  end;
  glGenFramebuffers(1, @R.SceneFbo);
  glBindFramebuffer(GL_FRAMEBUFFER, R.SceneFbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, R.SceneTex, 0);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, R.SceneDepth, 0);
  Status := glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if Status <> GL_FRAMEBUFFER_COMPLETE then
    R.Error := R.Error + 'кадровый буфер сцены не полон' + LineEnding;
  glGenFramebuffers(1, @R.WorkFbo);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
end;

procedure RenderDefaultPost(out P: TRenderPost);
begin
  P.Exposure := 1.0;
  P.BloomStrength := 0.06;
  P.BloomThreshold := 1.2;
  P.Saturation := 0.92;
  P.Contrast := 1.06;
  P.Vignette := 0.22;
  P.Fxaa := True;
end;

procedure RenderDefaultFog(out F: TRenderFog);
begin
  F.Color := V3(0.07, 0.08, 0.10);
  F.Density := 0.0;
  F.Falloff := 0.1;
end;

procedure RenderSetDiffuseMode(var R: TRenderer; Mode: Integer);
begin
  if (Mode < RENDER_DIFFUSE_LAMBERT) or (Mode > RENDER_DIFFUSE_OREN_NAYAR) then
    Mode := RENDER_DIFFUSE_BURLEY;
  R.DiffuseMode := Mode;
end;

function RenderDiffuseName(Mode: Integer): string;
begin
  case Mode of
    RENDER_DIFFUSE_LAMBERT: Result := 'lambert';
    RENDER_DIFFUSE_OREN_NAYAR: Result := 'oren-nayar';
  else
    Result := 'burley';
  end;
end;

function RenderInitGL(var R: TRenderer; const ShaderDir: string; W, H: Integer): Boolean;
var
  Err: string;
begin
  Err := '';
  R.Error := '';
  R.Ready := False;
  R.Width := Max(1, W);
  R.Height := Max(1, H);
  R.MeshCount := 0;
  SetLength(R.Meshes, 0);
  R.DiffuseMode := RENDER_DIFFUSE_BURLEY;
  RenderDefaultPost(R.Post);
  RenderDefaultFog(R.Fog);
  R.MainProg := BuildProgram(ShaderDir, 'mesh.vert', 'mesh.frag', Err);
  R.ShadowProg := BuildProgram(ShaderDir, 'shadow.vert', 'shadow.frag', Err);
  R.CompositeProg := BuildProgram(ShaderDir, 'fullscreen.vert', 'composite.frag', Err);
  R.BloomDownProg := BuildProgram(ShaderDir, 'fullscreen.vert', 'bloom_down.frag', Err);
  R.BlurProg := BuildProgram(ShaderDir, 'fullscreen.vert', 'blur.frag', Err);
  R.FxaaProg := BuildProgram(ShaderDir, 'fullscreen.vert', 'fxaa.frag', Err);
  if (R.MainProg = 0) or (R.ShadowProg = 0) or (R.CompositeProg = 0) or (R.BloomDownProg = 0)
     or (R.BlurProg = 0) or (R.FxaaProg = 0) then
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
  R.LocEmission := Loc(R.MainProg, 'uEmission');
  R.LocMetallic := Loc(R.MainProg, 'uMetallic');
  R.LocRoughness := Loc(R.MainProg, 'uRoughness');
  R.LocChecker := Loc(R.MainProg, 'uChecker');
  R.LocCheckerScale := Loc(R.MainProg, 'uCheckerScale');
  R.LocShadowMap := Loc(R.MainProg, 'uShadowMap');
  R.LocShadowTexel := Loc(R.MainProg, 'uShadowTexel');
  R.LocDiffuseMode := Loc(R.MainProg, 'uDiffuseMode');
  R.LocFogColor := Loc(R.MainProg, 'uFogColor');
  R.LocFogDensity := Loc(R.MainProg, 'uFogDensity');
  R.LocFogFalloff := Loc(R.MainProg, 'uFogFalloff');
  R.LocSModel := Loc(R.ShadowProg, 'uModel');
  R.LocSLightVP := Loc(R.ShadowProg, 'uLightViewProj');
  R.LocCompScene := Loc(R.CompositeProg, 'uScene');
  R.LocCompBloom[0] := Loc(R.CompositeProg, 'uBloom0');
  R.LocCompBloom[1] := Loc(R.CompositeProg, 'uBloom1');
  R.LocCompBloom[2] := Loc(R.CompositeProg, 'uBloom2');
  R.LocCompBloom[3] := Loc(R.CompositeProg, 'uBloom3');
  R.LocCompExposure := Loc(R.CompositeProg, 'uExposure');
  R.LocCompBloomStrength := Loc(R.CompositeProg, 'uBloomStrength');
  R.LocCompSaturation := Loc(R.CompositeProg, 'uSaturation');
  R.LocCompContrast := Loc(R.CompositeProg, 'uContrast');
  R.LocCompVignette := Loc(R.CompositeProg, 'uVignette');
  R.LocDownSrc := Loc(R.BloomDownProg, 'uSrc');
  R.LocDownTexel := Loc(R.BloomDownProg, 'uSrcTexel');
  R.LocDownThreshold := Loc(R.BloomDownProg, 'uThreshold');
  R.LocDownMode := Loc(R.BloomDownProg, 'uMode');
  R.LocBlurSrc := Loc(R.BlurProg, 'uSrc');
  R.LocBlurDir := Loc(R.BlurProg, 'uDir');
  R.LocFxaaLdr := Loc(R.FxaaProg, 'uLdr');
  R.LocFxaaTexel := Loc(R.FxaaProg, 'uTexel');
  R.LocFxaaOn := Loc(R.FxaaProg, 'uFxaa');

  CreateShadowTarget(R);
  glGenVertexArrays(1, @R.EmptyVao);
  CreateTargets(R);

  { Номера текстурных блоков фиксируются один раз: значения uniform-сэмплеров сохраняются в программе. }
  glUseProgram(R.MainProg);
  glUniform1i(R.LocShadowMap, 0);
  glUseProgram(R.CompositeProg);
  glUniform1i(R.LocCompScene, 0);
  glUniform1i(R.LocCompBloom[0], 1);
  glUniform1i(R.LocCompBloom[1], 2);
  glUniform1i(R.LocCompBloom[2], 3);
  glUniform1i(R.LocCompBloom[3], 4);
  glUseProgram(R.BloomDownProg);
  glUniform1i(R.LocDownSrc, 0);
  glUseProgram(R.BlurProg);
  glUniform1i(R.LocBlurSrc, 0);
  glUseProgram(R.FxaaProg);
  glUniform1i(R.LocFxaaLdr, 0);
  glUseProgram(0);

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
  W := Max(1, W);
  H := Max(1, H);
  if (W = R.Width) and (H = R.Height) then Exit;
  R.Width := W;
  R.Height := H;
  if R.Ready then
  begin
    DestroyTargets(R);
    CreateTargets(R);
  end;
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

procedure RunBloom(var R: TRenderer);
var
  I, W, H, SW, SH: Integer;
begin
  for I := 0 to RENDER_BLOOM_LEVELS - 1 do
  begin
    W := LevelW(R, I);
    H := LevelH(R, I);
    glBindFramebuffer(GL_FRAMEBUFFER, R.WorkFbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, R.BloomTex[I], 0);
    glViewport(0, 0, W, H);
    glUseProgram(R.BloomDownProg);
    if I = 0 then
    begin
      SW := R.Width;
      SH := R.Height;
      BindTexture(0, R.SceneTex);
      glUniform1i(R.LocDownMode, 0);
      glUniform1f(R.LocDownThreshold, R.Post.BloomThreshold);
    end
    else
    begin
      SW := LevelW(R, I - 1);
      SH := LevelH(R, I - 1);
      BindTexture(0, R.BloomTex[I - 1]);
      glUniform1i(R.LocDownMode, 1);
      glUniform1f(R.LocDownThreshold, 0.0);
    end;
    glUniform2f(R.LocDownTexel, 1.0 / SW, 1.0 / SH);
    DrawFullscreen(R);

    { Горизонтальный проход: BloomTex[I] -> BloomTmp[I]. }
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, R.BloomTmp[I], 0);
    glUseProgram(R.BlurProg);
    BindTexture(0, R.BloomTex[I]);
    glUniform2f(R.LocBlurDir, 1.0 / W, 0.0);
    DrawFullscreen(R);

    { Вертикальный проход: BloomTmp[I] -> BloomTex[I]. }
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, R.BloomTex[I], 0);
    BindTexture(0, R.BloomTmp[I]);
    glUniform2f(R.LocBlurDir, 0.0, 1.0 / H);
    DrawFullscreen(R);
  end;
end;

{ Кадр без обёртки исключений. }
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

  { Тест глубины включается в начале кадра: постобработка предыдущего кадра его выключает, а без теста
    карта теней получила бы самый поздний, а не ближайший треугольник. }
  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_LEQUAL);

  { --- 1. проход теней --- }
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

  { --- 2. основная сцена в HDR --- }
  View := Mat4LookAt(Cam.Eye, Cam.Target, Cam.Up);
  Proj := Mat4Perspective(Cam.FovY, R.Width / Max(1, R.Height), Cam.ZNear, Cam.ZFar);
  ViewProj := Mat4Mul(Proj, View);
  glBindFramebuffer(GL_FRAMEBUFFER, R.SceneFbo);
  glViewport(0, 0, R.Width, R.Height);
  glClearColor(R.Fog.Color.X, R.Fog.Color.Y, R.Fog.Color.Z, 1.0);
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
  glUniform1i(R.LocDiffuseMode, R.DiffuseMode);
  glUniform3f(R.LocFogColor, R.Fog.Color.X, R.Fog.Color.Y, R.Fog.Color.Z);
  glUniform1f(R.LocFogDensity, R.Fog.Density);
  glUniform1f(R.LocFogFalloff, R.Fog.Falloff);
  BindTexture(0, R.ShadowTex);
  for I := 0 to High(Items) do
  begin
    if (Items[I].Mesh < 0) or (Items[I].Mesh >= R.MeshCount) then Continue;
    F := Mat4ToF(Items[I].Model);
    glUniformMatrix4fv(R.LocModel, 1, GL_FALSE, PSingle(@F[0]));
    glUniform3f(R.LocTint, Items[I].Tint.X, Items[I].Tint.Y, Items[I].Tint.Z);
    glUniform3f(R.LocEmission, Items[I].Emission.X, Items[I].Emission.Y, Items[I].Emission.Z);
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

  { --- 3. блум --- }
  glDisable(GL_DEPTH_TEST);
  if R.Post.BloomStrength > 0.0 then
    RunBloom(R);

  { --- 4. композит: тонемаппинг и цветокоррекция в LDR --- }
  glBindFramebuffer(GL_FRAMEBUFFER, R.WorkFbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, R.LdrTex, 0);
  glViewport(0, 0, R.Width, R.Height);
  glUseProgram(R.CompositeProg);
  glUniform1f(R.LocCompExposure, R.Post.Exposure);
  glUniform1f(R.LocCompBloomStrength, R.Post.BloomStrength);
  glUniform1f(R.LocCompSaturation, R.Post.Saturation);
  glUniform1f(R.LocCompContrast, R.Post.Contrast);
  glUniform1f(R.LocCompVignette, R.Post.Vignette);
  BindTexture(0, R.SceneTex);
  for I := 0 to RENDER_BLOOM_LEVELS - 1 do
    BindTexture(I + 1, R.BloomTex[I]);
  DrawFullscreen(R);

  { --- 5. FXAA на экран --- }
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glViewport(0, 0, R.Width, R.Height);
  glUseProgram(R.FxaaProg);
  glUniform2f(R.LocFxaaTexel, 1.0 / R.Width, 1.0 / R.Height);
  if R.Post.Fxaa then
    glUniform1i(R.LocFxaaOn, 1)
  else
    glUniform1i(R.LocFxaaOn, 0);
  BindTexture(0, R.LdrTex);
  DrawFullscreen(R);
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
  DestroyTargets(R);
  if R.EmptyVao <> 0 then glDeleteVertexArrays(1, @R.EmptyVao);
  if R.ShadowFbo <> 0 then glDeleteFramebuffers(1, @R.ShadowFbo);
  if R.ShadowTex <> 0 then glDeleteTextures(1, @R.ShadowTex);
  if R.MainProg <> 0 then glDeleteProgram(R.MainProg);
  if R.ShadowProg <> 0 then glDeleteProgram(R.ShadowProg);
  if R.CompositeProg <> 0 then glDeleteProgram(R.CompositeProg);
  if R.BloomDownProg <> 0 then glDeleteProgram(R.BloomDownProg);
  if R.BlurProg <> 0 then glDeleteProgram(R.BlurProg);
  if R.FxaaProg <> 0 then glDeleteProgram(R.FxaaProg);
  R.EmptyVao := 0;
  R.ShadowFbo := 0;
  R.ShadowTex := 0;
  R.MainProg := 0;
  R.ShadowProg := 0;
  R.CompositeProg := 0;
  R.BloomDownProg := 0;
  R.BlurProg := 0;
  R.FxaaProg := 0;
  R.Ready := False;
end;

end.
