unit SDL3Lib;

{ Minimal dynamic binding for SDL3 + SDL3_image.
  Only the functions this application needs are imported. The DLLs are
  loaded at runtime so the program can show a friendly message if they
  are missing. }

{$mode objfpc}{$H+}
{$PACKRECORDS C}

interface

uses
  SysUtils, Math, DynLibs;

const
  {$IFDEF WINDOWS}
  SDL3_LIB       = 'SDL3.dll';
  SDL3_IMAGE_LIB = 'SDL3_image.dll';
  {$ELSE}
  {$IFDEF DARWIN}
  SDL3_LIB       = 'libSDL3.dylib';
  SDL3_IMAGE_LIB = 'libSDL3_image.dylib';
  {$ELSE}
  SDL3_LIB       = 'libSDL3.so.0';
  SDL3_IMAGE_LIB = 'libSDL3_image.so.0';
  {$ENDIF}
  {$ENDIF}

  { SDL_DEFINE_PIXELFORMAT(PACKED32, ARGB/ABGR, 8888, 32, 4) }
  SDL_PIXELFORMAT_ARGB8888 = $16362004;  { memory order on LE: B G R A }
  SDL_PIXELFORMAT_ABGR8888 = $16762004;  { memory order on LE: R G B A }

  SDL_INIT_VIDEO               = $00000020;
  SDL_WINDOW_RESIZABLE         = $0000000000000020;
  SDL_TEXTUREACCESS_STREAMING  = 1;
  SDL_BLENDMODE_BLEND          = $00000001;
  SDL_SCALEMODE_NEAREST        = 0;
  SDL_SCALEMODE_LINEAR         = 1;

  SDL_EVENT_QUIT                  = $100;
  SDL_EVENT_WINDOW_CLOSE_REQUESTED = $210;
  SDL_EVENT_KEY_DOWN              = $300;
  SDL_EVENT_MOUSE_MOTION          = $400;
  SDL_EVENT_MOUSE_WHEEL           = $403;

  SDL_BUTTON_LMASK = $1;
  SDL_BUTTON_RMASK = $4;

type
  SDL_PixelFormat = LongWord;


  PSDL_Surface = ^SDL_Surface;
  SDL_Surface = record
    flags    : LongWord;
    format   : SDL_PixelFormat;
    w, h     : LongInt;
    pitch    : LongInt;
    pixels   : Pointer;
    refcount : LongInt;
    reserved : Pointer;
  end;

  PSDL_Window   = Pointer;
  PSDL_Renderer = Pointer;
  PSDL_Texture  = Pointer;

  PSDL_FRect = ^SDL_FRect;
  SDL_FRect = record
    x, y, w, h: Single;
  end;

  { SDL_Event is a 128 byte union; only the fields used here are mapped }
  PSDL_Event = ^SDL_Event;
  SDL_Event = record
    case Integer of
      0: (type_: LongWord);
      1: (motion: record
            type_     : LongWord;
            reserved  : LongWord;
            timestamp : QWord;
            windowID  : LongWord;
            which     : LongWord;
            state     : LongWord;
            x, y      : Single;
            xrel, yrel: Single;
          end);
      2: (wheel: record
            type_     : LongWord;
            reserved  : LongWord;
            timestamp : QWord;
            windowID  : LongWord;
            which     : LongWord;
            x, y      : Single;
          end);
      3: (padding: array[0..127] of Byte);
  end;

