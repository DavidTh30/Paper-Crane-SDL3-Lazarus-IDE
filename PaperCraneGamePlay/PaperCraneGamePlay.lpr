program PaperCraneGamePlay;

{ Paper Crane - GamePlay edition: the papercut flying game alone, tuned for
  speed. The same game as "Paper Crane Papercut Game SDL3" without the
  Developer info window (and its export / timing tools): only the SDL3 game
  window, rendered from the LCL idle loop on all CPU cores.
  ugamescene.pas      scene state, static resources (3 palettes), band painter
  urenderpool.pas     worker thread pool (all threads created once)
  uframerenderer.pas  splits a frame into adaptive bands, renders them on the pool
  usdlview.pas        SDL3 window, streaming texture, vsync'ed render loop
  usvgrecorder.pas    SVG writer used by the painters in vector mode
  Needs SDL3.dll next to the program.

  Command line
    --bench=SECONDS                 frame pacing in the real window, writes
                                    PaperCraneGamePlay-bench.txt and quits
    --mode=morning|day|night|auto   start with that time of day
    --season=summer|rainy|autumn|winter  start with that season
    --map file.pcmap                fly a custom map
    --wav folder                    every tune and sound effect as WAV files
    --novsync                       start with vsync off (V toggles)
    --cpubench out.png [w h [mode [season]]]  no window: render speed for 1..all threads }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Classes, Forms, SysUtils, Math, BGRABitmap, uRenderPool, uGameScene, uFrameRenderer,
  uSvgRecorder, uAudio, uSDLView;


procedure Bench;
const
  Frames = 60;
var
  Scene: TGameScene;
  R: TFrameRenderer;
  Out: TBGRABitmap;
  Log: TStringList;
  Counts: array of Integer;
  I, J, N: Integer;
  T0, Wall, Cpu, Base: Double;
  Layers: string;
  Id: TLayerId;
begin
  Scene := TGameScene.Create;
  R := TFrameRenderer.Create(Scene, TThread.ProcessorCount, 1);
  Out := TBGRABitmap.Create(1, 1);
  Log := TStringList.Create;
  try
    T0 := HiResMs;
    Scene.SetModeInstant(StrToIntDef(ParamStr(5), 2));
    Scene.SetSeason(StrToIntDef(ParamStr(6), 0), False);  // applied by the first Prepare
    Scene.Prepare;
    R.SetSize(StrToIntDef(ParamStr(3), 1024), StrToIntDef(ParamStr(4), 576));
    Log.Add(Format('size %d x %d, %d logical cores, %d physical cores', [R.Width, R.Height,
      TThread.ProcessorCount, PhysicalCores]));
    Log.Add(Format('static cut %.1f ms (main thread) + sprites %.1f ms (%d sprites, all cores)',
      [Scene.StaticMs, R.SpriteMs, Scene.SpriteCount]));
    for I := 1 to 300 do
      Scene.Update(1 / 60);
    Log.Add('');
    Log.Add('threads  bands  wall ms/frame  cpu ms/frame  speed-up  fps limit');
    Counts := [1, 2, 4, PhysicalCores, 8, TThread.ProcessorCount];
    Base := 0;
    for J := 0 to High(Counts) do
    begin
      N := Counts[J];
      if (J > 0) and (N <= Counts[J - 1]) then Continue;
      R.SetThreads(N);
      Scene.Prepare;
      for I := 1 to 100 do  // warm-up: layer buffers, adaptive band borders
      begin
        Scene.Update(1 / 60);
        Scene.Prepare;
        R.Render;
      end;
      Wall := 0;
      Cpu := 0;
      T0 := HiResMs;
      for I := 1 to Frames do
      begin
        Scene.Update(1 / 60);
        Scene.Prepare;
        R.Render;
        Cpu := Cpu + R.RenderCpuMs;
      end;
      Wall := (HiResMs - T0) / Frames;
      Cpu := Cpu / Frames;
      if Base = 0 then Base := Wall;
      Log.Add(Format('%7d  %5d  %13.2f  %12.2f  %8.2f  %9.0f',
        [N, R.BandCount, Wall, Cpu, Base / Wall, 1000 / Wall]));
      Layers := '        cpu per layer:';
      for Id := Low(TLayerId) to High(TLayerId) do
        Layers := Layers + Format(' %s %.1f', [Copy(LayerNames[Id], 1, 6), R.LayerCpuMs[Id]]);
      Log.Add(Layers);
      Log.SaveToFile(ChangeFileExt(ParamStr(2), '.txt'));
    end;
    // bands per thread at full thread count
    Log.Add('');
    Log.Add('bands/thread  bands  wall ms/frame  cpu ms/frame');
    R.SetThreads(PhysicalCores);
    for J := 1 to 4 do
    begin
      R.SetBandsPerThread(J);
      for I := 1 to 100 do
      begin
        Scene.Update(1 / 60);
        Scene.Prepare;
        R.Render;
      end;
      Cpu := 0;
      T0 := HiResMs;
      for I := 1 to Frames do
      begin
        Scene.Update(1 / 60);
        Scene.Prepare;
        R.Render;
        Cpu := Cpu + R.RenderCpuMs;
      end;
      Log.Add(Format('%12d  %5d  %13.2f  %12.2f', [J, R.BandCount, (HiResMs - T0) / Frames,
        Cpu / Frames]));
    end;
    R.SetBandsPerThread(1);
    Log.Add('');
    Log.Add('adaptive  wall ms/frame  cpu ms/frame');
    for J := 0 to 1 do
    begin
      R.Adaptive := J = 1;
      R.SetBandsPerThread(2);
      R.SetBandsPerThread(1);  // fresh equal bands
      for I := 1 to 100 do
      begin
        Scene.Update(1 / 60);
        Scene.Prepare;
        R.Render;
      end;
      Cpu := 0;
      T0 := HiResMs;
      for I := 1 to Frames do
      begin
        Scene.Update(1 / 60);
        Scene.Prepare;
        R.Render;
        Cpu := Cpu + R.RenderCpuMs;
      end;
      Log.Add(Format('%8s  %13.2f  %12.2f', [BoolToStr(R.Adaptive, 'on', 'off'),
        (HiResMs - T0) / Frames, Cpu / Frames]));
    end;
    Scene.Prepare;
    R.Render;  // the band rebuild above left empty bands
    Log.Add('');
    Log.Add(Format('job exceptions: %d', [R.Pool.ErrorCount]));
    Log.Add(R.Pool.ErrorReport);
    R.Assemble(Out);
    Out.SaveToFile(ParamStr(2));
    Log.SaveToFile(ChangeFileExt(ParamStr(2), '.txt'));
  finally
    Log.Free;
    Out.Free;
    R.Free;
    Scene.Free;
  end;
