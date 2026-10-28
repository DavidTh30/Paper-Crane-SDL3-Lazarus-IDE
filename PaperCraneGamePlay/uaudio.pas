unit uAudio;

{ Sound for Paper Crane: everything is synthesised in code, no sound files.

  Mixer: one SDL3 audio stream (44.1 kHz stereo float) fed from its callback on
  SDL's audio thread. 24 sound-effect voices, two music players (the new track
  fades in while the old one fades out), a rain ambience (filtered noise).
  The main thread only sends commands (Play, PlayMusic, volumes) through a
  critical section; the callback mixes.

  Instruments (synthesised):
    guzheng / pipa  Karplus-Strong plucked string
    dizi            flute: sine + 2 harmonics, vibrato, breath noise
    erhu            bowed: band-limited saw, delayed vibrato, slow attack
    bells / gong    inharmonic partials with exponential decay
    tanggu / tom    pitch-dropping sine + click; woodblock; cymbal noise
    pad             detuned sines, slow swell
  Music: 7 tracks composed procedurally on Chinese pentatonic modes (melody
  phrases A A' B A over a chord progression, arpeggios, bass, percussion), with
  a stereo echo; rendered at 22.05 kHz in a background thread at startup, the
  menu theme first. Sound effects are rendered at 44.1 kHz when the mixer opens. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, SyncObjs, SDL3, uSynth, uPCMap;

const
  MixRate = 44100;
  MusicRate = 22050;
  TrackCount = 7;
  TrackNames: array[0..TrackCount - 1] of string = ('Li River Morning', 'Paper Wings',
    'Lantern Festival', 'Moonlit Pagoda', 'Rain on Bamboo', 'Autumn Wind', 'Snow over Karst');

type
  TSfx = (sfFlap, sfPass, sfLantern, sfHit, sfFall, sfSplash, sfGameOver, sfNewBest, sfMenuMove,
    sfMenuSelect, sfMenuBack, sfThunder, sfStart);

const
  SfxNames: array[TSfx] of string = ('flap', 'pass', 'lantern', 'hit', 'fall', 'splash', 'game over',
    'new best', 'menu move', 'menu select', 'menu back', 'thunder', 'start gong');

type
  TVoice = record
    Snd: TSfx;
    Pos, Step: Double;
    Vol, PanL, PanR: Single;
    Active: Boolean;
  end;

  TMusicPlayer = record
    Track: Integer;
    Pos: Double;           // in music frames
    Gain, Target: Single;
  end;

  TTrackData = uSynth.TTrackData;  // interleaved stereo at MusicRate
  TSingleArray = array of Single;

  TAudio = class;

  TGenThread = class(TThread)
  private
    FAudio: TAudio;
  protected
    procedure Execute; override;
  public
    constructor Create(AAudio: TAudio);
  end;

  { TAudio }

  TAudio = class
  private
    FStream: PSDL_AudioStream;
    FLock: TCriticalSection;
    FSfx: array[TSfx] of array of Single;
    FTracks: array[0..TrackCount] of TTrackData;   // slot TrackCount: a map's own tune
    FReady: array[0..TrackCount] of Boolean;
    FSongThread: TThread;
    FVoices: array[0..23] of TVoice;
    FMus: array[0..1] of TMusicPlayer;
    FMusicVol, FSfxVol, FDuck, FDuckNow: Single;
    FRain, FRainNow, FRainLP1, FRainLP2: Single;
    FNoise: LongWord;
    FBuf: array of Single;
    FGen: TGenThread;
    FOk: Boolean;
    FWanted: Integer;
    FGenMs: Double;
    FError: string;
    procedure MakeSfx;
    procedure Publish(I: Integer; const Data: TTrackData);
    function NextNoise: Single; inline;
  public
    constructor Create(OpenDevice: Boolean = True);
    destructor Destroy; override;
    function SfxData(S: TSfx): TSingleArray;
    procedure Fill(Stream: PSDL_AudioStream; Bytes: Integer);
    procedure Play(S: TSfx; Vol: Single = 1; Pan: Single = 0; Pitch: Single = 1);
    procedure PlayMusic(Track: Integer);        // crossfades; -1 fades to silence
    procedure SetVolumes(Music, Sfx: Single);   // 0..1
    procedure SetDuck(Level: Single);           // music level multiplier (pause, game over)
    procedure SetRain(Level: Single);           // rain ambience 0..1
    procedure PlaySongFile(const FileName: string);  // a .pcmusic tune into the custom slot
    procedure LoadOverrides(const Folder: string);   // sounds/<name>.pcsfx replace the built-in effects
    function TrackReady(I: Integer): Boolean;
    function ReadyCount: Integer;
    property Ok: Boolean read FOk;
    property Error: string read FError;
    property Wanted: Integer read FWanted;
    property GenMs: Double read FGenMs;
  end;

var
  Audio: TAudio = nil;

function GenerateTrack(Index: Integer): TTrackData;

implementation

function GenerateTrack(Index: Integer): TTrackData;
var
  Song: TSong;
begin
  Song := BuiltinSong(Index);
  try
    Result := Song.Render(MusicRate);
  finally
    Song.Free;
  end;
end;

{ ====================================================================== }
{ TGenThread: renders the music in the background                         }
{ ====================================================================== }

constructor TGenThread.Create(AAudio: TAudio);
begin
  FAudio := AAudio;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TGenThread.Execute;
var
  I: Integer;
  T0: QWord;
begin
  T0 := GetTickCount64;
  for I := 0 to TrackCount - 1 do
  begin
    if Terminated then Exit;
    FAudio.Publish(I, GenerateTrack(I));
  end;
  FAudio.FGenMs := GetTickCount64 - T0;
end;

{ ====================================================================== }
{ TAudio                                                                  }
{ ====================================================================== }

procedure AudioCallback(userdata: Pointer; stream: PSDL_AudioStream; additional_amount: LongInt;
  total_amount: LongInt); cdecl;
begin
  if additional_amount > 0 then TAudio(userdata).Fill(stream, additional_amount);
end;

constructor TAudio.Create(OpenDevice: Boolean);
var
  Spec: TSDL_AudioSpec;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FMusicVol := 0.7;
  FSfxVol := 0.8;
  FDuck := 1;
  FDuckNow := 1;
  FNoise := 99991;
  FWanted := -1;
  FMus[0].Track := -1;
  FMus[1].Track := -1;
  MakeSfx;
  LoadOverrides(PCRoot + 'sounds' + PathDelim);
  if not OpenDevice then Exit;
  if not SDL_InitSubSystem(SDL_INIT_AUDIO) then
  begin
    FError := 'SDL audio: ' + StrPas(SDL_GetError);
    Exit;
  end;
  Spec.format := SDL_AUDIO_F32;
  Spec.channels := 2;
  Spec.freq := MixRate;
  FStream := SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, @Spec, @AudioCallback, Self);
  if FStream = nil then
  begin
    FError := 'SDL audio stream: ' + StrPas(SDL_GetError);
    Exit;
  end;
  FOk := True;
  SDL_ResumeAudioStreamDevice(FStream);
  FGen := TGenThread.Create(Self);
