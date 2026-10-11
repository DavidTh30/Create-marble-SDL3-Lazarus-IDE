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
  TTexKind = (tkMarble, tkGranite, tkWood, tkMetal, tkGlass, tkCartoon, tkGlobe,
              tkLava, tkGem, tkSpace, tkAnimal, tkCamo, tkSport, tkIrid, tkBricks,
              tkFabric, tkGradient, tkGrid);

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
    'Glass', 'Cartoon', 'Globe / Planet',
    'Lava / Magma', 'Gemstone', 'Space / Nebula', 'Animal print', 'Camouflage',
    'Sports ball', 'Opal / Pearl / Iridescent', 'Bricks & tiles', 'Fabric',
    'Gradient / Rainbow', 'UV test grid');

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
    tkMetal  : Result := TStringArray.Create('Brushed', 'Hammered', 'Rusted', 'Copper patina');
    tkGlass  : Result := TStringArray.Create('Cat''s eye', 'Swirl', 'Clear with bubbles');
    tkCartoon: Result := TStringArray.Create('Stripes', 'Polka dots', 'Spiral', 'Checker');
    tkGlobe  : Result := TStringArray.Create('Earth-like', 'Desert planet', 'Gas giant', 'Moon (craters)', 'Ice planet');
    tkLava   : Result := TStringArray.Create('Cracked crust', 'Flowing magma');
    tkGem    : Result := TStringArray.Create('Faceted gem', 'Agate bands', 'Amethyst crystals');
    tkSpace  : Result := TStringArray.Create('Nebula', 'Starfield', 'Galaxy band');
    tkAnimal : Result := TStringArray.Create('Leopard', 'Zebra', 'Tiger', 'Giraffe', 'Cow');
    tkCamo   : Result := TStringArray.Create('Woodland', 'Digital (pixel)', 'Desert');
    tkSport  : Result := TStringArray.Create('Soccer ball', 'Basketball', 'Tennis ball', 'Baseball',
                                             'Billiard (solid)', 'Billiard (stripe)', 'Beach ball');
    tkIrid   : Result := TStringArray.Create('Opal', 'Pearl', 'Soap bubble', 'Holographic');
    tkBricks : Result := TStringArray.Create('Bricks', 'Tiles', 'Mosaic');
    tkFabric : Result := TStringArray.Create('Tartan / plaid', 'Denim', 'Gingham');
    tkGradient: Result := TStringArray.Create('Rainbow (vertical)', 'Rainbow (horizontal)', '3-colour gradient', 'Sunburst');
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
    tkLava:
      begin
        P.Color1 := RGBc(40, 30, 28); P.Color2 := RGBc(230, 70, 10); P.Color3 := RGBc(255, 220, 60);
        P.Scale := 1.5; P.Turbulence := 1.0;
      end;
    tkGem:
      begin
        P.Scale := 1.5; P.Turbulence := 1.0; P.BaseAlpha := 0.9;
      end;
    tkSpace, tkAnimal, tkCamo, tkIrid:
      begin
        P.Scale := 1.5; P.Turbulence := 1.0;
      end;
    tkSport, tkBricks, tkFabric:
      begin
        P.Scale := 1.0; P.Turbulence := 1.0;
      end;
    tkGradient:
      begin
        P.Color1 := RGBc(255, 80, 80); P.Color2 := RGBc(80, 200, 255); P.Color3 := RGBc(255, 230, 90);
        P.Scale := 1.0; P.Turbulence := 0;
      end;
  end;
  P.Style := 0;
  ApplyStyleColors(P);
end;

{ Some styles need their own palette. Returns True if colors changed. }
function ApplyStyleColors(var P: TTexParams): Boolean;

  procedure Pal(c1, c2, c3: LongWord);
  begin
    P.Color1 := c1; P.Color2 := c2; P.Color3 := c3;
  end;

