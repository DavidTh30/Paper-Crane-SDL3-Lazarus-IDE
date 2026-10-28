unit uPCMenuFx;

{ Paper Crane menu effects (.pcmenufx), shared by the game and the Menu FX Editor.

  Every menu screen has its own TMenuFx, independent of the others:
    Frame  the card's frame: a style (Chinese fret, cloud scrolls, bamboo, plum
           blossom, lattice, ...), its colours and a live effect (glow, running
           lights, spinning corners, falling petals, ...)
    Title  the title's text style
    Item   the items that are not selected
    Sel    the selected item
  A text style is a font, a size (design px of the 1600 x 900 screen), bold /
  italic, a colour or a vertical gradient, an outline, a shadow and a letter
  effect (wave, bounce, rainbow, typewriter, ...) with a speed and an amount;
  every letter moves on its own.

  Drawing: the letters are cut once into cached sprites (TGlyphCache.Prepare,
  main thread) and then only placed every frame (DrawFxText, any thread), so
  the animated menus cost little. The frame is cut once (DrawFrameStatic) and
  its effect is drawn live on top (DrawFrameFx). All positions are pixels: an
  origin OX, OY and a scale K (pixels per design px).

  File: PCMENUFX 1, then per menu (index = the game's menu number - 1)
    m<i>.frame=kind;fx;color;color2;paper;speed;amount
    m<i>.title / m<i>.item / m<i>.sel=font;size;bold;italic;color;color2;gradient;
      outline;outlinecolor;shadow;fx;speed;amount }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, LazUTF8, BGRABitmap, BGRABitmapTypes;

type
  TFrameKind = (fkChinese, fkCloud, fkBamboo, fkPlum, fkLattice, fkDouble, fkImperial, fkScallop, fkPlain);
  TFrameFx = (ffNone, ffGlow, ffRunLight, ffCornerSpin, ffPetals, ffSparkle, ffBreath, ffRipple, ffLanterns);
  TTextFx = (tfNone, tfWave, tfBounce, tfFloat, tfShake, tfPulse, tfGlow, tfRainbow, tfTypewriter, tfSwing,
    tfZoomWave, tfSparkle, tfFadeWave, tfJelly, tfDrop);

const
  FrameKindNames: array[TFrameKind] of string = ('Chinese key fret', 'Cloud scrolls', 'Bamboo', 'Plum blossom',
    'Window lattice', 'Double line', 'Imperial gold', 'Papercut scallops', 'Plain paper');
  FrameFxNames: array[TFrameFx] of string = ('None', 'Glow pulse', 'Running lights', 'Spinning corners',
    'Falling petals', 'Sparkles', 'Breathing border', 'Ripples', 'Swinging lanterns');
  TextFxNames: array[TTextFx] of string = ('None', 'Wave', 'Bounce', 'Float', 'Shake', 'Pulse', 'Glow',
    'Rainbow', 'Typewriter', 'Swing', 'Zoom wave', 'Sparkle', 'Fade wave', 'Jelly', 'Drop in');
  FontChoices: array[0..15] of string = ('Segoe UI', 'Georgia', 'Palatino Linotype', 'Trebuchet MS',
    'Comic Sans MS', 'Impact', 'Consolas', 'Microsoft YaHei', 'SimSun', 'KaiTi', 'FangSong', 'Segoe Script',
    'Segoe Print', 'Gabriola', 'Ink Free', 'Tahoma');
  MenuFxCount = 18;      // the game's menus 1..18
  MenuFxNames: array[0..MenuFxCount - 1] of string = ('Main menu', 'Pause', 'Game over', 'Settings',
    'How to play', 'High scores', 'Credits', 'Custom maps', 'Saved games', 'Saved game', 'Ghosts', 'Ghost',
    'Players', 'Player', 'New player', 'Character', 'Statistics', 'Select paper card');

type
  TTextStyle = record
    Font: string;
    Size: Single;
    Bold, Italic: Boolean;
    Color, Color2: TBGRAPixel;
    Gradient: Boolean;
    Outline: Single;
    OutlineColor: TBGRAPixel;
    Shadow: Boolean;
    Fx: TTextFx;
    Speed, Amount: Single;
  end;

  TFrameStyle = record
    Kind: TFrameKind;
    Fx: TFrameFx;
    Color, Color2, Paper: TBGRAPixel;
    Speed, Amount: Single;
  end;

  TMenuFx = record
    Frame: TFrameStyle;
    Title, Item, Sel: TTextStyle;
  end;

  { TMenuFxSet }

  TMenuFxSet = class
  public
    Menus: array[0..MenuFxCount - 1] of TMenuFx;
    FileName: string;
    constructor Create;
    procedure Defaults;
    procedure SaveToFile(const AFile: string);
    procedure LoadFromFile(const AFile: string);
    procedure Assign(Src: TMenuFxSet);
  end;

  TGlyph = class
    Bmp: TBGRABitmap;
    OX, OY, Adv, H: Single;      // sprite offset from the pen, advance, line height (px)
    destructor Destroy; override;
  end;

  { TGlyphCache: letters as sprites, by style, scale, letter and variant }

  TGlyphCache = class
  private
    FList: TStringList;
    function Key(const St: TTextStyle; K: Single; const Ch: string; V: Integer): string;
    function Make(const St: TTextStyle; K: Single; const Ch: string; V: Integer): TGlyph;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Count: Integer;
    { main thread / one thread: makes every sprite Text needs for St }
    procedure Prepare(const St: TTextStyle; K: Single; const Text: string);
    { any thread: nil when not prepared }
    function Find(const St: TTextStyle; K: Single; const Ch: string; V: Integer): TGlyph;
    function TextWidth(const St: TTextStyle; K: Single; const Text: string): Single;
  end;

function DefaultText(const Font: string; Size: Single; Bold: Boolean; C: TBGRAPixel): TTextStyle;
function DefaultFrame: TFrameStyle;
{ Align: 0 left (OX the left edge), 1 centred (OX the middle); OY is the top of the line.
  Phase separates lines (items) so they do not move in step. }
procedure DrawFxText(Dest: TBGRABitmap; Cache: TGlyphCache; const St: TTextStyle; K, OX, OY, T: Single;
  const Text: string; Align: Integer; Phase: Single = 0);
procedure DrawFrameStatic(B: TBGRABitmap; const F: TFrameStyle; OX, OY, W, H, K: Single; TitleY: Single = 0);
procedure DrawFrameFx(Dest: TBGRABitmap; const F: TFrameStyle; OX, OY, W, H, K, T: Single);
function TextStyleToStr(const St: TTextStyle): string;
function StrToTextStyle(const S: string; const Def: TTextStyle): TTextStyle;
function ColorHex(C: TBGRAPixel): string;
function HexColor(const S: string; Def: TBGRAPixel): TBGRAPixel;

