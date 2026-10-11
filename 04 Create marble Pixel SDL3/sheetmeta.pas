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
function SaveUnitySpriteSheet(const SheetFileName, AnimFileName: string; const Info: TSheetJsonInfo;
  out Err: string): Boolean;
function SaveGameMakerScript(const FileName: string; const Info: TSheetJsonInfo; out Err: string): Boolean;
function GameMakerStripName(const FramePrefix: string; Count: Integer): string;
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

{ ---------- Unity ---------- }

function NewUnityGuid: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := LowerCase(StringReplace(StringReplace(StringReplace(GUIDToString(G),
    '{', '', []), '}', '', []), '-', '', [rfReplaceAll]));
end;

function YamlStr(const S: string): string;
begin
  { plain scalars are fine for our names; quote anything unusual }
  if (S = '') or (Pos(':', S) > 0) or (Pos('#', S) > 0) or (Pos('''', S) > 0) or
     (Pos('"', S) > 0) or (S[1] in [' ', '-', '[', '{', '&', '*', '!', '|', '>', '%', '@', '`']) then
    Result := '"' + JsonEscape(S) + '"'
  else
    Result := S;
end;

{ Unity sprite fileIDs: the classic scheme 21300000 + 2*index. It is also
  written to the newer internalID / nameFileIdTable fields, so old (2018-2019)
  and current Unity versions resolve the same IDs used by the .anim clip. }
function SpriteFileID(i: Integer): Int64;
begin
  Result := 21300000 + 2 * Int64(i);
end;

{ Writes <sheet>.meta (TextureImporter, Sprite (2D and UI), Multiple, one
  sprite per frame) and an AnimationClip that swaps SpriteRenderer.m_Sprite.
  Copy the sheet, its .meta and the .anim into the Unity project's Assets
  folder together. }
function SaveUnitySpriteSheet(const SheetFileName, AnimFileName: string; const Info: TSheetJsonInfo;
  out Err: string): Boolean;
var
  M, A: TStringList;
  Guid, Name, Ref, ClipName: string;
  i, x, y, rows, sheetW, sheetH, maxSize, filterMode, compression: Integer;
  dt: Double;
begin
  Result := False;
  Err := '';
  if (Info.Count <= 0) or (Info.Cols <= 0) then
  begin
    Err := 'No frames';
    Exit;
  end;
  rows := (Info.Count + Info.Cols - 1) div Info.Cols;
  sheetW := Info.Cols * Info.FrameW;
  sheetH := rows * Info.FrameH;
  maxSize := 32;
  while (maxSize < sheetW) or (maxSize < sheetH) do maxSize := maxSize * 2;
  if maxSize > 16384 then maxSize := 16384;
  if Info.PixelArt then
  begin
    filterMode := 0;    { Point }
    compression := 0;   { None: keeps palette colours exact }
  end
  else
  begin
    filterMode := 1;    { Bilinear }
    compression := 1;   { Normal quality }
  end;
  Guid := NewUnityGuid;
  dt := Info.DurationMs / 1000;
  ClipName := ChangeFileExt(ExtractFileName(AnimFileName), '');

  M := TStringList.Create;
  A := TStringList.Create;
  try
    M.LineBreak := #10;
    A.LineBreak := #10;

    { ---- <sheet>.png.meta ---- }
    M.Add('fileFormatVersion: 2');
    M.Add('guid: ' + Guid);
    M.Add('TextureImporter:');
    M.Add('  internalIDToNameTable:');
    for i := 0 to Info.Count - 1 do
    begin
      M.Add('  - first:');
      M.Add('      213: ' + IntToStr(SpriteFileID(i)));
      M.Add('    second: ' + YamlStr(Format('%s_%.3d', [Info.FramePrefix, i])));
    end;
    M.Add('  externalObjects: {}');
    M.Add('  serializedVersion: 11');
    M.Add('  mipmaps:');
    M.Add('    mipMapMode: 0');
    M.Add('    enableMipMap: 0');
    M.Add('    sRGBTexture: 1');
    M.Add('    linearTexture: 0');
    M.Add('    fadeOut: 0');
    M.Add('    borderMipMap: 0');
    M.Add('    mipMapsPreserveCoverage: 0');
    M.Add('    alphaTestReferenceValue: 0.5');
    M.Add('    mipMapFadeDistanceStart: 1');
    M.Add('    mipMapFadeDistanceEnd: 3');
    M.Add('  bumpmap:');
    M.Add('    convertToNormalMap: 0');
    M.Add('    externalNormalMap: 0');
    M.Add('    heightScale: 0.25');
    M.Add('    normalMapFilter: 0');
    M.Add('  isReadable: 0');
    M.Add('  streamingMipmaps: 0');
    M.Add('  streamingMipmapsPriority: 0');
    M.Add('  grayScaleToAlpha: 0');
    M.Add('  generateCubemap: 6');
    M.Add('  cubemapConvolution: 0');
    M.Add('  seamlessCubemap: 0');
    M.Add('  textureFormat: 1');
    M.Add('  maxTextureSize: ' + IntToStr(maxSize));
    M.Add('  textureSettings:');
    M.Add('    serializedVersion: 2');
    M.Add('    filterMode: ' + IntToStr(filterMode));
    M.Add('    aniso: 1');
    M.Add('    mipBias: 0');
    M.Add('    wrapU: 1');
    M.Add('    wrapV: 1');
    M.Add('    wrapW: 1');
    M.Add('  nPOTScale: 0');
    M.Add('  lightmap: 0');
    M.Add('  compressionQuality: 50');
    M.Add('  spriteMode: 2');
    M.Add('  spriteExtrude: 1');
    M.Add('  spriteMeshType: 0');
    M.Add('  alignment: 0');
    M.Add('  spritePivot: {x: 0.5, y: 0.5}');
    { one frame = one world unit }
    M.Add('  spritePixelsToUnits: ' + IntToStr(Info.FrameW));
    M.Add('  spriteBorder: {x: 0, y: 0, z: 0, w: 0}');
    M.Add('  spriteGenerateFallbackPhysicsShape: 1');
    M.Add('  alphaUsage: 1');
    M.Add('  alphaIsTransparency: 1');
    M.Add('  spriteTessellationDetail: -1');
    M.Add('  textureType: 8');
    M.Add('  textureShape: 1');
    M.Add('  singleChannelComponent: 0');
    M.Add('  maxTextureSizeSet: 0');
    M.Add('  compressionQualitySet: 0');
    M.Add('  textureFormatSet: 0');
    M.Add('  applyGammaDecoding: 0');
    M.Add('  platformSettings:');
    M.Add('  - serializedVersion: 3');
    M.Add('    buildTarget: DefaultTexturePlatform');
    M.Add('    maxTextureSize: ' + IntToStr(maxSize));
    M.Add('    resizeAlgorithm: 0');
    M.Add('    textureFormat: -1');
    M.Add('    textureCompression: ' + IntToStr(compression));
    M.Add('    compressionQuality: 50');
    M.Add('    crunchedCompression: 0');
    M.Add('    allowsAlphaSplitting: 0');
    M.Add('    overridden: 0');
    M.Add('    androidETC2FallbackOverride: 0');
    M.Add('    forceMaximumCompressionQuality_BC6H_BC7: 0');
    M.Add('  spriteSheet:');
    M.Add('    serializedVersion: 2');
    M.Add('    sprites:');
    for i := 0 to Info.Count - 1 do
    begin
      x := (i mod Info.Cols) * Info.FrameW;
      { Unity rects start at the bottom-left corner of the texture }
      y := sheetH - ((i div Info.Cols) + 1) * Info.FrameH;
      Name := YamlStr(Format('%s_%.3d', [Info.FramePrefix, i]));
      M.Add('    - serializedVersion: 2');
      M.Add('      name: ' + Name);
      M.Add('      rect:');
      M.Add('        serializedVersion: 2');
      M.Add('        x: ' + IntToStr(x));
      M.Add('        y: ' + IntToStr(y));
      M.Add('        width: ' + IntToStr(Info.FrameW));
      M.Add('        height: ' + IntToStr(Info.FrameH));
      M.Add('      alignment: 0');
      M.Add('      pivot: {x: 0.5, y: 0.5}');
      M.Add('      border: {x: 0, y: 0, z: 0, w: 0}');
      M.Add('      outline: []');
      M.Add('      physicsShape: []');
      M.Add('      tessellationDetail: 0');
      M.Add('      bones: []');
      M.Add('      spriteID: ' + NewUnityGuid);
      M.Add('      internalID: ' + IntToStr(SpriteFileID(i)));
      M.Add('      vertices: []');
      M.Add('      indices: ');
      M.Add('      edges: []');
      M.Add('      weights: []');
    end;
    M.Add('    outline: []');
    M.Add('    physicsShape: []');
    M.Add('    bones: []');
    M.Add('    spriteID: ');
    M.Add('    internalID: 0');
    M.Add('    vertices: []');
    M.Add('    indices: ');
    M.Add('    edges: []');
    M.Add('    weights: []');
    M.Add('    secondaryTextures: []');
    M.Add('    nameFileIdTable:');
    for i := 0 to Info.Count - 1 do
      M.Add(Format('      %s: %d', [YamlStr(Format('%s_%.3d', [Info.FramePrefix, i])), SpriteFileID(i)]));
    M.Add('  spritePackingTag: ');
    M.Add('  pSDRemoveMatte: 0');
    M.Add('  pSDShowRemoveMatteOption: 0');
    M.Add('  userData: ');
    M.Add('  assetBundleName: ');
    M.Add('  assetBundleVariant: ');

    { ---- AnimationClip (.anim) ---- }
    A.Add('%YAML 1.1');
    A.Add('%TAG !u! tag:unity3d.com,2011:');
    A.Add('--- !u!74 &7400000');
    A.Add('AnimationClip:');
    A.Add('  m_ObjectHideFlags: 0');
    A.Add('  m_CorrespondingSourceObject: {fileID: 0}');
    A.Add('  m_PrefabInstance: {fileID: 0}');
    A.Add('  m_PrefabAsset: {fileID: 0}');
    A.Add('  m_Name: ' + YamlStr(ClipName));
    A.Add('  serializedVersion: 6');
    A.Add('  m_Legacy: 0');
    A.Add('  m_Compressed: 0');
    A.Add('  m_UseHighQualityCurve: 1');
    A.Add('  m_RotationCurves: []');
    A.Add('  m_CompressedRotationCurves: []');
    A.Add('  m_EulerCurves: []');
    A.Add('  m_PositionCurves: []');
    A.Add('  m_ScaleCurves: []');
    A.Add('  m_FloatCurves: []');
    A.Add('  m_PPtrCurves:');
    A.Add('  - curve:');
    for i := 0 to Info.Count - 1 do
    begin
      Ref := Format('{fileID: %d, guid: %s, type: 3}', [SpriteFileID(i), Guid]);
      A.Add('    - time: ' + FloatJson(i * dt));
      A.Add('      value: ' + Ref);
    end;
    A.Add('    attribute: m_Sprite');
    A.Add('    path: ');
    A.Add('    classID: 212');
    A.Add('    script: {fileID: 0}');
    A.Add('  m_SampleRate: ' + FloatJson(1000 / Info.DurationMs));
    A.Add('  m_WrapMode: 0');
    A.Add('  m_Bounds:');
    A.Add('    m_Center: {x: 0, y: 0, z: 0}');
    A.Add('    m_Extent: {x: 0, y: 0, z: 0}');
    A.Add('  m_ClipBindingConstant:');
    A.Add('    genericBindings:');
    A.Add('    - serializedVersion: 2');
    A.Add('      path: 0');
    A.Add('      attribute: 0');
    A.Add('      script: {fileID: 0}');
    A.Add('      typeID: 212');
    A.Add('      customType: 23');
    A.Add('      isPPtrCurve: 1');
    A.Add('    pptrCurveMapping:');
    for i := 0 to Info.Count - 1 do
      A.Add(Format('    - {fileID: %d, guid: %s, type: 3}', [SpriteFileID(i), Guid]));
    A.Add('  m_AnimationClipSettings:');
    A.Add('    serializedVersion: 2');
    A.Add('    m_AdditiveReferencePoseClip: {fileID: 0}');
    A.Add('    m_AdditiveReferencePoseTime: 0');
    A.Add('    m_StartTime: 0');
    A.Add('    m_StopTime: ' + FloatJson(Info.Count * dt));
    A.Add('    m_OrientationOffsetY: 0');
    A.Add('    m_Level: 0');
    A.Add('    m_CycleOffset: 0');
    A.Add('    m_HasAdditiveReferencePose: 0');
    A.Add('    m_LoopTime: 1');
    A.Add('    m_LoopBlend: 0');
    A.Add('    m_LoopBlendOrientation: 0');
    A.Add('    m_LoopBlendPositionY: 0');
    A.Add('    m_LoopBlendPositionXZ: 0');
    A.Add('    m_KeepOriginalOrientation: 0');
    A.Add('    m_KeepOriginalPositionY: 1');
    A.Add('    m_KeepOriginalPositionXZ: 0');
    A.Add('    m_HeightFromFeet: 0');
    A.Add('    m_Mirror: 0');
    A.Add('  m_EditorCurves: []');
    A.Add('  m_EulerEditorCurves: []');
    A.Add('  m_HasGenericRootTransform: 0');
    A.Add('  m_HasMotionFloatCurves: 0');
    A.Add('  m_Events: []');

    try
      M.SaveToFile(SheetFileName + '.meta');
      A.SaveToFile(AnimFileName);
      Result := True;
    except
      on E: Exception do Err := E.Message;
    end;
  finally
    M.Free;
    A.Free;
  end;
end;

{ ---------- GameMaker ---------- }

{ GameMaker resource / function names: letters, digits and underscores,
  not starting with a digit }
function GmlIdent(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if S[i] in ['a'..'z', 'A'..'Z', '0'..'9', '_'] then
      Result := Result + S[i]
    else
      Result := Result + '_';
  if (Result = '') or (Result[1] in ['0'..'9']) then Result := '_' + Result;
end;

function GameMakerStripName(const FramePrefix: string; Count: Integer): string;
begin
  Result := Format('%s_strip%d.png', [FramePrefix, Count]);
end;

{ GML helper for a horizontal strip <prefix>_strip<N>.png. In the IDE the
  "_strip<N>" suffix makes GameMaker split the image into N frames on import;
  at runtime sprite_add() does the same with the frame count. }
function SaveGameMakerScript(const FileName: string; const Info: TSheetJsonInfo; out Err: string): Boolean;
var
  L: TStringList;
  Strip, SprName, Fn, Fps: string;
  ox, oy: Integer;
begin
  Result := False;
  Err := '';
  if Info.Count <= 0 then
  begin
    Err := 'No frames';
    Exit;
  end;
  Strip := GameMakerStripName(Info.FramePrefix, Info.Count);
  SprName := 'spr_' + GmlIdent(Info.FramePrefix);
  Fn := 'load_' + GmlIdent(Info.FramePrefix) + '_' + GmlIdent(Info.TagName);
  Fps := FloatJson(1000 / Info.DurationMs);
  ox := Info.FrameW div 2;
  oy := Info.FrameH div 2;
  L := TStringList.Create;
  try
    L.LineBreak := #10;
    L.Add('/// ' + Fn + ' - generated by Pixel Marble Maker (SDL3)');
    L.Add('///');
    L.Add(Format('/// Strip image : %s  (%d frames of %d x %d px, one row)', [Strip, Info.Count, Info.FrameW, Info.FrameH]));
    L.Add(Format('/// Animation   : %s, %s fps (%d ms per frame), loops', [Info.TagName, Fps, Info.DurationMs]));
    L.Add('///');
    L.Add('/// Option A - import in the IDE (any GameMaker version):');
    L.Add('///   1. Create a sprite (e.g. ' + SprName + '), open the Sprite Editor > Import,');
    L.Add('///      and pick ' + Strip + '. The "_strip' + IntToStr(Info.Count) +
          '" suffix makes GameMaker split it into ' + IntToStr(Info.Count) + ' frames.');
    L.Add(Format('///   2. Origin: Middle Centre (%d, %d).  Speed: %s frames per second.', [ox, oy, Fps]));
    if Info.PixelArt then
      L.Add('///   3. Pixel art: turn off texture interpolation (Game Options > Graphics, or gpu_set_texfilter(false)).');
    L.Add('///');
    L.Add('/// Option B - load at runtime: add ' + Strip + ' to Included Files, then call');
    L.Add('///   sprite_index = ' + Fn + '();');
    L.Add('///   (functions declared like this need GameMaker Studio 2.3 or newer)');
    L.Add('');
    L.Add('function ' + Fn + '()');
    L.Add('{');
    L.Add(Format('    var _spr = sprite_add("%s", %d, false, false, %d, %d);', [JsonEscape(Strip), Info.Count, ox, oy]));
    L.Add('    if (_spr < 0) {');
    L.Add('        show_debug_message("' + Fn + ': could not load ' + JsonEscape(Strip) + '");');
    L.Add('        return -1;');
    L.Add('    }');
    L.Add('    sprite_set_speed(_spr, ' + Fps + ', spritespeed_framespersecond);');
    L.Add('    return _spr;');
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

end.
