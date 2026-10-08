{ EngPNG - запись PNG без внешних библиотек.

  Поток zlib формируется из блоков DEFLATE без сжатия (BTYPE=00): это корректный PNG,
  который читают все программы, но файлы крупнее сжатых. Фильтр строк - None (0).
  Контрольные суммы: CRC-32 (IEND/IHDR/IDAT по стандарту PNG) и Adler-32 (zlib).

  Вход: пиксели сверху вниз (строка 0 - верхняя), 8 бит на канал, RGB (3) или RGBA (4).
  Классов нет: модуль - набор функций без состояния (таблица CRC строится один раз). }
unit EngPNG;

{$mode objfpc}{$H+}

interface

type
  TByteBuf = array of Byte;

{ Сохранить изображение в файл. Channels: 3 (RGB) или 4 (RGBA). Возвращает False при ошибке записи. }
function PngSave(const FileName: string; Width, Height, Channels: Integer; const Pixels: TByteBuf): Boolean;
{ Контрольная сумма CRC-32 (полином 0xEDB88320) для буфера. }
function Crc32Of(const Buf: TByteBuf; Start, Count: Integer; Crc: LongWord): LongWord;
{ Adler-32 для буфера. }
function Adler32Of(const Buf: TByteBuf; Start, Count: Integer): LongWord;
{ Кодирование PNG в память (для тестов и сетевой отдачи). }
function PngEncode(Width, Height, Channels: Integer; const Pixels: TByteBuf): TByteBuf;

implementation

var
  CrcTable: array[0..255] of LongWord;
  CrcReady: Boolean = False;

procedure BuildCrcTable;
var
  N, K: Integer;
  C: LongWord;
begin
  for N := 0 to 255 do
  begin
    C := LongWord(N);
    for K := 0 to 7 do
      if (C and 1) <> 0 then
        C := $EDB88320 xor (C shr 1)
      else
        C := C shr 1;
    CrcTable[N] := C;
  end;
  CrcReady := True;
end;

function Crc32Of(const Buf: TByteBuf; Start, Count: Integer; Crc: LongWord): LongWord;
var
  I: Integer;
begin
  if not CrcReady then BuildCrcTable;
  Result := Crc xor $FFFFFFFF;
  for I := Start to Start + Count - 1 do
    Result := CrcTable[(Result xor Buf[I]) and $FF] xor (Result shr 8);
  Result := Result xor $FFFFFFFF;
end;

function Adler32Of(const Buf: TByteBuf; Start, Count: Integer): LongWord;
var
  A, B: LongWord;
  I, Chunk, Left: Integer;
begin
  A := 1;
  B := 0;
  I := Start;
  Left := Count;
  while Left > 0 do
  begin
    { 5552 - наибольшее число байт, при котором 32-битные суммы не переполняются }
    if Left > 5552 then Chunk := 5552 else Chunk := Left;
    Left := Left - Chunk;
    while Chunk > 0 do
    begin
      A := A + Buf[I];
      B := B + A;
      Inc(I);
      Dec(Chunk);
    end;
    A := A mod 65521;
    B := B mod 65521;
  end;
  Result := (B shl 16) or A;
end;

procedure PutU32BE(var B: TByteBuf; var Pos: Integer; V: LongWord);
begin
  B[Pos] := (V shr 24) and $FF;
  B[Pos + 1] := (V shr 16) and $FF;
  B[Pos + 2] := (V shr 8) and $FF;
  B[Pos + 3] := V and $FF;
  Inc(Pos, 4);
end;

{ Фрагмент PNG: длина, тип, данные, CRC(тип+данные). }
procedure PutChunk(var Out_: TByteBuf; var Pos: Integer; const Tag: string; const Data: TByteBuf; DataStart, DataLen: Integer);
var
  I: Integer;
  Crc: LongWord;
begin
  PutU32BE(Out_, Pos, LongWord(DataLen));
  for I := 1 to 4 do
    Out_[Pos + I - 1] := Byte(Tag[I]);
  Inc(Pos, 4);
  if DataLen > 0 then
    Move(Data[DataStart], Out_[Pos], DataLen);
  Crc := Crc32Of(Out_, Pos - 4, 4, 0);
  if DataLen > 0 then
    Crc := Crc32Of(Out_, Pos, DataLen, Crc);
  Inc(Pos, DataLen);
  PutU32BE(Out_, Pos, Crc);
