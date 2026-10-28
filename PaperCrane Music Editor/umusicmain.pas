unit uMusicMain;

{ Paper Crane Music Editor: write tunes for the game on a piano roll, without
  SDL. A tune (uSynth.TSong, .pcmusic) has tracks; each track plays one of the
  game's synthesised Chinese instruments (guzheng, pipa, dizi, erhu, bells,
  drums, gong ...) with a volume and a pan, and holds notes (step, length,
  pitch, velocity) on a 16th-note grid.

  Piano roll: rows are pitches (the scale's notes are highlighted, the root
  darker), columns are 16th steps (beats and bars marked). The selected track
  is drawn strong, the others faint. Left click on empty space adds a note of
  the chosen length, on a note selects it; drag a note to move it, drag its
  right end to change its length; right click deletes. Ctrl+Z undoes.

  Play renders the whole tune (seamless loop, echo) and plays it with Windows
  PlaySound; a playhead follows. The game's 7 built-in tunes can be imported
  and changed. A map can use a .pcmusic file from the game's music folder. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Spin,
  Dialogs, LCLType, uSynth;

type
  { TMusicForm }

  TMusicForm = class(TForm)
  private
    FSong: TSong;
    FUndo: TList;
    FFile: string;
    FDirty, FUpdating: Boolean;
    FTrack, FSelNote: Integer;
    FPlayT0: QWord;
    FPlayLen: Double;
    FPlaying: Boolean;
    FDrag: Integer;          // 0 none, 1 move, 2 resize
    FDragStep, FDragPitch, FDragNoteStep, FDragNotePitch, FDragLen: Integer;
    FStepW, FRowH: Integer;
    FName: TEdit;
    FBpm, FBars, FRoot, FNoteLen, FVel: TSpinEdit;
    FScale, FImport, FInstr: TComboBox;
    FEcho, FVol, FPan: TTrackBar;
    FTracks: TListBox;
    FMute, FLoop: TCheckBox;
    FScroll: TScrollBox;
    FRoll: TPaintBox;
    FTimer: TTimer;
    FStatus: TStatusBar;
    procedure BuildUI;
    function AddButton(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TButton;
    function AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
    procedure SongToControls;
    procedure TracksToList;
    procedure TrackToControls;
    procedure PushUndo;
    procedure Changed;
    procedure UpdateCaption;
    function PitchAt(Y: Integer): Integer;
    function StepAt(X: Integer): Integer;
    function NoteAt(X, Y: Integer): Integer;
    procedure ResizeRoll;
    procedure RollPaint(Sender: TObject);
    procedure RollDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure RollMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure RollUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure SongEdit(Sender: TObject);
    procedure TrackEdit(Sender: TObject);
    procedure TrackSelect(Sender: TObject);
    procedure AddTrackClick(Sender: TObject);
    procedure DelTrackClick(Sender: TObject);
    procedure ClearTrackClick(Sender: TObject);
    procedure PlayClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure WavClick(Sender: TObject);
    procedure ImportClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure ZoomIn(Sender: TObject);
    procedure ZoomOut(Sender: TObject);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    function GameDir: string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenFile(const AFile: string);
  end;

var
  MusicForm: TMusicForm;

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
  LowPitch = 33;
  HighPitch = 96;

constructor TMusicForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'Paper Crane Music Editor';
  Width := Scale96ToForm(1280);
  Height := Scale96ToForm(800);
  Position := poScreenCenter;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  FStepW := 14;
  FRowH := 12;
  FUndo := TList.Create;
  FSong := BuiltinSong(0);
  FSelNote := -1;
  BuildUI;
  SongToControls;
  TracksToList;
  FTracks.ItemIndex := 0;
  TrackSelect(nil);
  ResizeRoll;
end;

destructor TMusicForm.Destroy;
var
  I: Integer;
begin
  StopPcm;
  for I := 0 to FUndo.Count - 1 do TSong(FUndo[I]).Free;
  FUndo.Free;
  FSong.Free;
  inherited Destroy;
end;

function TMusicForm.GameDir: string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'Paper Crane Papercut Game SDL3') + PathDelim;
end;

