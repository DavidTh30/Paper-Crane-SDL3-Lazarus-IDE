program MapEditor;

{ Paper Crane Custom Map Editor (LCL, no SDL3) - a side view of the river.
  MapEditor.exe [file.pcmap]   MapEditor.exe --png file.pcmap out.png }

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, SysUtils, uPCMap, uPCShape, uMapMain;

{$R *.res}

begin
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Title := 'Paper Crane Map Editor';
  Application.Initialize;
  Application.CreateForm(TMapForm, MapForm);
  if (ParamCount >= 3) and (ParamStr(1) = '--png') then
  begin
    MapForm.OpenFile(ParamStr(2));
    MapForm.ExportPng(ParamStr(3));
    Exit;
  end;
  if (ParamCount >= 1) and FileExists(ParamStr(1)) then MapForm.OpenFile(ParamStr(1));
  Application.Run;
end.