implementation

const
  VGlow = 1;          // variants: 0 plain, 1 glow, 2..9 rainbow hues, 10..13 scales
  VHue0 = 2;
  VScale0 = 10;
  ScaleSteps: array[0..3] of Single = (0.84, 0.92, 1.1, 1.22);

function H01(N: Integer): Single;
var
  X: LongWord;
begin
  X := LongWord(N) * 2654435761 + 12345;
  X := X xor (X shr 13);
  X := X * 1274126177;
  Result := (X and $FFFF) / 65536;
end;

function ColorHex(C: TBGRAPixel): string;
begin
  Result := Format('#%.2x%.2x%.2x%.2x', [C.red, C.green, C.blue, C.alpha]);
end;

function HexColor(const S: string; Def: TBGRAPixel): TBGRAPixel;
var
  T: string;
begin
  T := Trim(S);
  if (Length(T) < 7) or (T[1] <> '#') then Exit(Def);
  Result := BGRA(StrToIntDef('$' + Copy(T, 2, 2), Def.red), StrToIntDef('$' + Copy(T, 4, 2), Def.green),
    StrToIntDef('$' + Copy(T, 6, 2), Def.blue), StrToIntDef('$' + Copy(T, 8, 2), 255));
end;

function DefaultText(const Font: string; Size: Single; Bold: Boolean; C: TBGRAPixel): TTextStyle;
begin
  Result := Default(TTextStyle);
  Result.Font := Font;
  Result.Size := Size;
  Result.Bold := Bold;
  Result.Color := C;
  Result.Color2 := BGRA(220, 150, 40);
  Result.OutlineColor := BGRA(255, 240, 200);
  Result.Speed := 1;
  Result.Amount := 1;
end;

function DefaultFrame: TFrameStyle;
begin
  Result.Kind := fkChinese;
  Result.Fx := ffNone;
  Result.Color := BGRA(178, 40, 34);
  Result.Color2 := BGRA(222, 170, 50);
  Result.Paper := BGRA(246, 238, 222, 248);
  Result.Speed := 1;
  Result.Amount := 1;
end;

{ ---------- styles in the file ---------- }

function FS: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
end;

function TextStyleToStr(const St: TTextStyle): string;
begin
  Result := Format('%s;%s;%d;%d;%s;%s;%d;%s;%s;%d;%d;%s;%s', [St.Font, FloatToStrF(St.Size, ffFixed, 6, 1, FS),
    Ord(St.Bold), Ord(St.Italic), ColorHex(St.Color), ColorHex(St.Color2), Ord(St.Gradient),
    FloatToStrF(St.Outline, ffFixed, 6, 1, FS), ColorHex(St.OutlineColor), Ord(St.Shadow), Ord(St.Fx),
    FloatToStrF(St.Speed, ffFixed, 6, 2, FS), FloatToStrF(St.Amount, ffFixed, 6, 2, FS)]);
end;

function StrToTextStyle(const S: string; const Def: TTextStyle): TTextStyle;
var
  P: TStringList;

  function G(I: Integer): string;
  begin
    if I < P.Count then Result := P[I] else Result := '';
  end;

begin
  Result := Def;
  P := TStringList.Create;
  try
    P.Delimiter := ';';
    P.StrictDelimiter := True;
    P.DelimitedText := S;
    if G(0) <> '' then Result.Font := G(0);
    Result.Size := EnsureRange(StrToFloatDef(G(1), Def.Size, FS), 6, 120);
    Result.Bold := G(2) = '1';
    Result.Italic := G(3) = '1';
    Result.Color := HexColor(G(4), Def.Color);
    Result.Color2 := HexColor(G(5), Def.Color2);
    Result.Gradient := G(6) = '1';
    Result.Outline := EnsureRange(StrToFloatDef(G(7), 0, FS), 0, 8);
    Result.OutlineColor := HexColor(G(8), Def.OutlineColor);
    Result.Shadow := G(9) = '1';
    Result.Fx := TTextFx(EnsureRange(StrToIntDef(G(10), 0), 0, Ord(High(TTextFx))));
    Result.Speed := EnsureRange(StrToFloatDef(G(11), 1, FS), 0, 5);
    Result.Amount := EnsureRange(StrToFloatDef(G(12), 1, FS), 0, 5);
  finally
    P.Free;
  end;
end;

{ ---------- TMenuFxSet ---------- }

constructor TMenuFxSet.Create;
begin
  inherited Create;
  Defaults;
end;

procedure TMenuFxSet.Defaults;
var
  I: Integer;
begin
  for I := 0 to MenuFxCount - 1 do
  begin
    Menus[I].Frame := DefaultFrame;
    Menus[I].Title := DefaultText('Segoe UI', 44, True, BGRA(48, 40, 52));
    Menus[I].Item := DefaultText('Segoe UI', 25, False, BGRA(64, 50, 56));
    Menus[I].Sel := DefaultText('Segoe UI', 25, True, BGRA(178, 40, 34));
    Menus[I].Sel.Fx := tfWave;
    Menus[I].Sel.Amount := 0.6;
  end;
  // the main menu is alive: running lights on the frame, a glowing title,
  // the items breathe softly and the selected one bounces
  with Menus[0] do
  begin
    Frame.Fx := ffRunLight;
    Title.Gradient := True;
    Title.Color := BGRA(196, 44, 34);
    Title.Color2 := BGRA(120, 30, 40);
    Title.Fx := tfGlow;
    Title.Color2 := BGRA(150, 30, 30);
    Title.Shadow := True;
    // the items that are not selected: dark ink, a paper shadow and a thin
    // cream edge, and a gentle wave that keeps them fully opaque
    Item.Color := BGRA(44, 30, 36);
    Item.Shadow := True;
    Item.Outline := 0.8;
    Item.OutlineColor := BGRA(255, 246, 226);
    Item.Fx := tfWave;
    Item.Speed := 0.8;
    Item.Amount := 0.45;
    Sel.Fx := tfBounce;
    Sel.Size := 27;
    Sel.Outline := 1.5;
    Sel.OutlineColor := BGRA(255, 236, 190);
    Sel.Shadow := True;
    Sel.Amount := 0.8;
  end;
  with Menus[2] do      // game over
  begin
    Title.Fx := tfDrop;
    Frame.Fx := ffSparkle;
  end;
  with Menus[17] do     // select paper card
  begin
    Title.Fx := tfWave;
    Title.Amount := 0.5;
    Frame.Fx := ffPetals;
  end;
end;

