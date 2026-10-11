unit PixelArt;

{ Pixel-art post processing for the sphere renderer:
  low-resolution hard-edged render, cel-shaded light bands, palette
  reduction (retro presets / adaptive median cut / posterize), ordered or
  Floyd-Steinberg dithering, 1-bit or dithered transparency, outlines and
  nearest-neighbour upscaling. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, PixBuf, SphereRender;

type
  TPixPalette = (ppFull, ppPosterize, ppAdaptive, ppPico8, ppNES, ppEndesga32,
                 ppEndesga16, ppSweetie16, ppDB16, ppDB32, ppGameBoy, ppVirtualBoy,
                 ppCGA, ppC64, ppZX, ppApple2, ppGray4, ppGray8, ppBW, ppCustom);
  TPixDither  = (pdNone, pdBayer2, pdBayer4, pdBayer8, pdFloyd);
  TPixAlpha   = (paHard, paDither, paStepped, paSmooth);
  TPixOutline = (poNone, poOuter, poInner, poBoth);

  TPixelParams = record
    Size           : Integer;     { canvas size in art pixels }
    Upscale        : Integer;     { nearest-neighbour export scale }
    Palette        : TPixPalette;
    Colors         : Integer;     { adaptive colour count / posterize levels }
    Dither         : TPixDither;
    DitherStrength : Double;      { 0..1 }
    AlphaMode      : TPixAlpha;
    Outline        : TPixOutline;
    OutlineColor   : LongWord;    { $00RRGGBB }
    ToonSteps      : Integer;     { 0 = smooth lighting }
    CustomPal      : array of LongWord;  { colours for ppCustom, $00RRGGBB }
  end;

  TPalette = array of LongWord;   { $00RRGGBB }

const
  PixPaletteNames: array[TPixPalette] of string = (
    'Full colour', 'Posterize (levels)', 'Adaptive (N colours)', 'PICO-8 (16)',
    'NES (54)', 'Endesga 32', 'Endesga 16', 'Sweetie 16', 'DawnBringer 16',
    'DawnBringer 32', 'Game Boy (4)', 'Virtual Boy (4)', 'CGA (16)',
    'Commodore 64 (16)', 'ZX Spectrum (15)', 'Apple II (15)', 'Grayscale (4)',
    'Grayscale (8)', 'Black & white (2)', 'Custom (from file)');
  PixDitherNames: array[TPixDither] of string = (
    'None', 'Ordered 2x2', 'Ordered 4x4', 'Ordered 8x8', 'Floyd-Steinberg');
  PixAlphaNames: array[TPixAlpha] of string = (
    'Hard edge (1-bit)', 'Dithered (1-bit)', 'Stepped (4 levels)', 'Smooth');
  PixOutlineNames: array[TPixOutline] of string = (
    'None', 'Outer outline', 'Inner edge shade', 'Outer + inner');

procedure DefaultPixelParams(out PP: TPixelParams);
function  PixelSphereParams(const SP: TSphereParams; const PP: TPixelParams): TSphereParams;
procedure RenderPixelRaw(const Tex: TPixelBuf; const SP: TSphereParams; const PP: TPixelParams;
  var Raw: TPixelBuf; Fast: Boolean = False);
function  BuildPalette(const PP: TPixelParams; const Frames: array of TPixelBuf): TPalette;
function  LoadPaletteFile(const FileName: string; out Pal: TPalette; out Err: string): Boolean;
procedure PixelFinish(const Raw: TPixelBuf; const SP: TSphereParams; const PP: TPixelParams;
  const Pal: TPalette; var Dst: TPixelBuf);
procedure RenderPixelSphere(const Tex: TPixelBuf; const SP: TSphereParams; const PP: TPixelParams;
  var Dst: TPixelBuf; Fast: Boolean = False);
procedure BufScaleNearest(const Src: TPixelBuf; K: Integer; var Dst: TPixelBuf);

implementation

const
  PalPico8: array[0..15] of LongWord = (
    $000000, $1D2B53, $7E2553, $008751, $AB5236, $5F574F, $C2C3C7, $FFF1E8,
    $FF004D, $FFA300, $FFEC27, $00E436, $29ADFF, $83769C, $FF77A8, $FFCCAA);
  PalGameBoy: array[0..3] of LongWord = ($0F380F, $306230, $8BAC0F, $9BBC0F);
  PalCGA: array[0..15] of LongWord = (
    $000000, $0000AA, $00AA00, $00AAAA, $AA0000, $AA00AA, $AA5500, $AAAAAA,
    $555555, $5555FF, $55FF55, $55FFFF, $FF5555, $FF55FF, $FFFF55, $FFFFFF);
  PalC64: array[0..15] of LongWord = (
    $000000, $FFFFFF, $68372B, $70A4B2, $6F3D86, $588D43, $352879, $B8C76F,
    $6F4F25, $433900, $9A6759, $444444, $6C6C6C, $9AD284, $6C5EB5, $959595);
  PalGray4: array[0..3] of LongWord = ($000000, $555555, $AAAAAA, $FFFFFF);
  PalGray8: array[0..7] of LongWord = ($000000, $242424, $494949, $6D6D6D,
                                       $929292, $B6B6B6, $DBDBDB, $FFFFFF);
  PalBW: array[0..1] of LongWord = ($000000, $FFFFFF);
  { NES 2C02 (common emulator palette, duplicates removed) }
  PalNES: array[0..53] of LongWord = (
    $7C7C7C, $0000FC, $0000BC, $4428BC, $940084, $A80020, $A81000, $881400,
    $503000, $007800, $006800, $005800, $004058, $000000,
    $BCBCBC, $0078F8, $0058F8, $6844FC, $D800CC, $E40058, $F83800, $E45C10,
    $AC7C00, $00B800, $00A800, $00A844, $008888,
    $F8F8F8, $3CBCFC, $6888FC, $9878F8, $F878F8, $F85898, $F87858, $FCA044,
    $F8B800, $B8F818, $58D854, $58F898, $00E8D8, $787878,
    $FCFCFC, $A4E4FC, $B8B8F8, $D8B8F8, $F8B8F8, $F8A4C0, $F0D0B0, $FCE0A8,
    $F8D878, $D8F878, $B8F8B8, $B8F8D8, $00FCFC);
  PalEndesga32: array[0..31] of LongWord = (
    $BE4A2F, $D77643, $EAD4AA, $E4A672, $B86F50, $733E39, $3E2731, $A22633,
    $E43B44, $F77622, $FEAE34, $FEE761, $63C74D, $3E8948, $265C42, $193C3E,
    $124E89, $0099DB, $2CE8F5, $FFFFFF, $C0CBDC, $8B9BB4, $5A6988, $3A4466,
    $262B44, $181425, $FF0044, $68386C, $B55088, $F6757A, $E8B796, $C28569);
  PalEndesga16: array[0..15] of LongWord = (
    $E4A672, $B86F50, $743F39, $3F2832, $9E2835, $E53B44, $FB922B, $FFE762,
    $63C64D, $327345, $193D3F, $4F6781, $AFBFD2, $FFFFFF, $2CE8F4, $0484D1);
  PalSweetie16: array[0..15] of LongWord = (
    $1A1C2C, $5D275D, $B13E53, $EF7D57, $FFCD75, $A7F070, $38B764, $257179,
    $29366F, $3B5DC9, $41A6F6, $73EFF7, $F4F4F4, $94B0C2, $566C86, $333C57);
  PalDB16: array[0..15] of LongWord = (
    $140C1C, $442434, $30346D, $4E4A4E, $854C30, $346524, $D04648, $757161,
    $597DCE, $D27D2C, $8595A1, $6DAA2C, $D2AA99, $6DC2CA, $DAD45E, $DEEED6);
  PalDB32: array[0..31] of LongWord = (
    $000000, $222034, $45283C, $663931, $8F563B, $DF7126, $D9A066, $EEC39A,
    $FBF236, $99E550, $6ABE30, $37946E, $4B692F, $524B24, $323C39, $3F3F74,
    $306082, $5B6EE1, $639BFF, $5FCDE4, $CBDBFC, $FFFFFF, $9BADB7, $847E87,
    $696A6A, $595652, $76428A, $AC3232, $D95763, $D77BBA, $8F974A, $8A6F30);
  PalVirtualBoy: array[0..3] of LongWord = ($000000, $550000, $AA0000, $FF0000);
  PalZX: array[0..14] of LongWord = (
    $000000, $0000D7, $D70000, $D700D7, $00D700, $00D7D7, $D7D700, $D7D7D7,
    $0000FF, $FF0000, $FF00FF, $00FF00, $00FFFF, $FFFF00, $FFFFFF);
  PalApple2: array[0..14] of LongWord = (
    $000000, $6C2940, $403578, $D93CF0, $135740, $808080, $2697F0, $BFB4F8,
    $404B07, $D9680F, $ECA8BF, $26C30F, $BFCA87, $93D6BF, $FFFFFF);

procedure DefaultPixelParams(out PP: TPixelParams);
begin
  PP.Size := 32;
  PP.Upscale := 8;
  PP.Palette := ppAdaptive;
  PP.Colors := 16;
  PP.Dither := pdNone;
  PP.DitherStrength := 0.5;
  PP.AlphaMode := paHard;
  PP.Outline := poOuter;
  PP.OutlineColor := $140C1C;
  PP.ToonSteps := 4;
end;

function PixelSphereParams(const SP: TSphereParams; const PP: TPixelParams): TSphereParams;
begin
  Result := SP;
  Result.ToonSteps := PP.ToonSteps;
  { leave room for a 1-pixel outer outline }
  if PP.Outline in [poOuter, poBoth] then
    Result.SizeFrac := Min(Result.SizeFrac, (PP.Size - 2.2) / PP.Size);
end;

procedure RenderPixelRaw(const Tex: TPixelBuf; const SP: TSphereParams; const PP: TPixelParams;
  var Raw: TPixelBuf; Fast: Boolean);
var
  SS: Integer;
begin
  { supersampling averages texture detail inside each art pixel }
  if Fast or (PP.Size > 128) then SS := 2 else SS := 4;
  RenderSphere(Tex, PixelSphereParams(SP, PP), PP.Size, PP.Size, Raw, SS, True);
end;

{ ---------- palette helpers ---------- }

function IsRamp(P: TPixPalette): Boolean;
begin
  Result := P in [ppGameBoy, ppVirtualBoy, ppGray4, ppGray8, ppBW];
end;

procedure CopyPal(const Src: array of LongWord; out Dst: TPalette);
var
  i: Integer;
begin
  SetLength(Dst, Length(Src));
  for i := 0 to High(Src) do Dst[i] := Src[i];
end;

function Chan(c: LongWord; k: Integer): Integer; inline;
begin
  Result := (c shr (16 - 8 * k)) and $FF;
end;

procedure SortByChannel(var A: array of LongWord; L, R, K: Integer);
var
  i, j, pv: Integer;
  t: LongWord;
begin
  while L < R do
  begin
    i := L; j := R;
    pv := Chan(A[(L + R) shr 1], K);
    repeat
      while Chan(A[i], K) < pv do Inc(i);
      while Chan(A[j], K) > pv do Dec(j);
      if i <= j then
      begin
        t := A[i]; A[i] := A[j]; A[j] := t;
        Inc(i); Dec(j);
      end;
    until i > j;
    if j - L < R - i then
    begin
      SortByChannel(A, L, j, K);
      L := i;
    end
    else
    begin
      SortByChannel(A, i, R, K);
      R := j;
    end;
  end;
end;

function MedianCut(var Cols: array of LongWord; N: Integer): TPalette;
type
  TBox = record s, e: Integer; end;
var
  Boxes: array of TBox;
  i, j, k, best, bestK, mid, rng, bestRng: Integer;
  mn, mx: array[0..2] of Integer;
  sr, sg, sb: Int64;
begin
  Result := nil;
  if Length(Cols) = 0 then Exit;
  SetLength(Boxes, 1);
  Boxes[0].s := 0;
  Boxes[0].e := High(Cols);
  while Length(Boxes) < N do
  begin
    best := -1; bestK := 0; bestRng := 0;
    for i := 0 to High(Boxes) do
    begin
      if Boxes[i].e <= Boxes[i].s then Continue;
      for k := 0 to 2 do begin mn[k] := 255; mx[k] := 0; end;
      for j := Boxes[i].s to Boxes[i].e do
        for k := 0 to 2 do
        begin
          if Chan(Cols[j], k) < mn[k] then mn[k] := Chan(Cols[j], k);
          if Chan(Cols[j], k) > mx[k] then mx[k] := Chan(Cols[j], k);
        end;
      for k := 0 to 2 do
      begin
        rng := mx[k] - mn[k];
        if rng > bestRng then
        begin
          bestRng := rng;
          best := i;
          bestK := k;
        end;
      end;
    end;
    if best < 0 then Break;   { every box is a single colour }
    SortByChannel(Cols, Boxes[best].s, Boxes[best].e, bestK);
    mid := (Boxes[best].s + Boxes[best].e) div 2;
    SetLength(Boxes, Length(Boxes) + 1);
    Boxes[High(Boxes)].s := mid + 1;
    Boxes[High(Boxes)].e := Boxes[best].e;
    Boxes[best].e := mid;
  end;
  SetLength(Result, Length(Boxes));
  for i := 0 to High(Boxes) do
  begin
    sr := 0; sg := 0; sb := 0;
    for j := Boxes[i].s to Boxes[i].e do
    begin
      Inc(sr, Chan(Cols[j], 0));
      Inc(sg, Chan(Cols[j], 1));
      Inc(sb, Chan(Cols[j], 2));
    end;
    j := Boxes[i].e - Boxes[i].s + 1;
    Result[i] := (LongWord(sr div j) shl 16) or (LongWord(sg div j) shl 8) or LongWord(sb div j);
  end;
end;

function BuildPalette(const PP: TPixelParams; const Frames: array of TPixelBuf): TPalette;
const
  MAXSAMPLES = 80000;
var
  Cols: array of LongWord;
  f, i, total, stp, n: Integer;
begin
  Result := nil;
  case PP.Palette of
    ppPico8  : CopyPal(PalPico8, Result);
    ppNES    : CopyPal(PalNES, Result);
    ppEndesga32: CopyPal(PalEndesga32, Result);
    ppEndesga16: CopyPal(PalEndesga16, Result);
    ppSweetie16: CopyPal(PalSweetie16, Result);
    ppDB16   : CopyPal(PalDB16, Result);
    ppDB32   : CopyPal(PalDB32, Result);
    ppVirtualBoy: CopyPal(PalVirtualBoy, Result);
    ppZX     : CopyPal(PalZX, Result);
    ppApple2 : CopyPal(PalApple2, Result);
    ppCustom : CopyPal(PP.CustomPal, Result);
    ppGameBoy: CopyPal(PalGameBoy, Result);
    ppCGA    : CopyPal(PalCGA, Result);
    ppC64    : CopyPal(PalC64, Result);
    ppGray4  : CopyPal(PalGray4, Result);
    ppGray8  : CopyPal(PalGray8, Result);
    ppBW     : CopyPal(PalBW, Result);
    ppAdaptive:
      begin
        total := 0;
        for f := 0 to High(Frames) do Inc(total, Length(Frames[f].Data));
        stp := Max(1, total div MAXSAMPLES);
        SetLength(Cols, total div stp + 1);
        n := 0;
        for f := 0 to High(Frames) do
        begin
          i := 0;
          while i <= High(Frames[f].Data) do
          begin
            if (Frames[f].Data[i] shr 24) >= 32 then
            begin
              Cols[n] := Frames[f].Data[i] and $FFFFFF;
              Inc(n);
            end;
            Inc(i, stp);
          end;
        end;
        SetLength(Cols, n);
        Result := MedianCut(Cols, EnsureRange(PP.Colors, 2, 64));
      end;
  end;
end;

{ ---------- palette files ---------- }

{ Reads Lospec .hex (RRGGBB per line), Paint.NET .txt (AARRGGBB, ';' comments),
  GIMP .gpl ("R G B name"), or the distinct colours of an image file. }
function LoadPaletteFile(const FileName: string; out Pal: TPalette; out Err: string): Boolean;
const
  MAXCOLS = 256;
var
  L: TStringList;
  Line, Ext, Tok: string;
  i, j, n, r, g, b: Integer;
  v: LongWord;
  Img: TPixelBuf;
  Cols: array of LongWord;
  Parts: TStringArray;
  Dup: Boolean;

  procedure AddCol(c: LongWord);
  var
    k: Integer;
  begin
    c := c and $FFFFFF;
    for k := 0 to n - 1 do
      if Pal[k] = c then Exit;
    if n >= Length(Pal) then SetLength(Pal, n + 64);
    Pal[n] := c;
    Inc(n);
  end;

begin
  Result := False;
  Err := '';
  Pal := nil;
  n := 0;
  Ext := LowerCase(ExtractFileExt(FileName));
  if (Ext = '.hex') or (Ext = '.txt') or (Ext = '.gpl') then
  begin
    L := TStringList.Create;
    try
      try
        L.LoadFromFile(FileName);
      except
        on E: Exception do
        begin
          Err := E.Message;
          Exit;
        end;
      end;
      for i := 0 to L.Count - 1 do
      begin
        Line := Trim(L[i]);
        if (Line = '') or (Line[1] = ';') or (Line[1] = '#') and (Ext = '.gpl') then Continue;
        if Ext = '.gpl' then
        begin
          { "R G B<tab>name"; skip header lines such as "GIMP Palette", "Name:", "Columns:" }
          Parts := Line.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
          if (Length(Parts) >= 3) and TryStrToInt(Parts[0], r) and TryStrToInt(Parts[1], g) and
             TryStrToInt(Parts[2], b) then
            AddCol((LongWord(EnsureRange(r, 0, 255)) shl 16) or (LongWord(EnsureRange(g, 0, 255)) shl 8) or
              LongWord(EnsureRange(b, 0, 255)));
        end
        else
        begin
          Tok := Line;
          if Tok[1] = '#' then Delete(Tok, 1, 1);
          if (Length(Tok) = 6) or (Length(Tok) = 8) then
            if TryStrToDWord('$' + Tok, v) then AddCol(v);   { AARRGGBB: AddCol drops alpha }
        end;
        if n >= MAXCOLS then Break;
      end;
    finally
      L.Free;
    end;
  end
  else
  begin
    { image: take its distinct opaque colours (reduced to 256 if needed) }
    if not BufLoadFile(FileName, Img, Err) then Exit;
    SetLength(Cols, 0);
    for i := 0 to High(Img.Data) do
      if (Img.Data[i] shr 24) >= 128 then
      begin
        AddCol(Img.Data[i]);
        if n > 4096 then Break;
      end;
    if n > MAXCOLS then
    begin
      SetLength(Cols, Length(Img.Data));
      j := 0;
      for i := 0 to High(Img.Data) do
        if (Img.Data[i] shr 24) >= 128 then
        begin
          Cols[j] := Img.Data[i] and $FFFFFF;
          Inc(j);
        end;
      SetLength(Cols, j);
      Pal := MedianCut(Cols, MAXCOLS);
      n := Length(Pal);
    end;
  end;
  SetLength(Pal, n);
  Dup := n = 0;
  if Dup then
  begin
    Err := 'No colours found in ' + ExtractFileName(FileName);
    Exit;
  end;
  Result := True;
end;

{ ---------- dithering ---------- }

function BayerValue(n, x, y: Integer): Integer;
const
  M2: array[0..1, 0..1] of Integer = ((0, 2), (3, 1));
var
  h: Integer;
begin
  if n <= 1 then Exit(0);
  h := n div 2;
  Result := 4 * BayerValue(h, x mod h, y mod h) + M2[y div h, x div h];
end;

function BayerThreshold(D: TPixDither; x, y: Integer): Double;
var
  n: Integer;
begin
  case D of
    pdBayer2: n := 2;
    pdBayer8: n := 8;
  else
    n := 4;
  end;
  Result := (BayerValue(n, x mod n, y mod n) + 0.5) / (n * n);
end;

{ ---------- colour quantization ---------- }

procedure Quantize(const PP: TPixelParams; const Pal: TPalette; var r, g, b: Double; bias: Double);
var
  L, i, best, n: Integer;
  lum, d, bd, cr, cg, cb: Double;
  c: LongWord;
begin
  case PP.Palette of
    ppFull: ;
    ppPosterize:
      begin
        L := EnsureRange(PP.Colors, 2, 16) - 1;
        r := Round(EnsureRange(r + bias, 0, 1) * L) / L;
        g := Round(EnsureRange(g + bias, 0, 1) * L) / L;
        b := Round(EnsureRange(b + bias, 0, 1) * L) / L;
      end;
  else
    n := Length(Pal);
    if n = 0 then Exit;
    if IsRamp(PP.Palette) then
    begin
      { dark-to-light ramp palettes: map brightness to palette index }
      lum := 0.299 * r + 0.587 * g + 0.114 * b + bias;
      best := EnsureRange(Round(lum * (n - 1)), 0, n - 1);
    end
    else
    begin
      cr := (r + bias) * 255; cg := (g + bias) * 255; cb := (b + bias) * 255;
      best := 0; bd := 1e30;
      for i := 0 to n - 1 do
      begin
        c := Pal[i];
        d := 2 * Sqr(cr - Chan(c, 0)) + 4 * Sqr(cg - Chan(c, 1)) + 3 * Sqr(cb - Chan(c, 2));
        if d < bd then
        begin
          bd := d;
          best := i;
        end;
      end;
    end;
    c := Pal[best];
    r := Chan(c, 0) / 255;
    g := Chan(c, 1) / 255;
    b := Chan(c, 2) / 255;
  end;
end;

function DitherSpread(const PP: TPixelParams; const Pal: TPalette): Double;
var
  n: Integer;
begin
  case PP.Palette of
    ppFull: Result := 0;
    ppPosterize: Result := 1 / (EnsureRange(PP.Colors, 2, 16) - 1);
  else
    n := Max(2, Length(Pal));
    if IsRamp(PP.Palette) then
      Result := 1 / (n - 1)
    else
      Result := 0.7 / Power(n, 1 / 3);
  end;
  Result := Result * PP.DitherStrength;
end;

procedure PixelFinish(const Raw: TPixelBuf; const SP: TSphereParams; const PP: TPixelParams;
  const Pal: TPalette; var Dst: TPixelBuf);
var
  W, H, x, y, i: Integer;
  P: TSphereParams;
  R, G, B, A: array of Double;
  Mask: array of Boolean;
  EdgeIn, EdgeOut: Boolean;
  c: LongWord;
  spread, bias, tr, tg, tb, er, eg, eb: Double;
  OR_, OG, OB: Byte;

  function InMask(xx, yy: Integer): Boolean;
  begin
    Result := (xx >= 0) and (yy >= 0) and (xx < W) and (yy < H) and Mask[yy * W + xx];
  end;

  procedure AddErr(xx, yy: Integer; f: Double);
  var
    k: Integer;
  begin
    if (xx < 0) or (xx >= W) or (yy >= H) then Exit;
    k := yy * W + xx;
    if A[k] <= 0 then Exit;
    R[k] := R[k] + er * f;
    G[k] := G[k] + eg * f;
    B[k] := B[k] + eb * f;
  end;

begin
  W := Raw.W; H := Raw.H;
  BufInit(Dst, W, H, 0);
  if (W = 0) or (H = 0) then Exit;
  P := PixelSphereParams(SP, PP);
  SetLength(R, W * H); SetLength(G, W * H); SetLength(B, W * H); SetLength(A, W * H);
  SetLength(Mask, W * H);

  for y := 0 to H - 1 do
    for x := 0 to W - 1 do
    begin
      i := y * W + x;
      c := Raw.Data[i];
      R[i] := ((c shr 16) and $FF) / 255;
      G[i] := ((c shr 8) and $FF) / 255;
      B[i] := (c and $FF) / 255;
      A[i] := (c shr 24) / 255;
      Mask[i] := InsideSphere(P, W, H, x, y);
      { 1. transparency }
      if not Mask[i] then
        A[i] := 0
      else
        case PP.AlphaMode of
          paHard   : if A[i] >= 0.5 then A[i] := 1 else A[i] := 0;
          paDither : if A[i] > BayerThreshold(PP.Dither, x, y) then A[i] := 1 else A[i] := 0;
          paStepped: A[i] := Round(A[i] * 3) / 3;
        end;
    end;

  { 2. inner edge shading (before quantization, so it stays in palette) }
  if PP.Outline in [poInner, poBoth] then
    for y := 0 to H - 1 do
      for x := 0 to W - 1 do
      begin
        i := y * W + x;
        if not Mask[i] then Continue;
        EdgeIn := not (InMask(x - 1, y) and InMask(x + 1, y) and InMask(x, y - 1) and InMask(x, y + 1));
        if EdgeIn then
        begin
          R[i] := R[i] * 0.55; G[i] := G[i] * 0.55; B[i] := B[i] * 0.55;
          A[i] := 1;
        end;
      end;

  { 3. colour reduction + dithering }
  spread := DitherSpread(PP, Pal);
  for y := 0 to H - 1 do
    for x := 0 to W - 1 do
    begin
      i := y * W + x;
      if A[i] <= 0 then Continue;
      if PP.Dither = pdFloyd then
      begin
        tr := EnsureRange(R[i], 0, 1); tg := EnsureRange(G[i], 0, 1); tb := EnsureRange(B[i], 0, 1);
        R[i] := tr; G[i] := tg; B[i] := tb;
        Quantize(PP, Pal, R[i], G[i], B[i], 0);
        er := (tr - R[i]) * PP.DitherStrength * 2;
        eg := (tg - G[i]) * PP.DitherStrength * 2;
        eb := (tb - B[i]) * PP.DitherStrength * 2;
        if PP.Palette <> ppFull then
        begin
          AddErr(x + 1, y, 7 / 16);
          AddErr(x - 1, y + 1, 3 / 16);
          AddErr(x, y + 1, 5 / 16);
          AddErr(x + 1, y + 1, 1 / 16);
        end;
      end
      else
      begin
        if PP.Dither = pdNone then bias := 0
        else bias := (BayerThreshold(PP.Dither, x, y) - 0.5) * spread;
        Quantize(PP, Pal, R[i], G[i], B[i], bias);
      end;
    end;

  { 4. write output + outer outline }
  OR_ := (PP.OutlineColor shr 16) and $FF;
  OG := (PP.OutlineColor shr 8) and $FF;
  OB := PP.OutlineColor and $FF;
  for y := 0 to H - 1 do
    for x := 0 to W - 1 do
    begin
      i := y * W + x;
      if Mask[i] then
      begin
        if A[i] <= 0 then Continue;
        Dst.Data[i] := (LongWord(Round(EnsureRange(A[i], 0, 1) * 255)) shl 24) or
                       (LongWord(Round(EnsureRange(R[i], 0, 1) * 255)) shl 16) or
                       (LongWord(Round(EnsureRange(G[i], 0, 1) * 255)) shl 8) or
                        LongWord(Round(EnsureRange(B[i], 0, 1) * 255));
      end
      else if PP.Outline in [poOuter, poBoth] then
      begin
        EdgeOut := InMask(x - 1, y) or InMask(x + 1, y) or InMask(x, y - 1) or InMask(x, y + 1);
        if EdgeOut then
          Dst.Data[i] := $FF000000 or (LongWord(OR_) shl 16) or (LongWord(OG) shl 8) or OB;
      end;
    end;
end;

procedure RenderPixelSphere(const Tex: TPixelBuf; const SP: TSphereParams; const PP: TPixelParams;
  var Dst: TPixelBuf; Fast: Boolean);
var
  Raw: TPixelBuf;
  Pal: TPalette;
begin
  RenderPixelRaw(Tex, SP, PP, Raw, Fast);
  Pal := BuildPalette(PP, [Raw]);
  PixelFinish(Raw, SP, PP, Pal, Dst);
end;

procedure BufScaleNearest(const Src: TPixelBuf; K: Integer; var Dst: TPixelBuf);
var
  x, y, sy, i: Integer;
  Row: PLongWord;
  c: LongWord;
begin
  K := Max(1, K);
  BufInit(Dst, Src.W * K, Src.H * K, 0);
  for y := 0 to Dst.H - 1 do
  begin
    sy := y div K;
    Row := @Dst.Data[y * Dst.W];
    for x := 0 to Src.W - 1 do
    begin
      c := Src.Data[sy * Src.W + x];
      for i := 1 to K do
      begin
        Row^ := c;
        Inc(Row);
      end;
    end;
  end;
end;

end.
