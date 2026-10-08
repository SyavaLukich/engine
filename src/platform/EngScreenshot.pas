{ EngScreenshot - сохранение кадра OpenGL в PNG.

  Метод (по описанию lencerf.github.io, 2019): размер берётся в пикселях кадрового буфера
  (glfwGetFramebufferSize - важно для HiDPI), строки выравниваются через GL_PACK_ALIGNMENT,
  чтение glReadPixels, ось Y переворачивается при записи (в OpenGL начало внизу).
  Отличие от описания: читается GL_BACK до SwapBuffers, а не GL_FRONT; так кадр точно
  соответствует нарисованному в этом кадре, а не предыдущему.

  Вызывать после отрисовки и до glfwSwapBuffers. }
unit EngScreenshot;

{$mode objfpc}{$H+}

interface

uses
  EngPNG, GLBind;

{ Сохранить текущий задний буфер размером W x H пикселей в файл FileName (PNG, RGB). }
function ScreenshotSave(const FileName: string; W, H: Integer): Boolean;

implementation

function ScreenshotSave(const FileName: string; W, H: Integer): Boolean;
var
  Buf: TByteBuf;
  Flipped: TByteBuf;
  Stride, Y: Integer;
begin
  Result := False;
  if (W <= 0) or (H <= 0) then Exit;
  Stride := W * 3;
  SetLength(Buf, Stride * H);
  SetLength(Flipped, Stride * H);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadBuffer(GL_BACK);
  glReadPixels(0, 0, W, H, GL_RGB, GL_UNSIGNED_BYTE, @Buf[0]);
  { переворот по вертикали: строка Y из буфера (снизу вверх) пишется в строку H-1-Y }
  for Y := 0 to H - 1 do
    Move(Buf[Y * Stride], Flipped[(H - 1 - Y) * Stride], Stride);
  Result := PngSave(FileName, W, H, 3, Flipped);
end;

end.
