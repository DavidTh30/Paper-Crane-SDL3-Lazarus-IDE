unit uPCMap;

{ Paper Crane maps (.pcmap), shared by the game and both map editors.

  A map is a flight along the river. Distances D are design pixels from the
  start (the crane flies at 10 design px per metre); Y is the height in the
  1600 x 900 design picture (0 top, WaterY the river). Objects:
    pillar   a stone pillar from the river and / or a rock from the sky with a
             gap at GapY of height Gap; W is the half width
    lantern  a red lantern to collect (+5)
    hawk     a hawk that flies against the crane once it is near
    shape    a paper shape from the shapes folder (.pcshape), decoration or
             solid, scaled and maybe mirrored
    heart    a bonus: one more life (up to MaxHearts)
    slow     a bonus: the river slows down for a few seconds
    swing    a pillar whose gap swings up and down by Amp as the crane nears
    bamboo   a grove of bamboo from the river up to Y, W the half width
    cloud    a storm cloud at Y, radius W, drifting up and down by Amp
    pinwheel a turning paper pinwheel at Y, blade length W
    koi      a koi that leaps from the river up to Y as the crane comes
  The moving obstacles move with the distance flown, never with the clock, so
  a flight can always be saved, replayed and raced (SwingOffset etc.).
  The map sets its name, author, description, season (-1: the player's),
  time of day (-1: auto cycle), speed at the start and at the end, the length
  (the finish line), lives (0: by difficulty) and the music (auto, a built-in
  tune or a .pcmusic file).

  TPCRandomGen is the endless random map of the game: every obstacle comes
  from its own random numbers and the distance only, so the same seed always
  gives the same river (saved games and ghosts rely on it). The editors use it
  to fill a stretch with random obstacles. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types;

const
  MapDesignW = 1600;
  MapDesignH = 900;
  MapWaterY = 826;
  MapCraneX = 360;
  MapPxPerMetre = 10;

type
  TMapObjKind = (okPillar, okLantern, okHawk, okShape, okHeart, okSlow, okSwing, okBamboo, okCloud, okPinwheel,
    okKoi);

const
  MapObjIds: array[TMapObjKind] of string = ('pillar', 'lantern', 'hawk', 'shape', 'heart', 'slow', 'swing',
    'bamboo', 'cloud', 'pinwheel', 'koi');
  MapObjNames: array[TMapObjKind] of string = ('Stone pillar / rock', 'Lantern', 'Hawk', 'Paper shape',
    'Heart (bonus life)', 'Slow-down (bonus)', 'Swinging pillar', 'Bamboo grove', 'Storm cloud', 'Pinwheel',
    'Leaping koi');
  MapThemeCount = 6;
  MapThemeNames: array[0..MapThemeCount - 1] of string = ('Karst River', 'Great Wall', 'Pagoda Town',
    'Rice Terraces', 'Bamboo Forest', 'Yellow Mountains');
  MaxHearts = 6;          // lives can grow up to this with heart bonuses
  SlowSeconds = 6;        // how long a slow-down bonus lasts
  SlowFactor = 0.6;       // the river speed while it lasts

type
  TMapObj = record
    Kind: TMapObjKind;
    D, Y: Single;              // distance, height (lantern, hawk, shape anchor)
    W, GapY, Gap: Single;      // pillar
    Top, Bottom: Boolean;      // pillar parts
    Shape: string;             // shape file name (in the shapes folder)
    Scale: Single;
    Solid, Flip: Boolean;
    Amp: Single;               // swing / cloud: how far it moves up and down
  end;
  TMapObjArray = array of TMapObj;

  { TPCMap }

  TPCMap = class
  public
    Name, Author, Description, Music, FileName: string;
    Season, TimeOfDay, Lives: Integer;
    Theme: Integer;            // background (MapThemeNames), -1 the player's setting
    SpeedStart, SpeedEnd, Length_: Single;
    Objs: TMapObjArray;
    constructor Create;
    procedure Clear;
    procedure Assign(Src: TPCMap);
    function Add(const O: TMapObj): Integer;
    procedure Delete(I: Integer);
    procedure Sort;
    function SpeedAt(D: Single): Single;
    function Validate: TStringList;   // warnings (caller frees)
    function Count(K: TMapObjKind): Integer;
    procedure SaveToFile(const AFileName: string);
    procedure LoadFromFile(const AFileName: string);
    procedure FillRandom(FromD, ToD: Single; Seed: LongWord; Difficulty: Integer);
  end;

  { the endless random river }
  TPCRandomGen = record
    State: LongWord;
    D: Single;                 // where the next obstacle stands
    Count, Difficulty: Integer;
  end;

function NewPillar(D, W, GapY, Gap: Single): TMapObj;
function NewItem(K: TMapObjKind; D, Y: Single): TMapObj;
function NewObj(K: TMapObjKind; D, Y: Single): TMapObj;   // any kind, with its usual size
function ObjRect(const O: TMapObj): TRectF;                // where it can be (design px, world x)
function SwingOffset(const O: TMapObj; Scroll: Single): Single;
function CloudOffset(const O: TMapObj; Scroll: Single): Single;
function PinwheelAngle(const O: TMapObj; Scroll: Single): Single;
procedure KoiPos(const O: TMapObj; Scroll: Single; out X, Y, Angle: Single);
procedure GenInit(var G: TPCRandomGen; Seed: LongWord; Difficulty: Integer; StartD: Single = 1060);
procedure GenNext(var G: TPCRandomGen; var Objs: TMapObjArray);
function RandomSpeedAt(D: Single; Difficulty: Integer): Single;
function MapFolder(const ExeDir: string): string;

var
  PCDataRoot: string = '';   // the game folder; '' = next to the exe (the editors point it at the game)

function PCRoot: string;

const
  DiffSpeedK: array[0..2] of Single = (0.85, 1, 1.15);
  DiffGapK: array[0..2] of Single = (55, 0, -25);
  DiffHawkK: array[0..2] of Single = (0.5, 1, 1.5);

implementation

function PCRoot: string;
begin
  if PCDataRoot <> '' then Result := IncludeTrailingPathDelimiter(PCDataRoot)
  else Result := ExtractFilePath(ParamStr(0));
end;

function MapFolder(const ExeDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ExeDir) + 'maps' + PathDelim;
end;

function NewPillar(D, W, GapY, Gap: Single): TMapObj;
begin
  Result := Default(TMapObj);
  Result.Kind := okPillar;
  Result.D := D;
  Result.W := W;
  Result.GapY := GapY;
  Result.Gap := Gap;
  Result.Top := True;
  Result.Bottom := True;
  Result.Scale := 1;
end;

function NewItem(K: TMapObjKind; D, Y: Single): TMapObj;
begin
  Result := Default(TMapObj);
  Result.Kind := K;
  Result.D := D;
  Result.Y := Y;
  Result.Scale := 1;
end;

function NewObj(K: TMapObjKind; D, Y: Single): TMapObj;
begin
  case K of
    okPillar: Result := NewPillar(D, 80, EnsureRange(Y, 150, 680), 300);
    okSwing:
      begin
        Result := NewPillar(D, 80, EnsureRange(Y, 240, 600), 290);
        Result.Kind := okSwing;
        Result.Amp := 120;
      end;
  else
    begin
      Result := NewItem(K, D, Y);
      case K of
        okBamboo:
          begin
            Result.Y := EnsureRange(Y, 260, MapWaterY - 80);
            Result.W := 70;
          end;
        okCloud:
          begin
            Result.W := 80;
            Result.Amp := 90;
          end;
        okPinwheel: Result.W := 110;
        okKoi: Result.Y := EnsureRange(Y, 150, MapWaterY - 120);
      end;
    end;
  end;
end;

function RectF(L, T, R, B: Single): TRectF;
begin
  Result.Left := L;
  Result.Top := T;
  Result.Right := R;
  Result.Bottom := B;
end;

function ObjRect(const O: TMapObj): TRectF;
var
  R: Single;
begin
  case O.Kind of
    okPillar: Result := RectF(O.D - O.W, 0, O.D + O.W, MapWaterY);
    okSwing: Result := RectF(O.D - O.W, 0, O.D + O.W, MapWaterY);
    okBamboo: Result := RectF(O.D - O.W, O.Y - 30, O.D + O.W, MapWaterY);
    okCloud: Result := RectF(O.D - O.W * 1.4, O.Y - O.Amp - O.W, O.D + O.W * 1.4, O.Y + O.Amp + O.W);
    okPinwheel: Result := RectF(O.D - O.W, O.Y - O.W, O.D + O.W, O.Y + O.W);
    okKoi: Result := RectF(O.D - 180, O.Y - 30, O.D + 40, MapWaterY + 20);
    okHawk: Result := RectF(O.D - 40, O.Y - 30, O.D + 40, O.Y + 30);
  else
    begin
      R := 28;
      Result := RectF(O.D - R, O.Y - R, O.D + R, O.Y + R);
    end;
  end;
end;

{ the gap of a swinging pillar: up and down as the crane comes nearer }
function SwingOffset(const O: TMapObj; Scroll: Single): Single;
begin
  Result := O.Amp * Sin((Scroll + MapCraneX - O.D) * 0.0065 + O.D * 0.013);
end;

function CloudOffset(const O: TMapObj; Scroll: Single): Single;
begin
  Result := O.Amp * Sin(Scroll * 0.0045 + O.D * 0.021);
end;

function PinwheelAngle(const O: TMapObj; Scroll: Single): Single;
begin
  Result := Scroll * 0.009 + O.D * 0.017;
end;

{ a koi leaps from the river when it is 520 px ahead of the crane and falls
  back 180 px behind; X is the world x }
procedure KoiPos(const O: TMapObj; Scroll: Single; out X, Y, Angle: Single);
var
  T, Rel: Single;
begin
  Rel := O.D - Scroll - MapCraneX;
  T := EnsureRange((520 - Rel) / 700, 0, 1);
  X := O.D - 140 * T;
  Y := MapWaterY + 40 - (MapWaterY + 40 - O.Y) * Sin(Pi * T);
  // heading: the slope of the arc (nose up while rising)
  Angle := ArcTan2(-(MapWaterY + 40 - O.Y) * Pi * Cos(Pi * T) / 700, -140 / 700 - 1);
end;

{ ---------- the random river ---------- }

function GenRnd(var G: TPCRandomGen): Single;
begin
  G.State := G.State * 1664525 + 1013904223;
  Result := (G.State shr 8) / 16777216;
end;

function RandomSpeedAt(D: Single; Difficulty: Integer): Single;
begin
  Result := Min(440, 230 + D / MapPxPerMetre * 0.12) * DiffSpeedK[EnsureRange(Difficulty, 0, 2)];
end;

procedure GenInit(var G: TPCRandomGen; Seed: LongWord; Difficulty: Integer; StartD: Single);
begin
  G.State := Seed;
  G.D := StartD;
  G.Count := 0;
  G.Difficulty := EnsureRange(Difficulty, 0, 2);
end;

{ the next obstacle (and maybe a lantern and a hawk); the gap narrows and the
  spacing shrinks with the speed the river will have there }
procedure GenNext(var G: TPCRandomGen; var Objs: TMapObjArray);
var
  O, It: TMapObj;
  Lv, Sp, R: Single;

  procedure Push(const X: TMapObj);
  begin
    SetLength(Objs, Length(Objs) + 1);
    Objs[High(Objs)] := X;
  end;

begin
  Sp := RandomSpeedAt(G.D, G.Difficulty) / DiffSpeedK[G.Difficulty];
  Lv := EnsureRange((Sp - 230) / 200, 0, 1);
  // now and then one of the other obstacles instead of a pillar
  R := GenRnd(G);
  if (G.D > 3200) and (R < 0.16 + 0.14 * Lv) then
  begin
    case Trunc(GenRnd(G) * 5) of
      0: begin
           O := NewObj(okSwing, G.D, 330 + GenRnd(G) * 220);
           O.Gap := 300 - 40 * Lv + DiffGapK[G.Difficulty];
           O.Amp := 70 + 70 * GenRnd(G);
         end;
      1: O := NewObj(okBamboo, G.D, 420 + GenRnd(G) * 200);
      2: O := NewObj(okCloud, G.D, 220 + GenRnd(G) * 360);
      3: O := NewObj(okPinwheel, G.D, 300 + GenRnd(G) * 260);
    else
      O := NewObj(okKoi, G.D, 260 + GenRnd(G) * 220);
    end;
    if O.Kind = okPinwheel then O.W := 90 + 40 * GenRnd(G);
    Push(O);
    if GenRnd(G) < 0.5 then Push(NewItem(okLantern, O.D + 230, 200 + GenRnd(G) * 420));
    Inc(G.Count);
    G.D := G.D + Max(340, 470 - (Sp - 230) * 0.6);
    Exit;
  end;
  // bonuses, rare
  R := GenRnd(G);
  if (G.D > 2400) and (R < 0.045) then Push(NewItem(okHeart, G.D + 215, 220 + GenRnd(G) * 380))
  else if (G.D > 2400) and (R < 0.10) then Push(NewItem(okSlow, G.D + 215, 220 + GenRnd(G) * 380));
  O := NewPillar(G.D, 62 + 26 * GenRnd(G) + 12 * Lv, 0, 0);
  O.Gap := 270 - 90 * Lv - 30 * GenRnd(G) + DiffGapK[G.Difficulty];
  O.GapY := 200 + GenRnd(G) * 420;
  O.Top := GenRnd(G) < 0.82;
  O.Bottom := (not O.Top) or (GenRnd(G) < 0.88);
  if not O.Top then O.GapY := Max(O.GapY, 320);
  if not O.Bottom then O.GapY := Min(O.GapY, 560);
  O.Scale := GenRnd(G) * 1000;   // the seed of its look (shrubs, vines)
  Push(O);
  if GenRnd(G) < 0.75 then
  begin
    if GenRnd(G) < 0.6 then It := NewItem(okLantern, O.D, O.GapY)
    else It := NewItem(okLantern, O.D + 215, 200 + GenRnd(G) * 420);
    Push(It);
  end;
  if (G.D > 1600 + 1060) and (GenRnd(G) < (0.18 + 0.25 * Lv) * DiffHawkK[G.Difficulty]) then
    Push(NewItem(okHawk, O.D + 260 + GenRnd(G) * 120, 160 + GenRnd(G) * 480));
  Inc(G.Count);
  G.D := G.D + Max(300, 440 - (Sp - 230) * 0.6);
end;

{ ---------- TPCMap ---------- }

constructor TPCMap.Create;
begin
  inherited Create;
  Clear;
end;

procedure TPCMap.Clear;
begin
  Name := 'New map';
  Author := '';
  Description := '';
  Music := '';
  FileName := '';
  Season := -1;
  TimeOfDay := -1;
  Theme := -1;
  Lives := 0;
  SpeedStart := 230;
  SpeedEnd := 330;
  Length_ := 12000;
  SetLength(Objs, 0);
end;

procedure TPCMap.Assign(Src: TPCMap);
begin
  Name := Src.Name;
  Author := Src.Author;
  Description := Src.Description;
  Music := Src.Music;
  FileName := Src.FileName;
  Season := Src.Season;
  TimeOfDay := Src.TimeOfDay;
  Theme := Src.Theme;
  Lives := Src.Lives;
  SpeedStart := Src.SpeedStart;
  SpeedEnd := Src.SpeedEnd;
  Length_ := Src.Length_;
  Objs := Copy(Src.Objs);
end;


function TPCMap.Add(const O: TMapObj): Integer;
begin
  SetLength(Objs, Length(Objs) + 1);
  Objs[High(Objs)] := O;
  Result := High(Objs);
end;

procedure TPCMap.Delete(I: Integer);
var
  K: Integer;
begin
  if (I < 0) or (I > High(Objs)) then Exit;
  for K := I to High(Objs) - 1 do Objs[K] := Objs[K + 1];
  SetLength(Objs, Length(Objs) - 1);
end;

procedure TPCMap.Sort;
var
  I, J: Integer;
  T: TMapObj;
begin
  for I := 1 to High(Objs) do
  begin
    T := Objs[I];
    J := I - 1;
    while (J >= 0) and (Objs[J].D > T.D) do
    begin
      Objs[J + 1] := Objs[J];
      Dec(J);
    end;
    Objs[J + 1] := T;
  end;
end;

function TPCMap.SpeedAt(D: Single): Single;
begin
  Result := SpeedStart + (SpeedEnd - SpeedStart) * EnsureRange(D / Max(1, Length_), 0, 1);
end;

function TPCMap.Count(K: TMapObjKind): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Objs) do
    if Objs[I].Kind = K then Inc(Result);
end;

{ things that make a map unfair or broken }
function TPCMap.Validate: TStringList;
var
  I, J: Integer;
begin
  Result := TStringList.Create;
  if Trim(Name) = '' then Result.Add('the map has no name');
  if Length_ < 2000 then Result.Add('the map is very short (under 200 m)');
  if Count(okPillar) + Count(okSwing) + Count(okBamboo) + Count(okCloud) + Count(okPinwheel) + Count(okKoi) = 0 then
    Result.Add('there are no obstacles');
  for I := 0 to High(Objs) do
    with Objs[I] do
    begin
      if D > Length_ then
        Result.Add(Format('%s %d at %d m stands after the finish', [MapObjIds[Kind], I + 1, Round(D / 10)]));
      if Kind = okPillar then
      begin
        if Top and Bottom and (Gap < 150) then
          Result.Add(Format('pillar %d at %d m: the gap (%d) is too small to fly through', [I + 1, Round(D / 10), Round(Gap)]));
        if (not Top) and (not Bottom) then
          Result.Add(Format('pillar %d at %d m has neither a pillar nor a rock', [I + 1, Round(D / 10)]));
        if Top and (GapY - Gap / 2 < 20) then
          Result.Add(Format('pillar %d at %d m: the gap reaches out of the top', [I + 1, Round(D / 10)]));
        if Bottom and (GapY + Gap / 2 > MapWaterY - 20) then
          Result.Add(Format('pillar %d at %d m: the gap reaches into the river', [I + 1, Round(D / 10)]));
        for J := I + 1 to High(Objs) do
          if (Objs[J].Kind = okPillar) and (Abs(Objs[J].D - D) < (Objs[J].W + W) * 0.8) and
             (Abs(Objs[J].GapY - GapY) > (Objs[J].Gap + Gap) / 2) then
            Result.Add(Format('pillars %d and %d overlap with gaps that do not line up', [I + 1, J + 1]));
      end;
      if Kind = okSwing then
      begin
        if GapY - Amp - Gap / 2 < 20 then
          Result.Add(Format('swinging pillar %d at %d m: the gap swings out of the top', [I + 1, Round(D / 10)]));
        if GapY + Amp + Gap / 2 > MapWaterY - 20 then
          Result.Add(Format('swinging pillar %d at %d m: the gap swings into the river', [I + 1, Round(D / 10)]));
        if Gap < 170 then
          Result.Add(Format('swinging pillar %d at %d m: the gap (%d) is too small', [I + 1, Round(D / 10), Round(Gap)]));
      end;
      if (Kind = okBamboo) and (Y < 200) then
        Result.Add(Format('bamboo %d at %d m is nearly as high as the sky', [I + 1, Round(D / 10)]));
      if (Kind = okShape) and (Trim(Shape) = '') then
        Result.Add(Format('shape %d at %d m has no shape file', [I + 1, Round(D / 10)]));
    end;
end;

procedure TPCMap.SaveToFile(const AFileName: string);
var
  SL: TStringList;
  I: Integer;
  FS: TFormatSettings;

  function F(V: Single): string;
  begin
    Result := FloatToStrF(V, ffFixed, 8, 1, FS);
  end;

begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Sort;
  SL := TStringList.Create;
  try
    SL.Add('PCMAP 1');
    SL.Add('name=' + Name);
    SL.Add('author=' + Author);
    SL.Add('description=' + StringReplace(Description, LineEnding, '\n', [rfReplaceAll]));
    SL.Add('season=' + IntToStr(Season));
    SL.Add('time=' + IntToStr(TimeOfDay));
    SL.Add('background=' + IntToStr(Theme));
    SL.Add('lives=' + IntToStr(Lives));
    SL.Add('speed=' + F(SpeedStart) + ';' + F(SpeedEnd));
    SL.Add('length=' + F(Length_));
    SL.Add('music=' + Music);
    for I := 0 to High(Objs) do
      with Objs[I] do
        case Kind of
          okPillar: SL.Add(Format('pillar=%s;%s;%s;%s;%d;%d;%s', [F(D), F(W), F(GapY), F(Gap), Ord(Top),
            Ord(Bottom), F(Scale)]));
          okLantern: SL.Add(Format('lantern=%s;%s', [F(D), F(Y)]));
          okHawk: SL.Add(Format('hawk=%s;%s', [F(D), F(Y)]));
          okShape: SL.Add(Format('shape=%s;%s;%s;%s;%d;%d', [F(D), F(Y), Shape, FloatToStrF(Scale, ffFixed, 8, 2, FS),
            Ord(Solid), Ord(Flip)]));
          okHeart: SL.Add(Format('heart=%s;%s', [F(D), F(Y)]));
          okSlow: SL.Add(Format('slow=%s;%s', [F(D), F(Y)]));
          okSwing: SL.Add(Format('swing=%s;%s;%s;%s;%s;%d;%d', [F(D), F(W), F(GapY), F(Gap), F(Amp), Ord(Top),
            Ord(Bottom)]));
          okBamboo: SL.Add(Format('bamboo=%s;%s;%s', [F(D), F(Y), F(W)]));
          okCloud: SL.Add(Format('cloud=%s;%s;%s;%s', [F(D), F(Y), F(W), F(Amp)]));
          okPinwheel: SL.Add(Format('pinwheel=%s;%s;%s', [F(D), F(Y), F(W)]));
          okKoi: SL.Add(Format('koi=%s;%s', [F(D), F(Y)]));
        end;
    SL.SaveToFile(AFileName);
    FileName := AFileName;
  finally
    SL.Free;
  end;
end;

procedure TPCMap.LoadFromFile(const AFileName: string);
var
  SL, P: TStringList;
  I: Integer;
  K, V: string;
  O: TMapObj;
  FS: TFormatSettings;

  function N(Idx: Integer; Def: Single): Single;
  begin
    if Idx < P.Count then Result := StrToFloatDef(P[Idx], Def, FS) else Result := Def;
  end;

begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SL := TStringList.Create;
  P := TStringList.Create;
  try
    P.Delimiter := ';';
    P.StrictDelimiter := True;
    SL.LoadFromFile(AFileName);
    if (SL.Count = 0) or (Copy(SL[0], 1, 5) <> 'PCMAP') then
      raise Exception.Create('not a Paper Crane map: ' + AFileName);
    Clear;
    FileName := AFileName;
    for I := 1 to SL.Count - 1 do
    begin
      K := SL.Names[I];
      V := SL.ValueFromIndex[I];
      P.DelimitedText := V;
      if K = 'name' then Name := V
      else if K = 'author' then Author := V
      else if K = 'description' then Description := StringReplace(V, '\n', LineEnding, [rfReplaceAll])
      else if K = 'season' then Season := EnsureRange(StrToIntDef(V, -1), -1, 3)
      else if K = 'time' then TimeOfDay := EnsureRange(StrToIntDef(V, -1), -1, 2)
      else if K = 'background' then Theme := EnsureRange(StrToIntDef(V, -1), -1, MapThemeCount - 1)
      else if K = 'lives' then Lives := EnsureRange(StrToIntDef(V, 0), 0, MaxHearts)
      else if K = 'speed' then
      begin
        SpeedStart := EnsureRange(N(0, 230), 80, 800);
        SpeedEnd := EnsureRange(N(1, SpeedStart), 80, 800);
      end
      else if K = 'length' then Length_ := Max(500, N(0, 12000))
      else if K = 'music' then Music := V
      else if K = 'pillar' then
      begin
        O := NewPillar(N(0, 0), N(1, 75), N(2, 420), N(3, 250));
        O.Top := (P.Count < 5) or (P[4] = '1');
        O.Bottom := (P.Count < 6) or (P[5] = '1');
        O.Scale := N(6, 0);
        Add(O);
      end
      else if K = 'lantern' then Add(NewItem(okLantern, N(0, 0), N(1, 400)))
      else if K = 'hawk' then Add(NewItem(okHawk, N(0, 0), N(1, 400)))
      else if K = 'heart' then Add(NewItem(okHeart, N(0, 0), N(1, 400)))
      else if K = 'slow' then Add(NewItem(okSlow, N(0, 0), N(1, 400)))
      else if K = 'swing' then
      begin
        O := NewObj(okSwing, N(0, 0), N(2, 420));
        O.W := N(1, 80);
        O.GapY := N(2, 420);
        O.Gap := N(3, 290);
        O.Amp := N(4, 120);
        O.Top := (P.Count < 6) or (P[5] = '1');
        O.Bottom := (P.Count < 7) or (P[6] = '1');
        Add(O);
      end
      else if K = 'bamboo' then
      begin
        O := NewObj(okBamboo, N(0, 0), N(1, 500));
        O.Y := N(1, 500);
        O.W := N(2, 70);
        Add(O);
      end
      else if K = 'cloud' then
      begin
        O := NewObj(okCloud, N(0, 0), N(1, 300));
        O.W := N(2, 80);
        O.Amp := N(3, 90);
        Add(O);
      end
      else if K = 'pinwheel' then
      begin
        O := NewObj(okPinwheel, N(0, 0), N(1, 400));
        O.W := N(2, 110);
        Add(O);
      end
      else if K = 'koi' then
      begin
        O := NewObj(okKoi, N(0, 0), N(1, 300));
        O.Y := N(1, 300);
        Add(O);
      end
      else if K = 'shape' then
      begin
        O := NewItem(okShape, N(0, 0), N(1, 700));
        if P.Count > 2 then O.Shape := P[2];
        O.Scale := N(3, 1);
        O.Solid := (P.Count > 4) and (P[4] = '1');
        O.Flip := (P.Count > 5) and (P[5] = '1');
        Add(O);
      end;
    end;
    Sort;
  finally
    P.Free;
    SL.Free;
  end;
end;

{ fill a stretch with the random river's obstacles (editors) }
procedure TPCMap.FillRandom(FromD, ToD: Single; Seed: LongWord; Difficulty: Integer);
var
  G: TPCRandomGen;
  Tmp: TMapObjArray;
  I: Integer;
begin
  GenInit(G, Seed, Difficulty, FromD);
  SetLength(Tmp, 0);
  while G.D < ToD do
    GenNext(G, Tmp);
  for I := 0 to High(Tmp) do
    if Tmp[I].D <= ToD then Add(Tmp[I]);
  Sort;
end;

end.