procedure TMenuFxSet.Assign(Src: TMenuFxSet);
begin
  Menus := Src.Menus;
  FileName := Src.FileName;
end;

procedure TMenuFxSet.SaveToFile(const AFile: string);
var
  SL: TStringList;
  I: Integer;
begin
  SL := TStringList.Create;
  try
    SL.Add('PCMENUFX 1');
    for I := 0 to MenuFxCount - 1 do
      with Menus[I] do
      begin
        SL.Add(Format('# %s', [MenuFxNames[I]]));
        SL.Add(Format('m%d.frame=%d;%d;%s;%s;%s;%s;%s', [I, Ord(Frame.Kind), Ord(Frame.Fx), ColorHex(Frame.Color),
          ColorHex(Frame.Color2), ColorHex(Frame.Paper), FloatToStrF(Frame.Speed, ffFixed, 6, 2, FS),
          FloatToStrF(Frame.Amount, ffFixed, 6, 2, FS)]));
        SL.Add(Format('m%d.title=%s', [I, TextStyleToStr(Title)]));
        SL.Add(Format('m%d.item=%s', [I, TextStyleToStr(Item)]));
        SL.Add(Format('m%d.sel=%s', [I, TextStyleToStr(Sel)]));
      end;
    SL.SaveToFile(AFile);
    FileName := AFile;
  finally
    SL.Free;
  end;
end;

procedure TMenuFxSet.LoadFromFile(const AFile: string);
var
  SL, P: TStringList;
  I, M, Dot: Integer;
  K, V, Part: string;
begin
  SL := TStringList.Create;
  P := TStringList.Create;
  try
    SL.LoadFromFile(AFile);
    if (SL.Count = 0) or (Copy(SL[0], 1, 8) <> 'PCMENUFX') then
      raise Exception.Create('not a Paper Crane menu effects file: ' + AFile);
    Defaults;
    P.Delimiter := ';';
    P.StrictDelimiter := True;
    for I := 1 to SL.Count - 1 do
    begin
      if (SL[I] = '') or (SL[I][1] = '#') then Continue;
      K := SL.Names[I];
      V := SL.ValueFromIndex[I];
      Dot := Pos('.', K);
      if (Length(K) < 3) or (K[1] <> 'm') or (Dot = 0) then Continue;
      M := StrToIntDef(Copy(K, 2, Dot - 2), -1);
      if (M < 0) or (M >= MenuFxCount) then Continue;
      Part := Copy(K, Dot + 1, MaxInt);
      if Part = 'frame' then
      begin
        P.DelimitedText := V;
        while P.Count < 7 do P.Add('');
        with Menus[M].Frame do
        begin
          Kind := TFrameKind(EnsureRange(StrToIntDef(P[0], 0), 0, Ord(High(TFrameKind))));
          Fx := TFrameFx(EnsureRange(StrToIntDef(P[1], 0), 0, Ord(High(TFrameFx))));
          Color := HexColor(P[2], Color);
          Color2 := HexColor(P[3], Color2);
          Paper := HexColor(P[4], Paper);
          Speed := EnsureRange(StrToFloatDef(P[5], 1, FS), 0, 5);
          Amount := EnsureRange(StrToFloatDef(P[6], 1, FS), 0, 5);
        end;
      end
      else if Part = 'title' then Menus[M].Title := StrToTextStyle(V, Menus[M].Title)
      else if Part = 'item' then Menus[M].Item := StrToTextStyle(V, Menus[M].Item)
      else if Part = 'sel' then Menus[M].Sel := StrToTextStyle(V, Menus[M].Sel);
    end;
    FileName := AFile;
  finally
    P.Free;
    SL.Free;
  end;
end;

{ ---------- glyphs ---------- }

destructor TGlyph.Destroy;
begin
  Bmp.Free;
  inherited Destroy;
end;

constructor TGlyphCache.Create;
begin
  inherited Create;
  FList := TStringList.Create;
  FList.CaseSensitive := True;   // "c" and "C" are different letters
  FList.Sorted := True;
  FList.Duplicates := dupIgnore;
  FList.OwnsObjects := True;
end;

destructor TGlyphCache.Destroy;
begin
  FList.Free;
  inherited Destroy;
end;

procedure TGlyphCache.Clear;
begin
  FList.Clear;
end;

function TGlyphCache.Count: Integer;
begin
  Result := FList.Count;
end;

function TGlyphCache.Key(const St: TTextStyle; K: Single; const Ch: string; V: Integer): string;
begin
  Result := Format('%s|%.1f|%d%d|%s|%s|%d|%.1f|%s|%d|%.3f|%d|', [St.Font, St.Size, Ord(St.Bold), Ord(St.Italic),
    ColorHex(St.Color), ColorHex(St.Color2), Ord(St.Gradient), St.Outline, ColorHex(St.OutlineColor), Ord(St.Shadow),
    K, V]) + Ch;
end;

function HueColor(H: Single; Light: Single = 0.45): TBGRAPixel;
var
  HS: THSLAPixel;
begin
  HS.hue := Round(Frac(H) * 65535);
  HS.saturation := 52000;
  HS.lightness := Round(Light * 65535);
  HS.alpha := 65535;
  Result := HSLAToBGRA(HS);
end;

function TGlyphCache.Make(const St: TTextStyle; K: Single; const Ch: string; V: Integer): TGlyph;
var
  Tmp, B, F, Bl: TBGRABitmap;
  Sz: TSize;
  Px, Pad, I, X, Y, SO: Integer;
  Sc, O: Single;
  C: TBGRAPixel;
  P: PBGRAPixel;

  procedure SetFont(Bm: TBGRABitmap);
  begin
    Bm.FontName := St.Font;
    Bm.FontHeight := Px;
    Bm.FontQuality := fqFineAntialiasing;
    Bm.FontStyle := [];
    if St.Bold then Bm.FontStyle := Bm.FontStyle + [fsBold];
    if St.Italic then Bm.FontStyle := Bm.FontStyle + [fsItalic];
  end;

