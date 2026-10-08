{ GLBind - привязки OpenGL 4.3 (core profile).

  Функции не линкуются статически: указатели загружаются через функцию получения адресов
  (glfwGetProcAddress или wglGetProcAddress/eglGetProcAddress). Так один и тот же код работает на
  Linux, Windows и macOS без системных библиотек OpenGL в зависимостях.

  Набор функций - то, что нужно движку: буферы, VAO, шейдеры, текстуры, кадровые буферы,
  чтение пикселей и отладочный вывод. Классов нет. }
unit GLBind;

{$mode objfpc}{$H+}

interface

type
  GLenum = Cardinal;
  GLbitfield = Cardinal;
  GLuint = Cardinal;
  GLint = Integer;
  GLsizei = Integer;
  GLboolean = Byte;
  GLfloat = Single;
  GLdouble = Double;
  GLintptr = PtrInt;
  GLsizeiptr = PtrInt;
  PGLuint = ^GLuint;
  PGLint = ^GLint;
  PGLchar = PChar;
  PGLfloat = ^GLfloat;

  TGLGetProc = function(Name: PChar): Pointer; cdecl;

  TGLDebugProc = procedure(Source, Kind, Id, Severity: GLenum; Length: GLsizei;
                           Message: PChar; UserParam: Pointer); cdecl;

  TglClearColor = procedure(R, G, B, A: GLfloat); cdecl;
  TglClear = procedure(Mask: GLbitfield); cdecl;
  TglEnable = procedure(Cap: GLenum); cdecl;
  TglDisable = procedure(Cap: GLenum); cdecl;
  TglViewport = procedure(X, Y: GLint; W, H: GLsizei); cdecl;
  TglDepthFunc = procedure(Func: GLenum); cdecl;
  TglDepthMask = procedure(Flag: GLboolean); cdecl;
  TglCullFace = procedure(Mode: GLenum); cdecl;
  TglFrontFace = procedure(Mode: GLenum); cdecl;
  TglGetError = function: GLenum; cdecl;
  TglGetString = function(Name: GLenum): PChar; cdecl;
  TglGetIntegerv = procedure(Pname: GLenum; Data: PGLint); cdecl;
  TglPixelStorei = procedure(Pname: GLenum; Param: GLint); cdecl;
  TglReadPixels = procedure(X, Y: GLint; W, H: GLsizei; Format, Kind: GLenum; Data: Pointer); cdecl;
  TglReadBuffer = procedure(Mode: GLenum); cdecl;
  TglDrawBuffer = procedure(Mode: GLenum); cdecl;
  TglFinish = procedure; cdecl;
  TglDrawElements = procedure(Mode: GLenum; Count: GLsizei; Kind: GLenum; Indices: Pointer); cdecl;
  TglGenBuffers = procedure(N: GLsizei; Buffers: PGLuint); cdecl;
  TglDeleteBuffers = procedure(N: GLsizei; Buffers: PGLuint); cdecl;
  TglBindBuffer = procedure(Target: GLenum; Buffer: GLuint); cdecl;
  TglBufferData = procedure(Target: GLenum; Size: GLsizeiptr; Data: Pointer; Usage: GLenum); cdecl;
  TglGenVertexArrays = procedure(N: GLsizei; Arrays: PGLuint); cdecl;
  TglDeleteVertexArrays = procedure(N: GLsizei; Arrays: PGLuint); cdecl;
  TglBindVertexArray = procedure(Arr: GLuint); cdecl;
  TglVertexAttribPointer = procedure(Index: GLuint; Size: GLint; Kind: GLenum; Normalized: GLboolean;
                                     Stride: GLsizei; Pointer_: Pointer); cdecl;
  TglEnableVertexAttribArray = procedure(Index: GLuint); cdecl;
  TglCreateShader = function(Kind: GLenum): GLuint; cdecl;
  TglDeleteShader = procedure(Shader: GLuint); cdecl;
  TglShaderSource = procedure(Shader: GLuint; Count: GLsizei; Strings: PPChar; Lengths: PGLint); cdecl;
  TglCompileShader = procedure(Shader: GLuint); cdecl;
  TglGetShaderiv = procedure(Shader: GLuint; Pname: GLenum; Params: PGLint); cdecl;
  TglGetShaderInfoLog = procedure(Shader: GLuint; MaxLen: GLsizei; Len: PGLint; Log: PChar); cdecl;
  TglCreateProgram = function: GLuint; cdecl;
  TglDeleteProgram = procedure(Prog: GLuint); cdecl;
  TglAttachShader = procedure(Prog, Shader: GLuint); cdecl;
  TglLinkProgram = procedure(Prog: GLuint); cdecl;
  TglGetProgramiv = procedure(Prog: GLuint; Pname: GLenum; Params: PGLint); cdecl;
  TglGetProgramInfoLog = procedure(Prog: GLuint; MaxLen: GLsizei; Len: PGLint; Log: PChar); cdecl;
  TglUseProgram = procedure(Prog: GLuint); cdecl;
  TglGetUniformLocation = function(Prog: GLuint; Name: PChar): GLint; cdecl;
  TglUniformMatrix4fv = procedure(Loc: GLint; Count: GLsizei; Transpose: GLboolean; Value: PGLfloat); cdecl;
  TglUniform3f = procedure(Loc: GLint; X, Y, Z: GLfloat); cdecl;
  TglUniform1i = procedure(Loc: GLint; V: GLint); cdecl;
  TglUniform1f = procedure(Loc: GLint; V: GLfloat); cdecl;
  TglGenTextures = procedure(N: GLsizei; Textures: PGLuint); cdecl;
  TglDeleteTextures = procedure(N: GLsizei; Textures: PGLuint); cdecl;
  TglBindTexture = procedure(Target: GLenum; Tex: GLuint); cdecl;
  TglTexImage2D = procedure(Target: GLenum; Level, Internal: GLint; W, H: GLsizei; Border: GLint;
                            Format, Kind: GLenum; Data: Pointer); cdecl;
  TglTexParameteri = procedure(Target, Pname: GLenum; Param: GLint); cdecl;
  TglActiveTexture = procedure(Unit_: GLenum); cdecl;
  TglGenFramebuffers = procedure(N: GLsizei; Frames: PGLuint); cdecl;
  TglDeleteFramebuffers = procedure(N: GLsizei; Frames: PGLuint); cdecl;
  TglBindFramebuffer = procedure(Target: GLenum; Frame: GLuint); cdecl;
  TglFramebufferTexture2D = procedure(Target, Attach, TexTarget: GLenum; Tex: GLuint; Level: GLint); cdecl;
  TglCheckFramebufferStatus = function(Target: GLenum): GLenum; cdecl;
  TglDebugMessageCallback = procedure(Callback: TGLDebugProc; UserParam: Pointer); cdecl;
  TglDebugMessageControl = procedure(Source, Kind, Severity: GLenum; Count: GLsizei;
                                     Ids: Pointer; Enabled: GLboolean); cdecl;