var
  SDL_Init          : function(flags: LongWord): ByteBool; cdecl;
  SDL_Quit          : procedure; cdecl;
  SDL_GetError      : function: PAnsiChar; cdecl;
  SDL_CreateSurface : function(width, height: LongInt; format: SDL_PixelFormat): PSDL_Surface; cdecl;
  SDL_DestroySurface: procedure(surface: PSDL_Surface); cdecl;
  SDL_ConvertSurface: function(surface: PSDL_Surface; format: SDL_PixelFormat): PSDL_Surface; cdecl;
  SDL_LockSurface   : function(surface: PSDL_Surface): ByteBool; cdecl;
  SDL_UnlockSurface : procedure(surface: PSDL_Surface); cdecl;
  SDL_LoadBMP       : function(const fname: PAnsiChar): PSDL_Surface; cdecl;
  SDL_SaveBMP       : function(surface: PSDL_Surface; const fname: PAnsiChar): ByteBool; cdecl;

  SDL_InitSubSystem : function(flags: LongWord): ByteBool; cdecl;
  SDL_CreateWindow  : function(const title: PAnsiChar; w, h: LongInt; flags: QWord): PSDL_Window; cdecl;
  SDL_DestroyWindow : procedure(window: PSDL_Window); cdecl;
  SDL_GetWindowSize : function(window: PSDL_Window; w, h: PLongInt): ByteBool; cdecl;
  SDL_RaiseWindow   : function(window: PSDL_Window): ByteBool; cdecl;
  SDL_CreateRenderer: function(window: PSDL_Window; const name: PAnsiChar): PSDL_Renderer; cdecl;
  SDL_DestroyRenderer: procedure(renderer: PSDL_Renderer); cdecl;
  SDL_CreateTexture : function(renderer: PSDL_Renderer; format: SDL_PixelFormat; access, w, h: LongInt): PSDL_Texture; cdecl;
  SDL_DestroyTexture: procedure(texture: PSDL_Texture); cdecl;
  SDL_UpdateTexture : function(texture: PSDL_Texture; const rect: Pointer; const pixels: Pointer; pitch: LongInt): ByteBool; cdecl;
  SDL_SetTextureBlendMode: function(texture: PSDL_Texture; blendMode: LongWord): ByteBool; cdecl;
  SDL_SetTextureScaleMode: function(texture: PSDL_Texture; scaleMode: LongInt): ByteBool; cdecl;
  SDL_SetRenderDrawColor: function(renderer: PSDL_Renderer; r, g, b, a: Byte): ByteBool; cdecl;
  SDL_RenderClear   : function(renderer: PSDL_Renderer): ByteBool; cdecl;
  SDL_RenderTexture : function(renderer: PSDL_Renderer; texture: PSDL_Texture; const srcrect, dstrect: PSDL_FRect): ByteBool; cdecl;
  SDL_RenderPresent : function(renderer: PSDL_Renderer): ByteBool; cdecl;
  SDL_PollEvent     : function(event: PSDL_Event): ByteBool; cdecl;

  IMG_Load          : function(const fname: PAnsiChar): PSDL_Surface; cdecl;
  IMG_SavePNG       : function(surface: PSDL_Surface; const fname: PAnsiChar): ByteBool; cdecl;

function LoadSDL3(out ErrMsg: string): Boolean;
procedure UnloadSDL3;
function SDL3Loaded: Boolean;
function SDL3ImageLoaded: Boolean;
function SDLErrorStr: string;

implementation

var
  hSDL : TLibHandle = NilHandle;
  hIMG : TLibHandle = NilHandle;

function SDL3Loaded: Boolean;
begin
  Result := hSDL <> NilHandle;
end;

function SDL3ImageLoaded: Boolean;
begin
  Result := hIMG <> NilHandle;
end;

function SDLErrorStr: string;
begin
  if Assigned(SDL_GetError) then
    Result := string(SDL_GetError())
  else
    Result := 'SDL not loaded';
end;

function LoadSDL3(out ErrMsg: string): Boolean;

  function Need(H: TLibHandle; const Name: string): Pointer;
  begin
    Result := GetProcedureAddress(H, Name);
    if Result = nil then
      raise Exception.CreateFmt('Function "%s" not found in SDL library', [Name]);
  end;

var
  Dir: string;