end;

destructor TAudio.Destroy;
begin
  if FGen <> nil then
  begin
    FGen.Terminate;
    FGen.WaitFor;
    FGen.Free;
  end;
  if FSongThread <> nil then
  begin
    FSongThread.WaitFor;
    FSongThread.Free;
  end;
  if FStream <> nil then SDL_DestroyAudioStream(FStream);  // stops the callback first
  FLock.Free;
  inherited Destroy;
end;

function TAudio.SfxData(S: TSfx): TSingleArray;
begin
  Result := Copy(FSfx[S]);
end;

function TAudio.NextNoise: Single;
begin
  FNoise := FNoise * 1664525 + 1013904223;
  Result := (FNoise shr 8) / 8388608 - 1;
end;

procedure TAudio.Publish(I: Integer; const Data: TTrackData);
var
  K: Integer;
begin
  FLock.Enter;
  try
    FTracks[I] := Data;
    FReady[I] := True;
    for K := 0 to 1 do
      if FMus[K].Track = I then FMus[K].Pos := 0;  // a new tune in a slot that plays
  finally
    FLock.Leave;
  end;
end;

function TAudio.TrackReady(I: Integer): Boolean;
begin
  Result := (I >= 0) and (I < TrackCount) and FReady[I];
end;

function TAudio.ReadyCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to TrackCount - 1 do
    if FReady[I] then Inc(Result);
end;

{ the sound effects, all at MixRate, mono }
procedure TAudio.MakeSfx;
var
  R, I, N: Integer;
  T, V, LP, LP2, F, Ph: Single;
  B: TBufF;

  { every effect is normalised to the same peak; the game sets the loudness }
  procedure Take(S: TSfx);
  var
    K: Integer;
    Pk: Single;
  begin
    Pk := 0.0001;
    for K := 0 to High(B) do Pk := Max(Pk, Abs(B[K]));
    SetLength(FSfx[S], Length(B));
    for K := 0 to High(B) do FSfx[S][K] := B[K] * 0.85 / Pk;
  end;

  procedure New(Secs: Single);
  begin
    SetLength(B, 0);
    SetLength(B, Round(Secs * R));
  end;

