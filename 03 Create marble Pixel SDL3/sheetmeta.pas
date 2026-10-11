unit SheetMeta;

{ Sprite sheet metadata in the TexturePacker JSON format (the same layout
  Aseprite exports). Readable by Phaser, PixiJS, Cocos2d, Defold and the
  common Godot / Unity / GameMaker importers.
  - Hash  : "frames": { "name": {...}, ... }   (Phaser, PixiJS default)
  - Array : "frames": [ {"filename": "name", ...}, ... ]
  Each frame carries its duration (ms); meta.frameTags holds one looping
  animation, plus a few extra marble-specific fields that readers ignore. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TSheetJsonInfo = record
    ImageName   : string;    { sprite sheet file name, relative to the JSON }
    FramePrefix : string;    { frame names: <prefix>_000, <prefix>_001, ... }
    Count       : Integer;
    Cols        : Integer;
    FrameW      : Integer;
    FrameH      : Integer;
    DurationMs  : Integer;
    AsArray     : Boolean;
    TagName     : string;    { animation name, e.g. "spin_y" }
    Axis        : string;    { "X", "Y" or "Z" }
    StartAngle  : Double;    { rotation of frame 0 around Axis, degrees }
    PixelArt    : Boolean;
    PixelSize   : Integer;
    Upscale     : Integer;
  end;

function SaveSheetJson(const FileName: string; const Info: TSheetJsonInfo; out Err: string): Boolean;
function SaveGodotSpriteFrames(const FileName: string; const Info: TSheetJsonInfo; Godot3: Boolean;
  out Err: string): Boolean;
function JsonEscape(const S: string): string;

implementation

function JsonEscape(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    case c of
      '"' : Result := Result + '\"';
      '\' : Result := Result + '\\';
      #8  : Result := Result + '\b';
      #9  : Result := Result + '\t';
      #10 : Result := Result + '\n';
      #12 : Result := Result + '\f';
      #13 : Result := Result + '\r';
    else
      if Ord(c) < 32 then
        Result := Result + '\u' + IntToHex(Ord(c), 4)
      else
        Result := Result + c;   { UTF-8 bytes pass through unchanged }
    end;
  end;
end;

function FloatJson(v: Double): string;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := FormatFloat('0.####', v, FS);
end;

function SaveSheetJson(const FileName: string; const Info: TSheetJsonInfo; out Err: string): Boolean;
var
  L: TStringList;
  i, x, y, rows: Integer;
  Name, Body, Sep, Ind: string;
begin
  Result := False;
  Err := '';
  if (Info.Count <= 0) or (Info.Cols <= 0) then
  begin
    Err := 'No frames';
    Exit;
  end;
  rows := (Info.Count + Info.Cols - 1) div Info.Cols;
  L := TStringList.Create;
  try
    L.LineBreak := #10;
    L.Add('{');
    if Info.AsArray then
    begin
      L.Add('  "frames": [');
      Ind := '    ';
    end
    else
    begin
      L.Add('  "frames": {');
      Ind := '    ';
    end;
    for i := 0 to Info.Count - 1 do
    begin
      x := (i mod Info.Cols) * Info.FrameW;
      y := (i div Info.Cols) * Info.FrameH;
      Name := JsonEscape(Format('%s_%.3d', [Info.FramePrefix, i]));
      Body :=
        Format('"frame": {"x": %d, "y": %d, "w": %d, "h": %d}, ', [x, y, Info.FrameW, Info.FrameH]) +
        '"rotated": false, "trimmed": false, ' +
        Format('"spriteSourceSize": {"x": 0, "y": 0, "w": %d, "h": %d}, ', [Info.FrameW, Info.FrameH]) +
        Format('"sourceSize": {"w": %d, "h": %d}, ', [Info.FrameW, Info.FrameH]) +
        Format('"duration": %d, ', [Info.DurationMs]) +
        '"angle": ' + FloatJson(Info.StartAngle + 360 * i / Info.Count);
      if i < Info.Count - 1 then Sep := ',' else Sep := '';
      if Info.AsArray then
        L.Add(Ind + '{"filename": "' + Name + '", ' + Body + '}' + Sep)
      else
        L.Add(Ind + '"' + Name + '": {' + Body + '}' + Sep);
    end;
    if Info.AsArray then L.Add('  ],') else L.Add('  },');

    L.Add('  "meta": {');
    L.Add('    "app": "Pixel Marble Maker (SDL3)",');
    L.Add('    "version": "1.0",');
    L.Add('    "image": "' + JsonEscape(Info.ImageName) + '",');
    L.Add('    "format": "RGBA8888",');
    L.Add(Format('    "size": {"w": %d, "h": %d},', [Info.Cols * Info.FrameW, rows * Info.FrameH]));
    L.Add('    "scale": "1",');
    L.Add('    "frameTags": [');
    L.Add(Format('      {"name": "%s", "from": 0, "to": %d, "direction": "forward"}',
      [JsonEscape(Info.TagName), Info.Count - 1]));
    L.Add('    ],');
    L.Add('    "layers": [],');
    L.Add('    "slices": [],');
    L.Add(Format('    "frameCount": %d,', [Info.Count]));
    L.Add(Format('    "columns": %d,', [Info.Cols]));
    L.Add(Format('    "rows": %d,', [rows]));
    L.Add(Format('    "frameDuration": %d,', [Info.DurationMs]));
    L.Add(Format('    "fps": %s,', [FloatJson(1000 / Info.DurationMs)]));
    L.Add('    "rotationAxis": "' + JsonEscape(Info.Axis) + '",');
    L.Add('    "degreesPerFrame": ' + FloatJson(360 / Info.Count) + ',');
    if Info.PixelArt then
      L.Add(Format('    "pixelArt": {"enabled": true, "pixelSize": %d, "upscale": %d, "filter": "nearest"}',
        [Info.PixelSize, Info.Upscale]))
    else
      L.Add('    "pixelArt": {"enabled": false, "filter": "linear"}');
    L.Add('  }');
    L.Add('}');
    try
      L.SaveToFile(FileName);
      Result := True;
    except
      on E: Exception do Err := E.Message;
    end;
  finally
    L.Free;
  end;
end;

{ Godot SpriteFrames resource (.tres): one AtlasTexture per frame cut from the
  sprite sheet, and a single looping animation. The sheet is referenced by a
  path relative to the .tres, so keep both files in the same folder inside
  the Godot project. Godot 4 uses format=3 (string ids, per-frame duration),
  Godot 3 uses format=2 (integer ids, plain frame list). }
function SaveGodotSpriteFrames(const FileName: string; const Info: TSheetJsonInfo; Godot3: Boolean;
  out Err: string): Boolean;
var
  L: TStringList;
  i, x, y: Integer;
  Img, Tag, Line: string;
begin
  Result := False;
  Err := '';
  if (Info.Count <= 0) or (Info.Cols <= 0) then
  begin
    Err := 'No frames';
    Exit;
  end;
  Img := JsonEscape(Info.ImageName);
  Tag := JsonEscape(Info.TagName);
  L := TStringList.Create;
  try
    L.LineBreak := #10;
    if Godot3 then
    begin
      L.Add(Format('[gd_resource type="SpriteFrames" load_steps=%d format=2]', [Info.Count + 2]));
      L.Add('');
      L.Add('[ext_resource path="' + Img + '" type="Texture" id=1]');
    end
    else
    begin
      L.Add(Format('[gd_resource type="SpriteFrames" load_steps=%d format=3]', [Info.Count + 2]));
      L.Add('');
      L.Add('[ext_resource type="Texture2D" path="' + Img + '" id="1_sheet"]');
    end;
    L.Add('');
    for i := 0 to Info.Count - 1 do
    begin
      x := (i mod Info.Cols) * Info.FrameW;
      y := (i div Info.Cols) * Info.FrameH;
      if Godot3 then
      begin
        L.Add(Format('[sub_resource type="AtlasTexture" id=%d]', [i + 1]));
        L.Add('atlas = ExtResource( 1 )');
        L.Add(Format('region = Rect2( %d, %d, %d, %d )', [x, y, Info.FrameW, Info.FrameH]));
      end
      else
      begin
        L.Add(Format('[sub_resource type="AtlasTexture" id="AtlasTexture_%.3d"]', [i]));
        L.Add('atlas = ExtResource("1_sheet")');
        L.Add(Format('region = Rect2(%d, %d, %d, %d)', [x, y, Info.FrameW, Info.FrameH]));
      end;
      L.Add('filter_clip = true');
      L.Add('');
    end;
    L.Add('[resource]');
    if Godot3 then
    begin
      Line := '"frames": [ ';
      for i := 0 to Info.Count - 1 do
      begin
        Line := Line + Format('SubResource( %d )', [i + 1]);
        if i < Info.Count - 1 then Line := Line + ', ';
      end;
      L.Add('animations = [ {');
      L.Add(Line + ' ],');
      L.Add('"loop": true,');
      L.Add('"name": "' + Tag + '",');
      L.Add('"speed": ' + FloatJson(1000 / Info.DurationMs));
      L.Add('} ]');
    end
    else
    begin
      L.Add('animations = [{');
      L.Add('"frames": [{');
      for i := 0 to Info.Count - 1 do
      begin
        L.Add('"duration": 1.0,');
        L.Add(Format('"texture": SubResource("AtlasTexture_%.3d")', [i]));
        if i < Info.Count - 1 then L.Add('}, {') else L.Add('}],');
      end;
      L.Add('"loop": true,');
      L.Add('"name": &"' + Tag + '",');
      L.Add('"speed": ' + FloatJson(1000 / Info.DurationMs));
      L.Add('}]');
    end;
    try
      L.SaveToFile(FileName);
      Result := True;
    except
      on E: Exception do Err := E.Message;
    end;
  finally
    L.Free;
  end;
end;

end.
