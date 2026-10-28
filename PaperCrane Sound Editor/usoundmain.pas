unit uSoundMain;

{ Paper Crane Sound Editor: design sound effects without any sound file and
  without SDL. A sound is a set of synth parameters (uSynth.TSfxParams, saved as
  .pcsfx): wave, pitch slide, envelope with punch, vibrato, pitch jump, noise,
  filters, repeats, echo. Every change renders the sound at 44.1 kHz and shows
  its waveform; Play uses Windows PlaySound from memory.

  Presets: the game's own 13 effects and classic game sounds; Random makes a
  new sound, Mutate changes the current one a little. Files: .pcsfx, WAV
  export, and "Install into game": saves the sound as one of the game's effects
  (sounds/<name>.pcsfx next to PaperCrane.exe), which the game then uses. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Spin, Dialogs,
  Menus, LCLType, BGRABitmap, BGRABitmapTypes, uSynth;

type
  TParamDef = record
    Caption: string;
    Lo, Hi: Single;
    LogScale: Boolean;
    Fmt: string;
  end;

  { TSoundForm }

  TSoundForm = class(TForm)
  private
    FP: TSfxParams;
    FData: TBufF;
    FFile: string;
    FDirty, FUpdating: Boolean;
    FPresets: TListBox;
    FWave: TComboBox;
    FRepeats: TSpinEdit;
    FBars: array of TTrackBar;
    FVals: array of TLabel;
    FView: TPaintBox;
    FInfo: TLabel;
    FAutoPlay, FLoop: TCheckBox;
    FGameSlot: TComboBox;
    FStatus: TStatusBar;
    procedure BuildUI;
    function AddButton(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TButton;
    function GetParam(I: Integer): Single;
    procedure SetParam(I: Integer; V: Single);
    procedure ParamsToControls;
    procedure Rendered;
    procedure BarChange(Sender: TObject);
    procedure WaveChange(Sender: TObject);
    procedure PresetClick(Sender: TObject);
    procedure ViewPaint(Sender: TObject);
    procedure PlayClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure RandomClick(Sender: TObject);
    procedure MutateClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure WavClick(Sender: TObject);
    procedure InstallClick(Sender: TObject);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    function GameDir: string;
    procedure UpdateCaption;
  public
    constructor Create(AOwner: TComponent); override;
    procedure OpenFile(const AFile: string);
  end;

var
  SoundForm: TSoundForm;

implementation

var
  GSeq: Integer = 0;

{ a growing position, so alLeft controls line up in creation order }
function NextSeq: Integer;
begin
  Inc(GSeq, 4);
  Result := GSeq;
end;

const
  ParamCount_ = 19;
  Defs: array[0..ParamCount_ - 1] of TParamDef = (
    (Caption: 'Start pitch (Hz)'; Lo: 20; Hi: 8000; LogScale: True; Fmt: '0'),
    (Caption: 'End pitch (Hz)'; Lo: 20; Hi: 8000; LogScale: True; Fmt: '0'),
    (Caption: 'Slide curve'; Lo: 0.1; Hi: 5; LogScale: True; Fmt: '0.00'),
    (Caption: 'Attack (s)'; Lo: 0; Hi: 2; LogScale: False; Fmt: '0.000'),
    (Caption: 'Sustain (s)'; Lo: 0; Hi: 3; LogScale: False; Fmt: '0.000'),
    (Caption: 'Release (s)'; Lo: 0.005; Hi: 4; LogScale: False; Fmt: '0.000'),
    (Caption: 'Punch'; Lo: 0; Hi: 1; LogScale: False; Fmt: '0.00'),
    (Caption: 'Vibrato depth (semitones)'; Lo: 0; Hi: 12; LogScale: False; Fmt: '0.00'),
    (Caption: 'Vibrato rate (Hz)'; Lo: 0.5; Hi: 30; LogScale: False; Fmt: '0.0'),
    (Caption: 'Square duty'; Lo: 0.05; Hi: 0.95; LogScale: False; Fmt: '0.00'),
    (Caption: 'Noise mix'; Lo: 0; Hi: 1; LogScale: False; Fmt: '0.00'),
    (Caption: 'Low pass (1 = open)'; Lo: 0.02; Hi: 1; LogScale: False; Fmt: '0.00'),
    (Caption: 'High pass'; Lo: 0; Hi: 1; LogScale: False; Fmt: '0.00'),
    (Caption: 'Pitch jump x'; Lo: 0.25; Hi: 4; LogScale: True; Fmt: '0.00'),
    (Caption: 'Pitch jump at (0 = off)'; Lo: 0; Hi: 1; LogScale: False; Fmt: '0.00'),
    (Caption: 'Repeat gap (s)'; Lo: -1; Hi: 1; LogScale: False; Fmt: '0.00'),
    (Caption: 'Echo'; Lo: 0; Hi: 0.8; LogScale: False; Fmt: '0.00'),
    (Caption: 'Echo delay (s)'; Lo: 0.02; Hi: 0.6; LogScale: False; Fmt: '0.000'),
    (Caption: 'Volume'; Lo: 0; Hi: 1; LogScale: False; Fmt: '0.00'));

  GameSfx: array[0..12] of string = ('flap', 'pass', 'lantern', 'hit', 'fall', 'splash', 'game over',
    'new best', 'menu move', 'menu select', 'menu back', 'thunder', 'start gong');

constructor TSoundForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'Paper Crane Sound Editor';
  Width := Scale96ToForm(1180);
  Height := Scale96ToForm(760);
  Position := poScreenCenter;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  BuildUI;
  FP := SfxPreset('lantern');
  ParamsToControls;
  Rendered;
end;

function TSoundForm.GameDir: string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'Paper Crane Papercut Game SDL3') + PathDelim;
end;

function TSoundForm.AddButton(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TButton;
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

procedure TSoundForm.BuildUI;
var
  Bar, LeftP, Params, Row, Right: TPanel;
  L: TLabel;
  I: Integer;
  W: TWave;
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
  AddButton(Bar, 'Export WAV...', @WavClick);
  AddButton(Bar, '  Play (Space)  ', @PlayClick);
  AddButton(Bar, 'Stop', @StopClick);
  FAutoPlay := TCheckBox.Create(Self);
  FAutoPlay.Parent := Bar;
  FAutoPlay.Caption := 'Play on change';
  FAutoPlay.Checked := True;
  FAutoPlay.Align := alLeft;
  FAutoPlay.Left := NextSeq;
  FAutoPlay.BorderSpacing.Left := 10;
  FLoop := TCheckBox.Create(Self);
  FLoop.Parent := Bar;
  FLoop.Caption := 'Loop';
  FLoop.Align := alLeft;
  FLoop.Left := NextSeq;
  FLoop.BorderSpacing.Left := 10;
  AddButton(Bar, 'Install into game as:', @InstallClick).Left := NextSeq;
  FGameSlot := TComboBox.Create(Self);
  FGameSlot.Parent := Bar;
  FGameSlot.Style := csDropDownList;
  for I := 0 to High(GameSfx) do FGameSlot.Items.Add(GameSfx[I]);
  FGameSlot.ItemIndex := 2;
  FGameSlot.Align := alLeft;
  FGameSlot.Left := NextSeq;
  FGameSlot.Width := Scale96ToForm(130);
  FGameSlot.BorderSpacing.Around := 5;

  // presets
  LeftP := TPanel.Create(Self);
  LeftP.Parent := Self;
  LeftP.Align := alLeft;
  LeftP.Width := Scale96ToForm(180);
  LeftP.BevelOuter := bvNone;
  L := TLabel.Create(Self);
  L.Parent := LeftP;
  L.Align := alTop;
  L.Caption := ' Presets (game sounds first)';
  L.BorderSpacing.Around := 4;
  Row := TPanel.Create(Self);
  Row.Parent := LeftP;
  Row.Align := alBottom;
  Row.Height := Scale96ToForm(36);
  Row.BevelOuter := bvNone;
  AddButton(Row, 'Random', @RandomClick);
  AddButton(Row, 'Mutate', @MutateClick);
  FPresets := TListBox.Create(Self);
  FPresets.Parent := LeftP;
  FPresets.Align := alClient;
  for I := 0 to High(SfxPresetNames) do FPresets.Items.Add(SfxPresetNames[I]);
  FPresets.OnClick := @PresetClick;

  // parameters
  Params := TPanel.Create(Self);
  Params.Parent := Self;
  Params.Align := alLeft;
  Params.Width := Scale96ToForm(470);
  Params.BevelOuter := bvNone;
  Row := TPanel.Create(Self);
  Row.Parent := Params;
  Row.Align := alTop;
  Row.Height := Scale96ToForm(30);
  Row.BevelOuter := bvNone;
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Caption := 'Wave';
  L.Align := alLeft;
  L.Layout := tlCenter;
  L.Width := Scale96ToForm(170);
  L.AutoSize := False;
  L.BorderSpacing.Left := 6;
  FWave := TComboBox.Create(Self);
  FWave.Parent := Row;
  FWave.Style := csDropDownList;
  for W := Low(TWave) to High(TWave) do FWave.Items.Add(WaveNames[W]);
  FWave.Align := alLeft;
  FWave.Left := NextSeq;
  FWave.Width := Scale96ToForm(170);
  FWave.OnChange := @WaveChange;
  L := TLabel.Create(Self);
  L.Parent := Row;
  L.Caption := '  repeats';
  L.Align := alLeft;
  L.Left := 1001;
  L.Layout := tlCenter;
  FRepeats := TSpinEdit.Create(Self);
  FRepeats.Parent := Row;
  FRepeats.MinValue := 0;
  FRepeats.MaxValue := 8;
  FRepeats.Align := alLeft;
  FRepeats.Left := 1002;
  FRepeats.Width := Scale96ToForm(50);
  FRepeats.OnChange := @BarChange;
  SetLength(FBars, ParamCount_);
  SetLength(FVals, ParamCount_);
  for I := 0 to ParamCount_ - 1 do
  begin
    Row := TPanel.Create(Self);
    Row.Parent := Params;
    Row.Align := alTop;
    Row.Top := 10000 + I;
    Row.Height := Scale96ToForm(32);
    Row.BevelOuter := bvNone;
    L := TLabel.Create(Self);
    L.Parent := Row;
    L.Caption := Defs[I].Caption;
    L.Align := alLeft;
    L.AutoSize := False;
    L.Width := Scale96ToForm(170);
    L.Layout := tlCenter;
    L.BorderSpacing.Left := 6;
    FVals[I] := TLabel.Create(Self);
    FVals[I].Parent := Row;
    FVals[I].Align := alRight;
    FVals[I].AutoSize := False;
    FVals[I].Width := Scale96ToForm(64);
    FVals[I].Layout := tlCenter;
    FBars[I] := TTrackBar.Create(Self);
    FBars[I].Parent := Row;
    FBars[I].Align := alClient;
    FBars[I].Min := 0;
    FBars[I].Max := 1000;
    FBars[I].TickStyle := tsNone;
    FBars[I].Tag := I;
    FBars[I].OnChange := @BarChange;
  end;

  // the waveform
  Right := TPanel.Create(Self);
  Right.Parent := Self;
  Right.Align := alClient;
  Right.BevelOuter := bvNone;
  FInfo := TLabel.Create(Self);
  FInfo.Parent := Right;
  FInfo.Align := alTop;
  FInfo.BorderSpacing.Around := 6;
  FView := TPaintBox.Create(Self);
  FView.Parent := Right;
  FView.Align := alClient;
  FView.OnPaint := @ViewPaint;
end;

{ parameter I of FP }
function TSoundForm.GetParam(I: Integer): Single;
begin
  case I of
    0: Result := FP.Freq;
    1: Result := FP.FreqEnd;
    2: Result := FP.Curve;
    3: Result := FP.Attack;
    4: Result := FP.Sustain;
    5: Result := FP.Release;
    6: Result := FP.Punch;
    7: Result := FP.VibDepth;
    8: Result := FP.VibRate;
    9: Result := FP.Duty;
    10: Result := FP.Noise;
    11: Result := FP.LowPass;
    12: Result := FP.HighPass;
    13: Result := FP.ArpMul;
    14: Result := FP.ArpTime;
    15: Result := FP.RepeatGap;
    16: Result := FP.Echo;
    17: Result := FP.EchoDelay;
  else
    Result := FP.Volume;
  end;
end;

procedure TSoundForm.SetParam(I: Integer; V: Single);
begin
  case I of
    0: FP.Freq := V;
    1: FP.FreqEnd := V;
    2: FP.Curve := V;
    3: FP.Attack := V;
    4: FP.Sustain := V;
    5: FP.Release := V;
    6: FP.Punch := V;
    7: FP.VibDepth := V;
    8: FP.VibRate := V;
    9: FP.Duty := V;
    10: FP.Noise := V;
    11: FP.LowPass := V;
    12: FP.HighPass := V;
    13: FP.ArpMul := V;
    14: FP.ArpTime := V;
    15: FP.RepeatGap := V;
    16: FP.Echo := V;
    17: FP.EchoDelay := V;
  else
    FP.Volume := V;
  end;
end;

function BarToValue(const D: TParamDef; Pos: Integer): Single;
var
  T: Single;
begin
  T := Pos / 1000;
  if D.LogScale then Result := D.Lo * Power(D.Hi / D.Lo, T)
  else Result := D.Lo + (D.Hi - D.Lo) * T;
end;

function ValueToBar(const D: TParamDef; V: Single): Integer;
begin
  V := EnsureRange(V, D.Lo, D.Hi);
  if D.LogScale then Result := Round(Ln(V / D.Lo) / Ln(D.Hi / D.Lo) * 1000)
  else Result := Round((V - D.Lo) / (D.Hi - D.Lo) * 1000);
end;

procedure TSoundForm.ParamsToControls;
var
  I: Integer;
begin
  FUpdating := True;
  try
    FWave.ItemIndex := Ord(FP.Wave);
    FRepeats.Value := FP.Repeats;
    for I := 0 to ParamCount_ - 1 do
    begin
      FBars[I].Position := ValueToBar(Defs[I], GetParam(I));
      FVals[I].Caption := FormatFloat(Defs[I].Fmt, GetParam(I));
    end;
  finally
    FUpdating := False;
  end;
end;

{ render the sound, show it, play it if wanted }
procedure TSoundForm.Rendered;
var
  I: Integer;
  Peak: Single;
begin
  FData := RenderSfx(FP, 44100);
  Peak := 0;
  for I := 0 to High(FData) do Peak := Max(Peak, Abs(FData[I]));
  FInfo.Caption := Format('%s   -   %s, %.2f s, %d samples at 44.1 kHz, peak %.2f',
    [FP.Name, WaveNames[FP.Wave], Length(FData) / 44100, Length(FData), Peak]);
  FView.Invalidate;
  UpdateCaption;
end;

procedure TSoundForm.UpdateCaption;
var
  N: string;
begin
  if FFile = '' then N := 'untitled' else N := ExtractFileName(FFile);
  Caption := 'Paper Crane Sound Editor - ' + N + IfThen(FDirty, ' *', '');
end;

procedure TSoundForm.BarChange(Sender: TObject);
var
  I: Integer;
begin
  if FUpdating then Exit;
  if Sender = FRepeats then FP.Repeats := FRepeats.Value
  else
  begin
    I := TTrackBar(Sender).Tag;
    SetParam(I, BarToValue(Defs[I], TTrackBar(Sender).Position));
    FVals[I].Caption := FormatFloat(Defs[I].Fmt, GetParam(I));
  end;
  FDirty := True;
  Rendered;
  if FAutoPlay.Checked then PlayClick(nil);
end;

procedure TSoundForm.WaveChange(Sender: TObject);
begin
  if FUpdating then Exit;
  FP.Wave := TWave(FWave.ItemIndex);
  FDirty := True;
  Rendered;
  if FAutoPlay.Checked then PlayClick(nil);
end;

procedure TSoundForm.PresetClick(Sender: TObject);
begin
  if FPresets.ItemIndex < 0 then Exit;
  FP := SfxPreset(FPresets.Items[FPresets.ItemIndex]);
  ParamsToControls;
  FDirty := True;
  Rendered;
  PlayClick(nil);
  if FPresets.ItemIndex <= High(GameSfx) then FGameSlot.ItemIndex := FPresets.ItemIndex;
end;

procedure TSoundForm.ViewPaint(Sender: TObject);
var
  B: TBGRABitmap;
  W, H, X, I0, I1, I: Integer;
  Lo, Hi, Env, MidY: Single;
  T: Single;
begin
  W := FView.Width;
  H := FView.Height;
  if (W < 4) or (H < 4) then Exit;
  B := TBGRABitmap.Create(W, H, BGRA(246, 238, 222));
  try
    MidY := H / 2;
    B.DrawLineAntialias(0, MidY, W, MidY, BGRA(200, 180, 160), 1);
    // time grid every 0.1 s
    if Length(FData) > 0 then
    begin
      T := 0;
      while T < Length(FData) / 44100 do
      begin
        X := Round(T * 44100 / Length(FData) * W);
        B.DrawLineAntialias(X, 0, X, H, BGRA(220, 205, 185), 1);
        B.FontHeight := 12;
        if (Round(T * 10) mod Max(1, Ceil(45 / Max(1, 0.1 * 44100 / Length(FData) * W)))) = 0 then
          B.TextOut(X + 3, 3, FormatFloat('0.0', T) + ' s', BGRA(150, 120, 100));
        T := T + 0.1;
      end;
      // min / max per pixel column
      for X := 0 to W - 1 do
      begin
        I0 := Int64(X) * Length(FData) div W;
        I1 := Max(I0 + 1, Int64(X + 1) * Length(FData) div W);
        Lo := 0;
        Hi := 0;
        for I := I0 to Min(High(FData), I1 - 1) do
        begin
          Lo := Min(Lo, FData[I]);
          Hi := Max(Hi, FData[I]);
        end;
        B.DrawLine(X, Round(MidY - Hi * MidY * 0.95), X, Round(MidY - Lo * MidY * 0.95), BGRA(178, 40, 34), True);
      end;
      // the envelope of the first sound
      for X := 0 to W - 1 do
      begin
        T := X / W * Length(FData) / 44100;
        if T < FP.Attack then Env := T / Max(0.0001, FP.Attack)
        else if T < FP.Attack + FP.Sustain then Env := 1
        else Env := Max(0, 1 - (T - FP.Attack - FP.Sustain) / Max(0.0001, FP.Release));
        B.SetPixel(X, Round(MidY - Env * MidY * 0.95), BGRA(40, 90, 160));
      end;
    end;
    B.Draw(FView.Canvas, 0, 0, True);
  finally
    B.Free;
  end;
end;

procedure TSoundForm.PlayClick(Sender: TObject);
begin
  if Length(FData) = 0 then Exit;
  PlayPcm(FloatToPcm(FData), 1, 44100, FLoop.Checked);
  FStatus.SimpleText := 'playing ' + FP.Name;
end;

procedure TSoundForm.StopClick(Sender: TObject);
begin
  StopPcm;
  FStatus.SimpleText := 'stopped';
end;

procedure TSoundForm.RandomClick(Sender: TObject);
begin
  FP := RandomSfx;
  ParamsToControls;
  FDirty := True;
  Rendered;
  PlayClick(nil);
end;

procedure TSoundForm.MutateClick(Sender: TObject);
begin
  MutateSfx(FP, 0.15);
  ParamsToControls;
  FDirty := True;
  Rendered;
  PlayClick(nil);
end;

procedure TSoundForm.NewClick(Sender: TObject);
begin
  FP := DefaultSfx;
  FFile := '';
  FDirty := False;
  ParamsToControls;
  Rendered;
end;

procedure TSoundForm.OpenFile(const AFile: string);
begin
  FP := LoadSfx(AFile);
  FFile := AFile;
  FDirty := False;
  ParamsToControls;
  Rendered;
  FStatus.SimpleText := 'opened ' + AFile;
end;

procedure TSoundForm.OpenClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Paper Crane sound (*.pcsfx)|*.pcsfx|All files|*.*';
    if DirectoryExists(GameDir + 'sounds') then D.InitialDir := GameDir + 'sounds';
    if D.Execute then OpenFile(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TSoundForm.SaveClick(Sender: TObject);
begin
  if FFile = '' then
  begin
    SaveAsClick(Sender);
    Exit;
  end;
  SaveSfx(FP, FFile);
  FDirty := False;
  UpdateCaption;
  FStatus.SimpleText := 'saved ' + FFile;
end;

procedure TSoundForm.SaveAsClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'Paper Crane sound (*.pcsfx)|*.pcsfx';
    D.DefaultExt := 'pcsfx';
    D.FileName := StringReplace(FP.Name, ' ', '_', [rfReplaceAll]) + '.pcsfx';
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
    begin
      FFile := D.FileName;
      FP.Name := ChangeFileExt(ExtractFileName(FFile), '');
      SaveClick(Sender);
    end;
  finally
    D.Free;
  end;
end;

procedure TSoundForm.WavClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'WAV (*.wav)|*.wav';
    D.DefaultExt := 'wav';
    D.FileName := StringReplace(FP.Name, ' ', '_', [rfReplaceAll]) + '.wav';
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
    begin
      SaveWav(D.FileName, FloatToPcm(FData), 1, 44100);
      FStatus.SimpleText := 'exported ' + D.FileName;
    end;
  finally
    D.Free;
  end;
end;

{ the game picks up sounds/<name>.pcsfx in place of its built-in effect }
procedure TSoundForm.InstallClick(Sender: TObject);
var
  Dir, F: string;
begin
  Dir := GameDir + 'sounds' + PathDelim;
  ForceDirectories(Dir);
  F := Dir + StringReplace(FGameSlot.Text, ' ', '_', [rfReplaceAll]) + '.pcsfx';
  SaveSfx(FP, F);
  FStatus.SimpleText := 'installed: ' + F + '  (restart the game; delete the file to get the built-in sound back)';
end;

procedure TSoundForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_SPACE) and not (ActiveControl is TComboBox) and not (ActiveControl is TSpinEdit) then
  begin
    PlayClick(nil);
    Key := 0;
  end
  else if (Key = VK_S) and (ssCtrl in Shift) then
  begin
    SaveClick(nil);
    Key := 0;
  end;
end;

end.
