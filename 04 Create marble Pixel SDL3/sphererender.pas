unit SphereRender;

{ Software ray-cast renderer for a textured sphere.
  Output is ARGB with straight alpha; everything outside the sphere is
  fully transparent black ($00000000). }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, PixBuf;

type
  TSphereParams = record
    RotX, RotY, RotZ : Double;   { degrees }
    OffsetU, OffsetV : Double;   { texture shift, 0..1 = full turn / full height }
    TileU, TileV     : Integer;  { texture repeats }
    FlipU            : Boolean;
    Opacity          : Double;   { 0..1 overall sphere opacity }
    Lighting         : Boolean;
    Ambient          : Double;   { 0..1 }
    Specular         : Double;   { 0..1 }
    Shininess        : Double;   { 1..256 }
    Rim              : Double;   { 0..1 fresnel edge opacity boost }
    LightAz, LightEl : Double;   { degrees }
    ShowBack         : Boolean;  { show inner back surface through transparent parts }
    SizeFrac         : Double;   { sphere diameter relative to image, 0.1..1 }
    ToonSteps        : Integer;  { 0 = smooth lighting, >0 = cel-shaded light bands }
  end;

procedure DefaultSphereParams(out P: TSphereParams);
procedure RenderSphere(const Tex: TPixelBuf; const P: TSphereParams;
  W, H: Integer; var Dst: TPixelBuf; SuperSample: Integer = 1; HardEdge: Boolean = False);
function SphereRadius(const P: TSphereParams; W, H: Integer): Double;
function InsideSphere(const P: TSphereParams; W, H, X, Y: Integer): Boolean;

implementation

type
  TMat3 = array[0..2, 0..2] of Double;

procedure DefaultSphereParams(out P: TSphereParams);
begin
  P.RotX := 15; P.RotY := 0; P.RotZ := 0;
  P.OffsetU := 0; P.OffsetV := 0;
  P.TileU := 1; P.TileV := 1;
  P.FlipU := False;
  P.Opacity := 1;
  P.Lighting := True;
  P.Ambient := 0.35;
  P.Specular := 0.6;
  P.Shininess := 40;
  P.Rim := 0.3;
  P.LightAz := -35;
  P.LightEl := 35;
  P.ShowBack := True;
  P.SizeFrac := 0.96;
  P.ToonSteps := 0;
end;

function SphereRadius(const P: TSphereParams; W, H: Integer): Double;
begin
  Result := EnsureRange(P.SizeFrac, 0.05, 1) * Min(W, H) / 2;
end;

{ pixel-centre test used for hard-edged (pixel art) rendering }
function InsideSphere(const P: TSphereParams; W, H, X, Y: Integer): Boolean;
begin
  Result := Sqr(X + 0.5 - W / 2) + Sqr(Y + 0.5 - H / 2) <= Sqr(SphereRadius(P, W, H));
end;

function MatMul(const A, B: TMat3): TMat3;
var
  i, j, k: Integer;
begin
  for i := 0 to 2 do
    for j := 0 to 2 do
    begin
      Result[i, j] := 0;
      for k := 0 to 2 do
        Result[i, j] := Result[i, j] + A[i, k] * B[k, j];
    end;
end;

function RotMatrix(ax, ay, az: Double): TMat3;
var
  Rx, Ry, Rz: TMat3;
  c, s: Double;
begin
  FillChar(Rx, SizeOf(Rx), 0); FillChar(Ry, SizeOf(Ry), 0); FillChar(Rz, SizeOf(Rz), 0);
  c := Cos(DegToRad(ax)); s := Sin(DegToRad(ax));
  Rx[0, 0] := 1; Rx[1, 1] := c; Rx[1, 2] := -s; Rx[2, 1] := s; Rx[2, 2] := c;
  c := Cos(DegToRad(ay)); s := Sin(DegToRad(ay));
  Ry[1, 1] := 1; Ry[0, 0] := c; Ry[0, 2] := s; Ry[2, 0] := -s; Ry[2, 2] := c;
  c := Cos(DegToRad(az)); s := Sin(DegToRad(az));
  Rz[2, 2] := 1; Rz[0, 0] := c; Rz[0, 1] := -s; Rz[1, 0] := s; Rz[1, 1] := c;
  { object -> view = Rz * Ry * Rx (X applied first) }
  Result := MatMul(Rz, MatMul(Ry, Rx));
end;

type
  TRenderCtx = record
    Tex: ^TPixelBuf;
    P: TSphereParams;
    M: TMat3;                 { object -> view }
    Lx, Ly, Lz: Double;
    WrapV: Boolean;
  end;

{ Bilinear sample with premultiplied result. }
procedure SampleTex(const C: TRenderCtx; u, v: Double; out r, g, b, a: Double);
var
  T: ^TPixelBuf;
  fx, fy, tx, ty, w: Double;
  x0, y0, x1, y1, i, xs, ys: Integer;
  px: LongWord;
  pa: Double;
