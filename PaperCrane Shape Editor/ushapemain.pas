unit uShapeMain;

{ Paper Crane Shape Editor: draw cut-paper shapes (uPCShape.TPCShape, .pcshape)
  for the custom maps: decorations or solid obstacles.

  A shape is a stack of polygons; each has a colour (with transparency) and a
  lift - how high the paper sheet sits, which sets the depth of its soft
  shadow. The anchor (0, 0) is the middle of the shape's foot (the red cross);
  in a map the anchor is put at a distance and a height.

  Tools: Select (click a polygon; drag it; drag a vertex), New polygon (click
  the points, double click / Enter / right click to close, Esc cancels), Insert
  vertex (click near an edge), Delete vertex, Ellipse and Rectangle (drag).
  The wheel zooms, the right or middle button pans. Polygons: colour, alpha,
  lift, up / down, duplicate, mirror, scale, delete. Ctrl+Z undoes. Presets,
  .pcshape files (saved into the game's shapes folder), PNG export. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Dialogs,
  LCLType, BGRABitmap, BGRABitmapTypes, uPCShape;

type
  TTool = (tlSelect, tlPoly, tlInsert, tlDelete, tlEllipse, tlRect);

  { TShapeForm }

  TShapeForm = class(TForm)
  private
    FShape: TPCShape;
    FUndo: TList;
    FFile: string;
    FDirty, FUpdating, FFitPending: Boolean;
    FTool: TTool;
    FSel, FVert: Integer;
    FZoom, FPanX, FPanY: Single;
    FNew: array of TPointF;          // the polygon being drawn
    FDragging, FPanning: Boolean;
    FDragStart, FMouse: TPointF;
    FPanStart: TPoint;
    FOrig: array of TPointF;
    FView: TPaintBox;
    FPolys: TListBox;
    FColor: TColorButton;
    FAlpha, FLift: TTrackBar;
    FName: TEdit;
    FSolid, FSnap, FPreview, FNight: TCheckBox;
    FPreset: TComboBox;
    FToolBtns: array[TTool] of TToggleBox;
    FStatus: TStatusBar;
    procedure BuildUI;
    function AddButton(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TButton;
    function ToScreen(P: TPointF): TPointF;
    function ToLocal(X, Y: Single): TPointF;
    function Snap(P: TPointF): TPointF;
    procedure PushUndo;
    procedure Changed;
    procedure PolysToList;
    procedure SelToControls;
    procedure UpdateCaption;
    procedure ViewPaint(Sender: TObject);
    procedure ViewDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ViewUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewDbl(Sender: TObject);
    procedure ViewWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
      var Handled: Boolean);
    procedure ToolClick(Sender: TObject);
    procedure SetTool(T: TTool);
    procedure FinishPoly;
    procedure PolySelect(Sender: TObject);
    procedure PolyEdit(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    procedure DupClick(Sender: TObject);
    procedure MirrorClick(Sender: TObject);
    procedure BiggerClick(Sender: TObject);
    procedure SmallerClick(Sender: TObject);
    procedure DelClick(Sender: TObject);
    procedure ShapeEdit(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure PngClick(Sender: TObject);
    procedure PresetClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    function GameDir: string;
    procedure ScaleSel(K: Single);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenFile(const AFile: string);
    procedure SavePngTo(const AFile: string);
  end;

var
  ShapeForm: TShapeForm;

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
  ToolNames: array[TTool] of string = ('Select', 'New polygon', 'Insert vertex', 'Delete vertex', 'Ellipse',
    'Rectangle');

constructor TShapeForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'Paper Crane Shape Editor';
  Width := Scale96ToForm(1240);
  Height := Scale96ToForm(800);
  Position := poScreenCenter;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  FShape := TPCShape.Create;
  MakeShapePreset(FShape, 'Lotus');
  FUndo := TList.Create;
  FZoom := 2.5;
  FSel := -1;
  FVert := -1;
  BuildUI;
  SetTool(tlSelect);
  FFitPending := True;
  PolysToList;
  FName.Text := FShape.Name;
end;

destructor TShapeForm.Destroy;
var
  I: Integer;
begin
  for I := 0 to FUndo.Count - 1 do TPCShape(FUndo[I]).Free;
  FUndo.Free;
  FShape.Free;
  inherited Destroy;
end;

function TShapeForm.GameDir: string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'Paper Crane Papercut Game SDL3') + PathDelim;
end;

function TShapeForm.AddButton(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.AutoSize := True;
  Result.Align := alLeft;
  Result.BorderSpacing.Around := 3;
  Result.Left := NextSeq;
  Result.OnClick := AHandler;
end;

procedure TShapeForm.BuildUI;
var
  Bar, Tools, Side, Row: TPanel;
  T: TTool;
  S: string;

  function Lbl(AParent: TWinControl; const C: string): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := AParent;
    Result.Caption := C;
    Result.Align := alTop;
    Result.Top := NextSeq;
    Result.BorderSpacing.Left := 6;
    Result.BorderSpacing.Top := 4;
  end;

  function Check(AParent: TWinControl; const C: string; V: Boolean): TCheckBox;
  begin
    Result := TCheckBox.Create(Self);
    Result.Parent := AParent;
    Result.Caption := C;
    Result.Checked := V;
    Result.Align := alLeft;
    Result.Left := NextSeq;
    Result.BorderSpacing.Left := 8;
    Result.OnClick := @ShapeEdit;
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
  AddButton(Bar, 'Export PNG...', @PngClick);
  AddButton(Bar, 'Undo', @UndoClick);
  AddButton(Bar, 'Fit', @FitClick);
  FPreset := TComboBox.Create(Self);
  FPreset.Parent := Bar;
  FPreset.Style := csDropDownList;
  for S in ShapePresetNames do FPreset.Items.Add(S);
  FPreset.ItemIndex := 0;
  FPreset.Align := alLeft;
  FPreset.Left := NextSeq;
  FPreset.Width := Scale96ToForm(130);
  FPreset.BorderSpacing.Around := 5;
  AddButton(Bar, 'Load preset', @PresetClick);
  FSnap := Check(Bar, 'Snap to grid (5)', True);
  FPreview := Check(Bar, 'Preview (no handles)', False);
  FNight := Check(Bar, 'Night paper', False);

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
    FToolBtns[T].Caption := Format('%d %s', [Ord(T) + 1, ToolNames[T]]);
    FToolBtns[T].Align := alLeft;
    FToolBtns[T].Left := 1000 + Ord(T);
    FToolBtns[T].Width := Scale96ToForm(118);
    FToolBtns[T].BorderSpacing.Around := 3;
    FToolBtns[T].Tag := Ord(T);
    FToolBtns[T].OnClick := @ToolClick;
  end;

  Side := TPanel.Create(Self);
  Side.Parent := Self;
  Side.Align := alRight;
  Side.Width := Scale96ToForm(270);
  Side.BevelOuter := bvNone;
  Lbl(Side, 'Shape name');
  FName := TEdit.Create(Self);
  FName.Parent := Side;
  FName.Align := alTop;
  FName.Top := NextSeq;
  FName.BorderSpacing.Around := 4;
  FName.OnChange := @ShapeEdit;
  FSolid := TCheckBox.Create(Self);
  FSolid.Parent := Side;
  FSolid.Caption := 'Solid by default (the crane hits it)';
  FSolid.Align := alTop;
  FSolid.Top := NextSeq;
  FSolid.BorderSpacing.Left := 6;
  FSolid.OnClick := @ShapeEdit;
  Lbl(Side, 'Polygons (first = bottom)');
  FPolys := TListBox.Create(Self);
  FPolys.Parent := Side;
  FPolys.Align := alTop;
  FPolys.Top := NextSeq;
  FPolys.Height := Scale96ToForm(220);
  FPolys.BorderSpacing.Around := 4;
  FPolys.OnClick := @PolySelect;
  Row := TPanel.Create(Self);
  Row.Parent := Side;
  Row.Align := alTop;
  Row.Top := NextSeq;
  Row.Height := Scale96ToForm(34);
  Row.BevelOuter := bvNone;
  AddButton(Row, 'Up', @UpClick);
  AddButton(Row, 'Down', @DownClick);
  AddButton(Row, 'Copy', @DupClick);
  AddButton(Row, 'Delete', @DelClick);
  Row := TPanel.Create(Self);
  Row.Parent := Side;
  Row.Align := alTop;
  Row.Top := NextSeq;
  Row.Height := Scale96ToForm(34);
  Row.BevelOuter := bvNone;
  AddButton(Row, 'Mirror', @MirrorClick);
  AddButton(Row, 'Bigger', @BiggerClick);
  AddButton(Row, 'Smaller', @SmallerClick);
  Lbl(Side, 'Colour');
  FColor := TColorButton.Create(Self);
  FColor.Parent := Side;
  FColor.Align := alTop;
  FColor.Top := NextSeq;
  FColor.Height := Scale96ToForm(30);
  FColor.BorderSpacing.Around := 4;
  FColor.OnColorChanged := @PolyEdit;
  Lbl(Side, 'Opacity');
  FAlpha := TTrackBar.Create(Self);
  FAlpha.Parent := Side;
  FAlpha.Min := 10; FAlpha.Max := 255; FAlpha.TickStyle := tsNone;
  FAlpha.Align := alTop; FAlpha.Top := NextSeq; FAlpha.Height := Scale96ToForm(28);
  FAlpha.OnChange := @PolyEdit;
  Lbl(Side, 'Lift (shadow depth)');
  FLift := TTrackBar.Create(Self);
  FLift.Parent := Side;
  FLift.Min := 0; FLift.Max := 100; FLift.TickStyle := tsNone;
  FLift.Align := alTop; FLift.Top := NextSeq; FLift.Height := Scale96ToForm(28);
  FLift.OnChange := @PolyEdit;
  Lbl(Side, 'Keys: 1-6 tools, Del polygon, Ctrl+Z undo,'#13'Enter closes a polygon, wheel zoom,'#13'right / middle drag pans');

  FView := TPaintBox.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.OnPaint := @ViewPaint;
  FView.OnMouseDown := @ViewDown;
  FView.OnMouseMove := @ViewMove;
  FView.OnMouseUp := @ViewUp;
  FView.OnDblClick := @ViewDbl;
  FView.OnMouseWheel := @ViewWheel;
end;

function TShapeForm.ToScreen(P: TPointF): TPointF;
begin
  Result.X := FView.Width / 2 + (P.X - FPanX) * FZoom;
  Result.Y := FView.Height * 0.78 + (P.Y - FPanY) * FZoom;
end;

function TShapeForm.ToLocal(X, Y: Single): TPointF;
begin
  Result.X := (X - FView.Width / 2) / FZoom + FPanX;
  Result.Y := (Y - FView.Height * 0.78) / FZoom + FPanY;
end;

function TShapeForm.Snap(P: TPointF): TPointF;
begin
  if FSnap.Checked then Result := PointF(Round(P.X / 5) * 5, Round(P.Y / 5) * 5) else Result := P;
end;

procedure TShapeForm.PushUndo;
var
  U: TPCShape;
begin
  U := TPCShape.Create;
  U.Assign(FShape);
  FUndo.Add(U);
  while FUndo.Count > 80 do
  begin
    TPCShape(FUndo[0]).Free;
    FUndo.Delete(0);
  end;
end;

procedure TShapeForm.Changed;
begin
  FDirty := True;
  PolysToList;
  UpdateCaption;
  FView.Invalidate;
end;

procedure TShapeForm.UpdateCaption;
var
  N: string;
  R: TRectF;
begin
  if FFile = '' then N := 'untitled' else N := ExtractFileName(FFile);
  R := FShape.Bounds;
  Caption := 'Paper Crane Shape Editor - ' + N + IfThen(FDirty, ' *', '') +
    Format('   (%d polygons, %d x %d design px)', [Length(FShape.Polys), Round(R.Right - R.Left), Round(R.Bottom - R.Top)]);
end;

procedure TShapeForm.PolysToList;
var
  I: Integer;
begin
  FPolys.Items.BeginUpdate;
  try
    FPolys.Items.Clear;
    for I := 0 to High(FShape.Polys) do
      FPolys.Items.Add(Format('%d  %s  lift %.2f  (%d pts)', [I + 1, ColorToHex(FShape.Polys[I].Color),
        FShape.Polys[I].Lift, Length(FShape.Polys[I].Pts)]));
  finally
    FPolys.Items.EndUpdate;
  end;
  if FSel > High(FShape.Polys) then FSel := -1;
  FPolys.ItemIndex := FSel;
  SelToControls;
end;

procedure TShapeForm.SelToControls;
begin
  FUpdating := True;
  try
    FSolid.Checked := FShape.Solid;
    if FSel >= 0 then
      with FShape.Polys[FSel] do
      begin
        FColor.ButtonColor := RGBToColor(Color.red, Color.green, Color.blue);
        FAlpha.Position := Color.alpha;
        FLift.Position := Round(Lift * 100);
      end;
  finally
    FUpdating := False;
  end;
end;

procedure TShapeForm.ViewPaint(Sender: TObject);
var
  B: TBGRABitmap;
  W, H, I, K: Integer;
  G, X: Single;
  O, P: TPointF;
  Pts: array of TPointF;
  BG, GridC: TBGRAPixel;
begin
  W := FView.Width;
  H := FView.Height;
  if (W < 4) or (H < 4) then Exit;
  if FFitPending and (W >= 200) then FitClick(nil);
  if FNight.Checked then
  begin
    BG := BGRA(28, 38, 70);
    GridC := BGRA(50, 62, 100);
  end
  else
  begin
    BG := BGRA(246, 238, 222);
    GridC := BGRA(228, 216, 196);
  end;
  B := TBGRABitmap.Create(W, H, BG);
  try
    // grid every 10 design px (every 50 stronger)
    G := 10;
    X := Floor(ToLocal(0, 0).X / G) * G;
    while ToScreen(PointF(X, 0)).X < W do
    begin
      P := ToScreen(PointF(X, 0));
      if Round(X) mod 50 = 0 then B.DrawLineAntialias(P.X, 0, P.X, H, BGRA(GridC.red * 9 div 10, GridC.green * 9 div 10, GridC.blue * 9 div 10), 1)
      else if FZoom >= 2 then B.DrawLineAntialias(P.X, 0, P.X, H, GridC, 1);
      X := X + G;
    end;
    X := Floor(ToLocal(0, 0).Y / G) * G;
    while ToScreen(PointF(0, X)).Y < H do
    begin
      P := ToScreen(PointF(0, X));
      if Round(X) mod 50 = 0 then B.DrawLineAntialias(0, P.Y, W, P.Y, BGRA(GridC.red * 9 div 10, GridC.green * 9 div 10, GridC.blue * 9 div 10), 1)
      else if FZoom >= 2 then B.DrawLineAntialias(0, P.Y, W, P.Y, GridC, 1);
      X := X + G;
    end;
    // the ground line and the anchor
    O := ToScreen(PointF(0, 0));
    B.DrawLineAntialias(0, O.Y, W, O.Y, BGRA(90, 140, 190, 160), 2);
    B.DrawLineAntialias(O.X - 12, O.Y, O.X + 12, O.Y, BGRA(200, 40, 30), 2);
    B.DrawLineAntialias(O.X, O.Y - 12, O.X, O.Y + 12, BGRA(200, 40, 30), 2);
    // the shape itself, papercut
    FShape.Draw(B, O.X - FPanX * FZoom * 0, O.Y, FZoom, False, True);
    if not FPreview.Checked then
    begin
      // the selected polygon: outline and vertex handles
      if FSel >= 0 then
      begin
        SetLength(Pts, Length(FShape.Polys[FSel].Pts) + 1);
        for K := 0 to High(FShape.Polys[FSel].Pts) do Pts[K] := ToScreen(FShape.Polys[FSel].Pts[K]);
        if Length(Pts) > 1 then Pts[High(Pts)] := Pts[0];
        B.DrawPolyLineAntialias(Pts, BGRA(40, 110, 220), 2);
        for K := 0 to High(FShape.Polys[FSel].Pts) do
        begin
          P := ToScreen(FShape.Polys[FSel].Pts[K]);
          if K = FVert then B.FillRectAntialias(P.X - 5, P.Y - 5, P.X + 5, P.Y + 5, BGRA(220, 60, 40))
          else B.FillRectAntialias(P.X - 4, P.Y - 4, P.X + 4, P.Y + 4, BGRA(255, 255, 255));
          B.RectangleAntialias(P.X - 4, P.Y - 4, P.X + 4, P.Y + 4, BGRA(40, 110, 220), 1);
        end;
      end;
      // the polygon being drawn
      if Length(FNew) > 0 then
      begin
        SetLength(Pts, Length(FNew) + 1);
        for K := 0 to High(FNew) do Pts[K] := ToScreen(FNew[K]);
        Pts[High(Pts)] := ToScreen(Snap(FMouse));
        B.DrawPolyLineAntialias(Pts, BGRA(220, 60, 40), 2);
        for K := 0 to High(FNew) do
          B.FillEllipseAntialias(Pts[K].X, Pts[K].Y, 4, 4, BGRA(220, 60, 40));
      end;
      // a rectangle / ellipse being dragged
      if FDragging and (FTool in [tlEllipse, tlRect]) then
      begin
        P := ToScreen(Snap(FDragStart));
        O := ToScreen(Snap(FMouse));
        if FTool = tlRect then B.RectangleAntialias(P.X, P.Y, O.X, O.Y, BGRA(220, 60, 40), 2)
        else B.EllipseAntialias((P.X + O.X) / 2, (P.Y + O.Y) / 2, Abs(O.X - P.X) / 2, Abs(O.Y - P.Y) / 2,
          BGRA(220, 60, 40), 2);
      end;
    end;
    B.TextOut(8, 6, Format('zoom %.1fx   tool: %s', [FZoom, ToolNames[FTool]]), BGRA(150, 70, 50));
    B.Draw(FView.Canvas, 0, 0, True);
  finally
    B.Free;
  end;
end;

procedure TShapeForm.SetTool(T: TTool);
var
  X: TTool;
begin
  if (FTool = tlPoly) and (T <> tlPoly) then SetLength(FNew, 0);
  FTool := T;
  for X := Low(TTool) to High(TTool) do FToolBtns[X].Checked := X = T;
  FView.Invalidate;
end;

procedure TShapeForm.ToolClick(Sender: TObject);
begin
  SetTool(TTool(TToggleBox(Sender).Tag));
end;

{ the vertex of the selected polygon near a screen point, -1 none }
function NearVertex(F: TShapeForm; X, Y: Integer): Integer;
var
  K: Integer;
  P: TPointF;
begin
  Result := -1;
  if F.FSel < 0 then Exit;
  for K := 0 to High(F.FShape.Polys[F.FSel].Pts) do
  begin
    P := F.ToScreen(F.FShape.Polys[F.FSel].Pts[K]);
    if (Abs(P.X - X) <= 6) and (Abs(P.Y - Y) <= 6) then Exit(K);
  end;
end;

procedure TShapeForm.ViewDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  L: TPointF;
  I, K, Best: Integer;
  D, BestD: Single;
  A, Z: TPointF;
begin
  L := ToLocal(X, Y);
  FMouse := L;
  if (Button = mbMiddle) or ((Button = mbRight) and (FTool <> tlPoly)) then
  begin
    FPanning := True;
    FPanStart := Point(X, Y);
    FDragStart := PointF(FPanX, FPanY);
    Exit;
  end;
  if (Button = mbRight) and (FTool = tlPoly) then
  begin
    FinishPoly;
    Exit;
  end;
  case FTool of
    tlSelect:
      begin
        K := NearVertex(Self, X, Y);
        if K >= 0 then
        begin
          PushUndo;
          FVert := K;
          FDragging := True;
          Exit;
        end;
        FVert := -1;
        FSel := FShape.HitTest(L.X, L.Y);
        if FSel >= 0 then
        begin
          PushUndo;
          FDragging := True;
          FDragStart := L;
          FOrig := Copy(FShape.Polys[FSel].Pts);
        end;
        PolysToList;
        FView.Invalidate;
      end;
    tlPoly:
      begin
        SetLength(FNew, Length(FNew) + 1);
        FNew[High(FNew)] := Snap(L);
        FView.Invalidate;
      end;
    tlInsert:
      if FSel >= 0 then
      begin
        // the nearest edge of the selected polygon gets a new vertex
        Best := -1;
        BestD := 1e9;
        with FShape.Polys[FSel] do
          for I := 0 to High(Pts) do
          begin
            A := ToScreen(Pts[I]);
            Z := ToScreen(Pts[(I + 1) mod Length(Pts)]);
            D := Sqr((A.X + Z.X) / 2 - X) + Sqr((A.Y + Z.Y) / 2 - Y);
            if D < BestD then
            begin
              BestD := D;
              Best := I;
            end;
          end;
        if Best >= 0 then
        begin
          PushUndo;
          with FShape.Polys[FSel] do
          begin
            SetLength(Pts, Length(Pts) + 1);
            for I := High(Pts) downto Best + 2 do Pts[I] := Pts[I - 1];
            Pts[Best + 1] := Snap(L);
          end;
          Changed;
        end;
      end;
    tlDelete:
      begin
        K := NearVertex(Self, X, Y);
        if (K >= 0) and (Length(FShape.Polys[FSel].Pts) > 3) then
        begin
          PushUndo;
          with FShape.Polys[FSel] do
          begin
            for I := K to High(Pts) - 1 do Pts[I] := Pts[I + 1];
            SetLength(Pts, Length(Pts) - 1);
          end;
          Changed;
        end;
      end;
    tlEllipse, tlRect:
      begin
        FDragging := True;
        FDragStart := L;
      end;
  end;
end;

procedure TShapeForm.ViewMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  L, Dl: TPointF;
  K: Integer;
begin
  L := ToLocal(X, Y);
  FMouse := L;
  FStatus.SimpleText := Format('x %d   y %d   (anchor 0, 0 = the foot of the shape)', [Round(L.X), Round(L.Y)]);
  if FPanning then
  begin
    FPanX := FDragStart.X - (X - FPanStart.X) / FZoom;
    FPanY := FDragStart.Y - (Y - FPanStart.Y) / FZoom;
    FView.Invalidate;
    Exit;
  end;
  if FDragging and (FTool = tlSelect) and (FSel >= 0) then
  begin
    if FVert >= 0 then
      FShape.Polys[FSel].Pts[FVert] := Snap(L)
    else
    begin
      Dl := Snap(PointF(L.X - FDragStart.X, L.Y - FDragStart.Y));
      for K := 0 to High(FOrig) do
        FShape.Polys[FSel].Pts[K] := PointF(FOrig[K].X + Dl.X, FOrig[K].Y + Dl.Y);
    end;
    FDirty := True;
  end;
  if FDragging or (Length(FNew) > 0) then FView.Invalidate;
end;

procedure TShapeForm.ViewUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  A, Z: TPointF;
  Pts: array of TPointF;
  I: Integer;
begin
  if FPanning then
  begin
    FPanning := False;
    Exit;
  end;
  if FDragging and (FTool in [tlEllipse, tlRect]) then
  begin
    A := Snap(FDragStart);
    Z := Snap(ToLocal(X, Y));
    if (Abs(Z.X - A.X) >= 3) and (Abs(Z.Y - A.Y) >= 3) then
    begin
      PushUndo;
      if FTool = tlRect then
        FSel := FShape.AddPoly([A, PointF(Z.X, A.Y), Z, PointF(A.X, Z.Y)], BGRA(200, 60, 50), 0.4)
      else
      begin
        SetLength(Pts, 28);
        for I := 0 to 27 do
          Pts[I] := PointF((A.X + Z.X) / 2 + Cos(I * 2 * Pi / 28) * Abs(Z.X - A.X) / 2,
            (A.Y + Z.Y) / 2 + Sin(I * 2 * Pi / 28) * Abs(Z.Y - A.Y) / 2);
        FSel := FShape.AddPoly(Pts, BGRA(236, 150, 170), 0.4);
      end;
      Changed;
    end;
  end;
  if FDragging then Changed;
  FDragging := False;
end;

procedure TShapeForm.ViewDbl(Sender: TObject);
begin
  if FTool = tlPoly then FinishPoly;
end;

procedure TShapeForm.FinishPoly;
begin
  if Length(FNew) >= 3 then
  begin
    PushUndo;
    FSel := FShape.AddPoly(FNew, BGRA(90, 140, 90), 0.4);
    Changed;
  end;
  SetLength(FNew, 0);
  FView.Invalidate;
end;

procedure TShapeForm.ViewWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
  var Handled: Boolean);
begin
  if WheelDelta > 0 then FZoom := Min(20, FZoom * 1.15) else FZoom := Max(0.3, FZoom / 1.15);
  FView.Invalidate;
  Handled := True;
end;

procedure TShapeForm.PolySelect(Sender: TObject);
begin
  FSel := FPolys.ItemIndex;
  FVert := -1;
  SelToControls;
  FView.Invalidate;
end;

procedure TShapeForm.PolyEdit(Sender: TObject);
var
  C: TColor;
begin
  if FUpdating or (FSel < 0) then Exit;
  PushUndo;
  C := FColor.ButtonColor;
  FShape.Polys[FSel].Color := BGRA(Red(C), Green(C), Blue(C), FAlpha.Position);
  FShape.Polys[FSel].Lift := FLift.Position / 100;
  Changed;
end;

procedure TShapeForm.ShapeEdit(Sender: TObject);
begin
  if FUpdating then Exit;
  if Sender = FName then FShape.Name := FName.Text
  else if Sender = FSolid then FShape.Solid := FSolid.Checked;
  FView.Invalidate;
  if (Sender = FName) or (Sender = FSolid) then
  begin
    FDirty := True;
    UpdateCaption;
  end;
end;

procedure TShapeForm.UpClick(Sender: TObject);
begin
  if FSel < 0 then Exit;
  PushUndo;
  FShape.MovePoly(FSel, 1);
  FSel := Min(FSel + 1, High(FShape.Polys));
  Changed;
end;

procedure TShapeForm.DownClick(Sender: TObject);
begin
  if FSel < 0 then Exit;
  PushUndo;
  FShape.MovePoly(FSel, -1);
  FSel := Max(FSel - 1, 0);
  Changed;
end;

procedure TShapeForm.DupClick(Sender: TObject);
var
  I, J: Integer;
begin
  if FSel < 0 then Exit;
  PushUndo;
  I := FShape.AddPoly(FShape.Polys[FSel].Pts, FShape.Polys[FSel].Color, FShape.Polys[FSel].Lift);
  for J := 0 to High(FShape.Polys[I].Pts) do
    FShape.Polys[I].Pts[J].X := FShape.Polys[I].Pts[J].X + 10;
  FVert := -1;
  FSel := I;
  Changed;
end;

procedure TShapeForm.MirrorClick(Sender: TObject);
var
  I, K: Integer;
begin
  PushUndo;
  for I := 0 to High(FShape.Polys) do
    if (FSel < 0) or (I = FSel) then
      for K := 0 to High(FShape.Polys[I].Pts) do
        FShape.Polys[I].Pts[K].X := -FShape.Polys[I].Pts[K].X;
  Changed;
end;

procedure TShapeForm.ScaleSel(K: Single);
var
  I, J: Integer;
begin
  PushUndo;
  for I := 0 to High(FShape.Polys) do
    if (FSel < 0) or (I = FSel) then
      for J := 0 to High(FShape.Polys[I].Pts) do
        FShape.Polys[I].Pts[J] := PointF(FShape.Polys[I].Pts[J].X * K, FShape.Polys[I].Pts[J].Y * K);
  Changed;
end;

procedure TShapeForm.BiggerClick(Sender: TObject);
begin
  ScaleSel(1.1);
end;

procedure TShapeForm.SmallerClick(Sender: TObject);
begin
  ScaleSel(1 / 1.1);
end;

procedure TShapeForm.DelClick(Sender: TObject);
begin
  if FSel < 0 then Exit;
  PushUndo;
  FShape.DeletePoly(FSel);
  FSel := -1;
  Changed;
end;

procedure TShapeForm.NewClick(Sender: TObject);
begin
  PushUndo;
  FShape.Clear;
  FFile := '';
  FSel := -1;
  FDirty := False;
  FName.Text := FShape.Name;
  Changed;
end;

procedure TShapeForm.OpenFile(const AFile: string);
begin
  PushUndo;
  FShape.LoadFromFile(AFile);
  FFile := AFile;
  FSel := -1;
  FDirty := False;
  FUpdating := True;
  FName.Text := FShape.Name;
  FUpdating := False;
  PolysToList;
  FitClick(nil);
  UpdateCaption;
  FStatus.SimpleText := 'opened ' + AFile;
end;

procedure TShapeForm.OpenClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Paper Crane shape (*.pcshape)|*.pcshape|All files|*.*';
    if DirectoryExists(GameDir + 'shapes') then D.InitialDir := GameDir + 'shapes';
    if D.Execute then OpenFile(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TShapeForm.SaveClick(Sender: TObject);
begin
  if FFile = '' then
  begin
    SaveAsClick(Sender);
    Exit;
  end;
  FShape.SaveToFile(FFile);
  FDirty := False;
  UpdateCaption;
  FStatus.SimpleText := 'saved ' + FFile;
end;

procedure TShapeForm.SaveAsClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'Paper Crane shape (*.pcshape)|*.pcshape';
    D.DefaultExt := 'pcshape';
    ForceDirectories(GameDir + 'shapes');
    D.InitialDir := GameDir + 'shapes';
    D.FileName := StringReplace(FShape.Name, ' ', '_', [rfReplaceAll]) + '.pcshape';
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
    begin
      FFile := D.FileName;
      SaveClick(Sender);
    end;
  finally
    D.Free;
  end;
end;

procedure TShapeForm.SavePngTo(const AFile: string);
var
  R: TRectF;
  B: TBGRABitmap;
  K: Single;
begin
  R := FShape.Bounds;
  K := 2;
  B := TBGRABitmap.Create(Max(8, Round((R.Right - R.Left) * K) + 40), Max(8, Round((R.Bottom - R.Top) * K) + 40));
  try
    FShape.Draw(B, 20 - R.Left * K, 20 - R.Top * K, K, False, True);
    B.SaveToFile(AFile);
  finally
    B.Free;
  end;
end;

procedure TShapeForm.PngClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'PNG (*.png)|*.png';
    D.DefaultExt := 'png';
    D.FileName := StringReplace(FShape.Name, ' ', '_', [rfReplaceAll]) + '.png';
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
    begin
      SavePngTo(D.FileName);
      FStatus.SimpleText := 'exported ' + D.FileName;
    end;
  finally
    D.Free;
  end;
end;

procedure TShapeForm.PresetClick(Sender: TObject);
begin
  PushUndo;
  MakeShapePreset(FShape, FPreset.Text);
  FSel := -1;
  FUpdating := True;
  FName.Text := FShape.Name;
  FUpdating := False;
  FitClick(nil);
  Changed;
end;

procedure TShapeForm.UndoClick(Sender: TObject);
begin
  if FUndo.Count = 0 then Exit;
  FShape.Assign(TPCShape(FUndo[FUndo.Count - 1]));
  TPCShape(FUndo[FUndo.Count - 1]).Free;
  FUndo.Delete(FUndo.Count - 1);
  FSel := -1;
  Changed;
end;

procedure TShapeForm.FitClick(Sender: TObject);
var
  R: TRectF;
begin
  R := FShape.Bounds;
  if R.Right - R.Left < 1 then Exit;
  FFitPending := FView.Width < 200;   // not laid out yet: fit on the first paint
  if FFitPending then Exit;
  FZoom := EnsureRange(Min(FView.Width * 0.7 / (R.Right - R.Left), FView.Height * 0.6 / Max(1, R.Bottom - R.Top)),
    0.3, 20);
  FPanX := (R.Left + R.Right) / 2;
  FPanY := 0;
  FView.Invalidate;
end;

procedure TShapeForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if ActiveControl is TEdit then Exit;
  case Key of
    VK_1..VK_6: if Shift = [] then
      begin
        SetTool(TTool(Key - VK_1));
        Key := 0;
      end;
    VK_RETURN: if FTool = tlPoly then FinishPoly;
    VK_ESCAPE:
      begin
        SetLength(FNew, 0);
        FView.Invalidate;
      end;
    VK_DELETE: DelClick(nil);
    VK_Z: if ssCtrl in Shift then UndoClick(nil);
    VK_S: if ssCtrl in Shift then SaveClick(nil);
  end;
end;

end.
