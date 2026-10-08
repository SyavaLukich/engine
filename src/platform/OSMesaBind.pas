{ OSMesaBind - контекст OpenGL без окна через OSMesa (программная растеризация в память).

  Две библиотеки и два режима:
  - OSMesaStart(W, H): контекст OpenGL 4.3 core. Нужна OSMesa с OSMesaCreateContextAttribs
    (Mesa 21 и новее, см. docs/OSMESA.md). Используется режимом --offscreen программы Demo.
  - OSMesaStartLegacy(W, H): контекст OpenGL 2.x (фиксированный конвейер). Работает с osmesa-main
    (форк Mesa 7.0.4) и с любой OSMesa, где есть OSMesaCreateContextExt. Используется снимками поз.

  Кадр рисуется в обычный массив пикселей, затем читается тем же методом lencerf (glReadPixels).
  Библиотека загружается динамически (dynlibs), сборка проекта её не требует. }
unit OSMesaBind;

{$mode objfpc}{$H+}

interface

uses
  dynlibs;

const
  OSMESA_RGBA = $1908;
  OSMESA_FORMAT = $22;
  OSMESA_DEPTH_BITS = $30;
  OSMESA_PROFILE = $33;
  OSMESA_CORE_PROFILE = $34;
  OSMESA_CONTEXT_MAJOR_VERSION = $36;
  OSMESA_CONTEXT_MINOR_VERSION = $37;
  OSMESA_GL_UNSIGNED_BYTE = $1401;

type
  TOSMesaCreateExt = function(Format: LongWord; DepthBits, StencilBits, AccumBits: LongInt;
                              Share: Pointer): Pointer; cdecl;
  TOSMesaCreateAttribs = function(Attribs: PLongInt; Share: Pointer): Pointer; cdecl;
  TOSMesaDestroy = procedure(Ctx: Pointer); cdecl;
  TOSMesaMakeCurrent = function(Ctx: Pointer; Buffer: Pointer; Kind: LongWord;
                                W, H: LongInt): Byte; cdecl;
  TOSMesaGetProc = function(Name: PChar): Pointer; cdecl;

{ Загружает библиотеку OSMesa по имени или пути. False - причина в OSMesaLastError. }
function OSMesaLoad(const LibName: string): Boolean;
procedure OSMesaUnload;
{ Контекст OpenGL 4.3 core (RGBA, буфер глубины 24 бита) размером W x H, текущий.
  Требует OSMesaCreateContextAttribs; в старых OSMesa возвращает False. }
function OSMesaStart(W, H: Integer): Boolean;
{ Контекст OpenGL 2.x (RGBA, буфер глубины 24 бита) размером W x H, текущий. }
function OSMesaStartLegacy(W, H: Integer): Boolean;
procedure OSMesaStop;
{ Адрес функции OpenGL для загрузчиков; доступна после запуска контекста. }
function OSMesaGetProc(Name: PChar): Pointer; cdecl;
function OSMesaLastError: string;

implementation

var
  OSLib: TLibHandle = NilHandle;
  osCreateExt: TOSMesaCreateExt = nil;
  osCreateAttribs: TOSMesaCreateAttribs = nil;
  osDestroy: TOSMesaDestroy = nil;
  osMakeCurrent: TOSMesaMakeCurrent = nil;
  osGetProcAddress: TOSMesaGetProc = nil;
  osCtx: Pointer = nil;
  osBuffer: Pointer = nil;
  osLastError: string = '';

function LoadOS(const Name: string): Pointer;
begin
  Result := GetProcedureAddress(OSLib, Name);
  if Result = nil then
    osLastError := 'в библиотеке OSMesa нет функции ' + Name;
end;

