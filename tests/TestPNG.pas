{ TestPNG - проверка кодировщика PNG: контрольные суммы по известным векторам и разбор результата. }
unit TestPNG;

{$mode objfpc}{$H+}

interface

procedure RunPngTests;

implementation

uses
  SysUtils, EngPNG, TestKit;

function FileBytes(const Path: string): Int64;
var
  F: file;
begin
  Result := -1;
  AssignFile(F, Path);
  Reset(F, 1);
  Result := FileSize(F);
  Close(F);
end;

function Be32(const B: TByteBuf; P: Integer): LongWord;
begin
  Result := (LongWord(B[P]) shl 24) or (LongWord(B[P + 1]) shl 16) or (LongWord(B[P + 2]) shl 8) or LongWord(B[P + 3]);
end;

{ Разбор PNG: проверка сигнатуры, CRC чанков, zlib (stored-блоки) и Adler-32; возврат пикселей. }
function DecodeStored(const Png: TByteBuf; out Width, Height, Channels: Integer; out Pixels: TByteBuf): Boolean;
var
  P, Len, N: Integer;
  Tag: string;
  Idat: TByteBuf;
  IdatLen: Integer;
  Raw: TByteBuf;
  RawLen, Z, Blen, Bhdr, K, Row, RowBytes: Integer;
  Final: Boolean;
  Crc: LongWord;
  Good: Boolean;
  Ct: Byte;
begin
  Result := False;
  Good := (Length(Png) > 8) and (Png[0] = $89) and (Png[1] = $50) and (Png[2] = $4E) and (Png[3] = $47);
  if not Good then Exit;
  SetLength(Idat, Length(Png));
  IdatLen := 0;
  P := 8;
  N := 0;
  Width := 0;
  Height := 0;
  Channels := 0;
  while P + 12 <= Length(Png) do
  begin
    Len := Integer(Be32(Png, P));
    Tag := Chr(Png[P + 4]) + Chr(Png[P + 5]) + Chr(Png[P + 6]) + Chr(Png[P + 7]);
    Crc := Crc32Of(Png, P + 4, 4 + Len, 0);
    if Crc <> Be32(Png, P + 8 + Len) then
    begin
      WriteLn('  PNG: неверный CRC чанка ', Tag);
      Exit;
    end;
    if Tag = 'IHDR' then
    begin
      Width := Integer(Be32(Png, P + 8));
      Height := Integer(Be32(Png, P + 12));
      Ct := Png[P + 17];
      if Ct = 6 then Channels := 4 else if Ct = 2 then Channels := 3 else Channels := 0;
      if Png[P + 16] <> 8 then Exit;
    end
    else if Tag = 'IDAT' then
    begin
      Move(Png[P + 8], Idat[IdatLen], Len);
      Inc(IdatLen, Len);
    end
    else if Tag = 'IEND' then
      Break;
    P := P + 12 + Len;
    N := N + 1;
  end;
  if (Width <= 0) or (Channels = 0) then Exit;
  { zlib }
  if (Idat[0] <> $78) or (Idat[1] <> $01) then Exit;
  SetLength(Raw, IdatLen);
  RawLen := 0;
  Z := 2;
  repeat
    Bhdr := Idat[Z];
    Final := (Bhdr and 1) <> 0;
    if ((Bhdr shr 1) and 3) <> 0 then Exit;   { должен быть stored }
    Blen := Idat[Z + 1] or (Idat[Z + 2] shl 8);
    if (Idat[Z + 3] or (Idat[Z + 4] shl 8)) <> ((not Blen) and $FFFF) then Exit;
    Move(Idat[Z + 5], Raw[RawLen], Blen);
    Inc(RawLen, Blen);
    Inc(Z, 5 + Blen);
  until Final;
  if Be32(Idat, Z) <> Adler32Of(Raw, 0, RawLen) then
  begin
    WriteLn('  PNG: неверный Adler-32');
    Exit;
  end;
  { фильтры и пиксели }
  RowBytes := Width * Channels;
  if RawLen <> (RowBytes + 1) * Height then Exit;
  SetLength(Pixels, RowBytes * Height);
  for Row := 0 to Height - 1 do
  begin
    if Raw[Row * (RowBytes + 1)] <> 0 then Exit;
    for K := 0 to RowBytes - 1 do
      Pixels[Row * RowBytes + K] := Raw[Row * (RowBytes + 1) + 1 + K];
  end;
  Result := True;
end;

procedure RunPngTests;
var
  Img, Back, Px: TByteBuf;
  W, H, C, I: Integer;
  Ok: Boolean;
  Path: string;
begin
  Section('PNG: контрольные суммы');
  SetLength(Img, 9);
  for I := 0 to 8 do Img[I] := Ord('1') + I;
  Check(Crc32Of(Img, 0, 9, 0) = $CBF43926, 'CRC-32("123456789") = CBF43926');
  SetLength(Img, 9);
  Move(PChar('Wikipedia')^, Img[0], 9);
  Check(Adler32Of(Img, 0, 9) = $11E60398, 'Adler-32("Wikipedia") = 11E60398');

  Section('PNG: кодирование и разбор');
  W := 3;
  H := 2;
  C := 3;
  SetLength(Img, W * H * C);
  for I := 0 to High(Img) do Img[I] := (I * 37) and $FF;
  Back := PngEncode(W, H, C, Img);
  Ok := DecodeStored(Back, W, H, C, Px);
  Check(Ok, 'RGB 3x2: файл разбирается, CRC и Adler-32 верны');
  Check(Ok and (Length(Px) = Length(Img)) and CompareMem(@Px[0], @Img[0], Length(Img)),
        'RGB 3x2: пиксели совпадают после разбора');

  { большое изображение: несколько stored-блоков (более 65535 байт) }
  W := 300;
  H := 200;
  C := 4;
  SetLength(Img, W * H * C);
  for I := 0 to High(Img) do Img[I] := ((I * 7) xor (I shr 9)) and $FF;
  Back := PngEncode(W, H, C, Img);
  Ok := DecodeStored(Back, W, H, C, Px);
  Check(Ok and (Length(Px) = Length(Img)) and CompareMem(@Px[0], @Img[0], Length(Img)),
        'RGBA 300x200 (несколько блоков): пиксели совпадают');

  Section('PNG: запись файла');
  Path := 'build/tests/png_roundtrip.png';
  Check(PngSave(Path, W, H, C, Img), 'PngSave записывает файл');
  Check(FileBytes(Path) = Length(Back), 'размер файла совпадает с PngEncode');
end;

end.
