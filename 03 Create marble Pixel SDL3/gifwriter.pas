unit GifWriter;

{ Minimal animated GIF89a encoder.
  - one global colour table shared by all frames (exact colours when there
    are <= 255 of them, otherwise a median-cut 255 colour palette)
  - 1-bit transparency (GIF has no partial alpha); soft edges can be cut at
    50% alpha or blended onto a matte colour first
  - every frame uses disposal "restore to background", so transparent areas
    never show the previous frame
  - NETSCAPE2.0 loop extension }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, PixBuf, PixelArt;

type
  TGifOptions = record
    DelayMs : Integer;   { per frame }
    Loop    : Integer;   { 0 = loop forever }
    Matte   : LongInt;   { -1 = hard cut at 50% alpha, else $RRGGBB to blend soft edges onto }
  end;

function SaveAnimatedGif(const FileName: string; const Frames: array of TPixelBuf;
  const Opt: TGifOptions; out Err: string): Boolean;

implementation

{ ---------- bit packing into 255-byte sub-blocks ---------- }

type
  TBitWriter = record
    S: TStream;
    Acc: LongWord;
    NBits: Integer;
    Block: array[0..254] of Byte;
    BLen: Integer;
  end;

procedure BWFlushBlock(var B: TBitWriter);
begin
  if B.BLen > 0 then
  begin
    B.S.WriteByte(B.BLen);
    B.S.WriteBuffer(B.Block[0], B.BLen);
    B.BLen := 0;
  end;
end;

procedure BWPutByte(var B: TBitWriter; v: Byte);
begin
  B.Block[B.BLen] := v;
  Inc(B.BLen);
  if B.BLen = 255 then BWFlushBlock(B);
end;

procedure BWWrite(var B: TBitWriter; Code, Size: Integer);
begin
  B.Acc := B.Acc or (LongWord(Code) shl B.NBits);
  Inc(B.NBits, Size);
  while B.NBits >= 8 do
  begin
    BWPutByte(B, B.Acc and $FF);
    B.Acc := B.Acc shr 8;
    Dec(B.NBits, 8);
  end;
end;

procedure BWFinish(var B: TBitWriter);
begin
  if B.NBits > 0 then BWPutByte(B, B.Acc and $FF);
  B.Acc := 0;
  B.NBits := 0;
  BWFlushBlock(B);
  B.S.WriteByte(0);   { block terminator }
end;

{ ---------- LZW ---------- }

const
  HSIZE = 16411;   { prime, > 4 * 4096 }

procedure LzwEncode(S: TStream; const Idx: array of Byte; MinCode: Integer);
var
  B: TBitWriter;
  HKey: array of LongInt;
  HCode: array of Word;
  ClearCode, CodeSize, MaxCode, Cur, k, key, found, i: Integer;
  h: LongWord;
begin
  SetLength(HKey, HSIZE);
  SetLength(HCode, HSIZE);
  FillChar(HKey[0], HSIZE * SizeOf(LongInt), $FF);
  FillChar(B, SizeOf(B), 0);
  B.S := S;
  S.WriteByte(MinCode);
  ClearCode := 1 shl MinCode;
  CodeSize := MinCode + 1;
  MaxCode := ClearCode + 1;
  BWWrite(B, ClearCode, CodeSize);
  Cur := Idx[0];
  for i := 1 to High(Idx) do
  begin
    k := Idx[i];
    key := (Cur shl 8) or k;
    h := LongWord((QWord(LongWord(key)) * 2654435761) mod HSIZE);
    found := -1;
    while HKey[h] <> -1 do
    begin
      if HKey[h] = key then
      begin
        found := HCode[h];
        Break;
      end;
      Inc(h);
      if h = HSIZE then h := 0;
    end;
    if found >= 0 then
      Cur := found
    else
    begin
      BWWrite(B, Cur, CodeSize);
      Inc(MaxCode);
      HKey[h] := key;
      HCode[h] := MaxCode;
      if MaxCode >= (1 shl CodeSize) then Inc(CodeSize);
      if MaxCode = 4095 then
      begin
        { dictionary full: start over }
        BWWrite(B, ClearCode, CodeSize);
        FillChar(HKey[0], HSIZE * SizeOf(LongInt), $FF);
        CodeSize := MinCode + 1;
        MaxCode := ClearCode + 1;
      end;
      Cur := k;
    end;
  end;
  BWWrite(B, Cur, CodeSize);
  BWWrite(B, ClearCode, CodeSize);
  BWWrite(B, ClearCode + 1, MinCode + 1);   { end of information }
  BWFinish(B);