function OSMesaLoad(const LibName: string): Boolean;
begin
  Result := False;
  if OSLib <> NilHandle then
    Exit(True);
  osLastError := '';
  OSLib := LoadLibrary(LibName);
  if OSLib = NilHandle then
  begin
    osLastError := 'не удалось открыть ' + LibName;
    Exit;
  end;
  osCreateExt := TOSMesaCreateExt(LoadOS('OSMesaCreateContextExt'));
  osDestroy := TOSMesaDestroy(LoadOS('OSMesaDestroyContext'));
  osMakeCurrent := TOSMesaMakeCurrent(LoadOS('OSMesaMakeCurrent'));
  osGetProcAddress := TOSMesaGetProc(LoadOS('OSMesaGetProcAddress'));
  { атрибуты версии есть не во всех OSMesa: без них доступен только OpenGL 2.x }
  osCreateAttribs := TOSMesaCreateAttribs(GetProcedureAddress(OSLib, 'OSMesaCreateContextAttribs'));
  if (osCreateExt = nil) or (osDestroy = nil) or (osMakeCurrent = nil) or (osGetProcAddress = nil) then
  begin
    FreeLibrary(OSLib);
    OSLib := NilHandle;
    Exit;
  end;
  osLastError := '';
  Result := True;
end;

procedure OSMesaUnload;
begin
  OSMesaStop;
  if OSLib <> NilHandle then
    FreeLibrary(OSLib);
  OSLib := NilHandle;
end;

{ Выделяет буфер W x H x 4 и делает контекст текущим. }
function OSMesaAttach(W, H: Integer): Boolean;
begin
  Result := False;
  osBuffer := GetMem(LongInt(W) * LongInt(H) * 4);
  if osBuffer = nil then
  begin
    osLastError := 'не хватило памяти под кадр';
    Exit;
  end;
  if osMakeCurrent(osCtx, osBuffer, OSMESA_GL_UNSIGNED_BYTE, W, H) = 0 then
  begin
    osLastError := 'OSMesaMakeCurrent не удалось';
    Exit;
  end;
  Result := True;
end;

function CheckStart(W, H: Integer): Boolean;
begin
  Result := False;
  if OSLib = NilHandle then
  begin
    osLastError := 'OSMesa не загружена';
    Exit;
  end;
  if (W <= 0) or (H <= 0) then
  begin
    osLastError := 'размер кадра должен быть положительным';
    Exit;
  end;
  Result := True;
end;

function OSMesaStart(W, H: Integer): Boolean;
var
  Attribs: array[0..10] of LongInt;
begin
  Result := False;
  if not CheckStart(W, H) then
    Exit;
  if osCreateAttribs = nil then
  begin
    osLastError := 'OSMesa без OSMesaCreateContextAttribs не даёт OpenGL 4.3 (нужна Mesa 21 или новее)';
    Exit;
  end;
  Attribs[0] := OSMESA_FORMAT;
  Attribs[1] := OSMESA_RGBA;
  Attribs[2] := OSMESA_DEPTH_BITS;
  Attribs[3] := 24;
  Attribs[4] := OSMESA_PROFILE;
  Attribs[5] := OSMESA_CORE_PROFILE;
  Attribs[6] := OSMESA_CONTEXT_MAJOR_VERSION;
  Attribs[7] := 4;
  Attribs[8] := OSMESA_CONTEXT_MINOR_VERSION;
  Attribs[9] := 3;
  Attribs[10] := 0;
  osCtx := osCreateAttribs(@Attribs[0], nil);
  if osCtx = nil then
  begin
    osLastError := 'OSMesa не создала контекст OpenGL 4.3 core';
    Exit;
  end;
  if not OSMesaAttach(W, H) then
  begin
    OSMesaStop;
    Exit;
  end;
  Result := True;
end;

function OSMesaStartLegacy(W, H: Integer): Boolean;
begin
  Result := False;
  if not CheckStart(W, H) then
    Exit;
  osCtx := osCreateExt(OSMESA_RGBA, 24, 0, 0, nil);
  if osCtx = nil then
  begin
    osLastError := 'OSMesa не создала контекст';
    Exit;
  end;
  if not OSMesaAttach(W, H) then
  begin
    OSMesaStop;
    Exit;
  end;
  Result := True;
end;

procedure OSMesaStop;
begin
  if (osCtx <> nil) and (osDestroy <> nil) then
  begin
    osDestroy(osCtx);
    osCtx := nil;
  end;
  if osBuffer <> nil then
  begin
    FreeMem(osBuffer);
    osBuffer := nil;
  end;
end;

function OSMesaGetProc(Name: PChar): Pointer; cdecl;
begin
  Result := osGetProcAddress(Name);
end;

function OSMesaLastError: string;
begin
  Result := osLastError;
end;

end.
