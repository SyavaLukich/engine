{ GLFixedBind - функции фиксированного конвейера OpenGL 1.x/2.x (glBegin-эпоха, массивы вершин,
  освещение и текстуры без шейдеров) для снимков через OSMesa.

  Функции берутся через адрес-загрузчик (OSMesaGetProcAddress). Имена переменных начинаются с fx,
  типы - с Tfx, чтобы модуль не конфликтовал с GLBind (шейдерный путь OpenGL 4.3).
  Константы совпадают с gl.h. Используется только вызовами EngFixedGL. }
unit GLFixedBind;

{$mode objfpc}{$H+}

interface

const
  GL_FALSE = 0;
  GL_TRUE = 1;
  GL_VERSION = $1F02;
  GL_RENDERER = $1F01;
  GL_COLOR_BUFFER_BIT = $00004000;
  GL_DEPTH_BUFFER_BIT = $00000100;
  GL_TRIANGLES = $0004;
  GL_SMOOTH = $1D01;
  GL_DEPTH_TEST = $0B71;
  GL_LEQUAL = $0203;
  GL_LIGHTING = $0B50;
  GL_LIGHT0 = $4000;
  GL_NORMALIZE = $0BA1;
  GL_COLOR_MATERIAL = $0B57;
  GL_LIGHT_MODEL_AMBIENT = $0B53;
  GL_POSITION = $1203;
  GL_AMBIENT = $1200;
  GL_DIFFUSE = $1201;
  GL_SPECULAR = $1202;
  GL_SHININESS = $1601;
  GL_AMBIENT_AND_DIFFUSE = $1602;
  GL_FRONT = $0404;
  GL_FRONT_AND_BACK = $0408;
  GL_PROJECTION = $1701;
  GL_MODELVIEW = $1700;
  GL_TEXTURE_2D = $0DE1;
  GL_TEXTURE_GEN_S = $0C60;
  GL_TEXTURE_GEN_T = $0C61;
  GL_TEXTURE_GEN_MODE = $2500;
  GL_OBJECT_LINEAR = $2401;
  GL_OBJECT_PLANE = $2501;
  GL_S = $2000;
  GL_T = $2001;
  GL_NEAREST = $2600;
  GL_TEXTURE_MAG_FILTER = $2800;
  GL_TEXTURE_MIN_FILTER = $2801;
  GL_TEXTURE_WRAP_S = $2802;
  GL_TEXTURE_WRAP_T = $2803;
  GL_REPEAT = $2901;
  GL_VERTEX_ARRAY = $8074;
  GL_NORMAL_ARRAY = $8075;
  GL_COLOR_ARRAY = $8076;
  GL_UNSIGNED_BYTE = $1401;
  GL_UNSIGNED_INT = $1405;
  GL_FLOAT = $1406;
  GL_RGB = $1907;
  GL_RGBA = $1908;
  GL_PACK_ALIGNMENT = $0D05;
  GL_UNPACK_ALIGNMENT = $0CF5;

type
  TFixedGetProc = function(Name: PChar): Pointer; cdecl;

  TfxGetString = function(Name: LongWord): PChar; cdecl;
  TfxGetError = function: LongWord; cdecl;
  TfxProc = procedure; cdecl;
  TfxClearColor = procedure(R, G, B, A: Single); cdecl;
  TfxClear = procedure(Mask: LongWord); cdecl;
  TfxViewport = procedure(X, Y, W, H: LongInt); cdecl;
  TfxCap = procedure(Cap: LongWord); cdecl;
  TfxEnum1 = procedure(Value: LongWord); cdecl;
  TfxEnum2 = procedure(A, B: LongWord); cdecl;
  TfxLoadMatrix = procedure(M: PSingle); cdecl;
  TfxLight = procedure(Light, Pname: LongWord; Params: PSingle); cdecl;
  TfxLightModel = procedure(Pname: LongWord; Params: PSingle); cdecl;
  TfxMaterial = procedure(Face, Pname: LongWord; Params: PSingle); cdecl;
  TfxColor3f = procedure(R, G, B: Single); cdecl;
  TfxVertexPointer = procedure(Size: LongInt; Kind: LongWord; Stride: LongInt; Ptr: Pointer); cdecl;
  TfxNormalPointer = procedure(Kind: LongWord; Stride: LongInt; Ptr: Pointer); cdecl;
  TfxDrawElements = procedure(Mode: LongWord; Count: LongInt; Kind: LongWord; Indices: Pointer); cdecl;
  TfxGenTextures = procedure(N: LongInt; Tex: PLongWord); cdecl;
  TfxBindTexture = procedure(Target, Tex: LongWord); cdecl;
  TfxTexImage2D = procedure(Target: LongWord; Level, Internal, W, H, Border: LongInt;
                            Format, Kind: LongWord; Pixels: Pointer); cdecl;
  TfxTexParam = procedure(Target, Pname: LongWord; Param: LongInt); cdecl;
  TfxTexGeni = procedure(Coord, Pname: LongWord; Param: LongInt); cdecl;
  TfxTexGenfv = procedure(Coord, Pname: LongWord; Params: PSingle); cdecl;
  TfxReadPixels = procedure(X, Y, W, H: LongInt; Format, Kind: LongWord; Pixels: Pointer); cdecl;
  TfxPixelStore = procedure(Pname: LongWord; Param: LongInt); cdecl;