end;

function PngEncode(Width, Height, Channels: Integer; const Pixels: TByteBuf): TByteBuf;
var
  RowBytes, Raw, Blocks, I, J, Pos, Len, Off: Integer;
  Filtered: TByteBuf;
  Zlib: TByteBuf;
  Ihdr: TByteBuf;
  Adl: LongWord;
  ColorType: Byte;
  ZPos: Integer;
  Last: Byte;
begin
  RowBytes := Width * Channels;
  Raw := (RowBytes + 1) * Height;
  SetLength(Filtered, Raw);
  { фильтр None в каждой строке }
  for J := 0 to Height - 1 do
  begin
    Filtered[J * (RowBytes + 1)] := 0;
    Move(Pixels[J * RowBytes], Filtered[J * (RowBytes + 1) + 1], RowBytes);
  end;

  { zlib: заголовок 0x78 0x01 (без сжатия, проверка FCHECK), блоки stored, Adler-32 }
  Blocks := (Raw + 65534) div 65535;
  if Raw = 0 then Blocks := 1;
  SetLength(Zlib, 2 + Raw + Blocks * 5 + 4);
  ZPos := 0;
  Zlib[0] := $78;
  Zlib[1] := $01;
  ZPos := 2;
  Off := 0;
  for I := 0 to Blocks - 1 do
  begin
    if Raw - Off > 65535 then Len := 65535 else Len := Raw - Off;
    if I = Blocks - 1 then Last := 1 else Last := 0;
    Zlib[ZPos] := Last;
    Zlib[ZPos + 1] := Len and $FF;
    Zlib[ZPos + 2] := (Len shr 8) and $FF;
    Zlib[ZPos + 3] := (not Len) and $FF;
    Zlib[ZPos + 4] := ((not Len) shr 8) and $FF;
    Inc(ZPos, 5);
    if Len > 0 then
      Move(Filtered[Off], Zlib[ZPos], Len);
    Inc(ZPos, Len);
    Inc(Off, Len);
  end;
  Adl := Adler32Of(Filtered, 0, Raw);
  PutU32BE(Zlib, ZPos, Adl);
  SetLength(Zlib, ZPos);

  if Channels = 4 then ColorType := 6 else ColorType := 2;
  SetLength(Ihdr, 13);
  Pos := 0;
  PutU32BE(Ihdr, Pos, LongWord(Width));
  PutU32BE(Ihdr, Pos, LongWord(Height));
  Ihdr[8] := 8;          { глубина цвета }
  Ihdr[9] := ColorType;
  Ihdr[10] := 0;         { сжатие }
  Ihdr[11] := 0;         { фильтр }
  Ihdr[12] := 0;         { чересстрочность нет }

  SetLength(Result, 8 + 12 + 13 + 12 + Length(Zlib) + 12);
  { сигнатура }
  Result[0] := $89; Result[1] := $50; Result[2] := $4E; Result[3] := $47;
  Result[4] := $0D; Result[5] := $0A; Result[6] := $1A; Result[7] := $0A;
  Pos := 8;
  PutChunk(Result, Pos, 'IHDR', Ihdr, 0, 13);
  PutChunk(Result, Pos, 'IDAT', Zlib, 0, Length(Zlib));
  PutChunk(Result, Pos, 'IEND', Ihdr, 0, 0);
  SetLength(Result, Pos);
end;

function PngSave(const FileName: string; Width, Height, Channels: Integer; const Pixels: TByteBuf): Boolean;
var
  Data: TByteBuf;
  F: file;
  Written: Integer;
begin
  Result := False;
  if (Width <= 0) or (Height <= 0) or ((Channels <> 3) and (Channels <> 4)) then Exit;
  if Length(Pixels) < Width * Height * Channels then Exit;
  Data := PngEncode(Width, Height, Channels, Pixels);
  AssignFile(F, FileName);
  {$I-}
  Rewrite(F, 1);
  {$I+}
  if IOResult <> 0 then Exit;
  BlockWrite(F, Data[0], Length(Data), Written);
  Close(F);
  Result := Written = Length(Data);
end;

end.