var
  glClearColor: TglClearColor;
  glClear: TglClear;
  glEnable: TglEnable;
  glDisable: TglDisable;
  glViewport: TglViewport;
  glDepthFunc: TglDepthFunc;
  glDepthMask: TglDepthMask;
  glCullFace: TglCullFace;
  glFrontFace: TglFrontFace;
  glGetError: TglGetError;
  glGetString: TglGetString;
  glGetIntegerv: TglGetIntegerv;
  glPixelStorei: TglPixelStorei;
  glReadPixels: TglReadPixels;
  glReadBuffer: TglReadBuffer;
  glDrawBuffer: TglDrawBuffer;
  glFinish: TglFinish;
  glDrawElements: TglDrawElements;
  glGenBuffers: TglGenBuffers;
  glDeleteBuffers: TglDeleteBuffers;
  glBindBuffer: TglBindBuffer;
  glBufferData: TglBufferData;
  glGenVertexArrays: TglGenVertexArrays;
  glDeleteVertexArrays: TglDeleteVertexArrays;
  glBindVertexArray: TglBindVertexArray;
  glVertexAttribPointer: TglVertexAttribPointer;
  glEnableVertexAttribArray: TglEnableVertexAttribArray;
  glCreateShader: TglCreateShader;
  glDeleteShader: TglDeleteShader;
  glShaderSource: TglShaderSource;
  glCompileShader: TglCompileShader;
  glGetShaderiv: TglGetShaderiv;
  glGetShaderInfoLog: TglGetShaderInfoLog;
  glCreateProgram: TglCreateProgram;
  glDeleteProgram: TglDeleteProgram;
  glAttachShader: TglAttachShader;
  glLinkProgram: TglLinkProgram;
  glGetProgramiv: TglGetProgramiv;
  glGetProgramInfoLog: TglGetProgramInfoLog;
  glUseProgram: TglUseProgram;
  glGetUniformLocation: TglGetUniformLocation;
  glUniformMatrix4fv: TglUniformMatrix4fv;
  glUniform3f: TglUniform3f;
  glUniform1i: TglUniform1i;
  glUniform1f: TglUniform1f;
  glGenTextures: TglGenTextures;
  glDeleteTextures: TglDeleteTextures;
  glBindTexture: TglBindTexture;
  glTexImage2D: TglTexImage2D;
  glTexParameteri: TglTexParameteri;
  glActiveTexture: TglActiveTexture;
  glGenFramebuffers: TglGenFramebuffers;
  glDeleteFramebuffers: TglDeleteFramebuffers;
  glBindFramebuffer: TglBindFramebuffer;
  glFramebufferTexture2D: TglFramebufferTexture2D;
  glCheckFramebufferStatus: TglCheckFramebufferStatus;
  { необязательные (отладка, KHR_debug входит в ядро 4.3) }
  glDebugMessageCallback: TglDebugMessageCallback;
  glDebugMessageControl: TglDebugMessageControl;

