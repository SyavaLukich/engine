{ GLFWBind - привязка к GLFW 3 с динамической загрузкой библиотеки (dynlibs).

  Библиотека ищется по имени: Linux - libglfw.so.3 / libglfw.so, Windows - glfw3.dll (рядом с exe),
  macOS - libglfw.3.dylib. Если библиотеки нет, GLFWLoad возвращает False и причину в GLFWLastError.
  Отдельной линковки с GLFW на этапе сборки не нужно, поэтому сборка проходит без dev-пакетов. }
unit GLFWBind;

{$mode objfpc}{$H+}

interface

uses
  dynlibs;

const
  GLFW_TRUE = 1;
  GLFW_FALSE = 0;
  GLFW_PRESS = 1;
  GLFW_RELEASE = 0;
  GLFW_KEY_SPACE = 32;
  GLFW_KEY_R = 82;
  GLFW_KEY_P = 80;
  GLFW_KEY_ESCAPE = 256;
  GLFW_KEY_F12 = 301;
  GLFW_KEY_LEFT = 263;
  GLFW_KEY_RIGHT = 262;
  GLFW_KEY_UP = 265;
  GLFW_KEY_DOWN = 264;
  GLFW_CONTEXT_VERSION_MAJOR = $00022002;
  GLFW_CONTEXT_VERSION_MINOR = $00022003;
  GLFW_OPENGL_FORWARD_COMPAT = $00022006;
  GLFW_OPENGL_PROFILE = $00022008;
  GLFW_OPENGL_DEBUG_CONTEXT = $00022007;
  GLFW_OPENGL_CORE_PROFILE = $00032001;
  GLFW_RESIZABLE = $00020003;
  GLFW_SAMPLES = $0002100D;
  GLFW_NO_ERROR = 0;

type
  TGLFWwindow = Pointer;
  TGLFWerrorfun = procedure(Code: Integer; Desc: PChar); cdecl;

  TglfwInit = function: Integer; cdecl;
  TglfwTerminate = procedure; cdecl;
  TglfwWindowHint = procedure(Hint, Value: Integer); cdecl;
  TglfwCreateWindow = function(W, H: Integer; Title: PChar; Monitor, Share: Pointer): TGLFWwindow; cdecl;
  TglfwDestroyWindow = procedure(Win: TGLFWwindow); cdecl;
  TglfwMakeContextCurrent = procedure(Win: TGLFWwindow); cdecl;
  TglfwSwapInterval = procedure(Interval: Integer); cdecl;
  TglfwSwapBuffers = procedure(Win: TGLFWwindow); cdecl;
  TglfwPollEvents = procedure; cdecl;
  TglfwWindowShouldClose = function(Win: TGLFWwindow): Integer; cdecl;
  TglfwSetWindowShouldClose = procedure(Win: TGLFWwindow; Value: Integer); cdecl;
  TglfwGetFramebufferSize = procedure(Win: TGLFWwindow; W, H: PInteger); cdecl;
  TglfwGetKey = function(Win: TGLFWwindow; Key: Integer): Integer; cdecl;
  TglfwGetTime = function: Double; cdecl;
  TglfwGetProcAddress = function(Name: PChar): Pointer; cdecl;
  TglfwGetError = function(Desc: PPChar): Integer; cdecl;
  TglfwSetErrorCallback = function(Cb: TGLFWerrorfun): Pointer; cdecl;

var
  glfwInit: TglfwInit;
  glfwTerminate: TglfwTerminate;
  glfwWindowHint: TglfwWindowHint;
  glfwCreateWindow: TglfwCreateWindow;
  glfwDestroyWindow: TglfwDestroyWindow;
  glfwMakeContextCurrent: TglfwMakeContextCurrent;
  glfwSwapInterval: TglfwSwapInterval;
  glfwSwapBuffers: TglfwSwapBuffers;
  glfwPollEvents: TglfwPollEvents;
  glfwWindowShouldClose: TglfwWindowShouldClose;
  glfwSetWindowShouldClose: TglfwSetWindowShouldClose;
  glfwGetFramebufferSize: TglfwGetFramebufferSize;
  glfwGetKey: TglfwGetKey;
  glfwGetTime: TglfwGetTime;
  glfwGetProcAddress: TglfwGetProcAddress;
  glfwGetError: TglfwGetError;
  glfwSetErrorCallback: TglfwSetErrorCallback;