begin
  T := C.Tex;
  r := 0; g := 0; b := 0; a := 0;
  if (T^.W = 0) or (T^.H = 0) then Exit;
  fx := u * T^.W - 0.5;
  fy := v * T^.H - 0.5;
  x0 := Floor(fx); y0 := Floor(fy);
  tx := fx - x0; ty := fy - y0;
  x1 := x0 + 1; y1 := y0 + 1;
  for i := 0 to 3 do
  begin
    if (i and 1) = 0 then begin xs := x0; w := 1 - tx; end else begin xs := x1; w := tx; end;
    if (i and 2) = 0 then begin ys := y0; w := w * (1 - ty); end else begin ys := y1; w := w * ty; end;
    xs := xs mod T^.W; if xs < 0 then Inc(xs, T^.W);
    if C.WrapV then
    begin
      ys := ys mod T^.H; if ys < 0 then Inc(ys, T^.H);
    end
    else
      ys := EnsureRange(ys, 0, T^.H - 1);
    px := T^.Data[ys * T^.W + xs];
    pa := (px shr 24) / 255 * w;
    a := a + pa;
    r := r + ((px shr 16) and $FF) / 255 * pa;
    g := g + ((px shr 8) and $FF) / 255 * pa;
    b := b + (px and $FF) / 255 * pa;
  end;
end;

{ View-space point on the sphere -> texture (premultiplied). }
procedure SurfaceTex(const C: TRenderCtx; nx, ny, nz: Double; out r, g, b, a: Double);
var
  ox, oy, oz, u, v: Double;
begin
  { inverse rotation = transpose }
  ox := C.M[0, 0] * nx + C.M[1, 0] * ny + C.M[2, 0] * nz;
  oy := C.M[0, 1] * nx + C.M[1, 1] * ny + C.M[2, 1] * nz;
  oz := C.M[0, 2] * nx + C.M[1, 2] * ny + C.M[2, 2] * nz;
  u := 0.5 + ArcTan2(ox, oz) / (2 * Pi);
  if C.P.FlipU then u := 1 - u;
  v := 0.5 - ArcSin(EnsureRange(oy, -1, 1)) / Pi;
  u := u * C.P.TileU + C.P.OffsetU;
  v := v * C.P.TileV + C.P.OffsetV;
  u := u - Floor(u);
  if C.WrapV then v := v - Floor(v) else v := EnsureRange(v, 0, 1);
  SampleTex(C, u, v, r, g, b, a);
end;

{ Shade one sample on the unit disk; returns premultiplied colour. }
procedure ShadeSample(const C: TRenderCtx; nx, ny: Double; out r, g, b, a: Double);
var
  d2, nz, ndl, shade, spec, rv, fr, s: Double;
  fr_, fg_, fb_, fa_, br, bg, bb, ba: Double;
begin
  d2 := nx * nx + ny * ny;
  nz := Sqrt(Max(0, 1 - d2));

  { --- front surface --- }
  SurfaceTex(C, nx, ny, nz, fr_, fg_, fb_, fa_);
  fa_ := fa_ * C.P.Opacity;
  fr_ := fr_ * C.P.Opacity; fg_ := fg_ * C.P.Opacity; fb_ := fb_ * C.P.Opacity;
  spec := 0;
  if C.P.Lighting then
  begin
    ndl := nx * C.Lx + ny * C.Ly + nz * C.Lz;
    if C.P.ToonSteps > 0 then
      shade := C.P.Ambient + (1 - C.P.Ambient) *
        Min(1.0, Floor(Max(0, ndl) * C.P.ToonSteps + 0.5) / C.P.ToonSteps)
    else
      shade := C.P.Ambient + (1 - C.P.Ambient) * Max(0, ndl);
    fr_ := fr_ * shade; fg_ := fg_ * shade; fb_ := fb_ * shade;
    if ndl > 0 then
    begin
      rv := 2 * ndl * nz - C.Lz;
      if rv > 0 then spec := C.P.Specular * Power(rv, C.P.Shininess);
      { cel shading: a single hard-edged highlight }
      if C.P.ToonSteps > 0 then
        if spec > 0.4 * C.P.Specular then spec := C.P.Specular else spec := 0;
    end;
    if C.P.Rim > 0 then
    begin
      { fresnel: edges of glass look more opaque }
      fr := C.P.Rim * Power(1 - nz, 3);
      if fa_ > 1e-6 then
      begin
        s := (fa_ + (1 - fa_) * fr) / fa_;
        fr_ := fr_ * s; fg_ := fg_ * s; fb_ := fb_ * s;
        fa_ := fa_ + (1 - fa_) * fr;
      end
      else
      begin
        fr_ := fr * 0.8; fg_ := fr * 0.8; fb_ := fr * 0.85; fa_ := fr;
      end;
    end;
  end;

  { --- inner back surface, seen through the front --- }
  if C.P.ShowBack and (fa_ < 0.999) then
  begin
    SurfaceTex(C, nx, ny, -nz, br, bg, bb, ba);
    ba := ba * C.P.Opacity;
    br := br * C.P.Opacity; bg := bg * C.P.Opacity; bb := bb * C.P.Opacity;
    if C.P.Lighting then
    begin
      { inner surface normal points back toward the viewer }
      ndl := -nx * C.Lx - ny * C.Ly + nz * C.Lz;
      shade := (C.P.Ambient + (1 - C.P.Ambient) * Max(0, ndl)) * 0.75;
      br := br * shade; bg := bg * shade; bb := bb * shade;
    end;
    fr_ := fr_ + br * (1 - fa_);
    fg_ := fg_ + bg * (1 - fa_);
    fb_ := fb_ + bb * (1 - fa_);
    fa_ := fa_ + ba * (1 - fa_);
  end;

  { --- specular highlight composited on top (white) --- }
  if spec > 0 then
  begin
    s := Min(1, spec);
    fr_ := s + (1 - s) * fr_;
    fg_ := s + (1 - s) * fg_;
    fb_ := s + (1 - s) * fb_;
    fa_ := s + (1 - s) * fa_;
  end;

  r := fr_; g := fg_; b := fb_; a := fa_;