const
  GL_FALSE = 0;
  GL_TRUE = 1;
  GL_NONE = 0;
  GL_POINTS = $0000;
  GL_LINES = $0001;
  GL_TRIANGLES = $0004;
  GL_FRONT = $0404;
  GL_BACK = $0405;
  GL_CW = $0900;
  GL_CCW = $0901;
  GL_CULL_FACE = $0B44;
  GL_DEPTH_TEST = $0B71;
  GL_BLEND = $0BE2;
  GL_VIEWPORT = $0BA2;
  GL_LESS = $0201;
  GL_LEQUAL = $0203;
  GL_SRC_ALPHA = $0302;
  GL_ONE_MINUS_SRC_ALPHA = $0303;
  GL_NO_ERROR = 0;
  GL_UNSIGNED_BYTE = $1401;
  GL_UNSIGNED_INT = $1405;
  GL_FLOAT = $1406;
  GL_RGB = $1907;
  GL_RGBA = $1908;
  GL_DEPTH_COMPONENT = $1902;
  GL_RGBA8 = $8058;
  GL_RGB8 = $8051;
  GL_DEPTH_COMPONENT24 = $81A6;
  GL_DEPTH_COMPONENT32F = $8CAC;
  GL_COLOR_BUFFER_BIT = $00004000;
  GL_DEPTH_BUFFER_BIT = $00000100;
  GL_ARRAY_BUFFER = $8892;
  GL_ELEMENT_ARRAY_BUFFER = $8893;
  GL_STATIC_DRAW = $88E4;
  GL_DYNAMIC_DRAW = $88E8;
  GL_TEXTURE_2D = $0DE1;
  GL_TEXTURE0 = $84C0;
  GL_TEXTURE_MAG_FILTER = $2800;
  GL_TEXTURE_MIN_FILTER = $2801;
  GL_TEXTURE_WRAP_S = $2802;
  GL_TEXTURE_WRAP_T = $2803;
  GL_NEAREST = $2600;
  GL_LINEAR = $2601;
  GL_CLAMP_TO_EDGE = $812F;
  GL_TEXTURE_COMPARE_MODE = $884C;
  GL_TEXTURE_COMPARE_FUNC = $884D;
  GL_COMPARE_REF_TO_TEXTURE = $884E;
  GL_FRAMEBUFFER = $8D40;
  GL_FRAMEBUFFER_COMPLETE = $8CD5;
  GL_DEPTH_ATTACHMENT = $8D00;
  GL_COLOR_ATTACHMENT0 = $8CE0;
  GL_VERTEX_SHADER = $8B31;
  GL_FRAGMENT_SHADER = $8B30;
  GL_COMPILE_STATUS = $8B81;
  GL_LINK_STATUS = $8B82;
  GL_INFO_LOG_LENGTH = $8B84;
  GL_VERSION = $1F02;
  GL_RENDERER = $1F01;
  GL_VENDOR = $1F00;
  GL_SHADING_LANGUAGE_VERSION = $8B8C;
  GL_MAJOR_VERSION = $821B;
  GL_MINOR_VERSION = $821C;
  GL_PACK_ALIGNMENT = $0D05;
  GL_UNPACK_ALIGNMENT = $0CF5;
  GL_READ_BUFFER = $0C02;
  GL_DEBUG_OUTPUT = $92E0;
  GL_DEBUG_OUTPUT_SYNCHRONOUS = $8242;
  GL_DONT_CARE = $1100;
  GL_DEBUG_SEVERITY_HIGH = $9146;
  GL_DEBUG_SEVERITY_MEDIUM = $9147;
  GL_DEBUG_SEVERITY_LOW = $9148;
  GL_DEBUG_SEVERITY_NOTIFICATION = $826B;