var
  fxGetString: TfxGetString = nil;
  fxGetError: TfxGetError = nil;
  fxFinish: TfxProc = nil;
  fxClearColor: TfxClearColor = nil;
  fxClear: TfxClear = nil;
  fxViewport: TfxViewport = nil;
  fxEnable: TfxCap = nil;
  fxDisable: TfxCap = nil;
  fxDepthFunc: TfxEnum1 = nil;
  fxShadeModel: TfxEnum1 = nil;
  fxMatrixMode: TfxEnum1 = nil;
  fxLoadIdentity: TfxProc = nil;
  fxLoadMatrixf: TfxLoadMatrix = nil;
  fxLightfv: TfxLight = nil;
  fxLightModelfv: TfxLightModel = nil;
  fxMaterialfv: TfxMaterial = nil;
  fxColorMaterial: TfxEnum2 = nil;
  fxColor3f: TfxColor3f = nil;
  fxEnableClientState: TfxEnum1 = nil;
  fxDisableClientState: TfxEnum1 = nil;
  fxVertexPointer: TfxVertexPointer = nil;
  fxNormalPointer: TfxNormalPointer = nil;
  fxColorPointer: TfxVertexPointer = nil;
  fxDrawElements: TfxDrawElements = nil;
  fxGenTextures: TfxGenTextures = nil;
  fxBindTexture: TfxBindTexture = nil;
  fxTexImage2D: TfxTexImage2D = nil;
  fxTexParameteri: TfxTexParam = nil;
  fxTexEnvi: TfxTexParam = nil;
  fxTexGeni: TfxTexGeni = nil;
  fxTexGenfv: TfxTexGenfv = nil;
  fxReadPixels: TfxReadPixels = nil;
  fxPixelStorei: TfxPixelStore = nil;

{ Загружает все функции через GetProc. Возвращает число отсутствующих функций (0 - всё на месте). }
function FixedLoad(GetProc: TFixedGetProc): Integer;

implementation

function FixedLoad(GetProc: TFixedGetProc): Integer;
var
  Missing: Integer;

  function Load(const Name: string): Pointer;
  begin
    Result := GetProc(PChar(Name));
    if Result = nil then
      Inc(Missing);
  end;

begin
  Missing := 0;
  fxGetString := TfxGetString(Load('glGetString'));
  fxGetError := TfxGetError(Load('glGetError'));
  fxFinish := TfxProc(Load('glFinish'));
  fxClearColor := TfxClearColor(Load('glClearColor'));
  fxClear := TfxClear(Load('glClear'));
  fxViewport := TfxViewport(Load('glViewport'));
  fxEnable := TfxCap(Load('glEnable'));
  fxDisable := TfxCap(Load('glDisable'));
  fxDepthFunc := TfxEnum1(Load('glDepthFunc'));
  fxShadeModel := TfxEnum1(Load('glShadeModel'));
  fxMatrixMode := TfxEnum1(Load('glMatrixMode'));
  fxLoadIdentity := TfxProc(Load('glLoadIdentity'));
  fxLoadMatrixf := TfxLoadMatrix(Load('glLoadMatrixf'));
  fxLightfv := TfxLight(Load('glLightfv'));
  fxLightModelfv := TfxLightModel(Load('glLightModelfv'));
  fxMaterialfv := TfxMaterial(Load('glMaterialfv'));
  fxColorMaterial := TfxEnum2(Load('glColorMaterial'));
  fxColor3f := TfxColor3f(Load('glColor3f'));
  fxEnableClientState := TfxEnum1(Load('glEnableClientState'));
  fxDisableClientState := TfxEnum1(Load('glDisableClientState'));
  fxVertexPointer := TfxVertexPointer(Load('glVertexPointer'));
  fxNormalPointer := TfxNormalPointer(Load('glNormalPointer'));
  fxColorPointer := TfxVertexPointer(Load('glColorPointer'));
  fxDrawElements := TfxDrawElements(Load('glDrawElements'));
  fxGenTextures := TfxGenTextures(Load('glGenTextures'));
  fxBindTexture := TfxBindTexture(Load('glBindTexture'));
  fxTexImage2D := TfxTexImage2D(Load('glTexImage2D'));
  fxTexParameteri := TfxTexParam(Load('glTexParameteri'));
  fxTexEnvi := TfxTexParam(Load('glTexEnvi'));
  fxTexGeni := TfxTexGeni(Load('glTexGeni'));
  fxTexGenfv := TfxTexGenfv(Load('glTexGenfv'));
  fxReadPixels := TfxReadPixels(Load('glReadPixels'));
  fxPixelStorei := TfxPixelStore(Load('glPixelStorei'));
  Result := Missing;
end;

end.
