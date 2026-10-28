program MenuFxEditor;

{ Paper Crane Menu FX Editor - frames, frame effects and letter effects of
  every menu of the game (.pcmenufx).
  MenuFxEditor.exe [file.pcmenufx] [--shot=N:out.png]   (N = the menu, 0 main) }

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, SysUtils, uPCMenuFx, uFxMain;

{$R *.res}

var
  I, P: Integer;
  A: string;
begin
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Title := 'Paper Crane Menu FX Editor';
  Application.Initialize;
  Application.CreateForm(TFxForm, FxForm);
  for I := 1 to ParamCount do
    if FileExists(ParamStr(I)) then FxForm.OpenFile(ParamStr(I));
  for I := 1 to ParamCount do
  begin
    A := ParamStr(I);
    if Pos('--shot=', A) = 1 then
    begin
      Delete(A, 1, 7);
      P := Pos(':', A);
      FxForm.Show;
      Application.ProcessMessages;
      FxForm.Menu := StrToIntDef(Copy(A, 1, P - 1), 0);
      FxForm.SavePreview(Copy(A, P + 1, MaxInt), 1.7);
      Exit;
    end;
  end;
  Application.Run;
end.