begin
  R := MixRate;
  SetSynthSeed(4242);
  // flap: a soft whoosh of paper wings (band-limited noise swelling and fading)
  New(0.22);
  LP := 0;
  LP2 := 0;
  for I := 0 to High(B) do
  begin
    T := I / R;
    F := 0.04 + 0.25 * Sin(Pi * T / 0.22);
    LP := LP + (RndS - LP) * F;
    LP2 := LP2 + (LP - LP2) * F;
    B[I] := (LP - LP2) * 3.2 * Sin(Pi * Min(1, T / 0.22));
  end;
  Take(sfFlap);
  // pass: a woodblock tick
  New(0.12);
  AddWood(B, 0, 1250, 0.6, R);
  Take(sfPass);
  // lantern: a little bell arpeggio (pentatonic)
  New(1.0);
  AddBell(B, 0, NoteHz(84), 0.9, 0.35, R);
  AddBell(B, Round(0.07 * R), NoteHz(88), 0.9, 0.3, R);
  AddBell(B, Round(0.14 * R), NoteHz(91), 0.9, 0.3, R);
  Take(sfLantern);
  // hit: paper tearing (crackling noise) and a dull thud
  New(0.4);
  LP := 0;
  for I := 0 to High(B) do
  begin
    T := I / R;
    V := RndS;
    if Rnd01 < 0.25 then V := V * 2.5;
    LP := LP + (V - LP) * 0.5;
    B[I] := LP * Exp(-T * 9) * 0.6 + Sin(2 * Pi * (90 - 40 * T) * T) * Exp(-T * 14) * 0.8;
  end;
  Take(sfHit);
  // fall: a descending whistle
  New(0.9);
  Ph := 0;
  for I := 0 to High(B) do
  begin
    T := I / R;
    Ph := Ph + 2 * Pi * (950 - 780 * T / 0.9) / R;
    B[I] := Sin(Ph) * 0.35 * Sin(Pi * T / 0.9);
  end;
  Take(sfFall);
  // splash: noise burst, low passed, with a few droplets
  New(0.8);
  LP := 0;
  for I := 0 to High(B) do
  begin
    T := I / R;
    LP := LP + (RndS - LP) * (0.35 - 0.3 * T);
    B[I] := LP * Exp(-T * 5) * 0.9;
  end;
  for N := 0 to 5 do
    AddWood(B, Round((0.15 + N * 0.08) * R), 1500 + Rnd01 * 900, 0.15, R);
  Take(sfSplash);
  // game over: a descending pentatonic pluck phrase
  New(2.4);
  AddPluck(B, 0, NoteHz(81), 1.2, 0.5, 0.997, 0.8, R);
  AddPluck(B, Round(0.25 * R), NoteHz(79), 1.2, 0.5, 0.997, 0.8, R);
  AddPluck(B, Round(0.5 * R), NoteHz(76), 1.2, 0.5, 0.997, 0.8, R);
  AddPluck(B, Round(0.75 * R), NoteHz(74), 1.4, 0.5, 0.997, 0.8, R);
  AddPluck(B, Round(1.1 * R), NoteHz(69), 1.3, 0.6, 0.998, 0.7, R);
  AddPluck(B, Round(1.1 * R), NoteHz(57), 1.3, 0.4, 0.998, 0.6, R);
  Take(sfGameOver);
  // new best: rising bells and a gong
  New(2.6);
  AddBell(B, 0, NoteHz(72), 1.6, 0.25, R);
  AddBell(B, Round(0.12 * R), NoteHz(76), 1.6, 0.25, R);
  AddBell(B, Round(0.24 * R), NoteHz(79), 1.6, 0.25, R);
  AddBell(B, Round(0.36 * R), NoteHz(84), 2.0, 0.3, R);
  AddBell(B, Round(0.36 * R), NoteHz(60), 2.2, 0.25, R);
  Take(sfNewBest);
  // menu: soft plucks
  New(0.35);
  AddPluck(B, 0, NoteHz(76), 0.3, 0.45, 0.994, 0.9, R);
  Take(sfMenuMove);
  New(0.6);
  AddPluck(B, 0, NoteHz(79), 0.5, 0.45, 0.996, 0.9, R);
  AddPluck(B, Round(0.08 * R), NoteHz(84), 0.5, 0.45, 0.996, 0.9, R);
  Take(sfMenuSelect);
  New(0.6);
  AddPluck(B, 0, NoteHz(72), 0.5, 0.45, 0.996, 0.9, R);
  AddPluck(B, Round(0.08 * R), NoteHz(67), 0.5, 0.45, 0.996, 0.9, R);
  Take(sfMenuBack);
  // thunder: brown noise rumble with slow swells
  New(3.2);
  LP := 0;
  LP2 := 0;
  for I := 0 to High(B) do
  begin
    T := I / R;
    LP := LP + (RndS - LP) * 0.02;
    LP2 := LP2 + (LP - LP2) * 0.05;
    B[I] := LP2 * 9 * Min(1, T / 0.05) * Exp(-T * 1.1) * (0.7 + 0.3 * Sin(T * 9 + Sin(T * 3)));
  end;
  Take(sfThunder);
  // start: a gong
  New(3.0);
  for I := 0 to High(B) do
  begin
    T := I / R;
    B[I] := (Sin(2 * Pi * 110 * T) * 0.6 + Sin(2 * Pi * 163 * T) * 0.4 + Sin(2 * Pi * 231 * T) * 0.3 +
      Sin(2 * Pi * 347 * T) * 0.15 * Exp(-T * 3)) * Exp(-T * 1.2) * Min(1, T / 0.01) * 0.6 +
      RndS * 0.3 * Exp(-T * 40);
  end;
  Take(sfStart);
