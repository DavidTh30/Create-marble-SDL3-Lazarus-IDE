unit MainForm;

{ Marble Maker - main window.
  Left  : material texture (import / procedural generator / save).
  Right : textured sphere preview with rotation, mapping, transparency,
          lighting, PNG/BMP export and "capture every angle".
  SDL3 is used for image file I/O and for an optional live SDL3 window. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Spin, LCLType,
  SDL3Lib, PixBuf, TextureGen, SphereRender, PixelArt, GifWriter, SheetMeta;

type

  { TfrmMain }

  TfrmMain = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    { data }
    FTex       : TPixelBuf;
    FTexBmp    : TBitmap;
    FSphere    : TPixelBuf;
    FSphereBmp : TBitmap;
    FParams    : TTexParams;
    FSP        : TSphereParams;
    FUpdating  : Boolean;
    FGenerating: Boolean;
    FBusy      : Boolean;
    FSphereDirty: Boolean;
    FTexSource : string;
    FDragging  : Boolean;
    FDragBtn   : TMouseButton;
    FLastPt    : TPoint;
    FRowTop    : Integer;
    FUIReady   : Boolean;

    { pixel art mode }
    FPP        : TPixelParams;
    FPixelMode : Boolean;
    FPixBuf    : TPixelBuf;
    FPixK      : Integer;
    FPixOrigin : TPoint;
    FPrevW, FPrevH: Integer;
    FLastPal   : TPalette;
    FImgPix    : TPixelBuf;
    FImgPixBmp : TBitmap;
    FImgPixDirty: Boolean;
    FImgPixBox : TPoint;

    { SDL3 live window }
    FSDLWin    : PSDL_Window;
    FSDLRen    : PSDL_Renderer;
    FSDLTex    : PSDL_Texture;
    FSDLTexW, FSDLTexH: Integer;
    FSDLDirty  : Boolean;
    FSDLBuf    : TPixelBuf;
    FInSDLPump : Boolean;

    { layout }
    pnlLeft, pnlRight, pnlTexTop, pnlTexBtns: TPanel;
    sbTex, sbSphere: TScrollBox;
    pbTexture, pbSphere: TPaintBox;
    lblTexInfo: TLabel;
    StatusBar: TStatusBar;
    OpenDlg: TOpenDialog;
    SaveDlg: TSaveDialog;
    GenTimer, SpinTimer, SDLTimer: TTimer;

    { texture controls }
    cbKind, cbStyle, cbTexSize: TComboBox;
    clr1, clr2, clr3: TColorButton;
    tbScale, tbTurb, tbDetail, tbBaseAlpha: TTrackBar;
    lvScale, lvTurb, lvDetail, lvBaseAlpha: TLabel;
    seSeed: TSpinEdit;
    chkAutoGen: TCheckBox;

    { sphere controls }
    tbRotX, tbRotY, tbRotZ, tbSpinSpeed: TTrackBar;
    lvRotX, lvRotY, lvRotZ, lvSpinSpeed: TLabel;
    chkSpin: TCheckBox;
    cbSpinAxis: TComboBox;
    tbOffU, tbOffV, tbTileU, tbTileV: TTrackBar;
    lvOffU, lvOffV, lvTileU, lvTileV: TLabel;
    chkFlipU: TCheckBox;
    tbOpacity, tbAmbient, tbSpecular, tbShininess, tbRim, tbLightAz, tbLightEl, tbSize: TTrackBar;
    lvOpacity, lvAmbient, lvSpecular, lvShininess, lvRim, lvLightAz, lvLightEl, lvSize: TLabel;
    chkLighting, chkBack: TCheckBox;
    cbBg: TComboBox;
    chkPixel, chkPixGrid: TCheckBox;
    tbPixSize, tbPixColors, tbPixDStr, tbToon, tbPixScale: TTrackBar;
    lvPixSize, lvPixColors, lvPixDStr, lvToon, lvPixScale: TLabel;
    cbPixPal, cbPixDither, cbPixAlpha, cbPixOutline: TComboBox;
    clrPixOutline: TColorButton;
    pbPalette: TPaintBox;
    PalOpenDlg: TOpenDialog;
    cbExpSize, cbAA, cbFormat, cbCapAxis: TComboBox;
    seFrames: TSpinEdit;
    chkSheet, chkFrames, chkGif, chkJson, chkGodot, chkUnity, chkGM: TCheckBox;
    cbGodotVer: TComboBox;
    { image to pixel art (left side) }
    chkImgPix: TCheckBox;
    tbImgPixW, tbImgScale: TTrackBar;
    lvImgPixW, lvImgScale: TLabel;
    cbImgResample: TComboBox;
    cbJsonFmt: TComboBox;
    seGifDelay: TSpinEdit;
    cbGifMatte: TComboBox;

    { UI builders }
    function NewRow(AParent: TWinControl; AHeight: Integer = 30): TPanel;
    procedure AddHeader(AParent: TWinControl; const ACaption: string);
    function AddTrack(AParent: TWinControl; const ACaption: string; AMin, AMax, APos: Integer;
      out AValLbl: TLabel; AHandler: TNotifyEvent): TTrackBar;
    function AddCombo(AParent: TWinControl; const ACaption: string; const AItems: array of string;
      AIndex: Integer; AHandler: TNotifyEvent): TComboBox;
    function AddCheck(AParent: TWinControl; const ACaption: string; AChecked: Boolean;
      AHandler: TNotifyEvent): TCheckBox;
    function AddColor(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TColorButton;
    function AddButton(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TButton;
    function AddSpin(AParent: TWinControl; const ACaption: string; AMin, AMax, AValue: Integer;
      AHandler: TNotifyEvent): TSpinEdit;
    procedure BuildUI;
    procedure BuildTexturePanel;
    procedure BuildSpherePanel;

    { texture logic }
    procedure ReadTexControls;
    procedure WriteTexControls;
    procedure UpdateTexLabels;
    procedure FillStyles;
    procedure GenerateNow;
    procedure TextureChanged;
    procedure GenProgress(Percent: Integer);
    procedure LoadTextureFile(const FN: string);

    { sphere logic }
    procedure ReadSphereControls;
    procedure WriteRotationControls;
    procedure UpdateSphereLabels;
    procedure SphereChanged;
    function  ExportSize: Integer;
    function  FrameSize: Integer;
    procedure RenderExportFrame(const P: TSphereParams; const Pal: TPalette; var B: TPixelBuf);
    function  ExportAA: Integer;
    function  ExportExt: string;
    function  AskSaveFile(const ATitle, ADefName: string; out FN: string): Boolean;
    procedure SetStatus(const S: string);

    { SDL3 live view }
    procedure OpenSDLView;
    procedure CloseSDLView;
    procedure RenderSDLView;

    { events }
    procedure TexParamChanged(Sender: TObject);
    procedure KindChanged(Sender: TObject);
    procedure SphereParamChanged(Sender: TObject);
    procedure GenTimerTick(Sender: TObject);
    procedure SpinTimerTick(Sender: TObject);
    procedure SDLTimerTick(Sender: TObject);
    procedure BtnGenerateClick(Sender: TObject);
    procedure BtnRandomSeedClick(Sender: TObject);
    procedure BtnImportClick(Sender: TObject);
    procedure BtnSaveTexClick(Sender: TObject);
    procedure BtnResetRotClick(Sender: TObject);
    procedure BtnResetMapClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure BtnCaptureClick(Sender: TObject);
    procedure BtnSDLViewClick(Sender: TObject);
    procedure BtnLoadPaletteClick(Sender: TObject);
    procedure ImgPixChanged(Sender: TObject);
    procedure BtnExportImgPixClick(Sender: TObject);
    procedure UpdateImgPixLabels;
    procedure PbPalettePaint(Sender: TObject);
    procedure PbTexturePaint(Sender: TObject);
    procedure PbSpherePaint(Sender: TObject);
    procedure PbSphereMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PbSphereMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PbSphereMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PbSphereMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    procedure PbSphereResize(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

const
  TexSizes: array[0..4] of string = ('256 x 128', '512 x 256', '1024 x 512', '2048 x 1024', '4096 x 2048');
  ExpSizes: array[0..5] of Integer = (128, 256, 512, 1024, 2048, 4096);
  FILTER_SAVE = 'PNG image (*.png)|*.png|BMP image (*.bmp)|*.bmp';

function WrapAngle(a: Double): Double;
begin
  Result := a;
  while Result > 180 do Result := Result - 360;
  while Result <= -180 do Result := Result + 360;
end;

{ ============================ UI builders ============================ }

function TfrmMain.NewRow(AParent: TWinControl; AHeight: Integer): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.BevelOuter := bvNone;
  Result.Height := AHeight;
  Inc(FRowTop, 100);
  Result.Top := FRowTop;   { unique increasing Top keeps alTop rows in creation order }
  Result.Align := alTop;
  Result.BorderSpacing.Left := 6;
  Result.BorderSpacing.Right := 6;
  Result.Parent := AParent;
end;

procedure TfrmMain.AddHeader(AParent: TWinControl; const ACaption: string);
var
  Row: TPanel;
  L: TLabel;
begin
  Row := NewRow(AParent, 28);
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Align := alClient;
  L.Layout := tlBottom;
  L.Caption := ACaption;
  L.Font.Style := [fsBold];
  L.Font.Color := clHighlight;
end;

function TfrmMain.AddTrack(AParent: TWinControl; const ACaption: string; AMin, AMax, APos: Integer;
  out AValLbl: TLabel; AHandler: TNotifyEvent): TTrackBar;
var
  Row: TPanel;
  L: TLabel;
begin
  Row := NewRow(AParent, 28);
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Align := alLeft;
  L.AutoSize := False;
  L.Width := 92;
  L.Layout := tlCenter;
  L.Caption := ACaption;
  AValLbl := TLabel.Create(Self);
  AValLbl.Parent := Row;
  AValLbl.Align := alRight;
  AValLbl.AutoSize := False;
  AValLbl.Width := 46;
  AValLbl.Alignment := taRightJustify;
  AValLbl.Layout := tlCenter;
  Result := TTrackBar.Create(Self);
  Result.Parent := Row;
  Result.Align := alClient;
  Result.TickStyle := tsNone;
  Result.Min := AMin;
  Result.Max := AMax;
  Result.Position := APos;
  Result.OnChange := AHandler;
end;

function TfrmMain.AddCombo(AParent: TWinControl; const ACaption: string; const AItems: array of string;
  AIndex: Integer; AHandler: TNotifyEvent): TComboBox;
var
  Row: TPanel;
  L: TLabel;
  i: Integer;
begin
  Row := NewRow(AParent, 30);
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Align := alLeft;
  L.AutoSize := False;
  L.Width := 92;
  L.Layout := tlCenter;
  L.Caption := ACaption;
  Result := TComboBox.Create(Self);
  Result.Parent := Row;
  Result.Align := alClient;
  Result.BorderSpacing.Top := 3;
  Result.BorderSpacing.Bottom := 3;
  Result.Style := csDropDownList;
  for i := 0 to High(AItems) do Result.Items.Add(AItems[i]);
  if Result.Items.Count > 0 then Result.ItemIndex := EnsureRange(AIndex, 0, Result.Items.Count - 1);
  Result.OnChange := AHandler;
end;

function TfrmMain.AddCheck(AParent: TWinControl; const ACaption: string; AChecked: Boolean;
  AHandler: TNotifyEvent): TCheckBox;
var
  Row: TPanel;
begin
  Row := NewRow(AParent, 26);
  Result := TCheckBox.Create(Self);
  Result.Parent := Row;
  Result.Align := alClient;
  Result.BorderSpacing.Left := 92;
  Result.Caption := ACaption;
  Result.Checked := AChecked;
  Result.OnChange := AHandler;
end;

function TfrmMain.AddColor(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TColorButton;
var
  Row: TPanel;
  L: TLabel;
begin
  Row := NewRow(AParent, 30);
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Align := alLeft;
  L.AutoSize := False;
  L.Width := 92;
  L.Layout := tlCenter;
  L.Caption := ACaption;
  Result := TColorButton.Create(Self);
  Result.Parent := Row;
  Result.Align := alLeft;
  Result.Width := 120;
  Result.BorderSpacing.Top := 2;
  Result.BorderSpacing.Bottom := 2;
  Result.OnColorChanged := AHandler;
end;

function TfrmMain.AddButton(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TButton;
var
  Row: TPanel;
begin
  Row := NewRow(AParent, 34);
  Result := TButton.Create(Self);
  Result.Parent := Row;
  Result.Align := alClient;
  Result.BorderSpacing.Top := 3;
  Result.BorderSpacing.Bottom := 3;
  Result.Caption := ACaption;
  Result.OnClick := AHandler;
end;

function TfrmMain.AddSpin(AParent: TWinControl; const ACaption: string; AMin, AMax, AValue: Integer;
  AHandler: TNotifyEvent): TSpinEdit;
var
  Row: TPanel;
  L: TLabel;
begin
  Row := NewRow(AParent, 30);
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Align := alLeft;
  L.AutoSize := False;
  L.Width := 92;
  L.Layout := tlCenter;
  L.Caption := ACaption;
  Result := TSpinEdit.Create(Self);
  Result.Parent := Row;
  Result.Align := alLeft;
  Result.Width := 110;
  Result.BorderSpacing.Top := 3;
  Result.BorderSpacing.Bottom := 3;
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.Value := AValue;
  Result.OnChange := AHandler;
end;

procedure TfrmMain.BuildUI;
var
  Spl: TSplitter;
begin
  StatusBar := TStatusBar.Create(Self);
  StatusBar.Parent := Self;
  StatusBar.SimplePanel := True;

  pnlLeft := TPanel.Create(Self);
  pnlLeft.Parent := Self;
  pnlLeft.Align := alLeft;
  pnlLeft.Width := 480;
  pnlLeft.BevelOuter := bvNone;

  Spl := TSplitter.Create(Self);
  Spl.Parent := Self;
  Spl.Align := alLeft;
  Spl.Left := pnlLeft.Width + 1;
  Spl.Width := 5;

  pnlRight := TPanel.Create(Self);
  pnlRight.Parent := Self;
  pnlRight.Align := alClient;
  pnlRight.BevelOuter := bvNone;

  OpenDlg := TOpenDialog.Create(Self);
  OpenDlg.Title := 'Import texture image';
  OpenDlg.Filter := 'Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tga;*.webp;*.tif;*.tiff;*.qoi|All files|*.*';
  OpenDlg.Options := OpenDlg.Options + [ofFileMustExist];
  SaveDlg := TSaveDialog.Create(Self);
  SaveDlg.Filter := FILTER_SAVE;
  SaveDlg.Options := SaveDlg.Options + [ofOverwritePrompt];

  GenTimer := TTimer.Create(Self);
  GenTimer.Enabled := False;
  GenTimer.Interval := 350;
  GenTimer.OnTimer := @GenTimerTick;
  SpinTimer := TTimer.Create(Self);
  SpinTimer.Enabled := False;
  SpinTimer.Interval := 33;
  SpinTimer.OnTimer := @SpinTimerTick;
  SDLTimer := TTimer.Create(Self);
  SDLTimer.Enabled := False;
  SDLTimer.Interval := 15;
  SDLTimer.OnTimer := @SDLTimerTick;

  BuildTexturePanel;
  BuildSpherePanel;
end;

procedure TfrmMain.BuildTexturePanel;
var
  L: TLabel;
  B: TButton;
  Row: TPanel;
  K: TTexKind;
  Kinds: array of string;
begin
  pnlTexTop := TPanel.Create(Self);
  pnlTexTop.Parent := pnlLeft;
  pnlTexTop.Align := alTop;
  pnlTexTop.Height := 300;
  pnlTexTop.BevelOuter := bvNone;

  L := TLabel.Create(Self);
  L.Parent := pnlTexTop;
  L.Align := alTop;
  L.Caption := '  MATERIAL TEXTURE';
  L.Font.Style := [fsBold];
  L.BorderSpacing.Top := 4;

  pnlTexBtns := TPanel.Create(Self);
  pnlTexBtns.Parent := pnlTexTop;
  pnlTexBtns.Align := alBottom;
  pnlTexBtns.Height := 36;
  pnlTexBtns.BevelOuter := bvNone;

  B := TButton.Create(Self);
  B.Parent := pnlTexBtns;
  B.Caption := 'Import image...';
  B.Align := alLeft;
  B.Width := 150;
  B.BorderSpacing.Around := 4;
  B.OnClick := @BtnImportClick;

  B := TButton.Create(Self);
  B.Parent := pnlTexBtns;
  B.Caption := 'Save texture (PNG/BMP)...';
  B.Align := alLeft;
  B.Left := 200;
  B.Width := 190;
  B.BorderSpacing.Around := 4;
  B.OnClick := @BtnSaveTexClick;

  lblTexInfo := TLabel.Create(Self);
  lblTexInfo.Parent := pnlTexTop;
  lblTexInfo.Align := alBottom;
  lblTexInfo.BorderSpacing.Left := 8;
  lblTexInfo.Caption := '';

  pbTexture := TPaintBox.Create(Self);
  pbTexture.Parent := pnlTexTop;
  pbTexture.Align := alClient;
  pbTexture.BorderSpacing.Around := 6;
  pbTexture.OnPaint := @PbTexturePaint;

  sbTex := TScrollBox.Create(Self);
  sbTex.Parent := pnlLeft;
  sbTex.Align := alClient;
  sbTex.BorderStyle := bsNone;
  sbTex.HorzScrollBar.Visible := False;
  sbTex.VertScrollBar.Tracking := True;

  SetLength(Kinds, Ord(High(TTexKind)) + 1);
  for K := Low(TTexKind) to High(TTexKind) do Kinds[Ord(K)] := KindNames[K];

  AddHeader(sbTex, 'Image to pixel art');
  chkImgPix := AddCheck(sbTex, 'Show texture as pixel art', False, @ImgPixChanged);
  tbImgPixW := AddTrack(sbTex, 'Pixel width', 8, 512, 128, lvImgPixW, @ImgPixChanged);
  cbImgResample := AddCombo(sbTex, 'Downscale', ['Box average (smooth)', 'Nearest (sharp)'], 0,
    @ImgPixChanged);
  tbImgScale := AddTrack(sbTex, 'Export scale', 1, 16, 4, lvImgScale, @ImgPixChanged);
  Row := NewRow(sbTex, 34);
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Align := alClient;
  L.WordWrap := True;
  L.Font.Color := clGrayText;
  L.Caption := 'Palette, dithering, transparency and outline come from "Pixel art style" on the right.';
  AddButton(sbTex, 'Export pixel art image (PNG/BMP)...', @BtnExportImgPixClick);

  AddHeader(sbTex, 'Procedural generator');
  cbKind    := AddCombo(sbTex, 'Material', Kinds, 0, @KindChanged);
  cbStyle   := AddCombo(sbTex, 'Style', [], 0, @TexParamChanged);
  clr1      := AddColor(sbTex, 'Color 1', @TexParamChanged);
  clr2      := AddColor(sbTex, 'Color 2', @TexParamChanged);
  clr3      := AddColor(sbTex, 'Color 3', @TexParamChanged);
  tbScale   := AddTrack(sbTex, 'Scale', 1, 100, 20, lvScale, @TexParamChanged);
  tbTurb    := AddTrack(sbTex, 'Turbulence', 0, 100, 20, lvTurb, @TexParamChanged);
  tbDetail  := AddTrack(sbTex, 'Detail', 1, 8, 6, lvDetail, @TexParamChanged);
  tbBaseAlpha := AddTrack(sbTex, 'Base opacity', 0, 100, 100, lvBaseAlpha, @TexParamChanged);

  Row := NewRow(sbTex, 30);
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Align := alLeft;
  L.AutoSize := False;
  L.Width := 92;
  L.Layout := tlCenter;
  L.Caption := 'Seed';
  B := TButton.Create(Self);
  B.Parent := Row;
  B.Align := alRight;
  B.Width := 90;
  B.BorderSpacing.Top := 3;
  B.BorderSpacing.Bottom := 3;
  B.Caption := 'Random';
  B.OnClick := @BtnRandomSeedClick;
  seSeed := TSpinEdit.Create(Self);
  seSeed.Parent := Row;
  seSeed.Align := alClient;
  seSeed.BorderSpacing.Top := 3;
  seSeed.BorderSpacing.Bottom := 3;
  seSeed.BorderSpacing.Right := 6;
  seSeed.MinValue := 0;
  seSeed.MaxValue := 999999;
  seSeed.Value := 1234;
  seSeed.OnChange := @TexParamChanged;

  cbTexSize := AddCombo(sbTex, 'Texture size', TexSizes, 2, @TexParamChanged);
  chkAutoGen := AddCheck(sbTex, 'Auto-update while editing', True, nil);
  AddButton(sbTex, 'Generate texture', @BtnGenerateClick);

  AddHeader(sbTex, 'Tips');
  Row := NewRow(sbTex, 70);
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Align := alClient;
  L.WordWrap := True;
  L.Caption := 'Textures are equirectangular (2:1) maps. Import any PNG/JPG/BMP, or drag '
    + 'and drop an image file onto the window. Lower opacity/alpha areas make the marble see-through.';
end;

procedure TfrmMain.BuildSpherePanel;
var
  L: TLabel;
  Row: TPanel;
begin
  sbSphere := TScrollBox.Create(Self);
  sbSphere.Parent := pnlRight;
  sbSphere.Align := alRight;
  sbSphere.Width := 330;
  sbSphere.BorderStyle := bsNone;
  sbSphere.HorzScrollBar.Visible := False;
  sbSphere.VertScrollBar.Tracking := True;

  L := TLabel.Create(Self);
  L.Parent := pnlRight;
  L.Align := alTop;
  L.Caption := '  SPHERE  (left-drag: rotate X/Y, right-drag: rotate Z, wheel: size)';
  L.Font.Style := [fsBold];
  L.BorderSpacing.Top := 4;

  pbSphere := TPaintBox.Create(Self);
  pbSphere.Parent := pnlRight;
  pbSphere.Align := alClient;
  pbSphere.BorderSpacing.Around := 6;
  pbSphere.OnPaint := @PbSpherePaint;
  pbSphere.OnMouseDown := @PbSphereMouseDown;
  pbSphere.OnMouseMove := @PbSphereMouseMove;
  pbSphere.OnMouseUp := @PbSphereMouseUp;
  pbSphere.OnMouseWheel := @PbSphereMouseWheel;
  pbSphere.OnResize := @PbSphereResize;

  AddHeader(sbSphere, 'Pixel art style');
  chkPixel := AddCheck(sbSphere, 'Pixel art mode', True, @SphereParamChanged);
  tbPixSize := AddTrack(sbSphere, 'Pixel size', 8, 256, FPP.Size, lvPixSize, @SphereParamChanged);
  cbPixPal := AddCombo(sbSphere, 'Palette', PixPaletteNames, Ord(FPP.Palette), @SphereParamChanged);
  cbPixPal.DropDownCount := 24;
  Row := NewRow(sbSphere, 26);
  pbPalette := TPaintBox.Create(Self);
  pbPalette.Parent := Row;
  pbPalette.Align := alClient;
  pbPalette.BorderSpacing.Left := 92;
  pbPalette.BorderSpacing.Top := 2;
  pbPalette.BorderSpacing.Bottom := 2;
  pbPalette.OnPaint := @PbPalettePaint;
  AddButton(sbSphere, 'Load palette file (.hex .gpl .txt or image)...', @BtnLoadPaletteClick);
  PalOpenDlg := TOpenDialog.Create(Self);
  PalOpenDlg.Title := 'Load palette';
  PalOpenDlg.Filter := 'Palettes and images|*.hex;*.gpl;*.txt;*.png;*.bmp;*.gif;*.jpg;*.jpeg|'
    + 'Lospec / HEX (*.hex)|*.hex|GIMP palette (*.gpl)|*.gpl|Paint.NET palette (*.txt)|*.txt|'
    + 'Image colours|*.png;*.bmp;*.gif;*.jpg;*.jpeg|All files|*.*';
  PalOpenDlg.Options := PalOpenDlg.Options + [ofFileMustExist];
  tbPixColors := AddTrack(sbSphere, 'Colours', 2, 64, FPP.Colors, lvPixColors, @SphereParamChanged);
  cbPixDither := AddCombo(sbSphere, 'Dithering', PixDitherNames, Ord(FPP.Dither), @SphereParamChanged);
  tbPixDStr := AddTrack(sbSphere, 'Dither amount', 0, 100, Round(FPP.DitherStrength * 100), lvPixDStr,
    @SphereParamChanged);
  cbPixAlpha := AddCombo(sbSphere, 'Transparency', PixAlphaNames, Ord(FPP.AlphaMode), @SphereParamChanged);
  cbPixOutline := AddCombo(sbSphere, 'Outline', PixOutlineNames, Ord(FPP.Outline), @SphereParamChanged);
  clrPixOutline := AddColor(sbSphere, 'Outline colour', @SphereParamChanged);
  clrPixOutline.ButtonColor := TColor(((FPP.OutlineColor and $FF) shl 16) or (FPP.OutlineColor and $FF00) or
    ((FPP.OutlineColor shr 16) and $FF));
  tbToon := AddTrack(sbSphere, 'Light bands', 0, 8, FPP.ToonSteps, lvToon, @SphereParamChanged);
  tbPixScale := AddTrack(sbSphere, 'Export scale', 1, 16, FPP.Upscale, lvPixScale, @SphereParamChanged);
  chkPixGrid := AddCheck(sbSphere, 'Show pixel grid', False, @SphereParamChanged);

  AddHeader(sbSphere, 'Rotation');
  tbRotX := AddTrack(sbSphere, 'Rotate X', -180, 180, Round(FSP.RotX), lvRotX, @SphereParamChanged);
  tbRotY := AddTrack(sbSphere, 'Rotate Y', -180, 180, Round(FSP.RotY), lvRotY, @SphereParamChanged);
  tbRotZ := AddTrack(sbSphere, 'Rotate Z', -180, 180, Round(FSP.RotZ), lvRotZ, @SphereParamChanged);
  AddButton(sbSphere, 'Reset rotation', @BtnResetRotClick);
  chkSpin := AddCheck(sbSphere, 'Auto spin', False, @SphereParamChanged);
  cbSpinAxis := AddCombo(sbSphere, 'Spin axis', ['X axis', 'Y axis', 'Z axis'], 1, @SphereParamChanged);
  tbSpinSpeed := AddTrack(sbSphere, 'Spin speed', 1, 20, 4, lvSpinSpeed, @SphereParamChanged);

  AddHeader(sbSphere, 'Texture placement');
  tbOffU := AddTrack(sbSphere, 'Offset H', 0, 360, 0, lvOffU, @SphereParamChanged);
  tbOffV := AddTrack(sbSphere, 'Offset V', -90, 90, 0, lvOffV, @SphereParamChanged);
  tbTileU := AddTrack(sbSphere, 'Repeat H', 1, 8, 1, lvTileU, @SphereParamChanged);
  tbTileV := AddTrack(sbSphere, 'Repeat V', 1, 8, 1, lvTileV, @SphereParamChanged);
  chkFlipU := AddCheck(sbSphere, 'Mirror horizontally', False, @SphereParamChanged);
  AddButton(sbSphere, 'Reset placement', @BtnResetMapClick);

  AddHeader(sbSphere, 'Appearance');
  tbOpacity := AddTrack(sbSphere, 'Opacity', 0, 100, 100, lvOpacity, @SphereParamChanged);
  chkBack := AddCheck(sbSphere, 'Show inner back face', FSP.ShowBack, @SphereParamChanged);
  tbSize := AddTrack(sbSphere, 'Sphere size', 20, 100, Round(FSP.SizeFrac * 100), lvSize, @SphereParamChanged);
  chkLighting := AddCheck(sbSphere, 'Lighting', FSP.Lighting, @SphereParamChanged);
  tbAmbient := AddTrack(sbSphere, 'Ambient', 0, 100, Round(FSP.Ambient * 100), lvAmbient, @SphereParamChanged);
  tbSpecular := AddTrack(sbSphere, 'Specular', 0, 100, Round(FSP.Specular * 100), lvSpecular, @SphereParamChanged);
  tbShininess := AddTrack(sbSphere, 'Shininess', 1, 200, Round(FSP.Shininess), lvShininess, @SphereParamChanged);
  tbRim := AddTrack(sbSphere, 'Glass rim', 0, 100, Round(FSP.Rim * 100), lvRim, @SphereParamChanged);
  tbLightAz := AddTrack(sbSphere, 'Light angle', -180, 180, Round(FSP.LightAz), lvLightAz, @SphereParamChanged);
  tbLightEl := AddTrack(sbSphere, 'Light height', -90, 90, Round(FSP.LightEl), lvLightEl, @SphereParamChanged);
  cbBg := AddCombo(sbSphere, 'Preview bg', ['Checkerboard', 'Black', 'Dark grey', 'White'], 0, @SphereParamChanged);

  AddHeader(sbSphere, 'Export (transparent background)');
  cbExpSize := AddCombo(sbSphere, 'Image size', ['128 px', '256 px', '512 px', '1024 px', '2048 px', '4096 px'], 2, nil);
  cbAA := AddCombo(sbSphere, 'Antialias', ['Off (1x)', '2x2', '3x3', '4x4'], 1, nil);
  cbFormat := AddCombo(sbSphere, 'Format', ['PNG (32-bit RGBA)', 'BMP (32-bit ARGB)'], 0, nil);
  AddButton(sbSphere, 'Export sphere image...', @BtnExportClick);

  AddHeader(sbSphere, 'Capture every angle');
  cbCapAxis := AddCombo(sbSphere, 'Around axis', ['X axis', 'Y axis', 'Z axis'], 1, nil);
  seFrames := AddSpin(sbSphere, 'Frames', 2, 720, 36, nil);
  chkFrames := AddCheck(sbSphere, 'Save individual frames', True, nil);
  chkSheet := AddCheck(sbSphere, 'Save sprite sheet', True, nil);
  chkJson := AddCheck(sbSphere, 'Save sheet JSON (game engines)', True, nil);
  chkGodot := AddCheck(sbSphere, 'Save Godot SpriteFrames (.tres)', True, nil);
  cbGodotVer := AddCombo(sbSphere, 'Godot version', ['Godot 4.x', 'Godot 3.x'], 0, nil);
  chkUnity := AddCheck(sbSphere, 'Save Unity sprite sheet (.meta + .anim)', True, nil);
  chkGM := AddCheck(sbSphere, 'Save GameMaker strip (+ .gml loader)', True, nil);
  cbJsonFmt := AddCombo(sbSphere, 'JSON layout',
    ['Hash (Phaser, PixiJS, TexturePacker)', 'Array (Aseprite, TexturePacker)'], 0, nil);
  chkGif := AddCheck(sbSphere, 'Save animated GIF', True, nil);
  seGifDelay := AddSpin(sbSphere, 'Frame time (ms)', 20, 2000, 60, nil);
  cbGifMatte := AddCombo(sbSphere, 'GIF soft edges',
    ['Cut at 50% alpha', 'Blend onto black', 'Blend onto dark grey', 'Blend onto white'], 0, nil);
  AddButton(sbSphere, 'Capture all angles...', @BtnCaptureClick);

  AddHeader(sbSphere, 'SDL3');
  AddButton(sbSphere, 'Open SDL3 live view window', @BtnSDLViewClick);
end;

{ ============================ form ============================ }

procedure TfrmMain.FormCreate(Sender: TObject);
var
  Err: string;
begin
  Caption := 'Pixel Marble Maker (SDL3)';
  Width := 1360;
  Height := 860;
  AllowDropFiles := True;
  OnDropFiles := @FormDropFiles;

  FTexBmp := TBitmap.Create;
  FSphereBmp := TBitmap.Create;
  FImgPixBmp := TBitmap.Create;
  DefaultSphereParams(FSP);
  DefaultPixelParams(FPP);
  FParams.Width := 1024;
  FParams.Height := 512;
  FParams.Seed := 1234;
  FParams.Style := 0;
  DefaultParams(tkMarble, FParams);

  BuildUI;
  FillStyles;
  WriteTexControls;
  FUIReady := True;
  ReadSphereControls;
  UpdateSphereLabels;

  if not LoadSDL3(Err) then
    MessageDlg('SDL3', Err + LineEnding + LineEnding +
      'The sphere preview still works, but import/export is disabled.', mtWarning, [mbOK], 0)
  else if Err <> '' then
    MessageDlg('SDL3_image', Err, mtWarning, [mbOK], 0);

  GenerateNow;
  SetStatus('Ready. SDL3 ' + BoolToStr(SDL3Loaded, 'loaded', 'NOT loaded') +
    ', SDL3_image ' + BoolToStr(SDL3ImageLoaded, 'loaded', 'NOT loaded') + '.');
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  SpinTimer.Enabled := False;
  GenTimer.Enabled := False;
  CloseSDLView;
  FTexBmp.Free;
  FSphereBmp.Free;
  FImgPixBmp.Free;
  UnloadSDL3;
end;

procedure TfrmMain.SetStatus(const S: string);
begin
  StatusBar.SimpleText := S;
  StatusBar.Update;
end;

{ ============================ texture ============================ }

procedure TfrmMain.FillStyles;
var
  S: TStringArray;
  i: Integer;
begin
  S := StyleNames(FParams.Kind);
  cbStyle.Items.BeginUpdate;
  try
    cbStyle.Items.Clear;
    for i := 0 to High(S) do cbStyle.Items.Add(S[i]);
  finally
    cbStyle.Items.EndUpdate;
  end;
  cbStyle.ItemIndex := EnsureRange(FParams.Style, 0, cbStyle.Items.Count - 1);
end;

procedure TfrmMain.ReadTexControls;
var
  idx: Integer;
begin
  FParams.Kind := TTexKind(Max(0, cbKind.ItemIndex));
  FParams.Style := Max(0, cbStyle.ItemIndex);
  idx := Max(0, cbTexSize.ItemIndex);
  FParams.Width := 256 shl idx;
  FParams.Height := FParams.Width div 2;
  FParams.Color1 := LongWord(ColorToRGB(clr1.ButtonColor));
  FParams.Color2 := LongWord(ColorToRGB(clr2.ButtonColor));
  FParams.Color3 := LongWord(ColorToRGB(clr3.ButtonColor));
  FParams.Scale := tbScale.Position / 10;
  FParams.Turbulence := tbTurb.Position / 20;
  FParams.Octaves := tbDetail.Position;
  FParams.BaseAlpha := tbBaseAlpha.Position / 100;
  FParams.Seed := seSeed.Value;
end;

procedure TfrmMain.WriteTexControls;
var
  i: Integer;
begin
  FUpdating := True;
  try
    cbKind.ItemIndex := Ord(FParams.Kind);
    cbStyle.ItemIndex := EnsureRange(FParams.Style, 0, cbStyle.Items.Count - 1);
    clr1.ButtonColor := TColor(FParams.Color1);
    clr2.ButtonColor := TColor(FParams.Color2);
    clr3.ButtonColor := TColor(FParams.Color3);
    tbScale.Position := EnsureRange(Round(FParams.Scale * 10), tbScale.Min, tbScale.Max);
    tbTurb.Position := EnsureRange(Round(FParams.Turbulence * 20), tbTurb.Min, tbTurb.Max);
    tbDetail.Position := EnsureRange(FParams.Octaves, 1, 8);
    tbBaseAlpha.Position := Round(FParams.BaseAlpha * 100);
    seSeed.Value := FParams.Seed;
    for i := 0 to High(TexSizes) do
      if (256 shl i) = FParams.Width then cbTexSize.ItemIndex := i;
  finally
    FUpdating := False;
  end;
  UpdateTexLabels;
end;

procedure TfrmMain.UpdateTexLabels;
begin
  if lvBaseAlpha = nil then Exit;
  lvScale.Caption := FormatFloat('0.0', tbScale.Position / 10);
  lvTurb.Caption := FormatFloat('0.00', tbTurb.Position / 20);
  lvDetail.Caption := IntToStr(tbDetail.Position);
  lvBaseAlpha.Caption := IntToStr(tbBaseAlpha.Position) + '%';
end;

procedure TfrmMain.TexParamChanged(Sender: TObject);
begin
  UpdateTexLabels;
  if FUpdating then Exit;
  ReadTexControls;
  if (Sender = cbStyle) and ApplyStyleColors(FParams) then WriteTexControls;
  if chkAutoGen.Checked then
  begin
    GenTimer.Enabled := False;
    GenTimer.Enabled := True;
  end;
end;

procedure TfrmMain.KindChanged(Sender: TObject);
var
  W, H, Seed: Integer;
begin
  if FUpdating then Exit;
  W := FParams.Width; H := FParams.Height; Seed := FParams.Seed;
  DefaultParams(TTexKind(Max(0, cbKind.ItemIndex)), FParams);
  FParams.Width := W; FParams.Height := H; FParams.Seed := Seed;
  FParams.Style := 0;
  FillStyles;
  WriteTexControls;
  GenTimer.Enabled := False;
  GenerateNow;
end;

procedure TfrmMain.GenTimerTick(Sender: TObject);
begin
  GenTimer.Enabled := False;
  GenerateNow;
end;

procedure TfrmMain.GenProgress(Percent: Integer);
begin
  SetStatus(Format('Generating %s texture... %d%%', [KindNames[FParams.Kind], Percent]));
end;

procedure TfrmMain.GenerateNow;
var
  T0: QWord;
begin
  if FGenerating then Exit;
  FGenerating := True;
  Screen.Cursor := crHourGlass;
  try
    ReadTexControls;
    T0 := GetTickCount64;
    GenerateTexture(FParams, FTex, @GenProgress);
    FTexSource := 'Generated: ' + KindNames[FParams.Kind] + ' / ' + cbStyle.Text;
    TextureChanged;
    SetStatus(Format('Texture generated in %d ms', [GetTickCount64 - T0]));
  finally
    Screen.Cursor := crDefault;
    FGenerating := False;
  end;
end;

procedure TfrmMain.TextureChanged;
begin
  FImgPixDirty := True;
  UpdateImgPixLabels;
  BufToBitmap(FTex, FTexBmp, pbChecker, Max(4, FTex.W div 64));
  lblTexInfo.Caption := Format('%s   (%d x %d)', [FTexSource, FTex.W, FTex.H]);
  pbTexture.Invalidate;
  SphereChanged;
end;

procedure TfrmMain.LoadTextureFile(const FN: string);
var
  Err: string;
  B: TPixelBuf;
begin
  if not BufLoadFile(FN, B, Err) then
  begin
    MessageDlg('Import failed', FN + LineEnding + Err, mtError, [mbOK], 0);
    Exit;
  end;
  FTex := B;
  FTexSource := 'Imported: ' + ExtractFileName(FN);
  TextureChanged;
  if (FTex.W <> FTex.H * 2) then
    SetStatus('Imported. Note: image is not 2:1, it will be stretched around the sphere.')
  else
    SetStatus('Imported ' + FN);
end;

procedure TfrmMain.BtnGenerateClick(Sender: TObject);
begin
  GenTimer.Enabled := False;
  GenerateNow;
end;

procedure TfrmMain.BtnRandomSeedClick(Sender: TObject);
begin
  seSeed.Value := Random(1000000);   { triggers TexParamChanged }
  if not chkAutoGen.Checked then GenerateNow;
end;

procedure TfrmMain.BtnImportClick(Sender: TObject);
begin
  if OpenDlg.Execute then LoadTextureFile(OpenDlg.FileName);
end;

procedure TfrmMain.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  if Length(FileNames) > 0 then LoadTextureFile(FileNames[0]);
end;

function TfrmMain.AskSaveFile(const ATitle, ADefName: string; out FN: string): Boolean;
var
  Ext: string;
begin
  SaveDlg.Title := ATitle;
  if cbFormat.ItemIndex = 1 then
  begin
    SaveDlg.FilterIndex := 2;
    SaveDlg.DefaultExt := 'bmp';
  end
  else
  begin
    SaveDlg.FilterIndex := 1;
    SaveDlg.DefaultExt := 'png';
  end;
  SaveDlg.FileName := ADefName + '.' + SaveDlg.DefaultExt;
  Result := SaveDlg.Execute;
  if not Result then Exit;
  FN := SaveDlg.FileName;
  Ext := LowerCase(ExtractFileExt(FN));
  if (Ext <> '.png') and (Ext <> '.bmp') then
  begin
    if SaveDlg.FilterIndex = 2 then FN := FN + '.bmp' else FN := FN + '.png';
  end;
end;

procedure TfrmMain.BtnSaveTexClick(Sender: TObject);
var
  FN, Err: string;
begin
  if FTex.W = 0 then Exit;
  if not AskSaveFile('Save texture', 'texture', FN) then Exit;
  if BufSaveFile(FN, FTex, Err) then
    SetStatus('Texture saved: ' + FN)
  else
    MessageDlg('Save failed', Err, mtError, [mbOK], 0);
end;

procedure TfrmMain.PbTexturePaint(Sender: TObject);
var
  C: TCanvas;
  R: TRect;
  W, H, dw, dh, k: Integer;
  Big: TPixelBuf;
begin
  C := pbTexture.Canvas;
  W := pbTexture.Width;
  H := pbTexture.Height;
  C.Brush.Color := clBtnFace;
  C.FillRect(0, 0, W, H);
  if (chkImgPix <> nil) and chkImgPix.Checked and (FTex.W > 0) then
  begin
    { pixel art version: whole-number nearest-neighbour zoom }
    if FImgPixDirty or (FImgPixBox.X <> W) or (FImgPixBox.Y <> H) then
    begin
      ImageToPixelArt(FTex, tbImgPixW.Position, cbImgResample.ItemIndex = 1, FPP, FImgPix);
      k := Max(1, Min(W div Max(1, FImgPix.W), H div Max(1, FImgPix.H)));
      BufScaleNearest(FImgPix, k, Big);
      BufToBitmap(Big, FImgPixBmp, pbChecker, k * Max(1, FImgPix.W div 32));
      FImgPixDirty := False;
      FImgPixBox := Point(W, H);
    end;
    dw := FImgPixBmp.Width;
    dh := FImgPixBmp.Height;
    if (dw > W) or (dh > H) then
    begin
      { more art pixels than screen pixels: shrink to fit (preview only) }
      if dw * H > dh * W then
      begin
        dh := Round(dh * W / dw); dw := W;
      end
      else
      begin
        dw := Round(dw * H / dh); dh := H;
      end;
    end;
    R := Rect((W - dw) div 2, (H - dh) div 2, (W - dw) div 2 + dw, (H - dh) div 2 + dh);
    C.StretchDraw(R, FImgPixBmp);
    C.Brush.Style := bsClear;
    C.Pen.Color := clGray;
    C.Rectangle(R.Left - 1, R.Top - 1, R.Right + 1, R.Bottom + 1);
    C.Brush.Style := bsSolid;
    Exit;
  end;
  if (FTexBmp.Width = 0) or (FTexBmp.Height = 0) then Exit;
  dw := W;
  dh := Round(dw * FTexBmp.Height / FTexBmp.Width);
  if dh > H then
  begin
    dh := H;
    dw := Round(dh * FTexBmp.Width / FTexBmp.Height);
  end;
  R := Rect((W - dw) div 2, (H - dh) div 2, (W - dw) div 2 + dw, (H - dh) div 2 + dh);
  C.StretchDraw(R, FTexBmp);
  C.Brush.Style := bsClear;
  C.Pen.Color := clGray;
  C.Rectangle(R.Left - 1, R.Top - 1, R.Right + 1, R.Bottom + 1);
  C.Brush.Style := bsSolid;
end;

{ ============================ sphere ============================ }

procedure TfrmMain.ReadSphereControls;
var
  c: LongWord;
begin
  FSP.OffsetU := tbOffU.Position / 360;
  FSP.OffsetV := tbOffV.Position / 180;
  FSP.TileU := tbTileU.Position;
  FSP.TileV := tbTileV.Position;
  FSP.FlipU := chkFlipU.Checked;
  FSP.Opacity := tbOpacity.Position / 100;
  FSP.ShowBack := chkBack.Checked;
  FSP.SizeFrac := tbSize.Position / 100;
  FSP.Lighting := chkLighting.Checked;
  FSP.Ambient := tbAmbient.Position / 100;
  FSP.Specular := tbSpecular.Position / 100;
  FSP.Shininess := tbShininess.Position;
  FSP.Rim := tbRim.Position / 100;
  FSP.LightAz := tbLightAz.Position;
  FSP.LightEl := tbLightEl.Position;
  { pixel art }
  FPixelMode := chkPixel.Checked;
  FPP.Size := tbPixSize.Position;
  FPP.Palette := TPixPalette(Max(0, cbPixPal.ItemIndex));
  FPP.Colors := tbPixColors.Position;
  FPP.Dither := TPixDither(Max(0, cbPixDither.ItemIndex));
  FPP.DitherStrength := tbPixDStr.Position / 100;
  FPP.AlphaMode := TPixAlpha(Max(0, cbPixAlpha.ItemIndex));
  FPP.Outline := TPixOutline(Max(0, cbPixOutline.ItemIndex));
  c := LongWord(ColorToRGB(clrPixOutline.ButtonColor));
  FPP.OutlineColor := ((c and $FF) shl 16) or (c and $FF00) or ((c shr 16) and $FF);
  FPP.ToonSteps := tbToon.Position;
  FPP.Upscale := tbPixScale.Position;
end;

procedure TfrmMain.WriteRotationControls;
begin
  FUpdating := True;
  try
    tbRotX.Position := Round(FSP.RotX);
    tbRotY.Position := Round(FSP.RotY);
    tbRotZ.Position := Round(FSP.RotZ);
  finally
    FUpdating := False;
  end;
  UpdateSphereLabels;
end;

procedure TfrmMain.UpdateSphereLabels;
begin
  if lvRotX = nil then Exit;
  lvRotX.Caption := FormatFloat('0', FSP.RotX) + #$C2#$B0;
  lvRotY.Caption := FormatFloat('0', FSP.RotY) + #$C2#$B0;
  lvRotZ.Caption := FormatFloat('0', FSP.RotZ) + #$C2#$B0;
  lvSpinSpeed.Caption := IntToStr(tbSpinSpeed.Position);
  lvOffU.Caption := IntToStr(tbOffU.Position) + #$C2#$B0;
  lvOffV.Caption := IntToStr(tbOffV.Position) + #$C2#$B0;
  lvTileU.Caption := IntToStr(tbTileU.Position) + 'x';
  lvTileV.Caption := IntToStr(tbTileV.Position) + 'x';
  lvOpacity.Caption := IntToStr(tbOpacity.Position) + '%';
  lvSize.Caption := IntToStr(tbSize.Position) + '%';
  lvAmbient.Caption := IntToStr(tbAmbient.Position) + '%';
  lvSpecular.Caption := IntToStr(tbSpecular.Position) + '%';
  lvShininess.Caption := IntToStr(tbShininess.Position);
  lvRim.Caption := IntToStr(tbRim.Position) + '%';
  lvLightAz.Caption := IntToStr(tbLightAz.Position) + #$C2#$B0;
  lvLightEl.Caption := IntToStr(tbLightEl.Position) + #$C2#$B0;
  lvPixSize.Caption := IntToStr(tbPixSize.Position) + ' px';
  if FPP.Palette = ppPosterize then
    lvPixColors.Caption := IntToStr(Min(16, tbPixColors.Position)) + ' lv'
  else
    lvPixColors.Caption := IntToStr(tbPixColors.Position);
  lvPixDStr.Caption := IntToStr(tbPixDStr.Position) + '%';
  if tbToon.Position = 0 then lvToon.Caption := 'smooth' else lvToon.Caption := IntToStr(tbToon.Position);
  lvPixScale.Caption := 'x' + IntToStr(tbPixScale.Position);
  tbPixColors.Enabled := FPP.Palette in [ppPosterize, ppAdaptive];
  if pbPalette <> nil then pbPalette.Invalidate;
  tbPixDStr.Enabled := FPP.Dither <> pdNone;
  cbExpSize.Enabled := not FPixelMode;
  cbAA.Enabled := not FPixelMode;
end;

procedure TfrmMain.SphereParamChanged(Sender: TObject);
begin
  if FUpdating or not FUIReady then Exit;
  if (Sender = cbPixPal) and (TPixPalette(Max(0, cbPixPal.ItemIndex)) = ppCustom) and
     (Length(FPP.CustomPal) = 0) then
  begin
    BtnLoadPaletteClick(nil);
    if Length(FPP.CustomPal) = 0 then Exit;
  end;
  if Sender = tbRotX then FSP.RotX := tbRotX.Position
  else if Sender = tbRotY then FSP.RotY := tbRotY.Position
  else if Sender = tbRotZ then FSP.RotZ := tbRotZ.Position;
  ReadSphereControls;
  UpdateSphereLabels;
  SpinTimer.Enabled := chkSpin.Checked;
  SphereChanged;
  if chkImgPix.Checked then ImgPixChanged(nil);   { palette/dither/outline also drive the image tool }
end;

procedure TfrmMain.SphereChanged;
begin
  FSphereDirty := True;
  FSDLDirty := True;
  if pbSphere <> nil then pbSphere.Invalidate;
end;

procedure TfrmMain.SpinTimerTick(Sender: TObject);
var
  Step: Double;
begin
  Step := tbSpinSpeed.Position * 0.5;
  case cbSpinAxis.ItemIndex of
    0: FSP.RotX := WrapAngle(FSP.RotX + Step);
    2: FSP.RotZ := WrapAngle(FSP.RotZ + Step);
  else
    FSP.RotY := WrapAngle(FSP.RotY + Step);
  end;
  WriteRotationControls;
  SphereChanged;
end;

procedure TfrmMain.BtnResetRotClick(Sender: TObject);
begin
  FSP.RotX := 15; FSP.RotY := 0; FSP.RotZ := 0;
  WriteRotationControls;
  SphereChanged;
end;

procedure TfrmMain.BtnResetMapClick(Sender: TObject);
begin
  FUpdating := True;
  try
    tbOffU.Position := 0;
    tbOffV.Position := 0;
    tbTileU.Position := 1;
    tbTileV.Position := 1;
    chkFlipU.Checked := False;
  finally
    FUpdating := False;
  end;
  ReadSphereControls;
  UpdateSphereLabels;
  SphereChanged;
end;

procedure TfrmMain.PbSpherePaint(Sender: TObject);
var
  W, H, f, k, i, ox, oy: Integer;
  Fast: Boolean;
  Big, Raw: TPixelBuf;
  C: TCanvas;
begin
  W := pbSphere.Width;
  H := pbSphere.Height;
  if (W < 4) or (H < 4) then Exit;
  Fast := FDragging or chkSpin.Checked;
  C := pbSphere.Canvas;

  if FPixelMode then
  begin
    { pixel art: tiny render, nearest-neighbour upscale by an integer factor }
    k := Max(1, Min(W, H) div FPP.Size);
    if FSphereDirty or (FPixK <> k) or (FPrevW <> W) or (FPrevH <> H) then
    begin
      RenderPixelRaw(FTex, FSP, FPP, Raw, Fast);
      FLastPal := BuildPalette(FPP, [Raw]);
      PixelFinish(Raw, FSP, FPP, FLastPal, FPixBuf);
      pbPalette.Invalidate;
      BufScaleNearest(FPixBuf, k, Big);
      BufToBitmap(Big, FSphereBmp, TPreviewBg(Max(0, cbBg.ItemIndex)), k * Max(1, FPP.Size div 16));
      FPixK := k;
      FPrevW := W;
      FPrevH := H;
      FSphereDirty := False;
    end;
    ox := (W - FSphereBmp.Width) div 2;
    oy := (H - FSphereBmp.Height) div 2;
    FPixOrigin := Point(ox, oy);
    C.Brush.Color := clBtnFace;
    C.FillRect(0, 0, W, H);
    C.Draw(ox, oy, FSphereBmp);
    if chkPixGrid.Checked and (k >= 4) then
    begin
      C.Pen.Color := RGBToColor(110, 110, 120);
      C.Pen.Width := 1;
      for i := 0 to FPP.Size do
      begin
        C.Line(ox + i * k, oy, ox + i * k, oy + FPP.Size * k);
        C.Line(ox, oy + i * k, ox + FPP.Size * k, oy + i * k);
      end;
    end;
    Exit;
  end;

  { smooth mode: render at half resolution while interacting / spinning }
  if Fast then f := 2 else f := 1;
  if FSphereDirty or (FSphereBmp.Width <> W div f) or (FSphereBmp.Height <> H div f) then
  begin
    RenderSphere(FTex, FSP, W div f, H div f, FSphere, 1);
    BufToBitmap(FSphere, FSphereBmp, TPreviewBg(Max(0, cbBg.ItemIndex)), 12 div f);
    FSphereDirty := False;
    FPixK := 0;
  end;
  if f = 1 then
    C.Draw(0, 0, FSphereBmp)
  else
    C.StretchDraw(Rect(0, 0, W, H), FSphereBmp);
end;
procedure TfrmMain.PbSphereResize(Sender: TObject);
begin
  SphereChanged;
end;

procedure TfrmMain.PbSphereMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FDragging := True;
  FDragBtn := Button;
  FLastPt := Point(X, Y);
end;

procedure TfrmMain.PbSphereMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  dx, dy: Integer;
begin
  if not FDragging then Exit;
  dx := X - FLastPt.X;
  dy := Y - FLastPt.Y;
  FLastPt := Point(X, Y);
  if (dx = 0) and (dy = 0) then Exit;
  if FDragBtn = mbRight then
    FSP.RotZ := WrapAngle(FSP.RotZ - dx * 0.5)
  else
  begin
    FSP.RotY := WrapAngle(FSP.RotY + dx * 0.5);
    FSP.RotX := WrapAngle(FSP.RotX + dy * 0.5);
  end;
  WriteRotationControls;
  SphereChanged;
end;

procedure TfrmMain.PbSphereMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FDragging := False;
  SphereChanged;   { re-render at full quality }
end;

procedure TfrmMain.PbSphereMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  tbSize.Position := EnsureRange(tbSize.Position + Sign(WheelDelta) * 2, tbSize.Min, tbSize.Max);
  Handled := True;
end;

function TfrmMain.ExportSize: Integer;
begin
  Result := ExpSizes[EnsureRange(cbExpSize.ItemIndex, 0, High(ExpSizes))];
end;

function TfrmMain.FrameSize: Integer;
begin
  if FPixelMode then
    Result := FPP.Size * FPP.Upscale
  else
    Result := ExportSize;
end;

{ one exported frame: smooth render, or pixel art with a given (shared) palette }
procedure TfrmMain.RenderExportFrame(const P: TSphereParams; const Pal: TPalette; var B: TPixelBuf);
var
  Raw, Small: TPixelBuf;
  UsePal: TPalette;
begin
  if not FPixelMode then
  begin
    RenderSphere(FTex, P, ExportSize, ExportSize, B, ExportAA);
    Exit;
  end;
  RenderPixelRaw(FTex, P, FPP, Raw);
  UsePal := Pal;
  if UsePal = nil then UsePal := BuildPalette(FPP, [Raw]);
  PixelFinish(Raw, P, FPP, UsePal, Small);
  BufScaleNearest(Small, FPP.Upscale, B);
end;

function TfrmMain.ExportAA: Integer;
begin
  Result := EnsureRange(cbAA.ItemIndex, 0, 3) + 1;
end;

function TfrmMain.ExportExt: string;
begin
  if cbFormat.ItemIndex = 1 then Result := '.bmp' else Result := '.png';
end;

procedure TfrmMain.BtnExportClick(Sender: TObject);
var
  FN, Err, Kind: string;
  B: TPixelBuf;
  S: Integer;
begin
  if FBusy then Exit;
  if not AskSaveFile('Export sphere', 'marble', FN) then Exit;
  FBusy := True;
  Screen.Cursor := crHourGlass;
  try
    S := FrameSize;
    SetStatus(Format('Rendering %d x %d ...', [S, S]));
    RenderExportFrame(FSP, nil, B);
    if FPixelMode then
      Kind := Format('pixel art %d px x%d', [FPP.Size, FPP.Upscale])
    else
      Kind := 'smooth';
    if BufSaveFile(FN, B, Err) then
      SetStatus(Format('Sphere exported (%d x %d, %s, transparent background): %s', [S, S, Kind, FN]))
    else
      MessageDlg('Export failed', Err, mtError, [mbOK], 0);
  finally
    Screen.Cursor := crDefault;
    FBusy := False;
  end;
end;
procedure TfrmMain.BtnCaptureClick(Sender: TObject);
var
  FN, Base, Ext, Err, OutFN: string;
  Params: array of TSphereParams;
  Raws: array of TPixelBuf;
  Pal: TPalette;
  Frame, Small, Sheet: TPixelBuf;
  i, N, S, Cols, Rows: Integer;
  Ang: Double;
  DoSheet, DoFrames, DoGif, DoJson, DoGodot, DoUnity, DoGM, WasSpinning: Boolean;
  Strip: TPixelBuf;
  StripFN: string;
  Meta: TSheetJsonInfo;
  GifFrames: array of TPixelBuf;
  GifOpt: TGifOptions;
  Outputs: string;
begin
  if FBusy then Exit;
  if not AskSaveFile('Capture every angle - choose base file name', 'marble', FN) then Exit;
  Ext := LowerCase(ExtractFileExt(FN));
  Base := ChangeFileExt(FN, '');
  N := seFrames.Value;
  S := FrameSize;
  Cols := Ceil(Sqrt(N));
  Rows := Ceil(N / Cols);
  DoJson := chkJson.Checked;
  DoGodot := chkGodot.Checked;
  DoUnity := chkUnity.Checked;
  DoGM := chkGM.Checked;
  { the JSON, Godot and Unity files describe the sheet, so they need one }
  DoSheet := chkSheet.Checked or DoJson or DoGodot or DoUnity;
  DoFrames := chkFrames.Checked;
  DoGif := chkGif.Checked;
  if not (DoSheet or DoFrames or DoGif or DoGM) then
  begin
    MessageDlg('Capture', 'Choose at least one output: frames, sprite sheet or animated GIF.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  if DoGif and (Int64(S) * S * N * 4 > Int64(1) shl 30) then
  begin
    DoGif := False;
    MessageDlg('Animated GIF', 'The frames are too large to keep in memory for the GIF (over 1 GB). '
      + 'Use fewer frames or a smaller size. Other outputs will still be saved.', mtInformation, [mbOK], 0);
  end;
  if DoGif then SetLength(GifFrames, N);
  if DoSheet and ((Int64(Cols) * S > 16384) or (Int64(Rows) * S > 16384)) then
  begin
    DoSheet := False;
    DoJson := False;
    DoGodot := False;
    DoUnity := False;
    MessageDlg('Sprite sheet', 'The sprite sheet (and its JSON) would exceed 16384 px and will be skipped. '
      + 'Use fewer frames or a smaller image size.', mtInformation, [mbOK], 0);
  end;
  if DoSheet then BufInit(Sheet, Cols * S, Rows * S, 0);
  { GameMaker strip: every frame in one row }
  if DoGM and (Int64(N) * S > 16384) then
  begin
    DoGM := False;
    MessageDlg('GameMaker strip', Format('A strip of %d frames x %d px would be wider than 16384 px and will be '
      + 'skipped. Use fewer frames or a smaller size.', [N, S]), mtInformation, [mbOK], 0);
  end;
  if DoGM then BufInit(Strip, N * S, S, 0);

  SetLength(Params, N);
  for i := 0 to N - 1 do
  begin
    Params[i] := FSP;
    Ang := 360 * i / N;
    case cbCapAxis.ItemIndex of
      0: Params[i].RotX := WrapAngle(Params[i].RotX + Ang);
      2: Params[i].RotZ := WrapAngle(Params[i].RotZ + Ang);
    else
      Params[i].RotY := WrapAngle(Params[i].RotY + Ang);
    end;
  end;

  WasSpinning := SpinTimer.Enabled;
  SpinTimer.Enabled := False;
  FBusy := True;
  Screen.Cursor := crHourGlass;
  try
    Pal := nil;
    if FPixelMode then
    begin
      { pass 1: raw low-res frames, one shared palette so the animation does not flicker }
      SetLength(Raws, N);
      for i := 0 to N - 1 do
      begin
        SetStatus(Format('Rendering pixel frame %d / %d ...', [i + 1, N]));
        RenderPixelRaw(FTex, Params[i], FPP, Raws[i]);
      end;
      Pal := BuildPalette(FPP, Raws);
    end;
    for i := 0 to N - 1 do
    begin
      SetStatus(Format('Capturing frame %d / %d ...', [i + 1, N]));
      if FPixelMode then
      begin
        PixelFinish(Raws[i], Params[i], FPP, Pal, Small);
        BufScaleNearest(Small, FPP.Upscale, Frame);
      end
      else
        RenderExportFrame(Params[i], nil, Frame);
      if DoFrames then
      begin
        OutFN := Format('%s_%.3d%s', [Base, i, Ext]);
        if not BufSaveFile(OutFN, Frame, Err) then
        begin
          MessageDlg('Capture failed', OutFN + LineEnding + Err, mtError, [mbOK], 0);
          Exit;
        end;
      end;
      if DoSheet then BufBlit(Frame, Sheet, (i mod Cols) * S, (i div Cols) * S);
      if DoGM then BufBlit(Frame, Strip, i * S, 0);
      if DoGif then GifFrames[i] := Frame;
      Frame.Data := nil;   { the GIF keeps its own reference }
    end;
    if DoSheet then
    begin
      OutFN := Base + '_sheet' + Ext;
      if not BufSaveFile(OutFN, Sheet, Err) then
      begin
        MessageDlg('Sprite sheet failed', Err, mtError, [mbOK], 0);
        DoJson := False;
        DoGodot := False;
        DoUnity := False;
      end;
    end;
    if DoJson or DoGodot or DoUnity or DoGM then
    begin
      Meta.ImageName := ExtractFileName(Base + '_sheet' + Ext);
      Meta.FramePrefix := ExtractFileName(Base);
      Meta.Count := N;
      Meta.Cols := Cols;
      Meta.FrameW := S;
      Meta.FrameH := S;
      Meta.DurationMs := seGifDelay.Value;
      Meta.AsArray := cbJsonFmt.ItemIndex = 1;
      case cbCapAxis.ItemIndex of
        0: begin Meta.Axis := 'X'; Meta.StartAngle := FSP.RotX; end;
        2: begin Meta.Axis := 'Z'; Meta.StartAngle := FSP.RotZ; end;
      else
        Meta.Axis := 'Y'; Meta.StartAngle := FSP.RotY;
      end;
      Meta.TagName := 'spin_' + LowerCase(Meta.Axis);
      Meta.PixelArt := FPixelMode;
      Meta.PixelSize := FPP.Size;
      Meta.Upscale := FPP.Upscale;
      if DoJson then
      begin
        OutFN := Base + '_sheet.json';
        if not SaveSheetJson(OutFN, Meta, Err) then
        begin
          MessageDlg('Sheet JSON failed', OutFN + LineEnding + Err, mtError, [mbOK], 0);
          DoJson := False;
        end;
      end;
      if DoGodot then
      begin
        OutFN := Base + '_frames.tres';
        if not SaveGodotSpriteFrames(OutFN, Meta, cbGodotVer.ItemIndex = 1, Err) then
        begin
          MessageDlg('Godot SpriteFrames failed', OutFN + LineEnding + Err, mtError, [mbOK], 0);
          DoGodot := False;
        end;
      end;
      if DoUnity then
      begin
        OutFN := Base + '_' + Meta.TagName + '.anim';
        if not SaveUnitySpriteSheet(Base + '_sheet' + Ext, OutFN, Meta, Err) then
        begin
          MessageDlg('Unity export failed', OutFN + LineEnding + Err, mtError, [mbOK], 0);
          DoUnity := False;
        end;
      end;
      if DoGM then
      begin
        { GameMaker splits "<name>_strip<N>.png" into N frames; always PNG }
        StripFN := ExtractFilePath(Base) + GameMakerStripName(Meta.FramePrefix, N);
        if not BufSaveFile(StripFN, Strip, Err) then
        begin
          MessageDlg('GameMaker strip failed', StripFN + LineEnding + Err, mtError, [mbOK], 0);
          DoGM := False;
        end
        else
        begin
          OutFN := Base + '_' + Meta.TagName + '.gml';
          if not SaveGameMakerScript(OutFN, Meta, Err) then
          begin
            MessageDlg('GameMaker script failed', OutFN + LineEnding + Err, mtError, [mbOK], 0);
            DoGM := False;
          end;
        end;
      end;
    end;
    if DoGif then
    begin
      SetStatus('Encoding animated GIF ...');
      GifOpt.DelayMs := seGifDelay.Value;
      GifOpt.Loop := 0;
      case cbGifMatte.ItemIndex of
        1: GifOpt.Matte := $000000;
        2: GifOpt.Matte := $303030;
        3: GifOpt.Matte := $FFFFFF;
      else
        GifOpt.Matte := -1;
      end;
      OutFN := Base + '.gif';
      if not SaveAnimatedGif(OutFN, GifFrames, GifOpt, Err) then
        MessageDlg('Animated GIF failed', OutFN + LineEnding + Err, mtError, [mbOK], 0);
    end;
    Outputs := '';
    if DoFrames then Outputs := Format('frames %s_###%s', [ExtractFileName(Base), Ext]);
    if DoSheet then Outputs := Outputs + Format(', sprite sheet %dx%d', [Cols, Rows]);
    if DoJson then Outputs := Outputs + ', sheet JSON';
    if DoGodot then Outputs := Outputs + ', Godot SpriteFrames';
    if DoUnity then Outputs := Outputs + ', Unity .meta + .anim';
    if DoGM then Outputs := Outputs + Format(', GameMaker strip (%d frames) + .gml', [N]);
    if DoGif then Outputs := Outputs + Format(', animated GIF (%d ms/frame)', [seGifDelay.Value]);
    if (Outputs <> '') and (Outputs[1] = ',') then Delete(Outputs, 1, 2);
    SetStatus(Format('Captured %d frames (%d x %d): %s', [N, S, S, Outputs]));
  finally
    Screen.Cursor := crDefault;
    FBusy := False;
    SpinTimer.Enabled := WasSpinning;
  end;
end;
procedure TfrmMain.UpdateImgPixLabels;
var
  TW, TH: Integer;
begin
  if lvImgPixW = nil then Exit;
  TW := tbImgPixW.Position;
  if FTex.W > 0 then
  begin
    TW := Min(TW, FTex.W);
    TH := Max(1, Round(FTex.H * TW / FTex.W));
    lvImgPixW.Caption := Format('%dx%d', [TW, TH]);
  end
  else
    lvImgPixW.Caption := IntToStr(TW);
  lvImgScale.Caption := 'x' + IntToStr(tbImgScale.Position);
end;

procedure TfrmMain.ImgPixChanged(Sender: TObject);
begin
  UpdateImgPixLabels;
  FImgPixDirty := True;
  if pbTexture <> nil then pbTexture.Invalidate;
end;

procedure TfrmMain.BtnExportImgPixClick(Sender: TObject);
var
  FN, Err: string;
  Small, Big: TPixelBuf;
begin
  if FTex.W = 0 then Exit;
  if not AskSaveFile('Export pixel art image', 'pixelart', FN) then Exit;
  Screen.Cursor := crHourGlass;
  try
    ImageToPixelArt(FTex, tbImgPixW.Position, cbImgResample.ItemIndex = 1, FPP, Small);
    BufScaleNearest(Small, tbImgScale.Position, Big);
    if BufSaveFile(FN, Big, Err) then
      SetStatus(Format('Pixel art image exported: %d x %d art pixels, x%d = %d x %d px: %s',
        [Small.W, Small.H, tbImgScale.Position, Big.W, Big.H, FN]))
    else
      MessageDlg('Export failed', Err, mtError, [mbOK], 0);
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TfrmMain.BtnLoadPaletteClick(Sender: TObject);
var
  Pal: TPalette;
  Err: string;
begin
  if not PalOpenDlg.Execute then Exit;
  if not LoadPaletteFile(PalOpenDlg.FileName, Pal, Err) then
  begin
    MessageDlg('Load palette', Err, mtError, [mbOK], 0);
    Exit;
  end;
  FPP.CustomPal := Pal;
  FUpdating := True;
  try
    cbPixPal.ItemIndex := Ord(ppCustom);
  finally
    FUpdating := False;
  end;
  ReadSphereControls;
  UpdateSphereLabels;
  SphereChanged;
  if chkImgPix.Checked then ImgPixChanged(nil);
  SetStatus(Format('Custom palette loaded: %d colours from %s',
    [Length(Pal), ExtractFileName(PalOpenDlg.FileName)]));
end;

procedure TfrmMain.PbPalettePaint(Sender: TObject);
var
  C: TCanvas;
  W, H, n, i, x0, x1, rows, perRow, r: Integer;
  Pal: TPalette;
  Msg: string;
begin
  C := pbPalette.Canvas;
  W := pbPalette.Width;
  H := pbPalette.Height;
  C.Brush.Color := clBtnFace;
  C.FillRect(0, 0, W, H);
  if FPixelMode and (FPP.Palette in [ppAdaptive]) then
    Pal := FLastPal
  else
    Pal := BuildPalette(FPP, []);
  n := Length(Pal);
  if n = 0 then
  begin
    case FPP.Palette of
      ppFull: Msg := 'no palette - full colour';
      ppPosterize: Msg := Format('%d levels per channel', [EnsureRange(FPP.Colors, 2, 16)]);
      ppCustom: Msg := 'no custom palette loaded';
    else
      Msg := '';
    end;
    C.Font.Color := clGrayText;
    C.TextOut(2, (H - C.TextHeight('Ag')) div 2, Msg);
    Exit;
  end;
  { up to 32 swatches per row, two rows for bigger palettes }
  if n > 32 then rows := 2 else rows := 1;
  perRow := (n + rows - 1) div rows;
  for i := 0 to n - 1 do
  begin
    r := i div perRow;
    x0 := (i mod perRow) * W div perRow;
    x1 := ((i mod perRow) + 1) * W div perRow;
    C.Brush.Color := RGBToColor((Pal[i] shr 16) and $FF, (Pal[i] shr 8) and $FF, Pal[i] and $FF);
    C.FillRect(x0, r * H div rows, x1, (r + 1) * H div rows);
  end;
end;

{ ============================ SDL3 live view ============================ }

procedure TfrmMain.BtnSDLViewClick(Sender: TObject);
begin
  if not SDL3Loaded then
  begin
    MessageDlg('SDL3', 'SDL3.dll is not loaded.', mtError, [mbOK], 0);
    Exit;
  end;
  if FSDLWin <> nil then
    SDL_RaiseWindow(FSDLWin)
  else
    OpenSDLView;
end;

procedure TfrmMain.OpenSDLView;
begin
  if not SDL_InitSubSystem(SDL_INIT_VIDEO) then
  begin
    MessageDlg('SDL3', 'SDL video init failed: ' + SDLErrorStr, mtError, [mbOK], 0);
    Exit;
  end;
  FSDLWin := SDL_CreateWindow('Marble - SDL3 live view (drag to rotate, wheel = size)', 640, 640,
    SDL_WINDOW_RESIZABLE);
  if FSDLWin = nil then
  begin
    MessageDlg('SDL3', 'SDL_CreateWindow failed: ' + SDLErrorStr, mtError, [mbOK], 0);
    Exit;
  end;
  FSDLRen := SDL_CreateRenderer(FSDLWin, nil);
  if FSDLRen = nil then
  begin
    MessageDlg('SDL3', 'SDL_CreateRenderer failed: ' + SDLErrorStr, mtError, [mbOK], 0);
    SDL_DestroyWindow(FSDLWin);
    FSDLWin := nil;
    Exit;
  end;
  FSDLTex := nil;
  FSDLTexW := 0;
  FSDLTexH := 0;
  FSDLDirty := True;
  SDLTimer.Enabled := True;
  SetStatus('SDL3 live view opened.');
end;

procedure TfrmMain.CloseSDLView;
begin
  SDLTimer.Enabled := False;
  if FSDLTex <> nil then SDL_DestroyTexture(FSDLTex);
  if FSDLRen <> nil then SDL_DestroyRenderer(FSDLRen);
  if FSDLWin <> nil then SDL_DestroyWindow(FSDLWin);
  FSDLTex := nil;
  FSDLRen := nil;
  FSDLWin := nil;
end;

procedure TfrmMain.RenderSDLView;
var
  w, h, tw, th, k: LongInt;
  bg: Byte;
  Dst: SDL_FRect;
begin
  w := 0; h := 0;
  SDL_GetWindowSize(FSDLWin, @w, @h);
  if (w < 4) or (h < 4) then Exit;
  if FPixelMode then
  begin
    tw := FPP.Size; th := FPP.Size;
  end
  else
  begin
    tw := w; th := h;
  end;
  if (FSDLTex = nil) or (tw <> FSDLTexW) or (th <> FSDLTexH) then
  begin
    if FSDLTex <> nil then SDL_DestroyTexture(FSDLTex);
    FSDLTex := SDL_CreateTexture(FSDLRen, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, tw, th);
    if FSDLTex = nil then Exit;
    SDL_SetTextureBlendMode(FSDLTex, SDL_BLENDMODE_BLEND);
    FSDLTexW := tw;
    FSDLTexH := th;
  end;
  if FPixelMode then
  begin
    { the GPU does the upscaling: nearest filtering keeps pixels crisp }
    SDL_SetTextureScaleMode(FSDLTex, SDL_SCALEMODE_NEAREST);
    RenderPixelSphere(FTex, FSP, FPP, FSDLBuf, FDragging or chkSpin.Checked);
  end
  else
  begin
    SDL_SetTextureScaleMode(FSDLTex, SDL_SCALEMODE_LINEAR);
    RenderSphere(FTex, FSP, w, h, FSDLBuf, 1);
  end;
  SDL_UpdateTexture(FSDLTex, nil, @FSDLBuf.Data[0], tw * 4);
  case cbBg.ItemIndex of
    1: bg := 0;
    3: bg := 255;
  else
    bg := 48;
  end;
  SDL_SetRenderDrawColor(FSDLRen, bg, bg, bg, 255);
  SDL_RenderClear(FSDLRen);
  if FPixelMode then
  begin
    k := Max(1, Min(w, h) div tw);
    Dst.w := tw * k;
    Dst.h := th * k;
    Dst.x := (w - tw * k) div 2;   { whole-pixel offsets avoid blurry seams }
    Dst.y := (h - th * k) div 2;
    SDL_RenderTexture(FSDLRen, FSDLTex, nil, @Dst);
  end
  else
    SDL_RenderTexture(FSDLRen, FSDLTex, nil, nil);
  SDL_RenderPresent(FSDLRen);
end;
procedure TfrmMain.SDLTimerTick(Sender: TObject);
var
  Ev: SDL_Event;
  RotChanged: Boolean;
begin
  if FInSDLPump or (FSDLWin = nil) then Exit;
  FInSDLPump := True;
  try
    RotChanged := False;
    FillChar(Ev, SizeOf(Ev), 0);
    while SDL_PollEvent(@Ev) do
    begin
      case Ev.type_ of
        SDL_EVENT_QUIT, SDL_EVENT_WINDOW_CLOSE_REQUESTED:
          begin
            CloseSDLView;
            SetStatus('SDL3 live view closed.');
            Exit;
          end;
        SDL_EVENT_MOUSE_MOTION:
          if (Ev.motion.state and SDL_BUTTON_LMASK) <> 0 then
          begin
            FSP.RotY := WrapAngle(FSP.RotY + Ev.motion.xrel * 0.5);
            FSP.RotX := WrapAngle(FSP.RotX + Ev.motion.yrel * 0.5);
            RotChanged := True;
          end
          else if (Ev.motion.state and SDL_BUTTON_RMASK) <> 0 then
          begin
            FSP.RotZ := WrapAngle(FSP.RotZ - Ev.motion.xrel * 0.5);
            RotChanged := True;
          end;
        SDL_EVENT_MOUSE_WHEEL:
          tbSize.Position := EnsureRange(tbSize.Position + Sign(Ev.wheel.y) * 2, tbSize.Min, tbSize.Max);
      else
        { window resize / expose etc: just redraw }
        FSDLDirty := True;
      end;
    end;
    if RotChanged then
    begin
      WriteRotationControls;
      SphereChanged;
    end;
    if FSDLDirty and (FSDLWin <> nil) then
    begin
      FSDLDirty := False;
      RenderSDLView;
    end;
  finally
    FInSDLPump := False;
  end;
end;

end.