begin
  Sc := 1;
  if V >= VScale0 then Sc := ScaleSteps[EnsureRange(V - VScale0, 0, 3)];
  Px := Max(4, Round(St.Size * K * Sc));
  Tmp := TBGRABitmap.Create(1, 1);
  try
    SetFont(Tmp);
    Sz := Tmp.TextSize(Ch);
  finally
    Tmp.Free;
  end;
  O := St.Outline * K * Sc;
  SO := 0;
  if St.Shadow then SO := Max(1, Round(2.2 * K * Sc));
  Pad := Ceil(O) + 2 + SO;
  if V = VGlow then Pad := Pad + Round(Px * 0.3);
  B := TBGRABitmap.Create(Max(1, Sz.cx + 2 * Pad), Max(1, Sz.cy + 2 * Pad));
  SetFont(B);
  if V = VGlow then
  begin
    // a soft light around the letter
    B.TextOut(Pad, Pad, Ch, St.Color2);
    if O > 0 then
      for I := 0 to 11 do
        B.TextOut(Pad + Cos(I * Pi / 6) * (O + 2), Pad + Sin(I * Pi / 6) * (O + 2), Ch, St.Color2);
    Bl := B.FilterBlurRadial(Max(2, Round(Px * 0.16)), rbFast) as TBGRABitmap;
    B.Free;
    B := Bl;
  end
  else
  begin
    if SO > 0 then B.TextOut(Pad + SO, Pad + SO, Ch, BGRA(0, 0, 0, 80));
    if O > 0 then
      for I := 0 to 15 do
        B.TextOut(Pad + Cos(I * Pi / 8) * O, Pad + Sin(I * Pi / 8) * O, Ch, St.OutlineColor);
    if (V >= VHue0) and (V < VHue0 + 8) then C := HueColor((V - VHue0) / 8) else C := St.Color;
    if St.Gradient and not ((V >= VHue0) and (V < VHue0 + 8)) then
    begin
      // the fill, then a vertical gradient from Color to Color2 over it (alpha kept)
      F := TBGRABitmap.Create(B.Width, B.Height);
      try
        SetFont(F);
        F.TextOut(Pad, Pad, Ch, BGRA(255, 255, 255));
        for Y := 0 to F.Height - 1 do
        begin
          C := MergeBGRA(St.Color, Round(255 * (1 - EnsureRange((Y - Pad) / Max(1, Sz.cy), 0, 1))) + 1,
            St.Color2, Round(255 * EnsureRange((Y - Pad) / Max(1, Sz.cy), 0, 1)) + 1);
          P := F.ScanLine[Y];
          for X := 0 to F.Width - 1 do
          begin
            if P^.alpha > 0 then
            begin
              P^.red := C.red;
              P^.green := C.green;
              P^.blue := C.blue;
            end;
            Inc(P);
          end;
        end;
        F.InvalidateBitmap;
        B.PutImage(0, 0, F, dmDrawWithTransparency);
      finally
        F.Free;
      end;
    end
    else
      B.TextOut(Pad, Pad, Ch, C);
  end;
  B.LoadFromBitmapIfNeeded;
  Result := TGlyph.Create;
  Result.Bmp := B;
  Result.OX := -Pad;
  Result.OY := -Pad;
  Result.Adv := Sz.cx;
  Result.H := Sz.cy;
end;

function TGlyphCache.Find(const St: TTextStyle; K: Single; const Ch: string; V: Integer): TGlyph;
var
  I: Integer;
begin
  if FList.Find(Key(St, K, Ch, V), I) then Result := TGlyph(FList.Objects[I]) else Result := nil;
end;

procedure TGlyphCache.Prepare(const St: TTextStyle; K: Single; const Text: string);
var
  P, PEnd: PChar;
  L, V: Integer;
  Ch, Ky: string;
  Vs: array of Integer;