end;

{ ---------- colour handling ---------- }

{ returns -1 for a transparent pixel, else $RRGGBB }
function GifColor(c: LongWord; Matte: LongInt): LongInt; inline;
var
  a: Integer;
begin
  a := c shr 24;
  if Matte < 0 then
  begin
    if a < 128 then Exit(-1);
    Exit(LongInt(c and $FFFFFF));
  end;
  if a < 8 then Exit(-1);
  if a = 255 then Exit(LongInt(c and $FFFFFF));
  Result :=
    (((Integer((c shr 16) and $FF) * a + Integer((Matte shr 16) and $FF) * (255 - a)) div 255) shl 16) or
    (((Integer((c shr 8) and $FF) * a + Integer((Matte shr 8) and $FF) * (255 - a)) div 255) shl 8) or
     ((Integer(c and $FF) * a + Integer(Matte and $FF) * (255 - a)) div 255);
end;

procedure WriteWord(S: TStream; v: Integer);
begin
  S.WriteByte(v and $FF);
  S.WriteByte((v shr 8) and $FF);
end;

function SaveAnimatedGif(const FileName: string; const Frames: array of TPixelBuf;
  const Opt: TGifOptions; out Err: string): Boolean;
const
  CHASH = 1031;
  MAXSAMPLES = 200000;
var
  W, H, f, i, j, nc, total, sizeField, tableSize, minCode, transIdx, stp, cnt: Integer;
  c, best, bd, d: LongInt;
  HasTransp, Exact: Boolean;
  { exact colour set: open addressing hash colour+1 -> index }
  CKey: array[0..CHASH - 1] of LongInt;
  CIdx: array[0..CHASH - 1] of Byte;
  Pal: TPalette;
  Samples: array of LongWord;
  Lut: array of SmallInt;   { 15-bit colour -> palette index, for >255 colours }
  Idx: array of Byte;
  S: TFileStream;
  li, delayCs: Integer;

  function FindExact(col: LongInt): Integer;
  var
    k: Integer;
  begin
    k := (LongWord(col) * 2654435761) mod CHASH;
    while CKey[k] <> 0 do
    begin
      if CKey[k] = col + 1 then Exit(CIdx[k]);
      Inc(k);
      if k = CHASH then k := 0;
    end;
    Result := -1;
  end;

  procedure AddExact(col: LongInt);
  var
    k: Integer;
  begin
    k := (LongWord(col) * 2654435761) mod CHASH;
    while CKey[k] <> 0 do
    begin
      if CKey[k] = col + 1 then Exit;
      Inc(k);
      if k = CHASH then k := 0;
    end;
    if nc >= 255 then
    begin
      Exact := False;   { too many colours: switch to a median-cut palette }
      Exit;
    end;
    CKey[k] := col + 1;
    CIdx[k] := nc;
    SetLength(Pal, nc + 1);
    Pal[nc] := LongWord(col);
    Inc(nc);
  end;

