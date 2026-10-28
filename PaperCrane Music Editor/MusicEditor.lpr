program MusicEditor;

{ Paper Crane Music Editor - write tunes for the game on a piano roll with the
  game's synthesised Chinese instruments (no SDL): tracks, notes, tempo, scale,
  play, .pcmusic files, WAV export, import the game's 7 tunes.
  MusicEditor.exe [file.pcmusic] }

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, SysUtils, uSynth, uMusicMain;

{$R *.res}

begin
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Title := 'Paper Crane Music Editor';
  Application.Initialize;
  Application.CreateForm(TMusicForm, MusicForm);
  if (ParamCount >= 1) and FileExists(ParamStr(1)) then MusicForm.OpenFile(ParamStr(1));
  Application.Run;
end.