begin
  Result := True;
  case P.Kind of
    tkMetal:
      case P.Style of
        0, 1: Pal(RGBc(225, 228, 232), RGBc(95, 100, 110), RGBc(255, 255, 255));
        2: Pal(RGBc(165, 165, 170), RGBc(100, 40, 20), RGBc(185, 95, 40));
        3: Pal(RGBc(190, 110, 60), RGBc(70, 160, 130), RGBc(130, 205, 175));
      end;
    tkGlobe:
      case P.Style of
        0: Pal(RGBc(30, 80, 160), RGBc(70, 140, 60), RGBc(245, 250, 255));
        1: Pal(RGBc(60, 110, 140), RGBc(205, 135, 75), RGBc(120, 70, 50));
        2: Pal(RGBc(120, 80, 50), RGBc(225, 190, 140), RGBc(250, 240, 225));
        3: Pal(RGBc(95, 95, 100), RGBc(170, 168, 165), RGBc(230, 228, 225));
        4: Pal(RGBc(60, 120, 170), RGBc(200, 225, 240), RGBc(250, 252, 255));
      end;
    tkGem:
      case P.Style of
        0: Pal(RGBc(30, 90, 200), RGBc(60, 160, 240), RGBc(230, 245, 255));
        1: Pal(RGBc(150, 60, 40), RGBc(230, 190, 150), RGBc(90, 50, 80));
        2: Pal(RGBc(90, 30, 120), RGBc(210, 170, 240), RGBc(250, 240, 255));
      end;
    tkSpace:
      case P.Style of
        0: Pal(RGBc(200, 40, 120), RGBc(40, 90, 220), RGBc(255, 250, 235));
        1: Pal(RGBc(60, 80, 160), RGBc(120, 60, 140), RGBc(255, 255, 255));
        2: Pal(RGBc(120, 140, 220), RGBc(230, 190, 150), RGBc(255, 240, 210));
      end;
    tkAnimal:
      case P.Style of
        0: Pal(RGBc(215, 160, 80), RGBc(35, 25, 15), RGBc(160, 100, 45));
        1: Pal(RGBc(240, 238, 230), RGBc(20, 20, 20), RGBc(240, 238, 230));
        2: Pal(RGBc(225, 120, 30), RGBc(20, 15, 10), RGBc(245, 240, 225));
        3: Pal(RGBc(240, 225, 190), RGBc(165, 95, 40), RGBc(240, 225, 190));
        4: Pal(RGBc(245, 245, 240), RGBc(25, 25, 25), RGBc(245, 245, 240));
      end;
    tkCamo:
      case P.Style of
        0: Pal(RGBc(85, 95, 55), RGBc(120, 100, 60), RGBc(45, 60, 35));
        1: Pal(RGBc(150, 155, 150), RGBc(100, 105, 100), RGBc(60, 65, 62));
        2: Pal(RGBc(200, 175, 130), RGBc(165, 135, 95), RGBc(120, 95, 65));
      end;
    tkSport:
      case P.Style of
        0: Pal(RGBc(245, 245, 245), RGBc(25, 25, 30), RGBc(90, 90, 90));
        1: Pal(RGBc(210, 100, 35), RGBc(20, 15, 15), RGBc(20, 15, 15));
        2: Pal(RGBc(205, 225, 60), RGBc(175, 200, 45), RGBc(250, 250, 245));
        3: Pal(RGBc(245, 240, 230), RGBc(200, 30, 30), RGBc(200, 30, 30));
        4: Pal(RGBc(250, 250, 245), RGBc(200, 30, 30), RGBc(0, 0, 0));
        5: Pal(RGBc(250, 250, 245), RGBc(240, 180, 20), RGBc(0, 0, 0));
        6: Pal(RGBc(230, 40, 40), RGBc(30, 90, 210), RGBc(250, 210, 30));
      end;
    tkIrid:
      case P.Style of
        0: Pal(RGBc(235, 240, 245), RGBc(180, 210, 230), RGBc(255, 255, 255));
        1: Pal(RGBc(245, 238, 225), RGBc(230, 220, 210), RGBc(255, 255, 255));
        2: Pal(RGBc(230, 240, 255), RGBc(200, 220, 255), RGBc(255, 255, 255));
        3: Pal(RGBc(200, 200, 210), RGBc(150, 150, 160), RGBc(255, 255, 255));
      end;
    tkBricks:
      case P.Style of
        0: Pal(RGBc(170, 70, 50), RGBc(120, 45, 35), RGBc(205, 200, 190));
        1: Pal(RGBc(240, 240, 235), RGBc(40, 90, 150), RGBc(180, 180, 175));
        2: Pal(RGBc(30, 120, 180), RGBc(240, 200, 60), RGBc(235, 230, 220));
      end;
    tkFabric:
      case P.Style of
        0: Pal(RGBc(30, 70, 40), RGBc(20, 30, 80), RGBc(200, 30, 30));
        1: Pal(RGBc(40, 65, 120), RGBc(120, 150, 190), RGBc(230, 235, 240));
        2: Pal(RGBc(250, 250, 250), RGBc(200, 30, 40), RGBc(200, 30, 40));
      end;
  else
    Result := False;
  end;
end;

{ ---------- generators ---------- }