begin
  Result := False;
  Err := '';
  if Length(Frames) = 0 then
  begin
    Err := 'No frames';
    Exit;
  end;
  W := Frames[0].W;
  H := Frames[0].H;
  if (W <= 0) or (H <= 0) or (W > 65535) or (H > 65535) then
  begin
    Err := 'Invalid frame size';
    Exit;
  end;
  for f := 1 to High(Frames) do
    if (Frames[f].W <> W) or (Frames[f].H <> H) then
    begin
      Err := 'All frames must have the same size';
      Exit;
    end;

  { 1. find the colours }
  FillChar(CKey, SizeOf(CKey), 0);
  nc := 0;
  Pal := nil;
  Exact := True;
  HasTransp := False;
  for f := 0 to High(Frames) do
    for i := 0 to High(Frames[f].Data) do
    begin
      c := GifColor(Frames[f].Data[i], Opt.Matte);
      if c < 0 then
        HasTransp := True
      else if Exact then
        AddExact(c);
    end;

  if not Exact then
  begin
    { too many colours: sample all frames and build a 255 colour palette }
    total := 0;
    for f := 0 to High(Frames) do Inc(total, Length(Frames[f].Data));
    stp := Max(1, total div MAXSAMPLES);
    SetLength(Samples, total div stp + 1);
    cnt := 0;
    for f := 0 to High(Frames) do
    begin
      i := 0;
      while i <= High(Frames[f].Data) do
      begin
        c := GifColor(Frames[f].Data[i], Opt.Matte);
        if c >= 0 then
        begin
          Samples[cnt] := LongWord(c);
          Inc(cnt);
        end;
        Inc(i, stp);
      end;
    end;
    SetLength(Samples, cnt);
    Pal := MedianCut(Samples, 255);
    nc := Length(Pal);
    SetLength(Lut, 32768);
    for i := 0 to High(Lut) do Lut[i] := -1;
  end;
  if nc = 0 then
  begin
    { completely transparent animation: keep one dummy colour }
    SetLength(Pal, 1);
    Pal[0] := 0;
    nc := 1;
  end;

  if HasTransp then transIdx := nc else transIdx := 0;
  total := nc + Ord(HasTransp);
  sizeField := 0;
  while (2 shl sizeField) < total do Inc(sizeField);
  tableSize := 2 shl sizeField;
  minCode := Max(2, sizeField + 1);
  delayCs := Max(2, Round(Opt.DelayMs / 10));

  SetLength(Idx, W * H);
  try
    S := TFileStream.Create(FileName, fmCreate);
  except
    on E: Exception do
    begin
      Err := E.Message;
      Exit;
    end;
  end;
  try
    try
      { header + logical screen descriptor + global colour table }
      S.WriteBuffer(PAnsiChar('GIF89a')^, 6);
      WriteWord(S, W);
      WriteWord(S, H);
      S.WriteByte($80 or $70 or sizeField);
      S.WriteByte(transIdx);
      S.WriteByte(0);
      for i := 0 to tableSize - 1 do
        if i < nc then
        begin
          S.WriteByte((Pal[i] shr 16) and $FF);
          S.WriteByte((Pal[i] shr 8) and $FF);
          S.WriteByte(Pal[i] and $FF);
        end
        else
        begin
          S.WriteByte(0); S.WriteByte(0); S.WriteByte(0);
        end;

      { loop forever (or N times) }
      if Length(Frames) > 1 then
      begin
        S.WriteByte($21); S.WriteByte($FF); S.WriteByte(11);
        S.WriteBuffer(PAnsiChar('NETSCAPE2.0')^, 11);
        S.WriteByte(3); S.WriteByte(1);
        WriteWord(S, Opt.Loop);
        S.WriteByte(0);
      end;

      for f := 0 to High(Frames) do
      begin
        { map pixels to palette indices }
        for i := 0 to W * H - 1 do
        begin
          c := GifColor(Frames[f].Data[i], Opt.Matte);
          if c < 0 then
            Idx[i] := transIdx
          else if Exact then
            Idx[i] := FindExact(c)
          else
          begin
            li := ((c shr 9) and $7C00) or ((c shr 6) and $3E0) or ((c shr 3) and $1F);
            if Lut[li] < 0 then
            begin
              best := 0; bd := MaxLongInt;
              for j := 0 to nc - 1 do
              begin
                d := 2 * Sqr(((c shr 16) and $FF) - LongInt((Pal[j] shr 16) and $FF)) +
                     4 * Sqr(((c shr 8) and $FF) - LongInt((Pal[j] shr 8) and $FF)) +
                     3 * Sqr((c and $FF) - LongInt(Pal[j] and $FF));
                if d < bd then
                begin
                  bd := d;
                  best := j;
                end;
              end;
              Lut[li] := best;
            end;
            Idx[i] := Lut[li];
          end;
        end;

        { graphic control extension: disposal 2, delay, transparency }
        S.WriteByte($21); S.WriteByte($F9); S.WriteByte(4);
        S.WriteByte((2 shl 2) or Ord(HasTransp));
        WriteWord(S, delayCs);
        S.WriteByte(transIdx);
        S.WriteByte(0);
        { image descriptor, full frame, no local table }
        S.WriteByte($2C);
        WriteWord(S, 0); WriteWord(S, 0);
        WriteWord(S, W); WriteWord(S, H);
        S.WriteByte(0);
        LzwEncode(S, Idx, minCode);
      end;
      S.WriteByte($3B);   { trailer }
      Result := True;
    except
      on E: Exception do Err := E.Message;
    end;
  finally
    S.Free;
  end;
end;

end.