function TMusicForm.AddButton(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TButton;
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

function TMusicForm.AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Align := alLeft;
  Result.Layout := tlCenter;
  Result.Left := NextSeq;
  Result.BorderSpacing.Left := 8;
  Result.BorderSpacing.Right := 3;
end;

procedure TMusicForm.BuildUI;
var
  Bar, Bar2, LeftP, Row: TPanel;
  I: Integer;
  In_: TInstrument;

  function Spin(AParent: TWinControl; Lo, Hi, W: Integer): TSpinEdit;
  begin
    Result := TSpinEdit.Create(Self);
    Result.Parent := AParent;
    Result.MinValue := Lo;
    Result.MaxValue := Hi;
    Result.Align := alLeft;
    Result.Left := NextSeq;
    Result.Width := Scale96ToForm(W);
    Result.BorderSpacing.Around := 4;
  end;

  function Track(AParent: TWinControl; Lo, Hi, W: Integer): TTrackBar;
  begin
    Result := TTrackBar.Create(Self);
    Result.Parent := AParent;
    Result.Min := Lo;
    Result.Max := Hi;
    Result.TickStyle := tsNone;
    Result.Align := alLeft;
    Result.Left := NextSeq;
    Result.Width := Scale96ToForm(W);
  end;

begin
  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;
  // files and playback
  Bar := TPanel.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := Scale96ToForm(38);
  Bar.BevelOuter := bvNone;
  AddButton(Bar, 'New', @NewClick);
  AddButton(Bar, 'Open...', @OpenClick);
  AddButton(Bar, 'Save', @SaveClick);
  AddButton(Bar, 'Save as...', @SaveAsClick);
  AddButton(Bar, 'Export WAV...', @WavClick);
  AddButton(Bar, 'Undo', @UndoClick);
  AddButton(Bar, '  Play (Space)  ', @PlayClick);
  AddButton(Bar, 'Stop', @StopClick);
  FLoop := TCheckBox.Create(Self);
  FLoop.Parent := Bar;
  FLoop.Caption := 'Loop';
  FLoop.Checked := True;
  FLoop.Align := alLeft;
  FLoop.Left := NextSeq;
  FLoop.BorderSpacing.Left := 8;
  AddLabel(Bar, 'Game tune:');
  FImport := TComboBox.Create(Self);
  FImport.Parent := Bar;
  FImport.Style := csDropDownList;
  for I := 0 to BuiltinCount - 1 do FImport.Items.Add(BuiltinNames[I]);
  FImport.ItemIndex := 0;
  FImport.Align := alLeft;
  FImport.Left := NextSeq;
  FImport.Width := Scale96ToForm(150);
  FImport.BorderSpacing.Around := 5;
  AddButton(Bar, 'Import', @ImportClick);
  AddButton(Bar, 'Zoom +', @ZoomIn);
  AddButton(Bar, 'Zoom -', @ZoomOut);
  // the tune
  Bar2 := TPanel.Create(Self);
  Bar2.Parent := Self;
  Bar2.Align := alTop;
  Bar2.Top := 100;
  Bar2.Height := Scale96ToForm(36);
  Bar2.BevelOuter := bvNone;
  AddLabel(Bar2, 'Name');
  FName := TEdit.Create(Self);
  FName.Parent := Bar2;
  FName.Align := alLeft;
  FName.Left := NextSeq;
  FName.Width := Scale96ToForm(170);
  FName.BorderSpacing.Around := 4;
  FName.OnChange := @SongEdit;
  AddLabel(Bar2, 'BPM');
  FBpm := Spin(Bar2, 30, 240, 60);
  FBpm.OnChange := @SongEdit;
  AddLabel(Bar2, 'Bars');
  FBars := Spin(Bar2, 1, 64, 55);
  FBars.OnChange := @SongEdit;
  AddLabel(Bar2, 'Root (midi)');
  FRoot := Spin(Bar2, 36, 84, 55);
  FRoot.OnChange := @SongEdit;
  AddLabel(Bar2, 'Scale');
  FScale := TComboBox.Create(Self);
  FScale.Parent := Bar2;
  FScale.Style := csDropDownList;
  for I := 0 to 2 do FScale.Items.Add(ScaleNames[I]);
  FScale.Align := alLeft;
  FScale.Left := NextSeq;
  FScale.Width := Scale96ToForm(170);
  FScale.BorderSpacing.Around := 4;
  FScale.OnChange := @SongEdit;
  AddLabel(Bar2, 'Echo');
  FEcho := Track(Bar2, 0, 60, 100);
  FEcho.OnChange := @SongEdit;
  AddLabel(Bar2, 'New note: length');
  FNoteLen := Spin(Bar2, 1, 64, 50);
  FNoteLen.Value := 4;
  AddLabel(Bar2, 'velocity %');
  FVel := Spin(Bar2, 1, 100, 50);
  FVel.Value := 30;
  // tracks
  LeftP := TPanel.Create(Self);
  LeftP.Parent := Self;
  LeftP.Align := alLeft;
  LeftP.Width := Scale96ToForm(230);
  LeftP.BevelOuter := bvNone;
  Row := TPanel.Create(Self);
  Row.Parent := LeftP;
  Row.Align := alBottom;
  Row.Height := Scale96ToForm(190);
  Row.BevelOuter := bvNone;
  FInstr := TComboBox.Create(Self);
  FInstr.Parent := Row;
  FInstr.Style := csDropDownList;
  for In_ := Low(TInstrument) to High(TInstrument) do FInstr.Items.Add(InstrumentNames[In_]);
  FInstr.Align := alTop;
  FInstr.BorderSpacing.Around := 4;
  FInstr.OnChange := @TrackEdit;
  with TLabel.Create(Self) do
  begin
    Parent := Row; Caption := ' Volume'; Align := alTop; Top := 50;
  end;
  FVol := TTrackBar.Create(Self);
  FVol.Parent := Row;
  FVol.Min := 0; FVol.Max := 150; FVol.TickStyle := tsNone;
  FVol.Align := alTop; FVol.Top := 60; FVol.Height := Scale96ToForm(28);
  FVol.OnChange := @TrackEdit;
  with TLabel.Create(Self) do
  begin
    Parent := Row; Caption := ' Pan (left - right)'; Align := alTop; Top := 90;
  end;
  FPan := TTrackBar.Create(Self);
  FPan.Parent := Row;
  FPan.Min := -100; FPan.Max := 100; FPan.TickStyle := tsNone;
  FPan.Align := alTop; FPan.Top := 100; FPan.Height := Scale96ToForm(28);
  FPan.OnChange := @TrackEdit;
  FMute := TCheckBox.Create(Self);
  FMute.Parent := Row;
  FMute.Caption := 'Mute';
  FMute.Align := alTop;
  FMute.Top := 140;
  FMute.OnClick := @TrackEdit;
  Bar := TPanel.Create(Self);
  Bar.Parent := Row;
  Bar.Align := alBottom;
  Bar.Height := Scale96ToForm(34);
  Bar.BevelOuter := bvNone;
  AddButton(Bar, 'Add', @AddTrackClick);
  AddButton(Bar, 'Delete', @DelTrackClick);
  AddButton(Bar, 'Clear', @ClearTrackClick);
  with TLabel.Create(Self) do
  begin
    Parent := LeftP; Caption := ' Tracks'; Align := alTop;
  end;
  FTracks := TListBox.Create(Self);
  FTracks.Parent := LeftP;
  FTracks.Align := alClient;
  FTracks.OnClick := @TrackSelect;
  // piano roll
  FScroll := TScrollBox.Create(Self);
  FScroll.Parent := Self;
  FScroll.Align := alClient;
  FScroll.HorzScrollBar.Tracking := True;
  FScroll.VertScrollBar.Tracking := True;
  FRoll := TPaintBox.Create(Self);
  FRoll.Parent := FScroll;
  FRoll.OnPaint := @RollPaint;
  FRoll.OnMouseDown := @RollDown;
  FRoll.OnMouseMove := @RollMove;
  FRoll.OnMouseUp := @RollUp;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 33;
  FTimer.Enabled := False;
  FTimer.OnTimer := @TimerTick;
end;

procedure TMusicForm.SongToControls;
begin
  FUpdating := True;
  try
    FName.Text := FSong.Name;
    FBpm.Value := Round(FSong.Bpm);
    FBars.Value := FSong.Bars;
    FRoot.Value := FSong.Root;
    FScale.ItemIndex := FSong.Scale;
    FEcho.Position := Round(FSong.Echo * 100);
  finally
    FUpdating := False;
  end;
  UpdateCaption;
end;

procedure TMusicForm.TracksToList;
var
  I, Keep: Integer;
begin
  Keep := FTracks.ItemIndex;
  FTracks.Items.BeginUpdate;
  try
    FTracks.Items.Clear;
    for I := 0 to High(FSong.Tracks) do
      with FSong.Tracks[I] do
        FTracks.Items.Add(Format('%s - %s (%d)%s', [Name, InstrumentNames[Instr], Length(Notes),
          IfThen(Mute, ' [mute]', '')]));
  finally
    FTracks.Items.EndUpdate;
  end;
  FTracks.ItemIndex := EnsureRange(Keep, -1, FTracks.Count - 1);
end;

procedure TMusicForm.TrackToControls;
begin
  if (FTrack < 0) or (FTrack > High(FSong.Tracks)) then Exit;
  FUpdating := True;
  try
    FInstr.ItemIndex := Ord(FSong.Tracks[FTrack].Instr);
    FVol.Position := Round(FSong.Tracks[FTrack].Vol * 100);
    FPan.Position := Round(FSong.Tracks[FTrack].Pan * 100);
    FMute.Checked := FSong.Tracks[FTrack].Mute;
  finally
    FUpdating := False;
  end;
end;

procedure TMusicForm.UpdateCaption;
var
  N: string;
begin
  if FFile = '' then N := 'untitled' else N := ExtractFileName(FFile);
  Caption := 'Paper Crane Music Editor - ' + N + IfThen(FDirty, ' *', '') + Format('   (%s, %d bars, %.1f s)',
    [FSong.Name, FSong.Bars, FSong.TotalSteps * FSong.StepSeconds]);
end;

procedure TMusicForm.PushUndo;
var
  U: TSong;
begin
  U := TSong.Create;
  U.Assign(FSong);
  FUndo.Add(U);
  while FUndo.Count > 60 do
  begin
    TSong(FUndo[0]).Free;
    FUndo.Delete(0);
  end;
end;

procedure TMusicForm.Changed;
begin
  FDirty := True;
  UpdateCaption;
  TracksToList;
  FRoll.Invalidate;
end;

procedure TMusicForm.ResizeRoll;
begin
  FRoll.Width := 48 + FSong.TotalSteps * FStepW + 20;
  FRoll.Height := (HighPitch - LowPitch + 1) * FRowH + 22;
  FRoll.Invalidate;
end;

function TMusicForm.PitchAt(Y: Integer): Integer;
begin
  Result := HighPitch - (Y - 20) div FRowH;
end;

function TMusicForm.StepAt(X: Integer): Integer;
begin
  Result := (X - 48) div FStepW;
end;

function TMusicForm.NoteAt(X, Y: Integer): Integer;
var
  I, S, P: Integer;
begin
  Result := -1;
  if (FTrack < 0) or (FTrack > High(FSong.Tracks)) then Exit;
  S := StepAt(X);
  P := PitchAt(Y);
  with FSong.Tracks[FTrack] do
    for I := High(Notes) downto 0 do
      if (Notes[I].Pitch = P) and (S >= Notes[I].Step) and (S < Notes[I].Step + Notes[I].Len) then Exit(I);
end;

procedure TMusicForm.RollPaint(Sender: TObject);
const
  Black: array[0..11] of Boolean = (False, True, False, True, False, False, True, False, True, False, True, False);
var
  C: TCanvas;
  P, Y, X, S, T, I, Total: Integer;
  Col: TColor;
  R: TRect;
  Ph: Double;
begin
  C := FRoll.Canvas;
  Total := FSong.TotalSteps;
  // rows: scale notes light, others greyed, root darker
  for P := LowPitch to HighPitch do
  begin
    Y := 20 + (HighPitch - P) * FRowH;
    if ((P - FSong.Root) mod 12 + 12) mod 12 = 0 then Col := RGBToColor(232, 214, 190)
    else if FSong.InScale(P) then Col := RGBToColor(246, 238, 222)
    else Col := RGBToColor(222, 216, 208);
    C.Brush.Color := Col;
    C.FillRect(48, Y, FRoll.Width, Y + FRowH);
    if Black[P mod 12] then C.Brush.Color := RGBToColor(60, 52, 56) else C.Brush.Color := RGBToColor(250, 248, 244);
    C.FillRect(0, Y, 46, Y + FRowH - 1);
    if P mod 12 = 0 then
    begin
      C.Font.Size := 7;
      C.Font.Color := RGBToColor(150, 60, 40);
      C.Brush.Style := bsClear;
      C.TextOut(2, Y - 1, NoteName(P));
      C.Brush.Style := bsSolid;
    end;
  end;
  // beats and bars
  for S := 0 to Total do
  begin
    X := 48 + S * FStepW;
    if S mod (StepsPerBeat * 4) = 0 then C.Pen.Color := RGBToColor(160, 70, 50)
    else if S mod StepsPerBeat = 0 then C.Pen.Color := RGBToColor(200, 180, 160)
    else C.Pen.Color := RGBToColor(232, 222, 206);
    C.Line(X, 20, X, FRoll.Height);
    if S mod (StepsPerBeat * 4) = 0 then
    begin
      C.Font.Size := 8;
      C.Font.Color := RGBToColor(150, 60, 40);
      C.Brush.Style := bsClear;
      C.TextOut(X + 3, 3, IntToStr(S div 16 + 1));
      C.Brush.Style := bsSolid;
    end;
  end;
  // notes: other tracks faint, the selected track strong
  for T := 0 to High(FSong.Tracks) do
  begin
    if T = FTrack then Continue;
    for I := 0 to High(FSong.Tracks[T].Notes) do
      with FSong.Tracks[T].Notes[I] do
        if (Pitch >= LowPitch) and (Pitch <= HighPitch) then
        begin
          C.Brush.Color := RGBToColor(196, 196, 210);
          C.FillRect(48 + Step * FStepW + 1, 20 + (HighPitch - Pitch) * FRowH + 2,
            48 + (Step + Len) * FStepW - 1, 20 + (HighPitch - Pitch + 1) * FRowH - 2);
        end;
  end;
  if (FTrack >= 0) and (FTrack <= High(FSong.Tracks)) then
    for I := 0 to High(FSong.Tracks[FTrack].Notes) do
      with FSong.Tracks[FTrack].Notes[I] do
        if (Pitch >= LowPitch) and (Pitch <= HighPitch) then
        begin
          R := Rect(48 + Step * FStepW + 1, 20 + (HighPitch - Pitch) * FRowH + 1,
            48 + (Step + Len) * FStepW - 1, 20 + (HighPitch - Pitch + 1) * FRowH - 1);
          if I = FSelNote then C.Brush.Color := RGBToColor(40, 90, 170)
          else C.Brush.Color := RGBToColor(Round(120 + 100 * Vel), 40, 34);
          C.FillRect(R);
          C.Brush.Color := RGBToColor(250, 230, 200);
          C.FillRect(R.Right - 3, R.Top + 2, R.Right - 1, R.Bottom - 2);  // the resize grip
        end;
  // the playhead
  if FPlaying and (FPlayLen > 0) then
  begin
    Ph := (GetTickCount64 - FPlayT0) / 1000;
    if FLoop.Checked then Ph := Ph - Floor(Ph / FPlayLen) * FPlayLen;
    X := 48 + Round(Ph / FSong.StepSeconds * FStepW);
    C.Pen.Color := clBlue;
    C.Pen.Width := 2;
    C.Line(X, 0, X, FRoll.Height);
    C.Pen.Width := 1;
  end;
end;

procedure TMusicForm.RollDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I, S, P: Integer;
begin
  if (FTrack < 0) or (FTrack > High(FSong.Tracks)) or (Y < 20) or (X < 48) then Exit;
  S := StepAt(X);
  P := PitchAt(Y);
  if (S < 0) or (S >= FSong.TotalSteps) or (P < LowPitch) or (P > HighPitch) then Exit;
  I := NoteAt(X, Y);
  if Button = mbRight then
  begin
    if I >= 0 then
    begin
      PushUndo;
      with FSong.Tracks[FTrack] do
      begin
        Notes[I] := Notes[High(Notes)];
        SetLength(Notes, Length(Notes) - 1);
      end;
      FSelNote := -1;
      Changed;
    end;
    Exit;
  end;
  PushUndo;
  if I < 0 then
  begin
    FSong.AddNote(FTrack, S, FNoteLen.Value, P, FVel.Value / 100);
    I := High(FSong.Tracks[FTrack].Notes);
    // hear the note
    with TSong.Create do
    try
      Bpm := FSong.Bpm;
      Bars := 1;
      Echo := 0;
      AddTrack('x', FSong.Tracks[FTrack].Instr, 1, 0);
      AddNote(0, 0, FNoteLen.Value, P, 0.6);
      PlayPcm(Render(22050), 2, 22050, False);
    finally
      Free;
    end;
  end;
  FSelNote := I;
  with FSong.Tracks[FTrack].Notes[I] do
  begin
    FDragStep := S;
    FDragPitch := P;
    FDragNoteStep := Step;
    FDragNotePitch := Pitch;
    FDragLen := Len;
    if X >= 48 + (Step + Len) * FStepW - 5 then FDrag := 2 else FDrag := 1;
  end;
  Changed;
  FStatus.SimpleText := Format('note %s, step %d, length %d', [NoteName(P), S, FSong.Tracks[FTrack].Notes[I].Len]);
end;

procedure TMusicForm.RollMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  S, P: Integer;
begin
  if FDrag = 0 then
  begin
    if X > 48 then
      FStatus.SimpleText := Format('%s   bar %d beat %d step %d', [NoteName(PitchAt(Y)), StepAt(X) div 16 + 1,
        (StepAt(X) mod 16) div 4 + 1, StepAt(X) mod 4 + 1]);
    Exit;
  end;
  if (FSelNote < 0) or (FTrack > High(FSong.Tracks)) or (FSelNote > High(FSong.Tracks[FTrack].Notes)) then Exit;
  S := StepAt(X);
  P := PitchAt(Y);
  with FSong.Tracks[FTrack].Notes[FSelNote] do
    if FDrag = 2 then
      Len := EnsureRange(FDragLen + S - FDragStep, 1, FSong.TotalSteps)
    else
    begin
      Step := EnsureRange(FDragNoteStep + S - FDragStep, 0, FSong.TotalSteps - 1);
      Pitch := EnsureRange(FDragNotePitch + P - FDragPitch, LowPitch, HighPitch);
    end;
  FDirty := True;
  FRoll.Invalidate;
end;

procedure TMusicForm.RollUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if FDrag <> 0 then
  begin
    FDrag := 0;
    Changed;
  end;
end;

procedure TMusicForm.SongEdit(Sender: TObject);
begin
  if FUpdating then Exit;
  PushUndo;
  FSong.Name := FName.Text;
  FSong.Bpm := FBpm.Value;
  FSong.Bars := FBars.Value;
  FSong.Root := FRoot.Value;
  FSong.Scale := Max(0, FScale.ItemIndex);
  FSong.Echo := FEcho.Position / 100;
  ResizeRoll;
  Changed;
end;

procedure TMusicForm.TrackEdit(Sender: TObject);
begin
  if FUpdating or (FTrack < 0) or (FTrack > High(FSong.Tracks)) then Exit;
  PushUndo;
  FSong.Tracks[FTrack].Instr := TInstrument(Max(0, FInstr.ItemIndex));
  FSong.Tracks[FTrack].Vol := FVol.Position / 100;
  FSong.Tracks[FTrack].Pan := FPan.Position / 100;
  FSong.Tracks[FTrack].Mute := FMute.Checked;
  Changed;
end;

procedure TMusicForm.TrackSelect(Sender: TObject);
begin
  FTrack := FTracks.ItemIndex;
  FSelNote := -1;
  TrackToControls;
  FRoll.Invalidate;
end;

procedure TMusicForm.AddTrackClick(Sender: TObject);
begin
  PushUndo;
  FTrack := FSong.AddTrack('Track ' + IntToStr(Length(FSong.Tracks) + 1), inGuzheng, 1, 0);
  TracksToList;
  FTracks.ItemIndex := FTrack;
  TrackSelect(nil);
  Changed;
end;

procedure TMusicForm.DelTrackClick(Sender: TObject);
var
  I: Integer;
begin
  if (FTrack < 0) or (FTrack > High(FSong.Tracks)) then Exit;
  PushUndo;
  for I := FTrack to High(FSong.Tracks) - 1 do FSong.Tracks[I] := FSong.Tracks[I + 1];
  SetLength(FSong.Tracks, Length(FSong.Tracks) - 1);
  TracksToList;
  FTracks.ItemIndex := Min(FTrack, FTracks.Count - 1);
  TrackSelect(nil);
  Changed;
end;

procedure TMusicForm.ClearTrackClick(Sender: TObject);
begin
  if (FTrack < 0) or (FTrack > High(FSong.Tracks)) then Exit;
  PushUndo;
  SetLength(FSong.Tracks[FTrack].Notes, 0);
  Changed;
end;

procedure TMusicForm.PlayClick(Sender: TObject);
var
  D: TTrackData;
begin
  Screen.Cursor := crHourGlass;
  try
    D := FSong.Render(22050);
  finally
    Screen.Cursor := crDefault;
  end;
  PlayPcm(D, 2, 22050, FLoop.Checked);
  FPlayLen := Length(D) / 2 / 22050;
  FPlayT0 := GetTickCount64;
  FPlaying := True;
  FTimer.Enabled := True;
  FStatus.SimpleText := Format('playing %s (%.1f s)', [FSong.Name, FPlayLen]);
end;

procedure TMusicForm.StopClick(Sender: TObject);
begin
  StopPcm;
  FPlaying := False;
  FTimer.Enabled := False;
  FRoll.Invalidate;
end;

procedure TMusicForm.TimerTick(Sender: TObject);
begin
  if FPlaying and not FLoop.Checked and ((GetTickCount64 - FPlayT0) / 1000 > FPlayLen) then StopClick(nil);
  FRoll.Invalidate;
end;

procedure TMusicForm.NewClick(Sender: TObject);
begin
  PushUndo;
  FSong.Free;
  FSong := TSong.Create;
  FSong.AddTrack('Melody', inDizi, 1, -0.15);
  FSong.AddTrack('Guzheng', inGuzheng, 1, 0.15);
  FSong.AddTrack('Bass', inBass, 1, 0.15);
  FSong.AddTrack('Drums', inTanggu, 1, 0);
  FFile := '';
  FDirty := False;
  SongToControls;
  TracksToList;
  FTracks.ItemIndex := 0;
  TrackSelect(nil);
  ResizeRoll;
end;

procedure TMusicForm.OpenFile(const AFile: string);
begin
  PushUndo;
  FSong.LoadFromFile(AFile);
  FFile := AFile;
  FDirty := False;
  SongToControls;
  TracksToList;
  FTracks.ItemIndex := 0;
  TrackSelect(nil);
  ResizeRoll;
  FStatus.SimpleText := 'opened ' + AFile;
end;

procedure TMusicForm.OpenClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Paper Crane music (*.pcmusic)|*.pcmusic|All files|*.*';
    if DirectoryExists(GameDir + 'music') then D.InitialDir := GameDir + 'music';
    if D.Execute then OpenFile(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TMusicForm.SaveClick(Sender: TObject);
begin
  if FFile = '' then
  begin
    SaveAsClick(Sender);
    Exit;
  end;
  FSong.SaveToFile(FFile);
  FDirty := False;
  UpdateCaption;
  FStatus.SimpleText := 'saved ' + FFile;
end;

procedure TMusicForm.SaveAsClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'Paper Crane music (*.pcmusic)|*.pcmusic';
    D.DefaultExt := 'pcmusic';
    ForceDirectories(GameDir + 'music');
    D.InitialDir := GameDir + 'music';
    D.FileName := StringReplace(FSong.Name, ' ', '_', [rfReplaceAll]) + '.pcmusic';
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

procedure TMusicForm.WavClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'WAV (*.wav)|*.wav';
    D.DefaultExt := 'wav';
    D.FileName := StringReplace(FSong.Name, ' ', '_', [rfReplaceAll]) + '.wav';
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
    begin
      SaveWav(D.FileName, FSong.Render(44100), 2, 44100);
      FStatus.SimpleText := 'exported ' + D.FileName;
    end;
  finally
    D.Free;
  end;
end;

procedure TMusicForm.ImportClick(Sender: TObject);
var
  S: TSong;
begin
  PushUndo;
  S := BuiltinSong(FImport.ItemIndex);
  FSong.Free;
  FSong := S;
  FFile := '';
  FDirty := True;
  SongToControls;
  TracksToList;
  FTracks.ItemIndex := 0;
  TrackSelect(nil);
  ResizeRoll;
  FStatus.SimpleText := 'imported the game tune ' + FSong.Name;
end;

procedure TMusicForm.UndoClick(Sender: TObject);
begin
  if FUndo.Count = 0 then Exit;
  FSong.Assign(TSong(FUndo[FUndo.Count - 1]));
  TSong(FUndo[FUndo.Count - 1]).Free;
  FUndo.Delete(FUndo.Count - 1);
  FSelNote := -1;
  SongToControls;
  TracksToList;
  TrackSelect(nil);
  ResizeRoll;
end;

procedure TMusicForm.ZoomIn(Sender: TObject);
begin
  FStepW := Min(40, FStepW + 3);
  FRowH := Min(24, FRowH + 2);
  ResizeRoll;
end;

procedure TMusicForm.ZoomOut(Sender: TObject);
begin
  FStepW := Max(5, FStepW - 3);
  FRowH := Max(7, FRowH - 2);
  ResizeRoll;
end;

procedure TMusicForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (ActiveControl is TEdit) or (ActiveControl is TSpinEdit) or (ActiveControl is TComboBox) then Exit;
  if Key = VK_SPACE then
  begin
    if FPlaying then StopClick(nil) else PlayClick(nil);
    Key := 0;
  end
  else if (Key = VK_Z) and (ssCtrl in Shift) then
  begin
    UndoClick(nil);
    Key := 0;
  end
  else if (Key = VK_S) and (ssCtrl in Shift) then
  begin
    SaveClick(nil);
    Key := 0;
  end
  else if (Key = VK_DELETE) and (FSelNote >= 0) and (FTrack >= 0) then
  begin
    PushUndo;
    with FSong.Tracks[FTrack] do
    begin
      Notes[FSelNote] := Notes[High(Notes)];
      SetLength(Notes, Length(Notes) - 1);
    end;
    FSelNote := -1;
    Changed;
    Key := 0;
  end;
end;

end.