begin
  SetLength(Vs, 1);
  Vs[0] := 0;
  case St.Fx of
    tfGlow: Vs := [0, VGlow];
    tfRainbow: Vs := [0, VHue0, VHue0 + 1, VHue0 + 2, VHue0 + 3, VHue0 + 4, VHue0 + 5, VHue0 + 6, VHue0 + 7];
    tfPulse, tfZoomWave: Vs := [0, VScale0, VScale0 + 1, VScale0 + 2, VScale0 + 3];
  end;
  P := PChar(Text);
  PEnd := P + Length(Text);
  while P < PEnd do
  begin
    L := Max(1, UTF8CodepointSize(P));
    SetString(Ch, P, L);
    Inc(P, L);
    if (Ch = #9) then Continue;
    for V in Vs do
    begin
      Ky := Key(St, K, Ch, V);
      if FList.IndexOf(Ky) < 0 then FList.AddObject(Ky, Make(St, K, Ch, V));
    end;
  end;
end;

function TGlyphCache.TextWidth(const St: TTextStyle; K: Single; const Text: string): Single;
var
  P, PEnd: PChar;
  L: Integer;
  Ch: string;
  G: TGlyph;
begin
  Result := 0;
  P := PChar(Text);
  PEnd := P + Length(Text);
  while P < PEnd do
  begin
    L := Max(1, UTF8CodepointSize(P));
    SetString(Ch, P, L);
    Inc(P, L);
    G := Find(St, K, Ch, 0);
    if G <> nil then Result := Result + G.Adv;
  end;
end;

function RowPtr(B: TBGRABitmap; Y: Integer): PBGRAPixel; inline;
begin
  if B.LineOrder = riloTopToBottom then Result := B.Data + Y * B.Width
  else Result := B.Data + (B.Height - 1 - Y) * B.Width;
end;

{ a letter onto Dest: only reads the sprite, so many threads may draw the same
  letter at once (TBGRABitmap.PutImage changes the source's scan offset) }
procedure GlyphBlit(Dest: TBGRABitmap; X, Y: Integer; Src: TBGRABitmap; Opacity: Integer);
var
  SX0, SY0, SX1, SY1, YY, XX, SA, DA, W1, W2, WS: Integer;
  S, D: PBGRAPixel;
begin
  if (Src = nil) or (Opacity <= 0) then Exit;
  SX0 := Max(0, -X);
  SY0 := Max(0, -Y);
  SX1 := Min(Src.Width, Dest.Width - X);
  SY1 := Min(Src.Height, Dest.Height - Y);
  if (SX1 <= SX0) or (SY1 <= SY0) then Exit;
  for YY := SY0 to SY1 - 1 do
  begin
    S := RowPtr(Src, YY) + SX0;
    D := RowPtr(Dest, Y + YY) + X + SX0;
    for XX := SX0 to SX1 - 1 do
    begin
      SA := S^.alpha;
      if Opacity < 255 then SA := SA * Opacity div 255;
      if SA = 255 then
        D^ := S^
      else if SA > 0 then
      begin
        DA := D^.alpha;
        if DA = 255 then
        begin
          W2 := 255 - SA;
          D^.red := (S^.red * SA + D^.red * W2) div 255;
          D^.green := (S^.green * SA + D^.green * W2) div 255;
          D^.blue := (S^.blue * SA + D^.blue * W2) div 255;
        end
        else
        begin
          W1 := SA * 255;
          W2 := DA * (255 - SA);
          WS := W1 + W2;
          D^.red := (S^.red * W1 + D^.red * W2) div WS;
          D^.green := (S^.green * W1 + D^.green * W2) div WS;
          D^.blue := (S^.blue * W1 + D^.blue * W2) div WS;
          D^.alpha := WS div 255;
        end;
      end;
      Inc(S);
      Inc(D);
    end;
  end;
end;

procedure Star(Dest: TBGRABitmap; X, Y, R: Single; C: TBGRAPixel);
begin
  Dest.FillPolyAntialias([PointF(X, Y - R), PointF(X + R * 0.25, Y - R * 0.25), PointF(X + R, Y),
    PointF(X + R * 0.25, Y + R * 0.25), PointF(X, Y + R), PointF(X - R * 0.25, Y + R * 0.25), PointF(X - R, Y),
    PointF(X - R * 0.25, Y - R * 0.25)], C);
end;

procedure DrawFxText(Dest: TBGRABitmap; Cache: TGlyphCache; const St: TTextStyle; K, OX, OY, T: Single;
  const Text: string; Align: Integer; Phase: Single);
var
  P, PEnd: PChar;
  L, I, N, V, Shown: Integer;
  Ch: string;
  G, G0: TGlyph;
  X, DX, DY, A, W, S, TT, Am: Single;
begin
  if Text = '' then Exit;
  N := UTF8Length(Text);
  W := Cache.TextWidth(St, K, Text);
  if Align = 1 then X := OX - W / 2 else X := OX;
  TT := T * St.Speed + Phase;
  Am := St.Amount * K;
  Shown := N;
  if St.Fx = tfTypewriter then
    Shown := Trunc(Frac(TT * 0.22) * (N + 10));       // letters appear, wait, start again
  P := PChar(Text);
  PEnd := P + Length(Text);
  I := 0;
  while P < PEnd do
  begin
    L := Max(1, UTF8CodepointSize(P));
    SetString(Ch, P, L);
    Inc(P, L);
    G0 := Cache.Find(St, K, Ch, 0);
    if G0 = nil then
    begin
      Inc(I);
      Continue;
    end;
    DX := 0;
    DY := 0;
    A := 255;
    V := 0;
    case St.Fx of
      tfWave: DY := -6 * Am * Sin(TT * 4 + I * 0.6);
      tfBounce: DY := -10 * Am * Abs(Sin(TT * 3.2 + I * 0.32));
      tfFloat: DY := 4 * Am * Sin(TT * 2);
      tfShake:
        begin
          DX := 1.6 * Am * (H01(Trunc(TT * 18) * 31 + I) - 0.5) * 2;
          DY := 1.6 * Am * (H01(Trunc(TT * 18) * 17 + I * 7) - 0.5) * 2;
        end;
      tfPulse: V := VScale0 + EnsureRange(Round(1.5 + 1.5 * Sin(TT * 3)), 0, 3);
      tfRainbow: V := VHue0 + ((Trunc(TT * 3) + I) mod 8);
      tfTypewriter: if I >= Shown then A := 0 else if I = Shown - 1 then A := 160;
      tfSwing: DX := 4 * Am * Sin(TT * 3 + I * 0.45);
      tfZoomWave: V := VScale0 + EnsureRange(Round(1.5 + 1.5 * Sin(TT * 4 - I * 0.55)), 0, 3);
      tfFadeWave: A := 255 * (1 - 0.4 * Min(1, St.Amount) * (0.5 + 0.5 * Sin(TT * 3 - I * 0.5)));
      tfJelly:
        begin
          DX := 2 * Am * Sin(TT * 6 + I);
          DY := 3 * Am * Cos(TT * 5 + I * 0.7);
        end;
      tfDrop:
        begin
          // letters fall into place one after the other, then rest
          S := EnsureRange(Frac(TT * 0.2) * 6 - I * 0.12, 0, 1);
          DY := -40 * Am * Sqr(1 - S);
          A := 255 * S;
        end;
    end;
    if A > 2 then
    begin
      if St.Fx = tfGlow then
      begin
        G := Cache.Find(St, K, Ch, VGlow);
        if G <> nil then
          GlyphBlit(Dest, Round(X + G.OX + DX), Round(OY + G.OY + DY), G.Bmp,
            Round(EnsureRange(110 + 110 * Sin(TT * 3 + I * 0.2), 0, 255) * Min(1, St.Amount)));
      end;
      G := G0;
      if V <> 0 then
      begin
        G := Cache.Find(St, K, Ch, V);
        if G = nil then G := G0;
      end;
      // a scaled letter stays centred on its place
      GlyphBlit(Dest, Round(X + (G0.Adv - G.Adv) / 2 + G.OX + DX), Round(OY + (G0.H - G.H) / 2 + G.OY + DY), G.Bmp,
        Round(EnsureRange(A, 0, 255)));
      if (St.Fx = tfSparkle) and (H01(I * 13 + Trunc(TT * 2.5)) < 0.22) then
      begin
        S := Frac(TT * 2.5);
        Star(Dest, X + G0.Adv * H01(I * 5 + Trunc(TT * 2.5)), OY + G0.H * (0.15 + 0.5 * H01(I * 3)),
          (3 + 5 * Sin(S * Pi)) * K * Min(1.5, St.Amount), BGRA(255, 250, 220, Round(230 * Sin(S * Pi))));
      end;
    end;
    X := X + G0.Adv;
    Inc(I);
  end;
end;

{ ---------- frames ---------- }

procedure DrawFrameStatic(B: TBGRABitmap; const F: TFrameStyle; OX, OY, W, H, K: Single; TitleY: Single);
var
  C, C2, Pale: TBGRAPixel;
  I, Side, J: Integer;
  A, Len, X, Y, R: Single;
  Pts: array of TPointF;

  function Px(X: Single): Single;
  begin
    Result := OX + X * K;
  end;

  function Py(Y: Single): Single;
  begin
    Result := OY + Y * K;
  end;

  { a point at A along side Sd and Bb inwards from the band's edge E }
  function Q(Sd: Integer; AA, BB, E: Single): TPointF;
  begin
    case Sd of
      0: Result := PointF(Px(AA), Py(E + BB));
      1: Result := PointF(Px(AA), Py(H - E - BB));
      2: Result := PointF(Px(E + BB), Py(AA));
    else
      Result := PointF(Px(W - E - BB), Py(AA));
    end;
  end;

  procedure Border(Inset, Width: Single; Col: TBGRAPixel; Round_: Single = 6);
  begin
    B.RoundRectAntialias(Px(Inset), Py(Inset), Px(W - Inset), Py(H - Inset), Round_ * K, Round_ * K, Col,
      Max(1, Width * K));
  end;

  procedure Ruyi(X, Y: Single);
  begin
    B.FillEllipseAntialias(Px(X), Py(Y), 11 * K, 11 * K, C);
    B.FillEllipseAntialias(Px(X - 9), Py(Y), 6 * K, 6 * K, C);
    B.FillEllipseAntialias(Px(X + 9), Py(Y), 6 * K, 6 * K, C);
    B.FillEllipseAntialias(Px(X), Py(Y - 9), 6 * K, 6 * K, C);
    B.FillEllipseAntialias(Px(X), Py(Y + 9), 6 * K, 6 * K, C);
    B.FillPolyAntialias([PointF(Px(X), Py(Y - 7)), PointF(Px(X + 7), Py(Y)), PointF(Px(X), Py(Y + 7)),
      PointF(Px(X - 7), Py(Y))], Pale);
    B.FillEllipseAntialias(Px(X), Py(Y), 2.6 * K, 2.6 * K, C2);
  end;

  procedure Flower(X, Y, R: Single);
  var
    P: Integer;
  begin
    for P := 0 to 4 do
      B.FillEllipseAntialias(Px(X + Cos(P * 2 * Pi / 5 - Pi / 2) * R * 0.9), Py(Y + Sin(P * 2 * Pi / 5 - Pi / 2) * R * 0.9),
        R * 0.62 * K, R * 0.62 * K, BGRA(236, 150, 170));
    B.FillEllipseAntialias(Px(X), Py(Y), R * 0.4 * K, R * 0.4 * K, C2);
  end;

begin
  C := F.Color;
  C2 := F.Color2;
  Pale := F.Paper;
  Pale.alpha := 255;
  case F.Kind of
    fkChinese:
      begin
        Border(9, 2.2, C);
        B.RectangleAntialias(Px(30), Py(30), Px(W - 30), Py(H - 30), BGRA(C.red, C.green, C.blue, 150), Max(1, K));
        SetLength(Pts, 9);
        for Side := 0 to 3 do
        begin
          if Side < 2 then Len := W else Len := H;
          A := 36;
          while A + 11 < Len - 36 do
          begin
            Pts[0] := Q(Side, A, 11, 14);
            Pts[1] := Q(Side, A, 0, 14);
            Pts[2] := Q(Side, A + 11, 0, 14);
            Pts[3] := Q(Side, A + 11, 8.6, 14);
            Pts[4] := Q(Side, A + 3.1, 8.6, 14);
            Pts[5] := Q(Side, A + 3.1, 3.3, 14);
            Pts[6] := Q(Side, A + 7.5, 3.3, 14);
            Pts[7] := Q(Side, A + 7.5, 6, 14);
            Pts[8] := Q(Side, A + 5.5, 6, 14);
            B.DrawPolyLineAntialias(Pts, C, Max(1, 1.3 * K), False);
            B.DrawLineAntialias(Pts[0].X, Pts[0].Y, Q(Side, A + 14.85, 11, 14).X, Q(Side, A + 14.85, 11, 14).Y, C,
              Max(1, 1.3 * K));
            A := A + 14.85;
          end;
        end;
        Ruyi(21, 21);
        Ruyi(W - 21, 21);
        Ruyi(21, H - 21);
        Ruyi(W - 21, H - 21);
      end;
    fkCloud:
      begin
        Border(9, 2, C);
        Border(28, 1, BGRA(C.red, C.green, C.blue, 140));
        // rows of curling cloud scrolls along the edges
        for Side := 0 to 3 do
        begin
          if Side < 2 then Len := W else Len := H;
          A := 40;
          while A < Len - 40 do
          begin
            X := Q(Side, A, 4.5, 14).X;
            Y := Q(Side, A, 4.5, 14).Y;
            B.EllipseAntialias(X, Y, 6 * K, 4.5 * K, C, Max(1, 1.2 * K));
            B.EllipseAntialias(X + 2 * K, Y, 2.5 * K, 2 * K, C2, Max(1, K));
            A := A + 18;
          end;
        end;
        for I := 0 to 3 do
        begin
          if I mod 2 = 0 then X := 24 else X := W - 24;
          if I < 2 then Y := 24 else Y := H - 24;
          B.FillEllipseAntialias(Px(X), Py(Y), 12 * K, 9 * K, C);
          B.FillEllipseAntialias(Px(X - 8), Py(Y + 3), 7 * K, 6 * K, C);
          B.FillEllipseAntialias(Px(X + 8), Py(Y + 3), 7 * K, 6 * K, C);
          B.FillEllipseAntialias(Px(X), Py(Y), 4 * K, 3 * K, C2);
        end;
      end;
    fkBamboo:
      begin
        // four bamboo canes as the frame, with nodes and leaves at the corners
        for Side := 0 to 3 do
        begin
          case Side of
            0: B.FillRectAntialias(Px(10), Py(10), Px(W - 10), Py(19), C);
            1: B.FillRectAntialias(Px(10), Py(H - 19), Px(W - 10), Py(H - 10), C);
            2: B.FillRectAntialias(Px(10), Py(10), Px(19), Py(H - 10), C);
          else
            B.FillRectAntialias(Px(W - 19), Py(10), Px(W - 10), Py(H - 10), C);
          end;
          if Side < 2 then Len := W else Len := H;
          A := 60;
          while A < Len - 30 do
          begin
            case Side of
              0: B.FillRectAntialias(Px(A), Py(9), Px(A + 3), Py(20), C2);
              1: B.FillRectAntialias(Px(A), Py(H - 20), Px(A + 3), Py(H - 9), C2);
              2: B.FillRectAntialias(Px(9), Py(A), Px(20), Py(A + 3), C2);
            else
              B.FillRectAntialias(Px(W - 20), Py(A), Px(W - 9), Py(A + 3), C2);
            end;
            A := A + 70;
          end;
        end;
        for I := 0 to 3 do
        begin
          if I mod 2 = 0 then X := 16 else X := W - 16;
          if I < 2 then Y := 16 else Y := H - 16;
          for J := 0 to 2 do
            B.FillPolyAntialias([PointF(Px(X), Py(Y)), PointF(Px(X + Cos(J * 0.9 + I * 1.6) * 34), Py(Y + Sin(J * 0.9 + I * 1.6) * 34)),
              PointF(Px(X + Cos(J * 0.9 + I * 1.6 + 0.25) * 18), Py(Y + Sin(J * 0.9 + I * 1.6 + 0.25) * 18))], C2);
        end;
        B.RectangleAntialias(Px(26), Py(26), Px(W - 26), Py(H - 26), BGRA(C.red, C.green, C.blue, 120), Max(1, K));
      end;
    fkPlum:
      begin
        Border(10, 1.6, C);
        // a plum branch from two corners with pink blossoms
        for I := 0 to 1 do
        begin
          if I = 0 then begin X := 12; Y := 12; end else begin X := W - 12; Y := H - 12; end;
          SetLength(Pts, 4);
          for J := 0 to 3 do
            Pts[J] := PointF(Px(X + (1 - 2 * I) * J * 52), Py(Y + (1 - 2 * I) * (J * 14 + 6 * Sin(J * 2.1))));
          B.DrawPolyLineAntialias(Pts, BGRA(90, 56, 40), Max(1, 3 * K));
          B.DrawLineAntialias(Pts[1].X, Pts[1].Y, Px(X + (1 - 2 * I) * 70), Py(Y + (1 - 2 * I) * 48), BGRA(90, 56, 40),
            Max(1, 2 * K));
          for J := 0 to 3 do
            Flower(X + (1 - 2 * I) * (24 + J * 46), Y + (1 - 2 * I) * (10 + J * 14 + 6 * Sin(J * 2.1)) - 4, 7);
          Flower(X + (1 - 2 * I) * 70, Y + (1 - 2 * I) * 48, 6);
        end;
      end;
    fkLattice:
      begin
        Border(8, 2.4, C);
        Border(32, 1.6, C);
        // a window lattice band: squares and their diagonals
        for Side := 0 to 3 do
        begin
          if Side < 2 then Len := W else Len := H;
          A := 8;
          while A < Len - 8 do
          begin
            B.DrawLineAntialias(Q(Side, A, 0, 8).X, Q(Side, A, 0, 8).Y, Q(Side, A, 24, 8).X, Q(Side, A, 24, 8).Y, C,
              Max(1, K));
            B.DrawLineAntialias(Q(Side, A, 0, 8).X, Q(Side, A, 0, 8).Y, Q(Side, A + 12, 12, 8).X, Q(Side, A + 12, 12, 8).Y,
              BGRA(C.red, C.green, C.blue, 130), Max(1, K));
            B.DrawLineAntialias(Q(Side, A + 24, 0, 8).X, Q(Side, A + 24, 0, 8).Y, Q(Side, A + 12, 12, 8).X,
              Q(Side, A + 12, 12, 8).Y, BGRA(C.red, C.green, C.blue, 130), Max(1, K));
            A := A + 24;
          end;
        end;
        for I := 0 to 3 do
        begin
          if I mod 2 = 0 then X := 20 else X := W - 20;
          if I < 2 then Y := 20 else Y := H - 20;
          B.FillRectAntialias(Px(X - 9), Py(Y - 9), Px(X + 9), Py(Y + 9), C);
          B.FillEllipseAntialias(Px(X), Py(Y), 4 * K, 4 * K, C2);
        end;
      end;
    fkDouble:
      begin
        Border(10, 1.8, C);
        Border(17, 0.9, C);
        for I := 0 to 3 do
        begin
          if I mod 2 = 0 then X := 13.5 else X := W - 13.5;
          if I < 2 then Y := 13.5 else Y := H - 13.5;
          B.FillEllipseAntialias(Px(X), Py(Y), 5 * K, 5 * K, C2);
        end;
      end;
    fkImperial:
      begin
        Border(6, 5, C2, 8);
        Border(13, 2.2, C, 6);
        // dragon scales: rows of half circles in gold
        for Side := 0 to 3 do
        begin
          if Side < 2 then Len := W else Len := H;
          A := 30;
          while A < Len - 30 do
          begin
            R := 5;
            X := Q(Side, A, 5, 16).X;
            Y := Q(Side, A, 5, 16).Y;
            B.EllipseAntialias(X, Y, R * K, R * K, C2, Max(1, 1.2 * K));
            A := A + 10;
          end;
        end;
        Border(26, 1.2, C2, 4);
        for I := 0 to 3 do
        begin
          if I mod 2 = 0 then X := 16 else X := W - 16;
          if I < 2 then Y := 16 else Y := H - 16;
          B.FillEllipseAntialias(Px(X), Py(Y), 10 * K, 10 * K, C);
          Star(B, Px(X), Py(Y), 8 * K, C2);
        end;
      end;
    fkScallop:
      begin
        // papercut scallops: a red band with half circles cut out, dots inside
        B.FillRoundRectAntialias(Px(6), Py(6), Px(W - 6), Py(H - 6), 10 * K, 10 * K, C);
        B.FillRoundRectAntialias(Px(16), Py(16), Px(W - 16), Py(H - 16), 6 * K, 6 * K, Pale);
        for Side := 0 to 3 do
        begin
          if Side < 2 then Len := W else Len := H;
          A := 24;
          while A < Len - 20 do
          begin
            B.FillEllipseAntialias(Q(Side, A, 0, 16).X, Q(Side, A, 0, 16).Y, 5 * K, 5 * K, Pale);
            B.FillEllipseAntialias(Q(Side, A + 8, -5, 16).X, Q(Side, A + 8, -5, 16).Y, 1.6 * K, 1.6 * K, C2);
            A := A + 16;
          end;
        end;
        B.RectangleAntialias(Px(26), Py(26), Px(W - 26), Py(H - 26), BGRA(C.red, C.green, C.blue, 120), Max(1, K));
      end;
    fkPlain:
      Border(9, 1.2, BGRA(C.red, C.green, C.blue, 150));
  end;
  // a knot under the title
  if (TitleY > 0) and (F.Kind <> fkPlain) then
  begin
    B.DrawLineAntialias(Px(W / 2 - 150), Py(TitleY), Px(W / 2 - 16), Py(TitleY), BGRA(C.red, C.green, C.blue, 170),
      Max(1, 1.2 * K));
    B.DrawLineAntialias(Px(W / 2 + 16), Py(TitleY), Px(W / 2 + 150), Py(TitleY), BGRA(C.red, C.green, C.blue, 170),
      Max(1, 1.2 * K));
    for I := -1 to 1 do
      B.FillPolyAntialias([PointF(Px(W / 2 + I * 150), Py(TitleY - 6)), PointF(Px(W / 2 + I * 150 + 6), Py(TitleY)),
        PointF(Px(W / 2 + I * 150), Py(TitleY + 6)), PointF(Px(W / 2 + I * 150 - 6), Py(TitleY))], C);
    B.FillEllipseAntialias(Px(W / 2), Py(TitleY), 4 * K, 4 * K, C2);
  end;
end;

{ a point at distance D around the frame's perimeter (inset In) }
function Around(D, W, H, Inset: Single): TPointF;
var
  L: Single;
begin
  L := 2 * (W + H - 4 * Inset);
  D := D - Floor(D / L) * L;
  if D < W - 2 * Inset then Exit(PointF(Inset + D, Inset));
  D := D - (W - 2 * Inset);
  if D < H - 2 * Inset then Exit(PointF(W - Inset, Inset + D));
  D := D - (H - 2 * Inset);
  if D < W - 2 * Inset then Exit(PointF(W - Inset - D, H - Inset));
  D := D - (W - 2 * Inset);
  Result := PointF(Inset, H - Inset - D);
end;

procedure DrawFrameFx(Dest: TBGRABitmap; const F: TFrameStyle; OX, OY, W, H, K, T: Single);
var
  I, N, M: Integer;
  TT, Am, X, Y, A, S, L: Single;
  P: TPointF;
  C: TBGRAPixel;
begin
  TT := T * F.Speed;
  Am := Max(0, F.Amount);
  case F.Fx of
    ffGlow:
      for I := 0 to 3 do
      begin
        A := (0.5 + 0.5 * Sin(TT * 2.4)) * Min(1, Am);
        Dest.RoundRectAntialias(OX + (4 - I * 2) * K, OY + (4 - I * 2) * K, OX + (W - 4 + I * 2) * K,
          OY + (H - 4 + I * 2) * K, 12 * K, 12 * K, BGRA(F.Color2.red, F.Color2.green, F.Color2.blue,
          Round(A * (110 - I * 25))), Max(1, 2.5 * K));
      end;
    ffRunLight:
      begin
        // lamps run round the frame, a bright head and a fading tail
        L := 2 * (W + H - 36);
        N := 6;
        for I := 0 to N - 1 do
          for M := 0 to 7 do
          begin
            P := Around(TT * 160 + I * L / N - M * 9, W, H, 9);
            S := (8 - M) / 8;
            Dest.FillEllipseAntialias(OX + P.X * K, OY + P.Y * K, (2 + 2.5 * S) * K * Max(0.5, Am),
              (2 + 2.5 * S) * K * Max(0.5, Am), BGRA(F.Color2.red, F.Color2.green, F.Color2.blue, Round(230 * S)));
          end;
      end;
    ffCornerSpin:
      for I := 0 to 3 do
      begin
        if I mod 2 = 0 then X := 21 else X := W - 21;
        if I < 2 then Y := 21 else Y := H - 21;
        A := TT * 2 + I;
        for N := 0 to 5 do
          Dest.FillPolyAntialias([PointF(OX + X * K, OY + Y * K),
            PointF(OX + (X + Cos(A + N * Pi / 3) * 16 * Max(0.5, Am)) * K, OY + (Y + Sin(A + N * Pi / 3) * 16 * Max(0.5, Am)) * K),
            PointF(OX + (X + Cos(A + N * Pi / 3 + 0.45) * 9 * Max(0.5, Am)) * K, OY + (Y + Sin(A + N * Pi / 3 + 0.45) * 9 * Max(0.5, Am)) * K)],
            IfThen(Odd(N), F.Color, F.Color2));
        Dest.FillEllipseAntialias(OX + X * K, OY + Y * K, 3.5 * K, 3.5 * K, F.Paper);
      end;
    ffPetals:
      for I := 0 to Round(14 * Max(0.3, Am)) - 1 do
      begin
        // plum petals drift down over the card and loop
        S := Frac(TT * 0.09 * (0.7 + 0.6 * H01(I * 3)) + H01(I * 7));
        X := W * H01(I * 11) + 40 * Sin(TT * 0.8 + I) + S * 60;
        Y := -10 + (H + 20) * S;
        if (X < 6) or (X > W - 6) then Continue;
        A := TT * 2 + I;
        Dest.FillEllipseAntialias(OX + X * K, OY + Y * K, 5 * K * (0.6 + 0.4 * Abs(Cos(A))), 3.2 * K,
          BGRA(240, 150, 172, 210));
      end;
    ffSparkle:
      for I := 0 to Round(16 * Max(0.3, Am)) - 1 do
      begin
        S := Frac(TT * 0.7 + H01(I * 5));
        P := Around(H01(I * 9 + Trunc(TT * 0.7 + H01(I * 5))) * 2 * (W + H), W, H, 14);
        Star(Dest, OX + P.X * K, OY + P.Y * K, (3 + 7 * Sin(S * Pi)) * K, BGRA(F.Color2.red, F.Color2.green,
          F.Color2.blue, Round(240 * Sin(S * Pi))));
      end;
    ffBreath:
      begin
        S := 0.5 + 0.5 * Sin(TT * 1.8);
        C := MergeBGRA(F.Color, Round(255 * (1 - S)) + 1, F.Color2, Round(255 * S) + 1);
        Dest.RoundRectAntialias(OX + 9 * K, OY + 9 * K, OX + (W - 9) * K, OY + (H - 9) * K, 6 * K, 6 * K, C,
          Max(1, (1.5 + 2.5 * S * Max(0.3, Am)) * K));
      end;
    ffRipple:
      for I := 0 to 2 do
      begin
        S := Frac(TT * 0.5 + I / 3);
        Dest.RoundRectAntialias(OX - S * 26 * K, OY - S * 26 * K, OX + (W + S * 26) * K, OY + (H + S * 26) * K,
          (14 + S * 20) * K, (14 + S * 20) * K, BGRA(F.Color.red, F.Color.green, F.Color.blue,
          Round(150 * (1 - S) * Min(1, Am))), Max(1, 2 * K));
      end;
    ffLanterns:
      for I := 0 to 1 do
      begin
        // two red lanterns hang from the top corners and swing
        X := 40 + I * (W - 80);
        A := 0.25 * Sin(TT * 1.6 + I * 1.3) * Max(0.3, Am);
        Y := 34;
        P := PointF(X + Sin(A) * 40, Y + Cos(A) * 40);
        Dest.DrawLineAntialias(OX + X * K, OY + 6 * K, OX + P.X * K, OY + P.Y * K, BGRA(120, 80, 40), Max(1, 1.2 * K));
        Dest.FillEllipseAntialias(OX + P.X * K, OY + (P.Y + 14) * K, 14 * K, 17 * K, F.Color);
        Dest.FillEllipseAntialias(OX + P.X * K, OY + (P.Y + 14) * K, 6 * K, 13 * K, BGRA(255, 190, 90, 150));
        Dest.FillRectAntialias(OX + (P.X - 7) * K, OY + (P.Y - 4) * K, OX + (P.X + 7) * K, OY + P.Y * K, F.Color2);
        Dest.FillRectAntialias(OX + (P.X - 7) * K, OY + (P.Y + 29) * K, OX + (P.X + 7) * K, OY + (P.Y + 33) * K, F.Color2);
        Dest.DrawLineAntialias(OX + P.X * K, OY + (P.Y + 33) * K, OX + (P.X + Sin(A) * 4) * K, OY + (P.Y + 46) * K,
          F.Color2, Max(1, 1.5 * K));
      end;
  end;
end;

end.
