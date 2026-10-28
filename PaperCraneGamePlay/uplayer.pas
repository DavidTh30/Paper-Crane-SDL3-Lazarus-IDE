unit uPlayer;

{ Paper Crane players: a name, the chosen character and the statistics of all
  the player's flights, kept in players\<name>.pcplayer next to the game.

  File (text, one key per line):
    PCPLAYER 1
    name= character= created= last=
    games= wins= deaths= time=          (flights, maps completed, lives lost, seconds)
    distance= best_distance= score= best_score=
    lanterns= best_lanterns= hearts= slows= best_bonus= passed=
    map=name;plays;best_m;best_score;best_bonus;best_lanterns;completed;last
  "Random map" is kept as a map of its own. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

const
  CharCount = 5;
  CharNames: array[0..CharCount - 1] of string = ('Paper Crane', 'Paper Dragon', 'Winged Panda Bike', 'Night Owl',
    'Phoenix');
  CharInfo: array[0..CharCount - 1] of string = ('folded white crane with a red crown',
    'red and gold dragon, its body waves', 'a panda pedalling a bicycle with paper wings',
    'a brown owl with big golden eyes', 'a fire bird with a long flowing tail');
  RandomMapName = 'Random map';

type
  TMapStat = record
    Name: string;
    Plays, BestDist, BestScore, BestBonus, BestLanterns, Completed: Integer;
    Last: string;
  end;

  { one flight, handed to TPCPlayer.Record }
  TFlight = record
    MapName: string;
    Dist, Score, Lanterns, Hearts, Slows, Passed, LivesLost: Integer;
    Seconds: Double;
    Won: Boolean;
  end;

  { TPCPlayer }

  TPCPlayer = class
  public
    Name, Created, Last, FileName: string;
    Character: Integer;
    Games, Wins, Deaths: Integer;
    Seconds: Double;
    Distance, Score: Int64;
    BestDist, BestScore, Lanterns, BestLanterns, Hearts, Slows, BestBonus, Passed: Integer;
    Maps: array of TMapStat;
    constructor Create(const AName: string);
    function MapIndex(const AMap: string; Add: Boolean): Integer;
    procedure RecordFlight(const F: TFlight);
    procedure SaveToFile(const AFile: string);
    procedure LoadFromFile(const AFile: string);
    function Summary: string;
  end;

function PlayerFolder(const Root: string): string;
function PlayerFileName(const Root, AName: string): string;
function ValidPlayerName(const AName: string): Boolean;
function FormatPlayTime(Sec: Double): string;

implementation

function PlayerFolder(const Root: string): string;
begin
  Result := IncludeTrailingPathDelimiter(Root) + 'players' + PathDelim;
end;

{ letters, digits and a few signs make the file name; the real name stays inside }
function PlayerFileName(const Root, AName: string): string;
var
  I: Integer;
  S: string;
begin
  S := '';
  for I := 1 to Length(AName) do
    if AName[I] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_'] then S := S + AName[I]
    else if AName[I] = ' ' then S := S + '_'
    else if Ord(AName[I]) >= 128 then S := S + LowerCase(IntToHex(Ord(AName[I]), 2));
  if S = '' then S := 'player';
  Result := PlayerFolder(Root) + S + '.pcplayer';
end;

function ValidPlayerName(const AName: string): Boolean;
begin
  Result := (Trim(AName) <> '') and (Length(AName) <= 40);
end;

function FormatPlayTime(Sec: Double): string;
var
  S: Integer;
begin
  S := Round(Sec);
  if S >= 3600 then Result := Format('%d h %d min', [S div 3600, (S mod 3600) div 60])
  else Result := Format('%d min %d s', [S div 60, S mod 60]);
end;

constructor TPCPlayer.Create(const AName: string);
begin
  inherited Create;
  Name := AName;
  Created := FormatDateTime('yyyy-mm-dd', Now);
  Last := Created;
end;

function TPCPlayer.MapIndex(const AMap: string; Add: Boolean): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Maps) do
    if SameText(Maps[I].Name, AMap) then Exit(I);
  Result := -1;
  if not Add then Exit;
  SetLength(Maps, Length(Maps) + 1);
  Result := High(Maps);
  Maps[Result] := Default(TMapStat);
  Maps[Result].Name := AMap;
end;

procedure TPCPlayer.RecordFlight(const F: TFlight);
var
  I, Bonus: Integer;
begin
  Last := FormatDateTime('yyyy-mm-dd hh:nn', Now);
  Inc(Games);
  if F.Won then Inc(Wins);
  Inc(Deaths, F.LivesLost);
  Seconds := Seconds + F.Seconds;
  Distance := Distance + F.Dist;
  Score := Score + F.Score;
  BestDist := Max(BestDist, F.Dist);
  BestScore := Max(BestScore, F.Score);
  Inc(Lanterns, F.Lanterns);
  BestLanterns := Max(BestLanterns, F.Lanterns);
  Inc(Hearts, F.Hearts);
  Inc(Slows, F.Slows);
  Bonus := F.Hearts + F.Slows;
  BestBonus := Max(BestBonus, Bonus);
  Inc(Passed, F.Passed);
  I := MapIndex(F.MapName, True);
  Inc(Maps[I].Plays);
  Maps[I].BestDist := Max(Maps[I].BestDist, F.Dist);
  Maps[I].BestScore := Max(Maps[I].BestScore, F.Score);
  Maps[I].BestBonus := Max(Maps[I].BestBonus, Bonus);
  Maps[I].BestLanterns := Max(Maps[I].BestLanterns, F.Lanterns);
  if F.Won then Inc(Maps[I].Completed);
  Maps[I].Last := FormatDateTime('yyyy-mm-dd', Now);
