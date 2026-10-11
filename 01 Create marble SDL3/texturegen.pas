unit TextureGen;

{ Procedural material textures in equirectangular (longitude/latitude)
  layout, ready to be wrapped around a sphere. Every pattern is evaluated
  on the 3D unit sphere, so the textures are seamless and do not pinch at
  the poles once wrapped. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, PixBuf;

type
  TTexKind = (tkMarble, tkGranite, tkWood, tkMetal, tkGlass, tkCartoon, tkGlobe, tkGrid);

  TTexParams = record
    Kind       : TTexKind;
    Style      : Integer;
    Width      : Integer;
    Height     : Integer;
    Color1     : LongWord;  { LCL TColor layout: $00BBGGRR }
    Color2     : LongWord;
    Color3     : LongWord;
    Scale      : Double;    { pattern frequency }
    Turbulence : Double;    { distortion / twist / clouds depending on kind }
    Octaves    : Integer;   { noise detail 1..8 }
    BaseAlpha  : Double;    { 0..1; base glass opacity, or overall alpha }
    Seed       : LongInt;
  end;

  TProgressProc = procedure(Percent: Integer) of object;

const
  KindNames: array[TTexKind] of string = (
    'Stone - Marble', 'Stone - Granite', 'Wood grain', 'Metal',
    'Glass', 'Cartoon', 'Globe / Planet', 'UV test grid');

function  StyleNames(K: TTexKind): TStringArray;
procedure DefaultParams(K: TTexKind; var P: TTexParams);
function  ApplyStyleColors(var P: TTexParams): Boolean;
procedure GenerateTexture(const P: TTexParams; var B: TPixelBuf; Progress: TProgressProc = nil);

implementation

type
  TCol = record r, g, b, a: Double; end;

  TPerlin = object
    Perm: array[0..511] of Byte;
    procedure Init(Seed: LongInt);
    function Noise(x, y, z: Double): Double;
    function FBM(x, y, z: Double; Oct: Integer): Double;
    function Turb(x, y, z: Double; Oct: Integer): Double;
    procedure Worley(x, y, z: Double; out F1, F2, CellId: Double);
  end;

{ ---------- helpers ---------- }

function Col(r, g, b: Double; a: Double = 1): TCol; inline;
begin
  Result.r := r; Result.g := g; Result.b := b; Result.a := a;
end;

function ColFromTColor(c: LongWord): TCol;
begin
  Result.r := (c and $FF) / 255;
  Result.g := ((c shr 8) and $FF) / 255;
  Result.b := ((c shr 16) and $FF) / 255;
  Result.a := 1;
end;

function Mix(const A, B: TCol; t: Double): TCol; inline;
begin
  Result.r := A.r + (B.r - A.r) * t;
  Result.g := A.g + (B.g - A.g) * t;
  Result.b := A.b + (B.b - A.b) * t;
  Result.a := A.a + (B.a - A.a) * t;
end;

function Scl(const A: TCol; f: Double): TCol; inline;
begin
  Result.r := A.r * f; Result.g := A.g * f; Result.b := A.b * f; Result.a := A.a;
end;

function Clamp01(v: Double): Double; inline;
begin
  if v < 0 then Result := 0 else if v > 1 then Result := 1 else Result := v;
end;

function SmoothStep(e0, e1, x: Double): Double; inline;
var
  t: Double;
begin
  if e1 = e0 then
  begin
    if x < e0 then Exit(0) else Exit(1);
  end;
  t := Clamp01((x - e0) / (e1 - e0));
  Result := t * t * (3 - 2 * t);
end;

function FastFloor(x: Double): Integer; inline;
begin
  Result := Trunc(x);
  if x < Result then Dec(Result);
end;

function Fract(x: Double): Double; inline;
begin
  Result := x - FastFloor(x);
end;

function PackCol(const C: TCol): LongWord;
var
  r, g, b, a: Integer;
begin
  r := Round(Clamp01(C.r) * 255);
  g := Round(Clamp01(C.g) * 255);
  b := Round(Clamp01(C.b) * 255);
  a := Round(Clamp01(C.a) * 255);
  Result := (LongWord(a) shl 24) or (LongWord(r) shl 16) or (LongWord(g) shl 8) or LongWord(b);
end;

function Hue(h: Double): TCol;
var
  i: Integer;
  f: Double;
begin
  h := Fract(h) * 6;
  i := Trunc(h);
  f := h - i;
  case i of
    0: Result := Col(1, f, 0);
    1: Result := Col(1 - f, 1, 0);
    2: Result := Col(0, 1, f);
    3: Result := Col(0, 1 - f, 1);
    4: Result := Col(f, 0, 1);
  else
    Result := Col(1, 0, 1 - f);
  end;
end;

{ ---------- noise ---------- }

procedure TPerlin.Init(Seed: LongInt);
var
  i, j: Integer;
  t: Byte;
  s: LongWord;

  function NextRand: LongWord;
  begin
    { xorshift32 }
    s := s xor (s shl 13);
    s := s xor (s shr 17);
    s := s xor (s shl 5);
    Result := s;
  end;

begin
  s := LongWord(Seed) * 2654435761 + 12345;
  if s = 0 then s := 1;
  for i := 0 to 255 do Perm[i] := i;
  for i := 255 downto 1 do
  begin
    j := NextRand mod LongWord(i + 1);
    t := Perm[i]; Perm[i] := Perm[j]; Perm[j] := t;
  end;
  for i := 0 to 255 do Perm[256 + i] := Perm[i];
end;

function Fade(t: Double): Double; inline;
begin
  Result := t * t * t * (t * (t * 6 - 15) + 10);
end;

function Grad(h: Integer; x, y, z: Double): Double; inline;
var
  u, v: Double;
begin
  h := h and 15;
  if h < 8 then u := x else u := y;
  if h < 4 then v := y
  else if (h = 12) or (h = 14) then v := x
  else v := z;
  if (h and 1) <> 0 then u := -u;
  if (h and 2) <> 0 then v := -v;
  Result := u + v;
end;

function Lerp(t, a, b: Double): Double; inline;
begin
  Result := a + t * (b - a);
end;

function TPerlin.Noise(x, y, z: Double): Double;
var
  X0, Y0, Z0, A, AA, AB, B, BA, BB: Integer;
  xf, yf, zf, u, v, w: Double;
begin
  X0 := FastFloor(x); Y0 := FastFloor(y); Z0 := FastFloor(z);
  xf := x - X0; yf := y - Y0; zf := z - Z0;
  X0 := X0 and 255; Y0 := Y0 and 255; Z0 := Z0 and 255;
  u := Fade(xf); v := Fade(yf); w := Fade(zf);
  A := Perm[X0] + Y0;     AA := Perm[A] + Z0; AB := Perm[A + 1] + Z0;
  B := Perm[X0 + 1] + Y0; BA := Perm[B] + Z0; BB := Perm[B + 1] + Z0;
  Result := Lerp(w,
    Lerp(v, Lerp(u, Grad(Perm[AA], xf, yf, zf),       Grad(Perm[BA], xf - 1, yf, zf)),
            Lerp(u, Grad(Perm[AB], xf, yf - 1, zf),   Grad(Perm[BB], xf - 1, yf - 1, zf))),
    Lerp(v, Lerp(u, Grad(Perm[AA + 1], xf, yf, zf - 1),     Grad(Perm[BA + 1], xf - 1, yf, zf - 1)),
            Lerp(u, Grad(Perm[AB + 1], xf, yf - 1, zf - 1), Grad(Perm[BB + 1], xf - 1, yf - 1, zf - 1))));
end;

function TPerlin.FBM(x, y, z: Double; Oct: Integer): Double;
var
  i: Integer;
  amp, sum, norm: Double;
begin
  sum := 0; amp := 1; norm := 0;
  for i := 1 to Max(1, Oct) do
  begin
    sum := sum + Noise(x, y, z) * amp;
    norm := norm + amp;
    amp := amp * 0.5;
    x := x * 2.03; y := y * 2.03; z := z * 2.03;
  end;
  Result := sum / norm;
end;

function TPerlin.Turb(x, y, z: Double; Oct: Integer): Double;
var
  i: Integer;
  amp, sum, norm: Double;
begin
  sum := 0; amp := 1; norm := 0;
  for i := 1 to Max(1, Oct) do
  begin
    sum := sum + Abs(Noise(x, y, z)) * amp;
    norm := norm + amp;
    amp := amp * 0.5;
    x := x * 2.03; y := y * 2.03; z := z * 2.03;
  end;
  Result := sum / norm;
end;

procedure TPerlin.Worley(x, y, z: Double; out F1, F2, CellId: Double);
var
  ix, iy, iz, dx, dy, dz, h: Integer;
  cx, cy, cz, px, py, pz, d: Double;
begin
  ix := FastFloor(x); iy := FastFloor(y); iz := FastFloor(z);
  F1 := 1e9; F2 := 1e9; CellId := 0;
  for dx := -1 to 1 do
    for dy := -1 to 1 do
      for dz := -1 to 1 do
      begin
        cx := ix + dx; cy := iy + dy; cz := iz + dz;
        h := Perm[(Perm[(Perm[(ix + dx) and 255] + ((iy + dy) and 255)) and 255] + ((iz + dz) and 255)) and 255];
        px := cx + Perm[h] / 255;
        py := cy + Perm[(h + 85) and 255] / 255;
        pz := cz + Perm[(h + 170) and 255] / 255;
        d := Sqrt(Sqr(px - x) + Sqr(py - y) + Sqr(pz - z));
        if d < F1 then
        begin
          F2 := F1;
          F1 := d;
          CellId := h / 255;
        end
        else if d < F2 then
          F2 := d;
      end;
end;

{ ---------- public helpers ---------- }

function StyleNames(K: TTexKind): TStringArray;
begin
  case K of
    tkMarble : Result := TStringArray.Create('Veined', 'Onyx bands');
    tkGranite: Result := TStringArray.Create('Speckled granite', 'Pebbles / cobble');
    tkWood   : Result := TStringArray.Create('Rings (end grain)', 'Straight grain');
    tkMetal  : Result := TStringArray.Create('Brushed', 'Hammered');
    tkGlass  : Result := TStringArray.Create('Cat''s eye', 'Swirl', 'Clear with bubbles');
    tkCartoon: Result := TStringArray.Create('Stripes', 'Polka dots', 'Spiral', 'Checker');
    tkGlobe  : Result := TStringArray.Create('Earth-like', 'Desert planet', 'Gas giant');
    tkGrid   : Result := TStringArray.Create('Checker + lines');
  else
    Result := TStringArray.Create('Default');
  end;
end;

function RGBc(r, g, b: Byte): LongWord; inline;
begin
  Result := r or (LongWord(g) shl 8) or (LongWord(b) shl 16);
end;

procedure DefaultParams(K: TTexKind; var P: TTexParams);
begin
  P.Kind := K;
  P.Octaves := 6;
  P.BaseAlpha := 1.0;
  case K of
    tkMarble:
      begin
        P.Color1 := RGBc(236, 232, 224); P.Color2 := RGBc(70, 70, 82); P.Color3 := RGBc(205, 190, 170);
        P.Scale := 2.0; P.Turbulence := 2.5;
      end;
    tkGranite:
      begin
        P.Color1 := RGBc(160, 150, 145); P.Color2 := RGBc(40, 38, 40); P.Color3 := RGBc(230, 215, 205);
        P.Scale := 2.0; P.Turbulence := 1.0;
      end;
    tkWood:
      begin
        P.Color1 := RGBc(214, 160, 100); P.Color2 := RGBc(120, 70, 35); P.Color3 := RGBc(235, 190, 130);
        P.Scale := 2.0; P.Turbulence := 1.5;
      end;
    tkMetal:
      begin
        P.Color1 := RGBc(225, 228, 232); P.Color2 := RGBc(95, 100, 110); P.Color3 := RGBc(255, 255, 255);
        P.Scale := 1.0; P.Turbulence := 1.0;
      end;
    tkGlass:
      begin
        P.Color1 := RGBc(170, 220, 235); P.Color2 := RGBc(230, 40, 40); P.Color3 := RGBc(250, 200, 30);
        P.Scale := 2.0; P.Turbulence := 1.0; P.BaseAlpha := 0.2;
      end;
    tkCartoon:
      begin
        P.Color1 := RGBc(255, 220, 40); P.Color2 := RGBc(240, 60, 90); P.Color3 := RGBc(20, 20, 30);
        P.Scale := 2.0; P.Turbulence := 0.5;
      end;
    tkGlobe:
      begin
        P.Color1 := RGBc(30, 80, 160); P.Color2 := RGBc(70, 140, 60); P.Color3 := RGBc(245, 250, 255);
        P.Scale := 1.5; P.Turbulence := 1.0; P.Octaves := 7;
      end;
    tkGrid:
      begin
        P.Color1 := RGBc(240, 240, 240); P.Color2 := RGBc(60, 60, 60); P.Color3 := RGBc(0, 0, 0);
        P.Scale := 1.0; P.Turbulence := 0;
      end;
  end;
end;

{ Some styles need their own palette. Returns True if colors changed. }
function ApplyStyleColors(var P: TTexParams): Boolean;
begin
  Result := True;
  if P.Kind = tkGlobe then
    case P.Style of
      0: begin P.Color1 := RGBc(30, 80, 160); P.Color2 := RGBc(70, 140, 60); P.Color3 := RGBc(245, 250, 255); end;
      1: begin P.Color1 := RGBc(60, 110, 140); P.Color2 := RGBc(205, 135, 75); P.Color3 := RGBc(120, 70, 50); end;
      2: begin P.Color1 := RGBc(120, 80, 50); P.Color2 := RGBc(225, 190, 140); P.Color3 := RGBc(250, 240, 225); end;
    end
  else
    Result := False;
end;

{ ---------- generators ---------- }

type
  TGenCtx = record
    N: TPerlin;
    P: TTexParams;
    C1, C2, C3: TCol;
    Dots: array of array[0..2] of Double;
    DotR: Double;
  end;

{ x,y,z = point on unit sphere; lon in -pi..pi, lat in -pi/2..pi/2 }

function GenMarble(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  s, t, f, vein, mott, band: Double;
begin
  s := G.P.Scale; t := G.P.Turbulence;
  x := x * s + 11.3; y := y * s + 3.7; z := z * s + 7.1;
  if G.P.Style = 0 then
  begin
    f := Sin((x * 0.8 + y * 1.6 + z * 0.4) * 2.5 + t * 4 * G.N.Turb(x, y, z, G.P.Octaves));
    vein := Power(1 - Abs(f), 8);
    vein := Max(vein, 0.6 * Power(1 - Abs(Sin((x - y * 0.7) * 4 + t * 6 * G.N.Turb(x * 2, y * 2, z * 2, G.P.Octaves))), 14));
    mott := 0.5 + 0.5 * G.N.FBM(x * 2 + 17, y * 2, z * 2, G.P.Octaves);
    Result := Mix(G.C1, G.C3, mott * 0.45);
    Result := Mix(Result, G.C2, Clamp01(vein));
  end
  else
  begin
    band := 0.5 + 0.5 * Sin(y * 5 + t * 3 * G.N.FBM(x, y, z, G.P.Octaves));
    if band < 0.5 then
      Result := Mix(G.C2, G.C3, band * 2)
    else
      Result := Mix(G.C3, G.C1, (band - 0.5) * 2);
    Result := Scl(Result, 0.92 + 0.12 * G.N.Noise(x * 12, y * 12, z * 12));
  end;
end;

function GenGranite(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  s, n1, n2, n3, F1, F2, id, edge: Double;
begin
  s := G.P.Scale;
  if G.P.Style = 0 then
  begin
    x := x * s * 3; y := y * s * 3; z := z * s * 3;
    n1 := G.N.FBM(x, y, z, G.P.Octaves);
    n2 := G.N.Noise(x * 4.7 + 31, y * 4.7, z * 4.7);
    n3 := G.N.Noise(x * 9.3 + 7, y * 9.3 + 5, z * 9.3);
    Result := Scl(G.C1, 0.85 + 0.3 * (0.5 + 0.5 * n1) + G.P.Turbulence * 0.08 * G.N.Noise(x * 0.3, y * 0.3, z * 0.3));
    Result := Mix(Result, G.C2, SmoothStep(0.22, 0.30, n2));
    Result := Mix(Result, G.C3, SmoothStep(0.30, 0.38, n3));
  end
  else
  begin
    x := x * s * 2; y := y * s * 2; z := z * s * 2;
    n1 := G.N.FBM(x * 2, y * 2, z * 2, 3) * 0.15 * G.P.Turbulence;
    G.N.Worley(x + n1, y + n1, z + n1, F1, F2, id);
    edge := SmoothStep(0.03, 0.12, F2 - F1);
    Result := Mix(G.C1, G.C2, id);
    Result := Scl(Result, 0.75 + 0.35 * (1 - F1) + 0.08 * G.N.Noise(x * 8, y * 8, z * 8));
    Result := Mix(G.C3, Result, edge);
  end;
end;

function GenWood(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  s, tb, r, ring, dark, grain: Double;
begin
  s := G.P.Scale;
  x := x * s; y := y * s; z := z * s;
  tb := G.N.FBM(x * 1.5, y * 1.5, z * 1.5, G.P.Octaves) * G.P.Turbulence * 0.6;
  if G.P.Style = 0 then
    r := Sqrt(y * y + z * z) * 4 + tb
  else
    r := y * 6 + z * 0.8 + tb * 1.5;
  ring := Fract(r);
  dark := SmoothStep(0.55, 0.9, ring) * (1 - SmoothStep(0.92, 1.0, ring)) + 0.25 * ring;
  grain := G.N.Noise(x * 2, y * 45, z * 45) * 0.08 + G.N.Noise(x * 6, y * 120, z * 120) * 0.04;
  Result := Mix(G.C1, G.C2, Clamp01(dark));
  Result := Mix(Result, G.C3, 0.3 * (0.5 + 0.5 * G.N.FBM(x * 0.7 + 5, y * 0.7, z * 0.7, 3)));
  Result := Scl(Result, 1 + grain);
end;

function GenMetal(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  s, t, streak, env, F1, F2, id: Double;
begin
  s := G.P.Scale; t := G.P.Turbulence;
  env := 0.5 + 0.5 * Sin(y * 3 + x * 1.0 + t * 2 * G.N.FBM(x * 2, y * 2, z * 2, G.P.Octaves));
  Result := Mix(G.C2, G.C1, env);
  if G.P.Style = 0 then
  begin
    streak := G.N.Noise(x * 2, y * s * 120, z * 2) * 0.5 +
              G.N.Noise(x * 5 + 3, y * s * 400, z * 5) * 0.3 +
              G.N.Noise(x * 9 + 9, y * s * 900, z * 9) * 0.2;
    Result := Scl(Result, 0.9 + 0.25 * streak);
  end
  else
  begin
    G.N.Worley(x * s * 6, y * s * 6, z * s * 6, F1, F2, id);
    Result := Scl(Result, 0.72 + 0.5 * SmoothStep(0, 0.7, F1) + 0.06 * (id - 0.5));
  end;
  Result := Mix(Result, G.C3, SmoothStep(0.85, 1.0, env) * 0.6);
end;

function GenGlass(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  s, t, ba, best, d, w, th, inten, band, F1, F2, id, bub: Double;
  k, nv, bestK: Integer;
  vc: TCol;
begin
  s := G.P.Scale; t := G.P.Turbulence; ba := G.P.BaseAlpha;
  Result := G.C1;
  Result := Scl(Result, 0.95 + 0.1 * G.N.Noise(x * 3, y * 3, z * 3));
  Result.a := ba;
  case G.P.Style of
    0: { cat's eye: thin twisted vanes through the centre }
      begin
        nv := EnsureRange(Round(s * 2), 1, 12);
        best := 0; bestK := 0;
        for k := 0 to nv - 1 do
        begin
          th := k * Pi / nv + t * y * Pi * 0.75;
          d := Cos(lat) * Abs(Sin(lon - th));
          w := 0.07 * (1 + 0.5 * G.N.Noise(x * 6 + k, y * 6, z * 6));
          inten := 1 - SmoothStep(w * 0.55, w, d);
          if inten > best then
          begin
            best := inten;
            bestK := k;
          end;
        end;
        if bestK mod 2 = 0 then vc := G.C2 else vc := G.C3;
        vc.a := 1;
        Result := Mix(Result, vc, best);
      end;
    1: { swirl }
      begin
        band := Sin(lon * 3 + y * t * 4 + 4 * G.N.FBM(x * s, y * s, z * s, G.P.Octaves));
        inten := SmoothStep(0.45, 0.75, band);
        if G.N.Noise(x * 1.3 + 40, y * 1.3, z * 1.3) > 0 then vc := G.C2 else vc := G.C3;
        vc.a := 0.95;
        Result := Mix(Result, vc, inten);
      end;
  end;
  { tiny air bubbles }
  G.N.Worley(x * 9 + 100, y * 9, z * 9, F1, F2, id);
  if id > 0.82 then
  begin
    bub := 1 - SmoothStep(0.06, 0.12, F1);
    if (G.P.Style = 2) or (id > 0.9) then
      Result := Mix(Result, Col(1, 1, 1, 0.7), bub * 0.8);
  end;
end;

function GenCartoon(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
const
  OW = 0.07;
var
  s, t, f, local, edge, d, best, dd: Double;
  n, band, i: Integer;
  fill: TCol;
begin
  s := G.P.Scale; t := G.P.Turbulence;
  n := Max(1, Round(s * 4));
  case G.P.Style of
    0, 2, 3:
      begin
        if G.P.Style = 0 then
          f := (lat / Pi + 0.5) * n + t * 0.3 * Sin(lon * 3)
        else if G.P.Style = 2 then
          f := (lon / (2 * Pi) + 0.5) * n + (lat / Pi) * n * (1 + t * 2)
        else
          f := 0;
        if G.P.Style = 3 then
        begin
          f := (lon / (2 * Pi) + 0.5) * n * 2;
          d := (lat / Pi + 0.5) * n;
          band := FastFloor(f) + FastFloor(d);
          local := Min(Min(Fract(f), 1 - Fract(f)), Min(Fract(d), 1 - Fract(d)));
        end
        else
        begin
          band := FastFloor(f);
          local := Min(Fract(f), 1 - Fract(f));
        end;
        if (band and 1) = 0 then fill := G.C1 else fill := G.C2;
        edge := SmoothStep(OW * 0.5, OW, local);
        Result := Mix(G.C3, fill, edge);
      end;
  else
    { polka dots, evenly spread with a Fibonacci lattice }
    best := 1e9;
    for i := 0 to High(G.Dots) do
    begin
      dd := Sqr(x - G.Dots[i][0]) + Sqr(y - G.Dots[i][1]) + Sqr(z - G.Dots[i][2]);
      if dd < best then best := dd;
    end;
    d := Sqrt(best) / G.DotR;   { 1.0 = dot rim }
    if d < 1 then fill := G.C2 else fill := G.C1;
    edge := SmoothStep(0.06, 0.13, Abs(d - 1));
    Result := Mix(G.C3, fill, edge);
  end;
end;

function GenGlobe(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  s, t, h, sea, e, moist, ice, cl, band: Double;
  qx, qy, qz: Double;
  sand, rock, snow, deep, shallow: TCol;
begin
  s := G.P.Scale; t := G.P.Turbulence;
  qx := x * s + 3.1; qy := y * s + 1.7; qz := z * s + 5.3;
  snow := Col(0.97, 0.98, 1.0);
  rock := Col(0.45, 0.40, 0.36);
  sand := Col(0.82, 0.72, 0.48);
  case G.P.Style of
    0: { Earth-like }
      begin
        h := G.N.FBM(qx, qy, qz, G.P.Octaves) * 1.4;
        sea := 0.02;
        if h < sea then
        begin
          shallow := Mix(G.C1, Col(0.4, 0.8, 0.9), 0.35);
          deep := Scl(G.C1, 0.45);
          Result := Mix(shallow, deep, SmoothStep(0, 0.35, sea - h));
        end
        else
        begin
          e := h - sea;
          moist := G.N.FBM(qx * 2 + 50, qy * 2, qz * 2, 4);
          Result := Mix(G.C2, sand, SmoothStep(0.0, -0.25, moist) * (1 - Abs(lat) / (Pi / 2)));
          Result := Mix(Result, rock, SmoothStep(0.15, 0.35, e));
          Result := Mix(Result, snow, SmoothStep(0.4, 0.5, e));
        end;
        ice := SmoothStep(1.15, 1.25, Abs(lat) + 0.12 * G.N.Noise(qx * 3, qy * 3, qz * 3));
        Result := Mix(Result, G.C3, ice);
        if t > 0 then
        begin
          cl := G.N.FBM(qx * 2.5 + 100, qy * 4, qz * 2.5, G.P.Octaves);
          Result := Mix(Result, Col(1, 1, 1), SmoothStep(0.05, 0.45, cl) * Clamp01(t * 0.5));
        end;
      end;
    1: { desert planet }
      begin
        h := G.N.FBM(qx, qy, qz, G.P.Octaves);
        Result := Mix(G.C2, Scl(G.C2, 0.7), 0.5 + 0.5 * Sin((qx + qz) * 12 + 6 * h * t));
        Result := Mix(Result, G.C3, SmoothStep(0.2, 0.4, h));
        Result := Mix(Result, G.C1, SmoothStep(-0.3, -0.38, h));
        ice := SmoothStep(1.3, 1.4, Abs(lat) + 0.1 * G.N.Noise(qx * 3, qy * 3, qz * 3));
        Result := Mix(Result, snow, ice * 0.8);
      end;
  else
    { gas giant bands }
    band := y * s * 3 + t * 0.4 * G.N.FBM(qx * 1.5, qy * 4, qz * 1.5, G.P.Octaves);
    h := 0.5 + 0.5 * Sin(band * Pi * 2);
    if h < 0.5 then Result := Mix(G.C1, G.C2, h * 2)
    else Result := Mix(G.C2, G.C3, (h - 0.5) * 2);
    Result := Scl(Result, 0.9 + 0.15 * G.N.Noise(qx * 6, qy * 20, qz * 6));
  end;
end;

function GenGrid(var G: TGenCtx; u, v: Double): TCol;
var
  n, cu, cv: Integer;
  fu, fv, lw, line: Double;
  base: TCol;
begin
  n := Max(1, Round(G.P.Scale * 8));
  fu := u * n * 2; fv := v * n;
  cu := FastFloor(fu); cv := FastFloor(fv);
  base := Mix(Hue(u), G.C1, 0.55);
  if ((cu + cv) and 1) = 1 then base := Mix(base, G.C2, 0.5);
  lw := 0.04;
  line := Min(Min(Fract(fu), 1 - Fract(fu)), Min(Fract(fv), 1 - Fract(fv)));
  Result := Mix(G.C3, base, SmoothStep(lw * 0.5, lw, line));
  if Abs(v - 0.5) < 0.004 then Result := Col(1, 0, 0);       { equator }
  if Abs(u - 0.5) < 0.002 then Result := Col(1, 1, 1);       { front meridian }
end;

procedure GenerateTexture(const P: TTexParams; var B: TPixelBuf; Progress: TProgressProc);
var
  G: TGenCtx;
  ix, iy, i, nd: Integer;
  u, v, lon, lat, cl, sl, x, y, z, gold, th, r: Double;
  SinLon, CosLon: array of Double;
  C: TCol;
begin
  BufInit(B, Max(8, P.Width), Max(4, P.Height));
  G.P := P;
  G.N.Init(P.Seed);
  G.C1 := ColFromTColor(P.Color1);
  G.C2 := ColFromTColor(P.Color2);
  G.C3 := ColFromTColor(P.Color3);

  if (P.Kind = tkCartoon) and (P.Style = 1) then
  begin
    nd := EnsureRange(Round(P.Scale * 12), 4, 400);
    SetLength(G.Dots, nd);
    gold := Pi * (3 - Sqrt(5));
    for i := 0 to nd - 1 do
    begin
      y := 1 - (i + 0.5) / nd * 2;
      r := Sqrt(1 - y * y);
      th := gold * i + P.Seed * 0.37;
      G.Dots[i][0] := Cos(th) * r;
      G.Dots[i][1] := y;
      G.Dots[i][2] := Sin(th) * r;
    end;
    G.DotR := Sqrt(4 / nd) * 0.55;
  end;

  SetLength(SinLon, B.W);
  SetLength(CosLon, B.W);
  for ix := 0 to B.W - 1 do
  begin
    lon := ((ix + 0.5) / B.W) * 2 * Pi - Pi;
    SinLon[ix] := Sin(lon);
    CosLon[ix] := Cos(lon);
  end;

  for iy := 0 to B.H - 1 do
  begin
    v := (iy + 0.5) / B.H;
    lat := (0.5 - v) * Pi;
    sl := Sin(lat);
    cl := Cos(lat);
    for ix := 0 to B.W - 1 do
    begin
      u := (ix + 0.5) / B.W;
      lon := u * 2 * Pi - Pi;
      x := cl * SinLon[ix];
      y := sl;
      z := cl * CosLon[ix];
      case P.Kind of
        tkMarble : C := GenMarble(G, x, y, z, lon, lat);
        tkGranite: C := GenGranite(G, x, y, z, lon, lat);
        tkWood   : C := GenWood(G, x, y, z, lon, lat);
        tkMetal  : C := GenMetal(G, x, y, z, lon, lat);
        tkGlass  : C := GenGlass(G, x, y, z, lon, lat);
        tkCartoon: C := GenCartoon(G, x, y, z, lon, lat);
        tkGlobe  : C := GenGlobe(G, x, y, z, lon, lat);
      else
        C := GenGrid(G, u, v);
      end;
      if P.Kind <> tkGlass then C.a := C.a * P.BaseAlpha;
      B.Data[iy * B.W + ix] := PackCol(C);
    end;
    if Assigned(Progress) and ((iy and 31) = 0) then
      Progress(iy * 100 div B.H);
  end;
  if Assigned(Progress) then Progress(100);
end;

end.