type
  TGenCtx = record
    N: TPerlin;
    P: TTexParams;
    C1, C2, C3: TCol;
    Dots: array of array[0..2] of Double;
    DotR: Double;
    Ctr: array of array[0..2] of Double;   { soccer ball panel centres }
    U, V: Double;                          { texture coords of the current texel }
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
  if G.P.Style >= 2 then
  begin
    streak := G.N.Noise(x * 2, y * s * 120, z * 2) * 0.5 + G.N.Noise(x * 5 + 3, y * s * 400, z * 5) * 0.3;
    Result := Scl(G.C1, (0.75 + 0.3 * env) * (0.9 + 0.2 * streak));
    if G.P.Style = 2 then
    begin
      { rust patches with speckled edges }
      F1 := G.N.FBM(x * s * 2 + 30, y * s * 2, z * s * 2, G.P.Octaves) + (t - 1) * 0.15
            + 0.12 * G.N.Noise(x * 25, y * 25, z * 25);
      id := 0.5 + 0.5 * G.N.Noise(x * 30 + 7, y * 30, z * 30);
      Result := Mix(Result, Scl(Mix(G.C2, G.C3, id), 0.8 + 0.3 * (0.5 + 0.5 * G.N.FBM(x * 8, y * 8, z * 8, 4))),
        SmoothStep(-0.05, 0.12, F1));
    end
    else
    begin
      { copper with green verdigris, streaking downwards }
      F1 := G.N.FBM(x * s * 2 + 60, y * s * 0.7, z * s * 2, G.P.Octaves) + (t - 1) * 0.15;
      id := 0.5 + 0.5 * G.N.Noise(x * 12, y * 12, z * 12);
      Result := Mix(Result, Mix(G.C2, G.C3, id), SmoothStep(-0.1, 0.15, F1));
    end;
    Exit;
  end;
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
  s, t, h, sea, e, moist, ice, cl, band, f: Double;
  k: Integer;
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
    3: { cratered moon }
      begin
        Result := Scl(G.C2, 0.75 + 0.35 * (0.5 + 0.5 * G.N.FBM(qx * 2, qy * 2, qz * 2, G.P.Octaves)));
        Result := Mix(Result, G.C1, SmoothStep(0.05, 0.25, G.N.FBM(qx * 0.6 + 40, qy * 0.6, qz * 0.6, 4)) * 0.8);
        for k := 0 to 2 do
        begin
          f := s * 2.5 * Power(2.2, k);
          G.N.Worley(x * f + k * 17, y * f, z * f, e, moist, cl);
          if cl > 0.55 then
          begin
            band := e / (0.18 + 0.2 * Fract(cl * 5.3));
            if band < 1.4 then
            begin
              Result := Scl(Result, 1 - 0.3 * (1 - SmoothStep(0.0, 1.0, band)));
              Result := Mix(Result, G.C3, 0.45 * (1 - SmoothStep(0.0, 0.18, Abs(band - 1))));
            end;
          end;
        end;
      end;
    4: { ice planet with cracks }
      begin
        G.N.Worley(qx * 2, qy * 2, qz * 2, e, moist, cl);
        Result := Mix(G.C2, G.C3, 0.5 + 0.5 * G.N.FBM(qx * 1.5, qy * 1.5, qz * 1.5, G.P.Octaves));
        Result := Mix(Result, G.C1, (1 - SmoothStep(0.0, 0.03 + 0.02 * t, moist - e)) * 0.8);
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

{ ---------- additional materials ---------- }

function CellRand(var G: TGenCtx; a, b: Integer): Double;
begin
  Result := G.N.Perm[(G.N.Perm[a and 255] + (b and 255)) and 255] / 255;
end;

function Ramp3(const A, B, C: TCol; t: Double): TCol;
begin
  t := Clamp01(t);
  if t < 0.5 then Result := Mix(A, B, t * 2) else Result := Mix(B, C, (t - 0.5) * 2);
end;