end;

procedure RenderSphere(const Tex: TPixelBuf; const P: TSphereParams;
  W, H: Integer; var Dst: TPixelBuf; SuperSample: Integer; HardEdge: Boolean);
var
  C: TRenderCtx;
  x, y, sx, sy, ss: Integer;
  cx, cy, R, px, py, nx, ny, d, cov, invSS2, len: Double;
  sr, sg, sb, sa, ar, ag, ab, aa: Double;
  el, az: Double;
  ir, ig, ib, ia: Integer;
begin
  BufInit(Dst, W, H, 0);
  if (W <= 0) or (H <= 0) or (Tex.W = 0) then Exit;
  ss := EnsureRange(SuperSample, 1, 8);
  C.Tex := @Tex;
  C.P := P;
  C.P.TileU := Max(1, P.TileU);
  C.P.TileV := Max(1, P.TileV);
  C.M := RotMatrix(P.RotX, P.RotY, P.RotZ);
  C.WrapV := (C.P.TileV > 1) or (Abs(P.OffsetV) > 1e-9);
  el := DegToRad(P.LightEl);
  az := DegToRad(P.LightAz);
  C.Lx := Cos(el) * Sin(az);
  C.Ly := Sin(el);
  C.Lz := Cos(el) * Cos(az);
  len := Sqrt(Sqr(C.Lx) + Sqr(C.Ly) + Sqr(C.Lz));
  C.Lx := C.Lx / len; C.Ly := C.Ly / len; C.Lz := C.Lz / len;

  cx := W / 2;
  cy := H / 2;
  R := SphereRadius(P, W, H);
  invSS2 := 1 / (ss * ss);

  for y := 0 to H - 1 do
  begin
    { quick reject rows fully outside the disk }
    if (Abs(y + 0.5 - cy) - 1) > R then Continue;
    for x := 0 to W - 1 do
    begin
      if (Sqr(x + 0.5 - cx) + Sqr(y + 0.5 - cy)) > Sqr(R + 1.5) then Continue;
      { hard edge: a pixel is either fully inside the sphere or skipped }
      if HardEdge and not InsideSphere(P, W, H, x, y) then Continue;
      ar := 0; ag := 0; ab := 0; aa := 0;
      for sy := 0 to ss - 1 do
        for sx := 0 to ss - 1 do
        begin
          px := x + (sx + 0.5) / ss;
          py := y + (sy + 0.5) / ss;
          nx := (px - cx) / R;
          ny := -(py - cy) / R;
          d := Sqrt(nx * nx + ny * ny);
          { analytic edge coverage at sub-sample resolution }
          if HardEdge then
            cov := 1
          else
            cov := EnsureRange((1 - d) * R * ss + 0.5, 0, 1);
          if cov <= 0 then Continue;
          if d > 0.9999 then
          begin
            nx := nx / d * 0.9999;
            ny := ny / d * 0.9999;
          end;
          ShadeSample(C, nx, ny, sr, sg, sb, sa);
          ar := ar + sr * cov; ag := ag + sg * cov; ab := ab + sb * cov; aa := aa + sa * cov;
        end;
      ar := ar * invSS2; ag := ag * invSS2; ab := ab * invSS2; aa := aa * invSS2;
      if aa <= 1 / 512 then Continue;
      { un-premultiply for straight-alpha output }
      ia := Round(Min(1, aa) * 255);
      ir := Round(Min(1, ar / aa) * 255);
      ig := Round(Min(1, ag / aa) * 255);
      ib := Round(Min(1, ab / aa) * 255);
      Dst.Data[y * W + x] := (LongWord(ia) shl 24) or (LongWord(ir) shl 16) or
                             (LongWord(ig) shl 8) or LongWord(ib);
    end;
  end;
end;

end.
