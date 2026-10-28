program ShapeEditor;

{ Paper Crane Shape Editor - draw cut-paper shapes (polygons with colour and
  lift) for the custom maps: decorations or solid obstacles.
  ShapeEditor.exe [file.pcshape]   ShapeEditor.exe --png file.pcshape out.png }

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, SysUtils, uPCShape, uShapeMain;

{$R *.res}

begin
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Title := 'Paper Crane Shape Editor';
  Application.Initialize;
  Application.CreateForm(TShapeForm, ShapeForm);
  if (ParamCount >= 3) and (ParamStr(1) = '--png') then
  begin
    ShapeForm.OpenFile(ParamStr(2));
    ShapeForm.SavePngTo(ParamStr(3));
    Exit;
  end;
  if (ParamCount >= 1) and FileExists(ParamStr(1)) then ShapeForm.OpenFile(ParamStr(1));
  Application.Run;
end.