function GenLava(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  s, t, n, w, F1, F2, id, crack, heat, qx, qy, qz: Double;
begin
  s := G.P.Scale; t := G.P.Turbulence;
  qx := x * s * 2; qy := y * s * 2; qz := z * s * 2;
  n := G.N.FBM(qx * 1.5 + 7, qy * 1.5, qz * 1.5, G.P.Octaves);
  if G.P.Style = 0 then
  begin
    { cooled crust broken by glowing cracks }
    w := t * 0.25 * n;
    G.N.Worley(qx + w, qy + w, qz - w, F1, F2, id);
    crack := 1 - SmoothStep(0.0, 0.05 + 0.05 * (0.5 + 0.5 * n), F2 - F1);
    Result := Scl(G.C1, 0.6 + 0.6 * (0.5 + 0.5 * G.N.FBM(qx * 4, qy * 4, qz * 4, G.P.Octaves)));
    Result := Mix(Result, G.C2, 0.3 * (1 - SmoothStep(0.0, 0.25, F2 - F1)));
    Result := Mix(Result, Mix(G.C2, G.C3, crack * crack), crack);
  end
  else
  begin
    { flowing magma: domain-warped heat field }
    heat := 0.5 + 0.5 * G.N.FBM(qx + t * n, qy + t * n * 0.7, qz - t * n, G.P.Octaves);
    heat := Clamp01((heat - 0.35) * 2.2);
    if heat < 0.4 then
      Result := Mix(Scl(G.C1, 0.6), G.C1, heat / 0.4)
    else
      Result := Ramp3(G.C1, G.C2, G.C3, (heat - 0.4) / 0.6);
  end;
end;

function GenGem(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  s, t, F1, F2, id, n, band, qx, qy, qz: Double;
begin
  s := G.P.Scale; t := G.P.Turbulence;
  qx := x * s * 2; qy := y * s * 2; qz := z * s * 2;
  case G.P.Style of
    0: { faceted gem: every Voronoi cell is a flat facet }
      begin
        G.N.Worley(qx, qy, qz, F1, F2, id);
        Result := Scl(G.C1, 0.45 + 0.9 * id);
        Result := Mix(Result, G.C2, Clamp01((id - 0.6) * 1.5));
        Result := Mix(G.C3, Result, SmoothStep(0.01, 0.04, F2 - F1));
        if id > 0.94 then Result := Mix(Result, Col(1, 1, 1), 0.7);
      end;
    1: { agate: wavy concentric bands }
      begin
        { low-detail warp keeps the bands smooth and continuous }
        n := G.N.FBM(qx * 0.35, qy * 0.35, qz * 0.35, Min(3, G.P.Octaves));
        band := n * (1.0 + t * 0.6) + y * 0.35 + 0.08 * G.N.Noise(qx * 1.5, qy * 1.5, qz * 1.5);
        Result := Ramp3(G.C1, G.C2, G.C3, 0.5 + 0.5 * Sin(band * 4 * Pi));
        { thin bright layers between the coloured bands }
        Result := Mix(Result, Col(1, 1, 1), 0.6 * (1 - SmoothStep(0.0, 0.04, Abs(Fract(band * 3) - 0.5))));
        Result := Scl(Result, 0.95 + 0.06 * G.N.Noise(qx * 12, qy * 12, qz * 12));
      end;
  else { amethyst crystals }
    G.N.Worley(qx * 2, qy * 2, qz * 2, F1, F2, id);
    Result := Mix(G.C1, G.C2, SmoothStep(0.0, 0.8, F1));
    Result := Scl(Result, 0.8 + 0.4 * id);
    Result := Mix(G.C3, Result, SmoothStep(0.0, 0.05, F2 - F1));
    if (id > 0.9) and (F1 < 0.15) then Result := Mix(Result, Col(1, 1, 1), 0.8);
  end;
end;

function Stars(var G: TGenCtx; x, y, z: Double): Double;
var
  F1, F2, id: Double;
begin
  Result := 0;
  G.N.Worley(x * 30 + 300, y * 30, z * 30, F1, F2, id);
  if id > 0.45 then Result := (1 - SmoothStep(0.0, 0.2, F1)) * (id - 0.2) * 1.4;
  G.N.Worley(x * 12 + 500, y * 12, z * 12, F1, F2, id);
  if id > 0.88 then Result := Max(Result, 1 - SmoothStep(0.0, 0.13, F1));
end;

function GenSpace(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  s, t, n, d, c, core, dust, qx, qy, qz: Double;
  bg: TCol;
begin
  s := G.P.Scale; t := G.P.Turbulence;
  qx := x * s + 1.3; qy := y * s + 2.1; qz := z * s + 0.7;
  bg := Col(0.01, 0.01, 0.03);
  n := G.N.FBM(qx + t * 0.5 * G.N.Noise(qx * 2, qy * 2, qz * 2), qy, qz, G.P.Octaves);
  case G.P.Style of
    0: { nebula }
      begin
        d := SmoothStep(-0.15, 0.55, n);
        c := 0.5 + 0.5 * G.N.FBM(qx * 2 + 9, qy * 2, qz * 2, 4);
        Result := Mix(bg, Mix(G.C1, G.C2, c), d);
        Result := Mix(Result, Col(1, 1, 1), 0.25 * SmoothStep(0.45, 0.8, n));
      end;
    1: { starfield with faint glow }
      Result := Mix(bg, Mix(G.C1, G.C2, 0.5 + 0.5 * n), 0.45 * SmoothStep(-0.1, 0.6, n));
  else { galaxy band }
    d := Exp(-Sqr(y / (0.2 + 0.08 * G.N.Noise(qx * 2, qy * 2, qz * 2))));
    c := 0.5 + 0.5 * G.N.FBM(qx * 2, qy * 2, qz * 2, G.P.Octaves);
    core := Exp(-Sqr(lon / 0.6)) * Exp(-Sqr(y / 0.12));
    dust := SmoothStep(0.05, 0.4, G.N.FBM(qx * 3 + 40, qy * 6, qz * 3, G.P.Octaves)) * Exp(-Sqr(y / 0.07));
    Result := Mix(bg, Mix(G.C1, G.C2, c), Clamp01(d * (0.35 + 0.8 * c)));
    Result := Mix(Result, G.C3, core * 0.9);
    Result := Scl(Result, 1 - Clamp01(0.4 * dust * (0.5 + t * 0.5)));
  end;
  Result := Mix(Result, G.C3, Clamp01(Stars(G, x, y, z)));
end;

function GenAnimal(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  s, t, w, F1, F2, id, r, inner, ring, f, taper, n, qx, qy, qz: Double;
begin
  s := G.P.Scale; t := G.P.Turbulence;
  qx := x * s * 3; qy := y * s * 3; qz := z * s * 3;
  w := t * 0.15 * G.N.FBM(qx * 2, qy * 2, qz * 2, 3);
  case G.P.Style of
    0: { leopard rosettes }
      begin
        G.N.Worley(qx + w, qy + w, qz + w, F1, F2, id);
        Result := Scl(G.C1, 0.9 + 0.15 * G.N.Noise(qx * 3, qy * 3, qz * 3));
        if id > 0.12 then
        begin
          r := 0.2 + 0.08 * id;
          inner := 1 - SmoothStep(r - 0.04, r, F1);
          ring := SmoothStep(r - 0.02, r + 0.02, F1) * (1 - SmoothStep(r + 0.08, r + 0.13, F1));
          ring := ring * SmoothStep(-0.25, 0.0, G.N.Noise(qx * 6 + id * 10, qy * 6, qz * 6));
          Result := Mix(Result, G.C3, inner);
          Result := Mix(Result, G.C2, ring);
        end;
      end;
    1: { zebra }
      begin
        f := Sin((x + y * 0.25 + z * 0.2) * s * 9 + t * 3 * G.N.FBM(qx * 0.5, qy * 0.5, qz * 0.5, G.P.Octaves));
        Result := Mix(G.C1, G.C2, SmoothStep(0.05, 0.2, f));
      end;
    2: { tiger }
      begin
        f := Sin(lon * Max(2, Round(s * 5)) + t * 2.5 * G.N.FBM(qx * 0.6, qy * 0.6, qz * 0.6, G.P.Octaves) + y * 2);
        taper := G.N.FBM(qx * 0.8 + 20, qy * 0.8, qz * 0.8, 3);
        Result := Mix(G.C1, G.C3, SmoothStep(-0.5, -0.85, y));
        Result := Mix(Result, G.C2, SmoothStep(0.55, 0.75, f + taper * 0.5));
      end;
    3: { giraffe patches }
      begin
        G.N.Worley(qx * 1.2 + w * 2, qy * 1.2 + w * 2, qz * 1.2, F1, F2, id);
        Result := Mix(G.C1, Scl(G.C2, 0.85 + 0.3 * id), SmoothStep(0.05, 0.1, F2 - F1));
      end;
  else { cow }
    n := G.N.FBM(qx * 0.4 + w, qy * 0.4, qz * 0.4, G.P.Octaves);
    Result := Mix(G.C1, G.C2, SmoothStep(0.1, 0.14, n));
  end;
end;

function CamoAt(var G: TGenCtx; x, y, z: Double): TCol;
var
  s, w, n1, n2, n3: Double;
begin
  s := G.P.Scale * 1.5;
  w := G.P.Turbulence * 0.3 * G.N.Noise(x * s * 4, y * s * 4, z * s * 4);
  n1 := G.N.FBM(x * s + 10 + w, y * s, z * s, G.P.Octaves);
  n2 := G.N.FBM(x * s + 50, y * s + w, z * s, G.P.Octaves);
  n3 := G.N.FBM(x * s * 1.4 + 90, y * s * 1.4, z * s * 1.4 + w, G.P.Octaves);
  Result := G.C1;
  Result := Mix(Result, G.C2, SmoothStep(0.01, 0.03, n1));
  Result := Mix(Result, G.C3, SmoothStep(0.09, 0.11, n2));
  Result := Mix(Result, Scl(G.C3, 0.45), SmoothStep(0.15, 0.17, n3));
end;

function GenCamo(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  nu, nv: Integer;
  qu, qv, lo, la: Double;
begin
  if G.P.Style = 1 then
  begin
    { digital camo: sample the pattern on a coarse pixel grid }
    nu := Max(16, Round(G.P.Scale * 48));
    nv := Max(8, nu div 2);
    qu := (FastFloor(G.U * nu) + 0.5) / nu;
    qv := (FastFloor(G.V * nv) + 0.5) / nv;
    lo := qu * 2 * Pi - Pi;
    la := (0.5 - qv) * Pi;
    x := Cos(la) * Sin(lo); y := Sin(la); z := Cos(la) * Cos(lo);
  end;
  Result := CamoAt(G, x, y, z);
end;

{ approx. distance (radians) to the tennis/baseball seam curve lat = A*sin(2*lon) }
function SeamDist(lon, lat: Double): Double;
const
  A = 0.9;
var
  dl, slope: Double;
begin
  dl := lat - A * Sin(2 * lon);
  slope := 2 * A * Cos(2 * lon) / Max(0.2, Cos(lat));
  Result := Abs(dl) / Sqrt(1 + slope * slope);
end;

function GenSport(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  i, g6: Integer;
  d, best, second, cmin, ca, w, fu: Double;
  bestPent: Boolean;
  fill: TCol;
begin
  case G.P.Style of
    0: { soccer ball: truncated icosahedron }
      begin
        best := 1e9; second := 1e9; bestPent := False;
        for i := 0 to High(G.Ctr) do
        begin
          d := ArcCos(EnsureRange(x * G.Ctr[i][0] + y * G.Ctr[i][1] + z * G.Ctr[i][2], -1.0, 1.0));
          if i >= 12 then d := d - 0.0747;   { hexagons are wider than pentagons }
          if d < best then
          begin
            second := best;
            best := d;
            bestPent := i < 12;
          end
          else if d < second then
            second := d;
        end;
        if bestPent then fill := G.C2 else fill := G.C1;
        Result := Mix(G.C3, fill, SmoothStep(0.006, 0.014, second - best));
      end;
    1: { basketball }
      begin
        w := 0.018;
        d := Min(Abs(y), Abs(x));
        d := Min(d, Abs(Abs(z) - 0.62 - 0.3 * y * y) * 0.8);
        fill := Scl(G.C1, 0.92 + 0.08 * G.N.Noise(x * 150, y * 150, z * 150));
        Result := Mix(G.C2, fill, SmoothStep(w * 0.6, w, d));
      end;
    2: { tennis ball }
      begin
        d := SeamDist(lon, lat);
        fill := Mix(G.C1, G.C2, 0.5 + 0.5 * G.N.FBM(x * 40, y * 40, z * 40, 3));
        Result := Mix(G.C3, fill, SmoothStep(0.025, 0.035, d));
      end;
    3: { baseball: leather, seam and red stitches }
      begin
        d := SeamDist(lon, lat);
        Result := Scl(G.C1, 0.95 + 0.05 * G.N.Noise(x * 20, y * 20, z * 20));
        Result := Mix(Scl(G.C1, 0.8), Result, SmoothStep(0.004, 0.008, d));
        if (Abs(d - 0.04) < 0.014) and (Sin(lon * 120) > 0.1) then
          Result := G.C2;
      end;
    4, 5: { billiard ball: solid or striped, white circle front and back }
      begin
        if (G.P.Style = 5) and (Abs(y) > 0.5) then fill := G.C1 else fill := G.C2;
        ca := ArcCos(EnsureRange(z, -1.0, 1.0));
        cmin := Min(ca, Pi - ca);
        Result := Mix(G.C1, fill, SmoothStep(0.32, 0.34, cmin));
      end;
  else { beach ball: 6 gores + white caps }
    fu := (lon / (2 * Pi) + 0.5) * 6;
    g6 := FastFloor(fu) mod 6;
    case g6 of
      0: fill := G.C1;
      2: fill := G.C2;
      4: fill := G.C3;
    else
      fill := Col(1, 1, 1);
    end;
    fu := Fract(fu);
    d := Min(fu, 1 - fu) * (2 * Pi / 6) * Cos(lat);
    Result := Mix(Scl(fill, 0.6), fill, SmoothStep(0.002, 0.006, d));
    Result := Mix(Result, Col(1, 1, 1), SmoothStep(1.22, 1.25, Abs(lat)));
  end;
end;

function GenIrid(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  s, t, h, flash, F1, F2, id, qx, qy, qz: Double;
begin
  s := G.P.Scale; t := G.P.Turbulence;
  qx := x * s; qy := y * s; qz := z * s;
  case G.P.Style of
    0: { opal: milky base with spectral flashes }
      begin
        Result := Mix(G.C1, G.C2, 0.5 + 0.5 * G.N.FBM(qx * 1.5, qy * 1.5, qz * 1.5, G.P.Octaves));
        G.N.Worley(qx * 3, qy * 3, qz * 3, F1, F2, id);
        flash := SmoothStep(0.15, 0.6, G.N.Noise(qx * 4 + id * 20, qy * 4, qz * 4)) *
                 (0.4 + 0.6 * SmoothStep(0.0, 0.1, F2 - F1));
        Result := Mix(Result, Hue(id + 0.15 * G.N.Noise(qx * 8, qy * 8, qz * 8)),
          flash * 0.85 * Clamp01(0.3 + t * 0.35));
      end;
    1: { pearl: soft pastel sheen }
      begin
        h := 0.5 + 0.5 * G.N.FBM(qx * 1.2, qy * 1.2, qz * 1.2, G.P.Octaves);
        Result := Mix(G.C1, Hue(h * 0.6 + 0.75), 0.1 + 0.05 * t);
        Result := Scl(Result, 0.95 + 0.08 * G.N.Noise(qx * 3, qy * 3, qz * 3));
      end;
    2: { soap bubble: thin-film colours, mostly transparent }
      begin
        h := y * 0.8 + G.N.FBM(qx * 1.2, qy * 1.2, qz * 1.2, G.P.Octaves) * t * 1.2 + 0.2 * Sin(lon * 2);
        Result := Mix(Hue(h), G.C1, 0.35);
        Result.a := 0.25 + 0.35 * Abs(Sin(h * Pi * 2));
      end;
  else { holographic foil }
    h := (x * 2 + y * 3 + z) * s + G.N.FBM(qx * 2, qy * 2, qz * 2, G.P.Octaves) * t;
    Result := Mix(Hue(h), G.C1, 0.35);
    Result := Scl(Result, 0.9 + 0.2 * G.N.Noise(x * 80, y * 80, z * 80));
  end;
end;

function GenBricks(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  R, row, nb, colI: Integer;
  fv, ly, latc, fu, lx, mv, mu, edge, F1, F2, id, s: Double;
  tile: TCol;
begin
  s := G.P.Scale;
  if G.P.Style = 2 then
  begin
    { mosaic }
    G.N.Worley(x * s * 8, y * s * 8, z * s * 8, F1, F2, id);
    tile := Mix(G.C1, G.C2, Fract(id * 7.31));
    tile := Mix(tile, Hue(id * 3), 0.15 * G.P.Turbulence);
    tile := Scl(tile, 0.9 + 0.2 * Fract(id * 13.7));
    Exit(Mix(G.C3, tile, SmoothStep(0.03, 0.07, F2 - F1)));
  end;
  R := Max(2, Round(s * 12));
  fv := (lat / Pi + 0.5) * R;
  row := FastFloor(fv);
  ly := fv - row;
  latc := ((row + 0.5) / R - 0.5) * Pi;
  if G.P.Style = 0 then
    nb := Max(3, Round(R * Cos(latc)))       { bricks are 2:1 }
  else
    nb := Max(3, Round(2 * R * Cos(latc)));  { square tiles }
  fu := (lon / (2 * Pi) + 0.5) * nb;
  if (G.P.Style = 0) and Odd(row) then fu := fu + 0.5;
  colI := FastFloor(fu);
  lx := fu - colI;
  colI := colI mod nb;
  mv := 0.08;
  if G.P.Style = 0 then mu := 0.04 else mu := 0.08;
  edge := Min(Min(ly, 1 - ly) / mv, Min(lx, 1 - lx) / mu);
  if G.P.Style = 0 then
  begin
    tile := Mix(G.C1, G.C2, CellRand(G, row, colI));
    tile := Scl(tile, 0.85 + 0.25 * (0.5 + 0.5 * G.N.FBM(x * 30, y * 30, z * 30, G.P.Octaves)));
  end
  else
  begin
    if Odd(row + colI) then tile := G.C2 else tile := G.C1;
    tile := Scl(tile, 0.96 + 0.06 * G.N.Noise(x * 10, y * 10, z * 10));
  end;
  Result := Mix(G.C3, tile, SmoothStep(0.6, 1.0, edge));
end;

function Sett(var G: TGenCtx; t: Double): TCol;
var
  f: Double;
begin
  f := Fract(t);
  if f < 0.38 then Result := G.C1
  else if f < 0.5 then Result := G.C2
  else if f < 0.54 then Result := G.C3
  else if f < 0.66 then Result := G.C2
  else Result := Scl(G.C1, 0.55);
end;

function GenFabric(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  N: Integer;
  diag, wear: Double;
  twill, bu, bv: Boolean;
begin
  N := Max(1, Round(G.P.Scale * 6));
  { 2/2 twill at texel level gives a woven look }
  diag := G.U * G.P.Width + G.V * G.P.Height;
  twill := Fract(diag / 4) < 0.5;
  case G.P.Style of
    0: { tartan / plaid }
      begin
        if twill then Result := Sett(G, G.U * N * 2) else Result := Sett(G, G.V * N);
        Result := Scl(Result, 0.92 + 0.08 * G.N.Noise(x * 40, y * 40, z * 40));
      end;
    1: { denim }
      begin
        wear := 0.5 + 0.5 * G.N.FBM(x * G.P.Scale * 2, y * G.P.Scale * 2, z * G.P.Scale * 2, G.P.Octaves);
        Result := Mix(G.C1, G.C2, Clamp01(wear * 0.5 * G.P.Turbulence));
        Result := Scl(Result, 0.85 + 0.15 * Sin(diag * Pi / 2));
        if G.N.Noise(x * 200, y * 60, z * 200) > 0.45 then Result := Mix(Result, G.C3, 0.5);
      end;
  else { gingham }
    bu := Fract(G.U * N * 2) < 0.5;
    bv := Fract(G.V * N) < 0.5;
    if bu and bv then Result := G.C2
    else if bu or bv then Result := Mix(G.C1, G.C2, 0.5)
    else Result := G.C1;
    if twill then Result := Scl(Result, 0.95);
  end;
end;

function GenGradient(var G: TGenCtx; x, y, z, lon, lat: Double): TCol;
var
  n: Integer;
begin
  case G.P.Style of
    0: Result := Hue(G.V * 0.85);
    1: Result := Hue(G.U);
    2: Result := Ramp3(G.C1, G.C2, G.C3, G.V);
  else { sunburst seen from the front }
    n := Max(2, Round(G.P.Scale * 6));
    if Fract(ArcTan2(y, x) / (2 * Pi) * n + G.P.Turbulence * 0.05 * z) < 0.5 then
      Result := G.C1
    else
      Result := G.C2;
    Result := Mix(Result, G.C3, SmoothStep(0.94, 0.95, Abs(z)));
  end;
end;

{ 12 icosahedron vertices (pentagons) followed by 20 face centres (hexagons) }
procedure BuildSoccerCentres(var G: TGenCtx);
var
  V: array[0..11, 0..2] of Double;
  i, j, k, n: Integer;
  phi, len, sa, sb: Double;

  function D2(a, b: Integer): Double;
  begin
    Result := Sqr(V[a, 0] - V[b, 0]) + Sqr(V[a, 1] - V[b, 1]) + Sqr(V[a, 2] - V[b, 2]);
  end;

  procedure SetV(idx: Integer; a, b, c: Double);
  begin
    V[idx, 0] := a; V[idx, 1] := b; V[idx, 2] := c;
  end;

begin
  phi := (1 + Sqrt(5)) / 2;
  n := 0;
  for i := 0 to 3 do
  begin
    if (i and 1) = 0 then sa := 1 else sa := -1;
    if (i and 2) = 0 then sb := phi else sb := -phi;
    SetV(n, 0, sa, sb); Inc(n);
    SetV(n, sa, sb, 0); Inc(n);
    SetV(n, sb, 0, sa); Inc(n);
  end;
  SetLength(G.Ctr, 32);
  for i := 0 to 11 do
  begin
    len := Sqrt(Sqr(V[i, 0]) + Sqr(V[i, 1]) + Sqr(V[i, 2]));
    for k := 0 to 2 do G.Ctr[i][k] := V[i, k] / len;
  end;
  n := 12;
  { faces = vertex triples whose pairwise distance equals the edge length (2) }
  for i := 0 to 9 do
    for j := i + 1 to 10 do
      for k := j + 1 to 11 do
        if (n < 32) and (Abs(D2(i, j) - 4) < 0.01) and (Abs(D2(j, k) - 4) < 0.01) and (Abs(D2(i, k) - 4) < 0.01) then
        begin
          G.Ctr[n][0] := V[i, 0] + V[j, 0] + V[k, 0];
          G.Ctr[n][1] := V[i, 1] + V[j, 1] + V[k, 1];
          G.Ctr[n][2] := V[i, 2] + V[j, 2] + V[k, 2];
          len := Sqrt(Sqr(G.Ctr[n][0]) + Sqr(G.Ctr[n][1]) + Sqr(G.Ctr[n][2]));
          G.Ctr[n][0] := G.Ctr[n][0] / len;
          G.Ctr[n][1] := G.Ctr[n][1] / len;
          G.Ctr[n][2] := G.Ctr[n][2] / len;
          Inc(n);
        end;
  SetLength(G.Ctr, n);
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

  if (P.Kind = tkSport) and (P.Style = 0) then
    BuildSoccerCentres(G);

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
      G.U := u;
      G.V := v;
      case P.Kind of
        tkMarble : C := GenMarble(G, x, y, z, lon, lat);
        tkGranite: C := GenGranite(G, x, y, z, lon, lat);
        tkWood   : C := GenWood(G, x, y, z, lon, lat);
        tkMetal  : C := GenMetal(G, x, y, z, lon, lat);
        tkGlass  : C := GenGlass(G, x, y, z, lon, lat);
        tkCartoon: C := GenCartoon(G, x, y, z, lon, lat);
        tkGlobe  : C := GenGlobe(G, x, y, z, lon, lat);
        tkLava   : C := GenLava(G, x, y, z, lon, lat);
        tkGem    : C := GenGem(G, x, y, z, lon, lat);
        tkSpace  : C := GenSpace(G, x, y, z, lon, lat);
        tkAnimal : C := GenAnimal(G, x, y, z, lon, lat);
        tkCamo   : C := GenCamo(G, x, y, z, lon, lat);
        tkSport  : C := GenSport(G, x, y, z, lon, lat);
        tkIrid   : C := GenIrid(G, x, y, z, lon, lat);
        tkBricks : C := GenBricks(G, x, y, z, lon, lat);
        tkFabric : C := GenFabric(G, x, y, z, lon, lat);
        tkGradient: C := GenGradient(G, x, y, z, lon, lat);
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
