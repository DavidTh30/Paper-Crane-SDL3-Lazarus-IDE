program MapEditorSDL;

{ Paper Crane Map Editor 1 (SDL3): the custom map is edited on the live
  papercut river drawn by the game's own scene (SDL3 window, all cores), with
  an LCL panel beside it for the map settings, the object properties, the
  object list and the files.
  MapEditorSDL.exe [file.pcmap] [--shot=frame.png] }

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, SysUtils, uPCMap, uPCShape, uSynth, uRenderPool, uGameScene, uFrameRenderer, uAudio,
  uMapMain, uEdView;

{$R *.res}

var
  I: Integer;
  GameDir: string;
begin
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Title := 'Paper Crane Map Editor (SDL3)';
  // the game's data folders (shapes, music, sounds, settings) are used, not our own
  GameDir := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'Paper Crane Papercut Game SDL3');
  if DirectoryExists(GameDir) then PCDataRoot := GameDir;
  Application.Initialize;
  Application.CreateForm(TMapForm, MapForm);
  MapForm.Width := MapForm.Scale96ToForm(1180);
  MapForm.Height := MapForm.Scale96ToForm(660);
  MapForm.Position := poDesigned;
  MapForm.SetBounds(30, Screen.WorkAreaRect.Bottom - MapForm.Height - 40, MapForm.Width, MapForm.Height);
  for I := 1 to ParamCount do
    if FileExists(ParamStr(I)) then MapForm.OpenFile(ParamStr(I));
  MapForm.Show;
  EdView := TEdView.Create(MapForm);
  for I := 1 to ParamCount do
    if Pos('--shot=', ParamStr(I)) = 1 then EdView.ShotFile := ExpandFileName(Copy(ParamStr(I), 8, MaxInt));
  try
    Application.Run;
  finally
    FreeAndNil(EdView);
  end;
end.
