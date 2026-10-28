unit uPCShape;

{ Paper Crane shapes (.pcshape): cut-paper pictures made of polygons, shared by
  the Shape Editor, both map editors and the game.

  Coordinates are design pixels around the anchor (0, 0) = the middle of the
  shape's foot; y grows downward, so a shape standing on the river has
  negative y. Every polygon has a colour (with alpha) and a lift: how high the
  sheet sits above the one under it (0 = flat, 1 = high, a deeper shadow).
  The shape is drawn polygon by polygon, the first at the bottom.
  A shape placed in a map can be decoration or solid (the crane hits it). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes;

type
  TPointFArray = array of TPointF;

  TShapePoly = record
    Color: TBGRAPixel;
    Lift: Single;
    Pts: array of TPointF;
  end;

  { TPCShape }

  TPCShape = class
  public
    Name, FileName: string;
    Solid: Boolean;              // default for new placements
    Polys: array of TShapePoly;
    constructor Create;
    procedure Clear;
    procedure Assign(Src: TPCShape);
    function AddPoly(const Pts: array of TPointF; C: TBGRAPixel; Lift: Single = 0.4): Integer;
    procedure DeletePoly(I: Integer);
    procedure MovePoly(I, Delta: Integer);
    function Bounds: TRectF;
    function HitTest(X, Y: Single): Integer;   // topmost polygon under a local point, -1 none
    procedure SaveToFile(const AFileName: string);
    procedure LoadFromFile(const AFileName: string);
    { draw at X, Y (pixels) with K pixels per design unit; a paper shadow per lift }
    procedure Draw(B: TBGRABitmap; X, Y, K: Single; Flip: Boolean = False; Shadow: Boolean = True;
      Alpha: Byte = 255);
  end;

function PointInPoly(const Pts: array of TPointF; X, Y: Single): Boolean;
function ShapePresetNames: TStringArray;
procedure MakeShapePreset(Sh: TPCShape; const Name: string);
function ColorToHex(C: TBGRAPixel): string;
function HexToColor(const S: string): TBGRAPixel;

implementation

function ColorToHex(C: TBGRAPixel): string;
begin
  Result := '#' + IntToHex(C.red, 2) + IntToHex(C.green, 2) + IntToHex(C.blue, 2) + IntToHex(C.alpha, 2);
end;

function HexToColor(const S: string): TBGRAPixel;
var
  H: string;
begin
  H := StringReplace(Trim(S), '#', '', []);
  if Length(H) < 6 then Exit(BGRA(128, 128, 128));
  Result.red := StrToIntDef('$' + Copy(H, 1, 2), 128);
  Result.green := StrToIntDef('$' + Copy(H, 3, 2), 128);
  Result.blue := StrToIntDef('$' + Copy(H, 5, 2), 128);
  if Length(H) >= 8 then Result.alpha := StrToIntDef('$' + Copy(H, 7, 2), 255) else Result.alpha := 255;
end;

function PointInPoly(const Pts: array of TPointF; X, Y: Single): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  J := High(Pts);
  for I := 0 to High(Pts) do
  begin
    if ((Pts[I].Y > Y) <> (Pts[J].Y > Y)) and
       (X < (Pts[J].X - Pts[I].X) * (Y - Pts[I].Y) / (Pts[J].Y - Pts[I].Y) + Pts[I].X) then
      Result := not Result;
    J := I;
  end;
end;

constructor TPCShape.Create;
begin
  inherited Create;
  Clear;
end;

procedure TPCShape.Clear;
begin
  Name := 'New shape';
  FileName := '';
  Solid := False;
  SetLength(Polys, 0);
end;

procedure TPCShape.Assign(Src: TPCShape);
var
  I: Integer;
begin
  Name := Src.Name;
  FileName := Src.FileName;
  Solid := Src.Solid;
  SetLength(Polys, Length(Src.Polys));
  for I := 0 to High(Polys) do
  begin
    Polys[I] := Src.Polys[I];
    Polys[I].Pts := Copy(Src.Polys[I].Pts);
  end;
end;

function TPCShape.AddPoly(const Pts: array of TPointF; C: TBGRAPixel; Lift: Single): Integer;
var
  I: Integer;
begin
  SetLength(Polys, Length(Polys) + 1);
  Result := High(Polys);
  Polys[Result].Color := C;
  Polys[Result].Lift := Lift;
  SetLength(Polys[Result].Pts, Length(Pts));
  for I := 0 to High(Pts) do Polys[Result].Pts[I] := Pts[I];
end;

procedure TPCShape.DeletePoly(I: Integer);
var
  K: Integer;
begin
  if (I < 0) or (I > High(Polys)) then Exit;
  for K := I to High(Polys) - 1 do Polys[K] := Polys[K + 1];
  SetLength(Polys, Length(Polys) - 1);
end;

procedure TPCShape.MovePoly(I, Delta: Integer);
var
  J: Integer;
  T: TShapePoly;
begin
  J := I + Delta;
  if (I < 0) or (I > High(Polys)) or (J < 0) or (J > High(Polys)) then Exit;
  T := Polys[I];
  Polys[I] := Polys[J];
  Polys[J] := T;
end;

function TPCShape.Bounds: TRectF;
var
  I, K: Integer;
begin
  Result := RectF(0, 0, 0, 0);
  if Length(Polys) = 0 then Exit;
  Result := RectF(1e9, 1e9, -1e9, -1e9);
  for I := 0 to High(Polys) do
    for K := 0 to High(Polys[I].Pts) do
      with Polys[I].Pts[K] do
      begin
        Result.Left := Min(Result.Left, X);
        Result.Top := Min(Result.Top, Y);
        Result.Right := Max(Result.Right, X);
        Result.Bottom := Max(Result.Bottom, Y);
      end;
  if Result.Left > Result.Right then Result := RectF(0, 0, 0, 0);
end;

function TPCShape.HitTest(X, Y: Single): Integer;
var
  I: Integer;
begin
  for I := High(Polys) downto 0 do
    if (Length(Polys[I].Pts) >= 3) and PointInPoly(Polys[I].Pts, X, Y) then Exit(I);
  Result := -1;
end;

procedure TPCShape.SaveToFile(const AFileName: string);
var
  SL: TStringList;
  I, K: Integer;
  S: string;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SL := TStringList.Create;
  try
    SL.Add('PCSHAPE 1');
    SL.Add('name=' + Name);
    SL.Add('solid=' + IntToStr(Ord(Solid)));
    for I := 0 to High(Polys) do
    begin
      S := 'poly=' + ColorToHex(Polys[I].Color) + ';' + FloatToStrF(Polys[I].Lift, ffFixed, 6, 2, FS) + ';';
      for K := 0 to High(Polys[I].Pts) do
      begin
        if K > 0 then S := S + ' ';
        S := S + FloatToStrF(Polys[I].Pts[K].X, ffFixed, 8, 1, FS) + ',' +
          FloatToStrF(Polys[I].Pts[K].Y, ffFixed, 8, 1, FS);
      end;
      SL.Add(S);
    end;
    SL.SaveToFile(AFileName);
    FileName := AFileName;
  finally
    SL.Free;
  end;
end;

procedure TPCShape.LoadFromFile(const AFileName: string);
var
  SL, P, Pt: TStringList;
  I, K, N: Integer;
  V: string;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SL := TStringList.Create;
  P := TStringList.Create;
  Pt := TStringList.Create;
  try
    P.Delimiter := ';';
    P.StrictDelimiter := True;
    Pt.Delimiter := ' ';
    Pt.StrictDelimiter := True;
    SL.LoadFromFile(AFileName);
    if (SL.Count = 0) or (Copy(SL[0], 1, 7) <> 'PCSHAPE') then
      raise Exception.Create('not a Paper Crane shape: ' + AFileName);
    Clear;
    FileName := AFileName;
    for I := 1 to SL.Count - 1 do
    begin
      V := SL.ValueFromIndex[I];
      if SL.Names[I] = 'name' then Name := V
      else if SL.Names[I] = 'solid' then Solid := V = '1'
      else if SL.Names[I] = 'poly' then
      begin
        P.DelimitedText := V;
        if P.Count < 3 then Continue;
        Pt.DelimitedText := Trim(P[2]);
        SetLength(Polys, Length(Polys) + 1);
        N := High(Polys);
        Polys[N].Color := HexToColor(P[0]);
        Polys[N].Lift := StrToFloatDef(P[1], 0.4, FS);
        SetLength(Polys[N].Pts, 0);
        for K := 0 to Pt.Count - 1 do
          if Pos(',', Pt[K]) > 0 then
          begin
            SetLength(Polys[N].Pts, Length(Polys[N].Pts) + 1);
            Polys[N].Pts[High(Polys[N].Pts)] := PointF(
              StrToFloatDef(Copy(Pt[K], 1, Pos(',', Pt[K]) - 1), 0, FS),
              StrToFloatDef(Copy(Pt[K], Pos(',', Pt[K]) + 1, 99), 0, FS));
          end;
      end;
    end;
  finally
    Pt.Free;
    P.Free;
    SL.Free;
  end;
end;

procedure TPCShape.Draw(B: TBGRABitmap; X, Y, K: Single; Flip: Boolean; Shadow: Boolean; Alpha: Byte);
var
  I, J: Integer;
  Pts, Sh: array of TPointF;
  F: Single;
  C: TBGRAPixel;
begin
  if Flip then F := -1 else F := 1;
  for I := 0 to High(Polys) do
  begin
    if Length(Polys[I].Pts) < 3 then Continue;
    SetLength(Pts, Length(Polys[I].Pts));
    for J := 0 to High(Pts) do
      Pts[J] := PointF(X + Polys[I].Pts[J].X * K * F, Y + Polys[I].Pts[J].Y * K);
    if Shadow and (Polys[I].Lift > 0) then
    begin
      // a soft paper shadow: two offset copies, the far one fainter
      SetLength(Sh, Length(Pts));
      for J := 0 to High(Pts) do
        Sh[J] := PointF(Pts[J].X + 5 * K * Polys[I].Lift, Pts[J].Y + 9 * K * Polys[I].Lift);
      B.FillPolyAntialias(Sh, BGRA(0, 0, 20, Round(30 * Alpha / 255)));
      for J := 0 to High(Pts) do
        Sh[J] := PointF(Pts[J].X + 3 * K * Polys[I].Lift, Pts[J].Y + 5 * K * Polys[I].Lift);
      B.FillPolyAntialias(Sh, BGRA(0, 0, 20, Round(40 * Alpha / 255)));
    end;
    C := Polys[I].Color;
    C.alpha := Round(C.alpha * Alpha / 255);
    B.FillPolyAntialias(Pts, C);
  end;
end;

{ ---------- presets ---------- }

function ShapePresetNames: TStringArray;
begin
  Result := ['Lotus', 'Pine tree', 'Red lantern', 'Cloud', 'Pagoda roof', 'Rock', 'Sampan', 'Koi fish',
    'Bamboo', 'Moon gate'];
end;

function Circle(CX, CY, RX, RY: Single; N: Integer = 24): TPointFArray;
var
  I: Integer;
begin
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := PointF(CX + Cos(I * 2 * Pi / N) * RX, CY + Sin(I * 2 * Pi / N) * RY);
end;

procedure MakeShapePreset(Sh: TPCShape; const Name: string);
var
  I: Integer;
  A: Single;
  P: TPointFArray;
begin
  Sh.Clear;
  Sh.Name := Name;
  if Name = 'Lotus' then
  begin
    Sh.AddPoly(Circle(0, -6, 70, 12), BGRA(60, 120, 80), 0.2);
    for I := 0 to 6 do
    begin
      A := -Pi / 2 + (I - 3) * 0.32;
      Sh.AddPoly([PointF(0, -10), PointF(Cos(A - 0.25) * 30, -10 + Sin(A - 0.25) * 30),
        PointF(Cos(A) * 62, -10 + Sin(A) * 62), PointF(Cos(A + 0.25) * 30, -10 + Sin(A + 0.25) * 30)],
        BGRA(236, 130 + Abs(I - 3) * 18, 160 + Abs(I - 3) * 10), 0.3 + 0.1 * (3 - Abs(I - 3)) / 3);
    end;
    Sh.AddPoly(Circle(0, -18, 9, 7, 12), BGRA(240, 200, 70), 0.5);
  end
  else if Name = 'Pine tree' then
  begin
    Sh.AddPoly([PointF(-6, 0), PointF(6, 0), PointF(10, -80), PointF(-2, -150), PointF(-8, -80)], BGRA(90, 66, 50), 0.3);
    Sh.AddPoly(Circle(18, -78, 58, 14), BGRA(44, 92, 60), 0.4);
    Sh.AddPoly(Circle(-14, -112, 50, 13), BGRA(50, 104, 66), 0.5);
    Sh.AddPoly(Circle(0, -146, 36, 11), BGRA(58, 116, 72), 0.6);
  end
  else if Name = 'Red lantern' then
  begin
    Sh.AddPoly([PointF(-1, -120), PointF(1, -120), PointF(1, -80), PointF(-1, -80)], BGRA(40, 30, 30), 0.1);
    Sh.AddPoly([PointF(-14, -80), PointF(14, -80), PointF(14, -72), PointF(-14, -72)], BGRA(230, 176, 48), 0.3);
    Sh.AddPoly(Circle(0, -48, 30, 26), BGRA(200, 48, 42), 0.5);
    Sh.AddPoly(Circle(-8, -50, 8, 20), BGRA(232, 96, 80), 0.6);
    Sh.AddPoly([PointF(-14, -24), PointF(14, -24), PointF(14, -16), PointF(-14, -16)], BGRA(230, 176, 48), 0.3);
    Sh.AddPoly([PointF(-3, -16), PointF(3, -16), PointF(5, 0), PointF(-5, 0)], BGRA(230, 176, 48), 0.3);
  end
  else if Name = 'Cloud' then
  begin
    Sh.AddPoly(Circle(-40, -30, 46, 30), BGRA(210, 220, 232), 0.3);
    Sh.AddPoly(Circle(30, -34, 52, 34), BGRA(210, 220, 232), 0.3);
    Sh.AddPoly(Circle(-10, -52, 44, 34), BGRA(250, 252, 255), 0.5);
    Sh.AddPoly(Circle(44, -44, 34, 26), BGRA(250, 252, 255), 0.5);
  end
  else if Name = 'Pagoda roof' then
  begin
    Sh.AddPoly([PointF(-40, 0), PointF(40, 0), PointF(36, -40), PointF(-36, -40)], BGRA(236, 226, 206), 0.3);
    Sh.AddPoly([PointF(-90, -36), PointF(-70, -46), PointF(70, -46), PointF(90, -36), PointF(50, -72),
      PointF(-50, -72)], BGRA(70, 56, 62), 0.6);
    Sh.AddPoly([PointF(-8, -72), PointF(8, -72), PointF(3, -110), PointF(-3, -110)], BGRA(70, 56, 62), 0.5);
  end
  else if Name = 'Rock' then
  begin
    Sh.AddPoly([PointF(-80, 0), PointF(-70, -40), PointF(-30, -70), PointF(20, -62), PointF(64, -30), PointF(80, 0)],
      BGRA(118, 120, 124), 0.5);
    Sh.AddPoly([PointF(-30, -70), PointF(20, -62), PointF(40, -44), PointF(-10, -50)], BGRA(156, 158, 160), 0.6);
  end
  else if Name = 'Sampan' then
  begin
    Sh.AddPoly([PointF(-90, -18), PointF(-70, 0), PointF(70, 0), PointF(90, -18), PointF(70, -10), PointF(-70, -10)],
      BGRA(96, 60, 40), 0.4);
    P := Circle(0, -10, 44, 32, 20);
    Sh.AddPoly([PointF(-44, -10), PointF(-40, -30), PointF(-22, -40), PointF(22, -40), PointF(40, -30), PointF(44, -10)],
      BGRA(160, 122, 72), 0.5);
  end
  else if Name = 'Koi fish' then
  begin
    Sh.AddPoly([PointF(-60, -20), PointF(0, -40), PointF(50, -24), PointF(60, -20), PointF(50, -14), PointF(0, -2)],
      BGRA(236, 110, 50), 0.5);
    Sh.AddPoly([PointF(-60, -20), PointF(-90, -42), PointF(-82, -20), PointF(-90, 0)], BGRA(240, 150, 90), 0.4);
    Sh.AddPoly(Circle(36, -24, 4, 4, 10), BGRA(30, 30, 30), 0.6);
    Sh.AddPoly(Circle(-6, -24, 16, 9, 14), BGRA(250, 240, 230), 0.6);
  end
  else if Name = 'Bamboo' then
  begin
    for I := 0 to 3 do
    begin
      Sh.AddPoly([PointF(-30 + I * 18, 0), PointF(-24 + I * 18, 0), PointF(-22 + I * 18 + I * 4, -170 + I * 12),
        PointF(-28 + I * 18 + I * 4, -170 + I * 12)], BGRA(110, 150, 70), 0.3 + I * 0.05);
      Sh.AddPoly([PointF(-25 + I * 18 + I * 4, -150 + I * 12), PointF(5 + I * 18, -164 + I * 12),
        PointF(-23 + I * 18 + I * 4, -144 + I * 12)], BGRA(90, 140, 60), 0.5);
    end;
  end
  else if Name = 'Moon gate' then
  begin
    P := Circle(0, -100, 100, 100, 32);
    Sh.AddPoly([PointF(-130, 0), PointF(-130, -210), PointF(130, -210), PointF(130, 0), PointF(90, 0),
      PointF(90, -60), PointF(70, -150), PointF(0, -186), PointF(-70, -150), PointF(-90, -60), PointF(-90, 0)],
      BGRA(232, 224, 210), 0.6);
    Sh.AddPoly([PointF(-140, -210), PointF(140, -210), PointF(120, -236), PointF(-120, -236)], BGRA(64, 58, 66), 0.7);
  end;
end;

end.