end;

type
  TSongThread = class(TThread)
  private
    FAudio: TAudio;
    FFile: string;
  protected
    procedure Execute; override;
  end;

procedure TSongThread.Execute;
var
  Song: TSong;
begin
  Song := TSong.Create;
  try
    try
      Song.LoadFromFile(FFile);
      FAudio.Publish(TrackCount, Song.Render(MusicRate));
    except
    end;
  finally
    Song.Free;
  end;
end;

procedure TAudio.PlaySongFile(const FileName: string);
var
  T: TSongThread;
begin
  if not FOk then Exit;
  if FSongThread <> nil then
  begin
    FSongThread.WaitFor;
    FreeAndNil(FSongThread);
  end;
  FLock.Enter;
  try
    FReady[TrackCount] := False;
  finally
    FLock.Leave;
  end;
  T := TSongThread.Create(True);
  T.FAudio := Self;
  T.FFile := FileName;
  FSongThread := T;
  T.Start;
end;

procedure TAudio.LoadOverrides(const Folder: string);
var
  S: TSfx;
  F: string;
  B: TBufF;
  K: Integer;
begin
  for S := Low(TSfx) to High(TSfx) do
  begin
    F := Folder + StringReplace(SfxNames[S], ' ', '_', [rfReplaceAll]) + '.pcsfx';
    if not FileExists(F) then Continue;
    try
      B := RenderSfx(LoadSfx(F), MixRate);
      if FLock <> nil then FLock.Enter;
      try
        SetLength(FSfx[S], Length(B));
        for K := 0 to High(B) do FSfx[S][K] := B[K];
      finally
        if FLock <> nil then FLock.Leave;
      end;
    except
    end;
  end;
end;

procedure TAudio.Play(S: TSfx; Vol: Single; Pan: Single; Pitch: Single);
var
  I, Best: Integer;
begin
  if not FOk then Exit;
  FLock.Enter;
  try
    Best := -1;
    for I := 0 to High(FVoices) do
      if not FVoices[I].Active then
      begin
        Best := I;
        Break;
      end;
    if Best < 0 then  // steal the voice that is furthest through its sound
    begin
      Best := 0;
      for I := 1 to High(FVoices) do
        if FVoices[I].Pos / Max(1, Length(FSfx[FVoices[I].Snd])) >
           FVoices[Best].Pos / Max(1, Length(FSfx[FVoices[Best].Snd])) then Best := I;
    end;
    FVoices[Best].Snd := S;
    FVoices[Best].Pos := 0;
    FVoices[Best].Step := Pitch;
    FVoices[Best].Vol := Vol;
    FVoices[Best].PanL := Min(1, 1 - Pan) * Vol;
    FVoices[Best].PanR := Min(1, 1 + Pan) * Vol;
    FVoices[Best].Active := True;
  finally
    FLock.Leave;
  end;
end;

procedure TAudio.PlayMusic(Track: Integer);
begin
  if not FOk then Exit;
  FLock.Enter;
  try
    FWanted := Track;
  finally
    FLock.Leave;
  end;
end;

procedure TAudio.SetVolumes(Music, Sfx: Single);
begin
  FMusicVol := EnsureRange(Music, 0, 1);
  FSfxVol := EnsureRange(Sfx, 0, 1);
end;

procedure TAudio.SetDuck(Level: Single);
begin
  FDuck := EnsureRange(Level, 0, 1);
