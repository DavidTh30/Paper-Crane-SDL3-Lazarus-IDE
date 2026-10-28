program SoundEditor;

{ Paper Crane Sound Editor - design the game's sound effects (no SDL, no sound
  files): synth parameters, waveform, play, .pcsfx files, WAV export, install
  into the game.  SoundEditor.exe [file.pcsfx] }

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, SysUtils, uSynth, uSoundMain;

{$R *.res}

begin
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Title := 'Paper Crane Sound Editor';
  Application.Initialize;
  Application.CreateForm(TSoundForm, SoundForm);
  if (ParamCount >= 1) and FileExists(ParamStr(1)) then SoundForm.OpenFile(ParamStr(1));
  Application.Run;
end.
