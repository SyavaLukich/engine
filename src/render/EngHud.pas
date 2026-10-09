{ EngHud - интерфейс поверх кадра: цветные прямоугольники в пикселях окна с альфа-смешиванием.
  Текста нет (шрифта в проекте нет): интерфейс строится из полос, квадратов и перекрестия.
  Использование за кадр: HudBegin, несколько HudRect, HudFlush (после RenderFrame).
  Классов нет. }
unit EngHud;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, EngShader, GLBind;

type
  THud = record
    Prog: GLuint;
    Vao: GLuint;
    Vbo: GLuint;
    LocViewport: GLint;
    Data: array of Single;    { на вершину: x, y, r, g, b, a }
    Count: Integer;           { число вершин в Data }
    WinW: Integer;
    WinH: Integer;
    Ready: Boolean;
    Error: string;
  end;

{ Программа hud.vert/hud.frag из каталога ShaderDir; требуется контекст OpenGL 4.3. }
function HudInit(var H: THud; const ShaderDir: string): Boolean;
procedure HudBegin(var H: THud; W, Ht: Integer);
{ Прямоугольник в пикселях; (X, Y) - левый верхний угол. Цвет - линейный, A - прозрачность 0..1. }
procedure HudRect(var H: THud; X, Y, Wd, Ht: Double; R, G, B, A: Double);
{ Рисует накопленное и очищает список. Глубина и отсечение отключаются; состояние смешивания восстанавливается. }
procedure HudFlush(var H: THud);
procedure HudShutdown(var H: THud);

implementation

const
  HUD_FLOATS_PER_VERTEX = 6;

function HudInit(var H: THud; const ShaderDir: string): Boolean;
begin
  H.Error := '';
  H.Ready := False;
  H.Count := 0;
  H.Prog := BuildProgram(ShaderDir, 'hud.vert', 'hud.frag', H.Error);
  if H.Prog = 0 then
  begin
    Result := False;
    Exit;
  end;
  H.LocViewport := glGetUniformLocation(H.Prog, PChar('uViewport'));
  glGenVertexArrays(1, @H.Vao);
  glGenBuffers(1, @H.Vbo);
  glBindVertexArray(H.Vao);
  glBindBuffer(GL_ARRAY_BUFFER, H.Vbo);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, HUD_FLOATS_PER_VERTEX * SizeOf(Single), nil);
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, HUD_FLOATS_PER_VERTEX * SizeOf(Single),
                        Pointer(PtrUInt(2 * SizeOf(Single))));
  glBindVertexArray(0);
  SetLength(H.Data, 0);
  H.Ready := True;
  Result := True;
end;

procedure HudBegin(var H: THud; W, Ht: Integer);
begin
  H.WinW := Max(1, W);
  H.WinH := Max(1, Ht);
  H.Count := 0;
end;

procedure PushVertex(var H: THud; X, Y: Double; R, G, B, A: Double);
var
  Base: Integer;
begin
  Base := H.Count * HUD_FLOATS_PER_VERTEX;
  if Base + HUD_FLOATS_PER_VERTEX > Length(H.Data) then
    SetLength(H.Data, Length(H.Data) * 2 + 6 * HUD_FLOATS_PER_VERTEX * 64);
  H.Data[Base + 0] := X;
  H.Data[Base + 1] := Y;
  H.Data[Base + 2] := R;
  H.Data[Base + 3] := G;
  H.Data[Base + 4] := B;
  H.Data[Base + 5] := A;
  Inc(H.Count);
end;

procedure HudRect(var H: THud; X, Y, Wd, Ht: Double; R, G, B, A: Double);
begin
  { Два треугольника: (X,Y)-(X+W,Y)-(X,Y+H) и (X+W,Y)-(X+W,Y+H)-(X,Y+H). }
  PushVertex(H, X, Y, R, G, B, A);
  PushVertex(H, X + Wd, Y, R, G, B, A);
  PushVertex(H, X, Y + Ht, R, G, B, A);
  PushVertex(H, X + Wd, Y, R, G, B, A);
  PushVertex(H, X + Wd, Y + Ht, R, G, B, A);
  PushVertex(H, X, Y + Ht, R, G, B, A);
end;

procedure HudFlush(var H: THud);
begin
  if (not H.Ready) or (H.Count = 0) then
  begin
    H.Count := 0;
    Exit;
  end;
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glUseProgram(H.Prog);
  glUniform2f(H.LocViewport, H.WinW, H.WinH);
  glBindVertexArray(H.Vao);
  glBindBuffer(GL_ARRAY_BUFFER, H.Vbo);
  glBufferData(GL_ARRAY_BUFFER, H.Count * HUD_FLOATS_PER_VERTEX * SizeOf(Single), @H.Data[0], GL_DYNAMIC_DRAW);
  glDrawArrays(GL_TRIANGLES, 0, H.Count);
  glBindVertexArray(0);
  glDisable(GL_BLEND);
  H.Count := 0;
end;

procedure HudShutdown(var H: THud);
begin
  if H.Vbo <> 0 then glDeleteBuffers(1, @H.Vbo);
  if H.Vao <> 0 then glDeleteVertexArrays(1, @H.Vao);
  if H.Prog <> 0 then glDeleteProgram(H.Prog);
  H.Vbo := 0;
  H.Vao := 0;
  H.Prog := 0;
  H.Ready := False;
  H.Count := 0;
end;

end.
