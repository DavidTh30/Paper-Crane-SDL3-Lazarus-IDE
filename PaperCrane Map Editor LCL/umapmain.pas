unit uMapMain;

{ Paper Crane Custom Map Editor (LCL, no SDL3).

  A side view of the river: across = distance (10 design px = 1 m), down = the
  height on the 1600 x 900 design screen (the river surface is at 826). The
  crane flies at a height chosen by the player; the obstacles stand at their
  distance.

  Tools: Select (click an object, drag it; drag the round handles of a pillar
  to change its gap), Pillar, Lantern, Hawk, Shape (click to place; the shape
  file comes from the combo, the game's shapes folder). Right click deletes.
  Wheel scrolls, Ctrl+wheel zooms. Del deletes, Ctrl+Z undoes, Ctrl+D copies.

  The map settings (name, author, season, time of day, lives, speed, length,
  music) and the selected object's properties are edited on the right. Fill
  random adds generated obstacles from the view to the finish; Validate lists
  problems; Test in game saves and starts PaperCrane.exe --map file. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Dialogs, Spin,
  LCLType, Process, BGRABitmap, BGRABitmapTypes, uPCMap, uPCShape;

type
  TTool = (tlSelect, tlPillar, tlLantern, tlHawk, tlShape, tlHeart, tlSlow, tlSwing, tlBamboo, tlCloud, tlPinwheel,
    tlKoi);
  TDragWhat = (dwNone, dwMove, dwGapTop, dwGapBottom, dwPan);

  { TMapForm }

  TMapForm = class(TForm)
  private
    FMap: TPCMap;
    FOnMapChanged: TNotifyEvent;
    FUndo: TList;
    FDirty, FUpdating: Boolean;
    FTool: TTool;
    FSel: Integer;
    FViewD, FZoom: Single;            // world distance at the left edge, x zoom
    FDrag: TDragWhat;
    FDragX, FDragY: Integer;
    FDragObj: TMapObj;
    FDragView: Single;
    FMouse: TPoint;
    FShapes: TStringList;             // shape file name -> TPCShape
    FView: TPaintBox;
    FScroll: TScrollBar;
    FObjList: TListBox;
    FStatus: TStatusBar;
    FToolBtns: array[TTool] of TToggleBox;
    FShapeCombo: TComboBox;
    // map settings
    FName, FAuthor: TEdit;
    FDesc: TMemo;
    FSeason, FTime, FMusic, FTheme: TComboBox;
    FLives: TSpinEdit;
    FSpeedA, FSpeedB, FLength: TFloatSpinEdit;
    // object properties
    FKindLbl: TLabel;
    FPD, FPY, FPW, FPGapY, FPGap, FPScale, FPAmp: TFloatSpinEdit;
    FPTop, FPBottom, FPSolid, FPFlip, FSnap: TCheckBox;
    FPShape: TComboBox;
    procedure BuildUI;
    function GameDir: string;
    function AddButton(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TButton;
    function YK: Single;
    function XK: Single;
    function SX(D: Single): Single;
    function SY(Y: Single): Single;
    function WD(X: Single): Single;
    function WY(Y: Single): Single;
    function GetShape(const AName: string): TPCShape;
    procedure LoadShapeList;
    procedure LoadMusicList;
    function HitObj(X, Y: Integer; out What: TDragWhat): Integer;
    procedure SetViewD(V: Single);
    procedure Changed;
    procedure ObjsToList;
    procedure MapToControls;
    procedure SelToControls;
    procedure UpdateCaption;
    procedure UpdateScroll;
    procedure SetTool(T: TTool);
    procedure ViewPaint(Sender: TObject);
    procedure ViewDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ViewUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
      var Handled: Boolean);
    procedure ScrollChange(Sender: TObject);
    procedure ToolClick(Sender: TObject);
    procedure ObjClick(Sender: TObject);
    procedure MapEdit(Sender: TObject);
    procedure PropEdit(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure ValidateClick(Sender: TObject);
    procedure RandomClick(Sender: TObject);
    procedure TestClick(Sender: TObject);
    procedure PngClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure DeleteSel;
    procedure CopySel;
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure RenderTo(B: TBGRABitmap; AViewD, AXK, AYK: Single; Handles: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    { for the SDL3 editor: it edits the same map through these }
    procedure PushUndo;
    procedure SelectObj(I: Integer);
    procedure ExternalChanged;
    function ToolIndex: Integer;
    function ShapeName: string;
    function SnapOn: Boolean;
    procedure Undo;
    procedure Save;
    procedure DeleteSelected;
    procedure CopySelected;
    function MakeObj(ATool: Integer; D, H: Single): TMapObj;   // a new object for a tool
    property Map: TPCMap read FMap;
    property Sel: Integer read FSel;
    property ViewD: Single read FViewD write SetViewD;
    property OnMapChanged: TNotifyEvent read FOnMapChanged write FOnMapChanged;
    destructor Destroy; override;
    procedure OpenFile(const AFile: string);
    procedure ExportPng(const AFile: string);
    procedure SampleMap;
  end;

var
  MapForm: TMapForm;

implementation

var
  GSeq: Integer = 0;

{ a growing position, so alTop / alLeft controls line up in creation order }
function NextSeq: Integer;
begin
  Inc(GSeq, 4);
  Result := GSeq;
end;

const
  ToolNames: array[TTool] of string = ('Select', 'Pillar', 'Lantern', 'Hawk', 'Shape', 'Heart', 'Slow',
    'Swing', 'Bamboo', 'Cloud', 'Pinwheel', 'Koi');
  ToolKinds: array[TTool] of TMapObjKind = (okPillar, okPillar, okLantern, okHawk, okShape, okHeart, okSlow, okSwing,
    okBamboo, okCloud, okPinwheel, okKoi);
  PillarKinds = [okPillar, okSwing];
  SeasonItems: array[0..4] of string = ('Player''s choice', 'Summer', 'Rainy', 'Autumn', 'Winter');
  TimeItems: array[0..3] of string = ('Player''s choice', 'Morning', 'Day', 'Night');
  BuiltinTracks: array[0..6] of string = ('Li River Morning', 'Paper Wings', 'Lantern Festival', 'Moonlit Pagoda',
    'Rain on Bamboo', 'Autumn Wind', 'Snow over Karst');

constructor TMapForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'Paper Crane Map Editor';
  Width := Scale96ToForm(1400);
  Height := Scale96ToForm(820);
  Position := poScreenCenter;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  OnCloseQuery := @FormCloseQuery;
  FMap := TPCMap.Create;
  FUndo := TList.Create;
  FShapes := TStringList.Create;
  FShapes.OwnsObjects := True;
  FShapes.CaseSensitive := False;
  FZoom := 1;
  FSel := -1;
  BuildUI;
  LoadShapeList;
  LoadMusicList;
  SampleMap;
  FDirty := False;
  SetTool(tlSelect);
  MapToControls;
  Changed;
  FDirty := False;
  UpdateCaption;
end;

destructor TMapForm.Destroy;
var
  I: Integer;
begin
  for I := 0 to FUndo.Count - 1 do TPCMap(FUndo[I]).Free;
  FUndo.Free;
  FShapes.Free;
  FMap.Free;
  inherited Destroy;
end;

function TMapForm.GameDir: string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'Paper Crane Papercut Game SDL3') +
    PathDelim;
end;

{ a short starter map, so a new map is not an empty river }
procedure TMapForm.SampleMap;
begin
  FMap.Clear;
  FMap.Name := 'New map';
  FMap.Length_ := 6000;
  FMap.Add(NewPillar(1400, 70, 420, 330));
  FMap.Add(NewItem(okLantern, 1700, 400));
  FMap.Add(NewPillar(2100, 80, 360, 300));
  FMap.Add(NewItem(okLantern, 2500, 520));
  FMap.Add(NewPillar(2900, 75, 480, 300));
  FMap.Add(NewItem(okHawk, 3500, 300));
  FMap.Add(NewPillar(4100, 85, 400, 280));
  FMap.Add(NewItem(okLantern, 4600, 380));
  FMap.Add(NewPillar(5200, 80, 450, 270));
  FMap.Sort;
  FMap.FileName := '';
  FSel := -1;
end;

function TMapForm.AddButton(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.AutoSize := True;
  Result.Align := alLeft;
  Result.Left := NextSeq;
  Result.BorderSpacing.Around := 3;
  Result.OnClick := AHandler;
end;

procedure TMapForm.BuildUI;
var
  Bar, Tools, Side, Box: TPanel;
  T: TTool;
  Grp: TGroupBox;
  I: Integer;

  function Lbl(AParent: TWinControl; const C: string): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := AParent;
    Result.Caption := C;
    Result.Align := alTop;
    Result.Top := NextSeq;
    Result.BorderSpacing.Left := 6;
    Result.BorderSpacing.Top := 3;
  end;

  function Edit(AParent: TWinControl; const C: string): TEdit;
  begin
    Lbl(AParent, C);
    Result := TEdit.Create(Self);
    Result.Parent := AParent;
    Result.Align := alTop;
    Result.Top := NextSeq;
    Result.BorderSpacing.Left := 4;
    Result.BorderSpacing.Right := 4;
    Result.OnChange := @MapEdit;
  end;

  function Combo(AParent: TWinControl; const C: string; const Items: array of string; H: TNotifyEvent): TComboBox;
  var
    S: string;
  begin
    Lbl(AParent, C);
    Result := TComboBox.Create(Self);
    Result.Parent := AParent;
    Result.Style := csDropDownList;
    for S in Items do Result.Items.Add(S);
    Result.Align := alTop;
    Result.Top := NextSeq;
    Result.BorderSpacing.Left := 4;
    Result.BorderSpacing.Right := 4;
    Result.OnChange := H;
  end;

  function Num(AParent: TWinControl; const C: string; AMin, AMax, AInc: Double; ADec: Integer;
    H: TNotifyEvent): TFloatSpinEdit;
  var
    P: TPanel;
    L: TLabel;
  begin
    P := TPanel.Create(Self);
    P.Parent := AParent;
    P.Align := alTop;
    P.Top := NextSeq;
    P.Height := Scale96ToForm(27);
    P.BevelOuter := bvNone;
    L := TLabel.Create(Self);
    L.Parent := P;
    L.Caption := C;
    L.Align := alLeft;
    L.Width := Scale96ToForm(120);
    L.AutoSize := False;
    L.Layout := tlCenter;
    L.BorderSpacing.Left := 6;
    Result := TFloatSpinEdit.Create(Self);
    Result.Parent := P;
    Result.Align := alClient;
    Result.BorderSpacing.Around := 2;
    Result.MinValue := AMin;
    Result.MaxValue := AMax;
    Result.Increment := AInc;
    Result.DecimalPlaces := ADec;
    Result.OnChange := H;
  end;

  function Chk(AParent: TWinControl; const C: string): TCheckBox;
  begin
    Result := TCheckBox.Create(Self);
    Result.Parent := AParent;
    Result.Caption := C;
    Result.Align := alTop;
    Result.Top := NextSeq;
    Result.BorderSpacing.Left := 6;
    Result.OnClick := @PropEdit;
  end;

begin
  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;

  Bar := TPanel.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := Scale96ToForm(38);
  Bar.BevelOuter := bvNone;
  AddButton(Bar, 'New', @NewClick);
  AddButton(Bar, 'Open...', @OpenClick);
  AddButton(Bar, 'Save', @SaveClick);
  AddButton(Bar, 'Save as...', @SaveAsClick);
  AddButton(Bar, 'Undo', @UndoClick);
  AddButton(Bar, 'Validate', @ValidateClick);
  AddButton(Bar, 'Fill random from view', @RandomClick);
  AddButton(Bar, 'Export PNG...', @PngClick);
  AddButton(Bar, '>  Test in game', @TestClick);

  Tools := TPanel.Create(Self);
  Tools.Parent := Self;
  Tools.Align := alTop;
  Tools.Top := 100;
  Tools.Height := Scale96ToForm(36);
  Tools.BevelOuter := bvNone;
  for T := Low(TTool) to High(TTool) do
  begin
    FToolBtns[T] := TToggleBox.Create(Self);
    FToolBtns[T].Parent := Tools;
    if Ord(T) < 9 then FToolBtns[T].Caption := Format('%d %s', [Ord(T) + 1, ToolNames[T]])
    else if Ord(T) = 9 then FToolBtns[T].Caption := '0 ' + ToolNames[T]
    else FToolBtns[T].Caption := ToolNames[T];
    FToolBtns[T].Align := alLeft;
    FToolBtns[T].Left := 1000 + Ord(T);
    FToolBtns[T].Width := Scale96ToForm(78);
    FToolBtns[T].BorderSpacing.Around := 3;
    FToolBtns[T].Tag := Ord(T);
    FToolBtns[T].OnClick := @ToolClick;
  end;
  FShapeCombo := TComboBox.Create(Self);
  FShapeCombo.Parent := Tools;
  FShapeCombo.Style := csDropDownList;
  FShapeCombo.Align := alLeft;
  FShapeCombo.Left := 2000;
  FShapeCombo.Width := Scale96ToForm(170);
  FShapeCombo.BorderSpacing.Around := 5;
  FSnap := TCheckBox.Create(Self);
  FSnap.Parent := Tools;
  FSnap.Caption := 'Snap (1 m / 10 px)';
  FSnap.Checked := True;
  FSnap.Align := alLeft;
  FSnap.Left := 3000;
  FSnap.BorderSpacing.Left := 10;

  Side := TPanel.Create(Self);
  Side.Parent := Self;
  Side.Align := alRight;
  Side.Width := Scale96ToForm(560);
  Side.BevelOuter := bvNone;

  // map settings column
  Grp := TGroupBox.Create(Self);
  Grp.Parent := Side;
  Grp.Caption := 'Map';
  Grp.Align := alLeft;
  Grp.Width := Scale96ToForm(275);
  Grp.BorderSpacing.Around := 3;
  FName := Edit(Grp, 'Name');
  FAuthor := Edit(Grp, 'Author');
  Lbl(Grp, 'Description');
  FDesc := TMemo.Create(Self);
  FDesc.Parent := Grp;
  FDesc.Align := alTop;
  FDesc.Top := NextSeq;
  FDesc.Height := Scale96ToForm(50);
  FDesc.BorderSpacing.Left := 4;
  FDesc.BorderSpacing.Right := 4;
  FDesc.OnChange := @MapEdit;
  FSeason := Combo(Grp, 'Season', SeasonItems, @MapEdit);
  FTime := Combo(Grp, 'Time of day', TimeItems, @MapEdit);
  FTheme := Combo(Grp, 'Background', [], @MapEdit);
  FTheme.Items.Add('(player''s setting)');
  for I := 0 to MapThemeCount - 1 do FTheme.Items.Add(MapThemeNames[I]);
  FMusic := Combo(Grp, 'Music', [], @MapEdit);
  Lbl(Grp, 'Lives (0 = by difficulty)');
  FLives := TSpinEdit.Create(Self);
  FLives.Parent := Grp;
  FLives.Align := alTop;
  FLives.Top := NextSeq;
  FLives.MinValue := 0;
  FLives.MaxValue := MaxHearts;
  FLives.BorderSpacing.Left := 4;
  FLives.BorderSpacing.Right := 4;
  FLives.OnChange := @MapEdit;
  FSpeedA := Num(Grp, 'Speed at start', 100, 700, 10, 0, @MapEdit);
  FSpeedB := Num(Grp, 'Speed at finish', 100, 700, 10, 0, @MapEdit);
  FLength := Num(Grp, 'Length (m)', 100, 10000, 50, 0, @MapEdit);

  // object column
  Box := TPanel.Create(Self);
  Box.Parent := Side;
  Box.Align := alClient;
  Box.BevelOuter := bvNone;
  Grp := TGroupBox.Create(Self);
  Grp.Parent := Box;
  Grp.Caption := 'Selected object';
  Grp.Align := alTop;
  Grp.Height := Scale96ToForm(425);
  Grp.BorderSpacing.Around := 3;
  FKindLbl := Lbl(Grp, '(nothing selected)');
  FKindLbl.Font.Style := [fsBold];
  FPD := Num(Grp, 'Distance (m)', 0, 10000, 1, 1, @PropEdit);
  FPY := Num(Grp, 'Height (px)', -200, 900, 10, 0, @PropEdit);
  FPW := Num(Grp, 'Half width (px)', 20, 300, 5, 0, @PropEdit);
  FPGapY := Num(Grp, 'Gap centre (px)', 40, 820, 10, 0, @PropEdit);
  FPGap := Num(Grp, 'Gap size (px)', 60, 800, 10, 0, @PropEdit);
  FPAmp := Num(Grp, 'Moves up / down (px)', 0, 400, 10, 0, @PropEdit);
  FPTop := Chk(Grp, 'Hanging pillar (top)');
  FPBottom := Chk(Grp, 'Rock (bottom)');
  Lbl(Grp, 'Shape file');
  FPShape := TComboBox.Create(Self);
  FPShape.Parent := Grp;
  FPShape.Style := csDropDownList;
  FPShape.Align := alTop;
  FPShape.Top := NextSeq;
  FPShape.BorderSpacing.Left := 4;
  FPShape.BorderSpacing.Right := 4;
  FPShape.OnChange := @PropEdit;
  FPScale := Num(Grp, 'Scale', 0.1, 10, 0.1, 2, @PropEdit);
  FPSolid := Chk(Grp, 'Solid (the crane hits it)');
  FPFlip := Chk(Grp, 'Mirrored');
  Lbl(Box, 'Objects (by distance)');
  FObjList := TListBox.Create(Self);
  FObjList.Parent := Box;
  FObjList.Align := alClient;
  FObjList.BorderSpacing.Around := 3;
  FObjList.OnClick := @ObjClick;

  FScroll := TScrollBar.Create(Self);
  FScroll.Parent := Self;
  FScroll.Kind := sbHorizontal;
  FScroll.Align := alBottom;
  FScroll.OnChange := @ScrollChange;

  FView := TPaintBox.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.OnPaint := @ViewPaint;
  FView.OnMouseDown := @ViewDown;
  FView.OnMouseMove := @ViewMove;
  FView.OnMouseUp := @ViewUp;
  FView.OnMouseWheel := @ViewWheel;


end;

procedure TMapForm.LoadShapeList;
var
  SR: TSearchRec;
  S: string;
begin
  FShapeCombo.Items.Clear;
  FPShape.Items.Clear;
  if FindFirst(GameDir + 'shapes' + PathDelim + '*.pcshape', faAnyFile, SR) = 0 then
  begin
    repeat
      FShapeCombo.Items.Add(SR.Name);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  if FShapeCombo.Items.Count = 0 then FShapeCombo.Items.Add('(no shapes - make some in the Shape Editor)');
  for S in FShapeCombo.Items do FPShape.Items.Add(S);
  FShapeCombo.ItemIndex := 0;
end;

procedure TMapForm.LoadMusicList;
var
  SR: TSearchRec;
  I: Integer;
begin
  FMusic.Items.Clear;
  FMusic.Items.Add('(player''s music setting)');
  for I := 0 to 6 do FMusic.Items.Add('builtin:' + IntToStr(I) + '  ' + BuiltinTracks[I]);
  if FindFirst(GameDir + 'music' + PathDelim + '*.pcmusic', faAnyFile, SR) = 0 then
  begin
    repeat
      FMusic.Items.Add(SR.Name);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
end;

function TMapForm.GetShape(const AName: string): TPCShape;
var
  I: Integer;
begin
  I := FShapes.IndexOf(AName);
  if I >= 0 then Exit(TPCShape(FShapes.Objects[I]));
  Result := TPCShape.Create;
  try
    if FileExists(GameDir + 'shapes' + PathDelim + AName) then
      Result.LoadFromFile(GameDir + 'shapes' + PathDelim + AName)
    else MakeShapePreset(Result, 'Rock');
  except
    MakeShapePreset(Result, 'Rock');
  end;
  FShapes.AddObject(AName, Result);
end;

{ ---------- view transform ---------- }

function TMapForm.YK: Single;
begin
  Result := Max(1, FView.Height) / MapDesignH;
end;

function TMapForm.XK: Single;
begin
  Result := YK * FZoom;
end;

function TMapForm.SX(D: Single): Single;
begin
  Result := (D - FViewD) * XK;
end;

function TMapForm.SY(Y: Single): Single;
begin
  Result := Y * YK;
end;

function TMapForm.WD(X: Single): Single;
begin
  Result := X / XK + FViewD;
end;

function TMapForm.WY(Y: Single): Single;
begin
  Result := Y / YK;
end;

function Snap10(V: Single; On: Boolean): Single;
begin
  if On then Result := Round(V / 10) * 10 else Result := V;
end;

{ ---------- drawing ---------- }

procedure TMapForm.RenderTo(B: TBGRABitmap; AViewD, AXK, AYK: Single; Handles: Boolean);
const
  BladeCols: array[0..3] of TBGRAPixel = ((blue: 46; green: 64; red: 216; alpha: 255), (blue: 48; green: 176; red: 240;
    alpha: 255), (blue: 192; green: 120; red: 58; alpha: 255), (blue: 74; green: 154; red: 78; alpha: 255));
var
  W, H, I, K, Season: Integer;
  X, Y, D, T, F: Single;
  Sky1, Sky2, Stone, StoneD, Water: TBGRAPixel;
  O: TMapObj;
  Sh: TPCShape;
  Pts: array of TPointF;
  R: TRectF;

  function PX(DD: Single): Single;
  begin
    Result := (DD - AViewD) * AXK;
  end;

  procedure PillarPoly(CX, Base, Tip, HW: Single; Up: Boolean; C: TBGRAPixel);
  var
    J: Integer;
    U, F: Single;
  begin
    // the game's karst peak profile: a rounded cone
    SetLength(Pts, 25);
    for J := 0 to 24 do
    begin
      U := J / 24 * 2 - 1;
      F := 1 - Sqr(Sqr(Abs(U)));
      F := Power(Max(0, 1 - Abs(U)), 0.6) * 0.85 + F * 0.15;
      if Up then Pts[J] := PointF(PX(CX) + U * HW * AXK, (Base - (Base - Tip) * F) * AYK)
      else Pts[J] := PointF(PX(CX) + U * HW * AXK, (Base + (Tip - Base) * F) * AYK);
    end;
    B.FillPolyAntialias(Pts, C);
  end;

begin
  W := B.Width;
  H := B.Height;
  Season := FMap.Season;
  case Season of
    1: begin Sky1 := BGRA(170, 182, 190); Sky2 := BGRA(214, 220, 222); Stone := BGRA(92, 112, 108); end;
    2: begin Sky1 := BGRA(240, 196, 150); Sky2 := BGRA(250, 232, 200); Stone := BGRA(150, 96, 60); end;
    3: begin Sky1 := BGRA(198, 214, 230); Sky2 := BGRA(240, 244, 248); Stone := BGRA(120, 130, 146); end;
  else
    begin Sky1 := BGRA(150, 200, 226); Sky2 := BGRA(238, 232, 208); Stone := BGRA(78, 128, 92); end;
  end;
  if FMap.TimeOfDay = 2 then
  begin
    Sky1 := BGRA(22, 30, 64);
    Sky2 := BGRA(52, 58, 98);
    Stone := BGRA(Stone.red div 2, Stone.green div 2, Stone.blue div 2 + 20);
  end;
  StoneD := BGRA(Stone.red * 3 div 4, Stone.green * 3 div 4, Stone.blue * 3 div 4);
  Water := BGRA(70, 130, 170);
  B.GradientFill(0, 0, W, H, Sky1, Sky2, gtLinear, PointF(0, 0), PointF(0, MapWaterY * AYK), dmSet);
  B.FillRect(0, Round(MapWaterY * AYK), W, H, Water, dmSet);
  // metre ruler
  D := Floor(AViewD / 100) * 100;
  while PX(D) < W do
  begin
    X := PX(D);
    if Round(D) mod 1000 = 0 then
    begin
      B.DrawLineAntialias(X, 0, X, H, BGRA(255, 255, 255, 110), 1);
      B.TextOut(X + 3, H - 18, Format('%d m', [Round(D / MapPxPerMetre)]), BGRA(255, 255, 255));
    end
    else if AXK * 100 > 14 then B.DrawLineAntialias(X, MapWaterY * AYK, X, MapWaterY * AYK + 8, BGRA(255, 255, 255, 140), 1);
    D := D + 100;
  end;
  // start (where the crane is when the run starts) and finish
  X := PX(MapCraneX);
  B.DrawLineAntialias(X, 0, X, MapWaterY * AYK, BGRA(40, 160, 60, 200), 2);
  B.TextOut(X + 4, 4, 'start', BGRA(30, 120, 40));
  X := PX(FMap.Length_);
  for K := 0 to Round(MapWaterY * AYK) div 12 do
    if K mod 2 = 0 then B.FillRect(Round(X) - 3, K * 12, Round(X) + 3, K * 12 + 12, BGRA(200, 40, 30), dmSet)
    else B.FillRect(Round(X) - 3, K * 12, Round(X) + 3, K * 12 + 12, BGRA(250, 250, 250), dmSet);
  B.TextOut(X + 6, 4, 'finish', BGRA(180, 30, 20));
  B.FillRect(Round(X) + 3, 0, W, H, BGRA(0, 0, 0, 50), dmDrawWithTransparency);

  for I := 0 to High(FMap.Objs) do
  begin
    O := FMap.Objs[I];
    if (PX(O.D) < -400 * AXK) or (PX(O.D) > W + 400 * AXK) then Continue;
    X := PX(O.D);
    case O.Kind of
      okPillar:
        begin
          if O.Bottom then PillarPoly(O.D, MapWaterY + 30, O.GapY + O.Gap / 2, O.W, True, Stone);
          if O.Top then PillarPoly(O.D, -30, O.GapY - O.Gap / 2, O.W * 0.92, False, StoneD);
          if Handles then
          begin
            B.DrawLineAntialias(X, (O.GapY - O.Gap / 2) * AYK, X, (O.GapY + O.Gap / 2) * AYK,
              BGRA(255, 255, 255, 120), 1);
            if I = FSel then
            begin
              B.FillEllipseAntialias(X, (O.GapY - O.Gap / 2) * AYK, 6, 6, BGRA(255, 230, 80));
              B.FillEllipseAntialias(X, (O.GapY + O.Gap / 2) * AYK, 6, 6, BGRA(255, 230, 80));
              B.EllipseAntialias(X, (O.GapY - O.Gap / 2) * AYK, 6, 6, BGRA(80, 50, 0), 1);
              B.EllipseAntialias(X, (O.GapY + O.Gap / 2) * AYK, 6, 6, BGRA(80, 50, 0), 1);
            end;
          end;
        end;
      okLantern:
        begin
          Y := O.Y * AYK;
          T := 18 * AYK * 1.6;
          B.FillEllipseAntialias(X + 2, Y + 4, T * 0.8, T, BGRA(0, 0, 0, 50));
          B.FillEllipseAntialias(X, Y, T * 0.8, T, BGRA(220, 40, 30));
          B.FillRectAntialias(X - T * 0.4, Y - T * 1.15, X + T * 0.4, Y - T * 0.85, BGRA(240, 190, 60));
          B.FillRectAntialias(X - T * 0.4, Y + T * 0.85, X + T * 0.4, Y + T * 1.15, BGRA(240, 190, 60));
          B.FillEllipseAntialias(X, Y, T * 0.35, T * 0.5, BGRA(255, 210, 120, 180));
        end;
      okHawk:
        begin
          Y := O.Y * AYK;
          T := 34 * AYK * 1.6;
          SetLength(Pts, 7);
          Pts[0] := PointF(X - T, Y - T * 0.25);
          Pts[1] := PointF(X - T * 0.3, Y - T * 0.05);
          Pts[2] := PointF(X, Y - T * 0.3);
          Pts[3] := PointF(X + T * 0.3, Y - T * 0.05);
          Pts[4] := PointF(X + T, Y - T * 0.25);
          Pts[5] := PointF(X + T * 0.2, Y + T * 0.25);
          Pts[6] := PointF(X - T * 0.2, Y + T * 0.25);
          B.FillPolyAntialias(Pts, BGRA(60, 40, 34));
          B.FillEllipseAntialias(X - T * 0.18, Y - T * 0.05, T * 0.12, T * 0.1, BGRA(240, 190, 60));
        end;
      okSwing:
        begin
          // drawn at the middle of its swing; the dashed lines show how far the gap moves
          if O.Bottom then PillarPoly(O.D, MapWaterY + 30, O.GapY + O.Gap / 2, O.W, True, Stone);
          if O.Top then PillarPoly(O.D, -30, O.GapY - O.Gap / 2, O.W * 0.92, False, StoneD);
          for K := -1 to 1 do
            if K <> 0 then
            begin
              B.DrawLineAntialias(X - O.W * AXK, (O.GapY + K * O.Amp - O.Gap / 2) * AYK, X + O.W * AXK,
                (O.GapY + K * O.Amp - O.Gap / 2) * AYK, BGRA(220, 50, 40, 200), 1.5, True);
              B.DrawLineAntialias(X - O.W * AXK, (O.GapY + K * O.Amp + O.Gap / 2) * AYK, X + O.W * AXK,
                (O.GapY + K * O.Amp + O.Gap / 2) * AYK, BGRA(220, 50, 40, 200), 1.5, True);
            end;
          B.FillPolyAntialias([PointF(X, (O.GapY + O.Gap / 2) * AYK), PointF(X, (O.GapY + O.Gap / 2 - 30) * AYK),
            PointF(X + 26 * AYK, (O.GapY + O.Gap / 2 - 22) * AYK)], BGRA(210, 50, 40));
          if Handles and (I = FSel) then
          begin
            B.FillEllipseAntialias(X, (O.GapY - O.Gap / 2) * AYK, 6, 6, BGRA(255, 230, 80));
            B.FillEllipseAntialias(X, (O.GapY + O.Gap / 2) * AYK, 6, 6, BGRA(255, 230, 80));
          end;
        end;
      okBamboo:
        for K := 0 to Max(3, Round(O.W / 13)) - 1 do
        begin
          T := X + (-O.W + 2 * O.W * (K + 0.5) / Max(3, Round(O.W / 13))) * AXK;
          B.FillRectAntialias(T - 6 * AYK, O.Y * AYK, T + 6 * AYK, (MapWaterY + 30) * AYK, BGRA(78, 154, 74));
          B.FillPolyAntialias([PointF(T, O.Y * AYK), PointF(T + 18 * AYK, (O.Y - 30) * AYK),
            PointF(T + 5 * AYK, O.Y * AYK)], BGRA(60, 128, 64));
        end;
      okCloud:
        begin
          Y := O.Y * AYK;
          T := O.W * AYK;
          B.DrawLineAntialias(X, (O.Y - O.Amp) * AYK, X, (O.Y + O.Amp) * AYK, BGRA(90, 96, 112, 200), 2, True);
          B.FillEllipseAntialias(X - T * 0.62, Y + T * 0.12, T * 0.62, T * 0.44, BGRA(90, 96, 112));
          B.FillEllipseAntialias(X + T * 0.6, Y + T * 0.16, T * 0.58, T * 0.42, BGRA(90, 96, 112));
          B.FillEllipseAntialias(X - T * 0.05, Y - T * 0.12, T * 0.74, T * 0.62, BGRA(117, 124, 140));
          B.DrawPolyLineAntialias([PointF(X, Y + T * 0.4), PointF(X - 8, Y + T * 0.4 + 26), PointF(X + 4, Y + T * 0.4 + 34),
            PointF(X - 6, Y + T * 0.4 + 60)], BGRA(255, 240, 160), 2);
        end;
      okPinwheel:
        begin
          Y := O.Y * AYK;
          T := O.W * AYK;
          B.DrawLineAntialias(X, Y, X, (MapWaterY + 30) * AYK, BGRA(138, 96, 56), Max(2, 6 * AYK));
          for K := 0 to 3 do
            B.FillPolyAntialias([PointF(X, Y), PointF(X + T * Cos(0.4 + K * Pi / 2), Y + T * Sin(0.4 + K * Pi / 2)),
              PointF(X + T * 0.62 * Cos(1.2 + K * Pi / 2), Y + T * 0.62 * Sin(1.2 + K * Pi / 2))],
              BladeCols[K]);
          B.FillEllipseAntialias(X, Y, 8 * AYK + 2, 8 * AYK + 2, BGRA(232, 176, 48));
        end;
      okKoi:
        begin
          // its leap: from the river up to Y and back, as the crane comes
          SetLength(Pts, 21);
          for K := 0 to 20 do
          begin
            KoiPos(O, O.D - MapCraneX - 520 + K * 35, T, Y, F);
            Pts[K] := PointF(PX(T), Y * AYK);
          end;
          B.DrawPolyLineAntialias(Pts, BGRA(232, 106, 42, 160), 1.5);
          KoiPos(O, O.D - MapCraneX - 170, T, Y, F);
          X := PX(T);
          Y := Y * AYK;
          B.FillEllipseAntialias(X, Y, 32 * AYK + 3, 13 * AYK + 2, BGRA(242, 238, 230));
          B.FillEllipseAntialias(X + 8 * AYK, Y - 3 * AYK, 14 * AYK + 1, 8 * AYK + 1, BGRA(232, 98, 42));
          B.FillPolyAntialias([PointF(X - 28 * AYK, Y), PointF(X - 50 * AYK, Y - 18 * AYK), PointF(X - 50 * AYK, Y + 18 * AYK)],
            BGRA(232, 106, 42));
          X := PX(O.D);
          Y := O.Y * AYK;
        end;
      okHeart:
        begin
          Y := O.Y * AYK;
          T := 1.6 * AYK;
          B.FillEllipseAntialias(X - 8 * T, Y - 5 * T, 10 * T, 10 * T, BGRA(224, 48, 58));
          B.FillEllipseAntialias(X + 8 * T, Y - 5 * T, 10 * T, 10 * T, BGRA(224, 48, 58));
          B.FillPolyAntialias([PointF(X - 17.5 * T, Y - 1 * T), PointF(X + 17.5 * T, Y - 1 * T), PointF(X, Y + 19 * T)],
            BGRA(224, 48, 58));
        end;
      okSlow:
        begin
          Y := O.Y * AYK;
          T := 1.6 * AYK;
          B.FillEllipseAntialias(X, Y, 17 * T, 17 * T, BGRA(58, 127, 200));
          B.FillPolyAntialias([PointF(X - 7 * T, Y - 9 * T), PointF(X + 7 * T, Y - 9 * T), PointF(X, Y)], BGRA(244, 240, 230));
          B.FillPolyAntialias([PointF(X - 7 * T, Y + 9 * T), PointF(X + 7 * T, Y + 9 * T), PointF(X, Y)], BGRA(244, 240, 230));
        end;
      okShape:
        begin
          Sh := GetShape(O.Shape);
          // shapes keep their proportions: drawn with the height scale
          Sh.Draw(B, X, O.Y * AYK, O.Scale * AYK, O.Flip, True);
          if Handles and O.Solid then
          begin
            R := Sh.Bounds;
            B.RectangleAntialias(X + R.Left * O.Scale * AYK, O.Y * AYK + R.Top * O.Scale * AYK,
              X + R.Right * O.Scale * AYK, O.Y * AYK + R.Bottom * O.Scale * AYK, BGRA(200, 40, 30, 150), 1);
          end;
        end;
    end;
    if Handles and (I = FSel) then
    begin
      if O.Kind in PillarKinds then Y := O.GapY * AYK else Y := O.Y * AYK;
      B.EllipseAntialias(X, Y, 22, 22, BGRA(255, 240, 60), 3);
      B.EllipseAntialias(X, Y, 22, 22, BGRA(60, 40, 0), 1);
    end;
  end;
end;

procedure TMapForm.ViewPaint(Sender: TObject);
var
  B: TBGRABitmap;
  P: TPointF;
begin
  if (FView.Width < 4) or (FView.Height < 4) then Exit;
  B := TBGRABitmap.Create(FView.Width, FView.Height);
  try
    RenderTo(B, FViewD, XK, YK, True);
    // the tool ghost under the mouse
    if (FTool <> tlSelect) and (FDrag = dwNone) and (FMouse.X >= 0) and (FMouse.Y >= 0) and (FMouse.X < FView.Width) and (FMouse.Y < FView.Height) then
    begin
      P := PointF(FMouse.X, FMouse.Y);
      B.EllipseAntialias(P.X, P.Y, 16, 16, BGRA(255, 255, 255, 200), 2);
      B.TextOut(P.X + 18, P.Y - 8, ToolNames[FTool], BGRA(255, 255, 255));
    end;
    B.TextOut(8, FView.Height - 40, Format('view %d m - %d m    zoom %.2f    background: %s', [Round(FViewD / 10),
      Round(WD(FView.Width) / 10), FZoom, IfThen(FMap.Theme < 0, 'player''s setting', MapThemeNames[Max(0, FMap.Theme)])]),
      BGRA(255, 255, 255));
    B.Draw(FView.Canvas, 0, 0, True);
  finally
    B.Free;
  end;
end;

{ ---------- picking ---------- }

function Rect4(L, T, R, B: Single): TRectF;
begin
  Result.Left := L;
  Result.Top := T;
  Result.Right := R;
  Result.Bottom := B;
end;

function TMapForm.HitObj(X, Y: Integer; out What: TDragWhat): Integer;
var
  I: Integer;
  O: TMapObj;
  OX, Y1, Y2, LX, LY, F: Single;
  Sh: TPCShape;
  R: TRectF;
begin
  What := dwMove;
  // the selected pillar's gap handles first
  if (FSel >= 0) and (FMap.Objs[FSel].Kind in PillarKinds) then
  begin
    O := FMap.Objs[FSel];
    OX := SX(O.D);
    Y1 := SY(O.GapY - O.Gap / 2);
    Y2 := SY(O.GapY + O.Gap / 2);
    if (Abs(X - OX) <= 8) and (Abs(Y - Y1) <= 8) then
    begin
      What := dwGapTop;
      Exit(FSel);
    end;
    if (Abs(X - OX) <= 8) and (Abs(Y - Y2) <= 8) then
    begin
      What := dwGapBottom;
      Exit(FSel);
    end;
  end;
  // small items over shapes over pillars; the last drawn wins
  for I := High(FMap.Objs) downto 0 do
  begin
    O := FMap.Objs[I];
    OX := SX(O.D);
    if O.Kind in [okLantern, okHawk, okHeart, okSlow] then
      if Sqr(X - OX) + Sqr(Y - SY(O.Y)) <= Sqr(Max(12, 40 * YK)) then Exit(I);
  end;
  // clouds, pinwheels, koi, bamboo: their box
  for I := High(FMap.Objs) downto 0 do
  begin
    O := FMap.Objs[I];
    if O.Kind in [okCloud, okPinwheel, okKoi, okBamboo] then
    begin
      R := ObjRect(O);
      if O.Kind = okCloud then R := Rect4(O.D - O.W * 1.3, O.Y - O.W * 0.8, O.D + O.W * 1.3, O.Y + O.W * 0.8);
      if O.Kind = okKoi then R := Rect4(O.D - 60, O.Y - 30, O.D + 40, O.Y + 30);
      if (X >= SX(R.Left)) and (X <= SX(R.Right)) and (Y >= SY(R.Top)) and (Y <= SY(R.Bottom)) then Exit(I);
    end;
  end;
  for I := High(FMap.Objs) downto 0 do
  begin
    O := FMap.Objs[I];
    if O.Kind <> okShape then Continue;
    Sh := GetShape(O.Shape);
    if O.Flip then F := -1 else F := 1;
    LX := (X - SX(O.D)) / (O.Scale * YK) * F;
    LY := (Y - SY(O.Y)) / (O.Scale * YK);
    if Sh.HitTest(LX, LY) >= 0 then Exit(I);
  end;
  for I := High(FMap.Objs) downto 0 do
  begin
    O := FMap.Objs[I];
    if (O.Kind in PillarKinds) and (Abs(X - SX(O.D)) <= O.W * XK) then
      if (O.Bottom and (Y > SY(O.GapY + O.Gap / 2))) or (O.Top and (Y < SY(O.GapY - O.Gap / 2))) or
         (Abs(X - SX(O.D)) <= 10) then Exit(I);
  end;
  What := dwNone;
  Result := -1;
end;

{ ---------- mouse ---------- }

procedure TMapForm.ViewDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  What: TDragWhat;
  I: Integer;
  O: TMapObj;
  D, H: Single;
begin

  if Button = mbMiddle then
  begin
    FDrag := dwPan;
    FDragX := X;
    FDragView := FViewD;
    Exit;
  end;
  if Button = mbRight then
  begin
    I := HitObj(X, Y, What);
    if I >= 0 then
    begin
      FSel := I;
      DeleteSel;
    end;
    Exit;
  end;
  D := Snap10(WD(X), FSnap.Checked);
  H := Snap10(WY(Y), FSnap.Checked);
  if FTool = tlSelect then
  begin
    I := HitObj(X, Y, What);
    FSel := I;
    if I >= 0 then
    begin
      PushUndo;
      FDrag := What;
      FDragX := X;
      FDragY := Y;
      FDragObj := FMap.Objs[I];
    end
    else
    begin
      // empty river: drag pans
      FDrag := dwPan;
      FDragX := X;
      FDragView := FViewD;
    end;
    ObjsToList;
    FView.Invalidate;
    Exit;
  end;
  PushUndo;
  O := MakeObj(Ord(FTool), D, H);
  FSel := FMap.Add(O);
  if D > FMap.Length_ - 200 then FMap.Length_ := D + 600;
  FMap.Sort;
  for I := 0 to High(FMap.Objs) do
    if (FMap.Objs[I].D = O.D) and (FMap.Objs[I].Kind = O.Kind) and (FMap.Objs[I].Y = O.Y) then FSel := I;
  Changed;
  MapToControls;
end;

function TMapForm.MakeObj(ATool: Integer; D, H: Single): TMapObj;
var
  K: TMapObjKind;
begin
  K := ToolKinds[TTool(EnsureRange(ATool, 1, Ord(High(TTool))))];
  if K in [okLantern, okHawk, okHeart, okSlow, okCloud, okPinwheel] then H := EnsureRange(H, 30, MapWaterY - 30);
  Result := NewObj(K, D, H);
  if K = okShape then
  begin
    if FShapeCombo.ItemIndex >= 0 then Result.Shape := FShapeCombo.Text;
    Result.Solid := GetShape(Result.Shape).Solid;
  end;
end;

procedure TMapForm.ViewMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  O: TMapObj;
  DD, DY: Single;
begin
  FMouse := Point(X, Y);
  FStatus.SimpleText := Format('distance %.1f m   height %d px   (river surface %d)   objects %d',
    [WD(X) / MapPxPerMetre, Round(WY(Y)), MapWaterY, Length(FMap.Objs)]);
  case FDrag of
    dwPan:
      begin
        FViewD := Max(-200, FDragView - (X - FDragX) / XK);
        UpdateScroll;
      end;
    dwMove, dwGapTop, dwGapBottom:
      if FSel >= 0 then
      begin
        O := FDragObj;
        DD := (X - FDragX) / XK;
        DY := (Y - FDragY) / YK;
        case FDrag of
          dwMove:
            begin
              O.D := Max(0, Snap10(FDragObj.D + DD, FSnap.Checked));
              if O.Kind in PillarKinds then O.GapY := EnsureRange(Snap10(FDragObj.GapY + DY, FSnap.Checked), 40, 800)
              else O.Y := Snap10(FDragObj.Y + DY, FSnap.Checked);
            end;
          dwGapTop:
            begin
              // the bottom edge stays put
              O.Gap := Max(60, Snap10(FDragObj.Gap - DY, FSnap.Checked));
              O.GapY := FDragObj.GapY + FDragObj.Gap / 2 - O.Gap / 2;
            end;
          dwGapBottom:
            begin
              O.Gap := Max(60, Snap10(FDragObj.Gap + DY, FSnap.Checked));
              O.GapY := FDragObj.GapY - FDragObj.Gap / 2 + O.Gap / 2;
            end;
        end;
        FMap.Objs[FSel] := O;
        FDirty := True;
        if Assigned(FOnMapChanged) then FOnMapChanged(Self);
        SelToControls;
      end;
  end;
  FView.Invalidate;
end;

procedure TMapForm.ViewUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  O: TMapObj;
  I: Integer;
begin
  if FDrag in [dwMove, dwGapTop, dwGapBottom] then
  begin
    if FSel >= 0 then
    begin
      // keep the selection on the same object after sorting
      O := FMap.Objs[FSel];
      FMap.Sort;
      for I := 0 to High(FMap.Objs) do
        if (FMap.Objs[I].D = O.D) and (FMap.Objs[I].Kind = O.Kind) and (FMap.Objs[I].Y = O.Y) and
           (FMap.Objs[I].GapY = O.GapY) then FSel := I;
    end;
    Changed;
  end;
  FDrag := dwNone;
end;

procedure TMapForm.ViewWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
  var Handled: Boolean);
var
  At: Single;
begin
  if ssCtrl in Shift then
  begin
    At := WD(MousePos.X);
    if WheelDelta > 0 then FZoom := Min(4, FZoom * 1.2) else FZoom := Max(0.05, FZoom / 1.2);
    FViewD := At - MousePos.X / XK;
  end
  else FViewD := Max(-200, FViewD - Sign(WheelDelta) * 300 / FZoom);
  UpdateScroll;
  FView.Invalidate;
  Handled := True;
end;

procedure TMapForm.UpdateScroll;
begin
  FUpdating := True;
  try
    FScroll.Min := -200;
    FScroll.Max := Max(100, Round(FMap.Length_ + 800));
    FScroll.PageSize := Max(1, Min(FScroll.Max - FScroll.Min, Round(FView.Width / XK)));
    FScroll.LargeChange := Max(1, FScroll.PageSize);
    FScroll.SmallChange := 100;
    FScroll.Position := EnsureRange(Round(FViewD), FScroll.Min, FScroll.Max);
  finally
    FUpdating := False;
  end;
end;

procedure TMapForm.ScrollChange(Sender: TObject);
begin
  if FUpdating then Exit;
  FViewD := FScroll.Position;
  FView.Invalidate;
end;

{ ---------- state ---------- }

procedure TMapForm.PushUndo;
var
  U: TPCMap;
begin
  U := TPCMap.Create;
  U.Assign(FMap);
  FUndo.Add(U);
  while FUndo.Count > 100 do
  begin
    TPCMap(FUndo[0]).Free;
    FUndo.Delete(0);
  end;
end;

procedure TMapForm.SetViewD(V: Single);
begin
  if Abs(V - FViewD) < 0.5 then Exit;
  FViewD := V;
  UpdateScroll;
  FView.Invalidate;
end;

procedure TMapForm.SelectObj(I: Integer);
begin
  if I > High(FMap.Objs) then I := -1;
  if I = FSel then Exit;
  FSel := I;
  FObjList.ItemIndex := I;
  SelToControls;
  FView.Invalidate;
end;

procedure TMapForm.ExternalChanged;
begin
  FDirty := True;
  ObjsToList;
  UpdateCaption;
  UpdateScroll;
  FView.Invalidate;
end;

function TMapForm.ToolIndex: Integer;
begin
  Result := Ord(FTool);
end;

function TMapForm.ShapeName: string;
begin
  Result := FShapeCombo.Text;
end;

procedure TMapForm.Undo;
begin
  UndoClick(nil);
end;

procedure TMapForm.Save;
begin
  SaveClick(nil);
end;

procedure TMapForm.DeleteSelected;
begin
  DeleteSel;
end;

procedure TMapForm.CopySelected;
begin
  CopySel;
end;

function TMapForm.SnapOn: Boolean;
begin
  Result := FSnap.Checked;
end;

procedure TMapForm.Changed;
begin
  if Assigned(FOnMapChanged) then FOnMapChanged(Self);
  FDirty := True;
  ObjsToList;
  UpdateCaption;
  UpdateScroll;
  FView.Invalidate;
end;

procedure TMapForm.UpdateCaption;
var
  N: string;
begin
  if FMap.FileName = '' then N := 'untitled' else N := ExtractFileName(FMap.FileName);
  Caption := Format('Paper Crane Map Editor - %s%s   (%s, %d m, %d obstacles, %d lanterns, %d hawks, %d bonuses, %d shapes)',
    [N, IfThen(FDirty, ' *', ''), FMap.Name, Round(FMap.Length_ / 10), FMap.Count(okPillar) + FMap.Count(okSwing) +
     FMap.Count(okBamboo) + FMap.Count(okCloud) + FMap.Count(okPinwheel) + FMap.Count(okKoi), FMap.Count(okLantern),
     FMap.Count(okHawk), FMap.Count(okHeart) + FMap.Count(okSlow), FMap.Count(okShape)]);
end;

function ObjText(const O: TMapObj): string;
begin
  case O.Kind of
    okPillar: Result := Format('%7.1f m  pillar  gap %d at %d%s', [O.D / 10, Round(O.Gap), Round(O.GapY),
      IfThen(not O.Top, '  (rock only)', IfThen(not O.Bottom, '  (top only)', ''))]);
    okLantern: Result := Format('%7.1f m  lantern  at %d', [O.D / 10, Round(O.Y)]);
    okHawk: Result := Format('%7.1f m  hawk  at %d', [O.D / 10, Round(O.Y)]);
    okHeart: Result := Format('%7.1f m  heart (bonus)  at %d', [O.D / 10, Round(O.Y)]);
    okSlow: Result := Format('%7.1f m  slow-down (bonus)  at %d', [O.D / 10, Round(O.Y)]);
    okSwing: Result := Format('%7.1f m  swinging pillar  gap %d at %d +-%d', [O.D / 10, Round(O.Gap), Round(O.GapY),
      Round(O.Amp)]);
    okBamboo: Result := Format('%7.1f m  bamboo  up to %d', [O.D / 10, Round(O.Y)]);
    okCloud: Result := Format('%7.1f m  storm cloud  at %d +-%d', [O.D / 10, Round(O.Y), Round(O.Amp)]);
    okPinwheel: Result := Format('%7.1f m  pinwheel  at %d, blades %d', [O.D / 10, Round(O.Y), Round(O.W)]);
    okKoi: Result := Format('%7.1f m  leaping koi  up to %d', [O.D / 10, Round(O.Y)]);
  else
    Result := Format('%7.1f m  shape %s x%.2f%s', [O.D / 10, ChangeFileExt(O.Shape, ''), O.Scale,
      IfThen(O.Solid, '  solid', '')]);
  end;
end;

procedure TMapForm.ObjsToList;
var
  I, TopI: Integer;
begin
  TopI := FObjList.TopIndex;
  FObjList.Items.BeginUpdate;
  try
    FObjList.Items.Clear;
    for I := 0 to High(FMap.Objs) do FObjList.Items.Add(ObjText(FMap.Objs[I]));
  finally
    FObjList.Items.EndUpdate;
  end;
  if FSel > High(FMap.Objs) then FSel := -1;
  FObjList.ItemIndex := FSel;
  if FSel < 0 then FObjList.TopIndex := TopI;
  SelToControls;
end;

procedure TMapForm.MapToControls;
var
  I: Integer;
begin
  FUpdating := True;
  try
    FName.Text := FMap.Name;
    FAuthor.Text := FMap.Author;
    FDesc.Text := FMap.Description;
    FSeason.ItemIndex := FMap.Season + 1;
    FTime.ItemIndex := FMap.TimeOfDay + 1;
    FTheme.ItemIndex := FMap.Theme + 1;
    FLives.Value := FMap.Lives;
    FSpeedA.Value := FMap.SpeedStart;
    FSpeedB.Value := FMap.SpeedEnd;
    FLength.Value := FMap.Length_ / 10;
    FMusic.ItemIndex := 0;
    for I := 1 to FMusic.Items.Count - 1 do
      if (FMap.Music <> '') and (Copy(FMusic.Items[I], 1, Length(FMap.Music)) = FMap.Music) then
        FMusic.ItemIndex := I;
  finally
    FUpdating := False;
  end;
end;

procedure TMapForm.SelToControls;
var
  O: TMapObj;
  Has: Boolean;
begin
  FUpdating := True;
  try
    Has := FSel >= 0;
    if Has then O := FMap.Objs[FSel] else O := NewItem(okLantern, 0, 0);
    if Has then FKindLbl.Caption := Format('#%d  %s', [FSel + 1, MapObjNames[O.Kind]])
    else FKindLbl.Caption := '(nothing selected)';
    FPD.Enabled := Has;
    FPY.Enabled := Has and not (O.Kind in PillarKinds);
    FPW.Enabled := Has and (O.Kind in [okPillar, okSwing, okBamboo, okCloud, okPinwheel]);
    FPGapY.Enabled := Has and (O.Kind in PillarKinds);
    FPGap.Enabled := FPGapY.Enabled;
    FPTop.Enabled := FPGapY.Enabled;
    FPBottom.Enabled := FPGapY.Enabled;
    FPAmp.Enabled := Has and (O.Kind in [okSwing, okCloud]);
    FPShape.Enabled := Has and (O.Kind = okShape);
    FPScale.Enabled := FPShape.Enabled;
    FPSolid.Enabled := FPShape.Enabled;
    FPFlip.Enabled := FPShape.Enabled;
    if not Has then Exit;
    FPD.Value := O.D / 10;
    FPY.Value := O.Y;
    FPW.Value := O.W;
    FPGapY.Value := O.GapY;
    FPGap.Value := O.Gap;
    FPAmp.Value := O.Amp;
    FPTop.Checked := O.Top;
    FPBottom.Checked := O.Bottom;
    FPShape.ItemIndex := FPShape.Items.IndexOf(O.Shape);
    FPScale.Value := O.Scale;
    FPSolid.Checked := O.Solid;
    FPFlip.Checked := O.Flip;
  finally
    FUpdating := False;
  end;
end;

procedure TMapForm.MapEdit(Sender: TObject);
var
  S: string;
begin
  if FUpdating then Exit;
  FMap.Name := FName.Text;
  FMap.Author := FAuthor.Text;
  FMap.Description := StringReplace(Trim(FDesc.Text), LineEnding, ' ', [rfReplaceAll]);
  FMap.Season := FSeason.ItemIndex - 1;
  FMap.TimeOfDay := FTime.ItemIndex - 1;
  FMap.Theme := FTheme.ItemIndex - 1;
  FMap.Lives := FLives.Value;
  FMap.SpeedStart := FSpeedA.Value;
  FMap.SpeedEnd := FSpeedB.Value;
  FMap.Length_ := FLength.Value * 10;
  S := FMusic.Text;
  if FMusic.ItemIndex <= 0 then FMap.Music := ''
  else if Copy(S, 1, 8) = 'builtin:' then FMap.Music := Copy(S, 1, 9)
  else FMap.Music := S;
  FDirty := True;
  if Assigned(FOnMapChanged) then FOnMapChanged(Self);
  UpdateCaption;
  UpdateScroll;
  FView.Invalidate;
end;

procedure TMapForm.PropEdit(Sender: TObject);
var
  O: TMapObj;
begin
  if FUpdating or (FSel < 0) then Exit;
  PushUndo;
  O := FMap.Objs[FSel];
  O.D := FPD.Value * 10;
  O.Y := FPY.Value;
  O.W := FPW.Value;
  O.GapY := FPGapY.Value;
  O.Gap := FPGap.Value;
  O.Amp := FPAmp.Value;
  O.Top := FPTop.Checked;
  O.Bottom := FPBottom.Checked;
  if FPShape.ItemIndex >= 0 then O.Shape := FPShape.Text;
  O.Scale := FPScale.Value;
  O.Solid := FPSolid.Checked;
  O.Flip := FPFlip.Checked;
  FMap.Objs[FSel] := O;
  FDirty := True;
  FObjList.Items[FSel] := ObjText(O);
  if Assigned(FOnMapChanged) then FOnMapChanged(Self);
  UpdateCaption;
  FView.Invalidate;
end;

procedure TMapForm.ObjClick(Sender: TObject);
begin
  FSel := FObjList.ItemIndex;
  if FSel >= 0 then
  begin
    // bring it into view
    if (SX(FMap.Objs[FSel].D) < 40) or (SX(FMap.Objs[FSel].D) > FView.Width - 40) then
      FViewD := FMap.Objs[FSel].D - FView.Width / 2 / XK;
    UpdateScroll;
  end;
  SelToControls;
  FView.Invalidate;
end;

procedure TMapForm.SetTool(T: TTool);
var
  X: TTool;
begin
  FTool := T;
  for X := Low(TTool) to High(TTool) do FToolBtns[X].Checked := X = T;
  FView.Invalidate;
end;

procedure TMapForm.ToolClick(Sender: TObject);
begin
  SetTool(TTool(TToggleBox(Sender).Tag));
end;

procedure TMapForm.DeleteSel;
begin
  if FSel < 0 then Exit;
  PushUndo;
  FMap.Delete(FSel);
  FSel := -1;
  Changed;
end;

procedure TMapForm.CopySel;
var
  O: TMapObj;
begin
  if FSel < 0 then Exit;
  PushUndo;
  O := FMap.Objs[FSel];
  O.D := O.D + 300;
  FMap.Add(O);
  FMap.Sort;
  FSel := -1;
  Changed;
end;

procedure TMapForm.UndoClick(Sender: TObject);
begin
  if FUndo.Count = 0 then Exit;
  FMap.Assign(TPCMap(FUndo[FUndo.Count - 1]));
  TPCMap(FUndo[FUndo.Count - 1]).Free;
  FUndo.Delete(FUndo.Count - 1);
  FSel := -1;
  MapToControls;
  Changed;
end;

{ ---------- files ---------- }

procedure TMapForm.NewClick(Sender: TObject);
begin
  PushUndo;
  SampleMap;
  FViewD := 0;
  MapToControls;
  Changed;
  FDirty := False;
  UpdateCaption;
end;

procedure TMapForm.OpenFile(const AFile: string);
begin
  PushUndo;
  FMap.LoadFromFile(AFile);
  FMap.FileName := AFile;
  FSel := -1;
  FViewD := 0;
  MapToControls;
  Changed;
  FDirty := False;
  UpdateCaption;
  FStatus.SimpleText := 'opened ' + AFile;
end;

procedure TMapForm.OpenClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Paper Crane map (*.pcmap)|*.pcmap|All files|*.*';
    if DirectoryExists(GameDir + 'maps') then D.InitialDir := GameDir + 'maps';
    if D.Execute then OpenFile(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TMapForm.SaveClick(Sender: TObject);
begin
  if FMap.FileName = '' then
  begin
    SaveAsClick(Sender);
    Exit;
  end;
  FMap.Sort;
  FMap.SaveToFile(FMap.FileName);
  FDirty := False;
  UpdateCaption;
  FStatus.SimpleText := 'saved ' + FMap.FileName;
end;

procedure TMapForm.SaveAsClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'Paper Crane map (*.pcmap)|*.pcmap';
    D.DefaultExt := 'pcmap';
    ForceDirectories(GameDir + 'maps');
    D.InitialDir := GameDir + 'maps';
    D.FileName := StringReplace(FMap.Name, ' ', '_', [rfReplaceAll]) + '.pcmap';
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
    begin
      FMap.FileName := D.FileName;
      SaveClick(Sender);
    end;
  finally
    D.Free;
  end;
end;

procedure TMapForm.ValidateClick(Sender: TObject);
var
  L: TStringList;
begin
  L := FMap.Validate;
  try
    if L.Count = 0 then ShowMessage('The map looks fine.')
    else ShowMessage(Format('%d problem(s):', [L.Count]) + LineEnding + LineEnding + L.Text);
  finally
    L.Free;
  end;
end;

procedure TMapForm.RandomClick(Sender: TObject);
var
  S: string;
  Diff: Integer;
  I: Integer;
begin
  S := '1';
  if not InputQuery('Fill random', 'Difficulty (0 easy, 1 normal, 2 hard).' + LineEnding +
    'Obstacles after the left edge of the view are replaced.', S) then Exit;
  Diff := EnsureRange(StrToIntDef(S, 1), 0, 2);
  PushUndo;
  for I := High(FMap.Objs) downto 0 do
    if FMap.Objs[I].D >= Max(FViewD, 800) then FMap.Delete(I);
  FMap.FillRandom(Max(FViewD + 300, 1060), FMap.Length_ - 300, Random($7FFFFFFF), Diff);
  FSel := -1;
  Changed;
end;

procedure TMapForm.TestClick(Sender: TObject);
var
  P: TProcess;
  Exe: string;
begin
  Exe := GameDir + 'PaperCrane.exe';
  if not FileExists(Exe) then
  begin
    ShowMessage('The game is not built: ' + Exe);
    Exit;
  end;
  SaveClick(Sender);
  if (FMap.FileName = '') or FDirty then Exit;
  P := TProcess.Create(nil);
  try
    P.Executable := Exe;
    P.Parameters.Add('--map');
    P.Parameters.Add(FMap.FileName);
    P.CurrentDirectory := GameDir;
    P.Options := [];
    P.Execute;
  finally
    P.Free;
  end;
  FStatus.SimpleText := 'testing ' + FMap.FileName + ' in the game';
end;

procedure TMapForm.ExportPng(const AFile: string);
var
  B: TBGRABitmap;
  K: Single;
begin
  // the whole river, 270 px high
  K := 270 / MapDesignH;
  B := TBGRABitmap.Create(Max(64, Round((FMap.Length_ + 500) * K)), 270);
  try
    RenderTo(B, -100, K, K, False);
    B.TextOut(8, 6, Format('%s  -  %d m', [FMap.Name, Round(FMap.Length_ / 10)]), BGRA(255, 255, 255));
    B.SaveToFile(AFile);
  finally
    B.Free;
  end;
end;

procedure TMapForm.PngClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'PNG (*.png)|*.png';
    D.DefaultExt := 'png';
    D.FileName := StringReplace(FMap.Name, ' ', '_', [rfReplaceAll]) + '.png';
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
    begin
      ExportPng(D.FileName);
      FStatus.SimpleText := 'exported ' + D.FileName;
    end;
  finally
    D.Free;
  end;
end;

procedure TMapForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (ActiveControl is TCustomEdit) or (ActiveControl is TCustomComboBox) then
    if not ((Key = VK_S) and (ssCtrl in Shift)) then Exit;
  case Key of
    VK_1..VK_9, VK_0: if Shift = [] then
      begin
        if Key = VK_0 then SetTool(TTool(9)) else SetTool(TTool(Key - VK_1));
        Key := 0;
      end;
    VK_DELETE: DeleteSel;
    VK_ESCAPE: SetTool(tlSelect);
    VK_LEFT: begin FViewD := Max(-200, FViewD - 200 / FZoom); UpdateScroll; FView.Invalidate; Key := 0; end;
    VK_RIGHT: begin FViewD := FViewD + 200 / FZoom; UpdateScroll; FView.Invalidate; Key := 0; end;
    VK_Z: if ssCtrl in Shift then UndoClick(nil);
    VK_D: if ssCtrl in Shift then CopySel;
    VK_S: if ssCtrl in Shift then SaveClick(nil);
    VK_F5: TestClick(nil);
  end;
end;

procedure TMapForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FDirty then
    case MessageDlg('Save the map before closing?', mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrYes:
        begin
          SaveClick(nil);
          CanClose := not FDirty;
        end;
      mrCancel: CanClose := False;
    end;
end;

end.
