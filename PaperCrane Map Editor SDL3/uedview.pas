unit uEdView;

{ Paper Crane Map Editor 1 (SDL3): the map is edited on the live papercut world.

  The game's own scene (uGameScene in editor mode) draws the river exactly as
  the game will, on all cores, into an SDL3 streaming texture; the editing marks
  are drawn on top with SDL render lines and SDL_RenderDebugText. The LCL panel
  (uMapMain.TMapForm) holds the same map: settings, properties, the object list,
  the files and a schematic overview; both windows edit one TPCMap.

  Mouse in the SDL window: the panel's tool (1..5) - Select drags objects and
  the gap handles of a pillar, the other tools place objects. Right click
  deletes. Dragging the empty river, the middle button or the wheel scrolls.
  Keys: Left / Right scroll, F5 test-flies from the view (Space flaps, Esc comes
  back), Del, Ctrl+D copy, Ctrl+Z undo, Ctrl+S save, F11 full screen, S saves a
  PNG of the frame, Tab shows / hides the marks. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, Forms, Controls, SDL3, BGRABitmap, BGRABitmapTypes,
  uRenderPool, uGameScene, uFrameRenderer, uPCMap, uPCShape, uMapMain;

type
  TEdDrag = (edNone, edMove, edGapTop, edGapBottom, edPan);

  { TEdView }

  TEdView = class
  private
    FWin: PSDL_Window;
    FRen: PSDL_Renderer;
    FTex: PSDL_Texture;
    FTexW, FTexH: Integer;
    FFlipV: Boolean;
    FScene: TGameScene;
    FRenderer: TFrameRenderer;
    FPanel: TMapForm;
    FRunning, FHaveFrame, FFresh, FFullScreen, FMarks: Boolean;
    FMapDirty, FPlayWanted, FStopWanted, FSaveWanted: Boolean;
    FScroll, FPanelViewD: Single;
    FLastSel: Integer;
    FLastUpdate, FLastSwap, FFps: Double;
    FDrag: TEdDrag;
    FDragX, FDragY: Single;          // window pixels
    FDragObj: TMapObj;
    FDragScroll: Single;
    FMouseX, FMouseY: Single;
    FShapes: TStringList;
    FTitleT: Double;
    procedure AppIdle(Sender: TObject; var Done: Boolean);
    procedure PollEvents;
    procedure KeyDown(Key: TSDL_Keycode; Mods: Word);
    procedure MouseDown(Button: Integer; X, Y: Single);
    procedure MouseMove(X, Y: Single);
    procedure MouseUp;
    procedure ToPixels(var X, Y: Single);
    function PX(D: Single): Single;
    function PY(Y: Single): Single;
    function WorldD(X: Single): Single;
    function WorldY(Y: Single): Single;
    function GetShape(const AName: string): TPCShape;
    function HitObj(X, Y: Single; out What: TEdDrag): Integer;
    function MarkRect(const O: TMapObj): TRectF;
    procedure MapChanged(Sender: TObject);
    procedure UploadFrame;
    procedure Present;
    procedure DrawMarks;
    procedure Text(X, Y: Single; const S: string; K: Single = 2);
    procedure DoSavePng;
    procedure DoSavePngTo(const F: string);
    function Playing: Boolean;
  public
    ShotFile: string;      // --shot=file.png: save one frame after a second and quit
    ShotFrames: Integer;
    constructor Create(APanel: TMapForm);
    destructor Destroy; override;
    procedure ToggleFullScreen;
    property Scene: TGameScene read FScene;
  end;

var
  EdView: TEdView;

implementation

uses
  uAudio;

function SDLErr: string;
begin
  Result := StrPas(SDL_GetError);
end;

constructor TEdView.Create(APanel: TMapForm);
var
  R: TSDL_Rect;
begin
  inherited Create;
  FPanel := APanel;
  if not SDL_Init(SDL_INIT_VIDEO) then raise Exception.Create('SDL_Init failed: ' + SDLErr);
  FWin := SDL_CreateWindow('Paper Crane Map Editor (SDL3) - live papercut view', 1120, 630,
    SDL_WINDOW_RESIZABLE or SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if FWin = nil then raise Exception.Create('SDL_CreateWindow failed: ' + SDLErr);
  if SDL_GetDisplayUsableBounds(SDL_GetPrimaryDisplay, @R) then SDL_SetWindowPosition(FWin, R.x + 20, R.y + 40);
  FRen := SDL_CreateRenderer(FWin, nil);
  if FRen = nil then raise Exception.Create('SDL_CreateRenderer failed: ' + SDLErr);
  SDL_SetRenderVSync(FRen, 1);
  FScene := TGameScene.Create;
  FRenderer := TFrameRenderer.Create(FScene, PhysicalCores, 1);
  Audio := TAudio.Create;
  FShapes := TStringList.Create;
  FShapes.OwnsObjects := True;
  FShapes.CaseSensitive := False;
  FMarks := True;
  FMapDirty := True;
  FLastSel := -2;
  FPanelViewD := -1e9;
  FPanel.OnMapChanged := @MapChanged;
  FRunning := True;
  FLastUpdate := HiResMs;
  FLastSwap := FLastUpdate;
  Application.AddOnIdleHandler(@AppIdle);
end;

destructor TEdView.Destroy;
begin
  Application.RemoveOnIdleHandler(@AppIdle);
  FPanel.OnMapChanged := nil;
  FreeAndNil(FRenderer);
  FreeAndNil(Audio);
  FreeAndNil(FScene);
  FShapes.Free;
  if FTex <> nil then SDL_DestroyTexture(FTex);
  if FRen <> nil then SDL_DestroyRenderer(FRen);
  if FWin <> nil then SDL_DestroyWindow(FWin);
  SDL_Quit;
  inherited Destroy;
end;

procedure TEdView.MapChanged(Sender: TObject);
begin
  FMapDirty := True;
end;

function TEdView.Playing: Boolean;
begin
  Result := FScene.EditorPlaying;
end;

{ ---------- coordinates: world distance / design height <-> frame pixels ---------- }

function TEdView.PX(D: Single): Single;
begin
  Result := FScene.OffX + (D - FScroll) * FScene.Scale;
end;

function TEdView.PY(Y: Single): Single;
begin
  Result := FScene.OffY + Y * FScene.Scale;
end;

function TEdView.WorldD(X: Single): Single;
begin
  Result := (X - FScene.OffX) / Max(0.01, FScene.Scale) + FScroll;
end;

function TEdView.WorldY(Y: Single): Single;
begin
  Result := (Y - FScene.OffY) / Max(0.01, FScene.Scale);
end;

procedure TEdView.ToPixels(var X, Y: Single);
var
  W, H, PW, PH: LongInt;
begin
  W := 1; H := 1; PW := 1; PH := 1;
  SDL_GetWindowSize(FWin, @W, @H);
  SDL_GetWindowSizeInPixels(FWin, @PW, @PH);
  X := X * PW / Max(1, W);
  Y := Y * PH / Max(1, H);
end;

function Snap10(V: Single; On: Boolean): Single;
begin
  if On then Result := Round(V / 10) * 10 else Result := V;
end;

function TEdView.GetShape(const AName: string): TPCShape;
var
  I: Integer;
begin
  I := FShapes.IndexOf(AName);
  if I >= 0 then Exit(TPCShape(FShapes.Objects[I]));
  Result := TPCShape.Create;
  try
    if FileExists(PCRoot + 'shapes' + PathDelim + AName) then Result.LoadFromFile(PCRoot + 'shapes' + PathDelim + AName)
    else MakeShapePreset(Result, 'Rock');
  except
    MakeShapePreset(Result, 'Rock');
  end;
  FShapes.AddObject(AName, Result);
end;

{ ---------- picking (frame pixels) ---------- }

{ the frame-pixel box of an object as the live view shows it now }
function TEdView.MarkRect(const O: TMapObj): TRectF;
var
  KX, KY, A, K: Single;
begin
  K := FScene.Scale;
  case O.Kind of
    okCloud:
      begin
        KY := O.Y + CloudOffset(O, FScroll);
        Result.Left := PX(O.D - O.W * 1.3);
        Result.Right := PX(O.D + O.W * 1.3);
        Result.Top := PY(KY - O.W * 0.8);
        Result.Bottom := PY(KY + O.W * 0.8);
      end;
    okKoi:
      begin
        KoiPos(O, FScroll, KX, KY, A);
        Result.Left := PX(KX - 50);
        Result.Right := PX(KX + 50);
        Result.Top := PY(Min(KY, MapWaterY) - 30);
        Result.Bottom := PY(Min(KY, MapWaterY) + 30);
      end;
    okPinwheel:
      begin
        Result.Left := PX(O.D - O.W);
        Result.Right := PX(O.D + O.W);
        Result.Top := PY(O.Y - O.W);
        Result.Bottom := PY(O.Y + O.W);
      end;
    okBamboo:
      begin
        Result.Left := PX(O.D - O.W);
        Result.Right := PX(O.D + O.W);
        Result.Top := PY(O.Y - 30);
        Result.Bottom := PY(MapWaterY);
      end;
  else
    begin
      Result.Left := PX(O.D) - Max(14, 40 * K);
      Result.Right := PX(O.D) + Max(14, 40 * K);
      Result.Top := PY(O.Y) - Max(14, 40 * K);
      Result.Bottom := PY(O.Y) + Max(14, 40 * K);
    end;
  end;
end;

function TEdView.HitObj(X, Y: Single; out What: TEdDrag): Integer;
var
  Bx: TRectF;
  I: Integer;
  O: TMapObj;
  K, F, LX, LY: Single;
  M: TPCMap;
begin
  M := FPanel.Map;
  K := FScene.Scale;
  What := edMove;
  I := FPanel.Sel;
  if (I >= 0) and (I <= High(M.Objs)) and (M.Objs[I].Kind in [okPillar, okSwing]) then
  begin
    O := M.Objs[I];
    if (Abs(X - PX(O.D)) <= 10) and (Abs(Y - PY(O.GapY - O.Gap / 2)) <= 10) then
    begin
      What := edGapTop;
      Exit(I);
    end;
    if (Abs(X - PX(O.D)) <= 10) and (Abs(Y - PY(O.GapY + O.Gap / 2)) <= 10) then
    begin
      What := edGapBottom;
      Exit(I);
    end;
  end;
  for I := High(M.Objs) downto 0 do
  begin
    O := M.Objs[I];
    if (O.Kind in [okLantern, okHawk, okHeart, okSlow]) and (Sqr(X - PX(O.D)) + Sqr(Y - PY(O.Y)) <= Sqr(Max(14, 42 * K))) then Exit(I);
  end;
  // clouds, pinwheels and koi where they are now, bamboo by its box
  for I := High(M.Objs) downto 0 do
  begin
    O := M.Objs[I];
    if not (O.Kind in [okCloud, okPinwheel, okKoi, okBamboo]) then Continue;
    Bx := MarkRect(O);
    if (X >= Bx.Left) and (X <= Bx.Right) and (Y >= Bx.Top) and (Y <= Bx.Bottom) then Exit(I);
  end;
  for I := High(M.Objs) downto 0 do
  begin
    O := M.Objs[I];
    if O.Kind <> okShape then Continue;
    if O.Flip then F := -1 else F := 1;
    LX := (X - PX(O.D)) / (Max(0.05, O.Scale) * K) * F;
    LY := (Y - PY(O.Y)) / (Max(0.05, O.Scale) * K);
    if GetShape(O.Shape).HitTest(LX, LY) >= 0 then Exit(I);
  end;
  for I := High(M.Objs) downto 0 do
  begin
    O := M.Objs[I];
    if (O.Kind in [okPillar, okSwing]) and (Abs(X - PX(O.D)) <= O.W * K) then
      if (O.Bottom and (Y > PY(O.GapY + O.Gap / 2))) or (O.Top and (Y < PY(O.GapY - O.Gap / 2))) or
         (Abs(X - PX(O.D)) <= 12) then Exit(I);
  end;
  What := edNone;
  Result := -1;
end;

{ ---------- mouse editing ---------- }

procedure TEdView.MouseDown(Button: Integer; X, Y: Single);
var
  What: TEdDrag;
  I: Integer;
  O: TMapObj;
  D, H: Single;
  M: TPCMap;
begin
  if Playing then
  begin
    if Button = SDL_BUTTON_LEFT then FScene.KeyInput(gkFlap);
    Exit;
  end;
  M := FPanel.Map;
  FDragX := X;
  FDragY := Y;
  if (Button = SDL_BUTTON_MIDDLE) then
  begin
    FDrag := edPan;
    FDragScroll := FScroll;
    Exit;
  end;
  if Button = SDL_BUTTON_RIGHT then
  begin
    I := HitObj(X, Y, What);
    if I >= 0 then
    begin
      FPanel.SelectObj(I);
      FPanel.DeleteSelected;
    end;
    Exit;
  end;
  if Button <> SDL_BUTTON_LEFT then Exit;
  D := Snap10(WorldD(X), FPanel.SnapOn);
  H := Snap10(WorldY(Y), FPanel.SnapOn);
  if FPanel.ToolIndex = 0 then
  begin
    I := HitObj(X, Y, What);
    FPanel.SelectObj(I);
    if I >= 0 then
    begin
      FPanel.PushUndo;
      FDrag := What;
      FDragObj := M.Objs[I];
    end
    else
    begin
      FDrag := edPan;
      FDragScroll := FScroll;
    end;
    Exit;
  end;
  FPanel.PushUndo;
  O := FPanel.MakeObj(FPanel.ToolIndex, D, H);
  M.Add(O);
  if D > M.Length_ - 200 then M.Length_ := D + 600;
  M.Sort;
  FPanel.ExternalChanged;
  for I := 0 to High(M.Objs) do
    if (M.Objs[I].D = O.D) and (M.Objs[I].Kind = O.Kind) and (M.Objs[I].Y = O.Y) then FPanel.SelectObj(I);
  FMapDirty := True;
end;

procedure TEdView.MouseMove(X, Y: Single);
var
  O: TMapObj;
  K, DD, DY: Single;
  Sn: Boolean;
  I: Integer;
begin
  FMouseX := X;
  FMouseY := Y;
  if Playing then Exit;
  K := Max(0.01, FScene.Scale);
  Sn := FPanel.SnapOn;
  case FDrag of
    edPan: FScroll := Max(-400, FDragScroll - (X - FDragX) / K);
    edMove, edGapTop, edGapBottom:
      begin
        I := FPanel.Sel;
        if (I < 0) or (I > High(FPanel.Map.Objs)) then Exit;
        O := FDragObj;
        DD := (X - FDragX) / K;
        DY := (Y - FDragY) / K;
        case FDrag of
          edMove:
            begin
              O.D := Max(0, Snap10(FDragObj.D + DD, Sn));
              if O.Kind in [okPillar, okSwing] then O.GapY := EnsureRange(Snap10(FDragObj.GapY + DY, Sn), 40, 800)
              else O.Y := Snap10(FDragObj.Y + DY, Sn);
            end;
          edGapTop:
            begin
              O.Gap := Max(60, Snap10(FDragObj.Gap - DY, Sn));
              O.GapY := FDragObj.GapY + FDragObj.Gap / 2 - O.Gap / 2;
            end;
          edGapBottom:
            begin
              O.Gap := Max(60, Snap10(FDragObj.Gap + DY, Sn));
              O.GapY := FDragObj.GapY - FDragObj.Gap / 2 + O.Gap / 2;
            end;
        end;
        FPanel.Map.Objs[I] := O;
        FMapDirty := True;
      end;
  end;
end;

procedure TEdView.MouseUp;
var
  O: TMapObj;
  I: Integer;
  M: TPCMap;
begin
  if FDrag in [edMove, edGapTop, edGapBottom] then
  begin
    M := FPanel.Map;
    I := FPanel.Sel;
    if (I >= 0) and (I <= High(M.Objs)) then
    begin
      O := M.Objs[I];
      M.Sort;
      FPanel.ExternalChanged;
      for I := 0 to High(M.Objs) do
        if (M.Objs[I].D = O.D) and (M.Objs[I].Kind = O.Kind) and (M.Objs[I].Y = O.Y) and
           (M.Objs[I].GapY = O.GapY) then FPanel.SelectObj(I);
    end;
    FMapDirty := True;
  end;
  FDrag := edNone;
end;

procedure TEdView.KeyDown(Key: TSDL_Keycode; Mods: Word);
var
  Ctrl: Boolean;
begin
  Ctrl := (Mods and SDL_KMOD_CTRL) <> 0;
  if Playing then
  begin
    case Key of
      SDLK_SPACE, SDLK_UP, SDLK_W, SDLK_RETURN: FScene.KeyInput(gkFlap);
      SDLK_ESCAPE, SDLK_F5: FStopWanted := True;
      SDLK_F11: ToggleFullScreen;
    end;
    Exit;
  end;
  case Key of
    SDLK_LEFT, SDLK_KP_4: FScroll := Max(-400, FScroll - 240);
    SDLK_RIGHT, SDLK_KP_6: FScroll := FScroll + 240;
    SDLK_HOME: FScroll := 0;
    SDLK_END: FScroll := Max(0, FPanel.Map.Length_ - 1200);
    SDLK_F5: FPlayWanted := True;
    SDLK_F11: ToggleFullScreen;
    SDLK_TAB: FMarks := not FMarks;
    SDLK_DELETE: FPanel.DeleteSelected;
    SDLK_ESCAPE: FPanel.SelectObj(-1);
    SDLK_D: if Ctrl then FPanel.CopySelected;
    SDLK_Z: if Ctrl then FPanel.Undo;
    SDLK_S: if Ctrl then FPanel.Save else FSaveWanted := True;
  end;
end;

procedure TEdView.PollEvents;
var
  E: TSDL_Event;
  X, Y: Single;
begin
  while SDL_PollEvent(@E) do
    case E._type of
      SDL_EVENT_QUIT, SDL_EVENT_WINDOW_CLOSE_REQUESTED:
        begin
          FRunning := False;
          FPanel.Close;
        end;
      SDL_EVENT_KEY_DOWN:
        if not E.key._repeat or (E.key.key = SDLK_LEFT) or (E.key.key = SDLK_RIGHT) or (E.key.key = SDLK_KP_4) or (E.key.key = SDLK_KP_6) then KeyDown(E.key.key, E.key.mod_);
      SDL_EVENT_MOUSE_BUTTON_DOWN:
        begin
          X := E.button.x;
          Y := E.button.y;
          ToPixels(X, Y);
          MouseDown(E.button.button, X, Y);
        end;
      SDL_EVENT_MOUSE_BUTTON_UP: MouseUp;
      SDL_EVENT_MOUSE_MOTION:
        begin
          X := E.motion.x;
          Y := E.motion.y;
          ToPixels(X, Y);
          MouseMove(X, Y);
        end;
      SDL_EVENT_MOUSE_WHEEL:
        if not Playing then FScroll := Max(-400, FScroll - E.wheel.y * 160);
    end;
end;

{ ---------- frame ---------- }

procedure TEdView.UploadFrame;
var
  I, W, H: Integer;
  B: TBGRABitmap;
  Rc: TSDL_Rect;
  Fmt: TSDL_PixelFormat;
begin
  W := FRenderer.Width;
  H := FRenderer.Height;
  if (FTex = nil) or (FTexW <> W) or (FTexH <> H) then
  begin
    if FTex <> nil then SDL_DestroyTexture(FTex);
    if TBGRAPixel_RGBAOrder then Fmt := SDL_PIXELFORMAT_ABGR8888 else Fmt := SDL_PIXELFORMAT_ARGB8888;
    FTex := SDL_CreateTexture(FRen, Fmt, SDL_TEXTUREACCESS_STREAMING, W, H);
    if FTex = nil then Exit;
    SDL_SetTextureScaleMode(FTex, SDL_SCALEMODE_NEAREST);
    SDL_SetTextureBlendMode(FTex, SDL_BLENDMODE_NONE);
    FTexW := W;
    FTexH := H;
  end;
  for I := 0 to FRenderer.BandCount - 1 do
  begin
    B := FRenderer.Bands[I];
    FFlipV := B.LineOrder = riloBottomToTop;
    Rc.x := 0;
    Rc.w := W;
    Rc.h := B.Height;
    if FFlipV then Rc.y := H - FRenderer.BandTops[I] - B.Height else Rc.y := FRenderer.BandTops[I];
    SDL_UpdateTexture(FTex, @Rc, B.Data, W * SizeOf(TBGRAPixel));
  end;
end;

procedure TEdView.Text(X, Y: Single; const S: string; K: Single);
var
  R: TSDL_FRect;
begin
  K := Max(1, Round(K * FScene.Scale * 2) / 2);
  SDL_SetRenderScale(FRen, K, K);
  R.x := X / K - 2;
  R.y := Y / K - 2;
  R.w := Length(S) * 8 + 4;
  R.h := 12;
  SDL_SetRenderDrawColor(FRen, 20, 16, 12, 150);
  SDL_RenderFillRect(FRen, @R);
  SDL_SetRenderDrawColor(FRen, 255, 246, 225, 255);
  SDL_RenderDebugText(FRen, X / K, Y / K, PChar(S));
  SDL_SetRenderScale(FRen, 1, 1);
end;

procedure Box(Ren: PSDL_Renderer; X0, Y0, X1, Y1: Single);
var
  R: TSDL_FRect;
begin
  R.x := Min(X0, X1);
  R.y := Min(Y0, Y1);
  R.w := Abs(X1 - X0);
  R.h := Abs(Y1 - Y0);
  SDL_RenderRect(Ren, @R);
end;

procedure Dot(Ren: PSDL_Renderer; X, Y, S: Single);
var
  R: TSDL_FRect;
begin
  R.x := X - S;
  R.y := Y - S;
  R.w := S * 2;
  R.h := S * 2;
  SDL_RenderFillRect(Ren, @R);
end;

procedure TEdView.DrawMarks;
const
  ToolNames: array[0..11] of string = ('Select', 'Pillar', 'Lantern', 'Hawk', 'Shape', 'Heart', 'Slow', 'Swing',
    'Bamboo', 'Cloud', 'Pinwheel', 'Koi');
var
  M: TPCMap;
  I, W, H, Sel: Integer;
  O: TMapObj;
  X, Y, K, T: Single;
  Bd: TRectF;
  S: string;
begin
  M := FPanel.Map;
  W := FRenderer.Width;
  H := FRenderer.Height;
  K := FScene.Scale;
  SDL_SetRenderDrawBlendMode(FRen, SDL_BLENDMODE_BLEND);
  if Playing then
  begin
    Text(12, FRenderer.Height - 30, Format('TEST FLIGHT  %d m   Space flap - Esc back to the editor   %.0f fps', [Round((FScene.Scroll + CraneX) / 10), FFps]));
    Exit;
  end;
  if not FMarks then
  begin
    Text(12, FRenderer.Height - 30, 'Tab: show the editing marks');
    Exit;
  end;
  // metre marks along the river surface
  X := Floor(WorldD(0) / 100) * 100;
  while PX(X) < W do
  begin
    SDL_SetRenderDrawColor(FRen, 255, 255, 255, IfThen(Round(X) mod 1000 = 0, 230, 110));
    SDL_RenderLine(FRen, PX(X), PY(MapWaterY), PX(X), PY(MapWaterY) + IfThen(Round(X) mod 1000 = 0, 18, 8));
    if Round(X) mod 1000 = 0 then Text(PX(X) + 4, PY(MapWaterY) + 22, Format('%d m', [Round(X / 10)]), 1.5);
    X := X + 100;
  end;
  // start line (the crane's place) and the finish
  SDL_SetRenderDrawColor(FRen, 60, 200, 80, 200);
  SDL_RenderLine(FRen, PX(CraneX), PY(0), PX(CraneX), PY(MapWaterY));
  SDL_SetRenderDrawColor(FRen, 230, 40, 30, 230);
  for I := -1 to 1 do SDL_RenderLine(FRen, PX(M.Length_) + I, PY(0), PX(M.Length_) + I, PY(MapWaterY));
  Text(PX(M.Length_) + 6, PY(20), 'FINISH', 2);
  Sel := FPanel.Sel;
  for I := 0 to High(M.Objs) do
  begin
    O := M.Objs[I];
    X := PX(O.D);
    if (X < -300 * K) or (X > W + 300 * K) then Continue;
    case O.Kind of
      okHeart, okSlow, okBamboo, okCloud, okPinwheel, okKoi:
        if I = Sel then
        begin
          SDL_SetRenderDrawColor(FRen, 255, 230, 60, 255);
          Bd := MarkRect(O);
          Box(FRen, Bd.Left, Bd.Top, Bd.Right, Bd.Bottom);
        end;
      okPillar, okSwing:
        begin
          SDL_SetRenderDrawColor(FRen, 255, 255, 255, 120);
          SDL_RenderLine(FRen, X, PY(O.GapY - O.Gap / 2), X, PY(O.GapY + O.Gap / 2));
          if I = Sel then
          begin
            SDL_SetRenderDrawColor(FRen, 255, 230, 60, 255);
            Dot(FRen, X, PY(O.GapY - O.Gap / 2), 7);
            Dot(FRen, X, PY(O.GapY + O.Gap / 2), 7);
            Box(FRen, X - O.W * K, PY(0), X + O.W * K, PY(MapWaterY));
            Text(X + O.W * K + 6, PY(O.GapY) - 8, Format('gap %d', [Round(O.Gap)]), 1.5);
          end;
        end;
      okLantern, okHawk:
        if I = Sel then
        begin
          SDL_SetRenderDrawColor(FRen, 255, 230, 60, 255);
          T := Max(14, 40 * K);
          Box(FRen, X - T, PY(O.Y) - T, X + T, PY(O.Y) + T);
        end;
      okShape:
        begin
          Bd := GetShape(O.Shape).Bounds;
          if O.Flip then
          begin
            T := Bd.Left;
            Bd.Left := -Bd.Right;
            Bd.Right := -T;
          end;
          T := Max(0.05, O.Scale) * K;
          if I = Sel then SDL_SetRenderDrawColor(FRen, 255, 230, 60, 255)
          else if O.Solid then SDL_SetRenderDrawColor(FRen, 230, 60, 40, 140)
          else SDL_SetRenderDrawColor(FRen, 255, 255, 255, 70);
          Box(FRen, X + Bd.Left * T, PY(O.Y) + Bd.Top * T, X + Bd.Right * T, PY(O.Y) + Bd.Bottom * T);
          SDL_RenderLine(FRen, X - 6, PY(O.Y), X + 6, PY(O.Y));
          SDL_RenderLine(FRen, X, PY(O.Y) - 6, X, PY(O.Y) + 6);
        end;
    end;
  end;
  // the tool ghost
  if (FPanel.ToolIndex > 0) and (FDrag = edNone) then
  begin
    SDL_SetRenderDrawColor(FRen, 255, 255, 255, 200);
    Box(FRen, FMouseX - 14, FMouseY - 14, FMouseX + 14, FMouseY + 14);
    Text(FMouseX + 18, FMouseY - 6, ToolNames[EnsureRange(FPanel.ToolIndex, 0, 11)], 1.5);
  end;
  S := Format('%s   tool %s   %d m   height %d   view %d-%d m   %.0f fps', [M.Name,
    ToolNames[EnsureRange(FPanel.ToolIndex, 0, 11)], Round(WorldD(FMouseX) / 10), Round(WorldY(FMouseY)),
    Round(WorldD(0) / 10), Round(WorldD(W) / 10), FFps]);
  Text(12, H - 30, S, 1.5);
  if HiResMs - FTitleT < 8000 then
    Text(12, H - 52, 'F5 fly from here  |  drag: move / scroll  |  right click: delete  |  wheel, arrows: scroll  |  1-5 tools in the panel', 1.5);
end;

procedure TEdView.Present;
var
  W, H: LongInt;
  Dst: TSDL_FRect;
begin
  if FTex = nil then
  begin
    SDL_SetRenderDrawColor(FRen, 244, 238, 222, 255);
    SDL_RenderClear(FRen);
  end
  else
  begin
    W := 0;
    H := 0;
    SDL_GetCurrentRenderOutputSize(FRen, @W, @H);
    Dst.x := 0;
    Dst.y := 0;
    Dst.w := W;
    Dst.h := H;
    if FFlipV then SDL_RenderTextureRotated(FRen, FTex, nil, @Dst, 0, nil, SDL_FLIP_VERTICAL)
    else SDL_RenderTexture(FRen, FTex, nil, @Dst);
    DrawMarks;
  end;
  SDL_RenderPresent(FRen);
end;

procedure TEdView.DoSavePngTo(const F: string);
var
  B: TBGRABitmap;
begin
  B := TBGRABitmap.Create(1, 1);
  try
    FRenderer.Assemble(B);
    B.SaveToFile(F);
  finally
    B.Free;
  end;
end;

procedure TEdView.DoSavePng;
begin
  FSaveWanted := False;
  DoSavePngTo(ExtractFilePath(ParamStr(0)) + 'mapedit_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.png');
end;

procedure TEdView.ToggleFullScreen;
begin
  FFullScreen := not FFullScreen;
  SDL_SetWindowFullscreen(FWin, FFullScreen);
end;

procedure TEdView.AppIdle(Sender: TObject; var Done: Boolean);
var
  Now, DT, Interval: Double;
  W, H: LongInt;
  I: Integer;
  M: TPCMap;
begin
  Done := False;
  if not FRunning then
  begin
    Done := True;
    Exit;
  end;
  if FTitleT = 0 then FTitleT := HiResMs;
  PollEvents;
  if not FRunning then Exit;
  if (SDL_GetWindowFlags(FWin) and SDL_WINDOW_MINIMIZED) <> 0 then
  begin
    Sleep(15);
    Exit;
  end;
  // 1. the frame the workers made during the last vsync wait
  if FRenderer.Rendering then
  begin
    FRenderer.Wait;
    FHaveFrame := True;
    FFresh := True;
  end;
  // 2. the workers are idle: the scene may change now
  W := 0;
  H := 0;
  SDL_GetWindowSizeInPixels(FWin, @W, @H);
  if (W >= 16) and (H >= 16) and ((W <> FRenderer.Width) or (H <> FRenderer.Height)) then
  begin
    FRenderer.SetSize(W, H);
    FHaveFrame := False;
  end;
  M := FPanel.Map;
  if FStopWanted then
  begin
    FStopWanted := False;
    FScene.EditorStop;
    FMapDirty := True;
  end;
  if FPlayWanted then
  begin
    FPlayWanted := False;
    FScene.EditorPlayFrom(M, FScroll + CraneX);
  end
  else if Playing then
    FScroll := FScene.Scroll
  else
  begin
    // the panel scrolled its overview or picked an object: follow it
    if Abs(FPanel.ViewD - FPanelViewD) > 0.5 then FScroll := FPanel.ViewD;
    I := FPanel.Sel;
    if (I <> FLastSel) and (I >= 0) and (I <= High(M.Objs)) then
      if (PX(M.Objs[I].D) < 0) or (PX(M.Objs[I].D) > FRenderer.Width) then
        FScroll := M.Objs[I].D - (FRenderer.Width / 2 - FScene.OffX) / Max(0.01, FScene.Scale);
    FLastSel := I;
    if FMapDirty or not FScene.EditMode then
    begin
      FMapDirty := False;
      FScene.EditorShowMap(M);
    end;
    FScene.Scroll := FScroll;
    FPanel.ViewD := FScroll;
    FPanelViewD := FPanel.ViewD;
  end;
  if not FHaveFrame then
  begin
    FScene.Prepare;
    FRenderer.Render;
    FHaveFrame := True;
    FFresh := True;
  end;
  if FSaveWanted then DoSavePng;
  if ShotFile <> '' then
  begin
    Inc(ShotFrames);
    if ShotFrames = 90 then
    begin
      FRenderer.Wait;
      W := 0;
      DoSavePngTo(ShotFile);
      FRunning := False;
      Application.Terminate;
      Exit;
    end;
  end;
  if FFresh then UploadFrame;
  FFresh := False;
  // 3. animate and start the next frame on all cores
  Now := HiResMs;
  DT := Min(0.1, (Now - FLastUpdate) / 1000);
  FLastUpdate := Now;
  FScene.Update(DT);
  FScene.Prepare;
  FRenderer.Start;
  // 4. present (vsync)
  Present;
  Now := HiResMs;
  Interval := Now - FLastSwap;
  FLastSwap := Now;
  if Interval > 0 then FFps := FFps * 0.93 + (1000 / Interval) * 0.07;
end;

end.
