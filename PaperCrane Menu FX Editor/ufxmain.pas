unit uFxMain;

{ Paper Crane Menu FX Editor: the frames and letter effects of every menu of
  the game (.pcmenufx, uPCMenuFx).

  Left: the game's menus - each one has its own frame, frame effect and three
  independent text styles (title, items, selected item). Middle: a live preview
  of the chosen menu with its real items (click an item or use Up / Down to
  select it, "Move the selection" walks through them). Right: the Frame,
  Title, Items and Selected item pages.

  Files: New, Open, Save, Save as; "Save to game" writes menufx.pcmenufx into
  the game's folder - a running game picks it up within half a second. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Dialogs, Spin,
  LCLType, BGRABitmap, BGRABitmapTypes, uPCMenuFx;

type
  TTextCtl = record
    Font: TComboBox;
    Size, Outline: TFloatSpinEdit;
    Bold, Italic, Gradient, Shadow: TCheckBox;
    Color, Color2, OutlineColor: TColorButton;
    Fx: TComboBox;
    Speed, Amount: TTrackBar;
  end;

  { TFxForm }

  TFxForm = class(TForm)
  private
    FSet: TMenuFxSet;
    FCur, FSelItem: Integer;
    FUpdating, FDirty: Boolean;
    FStart: QWord;
    FGlyphs: TGlyphCache;
    FGlyphK: Single;
    FCard: TBGRABitmap;       // the static card (frame, info) for FCardKey
    FCardKey: string;
    FBuf: TBGRABitmap;
    FMenus: TListBox;
    FView: TPaintBox;
    FTimer: TTimer;
    FPages: TPageControl;
    FStatus: TStatusBar;
    FAutoSel, FSuggest: TCheckBox;
    // frame
    FKind, FFrameFx: TComboBox;
    FFColor, FFColor2, FFPaper: TColorButton;
    FFSpeed, FFAmount: TTrackBar;
    FText: array[0..2] of TTextCtl;
    FFrames, FFrameT: Integer;
    FFrameMs: Double;
    procedure BuildUI;
    function AddButton(AParent: TWinControl; const C: string; H: TNotifyEvent): TButton;
    procedure BuildTextPage(Page: TTabSheet; Idx: Integer);
    procedure ToControls;
    procedure FromControls(Sender: TObject);
    procedure MenuClick(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure ViewPaint(Sender: TObject);
    procedure ViewDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure KindChange(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure GameClick(Sender: TObject);
    procedure CopyAllClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    function GameDir: string;
    procedure UpdateCaption;
    procedure Layout(out K, CX, CY, CW, CH: Single);
    procedure RenderPreview(B: TBGRABitmap; T: Single);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenFile(const AFile: string);
    procedure SavePreview(const AFile: string; T: Single);
    property Menu: Integer read FCur write FCur;
  end;

var
  FxForm: TFxForm;

function SampleItems(M: Integer): TStringArray;
function SampleTitle(M: Integer): string;
function SampleInfo(M: Integer): string;

implementation

var
  GSeq: Integer = 0;

function NextSeq: Integer;
begin
  Inc(GSeq, 4);
  Result := GSeq;
end;

{ the real items of each menu, so the preview looks like the game }
function SampleItems(M: Integer): TStringArray;
begin
  case M of
    0: Result := ['Player'#9'Mali  -  Paper Crane', 'Change player', 'Random map', 'Custom maps', 'Saved games',
         'Ghosts', 'Statistics', 'Settings', 'How to play', 'High scores', 'Credits', 'Quit'];
    1: Result := ['Resume', 'Save game', 'Restart', 'Settings', 'How to play', 'Main menu'];
    2: Result := ['Play again', 'Save ghost', 'High scores', 'Main menu'];
    3: Result := ['Music volume'#9'70%', 'Sound volume'#9'80%', 'Music'#9'Auto (by scene)', 'Difficulty'#9'Normal',
         'Season'#9'Summer', 'Time of day'#9'Auto cycle', 'Background'#9'Random', 'Show HUD'#9'On',
         'Full screen'#9'Off', 'VSync'#9'On', 'Back'];
    7: Result := ['Bamboo Valley', 'Crane''s Trial', 'Koi Pond', 'Lotus River', 'Pinwheel Festival', 'Back'];
    8, 10: Result := ['Lotus River - 107 m, 12 pts', 'Random #61016 - 420 m, 33 pts', 'Back'];
    9: Result := ['Continue', 'Delete', 'Back'];
    11: Result := ['Replay (watch)', 'Race against it', 'Delete', 'Back'];
    12: Result := ['Mali', 'Ton', '+  New player', 'Back'];
    13: Result := ['Switch player (paper cards)', 'Character'#9'Paper Crane', 'Statistics', 'Delete player', 'Back'];
    14: Result := ['OK', 'Back'];
    15: Result := ['Paper Crane', 'Paper Dragon', 'Winged Panda Bike', 'Night Owl', 'Phoenix', 'Back'];
    17: Result := [];
  else
    Result := ['Back'];
  end;
end;

function SampleTitle(M: Integer): string;
const
  T: array[0..MenuFxCount - 1] of string = ('PAPER CRANE  '#$E7#$BA#$B8#$E9#$B9#$A4, 'PAUSED', 'GAME OVER',
    'SETTINGS', 'HOW TO PLAY', 'HIGH SCORES', 'CREDITS', 'CUSTOM MAPS', 'SAVED GAMES', 'SAVED GAME', 'GHOSTS',
    'GHOST', 'PLAYERS', 'MALI', 'NEW PLAYER', 'CHOOSE YOUR CHARACTER', 'STATISTICS', 'SELECT YOUR PAPER CARD');
begin
  Result := T[EnsureRange(M, 0, MenuFxCount - 1)];
end;

function SampleInfo(M: Integer): string;
begin
  case M of
    0: Result := 'A papercut flight up the Li river';
    1: Result := 'Score 12     107 m     lanterns 2';
    2: Result := 'Score 33     lanterns 4     420 m';
    3: Result := 'Up / Down choose,  Left / Right or click change,  Esc back';
    17: Result := 'Left / Right choose a player,  Enter or click to fly';
  else
    Result := MenuFxNames[EnsureRange(M, 0, MenuFxCount - 1)];
  end;
end;

{ ---------- form ---------- }

constructor TFxForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'Paper Crane Menu FX Editor';
  Width := Scale96ToForm(1420);
  Height := Scale96ToForm(860);
  Position := poScreenCenter;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  OnCloseQuery := @FormCloseQuery;
  FSet := TMenuFxSet.Create;
  FGlyphs := TGlyphCache.Create;
  FBuf := TBGRABitmap.Create(1, 1);
  FStart := GetTickCount64;
  BuildUI;
  if FileExists(GameDir + 'menufx.pcmenufx') then
    try
      FSet.LoadFromFile(GameDir + 'menufx.pcmenufx');
    except
      FSet.Defaults;
    end;
  FMenus.ItemIndex := 0;
  ToControls;
  UpdateCaption;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 15;
  FTimer.OnTimer := @Tick;
end;

destructor TFxForm.Destroy;
begin
  FTimer.Enabled := False;
  FSet.Free;
  FGlyphs.Free;
  FCard.Free;
  FBuf.Free;
  inherited Destroy;
end;

function TFxForm.GameDir: string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'Paper Crane Papercut Game SDL3') +
    PathDelim;
end;

function TFxForm.AddButton(AParent: TWinControl; const C: string; H: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := C;
  Result.AutoSize := True;
  Result.Align := alLeft;
  Result.Left := NextSeq + 100000;
  Result.BorderSpacing.Around := 3;
  Result.OnClick := H;
end;

function Lbl(AOwner: TComponent; AParent: TWinControl; const C: string): TLabel;
begin
  Result := TLabel.Create(AOwner);
  Result.Parent := AParent;
  Result.Caption := C;
  Result.Align := alTop;
  Result.Top := NextSeq + 100000;
  Result.BorderSpacing.Left := 6;
  Result.BorderSpacing.Top := 5;
end;

function Combo(AOwner: TComponent; AParent: TWinControl; const C: string; const Items: array of string;
  H: TNotifyEvent; Free: Boolean = False): TComboBox;
var
  S: string;
begin
  Lbl(AOwner, AParent, C);
  Result := TComboBox.Create(AOwner);
  Result.Parent := AParent;
  if Free then Result.Style := csDropDown else Result.Style := csDropDownList;
  for S in Items do Result.Items.Add(S);
  Result.DropDownCount := 20;
  Result.Align := alTop;
  Result.Top := NextSeq + 100000;
  Result.BorderSpacing.Left := 6;
  Result.BorderSpacing.Right := 6;
  Result.OnChange := H;
end;

function Track(AOwner: TComponent; AParent: TWinControl; const C: string; H: TNotifyEvent): TTrackBar;
begin
  Lbl(AOwner, AParent, C);
  Result := TTrackBar.Create(AOwner);
  Result.Parent := AParent;
  Result.Min := 0;
  Result.Max := 300;
  Result.Frequency := 50;
  Result.Align := alTop;
  Result.Top := NextSeq + 100000;
  Result.Height := 30;
  Result.OnChange := H;
end;

function ColorBtn(AOwner: TComponent; AParent: TWinControl; const C: string; H: TNotifyEvent): TColorButton;
var
  P: TPanel;
  L: TLabel;
begin
  P := TPanel.Create(AOwner);
  P.Parent := AParent;
  P.Align := alTop;
  P.Top := NextSeq + 100000;
  P.Height := 30;
  P.BevelOuter := bvNone;
  L := TLabel.Create(AOwner);
  L.Parent := P;
  L.Caption := C;
  L.Align := alLeft;
  L.AutoSize := False;
  L.Width := 130;
  L.Layout := tlCenter;
  L.BorderSpacing.Left := 6;
  Result := TColorButton.Create(AOwner);
  Result.Parent := P;
  Result.Align := alClient;
  Result.BorderSpacing.Around := 2;
  Result.OnColorChanged := H;
end;

function Check(AOwner: TComponent; AParent: TWinControl; const C: string; H: TNotifyEvent): TCheckBox;
begin
  Result := TCheckBox.Create(AOwner);
  Result.Parent := AParent;
  Result.Caption := C;
  Result.Align := alTop;
  Result.Top := NextSeq + 100000;
  Result.BorderSpacing.Left := 6;
  Result.BorderSpacing.Top := 3;
  Result.OnClick := H;
end;

function Num(AOwner: TComponent; AParent: TWinControl; const C: string; AMin, AMax, AInc: Double;
  H: TNotifyEvent): TFloatSpinEdit;
var
  P: TPanel;
  L: TLabel;
begin
  P := TPanel.Create(AOwner);
  P.Parent := AParent;
  P.Align := alTop;
  P.Top := NextSeq + 100000;
  P.Height := 30;
  P.BevelOuter := bvNone;
  L := TLabel.Create(AOwner);
  L.Parent := P;
  L.Caption := C;
  L.Align := alLeft;
  L.AutoSize := False;
  L.Width := 130;
  L.Layout := tlCenter;
  L.BorderSpacing.Left := 6;
  Result := TFloatSpinEdit.Create(AOwner);
  Result.Parent := P;
  Result.Align := alClient;
  Result.BorderSpacing.Around := 2;
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.Increment := AInc;
  Result.DecimalPlaces := 1;
  Result.OnChange := H;
end;

procedure TFxForm.BuildTextPage(Page: TTabSheet; Idx: Integer);
var
  Box: TScrollBox;
  TF: TTextFx;
  Names: array of string;
begin
  Box := TScrollBox.Create(Self);
  Box.Parent := Page;
  Box.Align := alClient;
  Box.BorderStyle := bsNone;
  Box.HorzScrollBar.Visible := False;
  with FText[Idx] do
  begin
    Font := Combo(Self, Box, 'Font (pick or type any installed font)', FontChoices, @FromControls, True);
    Size := Num(Self, Box, 'Size (design px)', 6, 120, 1, @FromControls);
    Bold := Check(Self, Box, 'Bold', @FromControls);
    Italic := Check(Self, Box, 'Italic', @FromControls);
    Color := ColorBtn(Self, Box, 'Colour', @FromControls);
    Gradient := Check(Self, Box, 'Gradient (top colour to the second colour)', @FromControls);
    Color2 := ColorBtn(Self, Box, 'Second colour / glow', @FromControls);
    Outline := Num(Self, Box, 'Outline width', 0, 8, 0.5, @FromControls);
    OutlineColor := ColorBtn(Self, Box, 'Outline colour', @FromControls);
    Shadow := Check(Self, Box, 'Paper shadow', @FromControls);
    SetLength(Names, 0);
    for TF := Low(TTextFx) to High(TTextFx) do
    begin
      SetLength(Names, Length(Names) + 1);
      Names[High(Names)] := TextFxNames[TF];
    end;
    Self.FText[Idx].Fx := Combo(Self, Box, 'Letter effect', Names, @FromControls);
    Speed := Track(Self, Box, 'Effect speed', @FromControls);
    Amount := Track(Self, Box, 'Effect amount', @FromControls);
  end;
end;

procedure TFxForm.BuildUI;
var
  Bar, LeftP, RightP: TPanel;
  I: Integer;
  Page: TTabSheet;
  Box: TScrollBox;
  K: TFrameKind;
  F: TFrameFx;
  KN, FN: array of string;
const
  PageNames: array[0..3] of string = ('Frame', 'Title', 'Items', 'Selected item');
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
  AddButton(Bar, '>  Save to game', @GameClick);
  AddButton(Bar, 'Copy this menu to all', @CopyAllClick);
  AddButton(Bar, 'Reset this menu', @ResetClick);
  FAutoSel := TCheckBox.Create(Self);
  FAutoSel.Parent := Bar;
  FAutoSel.Caption := 'Move the selection';
  FAutoSel.Align := alLeft;
  FAutoSel.Left := NextSeq + 100000;
  FAutoSel.BorderSpacing.Left := 12;

  LeftP := TPanel.Create(Self);
  LeftP.Parent := Self;
  LeftP.Align := alLeft;
  LeftP.Width := Scale96ToForm(190);
  LeftP.BevelOuter := bvNone;
  Lbl(Self, LeftP, 'Menus (each one is independent)');
  FMenus := TListBox.Create(Self);
  FMenus.Parent := LeftP;
  FMenus.Align := alClient;
  FMenus.BorderSpacing.Around := 4;
  for I := 0 to MenuFxCount - 1 do FMenus.Items.Add(MenuFxNames[I]);
  FMenus.OnClick := @MenuClick;

  RightP := TPanel.Create(Self);
  RightP.Parent := Self;
  RightP.Align := alRight;
  RightP.Width := Scale96ToForm(340);
  RightP.BevelOuter := bvNone;
  FPages := TPageControl.Create(Self);
  FPages.Parent := RightP;
  FPages.Align := alClient;
  for I := 0 to 3 do
  begin
    Page := FPages.AddTabSheet;
    Page.Caption := PageNames[I];
    if I = 0 then
    begin
      Box := TScrollBox.Create(Self);
      Box.Parent := Page;
      Box.Align := alClient;
      Box.BorderStyle := bsNone;
      SetLength(KN, 0);
      for K := Low(TFrameKind) to High(TFrameKind) do
      begin
        SetLength(KN, Length(KN) + 1);
        KN[High(KN)] := FrameKindNames[K];
      end;
      SetLength(FN, 0);
      for F := Low(TFrameFx) to High(TFrameFx) do
      begin
        SetLength(FN, Length(FN) + 1);
        FN[High(FN)] := FrameFxNames[F];
      end;
      FKind := Combo(Self, Box, 'Frame', KN, @KindChange);
      FSuggest := Check(Self, Box, 'Suggested colours when the frame changes', nil);
      FSuggest.Checked := True;
      FFrameFx := Combo(Self, Box, 'Frame effect', FN, @FromControls);
      FFColor := ColorBtn(Self, Box, 'Frame colour', @FromControls);
      FFColor2 := ColorBtn(Self, Box, 'Accent colour', @FromControls);
      FFPaper := ColorBtn(Self, Box, 'Paper colour', @FromControls);
      FFSpeed := Track(Self, Box, 'Effect speed', @FromControls);
      FFAmount := Track(Self, Box, 'Effect amount', @FromControls);
    end
    else
      BuildTextPage(Page, I - 1);
  end;

  FView := TPaintBox.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.OnPaint := @ViewPaint;
  FView.OnMouseDown := @ViewDown;
end;

procedure TFxForm.UpdateCaption;
var
  N: string;
begin
  if FSet.FileName = '' then N := 'untitled' else N := ExtractFileName(FSet.FileName);
  Caption := 'Paper Crane Menu FX Editor - ' + N + IfThen(FDirty, ' *', '') + '   (' + MenuFxNames[FCur] + ')';
end;

{ ---------- controls <-> the menu's styles ---------- }

procedure TFxForm.ToControls;
var
  I: Integer;
  St: TTextStyle;

  function Col(C: TBGRAPixel): TColor;
  begin
    Result := RGBToColor(C.red, C.green, C.blue);
  end;

begin
  FUpdating := True;
  try
    with FSet.Menus[FCur].Frame do
    begin
      FKind.ItemIndex := Ord(Kind);
      FFrameFx.ItemIndex := Ord(Fx);
      FFColor.ButtonColor := Col(Color);
      FFColor2.ButtonColor := Col(Color2);
      FFPaper.ButtonColor := Col(Paper);
      FFSpeed.Position := Round(Speed * 100);
      FFAmount.Position := Round(Amount * 100);
    end;
    for I := 0 to 2 do
    begin
      case I of
        0: St := FSet.Menus[FCur].Title;
        1: St := FSet.Menus[FCur].Item;
      else
        St := FSet.Menus[FCur].Sel;
      end;
      with FText[I] do
      begin
        Font.Text := St.Font;
        Size.Value := St.Size;
        Bold.Checked := St.Bold;
        Italic.Checked := St.Italic;
        Color.ButtonColor := Col(St.Color);
        Gradient.Checked := St.Gradient;
        Color2.ButtonColor := Col(St.Color2);
        Outline.Value := St.Outline;
        OutlineColor.ButtonColor := Col(St.OutlineColor);
        Shadow.Checked := St.Shadow;
        Fx.ItemIndex := Ord(St.Fx);
        Speed.Position := Round(St.Speed * 100);
        Amount.Position := Round(St.Amount * 100);
      end;
    end;
  finally
    FUpdating := False;
  end;
  FCardKey := '';
end;

procedure TFxForm.FromControls(Sender: TObject);
var
  I: Integer;
  St: TTextStyle;

  function Px(C: TColor; A: Byte = 255): TBGRAPixel;
  begin
    Result := BGRA(Red(C), Green(C), Blue(C), A);
  end;

begin
  if FUpdating then Exit;
  with FSet.Menus[FCur].Frame do
  begin
    Kind := TFrameKind(Max(0, FKind.ItemIndex));
    Fx := TFrameFx(Max(0, FFrameFx.ItemIndex));
    Color := Px(FFColor.ButtonColor);
    Color2 := Px(FFColor2.ButtonColor);
    Paper := Px(FFPaper.ButtonColor, 248);
    Speed := FFSpeed.Position / 100;
    Amount := FFAmount.Position / 100;
  end;
  for I := 0 to 2 do
  begin
    with FText[I] do
    begin
      St.Font := Trim(Font.Text);
      if St.Font = '' then St.Font := 'Segoe UI';
      St.Size := Size.Value;
      St.Bold := Bold.Checked;
      St.Italic := Italic.Checked;
      St.Color := Px(Color.ButtonColor);
      St.Gradient := Gradient.Checked;
      St.Color2 := Px(Color2.ButtonColor);
      St.Outline := Outline.Value;
      St.OutlineColor := Px(OutlineColor.ButtonColor);
      St.Shadow := Shadow.Checked;
      St.Fx := TTextFx(Max(0, Fx.ItemIndex));
      St.Speed := Speed.Position / 100;
      St.Amount := Amount.Position / 100;
    end;
    case I of
      0: FSet.Menus[FCur].Title := St;
      1: FSet.Menus[FCur].Item := St;
    else
      FSet.Menus[FCur].Sel := St;
    end;
  end;
  FDirty := True;
  FCardKey := '';
  UpdateCaption;
end;

{ a new frame style brings colours that suit it }
procedure TFxForm.KindChange(Sender: TObject);
begin
  if FUpdating then Exit;
  if FSuggest.Checked then
  begin
    FUpdating := True;
    case TFrameKind(Max(0, FKind.ItemIndex)) of
      fkBamboo: begin FFColor.ButtonColor := RGBToColor(78, 140, 70); FFColor2.ButtonColor := RGBToColor(46, 96, 44); end;
      fkPlum: begin FFColor.ButtonColor := RGBToColor(150, 60, 70); FFColor2.ButtonColor := RGBToColor(240, 200, 80); end;
      fkImperial: begin FFColor.ButtonColor := RGBToColor(178, 30, 30); FFColor2.ButtonColor := RGBToColor(226, 176, 52); end;
      fkCloud: begin FFColor.ButtonColor := RGBToColor(40, 92, 150); FFColor2.ButtonColor := RGBToColor(222, 170, 50); end;
      fkLattice: begin FFColor.ButtonColor := RGBToColor(120, 70, 40); FFColor2.ButtonColor := RGBToColor(200, 60, 40); end;
    else
      begin FFColor.ButtonColor := RGBToColor(178, 40, 34); FFColor2.ButtonColor := RGBToColor(222, 170, 50); end;
    end;
    FUpdating := False;
  end;
  FromControls(Sender);
end;

procedure TFxForm.MenuClick(Sender: TObject);
begin
  if FMenus.ItemIndex < 0 then Exit;
  FCur := FMenus.ItemIndex;
  FSelItem := 0;
  ToControls;
  UpdateCaption;
end;

{ ---------- preview ---------- }

procedure TFxForm.Layout(out K, CX, CY, CW, CH: Single);
var
  N: Integer;
begin
  N := Length(SampleItems(FCur));
  CW := 860;
  if FCur = 17 then CH := 98 + 32 + 14 + 4 else CH := 98 + 32 + 14 + N * 46 + 40;
  K := Min((FView.Width - 40) / CW, (FView.Height - 40) / Max(400, CH));
  K := Max(0.2, K);
  CX := (FView.Width - CW * K) / 2;
  if FCur = 17 then CY := 30 else CY := (FView.Height - CH * K) / 2;
end;

procedure TFxForm.RenderPreview(B: TBGRABitmap; T: Single);
var
  K, CX, CY, CW, CH, Y, ItemY0: Single;
  Items: TStringArray;
  Fx: TMenuFx;
  I, TabP: Integer;
  Key, It: string;
  St: TTextStyle;
begin
  Layout(K, CX, CY, CW, CH);
  Fx := FSet.Menus[FCur];
  Items := SampleItems(FCur);
  if FSelItem >= Length(Items) then FSelItem := 0;
  // the paper sky behind
  B.GradientFill(0, 0, B.Width, B.Height, BGRA(150, 196, 226), BGRA(232, 240, 230), gtLinear, PointF(0, 0),
    PointF(0, B.Height), dmSet);
  B.FillEllipseAntialias(B.Width * 0.82, B.Height * 0.18, 46, 46, BGRA(255, 244, 214));
  // the static card (frame and info), made again when the frame or the size changes
  Key := Format('%d|%.3f|%d|%d|%s|%s|%s|%d', [FCur, K, B.Width, B.Height, ColorHex(Fx.Frame.Color),
    ColorHex(Fx.Frame.Color2), ColorHex(Fx.Frame.Paper), Ord(Fx.Frame.Kind)]);
  if (FCard = nil) or (Key <> FCardKey) then
  begin
    FCardKey := Key;
    FreeAndNil(FCard);
    FCard := TBGRABitmap.Create(Max(1, Round((CW + 12) * K)), Max(1, Round((CH + 14) * K)));
    FCard.FillRoundRectAntialias(8 * K, 12 * K, (CW + 10) * K, (CH + 12) * K, 14 * K, 14 * K, BGRA(0, 0, 0, 70));
    FCard.FillRoundRectAntialias(K, K, CW * K, CH * K, 14 * K, 14 * K, Fx.Frame.Paper);
    DrawFrameStatic(FCard, Fx.Frame, 0, 0, CW, CH, K, 82);
    FCard.FontName := 'Segoe UI';
    FCard.FontQuality := fqFineAntialiasing;
    FCard.FontHeight := Max(7, Round(20 * K));
    FCard.TextOut(CW / 2 * K, 92 * K, SampleInfo(FCur), BGRA(80, 60, 56), taCenter);
  end;
  B.PutImage(Round(CX), Round(CY), FCard, dmDrawWithTransparency);
  if FGlyphK <> K then
  begin
    FGlyphs.Clear;
    FGlyphK := K;
  end;
  DrawFrameFx(B, Fx.Frame, CX, CY, CW, CH, K, T);
  FGlyphs.Prepare(Fx.Title, K, SampleTitle(FCur));
  DrawFxText(B, FGlyphs, Fx.Title, K, CX + CW / 2 * K, CY + (18 + (44 - Fx.Title.Size) * 0.5) * K, T,
    SampleTitle(FCur), 1);
  ItemY0 := 98 + 32 + 14;
  for I := 0 to High(Items) do
  begin
    if I = FSelItem then
    begin
      St := Fx.Sel;
      B.FillRectAntialias(CX + 60 * K, CY + (ItemY0 + I * 46 + 4) * K, CX + (CW - 60) * K, CY + (ItemY0 + I * 46 + 44) * K,
        BGRA(178, 40, 34, 26));
      B.FillRectAntialias(CX + 54 * K, CY + (ItemY0 + I * 46 + 38) * K, CX + (CW - 54) * K, CY + (ItemY0 + I * 46 + 40) * K,
        BGRA(196, 44, 34, 120));
      B.FillPolyAntialias([PointF(CX + (30 + 3 * Sin(T * 5)) * K, CY + (ItemY0 + I * 46 + 14) * K),
        PointF(CX + (46 + 3 * Sin(T * 5)) * K, CY + (ItemY0 + I * 46 + 23) * K),
        PointF(CX + (30 + 3 * Sin(T * 5)) * K, CY + (ItemY0 + I * 46 + 32) * K)], BGRA(196, 44, 34, 235));
    end
    else
      St := Fx.Item;
    It := Items[I];
    FGlyphs.Prepare(St, K, It);
    Y := CY + (ItemY0 + I * 46 + (46 - St.Size * 1.36) / 2) * K;
    TabP := Pos(#9, It);
    if TabP > 0 then
    begin
      DrawFxText(B, FGlyphs, St, K, CX + 110 * K, Y, T, Copy(It, 1, TabP - 1), 0, I * 0.9);
      DrawFxText(B, FGlyphs, St, K, CX + (CW / 2 + 190) * K, Y, T, Copy(It, TabP + 1, MaxInt), 1, I * 0.9 + 0.5);
    end
    else
      DrawFxText(B, FGlyphs, St, K, CX + CW / 2 * K, Y, T, It, 1, I * 0.9);
  end;
end;

procedure TFxForm.ViewPaint(Sender: TObject);
var
  T0: QWord;
begin
  if (FView.Width < 8) or (FView.Height < 8) then Exit;
  T0 := GetTickCount64;
  if (FBuf.Width <> FView.Width) or (FBuf.Height <> FView.Height) then FBuf.SetSize(FView.Width, FView.Height);
  RenderPreview(FBuf, (GetTickCount64 - FStart) / 1000);
  FBuf.Draw(FView.Canvas, 0, 0, True);
  FFrameMs := FFrameMs * 0.9 + (GetTickCount64 - T0) * 0.1;
end;

procedure TFxForm.Tick(Sender: TObject);
var
  N: Integer;
begin
  Inc(FFrames);
  if FAutoSel.Checked and (FFrames mod 70 = 0) then
  begin
    N := Length(SampleItems(FCur));
    if N > 0 then FSelItem := (FSelItem + 1) mod N;
  end;
  if FFrames mod 30 = 0 then
    FStatus.SimpleText := Format('%s   -   preview %.1f ms per frame,  %d letters cut   -   click an item or Up / Down to select it',
      [MenuFxNames[FCur], FFrameMs, FGlyphs.Count]);
  FView.Invalidate;
end;

procedure TFxForm.ViewDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  K, CX, CY, CW, CH: Single;
  I: Integer;
begin
  Layout(K, CX, CY, CW, CH);
  I := Floor(((Y - CY) / K - (98 + 32 + 14)) / 46);
  if (I >= 0) and (I < Length(SampleItems(FCur))) then FSelItem := I;
end;

procedure TFxForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  N: Integer;
begin
  if (ActiveControl is TCustomEdit) or (ActiveControl is TCustomComboBox) or (ActiveControl is TTrackBar) then
    if not ((Key = VK_S) and (ssCtrl in Shift)) then Exit;
  N := Max(1, Length(SampleItems(FCur)));
  case Key of
    VK_UP: begin FSelItem := (FSelItem - 1 + N) mod N; Key := 0; end;
    VK_DOWN: begin FSelItem := (FSelItem + 1) mod N; Key := 0; end;
    VK_S: if ssCtrl in Shift then SaveClick(nil);
  end;
end;

{ ---------- files ---------- }

procedure TFxForm.NewClick(Sender: TObject);
begin
  FSet.Defaults;
  FSet.FileName := '';
  FDirty := False;
  ToControls;
  UpdateCaption;
end;

procedure TFxForm.OpenFile(const AFile: string);
begin
  FSet.LoadFromFile(AFile);
  FDirty := False;
  ToControls;
  UpdateCaption;
  FStatus.SimpleText := 'opened ' + AFile;
end;

procedure TFxForm.OpenClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Paper Crane menu effects (*.pcmenufx)|*.pcmenufx|All files|*.*';
    D.InitialDir := GameDir;
    if D.Execute then
      try
        OpenFile(D.FileName);
      except
        on E: Exception do ShowMessage(E.Message);
      end;
  finally
    D.Free;
  end;
end;

procedure TFxForm.SaveClick(Sender: TObject);
begin
  if FSet.FileName = '' then
  begin
    SaveAsClick(Sender);
    Exit;
  end;
  FSet.SaveToFile(FSet.FileName);
  FDirty := False;
  UpdateCaption;
  FStatus.SimpleText := 'saved ' + FSet.FileName;
end;

procedure TFxForm.SaveAsClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'Paper Crane menu effects (*.pcmenufx)|*.pcmenufx';
    D.DefaultExt := 'pcmenufx';
    D.InitialDir := GameDir;
    D.FileName := 'my_menus.pcmenufx';
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
    begin
      FSet.FileName := D.FileName;
      SaveClick(Sender);
    end;
  finally
    D.Free;
  end;
end;

{ the game reads menufx.pcmenufx next to it (and again whenever it changes) }
procedure TFxForm.GameClick(Sender: TObject);
var
  Keep: string;
begin
  Keep := FSet.FileName;
  FSet.SaveToFile(GameDir + 'menufx.pcmenufx');
  if Keep <> '' then FSet.FileName := Keep;
  if SameFileName(FSet.FileName, GameDir + 'menufx.pcmenufx') then FDirty := False;
  UpdateCaption;
  FStatus.SimpleText := 'saved to the game: ' + GameDir + 'menufx.pcmenufx (a running game takes it at once)';
end;

procedure TFxForm.CopyAllClick(Sender: TObject);
var
  I: Integer;
begin
  if MessageDlg('Give every menu the frame and text styles of "' + MenuFxNames[FCur] + '"?', mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes then Exit;
  for I := 0 to MenuFxCount - 1 do
    if I <> FCur then FSet.Menus[I] := FSet.Menus[FCur];
  FDirty := True;
  UpdateCaption;
end;

procedure TFxForm.ResetClick(Sender: TObject);
var
  D: TMenuFxSet;
begin
  D := TMenuFxSet.Create;
  try
    FSet.Menus[FCur] := D.Menus[FCur];
  finally
    D.Free;
  end;
  FDirty := True;
  ToControls;
  UpdateCaption;
end;

procedure TFxForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FDirty then
    case MessageDlg('Save the menu effects before closing?', mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrYes:
        begin
          SaveClick(nil);
          CanClose := not FDirty;
        end;
      mrCancel: CanClose := False;
    end;
end;

procedure TFxForm.SavePreview(const AFile: string; T: Single);
begin
  if (FBuf.Width <> FView.Width) or (FBuf.Height <> FView.Height) then FBuf.SetSize(Max(8, FView.Width), Max(8, FView.Height));
  RenderPreview(FBuf, T);
  FBuf.SaveToFile(AFile);
end;

end.