end;

procedure TAudio.SetRain(Level: Single);
begin
  FRain := EnsureRange(Level, 0, 1);
end;

{ audio thread: mix everything for Bytes of output }
procedure TAudio.Fill(Stream: PSDL_AudioStream; Bytes: Integer);
var
  Frames, I, K, P0, Len, N: Integer;
  F, S, Fade, MV, SV, Lv, Rv, A, Rn: Single;
  Data: TTrackData;
begin
  Frames := Bytes div 8;
  if Frames <= 0 then Exit;
  if Length(FBuf) < Frames * 2 then SetLength(FBuf, Frames * 2);
  FillChar(FBuf[0], Frames * 2 * SizeOf(Single), 0);
  Fade := 1 / (1.6 * MixRate);
  FLock.Enter;
  try
    // a new wanted track: the free player takes it, the other fades out
    if FWanted <> FMus[0].Track then
    begin
      if FMus[0].Target > 0 then
      begin
        FMus[1] := FMus[0];
        FMus[1].Target := 0;
      end;
      FMus[0].Track := FWanted;
      FMus[0].Pos := 0;
      FMus[0].Gain := 0;
      FMus[0].Target := 1;
    end;
    MV := FMusicVol * FMusicVol;
    SV := FSfxVol * FSfxVol;
    for K := 0 to 1 do
      with FMus[K] do
      begin
        if (Track < 0) or not FReady[Track] then Continue;
        Data := FTracks[Track];
        Len := Length(Data) div 2;
        if Len < 2 then Continue;
        for I := 0 to Frames - 1 do
        begin
          if Gain < Target then Gain := Min(Target, Gain + Fade)
          else if Gain > Target then Gain := Max(Target, Gain - Fade);
          FDuckNow := FDuckNow + (FDuck - FDuckNow) * 0.00005;
          P0 := Trunc(Pos);
          F := Pos - P0;
          N := (P0 + 1) mod Len;
          A := Gain * MV * FDuckNow / 32768;
          FBuf[I * 2] := FBuf[I * 2] + (Data[P0 * 2] * (1 - F) + Data[N * 2] * F) * A;
          FBuf[I * 2 + 1] := FBuf[I * 2 + 1] + (Data[P0 * 2 + 1] * (1 - F) + Data[N * 2 + 1] * F) * A;
          Pos := Pos + MusicRate / MixRate;
          if Pos >= Len then Pos := Pos - Len;
        end;
        if (Target = 0) and (Gain = 0) then Track := -1;
      end;
    // effects
    for K := 0 to High(FVoices) do
      with FVoices[K] do
      begin
        if not Active then Continue;
        Len := Length(FSfx[Snd]);
        for I := 0 to Frames - 1 do
        begin
          P0 := Trunc(Pos);
          if P0 >= Len - 1 then
          begin
            Active := False;
            Break;
          end;
          F := Pos - P0;
          S := (FSfx[Snd][P0] * (1 - F) + FSfx[Snd][P0 + 1] * F) * SV;
          FBuf[I * 2] := FBuf[I * 2] + S * PanL;
          FBuf[I * 2 + 1] := FBuf[I * 2 + 1] + S * PanR;
          Pos := Pos + Step;
        end;
      end;
    // rain: two low-passed noise layers, the ambience follows the scene
    for I := 0 to Frames - 1 do
    begin
      FRainNow := FRainNow + (FRain - FRainNow) * 0.00002;
      if FRainNow < 0.002 then Continue;
      Rn := NextNoise;
      FRainLP1 := FRainLP1 + (Rn - FRainLP1) * 0.35;
      FRainLP2 := FRainLP2 + (FRainLP1 - FRainLP2) * 0.08;
      Lv := (FRainLP1 - FRainLP2) * 0.22 * FRainNow * SV;
      FBuf[I * 2] := FBuf[I * 2] + Lv;
      FBuf[I * 2 + 1] := FBuf[I * 2 + 1] + Lv * 0.9 + FRainLP2 * 0.05 * FRainNow * SV;
    end;
  finally
    FLock.Leave;
  end;
  // soft clip
  for I := 0 to Frames * 2 - 1 do
  begin
    Rv := FBuf[I];
    if Rv > 0.8 then FBuf[I] := 0.8 + (Rv - 0.8) / (1 + Sqr((Rv - 0.8) / 0.2))
    else if Rv < -0.8 then FBuf[I] := -0.8 + (Rv + 0.8) / (1 + Sqr((Rv + 0.8) / 0.2));
  end;
  SDL_PutAudioStreamData(Stream, @FBuf[0], Frames * 8);
end;

end.