begin
  Result := False;
  ErrMsg := '';
  if hSDL <> NilHandle then Exit(True);
  { FPC unmasks FPU exceptions by default, but SDL and the Direct3D/OpenGL
    drivers behind SDL_Renderer rely on IEEE behaviour (NaN/Inf instead of
    traps). Without this the live view window dies with EInvalidOp. The mask
    must be process wide because SDL's window procedure is also called from
    the LCL message loop. }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
                    exOverflow, exUnderflow, exPrecision]);
  Dir := ExtractFilePath(ParamStr(0));
  hSDL := LoadLibrary(Dir + SDL3_LIB);
  if hSDL = NilHandle then hSDL := LoadLibrary(SDL3_LIB);
  if hSDL = NilHandle then
  begin
    ErrMsg := 'Cannot load ' + SDL3_LIB + '. Put it next to the executable.';
    Exit;
  end;
  try
    Pointer(SDL_Init)           := Need(hSDL, 'SDL_Init');
    Pointer(SDL_Quit)           := Need(hSDL, 'SDL_Quit');
    Pointer(SDL_GetError)       := Need(hSDL, 'SDL_GetError');
    Pointer(SDL_CreateSurface)  := Need(hSDL, 'SDL_CreateSurface');
    Pointer(SDL_DestroySurface) := Need(hSDL, 'SDL_DestroySurface');
    Pointer(SDL_ConvertSurface) := Need(hSDL, 'SDL_ConvertSurface');
    Pointer(SDL_LockSurface)    := Need(hSDL, 'SDL_LockSurface');
    Pointer(SDL_UnlockSurface)  := Need(hSDL, 'SDL_UnlockSurface');
    Pointer(SDL_LoadBMP)        := Need(hSDL, 'SDL_LoadBMP');
    Pointer(SDL_SaveBMP)        := Need(hSDL, 'SDL_SaveBMP');
    Pointer(SDL_InitSubSystem)  := Need(hSDL, 'SDL_InitSubSystem');
    Pointer(SDL_CreateWindow)   := Need(hSDL, 'SDL_CreateWindow');
    Pointer(SDL_DestroyWindow)  := Need(hSDL, 'SDL_DestroyWindow');
    Pointer(SDL_GetWindowSize)  := Need(hSDL, 'SDL_GetWindowSize');
    Pointer(SDL_RaiseWindow)    := Need(hSDL, 'SDL_RaiseWindow');
    Pointer(SDL_CreateRenderer) := Need(hSDL, 'SDL_CreateRenderer');
    Pointer(SDL_DestroyRenderer):= Need(hSDL, 'SDL_DestroyRenderer');
    Pointer(SDL_CreateTexture)  := Need(hSDL, 'SDL_CreateTexture');
    Pointer(SDL_DestroyTexture) := Need(hSDL, 'SDL_DestroyTexture');
    Pointer(SDL_UpdateTexture)  := Need(hSDL, 'SDL_UpdateTexture');
    Pointer(SDL_SetTextureBlendMode) := Need(hSDL, 'SDL_SetTextureBlendMode');
    Pointer(SDL_SetTextureScaleMode) := Need(hSDL, 'SDL_SetTextureScaleMode');
    Pointer(SDL_SetRenderDrawColor)  := Need(hSDL, 'SDL_SetRenderDrawColor');
    Pointer(SDL_RenderClear)    := Need(hSDL, 'SDL_RenderClear');
    Pointer(SDL_RenderTexture)  := Need(hSDL, 'SDL_RenderTexture');
    Pointer(SDL_RenderPresent)  := Need(hSDL, 'SDL_RenderPresent');
    Pointer(SDL_PollEvent)      := Need(hSDL, 'SDL_PollEvent');
  except
    on E: Exception do
    begin
      ErrMsg := E.Message;
      UnloadSDL3;
      Exit;
    end;
  end;

  hIMG := LoadLibrary(Dir + SDL3_IMAGE_LIB);
  if hIMG = NilHandle then hIMG := LoadLibrary(SDL3_IMAGE_LIB);
  if hIMG <> NilHandle then
  begin
    Pointer(IMG_Load)    := GetProcedureAddress(hIMG, 'IMG_Load');
    Pointer(IMG_SavePNG) := GetProcedureAddress(hIMG, 'IMG_SavePNG');
    if (IMG_Load = nil) or (IMG_SavePNG = nil) then
    begin
      UnloadLibrary(hIMG);
      hIMG := NilHandle;
      IMG_Load := nil;
      IMG_SavePNG := nil;
    end;
  end;
  if hIMG = NilHandle then
    ErrMsg := SDL3_IMAGE_LIB + ' not available: PNG/JPG import and PNG export are disabled (BMP still works).';

  SDL_Init(0);
  Result := True;
end;

procedure UnloadSDL3;
begin
  if hIMG <> NilHandle then
  begin
    UnloadLibrary(hIMG);
    hIMG := NilHandle;
  end;
  if hSDL <> NilHandle then
  begin
    if Assigned(SDL_Quit) then SDL_Quit();
    UnloadLibrary(hSDL);
    hSDL := NilHandle;
  end;
  IMG_Load := nil;
  IMG_SavePNG := nil;
  SDL_Init := nil;
  SDL_Quit := nil;
  SDL_GetError := nil;
end;

end.
