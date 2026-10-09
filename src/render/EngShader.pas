{ EngShader - загрузка GLSL: чтение файлов, компиляция стадий и линковка программ.
  Используется рендерером и интерфейсом. Классов нет. }
unit EngShader;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, GLBind;

{ Чтение текстового файла целиком. False, если файла нет или его нельзя открыть. }
function ReadTextFile(const Path: string; out Text: string): Boolean;

{ Компиляция одной стадии. При ошибке дописывает журнал в Err и возвращает 0. }
function CompileStage(Kind: GLenum; const Src, Name: string; var Err: string): GLuint;

{ Программа из Dir/VertName и Dir/FragName. При ошибке возвращает 0, журнал - в Err. }
function BuildProgram(const Dir, VertName, FragName: string; var Err: string): GLuint;

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
  Got := 0;
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

end.