end;

{ --wav folder: every tune and every sound effect as a WAV file }
procedure ExportWav;
var
  Dir: string;
  I, K: Integer;
  T: TTrackData;
  A: TAudio;
  S: TSfx;
  D: TSingleArray;
  Log: TStringList;

  procedure WriteWav(const FileName: string; const Data: array of SmallInt; Channels, Rate: Integer);
  var
    F: TFileStream;
    N, V: LongWord;
    W: Word;
  begin
    F := TFileStream.Create(FileName, fmCreate);
    try
      N := Length(Data) * 2;
      F.WriteBuffer(PChar('RIFF')^, 4); V := 36 + N; F.WriteBuffer(V, 4);
      F.WriteBuffer(PChar('WAVEfmt ')^, 8); V := 16; F.WriteBuffer(V, 4);
      W := 1; F.WriteBuffer(W, 2); W := Channels; F.WriteBuffer(W, 2);
      V := Rate; F.WriteBuffer(V, 4); V := Rate * Channels * 2; F.WriteBuffer(V, 4);
      W := Channels * 2; F.WriteBuffer(W, 2); W := 16; F.WriteBuffer(W, 2);
      F.WriteBuffer(PChar('data')^, 4); F.WriteBuffer(N, 4);
      if Length(Data) > 0 then F.WriteBuffer(Data[0], N);
    finally
      F.Free;
    end;
  end;

var
  M: array of SmallInt;
begin
  Dir := IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(2)));
  ForceDirectories(Dir);
  Log := TStringList.Create;
  try
    for I := 0 to TrackCount - 1 do
    begin
      T := GenerateTrack(I);
      WriteWav(Dir + Format('music_%d_%s.wav', [I + 1, StringReplace(LowerCase(TrackNames[I]), ' ', '_', [rfReplaceAll])]),
        T, 2, MusicRate);
      Log.Add(Format('music %d %s: %.1f s', [I + 1, TrackNames[I], Length(T) / 2 / MusicRate]));
    end;
    A := TAudio.Create(False);
    try
      for S := Low(TSfx) to High(TSfx) do
      begin
        D := A.SfxData(S);
        SetLength(M, Length(D));
        for K := 0 to High(D) do M[K] := Round(EnsureRange(D[K], -1, 1) * 32000);
        WriteWav(Dir + 'sfx_' + StringReplace(SfxNames[S], ' ', '_', [rfReplaceAll]) + '.wav', M, 1, MixRate);
        Log.Add(Format('sfx %s: %.2f s', [SfxNames[S], Length(D) / MixRate]));
      end;
    finally
      A.Free;
    end;
    Log.SaveToFile(Dir + 'sounds.txt');
  finally
    Log.Free;
  end;
end;

begin
  if (ParamCount >= 2) and (ParamStr(1) = '--wav') then
  begin
    ExportWav;
    Exit;
  end;
  if (ParamCount >= 2) and (ParamStr(1) = '--cpubench') then
  begin
    Bench;
    Exit;
  end;
  RequireDerivedFormResource := False;  // forms are built in code
  Application.Scaled := True;
  Application.Title := 'Paper Crane';
  Application.Initialize;
  try
    View := TSDLView.Create;
  except
    on E: Exception do
    begin
      Application.MessageBox(PChar(E.Message), 'Paper Crane', 0);
      Exit;
    end;
  end;
  // no LCL window: the loop only drives the SDL window (closing it ends the game)
  Application.Run;
  FreeAndNil(View);
end.
