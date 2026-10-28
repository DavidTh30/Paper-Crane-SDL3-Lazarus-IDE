unit uSynth;

{ Paper Crane shared synthesiser (game, Sound Editor, Music Editor).

  Instruments: guzheng / pipa / zither (Karplus-Strong strings), dizi (flute),
  erhu (bowed), bells, pad, tanggu (tom), woodblock, cymbal, gong.

  Songs (TSong, .pcmusic files): tracks of notes (step, length in 16th steps,
  midi pitch, velocity) on an instrument with volume and pan; tempo, root,
  scale (gong / yu pentatonic or chromatic), bars, echo. Render gives a seamless
  stereo loop. The 7 built-in tunes of the game are songs too (BuiltinSong), so
  the Music Editor can open and change them.

  Sound effects (TSfxParams, .pcsfx files): an sfxr-like synth - wave, pitch
  slide, envelope with punch, vibrato, arpeggio jump, noise, filters, repeats,
  echo. Presets for the game's effects and for classic game sounds.

  WAV writing and playback without SDL (Windows PlaySound from memory). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math{$IFDEF WINDOWS}, MMSystem{$ENDIF};

const
  StepsPerBeat = 4;
  BuiltinCount = 7;
  BuiltinNames: array[0..BuiltinCount - 1] of string = ('Li River Morning', 'Paper Wings',
    'Lantern Festival', 'Moonlit Pagoda', 'Rain on Bamboo', 'Autumn Wind', 'Snow over Karst');
  ScaleIds: array[0..2] of string = ('gong', 'yu', 'chromatic');
  ScaleNames: array[0..2] of string = ('Gong (do re mi sol la)', 'Yu (la do re mi sol)', 'Chromatic');

type
  TBufF = array of Single;
  TTrackData = array of SmallInt;   // interleaved stereo (or mono) 16-bit

  TInstrument = (inGuzheng, inBass, inPipa, inSoftZither, inDizi, inErhu, inBells, inPad, inTanggu,
    inWoodblock, inCymbal, inGong);

const
  InstrumentIds: array[TInstrument] of string = ('guzheng', 'bass', 'pipa', 'zither', 'dizi', 'erhu',
    'bells', 'pad', 'tanggu', 'woodblock', 'cymbal', 'gong');
  InstrumentNames: array[TInstrument] of string = ('Guzheng', 'Guzheng bass', 'Pipa', 'Soft zither',
    'Dizi (flute)', 'Erhu', 'Bells', 'Pad', 'Tanggu (drum)', 'Woodblock', 'Cymbal', 'Gong');

type
  TNote = record
    Step, Len, Pitch: Integer;
    Vel: Single;
  end;

  TSongTrack = record
    Name: string;
    Instr: TInstrument;
    Vol, Pan: Single;
    Mute: Boolean;
    Notes: array of TNote;
  end;

  { TSong }

  TSong = class
  public
    Name: string;
    Bpm: Single;
    Root, Scale, Bars: Integer;
    Echo: Single;
    Tracks: array of TSongTrack;
    constructor Create;
    function StepSeconds: Single;
    function TotalSteps: Integer;
    function AddTrack(const AName: string; AInstr: TInstrument; AVol, APan: Single): Integer;
    procedure AddNote(T, AStep, ALen, APitch: Integer; AVel: Single);
    procedure Assign(Src: TSong);
    function InScale(Pitch: Integer): Boolean;
    procedure SaveToFile(const FileName: string);
    procedure LoadFromFile(const FileName: string);
    function Render(R: Integer; Normalize: Boolean = True): TTrackData;
  end;

  TWave = (wvSine, wvSquare, wvSaw, wvTriangle, wvNoise, wvPluck, wvBell, wvBreath);

const
  WaveIds: array[TWave] of string = ('sine', 'square', 'saw', 'triangle', 'noise', 'pluck', 'bell', 'breath');
  WaveNames: array[TWave] of string = ('Sine', 'Square', 'Saw', 'Triangle', 'Noise', 'Pluck (string)',
    'Bell', 'Breath (filtered noise)');
  SfxPresetNames: array[0..18] of string = ('flap', 'pass', 'lantern', 'hit', 'fall', 'splash', 'game over',
    'new best', 'menu move', 'menu select', 'menu back', 'thunder', 'start gong', 'coin', 'jump', 'laser',
    'explosion', 'power up', 'blip');

type
  TSfxParams = record
    Name: string;
    Wave: TWave;
    Freq, FreqEnd, Curve: Single;        // pitch slide (Curve: exponent of the slide)
    Attack, Sustain, Release, Punch: Single;
    VibDepth, VibRate: Single;           // semitones, Hz
    Duty, Noise: Single;
    LowPass, HighPass: Single;           // 0..1 (low pass 1 = open)
    ArpMul, ArpTime: Single;             // pitch jump factor at a fraction of the sound
    Repeats: Integer;
    RepeatGap: Single;
    Echo, EchoDelay, Volume: Single;
  end;

function NoteHz(Midi: Single): Single;
function NoteName(Midi: Integer): string;
function InstrumentByName(const S: string): TInstrument;
function BuiltinSong(Index: Integer): TSong;
{ the instruments, into a mono buffer at rate R }
procedure AddPluck(var Dest: TBufF; Start: Integer; Hz, Dur, Vol, Decay, Bright: Single; R: Integer);
procedure AddFlute(var Dest: TBufF; Start: Integer; Hz, Dur, Vol: Single; R: Integer);
procedure AddErhu(var Dest: TBufF; Start: Integer; Hz, Dur, Vol: Single; R: Integer);
procedure AddBell(var Dest: TBufF; Start: Integer; Hz, Dur, Vol: Single; R: Integer);
procedure AddTom(var Dest: TBufF; Start: Integer; Hz, Vol: Single; R: Integer);
procedure AddWood(var Dest: TBufF; Start: Integer; Hz, Vol: Single; R: Integer);
procedure AddCymbal(var Dest: TBufF; Start: Integer; Dur, Vol: Single; R: Integer);
procedure AddPad(var Dest: TBufF; Start: Integer; Hz, Dur, Vol: Single; R: Integer);
procedure AddGong(var Dest: TBufF; Start: Integer; Hz, Dur, Vol: Single; R: Integer);
function Rnd01: Single;
function RndS: Single;
procedure SetSynthSeed(S: LongWord);
{ sound effects }
function DefaultSfx: TSfxParams;
function SfxPreset(const Name: string): TSfxParams;
function RandomSfx: TSfxParams;
procedure MutateSfx(var P: TSfxParams; Amount: Single);
function SfxLength(const P: TSfxParams): Single;
function RenderSfx(const P: TSfxParams; R: Integer): TBufF;
procedure SaveSfx(const P: TSfxParams; const FileName: string);
function LoadSfx(const FileName: string): TSfxParams;
{ WAV and playback without SDL }
procedure WriteWavStream(S: TStream; const Data: array of SmallInt; Channels, Rate: Integer);
procedure SaveWav(const FileName: string; const Data: array of SmallInt; Channels, Rate: Integer);
function FloatToPcm(const B: array of Single): TTrackData;
procedure PlayPcm(const Data: array of SmallInt; Channels, Rate: Integer; Loop: Boolean = False);
procedure StopPcm;

implementation

var
  GSeed: LongWord = 12345;

procedure SetSynthSeed(S: LongWord);
begin
  GSeed := S;
end;

function NoteName(Midi: Integer): string;
const
  N: array[0..11] of string = ('C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B');
begin
  Result := N[((Midi mod 12) + 12) mod 12] + IntToStr(Midi div 12 - 1);
end;

function Rnd01: Single;
begin
  GSeed := GSeed * 1664525 + 1013904223;
  Result := (GSeed shr 8) / 16777216;
end;

function RndS: Single;
begin
  Result := Rnd01 * 2 - 1;
end;

function NoteHz(Midi: Single): Single;
begin
  Result := 440 * Power(2, (Midi - 69) / 12);
end;

{ Karplus-Strong plucked string into Dest (mono) at Start, rate R }
procedure AddPluck(var Dest: TBufF; Start: Integer; Hz, Dur, Vol, Decay, Bright: Single; R: Integer);
var
  N, I, Len, P: Integer;
  Line: TBufF;
  V, Prev: Single;
begin
  N := Max(2, Round(R / Hz));
  SetLength(Line, N);
  Prev := 0;
  for I := 0 to N - 1 do
  begin
    V := RndS;
    Line[I] := Prev + (V - Prev) * Bright;  // a darker burst for a softer pluck
    Prev := Line[I];
  end;
  Len := Round(Dur * R);
  P := 0;
  for I := 0 to Len - 1 do
  begin
    if Start + I >= Length(Dest) then Break;
    if Start + I >= 0 then
      Dest[Start + I] := Dest[Start + I] + Line[P] * Vol * Min(1, (Len - I) / (0.02 * R));
    Line[P] := Decay * 0.5 * (Line[P] + Line[(P + 1) mod N]);
    P := (P + 1) mod N;
  end;
end;

procedure AddFlute(var Dest: TBufF; Start: Integer; Hz, Dur, Vol: Single; R: Integer);
var
  I, Len: Integer;
  T, Ph, Env, Vib, Br, LP: Single;
begin
  Len := Round((Dur + 0.15) * R);
  Ph := 0;
  LP := 0;
  for I := 0 to Len - 1 do
  begin
    if Start + I >= Length(Dest) then Break;
    T := I / R;
    Vib := 1 + 0.006 * Sin(2 * Pi * 5.2 * T) * Min(1, T / 0.25);
    Ph := Ph + 2 * Pi * Hz * Vib / R;
    Env := Min(1, T / 0.06) * Min(1, Max(0, (Dur + 0.15 - T) / 0.15));
    LP := LP + (RndS - LP) * 0.15;
    Br := LP * 0.18;
    if Start + I >= 0 then
      Dest[Start + I] := Dest[Start + I] + (Sin(Ph) + 0.22 * Sin(2 * Ph) + 0.07 * Sin(3 * Ph) + Br) * Env * Vol;
  end;
end;

procedure AddErhu(var Dest: TBufF; Start: Integer; Hz, Dur, Vol: Single; R: Integer);
var
  I, K, Len: Integer;
  T, Ph, Env, Vib, S: Single;
begin
  Len := Round((Dur + 0.2) * R);
  Ph := 0;
  for I := 0 to Len - 1 do
  begin
    if Start + I >= Length(Dest) then Break;
    T := I / R;
    Vib := 1 + 0.012 * Sin(2 * Pi * 6 * T) * EnsureRange((T - 0.15) / 0.3, 0, 1);
    Ph := Ph + 2 * Pi * Hz * Vib / R;
    S := 0;
    for K := 1 to 7 do
      if Hz * K < R * 0.45 then S := S + Sin(K * Ph) / K * (1 - K * 0.08);
    Env := Min(1, T / 0.14) * Min(1, Max(0, (Dur + 0.2 - T) / 0.2));
    if Start + I >= 0 then
      Dest[Start + I] := Dest[Start + I] + S * 0.55 * Env * Vol;
  end;
end;

procedure AddBell(var Dest: TBufF; Start: Integer; Hz, Dur, Vol: Single; R: Integer);
const
  Pt: array[0..4] of Single = (1, 2.0, 2.76, 4.07, 5.4);
  Am: array[0..4] of Single = (1, 0.45, 0.35, 0.18, 0.1);
  Dc: array[0..4] of Single = (1.0, 0.7, 0.5, 0.3, 0.2);
var
  I, K, Len: Integer;
  T, S: Single;
begin
  Len := Round(Dur * R);
  for I := 0 to Len - 1 do
  begin
    if Start + I >= Length(Dest) then Break;
    T := I / R;
    S := 0;
    for K := 0 to 4 do
      if Hz * Pt[K] < R * 0.45 then
        S := S + Sin(2 * Pi * Hz * Pt[K] * T) * Am[K] * Exp(-T / (Dc[K] * Dur * 0.5));
    if Start + I >= 0 then
      Dest[Start + I] := Dest[Start + I] + S * Vol * Min(1, T / 0.003);
  end;
end;

procedure AddTom(var Dest: TBufF; Start: Integer; Hz, Vol: Single; R: Integer);
var
  I, Len: Integer;
  T, Ph, F: Single;
begin
  Len := Round(0.45 * R);
  Ph := 0;
  for I := 0 to Len - 1 do
  begin
    if Start + I >= Length(Dest) then Break;
    T := I / R;
    F := Hz * (1 + 1.2 * Exp(-T * 30));
    Ph := Ph + 2 * Pi * F / R;
    if Start + I >= 0 then
      Dest[Start + I] := Dest[Start + I] + (Sin(Ph) * Exp(-T * 7) + RndS * 0.3 * Exp(-T * 60)) * Vol;
  end;
end;

procedure AddWood(var Dest: TBufF; Start: Integer; Hz, Vol: Single; R: Integer);
var
  I, Len: Integer;
  T: Single;
begin
  Len := Round(0.08 * R);
  for I := 0 to Len - 1 do
  begin
    if Start + I >= Length(Dest) then Break;
    T := I / R;
    if Start + I >= 0 then
      Dest[Start + I] := Dest[Start + I] + (Sin(2 * Pi * Hz * T) + 0.4 * Sin(2 * Pi * Hz * 2.4 * T)) *
        Exp(-T * 55) * Vol;
  end;
end;

procedure AddCymbal(var Dest: TBufF; Start: Integer; Dur, Vol: Single; R: Integer);
var
  I, Len: Integer;
  T, HP, Prev, N: Single;
begin
  Len := Round(Dur * R);
  Prev := 0;
  for I := 0 to Len - 1 do
  begin
    if Start + I >= Length(Dest) then Break;
    T := I / R;
    N := RndS;
    HP := N - Prev;  // crude high pass: bright noise
    Prev := N;
    if Start + I >= 0 then
      Dest[Start + I] := Dest[Start + I] + HP * Exp(-T * 4 / Dur) * Vol * 0.5;
  end;
end;

procedure AddPad(var Dest: TBufF; Start: Integer; Hz, Dur, Vol: Single; R: Integer);
var
  I, Len: Integer;
  T, Env: Single;
begin
  Len := Round(Dur * R);
  for I := 0 to Len - 1 do
  begin
    if Start + I >= Length(Dest) then Break;
    T := I / R;
    Env := Sin(Pi * T / Dur);
    Env := Env * Env;
    if Start + I >= 0 then
      Dest[Start + I] := Dest[Start + I] + (Sin(2 * Pi * Hz * T) + Sin(2 * Pi * Hz * 1.003 * T) +
        0.3 * Sin(2 * Pi * Hz * 2.002 * T)) * Env * Vol * 0.4;
  end;
end;

{ ====================================================================== }
{ music                                                                   }
{ ====================================================================== }


procedure AddGong(var Dest: TBufF; Start: Integer; Hz, Dur, Vol: Single; R: Integer);
var
  I, Len: Integer;
  T: Single;
begin
  Len := Round(Dur * R);
  for I := 0 to Len - 1 do
  begin
    if Start + I >= Length(Dest) then Break;
    T := I / R;
    if Start + I >= 0 then
      Dest[Start + I] := Dest[Start + I] + ((Sin(2 * Pi * Hz * T) * 0.6 + Sin(2 * Pi * Hz * 1.48 * T) * 0.4 +
        Sin(2 * Pi * Hz * 2.1 * T) * 0.3 + Sin(2 * Pi * Hz * 3.15 * T) * 0.15 * Exp(-T * 3)) * Exp(-T * 3 / Dur) *
        Min(1, T / 0.01) * 0.6 + RndS * 0.3 * Exp(-T * 40)) * Vol;
  end;
end;

{ ====================================================================== }
{ songs                                                                   }
{ ====================================================================== }

function InstrumentByName(const S: string): TInstrument;
var
  I: TInstrument;
begin
  for I := Low(TInstrument) to High(TInstrument) do
    if SameText(InstrumentIds[I], S) or SameText(InstrumentNames[I], S) then Exit(I);
  Result := inGuzheng;
end;

constructor TSong.Create;
begin
  inherited Create;
  Name := 'New tune';
  Bpm := 90;
  Root := 62;
  Scale := 0;
  Bars := 8;
  Echo := 0.28;
end;

function TSong.StepSeconds: Single;
begin
  Result := 60 / Max(20, Bpm) / StepsPerBeat;
end;

function TSong.TotalSteps: Integer;
begin
  Result := Bars * 4 * StepsPerBeat;
end;

function TSong.AddTrack(const AName: string; AInstr: TInstrument; AVol, APan: Single): Integer;
begin
  SetLength(Tracks, Length(Tracks) + 1);
  Result := High(Tracks);
  Tracks[Result].Name := AName;
  Tracks[Result].Instr := AInstr;
  Tracks[Result].Vol := AVol;
  Tracks[Result].Pan := APan;
  Tracks[Result].Mute := False;
  SetLength(Tracks[Result].Notes, 0);
end;

procedure TSong.AddNote(T, AStep, ALen, APitch: Integer; AVel: Single);
begin
  if (T < 0) or (T > High(Tracks)) then Exit;
  with Tracks[T] do
  begin
    SetLength(Notes, Length(Notes) + 1);
    Notes[High(Notes)].Step := AStep;
    Notes[High(Notes)].Len := Max(1, ALen);
    Notes[High(Notes)].Pitch := APitch;
    Notes[High(Notes)].Vel := AVel;
  end;
end;

procedure TSong.Assign(Src: TSong);
var
  I: Integer;
begin
  Name := Src.Name;
  Bpm := Src.Bpm;
  Root := Src.Root;
  Scale := Src.Scale;
  Bars := Src.Bars;
  Echo := Src.Echo;
  SetLength(Tracks, Length(Src.Tracks));
  for I := 0 to High(Tracks) do
  begin
    Tracks[I] := Src.Tracks[I];
    Tracks[I].Notes := Copy(Src.Tracks[I].Notes);
  end;
end;

function TSong.InScale(Pitch: Integer): Boolean;
var
  PC: Integer;
begin
  PC := ((Pitch - Root) mod 12 + 12) mod 12;
  case Scale of
    0: Result := PC in [0, 2, 4, 7, 9];
    1: Result := PC in [0, 3, 5, 7, 10];
  else
    Result := True;
  end;
end;

procedure TSong.SaveToFile(const FileName: string);
var
  SL: TStringList;
  T, N: Integer;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SL := TStringList.Create;
  try
    SL.Add('PCMUSIC 1');
    SL.Add('name=' + Name);
    SL.Add('bpm=' + FloatToStr(Bpm, FS));
    SL.Add('root=' + IntToStr(Root));
    SL.Add('scale=' + ScaleIds[EnsureRange(Scale, 0, 2)]);
    SL.Add('bars=' + IntToStr(Bars));
    SL.Add('echo=' + FloatToStr(Echo, FS));
    for T := 0 to High(Tracks) do
      with Tracks[T] do
      begin
        SL.Add(Format('track=%s;%s;%s;%s;%d', [StringReplace(Name, ';', ',', [rfReplaceAll]),
          InstrumentIds[Instr], FloatToStr(Vol, FS), FloatToStr(Pan, FS), Ord(Mute)]));
        for N := 0 to High(Notes) do
          SL.Add(Format('note=%d;%d;%d;%s', [Notes[N].Step, Notes[N].Len, Notes[N].Pitch,
            FloatToStr(Notes[N].Vel, FS)]));
      end;
    SL.SaveToFile(FileName);
  finally
    SL.Free;
  end;
end;

procedure TSong.LoadFromFile(const FileName: string);
var
  SL, P: TStringList;
  I, T: Integer;
  K, V: string;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SL := TStringList.Create;
  P := TStringList.Create;
  try
    P.Delimiter := ';';
    P.StrictDelimiter := True;
    SL.LoadFromFile(FileName);
    if (SL.Count = 0) or (Copy(SL[0], 1, 7) <> 'PCMUSIC') then
      raise Exception.Create('not a Paper Crane music file: ' + FileName);
    SetLength(Tracks, 0);
    T := -1;
    for I := 1 to SL.Count - 1 do
    begin
      K := SL.Names[I];
      V := SL.ValueFromIndex[I];
      if K = 'name' then Name := V
      else if K = 'bpm' then Bpm := StrToFloatDef(V, 90, FS)
      else if K = 'root' then Root := StrToIntDef(V, 62)
      else if K = 'scale' then
      begin
        if V = 'yu' then Scale := 1 else if V = 'chromatic' then Scale := 2 else Scale := 0;
      end
      else if K = 'bars' then Bars := EnsureRange(StrToIntDef(V, 8), 1, 256)
      else if K = 'echo' then Echo := StrToFloatDef(V, 0.28, FS)
      else if K = 'track' then
      begin
        P.DelimitedText := V;
        while P.Count < 5 do P.Add('');
        T := AddTrack(P[0], InstrumentByName(P[1]), StrToFloatDef(P[2], 1, FS), StrToFloatDef(P[3], 0, FS));
        Tracks[T].Mute := P[4] = '1';
      end
      else if (K = 'note') and (T >= 0) then
      begin
        P.DelimitedText := V;
        if P.Count >= 4 then
          AddNote(T, StrToIntDef(P[0], 0), StrToIntDef(P[1], 1), StrToIntDef(P[2], 60), StrToFloatDef(P[3], 0.5, FS));
      end;
    end;
  finally
    P.Free;
    SL.Free;
  end;
end;

{ one note of an instrument into a mono buffer }
procedure RenderNote(var B: TBufF; Instr: TInstrument; Start: Integer; Pitch: Integer; LenS, Vel: Single; R: Integer);
var
  Hz: Single;
begin
  Hz := NoteHz(Pitch);
  case Instr of
    inGuzheng: AddPluck(B, Start, Hz, LenS, Vel, 0.997, 0.8, R);
    inBass: AddPluck(B, Start, Hz, LenS, Vel, 0.996, 0.5, R);
    inPipa: AddPluck(B, Start, Hz, LenS, Vel, 0.99, 0.9, R);
    inSoftZither: AddPluck(B, Start, Hz, LenS, Vel, 0.998, 0.6, R);
    inDizi: AddFlute(B, Start, Hz, LenS * 0.92, Vel, R);
    inErhu: AddErhu(B, Start, Hz, LenS * 0.95, Vel, R);
    inBells: AddBell(B, Start, Hz, Max(2.2, LenS), Vel, R);
    inPad: AddPad(B, Start, Hz, LenS, Vel, R);
    inTanggu: AddTom(B, Start, Hz, Vel, R);
    inWoodblock: AddWood(B, Start, Hz, Vel, R);
    inCymbal: AddCymbal(B, Start, LenS, Vel, R);
    inGong: AddGong(B, Start, Hz, Max(1.5, LenS), Vel, R);
  end;
end;

{ the whole song as interleaved stereo SmallInt at rate R: tracks panned, notes
  ringing past the end folded onto the start (a seamless loop), a stereo echo,
  normalised to 0.8 }
function TSong.Render(R: Integer; Normalize: Boolean = True): TTrackData;
var
  Total, Tail, T, N, I, J, Dl, Dr: Integer;
  StepS, Gl, GR, Peak: Single;
  Buf, L, Rr: TBufF;
begin
  StepS := StepSeconds;
  Total := Max(1, Round(TotalSteps * StepS * R));
  Tail := 5 * R;
  SetLength(L, Total);
  SetLength(Rr, Total);
  GSeed := 4321;
  for T := 0 to High(Tracks) do
    with Tracks[T] do
    begin
      if Mute or (Length(Notes) = 0) then Continue;
      SetLength(Buf, 0);
      SetLength(Buf, Total + Tail);
      for N := 0 to High(Notes) do
        RenderNote(Buf, Instr, Round(Notes[N].Step * StepS * R), Notes[N].Pitch, Notes[N].Len * StepS,
          Notes[N].Vel, R);
      for I := Total to High(Buf) do
        Buf[I - Total] := Buf[I - Total] + Buf[I];
      Gl := Vol * 1.3 * (1 - Pan) / 2;
      GR := Vol * 1.3 * (1 + Pan) / 2;
      for I := 0 to Total - 1 do
      begin
        L[I] := L[I] + Buf[I] * Gl;
        Rr[I] := Rr[I] + Buf[I] * GR;
      end;
    end;
  if Echo > 0 then
  begin
    Dl := Round(StepS * StepsPerBeat * 0.75 * R);
    Dr := Round(StepS * StepsPerBeat * 1.0 * R);
    for I := 0 to Total - 1 do
    begin
      J := I - Dl;
      if J < 0 then J := J + Total;
      L[I] := L[I] + Rr[J] * Echo;
      J := I - Dr;
      if J < 0 then J := J + Total;
      Rr[I] := Rr[I] + L[J] * Echo;
    end;
  end;
  Peak := 0.001;
  for I := 0 to Total - 1 do
    Peak := Max(Peak, Max(Abs(L[I]), Abs(Rr[I])));
  if Normalize then Gl := 0.8 / Peak else Gl := Min(1, 0.95 / Peak);
  SetLength(Result, Total * 2);
  for I := 0 to Total - 1 do
  begin
    Result[I * 2] := Round(EnsureRange(L[I] * Gl, -1, 1) * 32000);
    Result[I * 2 + 1] := Round(EnsureRange(Rr[I] * Gl, -1, 1) * 32000);
  end;
end;

{ ---------- the 7 built-in tunes as songs (composed procedurally) ---------- }

type
  TTuneDef = record
    Bpm: Single;
    Root: Integer;
    Minor: Boolean;
    Bars: Integer;
    Lead: Integer;          // 0 dizi, 1 erhu, 2 bells
    Arp: Integer;           // 0 none, 1 guzheng eighths, 2 pipa 16ths, 3 sparse
    Drums: Integer;         // 0 none, 1 woodblock, 2 tom + woodblock, 3 festival drums + cymbal
    Pad: Boolean;
    Seed: LongWord;
  end;

const
  Defs: array[0..BuiltinCount - 1] of TTuneDef = (
    (Bpm: 72; Root: 62; Minor: False; Bars: 16; Lead: 0; Arp: 1; Drums: 0; Pad: True; Seed: 11),
    (Bpm: 108; Root: 67; Minor: False; Bars: 16; Lead: 0; Arp: 1; Drums: 2; Pad: False; Seed: 23),
    (Bpm: 124; Root: 60; Minor: False; Bars: 16; Lead: 2; Arp: 2; Drums: 3; Pad: False; Seed: 37),
    (Bpm: 62; Root: 57; Minor: True; Bars: 12; Lead: 1; Arp: 3; Drums: 0; Pad: True; Seed: 41),
    (Bpm: 82; Root: 64; Minor: True; Bars: 16; Lead: 0; Arp: 3; Drums: 1; Pad: True; Seed: 53),
    (Bpm: 92; Root: 65; Minor: False; Bars: 16; Lead: 1; Arp: 1; Drums: 1; Pad: False; Seed: 67),
    (Bpm: 58; Root: 72; Minor: False; Bars: 12; Lead: 2; Arp: 3; Drums: 0; Pad: True; Seed: 79));

  GongSteps: array[0..4] of Integer = (0, 2, 4, 7, 9);
  YuSteps: array[0..4] of Integer = (0, 3, 5, 7, 10);

function Degree(const D: TTuneDef; Deg: Integer): Integer;
var
  Oct, I: Integer;
begin
  Oct := Floor(Deg / 5);
  I := Deg - Oct * 5;
  if D.Minor then Result := D.Root + Oct * 12 + YuSteps[I]
  else Result := D.Root + Oct * 12 + GongSteps[I];
end;

function BuiltinSong(Index: Integer): TSong;
const
  Prog: array[0..7] of Integer = (0, 3, 4, 0, 2, 3, 1, 0);
  Rhythms: array[0..5, 0..3] of Single = ((1, 1, 1, 1), (1.5, 0.5, 1, 1), (2, 1, 1, 0), (0.5, 0.5, 1, 2),
    (1, 0.5, 0.5, 2), (3, 1, 0, 0));
var
  D: TTuneDef;
  S: TSong;
  Bar, Beat, K, Chord, Deg, Phrase, NI, Sub, B0: Integer;
  V, Len: Single;
  Motif: array[0..3, 0..15] of Integer;
  MotifR: array[0..3] of Integer;
  TLead, TBass, TArp, TPad, TTom, TWood, TCym: Integer;
  LeadInstr: TInstrument;
begin
  D := Defs[EnsureRange(Index, 0, BuiltinCount - 1)];
  GSeed := D.Seed * 7919 + 17;
  S := TSong.Create;
  S.Name := BuiltinNames[Index];
  S.Bpm := D.Bpm;
  S.Root := D.Root;
  if D.Minor then S.Scale := 1 else S.Scale := 0;
  S.Bars := D.Bars;
  S.Echo := 0.28;
  case D.Lead of
    0: LeadInstr := inDizi;
    1: LeadInstr := inErhu;
  else
    LeadInstr := inBells;
  end;
  TLead := S.AddTrack('Melody', LeadInstr, 1, -0.15);
  TBass := S.AddTrack('Bass', inBass, 1, 0.15);
  case D.Arp of
    2: TArp := S.AddTrack('Tremolo', inPipa, 1, 0.15);
    3: TArp := S.AddTrack('Zither', inSoftZither, 1, 0.15);
  else
    TArp := S.AddTrack('Arpeggio', inGuzheng, 1, 0.15);
  end;
  TPad := S.AddTrack('Pad', inPad, 1, 0.15);
  TTom := S.AddTrack('Drums', inTanggu, 1.08, 0);
  TWood := S.AddTrack('Woodblock', inWoodblock, 1.08, 0);
  TCym := S.AddTrack('Cymbal', inCymbal, 1.08, 0);
  for Phrase := 0 to 3 do
  begin
    MotifR[Phrase] := Floor(Rnd01 * 6);
    Deg := 5 + Floor(Rnd01 * 3);
    for K := 0 to 15 do
    begin
      Deg := EnsureRange(Deg + Round(RndS * 2.2), 3, 10);
      Motif[Phrase, K] := Deg;
    end;
  end;
  for K := 0 to 15 do Motif[1, K] := Motif[0, K] + IfThen(K >= 4, Round(RndS), 0);
  for K := 0 to 15 do Motif[3, K] := Motif[0, K];
  Motif[3, 7] := 5;
  Motif[0, 7] := 7;
  for Bar := 0 to D.Bars - 1 do
  begin
    Chord := Prog[(Bar div 2) mod 8];
    B0 := Bar * 16;
    for Beat := 0 to 3 do
      if (Beat = 0) or (Beat = 2) then
        S.AddNote(TBass, B0 + Beat * 4, 8, Degree(D, Chord - 5), 0.5);
    case D.Arp of
      1: for Sub := 0 to 7 do
           S.AddNote(TArp, B0 + Sub * 2, 6, Degree(D, Chord + Sub mod 4 + IfThen(Sub >= 4, 1, 0)), 0.22);
      2: for Sub := 0 to 15 do
           S.AddNote(TArp, B0 + Sub, 2, Degree(D, Chord + 5 + IfThen(Odd(Sub div 2), 2, 0)), 0.13);
      3: for Sub := 0 to 3 do
           if (Sub <> 1) or Odd(Bar) then
             S.AddNote(TArp, B0 + Sub * 4 + 2 * Ord(Sub = 3), 12, Degree(D, Chord + 3 + Sub), 0.2);
    end;
    if D.Pad and (Bar mod 2 = 0) then
    begin
      S.AddNote(TPad, B0, 32, Degree(D, Chord), 0.12);
      S.AddNote(TPad, B0, 32, Degree(D, Chord + 2), 0.09);
    end;
    case D.Drums of
      1: for Beat := 0 to 3 do
           S.AddNote(TWood, B0 + Beat * 4 + 2, 1, IfThen(Odd(Beat), 85, 81), 0.18);
      2: for Beat := 0 to 3 do
         begin
           if (Beat = 0) or (Beat = 2) then S.AddNote(TTom, B0 + Beat * 4, 2, 42, 0.55);
           S.AddNote(TWood, B0 + Beat * 4 + 2, 1, 83, 0.16);
         end;
      3: begin
           for Beat := 0 to 3 do
           begin
             S.AddNote(TTom, B0 + Beat * 4, 2, IfThen(Beat = 0, 37, 44), 0.6);
             if Odd(Beat) then S.AddNote(TTom, B0 + Beat * 4 + 2, 2, 48, 0.3);
           end;
           if Bar mod 2 = 0 then S.AddNote(TCym, B0, Round(1.2 / S.StepSeconds), 72, 0.35);
         end;
    end;
    Phrase := (Bar div 2) mod 4;
    if (Index = 6) and Odd(Bar) then Continue;
    Len := 0;
    NI := (Bar mod 2) * 4;
    for Beat := 0 to 3 do
    begin
      V := Rhythms[MotifR[Phrase], Beat];
      if V <= 0 then Continue;
      Deg := Motif[Phrase, NI + Beat];
      if (Bar mod 2 = 1) and (Beat >= 2) and (Phrase in [1, 3]) then Deg := Chord + 5;
      case D.Lead of
        0: S.AddNote(TLead, B0 + Round(Len * 4), Round(V * 4), Degree(D, Deg), 0.3);
        1: S.AddNote(TLead, B0 + Round(Len * 4), Round(V * 4), Degree(D, Deg - 5), 0.32);
      else
        S.AddNote(TLead, B0 + Round(Len * 4), Round(V * 4), Degree(D, Deg + 5), 0.22);
      end;
      Len := Len + V;
    end;
  end;
  Result := S;
end;

{ ====================================================================== }
{ sound effects from parameters (an sfxr-like synth)                      }
{ ====================================================================== }

function DefaultSfx: TSfxParams;
begin
  Result := Default(TSfxParams);
  Result.Name := 'new sound';
  Result.Wave := wvSine;
  Result.Freq := 440;
  Result.FreqEnd := 440;
  Result.Curve := 1;
  Result.Attack := 0.01;
  Result.Sustain := 0.1;
  Result.Release := 0.2;
  Result.Duty := 0.5;
  Result.LowPass := 1;
  Result.HighPass := 0;
  Result.Volume := 0.8;
  Result.RepeatGap := 0.1;
  Result.EchoDelay := 0.12;
  Result.VibRate := 6;
end;

function SfxLength(const P: TSfxParams): Single;
begin
  Result := (P.Attack + P.Sustain + P.Release) * (1 + P.Repeats) + P.RepeatGap * P.Repeats;
  if P.Echo > 0 then Result := Result + P.EchoDelay * 4;
  Result := EnsureRange(Result, 0.01, 10);
end;

function RenderSfx(const P: TSfxParams; R: Integer): TBufF;
var
  N, I, Rep, Start, OneLen, KN, KP: Integer;
  T, Life, F, Env, Ph, V, LP, HP, HPPrev, Vib, Peak, A, Prog: Single;
  One, Line: TBufF;
begin
  GSeed := 777;
  Life := Max(0.005, P.Attack + P.Sustain + P.Release);
  OneLen := Max(1, Round(Life * R));
  SetLength(One, OneLen);
  Ph := 0;
  LP := 0;
  HP := 0;
  HPPrev := 0;
  // the Karplus-Strong line for the pluck wave
  KN := Max(2, Round(R / Max(20, P.Freq)));
  SetLength(Line, KN);
  for I := 0 to KN - 1 do Line[I] := RndS;
  KP := 0;
  for I := 0 to OneLen - 1 do
  begin
    T := I / R;
    Prog := T / Life;
    if T < P.Attack then Env := T / Max(0.0001, P.Attack)
    else if T < P.Attack + P.Sustain then Env := 1 + P.Punch * (1 - (T - P.Attack) / Max(0.0001, P.Sustain))
    else Env := Max(0, 1 - (T - P.Attack - P.Sustain) / Max(0.0001, P.Release));
    F := P.Freq + (P.FreqEnd - P.Freq) * Power(Min(1, Prog), Max(0.05, P.Curve));
    if (P.ArpTime > 0) and (Prog >= P.ArpTime) then F := F * P.ArpMul;
    Vib := 1 + (Power(2, P.VibDepth / 12) - 1) * Sin(2 * Pi * P.VibRate * T);
    Ph := Ph + F * Vib / R;
    Ph := Ph - Floor(Ph);
    case P.Wave of
      wvSine: V := Sin(2 * Pi * Ph);
      wvSquare: if Ph < P.Duty then V := 0.7 else V := -0.7;
      wvSaw: V := (2 * Ph - 1) * 0.8;
      wvTriangle: V := 1 - 4 * Abs(Ph - 0.5);
      wvNoise: V := RndS;
      wvPluck:
        begin
          V := Line[KP];
          Line[KP] := 0.996 * 0.5 * (Line[KP] + Line[(KP + 1) mod KN]);
          KP := (KP + 1) mod KN;
        end;
      wvBell: V := Sin(2 * Pi * Ph) + 0.4 * Sin(2 * Pi * Ph * 2.76) * Exp(-T * 6) + 0.25 * Sin(2 * Pi * Ph * 5.4) * Exp(-T * 10);
    else  // wvBreath: band-limited noise
      begin
        LP := LP + (RndS - LP) * EnsureRange(F / R * 6, 0.01, 1);
        V := LP * 2.5;
      end;
    end;
    if P.Noise > 0 then V := V * (1 - P.Noise) + RndS * P.Noise;
    // filters: one-pole low pass (LowPass 1 = open) and high pass
    if P.Wave <> wvBreath then
    begin
      A := Sqr(EnsureRange(P.LowPass, 0.01, 1));
      LP := LP + (V - LP) * A;
      V := LP;
    end;
    if P.HighPass > 0 then
    begin
      HP := 0.99 * (HP + V - HPPrev) * (1 - P.HighPass * 0.5) + 0.0;
      HPPrev := V;
      V := V * (1 - P.HighPass) + HP * P.HighPass;
    end;
    One[I] := V * Env;
  end;
  N := Max(1, Round(SfxLength(P) * R));
  SetLength(Result, N);
  FillChar(Result[0], N * SizeOf(Single), 0);
  for Rep := 0 to P.Repeats do
  begin
    Start := Round(Rep * (Life + P.RepeatGap) * R);
    for I := 0 to OneLen - 1 do
      if Start + I < N then Result[Start + I] := Result[Start + I] + One[I] * Power(0.8, Rep);
  end;
  if P.Echo > 0 then
  begin
    KN := Max(1, Round(P.EchoDelay * R));
    for I := KN to N - 1 do
      Result[I] := Result[I] + Result[I - KN] * P.Echo;
  end;
  Peak := 0.0001;
  for I := 0 to N - 1 do Peak := Max(Peak, Abs(Result[I]));
  for I := 0 to N - 1 do Result[I] := Result[I] / Peak * 0.85 * EnsureRange(P.Volume, 0, 1);
end;

procedure SaveSfx(const P: TSfxParams; const FileName: string);
var
  SL: TStringList;
  FS: TFormatSettings;

  procedure F(const K: string; V: Single);
  begin
    SL.Add(K + '=' + FloatToStr(V, FS));
  end;

begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SL := TStringList.Create;
  try
    SL.Add('PCSFX 1');
    SL.Add('name=' + P.Name);
    SL.Add('wave=' + WaveIds[P.Wave]);
    F('freq', P.Freq); F('freqend', P.FreqEnd); F('curve', P.Curve);
    F('attack', P.Attack); F('sustain', P.Sustain); F('release', P.Release); F('punch', P.Punch);
    F('vibdepth', P.VibDepth); F('vibrate', P.VibRate); F('duty', P.Duty); F('noise', P.Noise);
    F('lowpass', P.LowPass); F('highpass', P.HighPass); F('arpmul', P.ArpMul); F('arptime', P.ArpTime);
    SL.Add('repeats=' + IntToStr(P.Repeats));
    F('repeatgap', P.RepeatGap); F('echo', P.Echo); F('echodelay', P.EchoDelay); F('volume', P.Volume);
    SL.SaveToFile(FileName);
  finally
    SL.Free;
  end;
end;

function LoadSfx(const FileName: string): TSfxParams;
var
  SL: TStringList;
  FS: TFormatSettings;
  W: TWave;

  function G(const K: string; Def: Single): Single;
  begin
    Result := StrToFloatDef(SL.Values[K], Def, FS);
  end;

begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := DefaultSfx;
  SL := TStringList.Create;
  try
    SL.LoadFromFile(FileName);
    if (SL.Count = 0) or (Copy(SL[0], 1, 5) <> 'PCSFX') then
      raise Exception.Create('not a Paper Crane sound file: ' + FileName);
    Result.Name := SL.Values['name'];
    for W := Low(TWave) to High(TWave) do
      if WaveIds[W] = SL.Values['wave'] then Result.Wave := W;
    Result.Freq := G('freq', 440); Result.FreqEnd := G('freqend', 440); Result.Curve := G('curve', 1);
    Result.Attack := G('attack', 0.01); Result.Sustain := G('sustain', 0.1); Result.Release := G('release', 0.2);
    Result.Punch := G('punch', 0); Result.VibDepth := G('vibdepth', 0); Result.VibRate := G('vibrate', 6);
    Result.Duty := G('duty', 0.5); Result.Noise := G('noise', 0); Result.LowPass := G('lowpass', 1);
    Result.HighPass := G('highpass', 0); Result.ArpMul := G('arpmul', 1); Result.ArpTime := G('arptime', 0);
    Result.Repeats := StrToIntDef(SL.Values['repeats'], 0); Result.RepeatGap := G('repeatgap', 0.1);
    Result.Echo := G('echo', 0); Result.EchoDelay := G('echodelay', 0.12); Result.Volume := G('volume', 0.8);
  finally
    SL.Free;
  end;
end;

function SfxPreset(const Name: string): TSfxParams;
begin
  Result := DefaultSfx;
  Result.Name := Name;
  if Name = 'flap' then
  begin
    Result.Wave := wvBreath; Result.Freq := 900; Result.FreqEnd := 2600; Result.Curve := 0.6;
    Result.Attack := 0.06; Result.Sustain := 0.04; Result.Release := 0.12;
  end
  else if Name = 'pass' then
  begin
    Result.Wave := wvSine; Result.Freq := 1250; Result.FreqEnd := 1250; Result.Attack := 0.001;
    Result.Sustain := 0.0; Result.Release := 0.07; Result.Noise := 0.05;
  end
  else if Name = 'lantern' then
  begin
    Result.Wave := wvBell; Result.Freq := 1047; Result.FreqEnd := 1047; Result.Attack := 0.002;
    Result.Sustain := 0.02; Result.Release := 0.5; Result.ArpMul := 1.26; Result.ArpTime := 0.12;
    Result.Repeats := 1; Result.RepeatGap := -0.4; Result.Echo := 0.25;
  end
  else if Name = 'hit' then
  begin
    Result.Wave := wvNoise; Result.Freq := 200; Result.FreqEnd := 60; Result.Attack := 0.002;
    Result.Sustain := 0.05; Result.Release := 0.3; Result.LowPass := 0.6; Result.Punch := 0.6;
  end
  else if Name = 'fall' then
  begin
    Result.Wave := wvSine; Result.Freq := 950; Result.FreqEnd := 170; Result.Curve := 0.8;
    Result.Attack := 0.05; Result.Sustain := 0.5; Result.Release := 0.3;
  end
  else if Name = 'splash' then
  begin
    Result.Wave := wvNoise; Result.Attack := 0.005; Result.Sustain := 0.05; Result.Release := 0.6;
    Result.LowPass := 0.55;
  end
  else if Name = 'game over' then
  begin
    Result.Wave := wvPluck; Result.Freq := 880; Result.FreqEnd := 440; Result.Curve := 1;
    Result.Attack := 0.001; Result.Sustain := 0.3; Result.Release := 0.9; Result.Repeats := 3;
    Result.RepeatGap := -1.0; Result.ArpMul := 0.75; Result.ArpTime := 0.5;
  end
  else if Name = 'new best' then
  begin
    Result.Wave := wvBell; Result.Freq := 523; Result.FreqEnd := 1047; Result.Curve := 0.3;
    Result.Attack := 0.002; Result.Sustain := 0.2; Result.Release := 1.4; Result.Echo := 0.3;
  end
  else if Name = 'menu move' then
  begin
    Result.Wave := wvPluck; Result.Freq := 659; Result.FreqEnd := 659; Result.Attack := 0.001;
    Result.Sustain := 0.05; Result.Release := 0.2;
  end
  else if Name = 'menu select' then
  begin
    Result.Wave := wvPluck; Result.Freq := 784; Result.FreqEnd := 784; Result.Attack := 0.001;
    Result.Sustain := 0.05; Result.Release := 0.3; Result.ArpMul := 1.33; Result.ArpTime := 0.2;
  end
  else if Name = 'menu back' then
  begin
    Result.Wave := wvPluck; Result.Freq := 523; Result.FreqEnd := 523; Result.Attack := 0.001;
    Result.Sustain := 0.05; Result.Release := 0.3; Result.ArpMul := 0.75; Result.ArpTime := 0.2;
  end
  else if Name = 'thunder' then
  begin
    Result.Wave := wvBreath; Result.Freq := 60; Result.FreqEnd := 30; Result.Attack := 0.03;
    Result.Sustain := 0.6; Result.Release := 2.4; Result.VibDepth := 0; Result.Punch := 0.8;
  end
  else if Name = 'start gong' then
  begin
    Result.Wave := wvBell; Result.Freq := 110; Result.FreqEnd := 108; Result.Attack := 0.005;
    Result.Sustain := 0.3; Result.Release := 2.6;
  end
  else if Name = 'coin' then
  begin
    Result.Wave := wvSquare; Result.Freq := 988; Result.FreqEnd := 988; Result.Attack := 0.001;
    Result.Sustain := 0.05; Result.Release := 0.25; Result.ArpMul := 1.33; Result.ArpTime := 0.25; Result.Duty := 0.5;
  end
  else if Name = 'jump' then
  begin
    Result.Wave := wvSquare; Result.Freq := 300; Result.FreqEnd := 700; Result.Curve := 0.5;
    Result.Attack := 0.002; Result.Sustain := 0.08; Result.Release := 0.12; Result.Duty := 0.3;
  end
  else if Name = 'laser' then
  begin
    Result.Wave := wvSaw; Result.Freq := 1800; Result.FreqEnd := 200; Result.Curve := 0.4;
    Result.Attack := 0.001; Result.Sustain := 0.05; Result.Release := 0.2;
  end
  else if Name = 'explosion' then
  begin
    Result.Wave := wvNoise; Result.Attack := 0.002; Result.Sustain := 0.15; Result.Release := 1.0;
    Result.LowPass := 0.4; Result.Punch := 1;
  end
  else if Name = 'power up' then
  begin
    Result.Wave := wvTriangle; Result.Freq := 300; Result.FreqEnd := 1200; Result.Curve := 1;
    Result.Attack := 0.01; Result.Sustain := 0.3; Result.Release := 0.2; Result.VibDepth := 0.5;
    Result.VibRate := 12;
  end
  else if Name = 'blip' then
  begin
    Result.Wave := wvSquare; Result.Freq := 1400; Result.FreqEnd := 1400; Result.Attack := 0.001;
    Result.Sustain := 0.03; Result.Release := 0.04; Result.Duty := 0.25;
  end;
  if Result.ArpMul = 0 then Result.ArpMul := 1;
end;

{ a random sound in the spirit of a preset family (Mutate: small changes) }
procedure MutateSfx(var P: TSfxParams; Amount: Single);

  function J(V, Lo, Hi: Single): Single;
  begin
    Result := EnsureRange(V * (1 + (Random * 2 - 1) * Amount), Lo, Hi);
  end;

begin
  P.Freq := J(P.Freq, 20, 8000);
  P.FreqEnd := J(P.FreqEnd, 20, 8000);
  P.Attack := J(P.Attack + 0.001, 0, 2);
  P.Sustain := J(P.Sustain + 0.001, 0, 3);
  P.Release := J(P.Release + 0.001, 0.005, 4);
  P.Curve := J(P.Curve, 0.1, 5);
  P.LowPass := J(P.LowPass, 0.05, 1);
  if Random < Amount then P.VibDepth := Random * 2;
end;

function RandomSfx: TSfxParams;
begin
  Result := DefaultSfx;
  Result.Name := 'random';
  Result.Wave := TWave(Random(Ord(High(TWave)) + 1));
  Result.Freq := 80 + Random * 1800;
  Result.FreqEnd := Result.Freq * (0.25 + Random * 3);
  Result.Curve := 0.3 + Random * 2;
  Result.Attack := Random * 0.08;
  Result.Sustain := Random * 0.3;
  Result.Release := 0.05 + Random * 0.8;
  Result.Punch := Random * 0.6;
  if Random < 0.3 then Result.VibDepth := Random * 2;
  Result.VibRate := 3 + Random * 12;
  Result.Duty := 0.15 + Random * 0.7;
  Result.LowPass := 0.3 + Random * 0.7;
  if Random < 0.3 then
  begin
    Result.ArpMul := 0.5 + Random * 1.5;
    Result.ArpTime := 0.1 + Random * 0.6;
  end
  else
    Result.ArpMul := 1;
  if Random < 0.2 then Result.Repeats := 1 + Random(3);
  if Random < 0.3 then Result.Echo := Random * 0.4;
end;

{ ====================================================================== }
{ WAV files and playback without SDL                                      }
{ ====================================================================== }

procedure WriteWavStream(S: TStream; const Data: array of SmallInt; Channels, Rate: Integer);
var
  N, V: LongWord;
  W: Word;
begin
  N := Length(Data) * 2;
  S.WriteBuffer(PChar('RIFF')^, 4); V := 36 + N; S.WriteBuffer(V, 4);
  S.WriteBuffer(PChar('WAVEfmt ')^, 8); V := 16; S.WriteBuffer(V, 4);
  W := 1; S.WriteBuffer(W, 2); W := Channels; S.WriteBuffer(W, 2);
  V := Rate; S.WriteBuffer(V, 4); V := Rate * Channels * 2; S.WriteBuffer(V, 4);
  W := Channels * 2; S.WriteBuffer(W, 2); W := 16; S.WriteBuffer(W, 2);
  S.WriteBuffer(PChar('data')^, 4); S.WriteBuffer(N, 4);
  if Length(Data) > 0 then S.WriteBuffer(Data[0], N);
end;

procedure SaveWav(const FileName: string; const Data: array of SmallInt; Channels, Rate: Integer);
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmCreate);
  try
    WriteWavStream(F, Data, Channels, Rate);
  finally
    F.Free;
  end;
end;

function FloatToPcm(const B: array of Single): TTrackData;
var
  I: Integer;
begin
  SetLength(Result, Length(B));
  for I := 0 to High(B) do
    Result[I] := Round(EnsureRange(B[I], -1, 1) * 32000);
end;

var
  PlayMem: TMemoryStream = nil;

procedure PlayPcm(const Data: array of SmallInt; Channels, Rate: Integer; Loop: Boolean);
var
  Flags: LongWord;
begin
  {$IFDEF WINDOWS}
  PlaySound(nil, 0, 0);
  FreeAndNil(PlayMem);
  PlayMem := TMemoryStream.Create;
  WriteWavStream(PlayMem, Data, Channels, Rate);
  Flags := SND_MEMORY or SND_ASYNC or SND_NODEFAULT;
  if Loop then Flags := Flags or SND_LOOP;
  PlaySound(PChar(PlayMem.Memory), 0, Flags);
  {$ENDIF}
end;

procedure StopPcm;
begin
  {$IFDEF WINDOWS}
  PlaySound(nil, 0, 0);
  {$ENDIF}
end;

finalization
  {$IFDEF WINDOWS}
  PlaySound(nil, 0, 0);
  {$ENDIF}
  PlayMem.Free;
end.