{ Загрузка библиотеки и функций. Path - полный путь или пустая строка (поиск по умолчанию). }
function GLFWLoad(const Path: string): Boolean;
procedure GLFWUnload;
function GLFWLastError: string;

implementation

var
  GLib: TLibHandle = NilHandle;
  GLastError: string = '';

function LoadFn(const Name: string): Pointer;
begin
  Result := GetProcedureAddress(GLib, Name);
  if Result = nil then
    GLastError := 'в библиотеке GLFW нет функции ' + Name;
end;

function GLFWLoad(const Path: string): Boolean;
var
  Candidates: array of string;
  I: Integer;
begin
  Result := False;
  if GLib <> NilHandle then
  begin
    Result := True;
    Exit;
  end;
  if Path <> '' then
  begin
    SetLength(Candidates, 1);
    Candidates[0] := Path;
  end
  else
  begin
    {$IFDEF WINDOWS}
    SetLength(Candidates, 2);
    Candidates[0] := 'glfw3.dll';
    Candidates[1] := 'glfw.dll';
    {$ELSE}
    {$IFDEF DARWIN}
    SetLength(Candidates, 2);
    Candidates[0] := 'libglfw.3.dylib';
    Candidates[1] := 'libglfw.dylib';
    {$ELSE}
    SetLength(Candidates, 3);
    Candidates[0] := 'libglfw.so.3';
    Candidates[1] := 'libglfw.so';
    Candidates[2] := 'libglfw3.so';
    {$ENDIF}
    {$ENDIF}
  end;
  for I := 0 to High(Candidates) do
  begin
    GLib := LoadLibrary(Candidates[I]);
    if GLib <> NilHandle then Break;
  end;
  if GLib = NilHandle then
  begin
    GLastError := 'не найдена библиотека GLFW (ожидалась ' + Candidates[0] + ')';
    Exit;
  end;

  glfwInit := TglfwInit(LoadFn('glfwInit'));
  glfwTerminate := TglfwTerminate(LoadFn('glfwTerminate'));
  glfwWindowHint := TglfwWindowHint(LoadFn('glfwWindowHint'));
  glfwCreateWindow := TglfwCreateWindow(LoadFn('glfwCreateWindow'));
  glfwDestroyWindow := TglfwDestroyWindow(LoadFn('glfwDestroyWindow'));
  glfwMakeContextCurrent := TglfwMakeContextCurrent(LoadFn('glfwMakeContextCurrent'));
  glfwSwapInterval := TglfwSwapInterval(LoadFn('glfwSwapInterval'));
  glfwSwapBuffers := TglfwSwapBuffers(LoadFn('glfwSwapBuffers'));
  glfwPollEvents := TglfwPollEvents(LoadFn('glfwPollEvents'));
  glfwWindowShouldClose := TglfwWindowShouldClose(LoadFn('glfwWindowShouldClose'));
  glfwSetWindowShouldClose := TglfwSetWindowShouldClose(LoadFn('glfwSetWindowShouldClose'));
  glfwGetFramebufferSize := TglfwGetFramebufferSize(LoadFn('glfwGetFramebufferSize'));
  glfwGetKey := TglfwGetKey(LoadFn('glfwGetKey'));
  glfwGetTime := TglfwGetTime(LoadFn('glfwGetTime'));
  glfwGetProcAddress := TglfwGetProcAddress(LoadFn('glfwGetProcAddress'));
  glfwGetError := TglfwGetError(LoadFn('glfwGetError'));
  glfwSetErrorCallback := TglfwSetErrorCallback(LoadFn('glfwSetErrorCallback'));
  Result := GLastError = '';
  if not Result then
  begin
    UnloadLibrary(GLib);
    GLib := NilHandle;
  end;
end;

procedure GLFWUnload;
begin
  if GLib <> NilHandle then
  begin
    UnloadLibrary(GLib);
    GLib := NilHandle;
  end;
end;

function GLFWLastError: string;
begin
  Result := GLastError;
end;

end.