{ Загрузка всех функций. Возвращает число обязательных функций, которых нет (0 - всё в порядке). }
function GLLoadFunctions(GetProc: TGLGetProc): Integer;
{ Версия контекста: True, если не меньше Major.Minor. }
function GLVersionAtLeast(Major, Minor: Integer): Boolean;
function GLVersionString: string;

implementation

uses
  SysUtils;

var
  GMissing: Integer;

function LoadOne(GetProc: TGLGetProc; const Name: string; Required: Boolean): Pointer;
begin
  Result := GetProc(PChar(Name));
  if (Result = nil) and Required then
  begin
    WriteLn(ErrOutput, 'GLBind: нет функции ', Name);
    Inc(GMissing);
  end;
end;

function GLLoadFunctions(GetProc: TGLGetProc): Integer;
begin
  GMissing := 0;
  glClearColor := TglClearColor(LoadOne(GetProc, 'glClearColor', True));
  glClear := TglClear(LoadOne(GetProc, 'glClear', True));
  glEnable := TglEnable(LoadOne(GetProc, 'glEnable', True));
  glDisable := TglDisable(LoadOne(GetProc, 'glDisable', True));
  glViewport := TglViewport(LoadOne(GetProc, 'glViewport', True));
  glDepthFunc := TglDepthFunc(LoadOne(GetProc, 'glDepthFunc', True));
  glDepthMask := TglDepthMask(LoadOne(GetProc, 'glDepthMask', True));
  glCullFace := TglCullFace(LoadOne(GetProc, 'glCullFace', True));
  glFrontFace := TglFrontFace(LoadOne(GetProc, 'glFrontFace', True));
  glGetError := TglGetError(LoadOne(GetProc, 'glGetError', True));
  glGetString := TglGetString(LoadOne(GetProc, 'glGetString', True));
  glGetIntegerv := TglGetIntegerv(LoadOne(GetProc, 'glGetIntegerv', True));
  glPixelStorei := TglPixelStorei(LoadOne(GetProc, 'glPixelStorei', True));
  glReadPixels := TglReadPixels(LoadOne(GetProc, 'glReadPixels', True));
  glReadBuffer := TglReadBuffer(LoadOne(GetProc, 'glReadBuffer', True));
  glDrawBuffer := TglDrawBuffer(LoadOne(GetProc, 'glDrawBuffer', True));
  glFinish := TglFinish(LoadOne(GetProc, 'glFinish', True));
  glDrawElements := TglDrawElements(LoadOne(GetProc, 'glDrawElements', True));
  glGenBuffers := TglGenBuffers(LoadOne(GetProc, 'glGenBuffers', True));
  glDeleteBuffers := TglDeleteBuffers(LoadOne(GetProc, 'glDeleteBuffers', True));
  glBindBuffer := TglBindBuffer(LoadOne(GetProc, 'glBindBuffer', True));
  glBufferData := TglBufferData(LoadOne(GetProc, 'glBufferData', True));
  glGenVertexArrays := TglGenVertexArrays(LoadOne(GetProc, 'glGenVertexArrays', True));
  glDeleteVertexArrays := TglDeleteVertexArrays(LoadOne(GetProc, 'glDeleteVertexArrays', True));
  glBindVertexArray := TglBindVertexArray(LoadOne(GetProc, 'glBindVertexArray', True));
  glVertexAttribPointer := TglVertexAttribPointer(LoadOne(GetProc, 'glVertexAttribPointer', True));
  glEnableVertexAttribArray := TglEnableVertexAttribArray(LoadOne(GetProc, 'glEnableVertexAttribArray', True));
  glCreateShader := TglCreateShader(LoadOne(GetProc, 'glCreateShader', True));
  glDeleteShader := TglDeleteShader(LoadOne(GetProc, 'glDeleteShader', True));
  glShaderSource := TglShaderSource(LoadOne(GetProc, 'glShaderSource', True));
  glCompileShader := TglCompileShader(LoadOne(GetProc, 'glCompileShader', True));
  glGetShaderiv := TglGetShaderiv(LoadOne(GetProc, 'glGetShaderiv', True));
  glGetShaderInfoLog := TglGetShaderInfoLog(LoadOne(GetProc, 'glGetShaderInfoLog', True));
  glCreateProgram := TglCreateProgram(LoadOne(GetProc, 'glCreateProgram', True));
  glDeleteProgram := TglDeleteProgram(LoadOne(GetProc, 'glDeleteProgram', True));
  glAttachShader := TglAttachShader(LoadOne(GetProc, 'glAttachShader', True));
  glLinkProgram := TglLinkProgram(LoadOne(GetProc, 'glLinkProgram', True));
  glGetProgramiv := TglGetProgramiv(LoadOne(GetProc, 'glGetProgramiv', True));
  glGetProgramInfoLog := TglGetProgramInfoLog(LoadOne(GetProc, 'glGetProgramInfoLog', True));
  glUseProgram := TglUseProgram(LoadOne(GetProc, 'glUseProgram', True));
  glGetUniformLocation := TglGetUniformLocation(LoadOne(GetProc, 'glGetUniformLocation', True));
  glUniformMatrix4fv := TglUniformMatrix4fv(LoadOne(GetProc, 'glUniformMatrix4fv', True));
  glUniform3f := TglUniform3f(LoadOne(GetProc, 'glUniform3f', True));
  glUniform1i := TglUniform1i(LoadOne(GetProc, 'glUniform1i', True));
  glUniform1f := TglUniform1f(LoadOne(GetProc, 'glUniform1f', True));
  glGenTextures := TglGenTextures(LoadOne(GetProc, 'glGenTextures', True));
  glDeleteTextures := TglDeleteTextures(LoadOne(GetProc, 'glDeleteTextures', True));
  glBindTexture := TglBindTexture(LoadOne(GetProc, 'glBindTexture', True));
  glTexImage2D := TglTexImage2D(LoadOne(GetProc, 'glTexImage2D', True));
  glTexParameteri := TglTexParameteri(LoadOne(GetProc, 'glTexParameteri', True));
  glActiveTexture := TglActiveTexture(LoadOne(GetProc, 'glActiveTexture', True));
  glGenFramebuffers := TglGenFramebuffers(LoadOne(GetProc, 'glGenFramebuffers', True));
  glDeleteFramebuffers := TglDeleteFramebuffers(LoadOne(GetProc, 'glDeleteFramebuffers', True));
  glBindFramebuffer := TglBindFramebuffer(LoadOne(GetProc, 'glBindFramebuffer', True));
  glFramebufferTexture2D := TglFramebufferTexture2D(LoadOne(GetProc, 'glFramebufferTexture2D', True));
  glCheckFramebufferStatus := TglCheckFramebufferStatus(LoadOne(GetProc, 'glCheckFramebufferStatus', True));
  glDebugMessageCallback := TglDebugMessageCallback(LoadOne(GetProc, 'glDebugMessageCallback', False));
  glDebugMessageControl := TglDebugMessageControl(LoadOne(GetProc, 'glDebugMessageControl', False));
  Result := GMissing;
end;

function GLVersionAtLeast(Major, Minor: Integer): Boolean;
var
  Mj, Mn: GLint;
begin
  Mj := 0;
  Mn := 0;
  glGetIntegerv(GL_MAJOR_VERSION, @Mj);
  glGetIntegerv(GL_MINOR_VERSION, @Mn);
  Result := (Mj > Major) or ((Mj = Major) and (Mn >= Minor));
end;

function GLVersionString: string;
var
  P: PChar;
begin
  P := glGetString(GL_VERSION);
  if P = nil then
    Result := '(нет контекста)'
  else
    Result := string(P);
end;

end.
