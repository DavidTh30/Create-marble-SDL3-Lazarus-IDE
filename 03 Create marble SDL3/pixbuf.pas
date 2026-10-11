unit PixBuf;

{ Simple 32-bit ARGB pixel buffer ($AARRGGBB, straight alpha) plus
  SDL3-based load/save and conversion to an LCL TBitmap for display.
  The LongWord layout matches SDL_PIXELFORMAT_ARGB8888, so rows can be
  copied directly into SDL surfaces. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Graphics, GraphType, IntfGraphics, SDL3Lib;

type
  TPixelBuf = record
    W, H: Integer;
    Data: array of LongWord;
  end;

  TPreviewBg = (pbChecker, pbBlack, pbGrey, pbWhite);

procedure BufInit(var B: TPixelBuf; AW, AH: Integer; Fill: LongWord = 0);
function  BufLoadFile(const FileName: string; var B: TPixelBuf; out Err: string): Boolean;
function  BufSaveFile(const FileName: string; const B: TPixelBuf; out Err: string): Boolean;
procedure BufToBitmap(const B: TPixelBuf; Bmp: TBitmap; Bg: TPreviewBg; CheckSize: Integer = 8);
procedure BufBlit(const Src: TPixelBuf; var Dst: TPixelBuf; DX, DY: Integer);

implementation

procedure BufInit(var B: TPixelBuf; AW, AH: Integer; Fill: LongWord);
var
  i: Integer;
begin
  B.W := AW;
  B.H := AH;
  SetLength(B.Data, AW * AH);
  for i := 0 to High(B.Data) do B.Data[i] := Fill;
end;

function SurfaceToBuf(S: PSDL_Surface; var B: TPixelBuf): Boolean;
var
  Conv: PSDL_Surface;
  y: Integer;
begin
  Result := False;
  Conv := SDL_ConvertSurface(S, SDL_PIXELFORMAT_ARGB8888);
  if Conv = nil then Exit;
  try
    SDL_LockSurface(Conv);
    BufInit(B, Conv^.w, Conv^.h);
    for y := 0 to Conv^.h - 1 do
      Move((PByte(Conv^.pixels) + PtrInt(y) * Conv^.pitch)^, B.Data[y * B.W], B.W * 4);
    SDL_UnlockSurface(Conv);
    Result := True;
  finally
    SDL_DestroySurface(Conv);
  end;
end;

function BufLoadFile(const FileName: string; var B: TPixelBuf; out Err: string): Boolean;
var
  S: PSDL_Surface;
  Ext: string;
begin
  Result := False;
  Err := '';
  if not SDL3Loaded then
  begin
    Err := 'SDL3 is not loaded';
    Exit;
  end;
  Ext := LowerCase(ExtractFileExt(FileName));
  if SDL3ImageLoaded then
    S := IMG_Load(PAnsiChar(UTF8String(FileName)))
  else if Ext = '.bmp' then
    S := SDL_LoadBMP(PAnsiChar(UTF8String(FileName)))
  else
  begin
    Err := 'SDL3_image is required to load ' + Ext + ' files';
    Exit;
  end;
  if S = nil then
  begin
    Err := SDLErrorStr;
    Exit;
  end;
  try
    Result := SurfaceToBuf(S, B);
    if not Result then Err := SDLErrorStr;
  finally
    SDL_DestroySurface(S);
  end;
end;

function BufSaveFile(const FileName: string; const B: TPixelBuf; out Err: string): Boolean;
var
  S: PSDL_Surface;
  y: Integer;
  Ext: string;
  Ok: Boolean;
begin
  Result := False;
  Err := '';
  if not SDL3Loaded then
  begin
    Err := 'SDL3 is not loaded';
    Exit;
  end;
  if (B.W <= 0) or (B.H <= 0) then
  begin
    Err := 'Image is empty';
    Exit;
  end;
  S := SDL_CreateSurface(B.W, B.H, SDL_PIXELFORMAT_ARGB8888);
  if S = nil then
  begin
    Err := SDLErrorStr;
    Exit;
  end;
  try
    SDL_LockSurface(S);
    for y := 0 to B.H - 1 do
      Move(B.Data[y * B.W], (PByte(S^.pixels) + PtrInt(y) * S^.pitch)^, B.W * 4);
    SDL_UnlockSurface(S);

    Ext := LowerCase(ExtractFileExt(FileName));
    if Ext = '.bmp' then
      Ok := SDL_SaveBMP(S, PAnsiChar(UTF8String(FileName)))
    else if Ext = '.png' then
    begin
      if not SDL3ImageLoaded then
      begin
        Err := 'SDL3_image is required to save PNG files';
        Exit;
      end;
      Ok := IMG_SavePNG(S, PAnsiChar(UTF8String(FileName)));
    end
    else
    begin
      Err := 'Unsupported file type: ' + Ext + ' (use .png or .bmp)';
      Exit;
    end;
    if not Ok then Err := SDLErrorStr;
    Result := Ok;
  finally
    SDL_DestroySurface(S);
  end;
end;

procedure BufToBitmap(const B: TPixelBuf; Bmp: TBitmap; Bg: TPreviewBg; CheckSize: Integer);
var
  Img: TLazIntfImage;
  Desc: TRawImageDescription;
  x, y: Integer;
  P: PLongWord;
  c, bgc: LongWord;
  a, r, g, bl: Integer;
  br, bgg, bb: Integer;
begin
  if (B.W <= 0) or (B.H <= 0) then Exit;
  if CheckSize < 1 then CheckSize := 1;
  Img := TLazIntfImage.Create(0, 0);
  try
    Desc.Init_BPP32_B8G8R8A8_BIO_TTB(B.W, B.H);
    Img.DataDescription := Desc;
    for y := 0 to B.H - 1 do
    begin
      P := PLongWord(Img.GetDataLineStart(y));
      for x := 0 to B.W - 1 do
      begin
        case Bg of
          pbChecker:
            if (((x div CheckSize) + (y div CheckSize)) and 1) = 0 then
              bgc := $C8C8C8 else bgc := $969696;
          pbBlack: bgc := $000000;
          pbGrey:  bgc := $404040;
        else
          bgc := $FFFFFF;
        end;
        c := B.Data[y * B.W + x];
        a := c shr 24;
        br := (bgc shr 16) and $FF;
        bgg := (bgc shr 8) and $FF;
        bb := bgc and $FF;
        r  := br  + (Integer((c shr 16) and $FF) - br)  * a div 255;
        g  := bgg + (Integer((c shr 8) and $FF) - bgg) * a div 255;
        bl := bb  + (Integer(c and $FF) - bb) * a div 255;
        P^ := $FF000000 or (LongWord(r) shl 16) or (LongWord(g) shl 8) or LongWord(bl);
        Inc(P);
      end;
    end;
    Bmp.LoadFromIntfImage(Img);
  finally
    Img.Free;
  end;
end;

procedure BufBlit(const Src: TPixelBuf; var Dst: TPixelBuf; DX, DY: Integer);
var
  y, n: Integer;
begin
  for y := 0 to Src.H - 1 do
  begin
    if (DY + y < 0) or (DY + y >= Dst.H) then Continue;
    n := Src.W;
    if DX + n > Dst.W then n := Dst.W - DX;
    if (n <= 0) or (DX < 0) then Continue;
    Move(Src.Data[y * Src.W], Dst.Data[(DY + y) * Dst.W + DX], n * 4);
  end;
end;

end.