end;

procedure TPCPlayer.SaveToFile(const AFile: string);
var
  SL: TStringList;
  I: Integer;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SL := TStringList.Create;
  try
    SL.Add('PCPLAYER 1');
    SL.Add('name=' + Name);
    SL.Add('character=' + IntToStr(Character));
    SL.Add('created=' + Created);
    SL.Add('last=' + Last);
    SL.Add('games=' + IntToStr(Games));
    SL.Add('wins=' + IntToStr(Wins));
    SL.Add('deaths=' + IntToStr(Deaths));
    SL.Add('time=' + FloatToStrF(Seconds, ffFixed, 12, 1, FS));
    SL.Add('distance=' + IntToStr(Distance));
    SL.Add('best_distance=' + IntToStr(BestDist));
    SL.Add('score=' + IntToStr(Score));
    SL.Add('best_score=' + IntToStr(BestScore));
    SL.Add('lanterns=' + IntToStr(Lanterns));
    SL.Add('best_lanterns=' + IntToStr(BestLanterns));
    SL.Add('hearts=' + IntToStr(Hearts));
    SL.Add('slows=' + IntToStr(Slows));
    SL.Add('best_bonus=' + IntToStr(BestBonus));
    SL.Add('passed=' + IntToStr(Passed));
    for I := 0 to High(Maps) do
      with Maps[I] do
        SL.Add(Format('map=%s;%d;%d;%d;%d;%d;%d;%s', [StringReplace(Name, ';', ',', [rfReplaceAll]), Plays, BestDist,
          BestScore, BestBonus, BestLanterns, Completed, Last]));
    ForceDirectories(ExtractFilePath(AFile));
    SL.SaveToFile(AFile);
    FileName := AFile;
  finally
    SL.Free;
  end;
end;

procedure TPCPlayer.LoadFromFile(const AFile: string);
var
  SL, P: TStringList;
  I, K: Integer;
  Key, V: string;
  FS: TFormatSettings;

  function N(Idx: Integer): Integer;
  begin
    if Idx < P.Count then Result := StrToIntDef(P[Idx], 0) else Result := 0;
  end;

begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SL := TStringList.Create;
  P := TStringList.Create;
  try
    P.Delimiter := ';';
    P.StrictDelimiter := True;
    SL.LoadFromFile(AFile);
    if (SL.Count = 0) or (Copy(SL[0], 1, 8) <> 'PCPLAYER') then
      raise Exception.Create('not a Paper Crane player: ' + AFile);
    SetLength(Maps, 0);
    FileName := AFile;
    for I := 1 to SL.Count - 1 do
    begin
      Key := SL.Names[I];
      V := SL.ValueFromIndex[I];
      if Key = 'name' then Name := V
      else if Key = 'character' then Character := EnsureRange(StrToIntDef(V, 0), 0, CharCount - 1)
      else if Key = 'created' then Created := V
      else if Key = 'last' then Last := V
      else if Key = 'games' then Games := StrToIntDef(V, 0)
      else if Key = 'wins' then Wins := StrToIntDef(V, 0)
      else if Key = 'deaths' then Deaths := StrToIntDef(V, 0)
      else if Key = 'time' then Seconds := StrToFloatDef(V, 0, FS)
      else if Key = 'distance' then Distance := StrToInt64Def(V, 0)
      else if Key = 'best_distance' then BestDist := StrToIntDef(V, 0)
      else if Key = 'score' then Score := StrToInt64Def(V, 0)
      else if Key = 'best_score' then BestScore := StrToIntDef(V, 0)
      else if Key = 'lanterns' then Lanterns := StrToIntDef(V, 0)
      else if Key = 'best_lanterns' then BestLanterns := StrToIntDef(V, 0)
      else if Key = 'hearts' then Hearts := StrToIntDef(V, 0)
      else if Key = 'slows' then Slows := StrToIntDef(V, 0)
      else if Key = 'best_bonus' then BestBonus := StrToIntDef(V, 0)
      else if Key = 'passed' then Passed := StrToIntDef(V, 0)
      else if Key = 'map' then
      begin
        P.DelimitedText := V;
        if P.Count = 0 then Continue;
        K := MapIndex(P[0], True);
        Maps[K].Plays := N(1);
        Maps[K].BestDist := N(2);
        Maps[K].BestScore := N(3);
        Maps[K].BestBonus := N(4);
        Maps[K].BestLanterns := N(5);
        Maps[K].Completed := N(6);
        if P.Count > 7 then Maps[K].Last := P[7];
      end;
    end;
  finally
    P.Free;
    SL.Free;
  end;
end;

function TPCPlayer.Summary: string;
begin
  Result := Format('%s - %s, %d flights, best %d m', [Name, CharNames[Character], Games, BestDist]);
end;

end.
