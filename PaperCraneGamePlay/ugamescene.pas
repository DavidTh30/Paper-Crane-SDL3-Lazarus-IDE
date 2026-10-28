unit uGameScene;

{ Paper Crane - a papercut side-scrolling flying game.

  You fly a folded paper crane up the Li river through the karst mountains.
  Space / Up / W / a mouse click beats the wings. Fly through the gaps between
  the stone pillars rising from the river and the rocks hanging from the sky,
  collect red lanterns, keep away from the hawks. The river runs faster the
  further you get. Three lives; the best score is kept in papercrane_best.txt.

  The world is cut paper (shared engine with the papercut scenes): flat paper
  colours, grain, a soft shadow under every sheet. The far and middle ranges
  are TILEABLE paper strips cut once per window size and palette and scrolled
  with parallax; pillars, rocks, lanterns, hawks and the crane are live paper
  with a live shadow; lights ADD light. Morning, day and night follow each other
  while you fly (or M / D / N / A); 1-4 choose summer, rainy, autumn, winter.

  Game states: TITLE (an autopilot flies behind the title card), PLAY, DYING
  (the crane tumbles into the river), OVER (score card). All game logic runs in
  Update on the main thread; workers only read the state. }

{$mode objfpc}{$H+}
{$INLINE ON}

interface

uses
  Classes, SysUtils, StrUtils, Math, Graphics, BGRABitmap, BGRABitmapTypes,
  BGRAGradientScanner, uRenderPool, uSvgRecorder, uPCMap, uPCShape, uPlayer, uPCMenuFx;

const
  DesignW = 1600;
  DesignH = 900;
  Period = 1600;     // design width of one tile of the scrolling ranges
  Base0 = 520;       // foot of the far range
  Base1 = 612;       // foot of the middle range
  RiverTop = 790;
  RiverBot = 905;
  WaterY = 826;      // pillars stand here; the crane drowns below it
  CraneX = 360;
  Par0 = 0.12;       // parallax of the far range
  Par1 = 0.3;        // middle range
  SpriteKinds = 1;
  MaxDepth = 0.9;
  ModeCount = 3;
  ModeNames: array[0..2] of string = ('Morning', 'Day', 'Night');
  ModeNight: array[0..2] of Single = (0.3, 0, 1);
  ModeShade: array[0..2] of Single = (0.88, 1, 0.5);
  SeasonCount = 4;
  SeasonNames: array[0..3] of string = ('Summer', 'Rainy', 'Autumn', 'Winter');
  StateNames: array[0..3] of string = ('Title', 'Play', 'Dying', 'Game over');
  gsTitle = 0;
  gsPlay = 1;
  gsDying = 2;
  gsOver = 3;
  { input codes (the window maps keys to these) }
  gkUp = 1;
  gkDown = 2;
  gkLeft = 3;
  gkRight = 4;
  gkOk = 5;
  gkBack = 6;
  gkFlap = 7;
  gkErase = 8;         // Backspace: deletes a letter while a name is typed
  { menu screens }
  msNone = 0;
  msMain = 1;
  msPause = 2;
  msOver = 3;
  msSettings = 4;
  msHelp = 5;
  msScores = 6;
  msCredits = 7;
  msMaps = 8;          // custom maps
  msSaves = 9;         // saved games
  msSaveItem = 10;     // one saved game: continue / delete
  msGhosts = 11;       // ghosts
  msGhostItem = 12;    // one ghost: replay / race / delete
  msPlayers = 13;      // the players: choose one or make a new one
  msPlayerItem = 14;   // one player: fly, character, statistics, delete
  msNewName = 15;      // typing a new player's name
  msCharacter = 16;    // choosing the character
  msStats = 17;        // the player's statistics
  msSelect = 18;       // Select Paper card: every player as a paper card (always before the main menu)
  MenuNames: array[0..18] of string = ('none', 'Main menu', 'Pause', 'Game over', 'Settings',
    'How to play', 'High scores', 'Credits', 'Custom maps', 'Saved games', 'Saved game', 'Ghosts', 'Ghost',
    'Players', 'Player', 'New player', 'Character', 'Statistics', 'Select Paper card');
  SelVisible = 5;      // paper cards shown at once
  SelCardW = 250;
  SelCardH = 372;
  SelGap = 34;
  SelY = 270;
  SelQuitY = 690;      // the Quit button under the cards (first entry only)
  SelQuitW = 220;
  SelQuitH = 54;
  ListRows = 8;        // entries shown at once in a list menu
  GhostRate = 30;      // ghost samples per second
  DiffNames: array[0..2] of string = ('Easy', 'Normal', 'Hard');
  DiffSpeed: array[0..2] of Single = (0.85, 1, 1.15);
  DiffGap: array[0..2] of Single = (55, 0, -25);
  DiffHawk: array[0..2] of Single = (0.5, 1, 1.5);
  DiffLives: array[0..2] of Integer = (5, 3, 2);
  TimeChoiceNames: array[0..3] of string = ('Auto cycle', 'Morning', 'Day', 'Night');

type
  TLayerId = (lySky, lyStars, lyClouds, lyFarPeaks, lyMist, lyMidPeaks, lyRiver, lyObstacles,
    lyLanterns, lyHawks, lyPlayer, lyParticles, lyWeather, lyHUD, lyCaption);

const
  LayerNames: array[TLayerId] of string = ('Sky', 'Stars', 'Clouds', 'Far peaks', 'Mist',
    'Middle peaks', 'River', 'Obstacles', 'Lanterns', 'Hawks', 'Crane', 'Particles', 'Weather',
    'HUD', 'Screen card');
  LayerKinds: array[TLayerId] of string = ('paper x3', 'vector', 'paper sprites x3',
    'paper strip x3', 'live strips', 'paper strip x3', 'paper+strips', 'live paper', 'live paper+light',
    'live paper', 'live paper', 'light', 'live', 'sprite', 'sprite');
  LayerDepth: array[TLayerId] of Single = (0.3, 0, 0.5, 0.3, 0, 0.4, 0.35, 0.8, 0.5, 0.6, 0.7,
    0, 0, 0, 0);
  LayerNotes: array[TLayerId] of string = (
    '7 wavy paper bands, paper rings round the sun / moon (overcast when rainy)',
    'Stars twinkling at night (not when it rains)',
    'Paper clouds drifting slower than the river (parallax 0.2)',
    'Far karst range: a tileable paper strip scrolled at 0.12 of the speed',
    'Mist strips at three heights, scrolling with their range',
    'Middle range: a tileable paper strip scrolled at 0.3 of the speed',
    'River water and 4 paper wave strips moving with the speed',
    'Stone pillars from the river and rocks hanging from the sky, with gaps to fly through',
    'Red lanterns to collect (+5), glowing at night',
    'Hawks swooping in waves against the flight',
    'The paper crane: wing beats, tilt with the climb, blinking after a hit',
    'Sparks of collected lanterns and paper scraps of hits',
    'Fireflies (summer night), rain + lightning, falling leaves, snow',
    'Score, best, lanterns, lives, distance, season',
    'Title / pause / game over card');

  PaletteNames: array[0..15] of string = ('Day sky top', 'Day horizon', 'Night sky top',
    'Night horizon', 'Far peaks', 'Middle peaks', 'Pillars', 'Water', 'Crane paper', 'Crane crown',
    'Lantern red', 'Hawk', 'Autumn red', 'Autumn gold', 'Snow', 'Card');
  PaletteHex: array[0..15] of string = ('#3C86D0', '#CFE8F2', '#070B1C', '#22305A', '#B4D2CC',
    '#88B8AC', '#5A9484', '#5AA0B8', '#F6F2EA', '#D42A20', '#C8302A', '#5A4030', '#C8462A',
    '#E8A830', '#F2F6FA', '#F6EEDE');

type
  TPal = record
    SkyTop, SkyBot, Glow, SunC, Haze, Water1, Water2, Foliage, Foliage2, Snow, CloudLit,
    CloudShade, Lit, Rock: TBGRAPixel;
    Range: array[0..2] of TBGRAPixel;  // far, middle, pillars
    SunX, SunY, SunR, MistK, Shade: Single;
    Moon, SunHidden: Boolean;
  end;

  TPeak = record
    C, W, H: Single;
  end;

  TCloud = record
    Puffs: array of Single;
    MinX, MaxX, MinY, MaxY, OX, Speed: Single;
    Sprite: array[0..2] of TBGRABitmap;
    Svg: array[0..2] of string;
  end;

  TStar = record
    X, Y, R, Phase: Single;
  end;

  { one obstacle: a pillar from the river and / or a rock from the sky, with a gap }
  TObstacle = record
    X, W, GapY, Gap: Single;
    HasTop, HasBottom, Passed: Boolean;
    Seed: Integer;
  end;

  TItem = record           // lantern, hawk or bonus
    X, Y, Phase: Single;
    Alive: Boolean;
    Kind: Integer;         // bonus: 0 heart, 1 slow-down
  end;

  THazard = record         // swing, bamboo, cloud, pinwheel, koi (O.D = world x)
    O: TMapObj;
    Passed: Boolean;
  end;

  TScoreRec = record
    Score, Dist, Lanterns, Season, Difficulty: Integer;
    When: string;
  end;

  TInputEv = record
    Kind, Code: Integer;      // 0 key, 1 mouse move, 2 mouse click
    X, Y: Single;             // window pixels
  end;

  TShapeInst = record     // a paper shape placed in a map
    X, Y, Scale: Single;  // world distance, anchor height
    Flip, Solid: Boolean;
    Lib: Integer;         // index in the map's shape library
  end;

  TParticle = record
    X, Y, VX, VY, Life, MaxLife, Size, Spin: Single;
    Kind: Integer;         // 0 spark (light), 1 paper scrap
    C: TBGRAPixel;
  end;

  TGameScene = class;

  TDrawProc = procedure(B: TBGRABitmap) of object;

  TPainter = class
  private
    FScene: TGameScene;
    FLayer: TBGRABitmap;
    FOrgX, FOrgY: Single;
    FTargetH: Integer;
    FPts: array of TPointF;
    FSvg: TSvgRecorder;
    FRaster: Boolean;
    FLayerTop: Integer;
    FRowA, FRowB: Integer;
    FSvgMark: Integer;
    FPart: Integer;
    FShadow, FBlurTmp, FRow: array of Single;
    FColT, FColB: array of Single;   // EdgeFill / EdgeBand column edges (one painter per worker)
    FXIdx: array of Integer;
    FXFrac: array of Single;
    procedure BeginLayer;
    procedure CompositeLayer(Dest: TBGRABitmap; DestTop: Integer; Depth: Single);
    procedure SvgLayerEnd(Depth: Single);
    function P(X, Y: Single): TPointF; inline;
    function S(V: Single): Single; inline;
    function RowsHit(Y0, Y1: Single): Boolean; inline;
    procedure TargetBand(ATop, AHeight: Integer);
    procedure DPoly(B: TBGRABitmap; const Pts: array of TPointF; C: TBGRAPixel);
    procedure DPolyG(B: TBGRABitmap; const Pts: array of TPointF; const G: TGrad);
    procedure DEllipse(B: TBGRABitmap; X, Y, RX, RY: Single; C: TBGRAPixel);
    procedure DEllipseG(B: TBGRABitmap; X, Y, RX, RY: Single; const G: TGrad);
    procedure DPolyLine(B: TBGRABitmap; const Pts: array of TPointF; C: TBGRAPixel; W: Single);
    procedure DLine(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel; W: Single);
    procedure DRect(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel);
    procedure DRadialRect(B: TBGRABitmap; X1, Y1, X2, Y2: Integer; C1, C2: TBGRAPixel;
      Ctr, Edge: TPointF);
    procedure Glow(B: TBGRABitmap; X, Y, R: Single; C: TBGRAPixel);
    procedure HDash(B: TBGRABitmap; X, Y, Len, Thick: Single; C: TBGRAPixel);
    procedure RainStreak(B: TBGRABitmap; X, Y, DX, Len, Thick: Single; C: TBGRAPixel);
    procedure EdgeFill(B: TBGRABitmap; const Edge: array of TPointF; ShiftX, Off, Thick, YBot: Single;
      C: TBGRAPixel);
    procedure Box(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel);
    procedure Ell(B: TBGRABitmap; X, Y, RX, RY: Single; C: TBGRAPixel);
    procedure Ln(B: TBGRABitmap; X1, Y1, X2, Y2, W: Single; C: TBGRAPixel);
    procedure EdgeBand(B: TBGRABitmap; const TopE, BotE: array of TPointF; C: TBGRAPixel);
    procedure Rot(B: TBGRABitmap; const Local: array of TPointF; CX, CY, A, K: Single; C: TBGRAPixel);
    { paper peaks: a karst pillar (Up) or a rock hanging from the sky (not Up) }
    procedure CutPeak(B: TBGRABitmap; C, W, H, Base: Single; Up: Boolean; Col: TBGRAPixel;
      const Pal: TPal; Detail: Integer; Seed: Integer);
    { live parts }
    procedure DrawStars(Dest: TBGRABitmap);
    procedure DrawClouds(Dest: TBGRABitmap);
    procedure DrawMist(Dest: TBGRABitmap; Level: Integer);
    procedure DrawWaves(Dest: TBGRABitmap);
    procedure DrawObstacles(Dest: TBGRABitmap);
    procedure DrawLanterns(Dest: TBGRABitmap);
    procedure DrawHawks(Dest: TBGRABitmap);
    procedure DrawHazards(Dest: TBGRABitmap);
    procedure DrawBonus(Dest: TBGRABitmap);
    procedure DrawCrane(Dest: TBGRABitmap);
    procedure DrawCharacter(Dest: TBGRABitmap; Ch: Integer; X, Y, A, K, Up, Sh: Single);
    procedure DrawCharBoard(Dest: TBGRABitmap);
    procedure DrawSelectCards(Dest: TBGRABitmap);
    procedure DrawMenuTexts(Dest: TBGRABitmap);
    procedure COval(B: TBGRABitmap; CX, CY, RX, RY, X, Y, A, K: Single; C: TBGRAPixel);
    procedure DrawDragon(Dest: TBGRABitmap; X, Y, A, K, Up, Sh: Single);
    procedure DrawPanda(Dest: TBGRABitmap; X, Y, A, K, Up, Sh: Single);
    procedure DrawOwl(Dest: TBGRABitmap; X, Y, A, K, Up, Sh: Single);
    procedure DrawPhoenix(Dest: TBGRABitmap; X, Y, A, K, Up, Sh: Single);
    procedure DrawGhost(Dest: TBGRABitmap);
    procedure DrawParticles(Dest: TBGRABitmap);
    procedure DrawWeather(Dest: TBGRABitmap);
  public
    LayerMs: array[TLayerId] of Double;
    constructor Create(AScene: TGameScene);
    destructor Destroy; override;
    procedure ResetStats;
    procedure RenderBand(Dest: TBGRABitmap; ATop: Integer);
  end;

  { TGameScene }

  TGameScene = class
  private
    FWidth, FHeight: Integer;
    FVisL, FVisR: Single;
    FScale, FOffX, FOffY: Single;
    FPal: array[0..2] of TPal;
    FSky, FR0, FR1, FRiver: array[0..2] of TBGRABitmap;
    FR0Pos, FR1Pos, FRiverPos: TPoint;  // Y only for the strips
    FSvgSky, FSvgR0, FSvgR1, FSvgRiver: array[0..2] of string;
    FStripW, FStripPad: Integer;         // pixel width of one strip tile, cut margin
    FCaption: TBGRABitmap;
    FSvgCaption: string;
    FAcc: TBGRABitmap;
    FCutter: TPainter;
    FRecordSvg: Boolean;
    FStaticSvg: TSvgRecorder;
    { world }
    FPeaks: array[0..1] of array of TPeak;   // the two tileable ranges
    FStars: array of TStar;
    FClouds: array of TCloud;
    FScroll: Single;                         // design px flown (for parallax)
    FTime: Single;
    { game }
    FState: Integer;
    FY, FVY, FTilt, FFlapT, FInvuln, FStateT, FSpeed, FDist: Single;
    FLives, FScore, FBest, FLanternsGot: Integer;
    FNewBest, FAutoPilot, FExportCopy, FShowPause, FFlapQueued: Boolean;
    FPlayTrack: Integer;
    FObs: array of TObstacle;
    FLants, FHawks: array of TItem;
    FBonus: array of TItem;
    FHaz: array of THazard;
    FSlowT: Single;          // seconds of slow river left (slow-down bonus)
    FParts: array of TParticle;
    FRng: LongWord;
    FHud, FCard: TBGRABitmap;
    FItemSpr: array of array[0..1] of TBGRABitmap;  // menu items: normal, selected (owned by FCache)
    FCache: TStringList;   // item sprites and blank cards, by text / size; cleared on resize
    FCacheWarm: Boolean;
    FItemTxt: array of string;
    FCardW: Single;
    FSvgHud, FSvgCard: string;
    FHudKey, FCardKey: string;
    { menus, settings, scores }
    FMenu, FMenuPrev, FSel, FMenuN, FRank, FGames: Integer;
    FMenuT: Double;
    FItemY0, FItemH, FCardX0, FCardX1, FCardTop: Single;
    FMusicVol, FSfxVol, FMusicChoice, FDifficulty, FSeasonChoice, FTimeChoice: Integer;
    FHudOn, FFullWanted, FVSyncWanted, FQuit: Boolean;
    FScores: array of TScoreRec;
    FInput: array of TInputEv;
    { maps: random (seeded, endless) or custom (.pcmap) }
    FMapMode: Integer;                 // 0 random, 1 custom map
    FMap: TPCMap;
    FSeed: LongWord;
    FGen: TPCRandomGen;
    FShapes: array of TShapeInst;
    FShapeLib: array of TPCShape;
    FFinishD: Single;                  // custom map: world distance of the finish, 0 none
    FWon: Boolean;
    FMapMusic: Integer;                // -1 auto, 0..6 built-in, 7 the map's own tune
    FDiffUser: Integer;                // the difficulty in the settings (a ghost may use another)
    { ghosts: recording, replay and race }
    FRec: array of TPointF;            // (world distance, y) every 1/GhostRate s
    FRecFlaps: array of Single;
    FRecT: Single;
    FGhost: array of TPointF;
    FGhostFlaps: array of Single;
    FGhostFlapI, FGhostFlapJ: Integer;
    FGhostFlapT: Single;
    FReplay, FRace: Boolean;
    FGhostFile: string;
    { list menus and messages }
    FList: TStringList;                // file paths of the current list menu
    FListNames: TStringList;
    FListTop: Integer;
    FSelFile, FMsg: string;
    FPlayer: TPCPlayer;        // who flies (nil: nobody chosen yet)
    FCharacter: Integer;       // the player's character
    FNameEdit: string;         // the name being typed (msNewName)
    FPendingStart: Integer;    // after choosing a player: 1 random map, 2 the custom map FPendingFile
    FPendingFile: string;
    FRunHearts, FRunSlows, FRunPassed, FRunLost: Integer;   // this flight, for the statistics
    FRunTime: Single;
    FSelPlayers: array of TPCPlayer;   // the players on the paper cards (newest flight first)
    FSelSpr: array of TBGRABitmap;     // their cards (the last one: New player)
    FSelSprScale: Single;
    FFx: TMenuFxSet;                   // the menus' frames and letter effects (menufx.pcmenufx)
    FGlyphs: TGlyphCache;              // their letters, cut for the current scale
    FGlyphScale: Single;
    FFxVersion, FFxCheck: Integer;
    FFxAge: LongInt;
    FCardTitle: string;
    FCardH: Single;
    FSelTop: Integer;                  // the first card shown
    FCharBack: Integer;                // where choosing a character returns to
    FSelCanBack: Boolean;              // the cards were opened from a menu: Esc goes back
    FReachedMain: Boolean;             // the main menu was shown once: no Quit on the cards any more
    FPendingMap: string;
    FEditMode: Boolean;
    FEditPlay: Boolean;
    { time of day }
    FFrom, FTo: Integer;
    FBlend: Single;
    FAuto: Boolean;
    FAutoTimer: Single;
    FShowCaption: Boolean;
    { season }
    FSeason, FPendingSeason: Integer;
    FTheme, FPendingTheme, FThemeChoice: Integer;   // background (MapThemeNames); choice 0 random, 1.. a theme
    FPendingFade: Boolean;
    FSnap: TBGRABitmap;
    FSnapFade: Single;
    FFlash, FFlashT, FFlashNext: Single;
    FBolt: array of TPointF;
    FBoltOn: Boolean;
    function P(X, Y: Single): TPointF;
    function S(V: Single): Single;
    procedure MakePalettes;
    procedure SeasonTint(var Pl: TPal; M: Integer);
    procedure Generate;
    procedure GeneratePeaks;
    procedure AddCloud(Index: Integer; CX, CY, W, H, Speed: Single);
    procedure FreeResources;
    function Crop(Y0, Y1: Single; out Pos: TPoint): TBGRABitmap;
    function TakeSvg(Mark: Integer): string;
    procedure RenderStatic;
    procedure Grain(B: TBGRABitmap);
    procedure CutCloudSprites;
    procedure ApplySeason;
    function Rnd: Single;                   // the game's own random numbers (replayable)
    procedure SpawnObstacle(X: Single);
    procedure ResetWorld;
    procedure Hit;
    procedure RequirePlayer(Action: Integer);
    procedure SetPlayer(APlayer: TPCPlayer);
    procedure DoPendingStart;
    procedure RecordFlight;
    function ShownChar: Integer;
    { the design rows the visible things of a shadow layer use: 0 lanterns,
      1 bonuses, 2 hawks, 3 clouds / pinwheels / koi; False: nothing visible }
    function LayerRows(Which: Integer; out Y0, Y1: Single): Boolean;
    procedure LoadSelect;
    procedure LoadMenuFx;
    function MenuStyle: Integer;          // FFx index of the open menu
    procedure FreeSelect;
    procedure MakeSelectCards;
    function SelCount: Integer;
    function SelHasQuit: Boolean;
    function SelCardX(I: Integer): Single;
    procedure DoFlap;
    procedure Burst(X, Y: Single; Kind, N: Integer; C: TBGRAPixel);
    procedure UpdateGame(DT: Single);
    procedure MakeHud;
    procedure MakeCard;
    procedure MakeItems;
    procedure FreeItems;
    function ItemSprite(const It: string; Sel: Integer): TBGRABitmap;
    function BlankCard(CW, CH: Single; const Fr: TFrameStyle): TBGRABitmap;
    procedure ChineseFrame(B: TBGRABitmap; CW, CH: Single; Knot: Boolean = True);
    procedure ClearCache;
    procedure WarmCache;
    procedure LoadBest;
    procedure SaveBest;
    function Collides(PX, PY: Single): Boolean;
    procedure Snd(Sfx: Integer; Vol: Single = 1; Pitch: Single = 1);
    procedure HandleInput;
    procedure OpenMenu(M: Integer);
    procedure MenuKey(Code: Integer);
    procedure MenuActivate(Dir: Integer);
    procedure MenuBack;
    function MenuItem(I: Integer): string;
    function ItemAt(PX, PY: Single): Integer;
    procedure GoMainMenu;
    procedure ChangeSetting(I, Dir: Integer);
    procedure LoadSettings;
    procedure SaveSettings;
    procedure LoadScores;
    procedure SaveScores;
    procedure AddScore;
    procedure SyncAudio;
    function WantedTrack: Integer;
    function MaxLives: Integer;
    procedure SpawnAhead;
    procedure AddObjs(const Objs: TMapObjArray);
    function ShapeIndex(const AName: string): Integer;
    procedure ClearShapeLib;
    procedure BeginRun;
    procedure StartRandom(ASeed: LongWord);
    procedure StartMapObj(M: TPCMap; FromD: Single);
    procedure FinishRun(Won: Boolean);
    procedure LoadList(M: Integer);
    function ListVisible: Integer;
    procedure SaveGame;
    procedure LoadGame(const AFile: string);
    procedure SaveGhost;
    procedure StartGhost(const AFile: string; Race: Boolean);
    function GhostYAt(D: Single; out Ok: Boolean): Single;
    function DataDir(const Sub: string): string;
  public
    LayerOn: array[TLayerId] of Boolean;
    TransparentBack: Boolean;
    StaticMs: Double;
    StaticCount: Integer;
    AutoSeconds: Single;
    FadeSeconds: Single;
    constructor Create;
    destructor Destroy; override;
    procedure Resize(AWidth, AHeight: Integer);
    function SpriteJobCount: Integer;
    procedure SpriteJob(AIndex, AWorker: Integer);
    procedure Update(DT: Single);
    procedure Prepare;
    procedure CopyStateFrom(Src: TGameScene);
    procedure RenderSvg(Svg: TSvgRecorder);
    procedure SetMode(AMode: Integer);
    procedure SetModeInstant(AMode: Integer);
    procedure SetSeason(ASeason: Integer; AFade: Boolean = True);
    procedure SetTheme(ATheme: Integer; AFade: Boolean = True);
    function RunTheme: Integer;
    function Night: Single;
    function Shade: Single;
    function CurrentMode: Integer;
    function SpriteCount: Integer;
    function SpriteBytes: Int64;
    function StaticBytes: Int64;
    function DescribeParams: string;
    { game input: queued here, handled in Prepare (main thread, workers idle) }
    procedure Flap;                          // = KeyInput(gkFlap)
    procedure KeyInput(Code: Integer);
    procedure TextInput(const AText: string);    // typed text (names)
    function TextEntry: Boolean;             // a name is being typed: keys are letters
    procedure MouseInput(Kind: Integer; PX, PY: Single);  // 1 move, 2 click (window pixels)
    procedure StartGame;
    procedure StartMapFile(const AFile: string);   // --map file (queued, started in Prepare)
    { Map Editor 1: the game world as a live preview }
    procedure EditorShowMap(M: TPCMap);
    procedure EditorPlayFrom(M: TPCMap; FromD: Single);
    procedure EditorStop;
    function EditorPlaying: Boolean;
    property EditMode: Boolean read FEditMode;
    property Scroll: Single read FScroll write FScroll;
    property CraneY: Single read FY;
    property Menu: Integer read FMenu;
    property QuitRequested: Boolean read FQuit;
    property FullScreenWanted: Boolean read FFullWanted write FFullWanted;
    property VSyncWanted: Boolean read FVSyncWanted write FVSyncWanted;
    property Difficulty: Integer read FDifficulty;
    property MusicVolume: Integer read FMusicVol;
    property SoundVolume: Integer read FSfxVol;
    property MusicChoice: Integer read FMusicChoice;
    property ShowPause: Boolean read FShowPause write FShowPause;
    property Character: Integer read FCharacter write FCharacter;
    property ThemeChoice: Integer read FThemeChoice write FThemeChoice;   // 0 random, 1.. a theme
    property State: Integer read FState;
    property Score: Integer read FScore;
    property Best: Integer read FBest;
    property Lives: Integer read FLives;
    property GameSpeed: Single read FSpeed;
    property Distance: Single read FDist;
    property LanternsGot: Integer read FLanternsGot;
    property ShowCaption: Boolean read FShowCaption write FShowCaption;
    property AutoCycle: Boolean read FAuto write FAuto;
    property Season: Integer read FSeason;
    property ModeFrom: Integer read FFrom;
    property ModeTo: Integer read FTo;
    property Blend: Single read FBlend;
    property VectorStatic: Boolean read FRecordSvg write FRecordSvg;
    property Time: Single read FTime;
    property Scale: Single read FScale;
    property OffX: Single read FOffX;
    property OffY: Single read FOffY;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property VisL: Single read FVisL;
    property VisR: Single read FVisR;
  end;

implementation

uses
  uAudio;

function Hex(const S: string): TBGRAPixel;
begin
  Result := StrToBGRA(S);
end;

function WithAlpha(C: TBGRAPixel; A: Integer): TBGRAPixel; inline;
begin
  Result := C;
  Result.alpha := EnsureRange(A, 0, 255);
end;

function Darken(C: TBGRAPixel; K: Single): TBGRAPixel;
begin
  Result.red := EnsureRange(Round(C.red * K), 0, 255);
  Result.green := EnsureRange(Round(C.green * K), 0, 255);
  Result.blue := EnsureRange(Round(C.blue * K), 0, 255);
  Result.alpha := C.alpha;
end;

function Mix(A, B: TBGRAPixel; T: Single): TBGRAPixel;
begin
  Result.red := Round(A.red + (B.red - A.red) * T);
  Result.green := Round(A.green + (B.green - A.green) * T);
  Result.blue := Round(A.blue + (B.blue - A.blue) * T);
  Result.alpha := Round(A.alpha + (B.alpha - A.alpha) * T);
end;

function RandRange(A, B: Single): Single;
begin
  Result := A + Random * (B - A);
end;

{ deterministic 0..1 noise for an integer key (no state, thread safe) }
function Hash01(K: Integer): Single;
var
  X: LongWord;
begin
  X := LongWord(K) * 2654435761;
  X := X xor (X shr 15);
  X := X * 2246822519;
  X := X xor (X shr 13);
  Result := (X and $FFFFFF) / $1000000;
end;

{ fractional part that is always 0..1 (also for negative values) }
function PFrac(V: Single): Single; inline;
begin
  Result := V - Floor(V);
end;

function GreyMix(C: TBGRAPixel; T: Single): TBGRAPixel;
var
  L: Integer;
begin
  L := (C.red * 30 + C.green * 59 + C.blue * 11) div 100;
  Result := Mix(C, BGRA(L, L, L, C.alpha), T);
end;


procedure BoxBlur(var A, Tmp: array of Single; W, H, R: Integer);
var
  X, Y, I: Integer;
  Sum, Inv: Single;
begin
  Inv := 1 / (2 * R + 1);
  for Y := 0 to H - 1 do
  begin
    Sum := 0;
    for I := 0 to Min(R, W - 1) do
      Sum := Sum + A[Y * W + I];
    for X := 0 to W - 1 do
    begin
      Tmp[Y * W + X] := Sum * Inv;
      if X + R + 1 < W then Sum := Sum + A[Y * W + X + R + 1];
      if X - R >= 0 then Sum := Sum - A[Y * W + X - R];
    end;
  end;
  for X := 0 to W - 1 do
  begin
    Sum := 0;
    for I := 0 to Min(R, H - 1) do
      Sum := Sum + Tmp[I * W + X];
    for Y := 0 to H - 1 do
    begin
      A[Y * W + X] := Sum * Inv;
      if Y + R + 1 < H then Sum := Sum + Tmp[(Y + R + 1) * W + X];
      if Y - R >= 0 then Sum := Sum - Tmp[(Y - R) * W + X];
    end;
  end;
end;

function RowPtr(B: TBGRABitmap; Y: Integer): PBGRAPixel; inline;
begin
  if B.LineOrder = riloTopToBottom then
    Result := B.Data + Y * B.Width
  else
    Result := B.Data + (B.Height - 1 - Y) * B.Width;
end;

procedure BlendBitmap(Dest: TBGRABitmap; X, Y: Integer; Src: TBGRABitmap; Opacity: Integer = 255);
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

{ ====================================================================== }
{ TPainter: the paper engine (shared with New York Town Papercut)         }
{ ====================================================================== }

constructor TPainter.Create(AScene: TGameScene);
begin
  inherited Create;
  FScene := AScene;
  FLayer := TBGRABitmap.Create(1, 1);
  FRaster := True;
  SetLength(FPts, 64);
end;

destructor TPainter.Destroy;
begin
  FLayer.Free;
  inherited Destroy;
end;

procedure TPainter.ResetStats;
begin
  FillChar(LayerMs, SizeOf(LayerMs), 0);
end;

function TPainter.P(X, Y: Single): TPointF;
begin
  Result.X := FOrgX + X * FScene.FScale;
  Result.Y := FOrgY + Y * FScene.FScale;
end;

function TPainter.S(V: Single): Single;
begin
  Result := V * FScene.FScale;
end;

function TPainter.RowsHit(Y0, Y1: Single): Boolean;
begin
  Result := (FOrgY + Y1 * FScene.FScale >= -2) and (FOrgY + Y0 * FScene.FScale <= FTargetH + 2);
end;

procedure TPainter.TargetBand(ATop, AHeight: Integer);
begin
  FOrgX := FScene.FOffX;
  FOrgY := FScene.FOffY - ATop;
  FTargetH := AHeight;
end;

procedure TPainter.BeginLayer;
begin
  FOrgX := FScene.FOffX;
  FOrgY := FScene.FOffY - FLayerTop;
  if FRaster then
  begin
    FRowA := EnsureRange(FRowA, 0, FLayer.Height);
    FRowB := EnsureRange(FRowB, FRowA, FLayer.Height);
    if (FRowA = 0) and (FRowB = FLayer.Height) then
      FLayer.FillTransparent
    else if FRowB > FRowA then
      FLayer.FillRect(0, FRowA, FLayer.Width, FRowB, BGRAPixelTransparent, dmSet);
    FTargetH := FLayer.Height;
  end
  else
    FTargetH := FScene.FHeight;
  if FSvg <> nil then FSvgMark := FSvg.Mark;
end;

procedure TPainter.SvgLayerEnd(Depth: Single);
var
  Content: string;
begin
  Content := FSvg.Take(FSvgMark);
  if Content = '' then Exit;
  if Depth > 0 then
    FSvg.Raw('<g filter="url(#' + FSvg.DropShadow(S(3) * Depth, S(6) * Depth, S(7) * Depth * 0.5,
      90 / 255) + ')">' + LineEnding + Content + '</g>')
  else
    FSvg.Raw('<g>' + LineEnding + Content + '</g>');
end;

procedure TPainter.CompositeLayer(Dest: TBGRABitmap; DestTop: Integer; Depth: Single);
const
  F = 4;
  Strength = 90 / 255;
var
  LW, LH, DH, SW, SH, X, Y, R, DX, DY, LX, LY, SY0, X0, X1, Y0, Y1, SA, LA, Inv,
  Pad, BX0, BX1, BY0, BY1, W1, W2, WS, RL, RR, GC, K: Integer;
  FY, V: Single;
  Src, Dst, L: PBGRAPixel;
  CMin, CMax, SMin, SMax: array of Integer;
begin
  if FSvg <> nil then SvgLayerEnd(Depth);
  if not FRaster then Exit;
  LW := FLayer.Width;
  LH := FLayer.Height;
  DH := Dest.Height;
  BX0 := MaxInt; BX1 := -1; BY0 := MaxInt; BY1 := -1;
  SW := LW div F + 2;
  SH := LH div F + 2;
  if Length(FShadow) < SW * SH then
  begin
    SetLength(FShadow, SW * SH);
    SetLength(FBlurTmp, SW * SH);
  end;
  for Y := 0 to SH - 1 do
  begin
    LY := Y * F;
    if (LY >= LH) or (LY < FRowA) or (LY >= FRowB) then
    begin
      for X := 0 to SW - 1 do FShadow[Y * SW + X] := 0;
      Continue;
    end;
    Src := RowPtr(FLayer, LY);
    for X := 0 to SW - 1 do
    begin
      LX := X * F;
      if (LX < LW) and ((Src + LX)^.alpha > 0) then
      begin
        FShadow[Y * SW + X] := (Src + LX)^.alpha * Strength;
        if X < BX0 then BX0 := X;
        if X > BX1 then BX1 := X;
        if Y < BY0 then BY0 := Y;
        if Y > BY1 then BY1 := Y;
      end
      else
        FShadow[Y * SW + X] := 0;
    end;
  end;
  if BX1 < 0 then Exit;  // empty layer
  // where the content is, row by row (grid units), before the blur spreads it
  SetLength(CMin, SH);
  SetLength(CMax, SH);
  SetLength(SMin, SH);
  SetLength(SMax, SH);
  for Y := 0 to SH - 1 do
  begin
    CMin[Y] := MaxInt;
    CMax[Y] := -1;
    for X := 0 to SW - 1 do
      if FShadow[Y * SW + X] > 0 then
      begin
        if CMin[Y] = MaxInt then CMin[Y] := X;
        CMax[Y] := X;
      end;
  end;
  R := Max(1, Round(S(7) * Depth / F));
  if Depth > 0 then
  begin
    BoxBlur(FShadow, FBlurTmp, SW, SH, R);
    BoxBlur(FShadow, FBlurTmp, SW, SH, R);
  end
  else
    FillChar(FShadow[0], SW * SH * SizeOf(Single), 0);
  // and where the blurred shadow is visible
  for Y := 0 to SH - 1 do
  begin
    SMin[Y] := MaxInt;
    SMax[Y] := -1;
    for X := 0 to SW - 1 do
      if FShadow[Y * SW + X] > 0.4 then
      begin
        if SMin[Y] = MaxInt then SMin[Y] := X;
        SMax[Y] := X;
      end;
  end;

  DX := Round(S(3) * Depth);
  DY := Round(S(6) * Depth);
  Pad := (2 * R + 2) * F;
  X0 := Max(0, BX0 * F - Pad);
  X1 := Min(Min(LW, Dest.Width), BX1 * F + DX + Pad);
  Y0 := Max(0, FLayerTop + BY0 * F - Pad - DestTop);
  Y1 := Min(DH, FLayerTop + BY1 * F + DY + Pad - DestTop);
  if (X1 <= X0) or (Y1 <= Y0) then Exit;
  if Length(FXIdx) < LW then
  begin
    SetLength(FXIdx, LW);
    SetLength(FXFrac, LW);
  end;
  for X := X0 to X1 - 1 do
  begin
    V := (X - DX) / F;
    FXIdx[X] := Floor(V);
    FXFrac[X] := V - FXIdx[X];
  end;
  if Length(FRow) < SW then SetLength(FRow, SW);
  L := nil;
  for Y := Y0 to Y1 - 1 do
  begin
    FY := (DestTop + Y - DY - FLayerTop) / F;
    SY0 := Floor(FY);
    FY := FY - SY0;
    // the x range this row can touch: its content and its shadow; skip empty rows
    RL := MaxInt;
    RR := -MaxInt;
    GC := (DestTop + Y - FLayerTop) div F;
    for K := GC to GC + 1 do
      if (K >= 0) and (K < SH) and (CMax[K] >= 0) then
      begin
        RL := Min(RL, CMin[K] * F - F);
        RR := Max(RR, CMax[K] * F + 2 * F);
      end;
    for K := SY0 to SY0 + 1 do
      if (K >= 0) and (K < SH) and (SMax[K] >= 0) then
      begin
        RL := Min(RL, SMin[K] * F + DX - F);
        RR := Max(RR, SMax[K] * F + DX + 2 * F);
      end;
    if RR < RL then Continue;
    RL := Max(RL, X0);
    RR := Min(RR, X1);
    for X := 0 to SW - 1 do
    begin
      V := 0;
      if (SY0 >= 0) and (SY0 < SH) then V := FShadow[SY0 * SW + X] * (1 - FY);
      if (SY0 + 1 >= 0) and (SY0 + 1 < SH) then V := V + FShadow[(SY0 + 1) * SW + X] * FY;
      FRow[X] := V;
    end;
    LY := DestTop + Y - FLayerTop;
    if (LY >= FRowA) and (LY < FRowB) and (LY < LH) then Src := RowPtr(FLayer, LY) else Src := nil;
    Dst := RowPtr(Dest, Y);
    for X := RL to RR - 1 do
    begin
      LX := FXIdx[X];
      V := 0;
      if (LX >= 0) and (LX < SW) then V := FRow[LX] * (1 - FXFrac[X]);
      if (LX + 1 >= 0) and (LX + 1 < SW) then V := V + FRow[LX + 1] * FXFrac[X];
      SA := Round(V);
      LA := 0;
      if Src <> nil then
      begin
        L := Src + X;
        LA := L^.alpha;
      end;
      if (SA = 0) and (LA = 0) then Continue;
      with (Dst + X)^ do
      begin
        if LA = 255 then
        begin
          red := L^.red;
          green := L^.green;
          blue := L^.blue;
          alpha := 255;
          Continue;
        end;
        if alpha = 255 then
        begin
          if SA > 0 then
          begin
            Inv := 255 - SA;
            red := red * Inv div 255;
            green := green * Inv div 255;
            blue := blue * Inv div 255;
          end;
          if LA > 0 then
          begin
            Inv := 255 - LA;
            red := (L^.red * LA + red * Inv) div 255;
            green := (L^.green * LA + green * Inv) div 255;
            blue := (L^.blue * LA + blue * Inv) div 255;
          end;
        end
        else
        begin
          if SA > 0 then
          begin
            W2 := alpha * (255 - SA);
            WS := SA * 255 + W2;
            red := red * W2 div WS;
            green := green * W2 div WS;
            blue := blue * W2 div WS;
            alpha := WS div 255;
          end;
          if LA > 0 then
          begin
            W1 := LA * 255;
            W2 := alpha * (255 - LA);
            WS := W1 + W2;
            red := (L^.red * W1 + red * W2) div WS;
            green := (L^.green * W1 + green * W2) div WS;
            blue := (L^.blue * W1 + blue * W2) div WS;
            alpha := WS div 255;
          end;
        end;
      end;
    end;
  end;
  Dest.InvalidateBitmap;
end;

procedure TPainter.DPoly(B: TBGRABitmap; const Pts: array of TPointF; C: TBGRAPixel);
begin
  if FSvg <> nil then FSvg.Poly(Pts, C);
  if FRaster then B.FillPolyAntialias(Pts, C);
end;

procedure TPainter.DPolyG(B: TBGRABitmap; const Pts: array of TPointF; const G: TGrad);
var
  Sc: TBGRAGradientScanner;
begin
  if FSvg <> nil then FSvg.PolyFill(Pts, FSvg.Gradient(G));
  if FRaster then
  begin
    if G.Radial then
      Sc := TBGRAGradientScanner.Create(G.C1, G.C2, gtRadial, G.P1, G.P2, True)
    else
      Sc := TBGRAGradientScanner.Create(G.C1, G.C2, gtLinear, G.P1, G.P2, True);
    try
      B.FillPolyAntialias(Pts, Sc);
    finally
      Sc.Free;
    end;
  end;
end;

procedure TPainter.DEllipse(B: TBGRABitmap; X, Y, RX, RY: Single; C: TBGRAPixel);
begin
  if FSvg <> nil then FSvg.Ellipse(X, Y, RX, RY, C);
  if FRaster then B.FillEllipseAntialias(X, Y, RX, RY, C);
end;

procedure TPainter.DEllipseG(B: TBGRABitmap; X, Y, RX, RY: Single; const G: TGrad);
var
  Sc: TBGRAGradientScanner;
begin
  if FSvg <> nil then FSvg.EllipseFill(X, Y, RX, RY, FSvg.Gradient(G));
  if FRaster then
  begin
    if G.Radial then
      Sc := TBGRAGradientScanner.Create(G.C1, G.C2, gtRadial, G.P1, G.P2, True)
    else
      Sc := TBGRAGradientScanner.Create(G.C1, G.C2, gtLinear, G.P1, G.P2, True);
    try
      B.FillEllipseAntialias(X, Y, RX, RY, Sc);
    finally
      Sc.Free;
    end;
  end;
end;

procedure TPainter.DPolyLine(B: TBGRABitmap; const Pts: array of TPointF; C: TBGRAPixel; W: Single);
begin
  if FSvg <> nil then FSvg.PolyLine(Pts, C, W);
  if FRaster then B.DrawPolyLineAntialias(Pts, C, W);
end;

procedure TPainter.DLine(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel; W: Single);
begin
  if FSvg <> nil then FSvg.Line(X1, Y1, X2, Y2, C, W);
  if FRaster then B.DrawLineAntialias(X1, Y1, X2, Y2, C, W);
end;

procedure TPainter.DRect(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel);
var
  A, Z: TPointF;
  IX1, IY1, IX2, IY2: Integer;
begin
  A := P(X1, Y1);
  Z := P(X2, Y2);
  IX1 := Round(A.X); IY1 := Round(A.Y); IX2 := Max(IX1 + 1, Round(Z.X)); IY2 := Max(IY1 + 1, Round(Z.Y));
  if FSvg <> nil then
    if C.alpha = 255 then
      FSvg.Rect(IX1, IY1, IX2 - IX1, IY2 - IY1, '#' + IntToHex(C.red, 2) + IntToHex(C.green, 2) +
        IntToHex(C.blue, 2))
    else
      FSvg.Poly([PointF(IX1, IY1), PointF(IX2, IY1), PointF(IX2, IY2), PointF(IX1, IY2)], C);
  if FRaster then
    if C.alpha = 255 then B.FillRect(IX1, IY1, IX2, IY2, C, dmSet)
    else B.FillRect(IX1, IY1, IX2, IY2, C, dmDrawWithTransparency);
end;

procedure TPainter.DRadialRect(B: TBGRABitmap; X1, Y1, X2, Y2: Integer; C1, C2: TBGRAPixel;
  Ctr, Edge: TPointF);
begin
  if FSvg <> nil then
    FSvg.Rect(X1, Y1, X2 - X1, Y2 - Y1, FSvg.Gradient(MakeGrad(C1, C2, True, Ctr, Edge)));
  if FRaster then
    B.GradientFill(X1, Y1, X2, Y2, C1, C2, gtRadial, Ctr, Edge, dmDrawWithTransparency);
end;

procedure TPainter.Glow(B: TBGRABitmap; X, Y, R: Single; C: TBGRAPixel);
var
  Q: TPointF;
  RP, RR, DY2, D2, F, Ia: Single;
  X0, X1, Y0, Y1, XX, YY, A, W1, W2, WS, FI: Integer;
  D: PBGRAPixel;
begin
  if (C.alpha = 0) or (R <= 0) then Exit;
  if not RowsHit(Y - R, Y + R) then Exit;
  Q := P(X, Y);
  RP := Max(1, S(R));
  if FSvg <> nil then
    FSvg.EllipseFill(Q.X, Q.Y, RP, RP, FSvg.Gradient(MakeGrad(C, WithAlpha(C, 0), True, Q,
      PointF(Q.X + RP, Q.Y))));
  if not FRaster then Exit;
  X0 := Max(0, Floor(Q.X - RP));
  X1 := Min(B.Width - 1, Ceil(Q.X + RP));
  Y0 := Max(0, Floor(Q.Y - RP));
  Y1 := Min(B.Height - 1, Ceil(Q.Y + RP));
  if (X1 < X0) or (Y1 < Y0) then Exit;
  RR := 1 / (RP * RP);
  Ia := C.alpha / 255;
  for YY := Y0 to Y1 do
  begin
    DY2 := Sqr(YY + 0.5 - Q.Y) * RR;
    if DY2 >= 1 then Continue;
    D := RowPtr(B, YY) + X0;
    for XX := X0 to X1 do
    begin
      D2 := DY2 + Sqr(XX + 0.5 - Q.X) * RR;
      if D2 < 1 then
      begin
        F := 1 - D2;
        FI := Trunc(F * F * Ia * 256);          // 0..256
        A := (FI * 255) shr 8;
        if A > 0 then
          if D^.alpha = 255 then
          begin
            W1 := D^.red + (C.red * FI) shr 8;
            if W1 > 255 then W1 := 255;
            D^.red := W1;
            W1 := D^.green + (C.green * FI) shr 8;
            if W1 > 255 then W1 := 255;
            D^.green := W1;
            W1 := D^.blue + (C.blue * FI) shr 8;
            if W1 > 255 then W1 := 255;
            D^.blue := W1;
          end
          else
          begin
            W1 := A * 255;
            W2 := D^.alpha * (255 - A);
            WS := W1 + W2;
            D^.red := (C.red * W1 + D^.red * W2) div WS;
            D^.green := (C.green * W1 + D^.green * W2) div WS;
            D^.blue := (C.blue * W1 + D^.blue * W2) div WS;
            D^.alpha := WS div 255;
          end;
      end;
      Inc(D);
    end;
  end;
end;

procedure TPainter.HDash(B: TBGRABitmap; X, Y, Len, Thick: Single; C: TBGRAPixel);
var
  A, Z: TPointF;
  Y0, Y1, YY, XX, X0, X1, Al, W2: Integer;
  Cov: Single;
  D: PBGRAPixel;
begin
  if C.alpha = 0 then Exit;
  A := P(X, Y - Thick / 2);
  Z := P(X + Len, Y + Thick / 2);
  if (Z.Y < 0) or (A.Y > FTargetH) then Exit;
  if FSvg <> nil then FSvg.Poly([A, PointF(Z.X, A.Y), Z, PointF(A.X, Z.Y)], C);
  if not FRaster then Exit;
  Y0 := Max(0, Floor(A.Y));
  Y1 := Min(B.Height - 1, Max(Y0, Ceil(Z.Y) - 1));
  X0 := Max(0, Floor(A.X));
  X1 := Min(B.Width - 1, Ceil(Z.X) - 1);
  if (X1 < X0) or (Y0 > Y1) then Exit;
  for YY := Y0 to Y1 do
  begin
    // vertical coverage of this row
    Cov := Min(Z.Y, YY + 1) - Max(A.Y, YY);
    if Cov <= 0 then Continue;
    if Cov > 1 then Cov := 1;
    D := RowPtr(B, YY) + X0;
    for XX := X0 to X1 do
    begin
      if XX = X0 then Al := Round(C.alpha * Cov * Min(1, XX + 1 - A.X))
      else if XX = X1 then Al := Round(C.alpha * Cov * Min(1, Z.X - XX))
      else Al := Round(C.alpha * Cov);
      if Al > 0 then
      begin
        if Al > 255 then Al := 255;
        W2 := 255 - Al;
        D^.red := (C.red * Al + D^.red * W2) div 255;
        D^.green := (C.green * Al + D^.green * W2) div 255;
        D^.blue := (C.blue * Al + D^.blue * W2) div 255;
        if D^.alpha < 255 then D^.alpha := Al + D^.alpha * W2 div 255;
      end;
      Inc(D);
    end;
  end;
end;

procedure TPainter.RainStreak(B: TBGRABitmap; X, Y, DX, Len, Thick: Single; C: TBGRAPixel);
var
  A, Z: TPointF;
  R0, R1, YY, XX, X0, X1, Al, W2: Integer;
  T, XC, HW, L, R, Cov: Single;
  D: PBGRAPixel;
begin
  if C.alpha = 0 then Exit;
  A := P(X, Y);
  Z := P(X + DX, Y + Len);
  if FSvg <> nil then FSvg.Line(A.X, A.Y, Z.X, Z.Y, C, Max(0.5, S(Thick)));
  if not FRaster then Exit;
  if Z.Y - A.Y < 0.5 then Exit;
  R0 := Max(0, Floor(A.Y));
  R1 := Min(B.Height - 1, Ceil(Z.Y) - 1);
  HW := Max(0.5, S(Thick)) / 2;
  for YY := R0 to R1 do
  begin
    T := (YY + 0.5 - A.Y) / (Z.Y - A.Y);
    if (T < 0) or (T > 1) then Continue;
    XC := A.X + T * (Z.X - A.X);
    L := XC - HW;
    R := XC + HW;
    X0 := Max(0, Floor(L));
    X1 := Min(B.Width - 1, Ceil(R) - 1);
    D := RowPtr(B, YY) + X0;
    for XX := X0 to X1 do
    begin
      Cov := Min(R, XX + 1) - Max(L, XX);
      if Cov > 0 then
      begin
        Al := Round(C.alpha * Min(1, Cov));
        W2 := 255 - Al;
        D^.red := (C.red * Al + D^.red * W2) div 255;
        D^.green := (C.green * Al + D^.green * W2) div 255;
        D^.blue := (C.blue * Al + D^.blue * W2) div 255;
        if D^.alpha < 255 then D^.alpha := Al + D^.alpha * W2 div 255;
      end;
      Inc(D);
    end;
  end;
end;

procedure TPainter.EdgeFill(B: TBGRABitmap; const Edge: array of TPointF; ShiftX, Off, Thick, YBot: Single;
  C: TBGRAPixel);
var
  N, I, J, X0, X1, XX, YY, RMin, RMax, Al, W1, W2, WS: Integer;
  T, Yt, Yb, Cov, FY, FY1: Single;
  Poly: array of TPointF;
  ColT, ColB: PSingle;
  D: PBGRAPixel;
begin
  N := Length(Edge);
  if (N < 2) or (C.alpha = 0) then Exit;
  if FSvg <> nil then
  begin
    SetLength(Poly, 2 * N);
    for I := 0 to N - 1 do
    begin
      Poly[I] := PointF(Edge[I].X + ShiftX, Edge[I].Y + Off);
      if Thick > 0 then
        Poly[2 * N - 1 - I] := PointF(Edge[I].X + ShiftX, Edge[I].Y + Off + Thick)
      else
        Poly[2 * N - 1 - I] := PointF(Edge[I].X + ShiftX, YBot);
    end;
    FSvg.Poly(Poly, C);
  end;
  if not FRaster then Exit;
  X0 := Max(0, Ceil(Edge[0].X + ShiftX));
  X1 := Min(B.Width - 1, Floor(Edge[N - 1].X + ShiftX));
  if X1 < X0 then Exit;
  // the top and bottom of every column first
  if Length(FColT) < X1 - X0 + 1 then
  begin
    SetLength(FColT, X1 - X0 + 64);
    SetLength(FColB, X1 - X0 + 64);
  end;
  ColT := PSingle(FColT);
  ColB := PSingle(FColB);
  RMin := MaxInt;
  RMax := -1;
  J := 0;
  for XX := X0 to X1 do
  begin
    T := XX + 0.5 - ShiftX;
    while (J < N - 2) and (Edge[J + 1].X < T) do Inc(J);
    if Edge[J + 1].X = Edge[J].X then Yt := Edge[J].Y
    else Yt := Edge[J].Y + (Edge[J + 1].Y - Edge[J].Y) * (T - Edge[J].X) / (Edge[J + 1].X - Edge[J].X);
    Yt := Yt + Off;
    if Thick > 0 then Yb := Yt + Thick else Yb := YBot;
    if Yb <= Yt then
    begin
      ColT[XX - X0] := 1E9;
      ColB[XX - X0] := -1E9;
      Continue;
    end;
    ColT[XX - X0] := Yt;
    ColB[XX - X0] := Yb;
    if Floor(Yt) < RMin then RMin := Floor(Yt);
    if Ceil(Yb) - 1 > RMax then RMax := Ceil(Yb) - 1;
  end;
  // then row by row (memory order): every row walks the columns once
  if RMin < 0 then RMin := 0;
  if RMax > B.Height - 1 then RMax := B.Height - 1;
  for YY := RMin to RMax do
  begin
    D := RowPtr(B, YY) + X0;
    FY := YY;
    FY1 := YY + 1;
    for I := 0 to X1 - X0 do
    begin
      Yt := ColT[I];
      Yb := ColB[I];
      if (Yb > FY) and (Yt < FY1) then
      begin
        if (Yt <= FY) and (Yb >= FY1) then Al := C.alpha
        else
        begin
          if Yb < FY1 then Cov := Yb else Cov := FY1;
          if Yt > FY then Cov := Cov - Yt else Cov := Cov - FY;
          Al := Trunc(C.alpha * Cov + 0.5);
        end;
        if Al > 0 then
        begin
          if Al >= 255 then
            D^ := C
          else if D^.alpha = 255 then
          begin
            W2 := 255 - Al;
            D^.red := (C.red * Al + D^.red * W2) div 255;
            D^.green := (C.green * Al + D^.green * W2) div 255;
            D^.blue := (C.blue * Al + D^.blue * W2) div 255;
          end
          else
          begin
            W1 := Al * 255;
            W2 := D^.alpha * (255 - Al);
            WS := W1 + W2;
            D^.red := (C.red * W1 + D^.red * W2) div WS;
            D^.green := (C.green * W1 + D^.green * W2) div WS;
            D^.blue := (C.blue * W1 + D^.blue * W2) div WS;
            D^.alpha := WS div 255;
          end;
        end;
      end;
      Inc(D);
    end;
  end;
end;

procedure TPainter.Box(B: TBGRABitmap; X1, Y1, X2, Y2: Single; C: TBGRAPixel);
begin
  DPoly(B, [P(X1, Y1), P(X2, Y1), P(X2, Y2), P(X1, Y2)], C);
end;

procedure TPainter.DrawClouds(Dest: TBGRABitmap);
var
  I, A: Integer;
  Q: TPointF;
begin
  if not RowsHit(30, 420) then Exit;
  A := Round(255 * FScene.FBlend);
  for I := 0 to High(FScene.FClouds) do
    with FScene.FClouds[I] do
    begin
      Q := P(MinX - 12 + OX, MinY - 12);
      if FSvg <> nil then
        FSvg.Raw(Format('<g transform="translate(%s,%s)">', [FSvg.N(Round(Q.X)), FSvg.N(Round(Q.Y))]) +
          LineEnding + Svg[FScene.CurrentMode] + '</g>');
      if not FRaster then Continue;
      BlendBitmap(Dest, Round(Q.X), Round(Q.Y), Sprite[FScene.FFrom], 255 - IfThen(FScene.FFrom = FScene.FTo, 0, 0));
      if (FScene.FFrom <> FScene.FTo) and (A > 0) then
        BlendBitmap(Dest, Round(Q.X), Round(Q.Y), Sprite[FScene.FTo], A);
    end;
end;

procedure TGameScene.AddCloud(Index: Integer; CX, CY, W, H, Speed: Single);
var
  C: TCloud;
  I, NB, K: Integer;
  U, X, Y, R: Single;
begin
  NB := 14 + Random(8);
  SetLength(C.Puffs, 3 * NB);
  K := 0;
  for I := 0 to NB - 1 do
  begin
    // domes are bigger in the middle; their bottoms sit near a flat base line
    if I < 3 then U := RandRange(-0.18, 0.18) else U := RandRange(-0.5, 0.5);
    R := H * RandRange(0.3, 0.55) * (1 - 1.1 * Abs(U)) + H * 0.08;
    C.Puffs[K] := CX + U * W;
    C.Puffs[K + 1] := CY + H * 0.25 - R * RandRange(0.35, 0.8);
    C.Puffs[K + 2] := R;
    Inc(K, 3);
  end;
  C.MinX := 1e9; C.MaxX := -1e9; C.MinY := 1e9; C.MaxY := -1e9;
  I := 0;
  while I + 2 <= High(C.Puffs) do
  begin
    X := C.Puffs[I]; Y := C.Puffs[I + 1]; R := C.Puffs[I + 2];
    C.MinX := Min(C.MinX, X - R); C.MaxX := Max(C.MaxX, X + R);
    C.MinY := Min(C.MinY, Y - R); C.MaxY := Max(C.MaxY, Y + R);
    Inc(I, 3);
  end;
  C.OX := 0;
  C.Speed := Speed;
  for I := 0 to 2 do
  begin
    C.Sprite[I] := nil;
    C.Svg[I] := '';
  end;
  FClouds[Index] := C;
end;

function TGameScene.Crop(Y0, Y1: Single; out Pos: TPoint): TBGRABitmap;
var
  A, B: Integer;
begin
  A := EnsureRange(Floor(P(0, Y0).Y), 0, FHeight - 1);
  B := EnsureRange(Ceil(P(0, Y1).Y), A + 1, FHeight);
  Pos := Point(0, A);
  Result := TBGRABitmap(FAcc.GetPart(Rect(0, A, FWidth, B)));
  Result.LoadFromBitmapIfNeeded;
end;

function TGameScene.TakeSvg(Mark: Integer): string;
begin
  if FStaticSvg <> nil then Result := FStaticSvg.Take(Mark) else Result := '';
end;

procedure TGameScene.Grain(B: TBGRABitmap);
var
  X, Y, V, T: Integer;
  H, H2: LongWord;
  Px: PBGRAPixel;
begin
  for Y := 0 to B.Height - 1 do
  begin
    Px := RowPtr(B, Y);
    for X := 0 to B.Width - 1 do
    begin
      if Px^.alpha > 0 then
      begin
        H := (LongWord(X) * 73856093) xor (LongWord(Y) * 19349663);
        H := H * 2654435761;
        H := H xor (H shr 15);
        H2 := (LongWord(X div 3) * 83492791) xor (LongWord(Y div 2) * 2971215073);
        H2 := H2 * 2246822519;
        H2 := H2 xor (H2 shr 13);
        V := Integer((H shr 8) and 7) - 4 + Integer((H2 shr 9) and 7) - 3;
        T := Px^.red + V;
        if T < 0 then T := 0 else if T > 255 then T := 255;
        Px^.red := T;
        T := Px^.green + V;
        if T < 0 then T := 0 else if T > 255 then T := 255;
        Px^.green := T;
        T := Px^.blue + V;
        if T < 0 then T := 0 else if T > 255 then T := 255;
        Px^.blue := T;
      end;
      Inc(Px);
    end;
  end;
  B.InvalidateBitmap;
end;

procedure TGameScene.CutCloudSprites;
var
  I, M, J, W, H, Mk: Integer;
  Spr: TBGRABitmap;
  Q: TPointF;
  R: Single;
  Cut: TPainter;
  Outer: string;

  procedure Origin(const Cl: TCloud);
  begin
    Cut.FOrgX := S(-Cl.MinX + 12);
    Cut.FOrgY := S(-Cl.MinY + 12);
  end;

begin
  Cut := FCutter;
  Cut.FLayerTop := 0;
  for I := 0 to High(FClouds) do
    with FClouds[I] do
    begin
      W := Min(FWidth, Ceil(S(MaxX - MinX + 44)));
      H := Min(FHeight, Ceil(S(MaxY - MinY + 44)));
      if (W < 4) or (H < 4) then Continue;
      for M := 0 to 2 do
      begin
        Spr := TBGRABitmap.Create(W, H);
        if FStaticSvg <> nil then Mk := FStaticSvg.Mark else Mk := 0;
        // back sheet: the shaded underside, a little lower and to the right
        Cut.BeginLayer;
        Origin(FClouds[I]);
        J := 0;
        while J + 2 <= High(Puffs) do
        begin
          R := Puffs[J + 2];
          Q := Cut.P(Puffs[J] + 8, Puffs[J + 1] + 6);
          Cut.DEllipse(Cut.FLayer, Q.X, Q.Y, S(R), S(R * 0.82), FPal[M].CloudShade);
          Inc(J, 3);
        end;
        Cut.CompositeLayer(Spr, 0, 0.35);
        // front sheet: the lit top
        Cut.BeginLayer;
        Origin(FClouds[I]);
        J := 0;
        while J + 2 <= High(Puffs) do
        begin
          R := Puffs[J + 2];
          Q := Cut.P(Puffs[J], Puffs[J + 1] - 2);
          Cut.DEllipse(Cut.FLayer, Q.X, Q.Y, S(R * 0.86), S(R * 0.72), FPal[M].CloudLit);
          Inc(J, 3);
        end;
        Cut.CompositeLayer(Spr, 0, 0.5);
        Grain(Spr);
        if M = 2 then Spr.ApplyGlobalOpacity(200);
        Spr.LoadFromBitmapIfNeeded;
        Sprite[M] := Spr;
        if FStaticSvg <> nil then
        begin
          if M = 2 then Outer := '<g opacity="0.78">' else Outer := '<g>';
          Svg[M] := Outer + LineEnding + FStaticSvg.Take(Mk) + '</g>';
        end;
      end;
    end;
  Cut.TargetBand(0, FHeight);
end;

procedure TGameScene.SetMode(AMode: Integer);
begin
  AMode := EnsureRange(AMode, 0, 2);
  if (AMode = FTo) and (FBlend = 0) and (FFrom = FTo) then Exit;
  FFrom := CurrentMode;
  FTo := AMode;
  FBlend := 0;
  if FFrom = FTo then FBlend := 0;
  FAutoTimer := 0;
end;

procedure TGameScene.SetModeInstant(AMode: Integer);
begin
  FFrom := EnsureRange(AMode, 0, 2);
  FTo := FFrom;
  FBlend := 0;
end;

function TGameScene.CurrentMode: Integer;
begin
  if FBlend >= 0.5 then Result := FTo else Result := FFrom;
end;

function TGameScene.Night: Single;
begin
  Result := ModeNight[FFrom] + (ModeNight[FTo] - ModeNight[FFrom]) * FBlend;
end;

function TGameScene.Shade: Single;
begin
  Result := ModeShade[FFrom] + (ModeShade[FTo] - ModeShade[FFrom]) * FBlend;
end;

function TGameScene.SpriteJobCount: Integer;
begin
  Result := 0;
end;

procedure TGameScene.SpriteJob(AIndex, AWorker: Integer);
begin
end;

procedure TGameScene.SetTheme(ATheme: Integer; AFade: Boolean);
begin
  FPendingTheme := EnsureRange(ATheme, 0, MapThemeCount - 1);
  FPendingFade := AFade;
end;

{ the background of a new flight: the map's, else the setting (random: from the seed) }
function TGameScene.RunTheme: Integer;
begin
  if (FMapMode = 1) and (FMap.Theme >= 0) then Exit(FMap.Theme);
  if FThemeChoice > 0 then Exit(FThemeChoice - 1);
  if FMapMode = 1 then Result := Length(FMap.Name) mod MapThemeCount
  else Result := Integer(FSeed mod LongWord(MapThemeCount));
end;

procedure TGameScene.SetSeason(ASeason: Integer; AFade: Boolean);
begin
  FPendingSeason := EnsureRange(ASeason, 0, SeasonCount - 1);
  FPendingFade := AFade;
end;

procedure TGameScene.ApplySeason;
var
  NewS, NewT: Integer;
  Snap: TBGRABitmap;
  Pt: TPainter;
begin
  NewS := FPendingSeason;
  if NewS < 0 then NewS := FSeason;
  NewT := FPendingTheme;
  if NewT < 0 then NewT := FTheme;
  FPendingSeason := -1;
  FPendingTheme := -1;
  FPendingTheme := -1;
  if (NewS = FSeason) and (NewT = FTheme) then Exit;
  Snap := nil;
  if FPendingFade and (FWidth > 1) and (FSky[0] <> nil) then
  begin
    Snap := TBGRABitmap.Create(FWidth, FHeight);
    Pt := TPainter.Create(Self);
    try
      Pt.RenderBand(Snap, 0);
    finally
      Pt.Free;
    end;
  end;
  if (NewS <> FSeason) and (FSeasonChoice <> 4) then FSeasonChoice := NewS;  // the settings follow keys 1-4 and --season
  FSeason := NewS;
  if NewT <> FTheme then
  begin
    FTheme := NewT;
    GeneratePeaks;
  end;
  MakePalettes;
  FFlashT := 10;
  FFlash := 0;
  if FWidth > 1 then Resize(FWidth, FHeight);
  FSnap := Snap;
  FSnapFade := 1;
end;

procedure TGameScene.RenderSvg(Svg: TSvgRecorder);
var
  Pt: TPainter;
begin
  Svg.AddDefsFrom(FStaticSvg);
  Pt := TPainter.Create(Self);
  try
    Pt.FSvg := Svg;
    Pt.FRaster := False;
    Pt.RenderBand(nil, 0);
  finally
    Pt.Free;
  end;
end;


function PeakF(U: Single): Single;
begin
  U := Abs(U);
  if U >= 1 then Result := 0
  else Result := Power(1 - Power(U, 2.4), 0.55);
end;

{ ====================================================================== }
{ TPainter: helpers and paper peaks                                       }
{ ====================================================================== }

procedure TPainter.Ell(B: TBGRABitmap; X, Y, RX, RY: Single; C: TBGRAPixel);
var
  Q: TPointF;
begin
  if not RowsHit(Y - RY, Y + RY) then Exit;  // not in this band
  Q := P(X, Y);
  DEllipse(B, Q.X, Q.Y, S(RX), S(RY), C);
end;

procedure TPainter.Ln(B: TBGRABitmap; X1, Y1, X2, Y2, W: Single; C: TBGRAPixel);
var
  A, Z: TPointF;
begin
  if not RowsHit(Min(Y1, Y2) - W, Max(Y1, Y2) + W) then Exit;
  A := P(X1, Y1);
  Z := P(X2, Y2);
  DLine(B, A.X, A.Y, Z.X, Z.Y, C, Max(0.5, S(W)));
end;

{ a polygon given in local coordinates, scaled by K, turned by A, placed at CX, CY }
procedure TPainter.Rot(B: TBGRABitmap; const Local: array of TPointF; CX, CY, A, K: Single; C: TBGRAPixel);
var
  I: Integer;
  CA, SA: Single;
  Pts: array of TPointF;
begin
  CA := Cos(A);
  SA := Sin(A);
  SetLength(Pts, Length(Local));
  for I := 0 to High(Local) do
    Pts[I] := P(CX + (Local[I].X * CA - Local[I].Y * SA) * K, CY + (Local[I].X * SA + Local[I].Y * CA) * K);
  DPoly(B, Pts, C);
end;

{ A karst peak (Up: rising from Base) or a rock hanging from the sky (not Up:
  hanging down from Base): the body, a lit crescent on the sun side, ridge lines
  and (Detail > 0) shrubs on the top and a snow cap in winter. }
{ Fills between two edges sampled at the same x positions (pixel coordinates,
  sorted by x), column by column; both ends of every column get their
  coverage. The paper peaks are all of this kind, and it is far cheaper than
  antialiased polygons for tall shapes. SVG gets the same shape as a polygon. }
procedure TPainter.EdgeBand(B: TBGRABitmap; const TopE, BotE: array of TPointF; C: TBGRAPixel);
var
  N, I, J, X0, X1, XX, YY, RMin, RMax, Al, W1, W2, WS: Integer;
  T, F, Ya, Yb2, Yt, Yb, Cov, FY, FY1: Single;
  Poly: array of TPointF;
  ColT, ColB: PSingle;
  D: PBGRAPixel;
begin
  N := Min(Length(TopE), Length(BotE));
  if (N < 2) or (C.alpha = 0) then Exit;
  if FSvg <> nil then
  begin
    SetLength(Poly, 2 * N);
    for I := 0 to N - 1 do
    begin
      Poly[I] := TopE[I];
      Poly[2 * N - 1 - I] := BotE[I];
    end;
    FSvg.Poly(Poly, C);
  end;
  if not FRaster then Exit;
  X0 := Max(0, Ceil(TopE[0].X));
  X1 := Min(B.Width - 1, Floor(TopE[N - 1].X));
  if X1 < X0 then Exit;
  if Length(FColT) < X1 - X0 + 1 then
  begin
    SetLength(FColT, X1 - X0 + 64);
    SetLength(FColB, X1 - X0 + 64);
  end;
  ColT := PSingle(FColT);
  ColB := PSingle(FColB);
  RMin := MaxInt;
  RMax := -1;
  J := 0;
  for XX := X0 to X1 do
  begin
    T := XX + 0.5;
    while (J < N - 2) and (TopE[J + 1].X < T) do Inc(J);
    if TopE[J + 1].X = TopE[J].X then F := 0
    else F := (T - TopE[J].X) / (TopE[J + 1].X - TopE[J].X);
    Ya := TopE[J].Y + (TopE[J + 1].Y - TopE[J].Y) * F;
    Yb2 := BotE[J].Y + (BotE[J + 1].Y - BotE[J].Y) * F;
    if Ya < Yb2 then begin Yt := Ya; Yb := Yb2; end else begin Yt := Yb2; Yb := Ya; end;
    if Yb - Yt < 0.01 then
    begin
      ColT[XX - X0] := 1E9;
      ColB[XX - X0] := -1E9;
      Continue;
    end;
    ColT[XX - X0] := Yt;
    ColB[XX - X0] := Yb;
    if Floor(Yt) < RMin then RMin := Floor(Yt);
    if Ceil(Yb) - 1 > RMax then RMax := Ceil(Yb) - 1;
  end;
  // then row by row (memory order): every row walks the columns once
  if RMin < 0 then RMin := 0;
  if RMax > B.Height - 1 then RMax := B.Height - 1;
  for YY := RMin to RMax do
  begin
    D := RowPtr(B, YY) + X0;
    FY := YY;
    FY1 := YY + 1;
    for I := 0 to X1 - X0 do
    begin
      Yt := ColT[I];
      Yb := ColB[I];
      if (Yb > FY) and (Yt < FY1) then
      begin
        if (Yt <= FY) and (Yb >= FY1) then Al := C.alpha
        else
        begin
          if Yb < FY1 then Cov := Yb else Cov := FY1;
          if Yt > FY then Cov := Cov - Yt else Cov := Cov - FY;
          Al := Trunc(C.alpha * Cov + 0.5);
        end;
        if Al > 0 then
        begin
          if Al >= 255 then
            D^ := C
          else if D^.alpha = 255 then
          begin
            W2 := 255 - Al;
            D^.red := (C.red * Al + D^.red * W2) div 255;
            D^.green := (C.green * Al + D^.green * W2) div 255;
            D^.blue := (C.blue * Al + D^.blue * W2) div 255;
          end
          else
          begin
            W1 := Al * 255;
            W2 := D^.alpha * (255 - Al);
            WS := W1 + W2;
            D^.red := (C.red * W1 + D^.red * W2) div WS;
            D^.green := (C.green * W1 + D^.green * W2) div WS;
            D^.blue := (C.blue * W1 + D^.blue * W2) div WS;
            D^.alpha := WS div 255;
          end;
        end;
      end;
      Inc(D);
    end;
  end;
end;

{ A karst peak (Up: rising from Base) or a rock hanging from the sky (not Up:
  hanging down from Base): (Detail > 0: a two-step paper shadow,) the body, a lit
  band on the sun side, ridge lines, shrubs on the top or vines / icicles under
  the rock, a snow cap in winter. The big shapes are EdgeBands. }
procedure TPainter.CutPeak(B: TBGRABitmap; C, W, H, Base: Single; Up: Boolean; Col: TBGRAPixel;
  const Pal: TPal; Detail: Integer; Seed: Integer);
const
  NS = 33;
var
  J, K, Side: Integer;
  U, T, X, Y, Dir, XIn, YB: Single;
  Lit, Dark, Veg: TBGRAPixel;
  TopE, BotE, Pts: array of TPointF;
begin
  if Up then Dir := -1 else Dir := 1;
  Lit := Mix(Col, Pal.Lit, 0.22);
  Dark := Darken(Col, 0.78);
  if Pal.SunX < 800 then Side := -1 else Side := 1;
  SetLength(TopE, NS);
  SetLength(BotE, NS);
  if Detail > 0 then
  begin
    // the paper shadow: the outline shifted right and down (twice, for a soft
    // edge); only the sliver outside the body is drawn - the rest is hidden
    for K := 0 to 1 do
    begin
      for J := 0 to NS - 1 do
      begin
        X := C - W + (2 * W + 8) * J / (NS - 1) + 2;   // columns of the shifted outline
        U := (X - (7 - 3 * K) - C) / W;
        Y := Base + Dir * H * PeakF(U) + 12 - 5 * K;    // shadow edge
        if Abs(X - C) < W then YB := Base + Dir * H * PeakF((X - C) / W)
        else YB := Base - Dir * 30;                       // body edge (or none)
        if Up then YB := Max(Y, YB) else YB := Min(Y, YB);
        TopE[J] := P(X, Y);
        BotE[J] := P(X, YB);
      end;
      EdgeBand(B, TopE, BotE, BGRA(0, 0, 20, 34 + 4 * K));
    end;
  end;
  // body
  for J := 0 to NS - 1 do
  begin
    U := -1 + 2 * J / (NS - 1);
    TopE[J] := P(C + U * W, Base + Dir * H * PeakF(U));
    BotE[J] := P(C + U * W, Base - Dir * 30);
  end;
  EdgeBand(B, TopE, BotE, Col);
  // lit band on the sun side: from the edge to an inner line that reaches the
  // foot at 0.68 of the half width
  for J := 0 to NS - 1 do
  begin
    T := J / (NS - 1);                       // 0 centre .. 1 outer edge
    X := C + Side * W * (0.16 + 0.84 * T);
    U := (X - C) / W;
    TopE[J] := P(X, Base + Dir * (H * PeakF(U) - 0.5));
    XIn := (Abs(U) - 0.16) / 0.52;            // where the inner line is at this x
    if XIn >= 1 then YB := Base - Dir * 2
    else YB := Base + Dir * (H * PeakF(Max(0, XIn)) * 0.96 - 3);
    BotE[J] := P(X, YB);
  end;
  if Side < 0 then
    for J := 0 to (NS div 2) - 1 do  // keep the samples sorted by x
    begin
      Pts := [TopE[J]];
      TopE[J] := TopE[NS - 1 - J];
      TopE[NS - 1 - J] := Pts[0];
      Pts := [BotE[J]];
      BotE[J] := BotE[NS - 1 - J];
      BotE[NS - 1 - J] := Pts[0];
    end;
  EdgeBand(B, TopE, BotE, Lit);
  if Detail > 0 then
  begin
    Ln(B, C - Side * 0.12 * W, Base + Dir * H * 0.86, C - Side * 0.3 * W, Base + Dir * H * 0.32, 1.4, WithAlpha(Dark, 130));
    Ln(B, C + Side * 0.04 * W, Base + Dir * H * 0.7, C - Side * 0.06 * W, Base + Dir * H * 0.22, 1.2, WithAlpha(Dark, 110));
    if Up then
      for J := 0 to 5 do
      begin
        U := -0.55 + J * 0.22 + 0.08 * (Hash01(Seed + J) - 0.5);
        X := C + U * W;
        Y := Base - H * PeakF(U) + 3;
        case FScene.FSeason of
          2: if Odd(J) then Veg := Pal.Foliage else Veg := Pal.Foliage2;
          3: Veg := Pal.Snow;
        else
          Veg := Mix(Pal.Foliage, Col, 0.3);
        end;
        Ell(B, X, Y, 6 + 4 * Hash01(Seed * 3 + J), 4, Veg);
      end
    else
      for J := 0 to 4 do
      begin
        U := -0.5 + J * 0.25;
        X := C + U * W;
        Y := Base + H * PeakF(U) - 2;
        if FScene.FSeason = 3 then
          DPoly(B, [P(X - 3, Y), P(X + 3, Y), P(X, Y + 10 + 12 * Hash01(Seed + J))], Pal.Snow)
        else if FScene.FSeason = 2 then
          Ln(B, X, Y, X + 3 * Sin(J + Seed), Y + 14 + 16 * Hash01(Seed + J), 1.4, Pal.Foliage)
        else
          Ln(B, X, Y, X + 3 * Sin(J + Seed), Y + 14 + 16 * Hash01(Seed + J), 1.4, Mix(Pal.Foliage, Col, 0.2));
      end;
    if Up and (FScene.FSeason = 3) and (H > 80) then
    begin
      SetLength(TopE, 17);
      SetLength(BotE, 17);
      for J := 0 to 16 do
      begin
        U := -0.62 + J * 1.24 / 16;
        TopE[J] := P(C + U * W, Base - H * PeakF(U) - 0.6);
        BotE[J] := P(C + U * W, Base - H * PeakF(U) + Min(60, H * 0.13) * (1 - Sqr(U / 0.62)) + 4 * Sin(J * 2.3 + C));
      end;
      EdgeBand(B, TopE, BotE, Pal.Snow);
    end;
  end;
end;

{ ---------- live parts ---------- }

procedure TPainter.DrawStars(Dest: TBGRABitmap);
var
  I, A: Integer;
  N, X: Single;
  Q: TPointF;
begin
  N := FScene.Night;
  if (N < 0.05) or (FScene.FSeason = 1) then Exit;
  if not RowsHit(0, 520) then Exit;
  for I := 0 to High(FScene.FStars) do
  begin
    X := FScene.FVisL + PFrac((FScene.FStars[I].X - FScene.FScroll * 0.02) / 1700) * 1700 - 40;
    Q := P(X, FScene.FStars[I].Y);
    if (Q.Y < -3) or (Q.Y > FTargetH + 3) then Continue;
    with FScene.FStars[I] do
    begin
      A := Round(255 * N * (0.45 + 0.55 * Sin(FScene.FTime * (1.3 + Phase) + Phase * 7)));
      if A > 8 then DEllipse(Dest, Q.X, Q.Y, S(R), S(R), BGRA(255, 250, 235, A));
    end;
  end;
end;

procedure TPainter.DrawMist(Dest: TBGRABitmap; Level: Integer);
var
  Sc: TGameScene;
  K, I, N: Integer;
  X, X0, Y, Base, Shift, Thick, MK: Single;
  Edge: array of TPointF;
  C: TBGRAPixel;
begin
  Sc := FScene;
  case Level of
    0: begin Base := Base0 - 26; Shift := Sc.FScroll * Par0; end;
    1: begin Base := Base1 - 24; Shift := Sc.FScroll * Par1; end;
  else
    begin Base := WaterY - 22; Shift := Sc.FScroll; end;
  end;
  if not RowsHit(Base - 20, Base + 60) then Exit;
  MK := Sc.FPal[Sc.FFrom].MistK + (Sc.FPal[Sc.FTo].MistK - Sc.FPal[Sc.FFrom].MistK) * Sc.FBlend;
  if Level = 2 then MK := MK * 0.6;
  C := Mix(Sc.FPal[Sc.FFrom].Haze, Sc.FPal[Sc.FTo].Haze, Sc.FBlend);
  X0 := Sc.FVisL - 40;
  N := Ceil((Sc.FVisR - X0 + 40) / 16) + 1;
  SetLength(Edge, N);
  for K := 0 to 1 do
  begin
    Thick := 22 + 12 * K + 6 * Level;
    for I := 0 to N - 1 do
    begin
      X := X0 + I * 16 + Shift * (1 + 0.15 * K);
      Y := Base + K * 10 + 9 * Sin(X * 0.006 + K * 1.7 + Level + Sc.FTime * 0.15) + 5 * Sin(X * 0.017 + K * 2);
      Edge[I] := P(X0 + I * 16, Y);
    end;
    EdgeFill(Dest, Edge, 0, 0, S(Thick), 0, WithAlpha(C, Round(Min(220, (78 - 26 * K) * MK))));
  end;
end;

{ the river: 4 paper wave strips sliding with the flight }
procedure TPainter.DrawWaves(Dest: TBGRABitmap);
const
  Strips = 4;
var
  Sc: TGameScene;
  K, I, N: Integer;
  X, X0, X1, Y, Base, Amp, WX: Single;
  Edge: array of TPointF;
  W1, W2, C, Crest: TBGRAPixel;
begin
  Sc := FScene;
  if not RowsHit(RiverTop, RiverBot + 4) then Exit;
  W1 := Mix(Sc.FPal[Sc.FFrom].Water1, Sc.FPal[Sc.FTo].Water1, Sc.FBlend);
  W2 := Mix(Sc.FPal[Sc.FFrom].Water2, Sc.FPal[Sc.FTo].Water2, Sc.FBlend);
  X0 := Sc.FVisL - 30;
  X1 := Sc.FVisR + 30;
  N := Ceil((X1 - X0) / 10) + 1;
  SetLength(Edge, N);
  for K := 0 to Strips - 1 do
  begin
    Base := RiverTop + 10 + K * 26;
    if not RowsHit(Base - 12, RiverBot + 4) then Continue;
    Amp := 2.4 + K * 1.3;
    for I := 0 to N - 1 do
    begin
      X := X0 + I * 10;
      WX := X + Sc.FScroll * (0.85 + 0.1 * K);   // nearer strips slide faster
      Y := Base + Amp * Sin(WX * (0.035 - K * 0.004) + Sc.FTime * (0.8 + 0.3 * K) + K * 1.3) +
        Amp * 0.4 * Sin(WX * 0.1 + K);
      Edge[I] := P(X, Y);
    end;
    if K = Strips - 1 then Y := RiverBot + 2 else Y := Base + 26 + 2.4 + (K + 1) * 1.3 * 1.4 + 3;
    C := Mix(W1, W2, 0.15 + 0.25 * K);
    Crest := Mix(C, BGRA(255, 255, 255), 0.26 * (1 - Sc.Night * 0.75));
    EdgeFill(Dest, Edge, S(1.5), -S(3.5), S(3.5), 0, BGRA(0, 0, 20, 45));
    EdgeFill(Dest, Edge, 0, 0, 0, P(0, Y).Y, C);
    EdgeFill(Dest, Edge, 0, 0, Max(0.8, S(1.4)), 0, Crest);
  end;
end;

procedure TPainter.DrawObstacles(Dest: TBGRABitmap);
var
  Sc: TGameScene;
  I, J, K2: Integer;
  Col, ColTop: TBGRAPixel;
  Pl: TPal;
  K, X, F, SK, Lift: Single;
  Sh: TPCShape;
  Pts, ShP: array of TPointF;
  Ob: TObstacle;
  Hz: TMapObj;
  G, BX, BT, Sw, Y0: Single;
  N: Integer;
  Stalk, Leaf: TBGRAPixel;
begin
  if FPart <> 0 then Exit;
  Sc := FScene;
  Pl := Sc.FPal[Sc.CurrentMode];
  K := Sc.FBlend;
  Col := Mix(Sc.FPal[Sc.FFrom].Range[2], Sc.FPal[Sc.FTo].Range[2], K);
  ColTop := Darken(Col, 0.86);
  // paper shapes from the map (behind the pillars)
  for I := 0 to High(Sc.FShapes) do
  begin
    X := Sc.FShapes[I].X - Sc.FScroll;
    if (X < Sc.FVisL - 400) or (X > Sc.FVisR + 400) then Continue;
    Sh := Sc.FShapeLib[Sc.FShapes[I].Lib];
    if Sc.FShapes[I].Flip then F := -1 else F := 1;
    SK := Sc.FShapes[I].Scale;
    for J := 0 to High(Sh.Polys) do
    begin
      if Length(Sh.Polys[J].Pts) < 3 then Continue;
      SetLength(Pts, Length(Sh.Polys[J].Pts));
      SetLength(ShP, Length(Pts));
      Lift := Sh.Polys[J].Lift;
      for K2 := 0 to High(Pts) do
      begin
        Pts[K2] := P(X + Sh.Polys[J].Pts[K2].X * SK * F, Sc.FShapes[I].Y + Sh.Polys[J].Pts[K2].Y * SK);
        ShP[K2] := PointF(Pts[K2].X + S(4 * Lift * SK), Pts[K2].Y + S(7 * Lift * SK));
      end;
      if Lift > 0 then DPoly(Dest, ShP, BGRA(0, 0, 20, 50));
      DPoly(Dest, Pts, Darken(Sh.Polys[J].Color, Max(0.55, Sc.Shade)));
    end;
  end;
  for I := 0 to High(Sc.FObs) do
  begin
    Ob := Sc.FObs[I];                 // (no "with": its X would hide the screen x)
    X := Ob.X - Sc.FScroll;
    if (X + Ob.W < Sc.FVisL - 40) or (X - Ob.W > Sc.FVisR + 40) then Continue;
    if Ob.HasBottom and RowsHit(Ob.GapY + Ob.Gap / 2 - 20, WaterY + 40) then
      CutPeak(Dest, X, Ob.W, WaterY + 30 - (Ob.GapY + Ob.Gap / 2), WaterY + 30, True, Col, Pl, 1, Ob.Seed);
    if Ob.HasTop and RowsHit(-60, Ob.GapY - Ob.Gap / 2 + 40) then
      CutPeak(Dest, X, Ob.W * 0.92, (Ob.GapY - Ob.Gap / 2) + 30, -30, False, ColTop, Pl, 1, Ob.Seed + 7);
  end;
  // swinging pillars and bamboo groves (cut like the pillars, no shadow layer)
  for I := 0 to High(Sc.FHaz) do
  begin
    Hz := Sc.FHaz[I].O;
    X := Hz.D - Sc.FScroll;
    if (X + Hz.W < Sc.FVisL - 40) or (X - Hz.W > Sc.FVisR + 40) then Continue;
    case Hz.Kind of
      okSwing:
        begin
          G := Hz.GapY + SwingOffset(Hz, Sc.FScroll);
          if Hz.Bottom and RowsHit(G + Hz.Gap / 2 - 20, WaterY + 40) then
          begin
            CutPeak(Dest, X, Hz.W, WaterY + 30 - (G + Hz.Gap / 2), WaterY + 30, True, Col, Pl, 1, Round(Hz.D));
            // a red paper pennant on the tip: this one moves
            DPoly(Dest, [P(X, G + Hz.Gap / 2 + 2), P(X, G + Hz.Gap / 2 - 30), P(X + 26, G + Hz.Gap / 2 - 22)],
              Darken(Hex('#D03A2E'), Max(0.55, Sc.Shade)));
            Ln(Dest, X, G + Hz.Gap / 2 + 4, X, G + Hz.Gap / 2 - 30, 2, Darken(Hex('#5A4030'), Sc.Shade));
          end;
          if Hz.Top and RowsHit(-60, G - Hz.Gap / 2 + 40) then
          begin
            CutPeak(Dest, X, Hz.W * 0.92, (G - Hz.Gap / 2) + 30, -30, False, ColTop, Pl, 1, Round(Hz.D) + 7);
            DPoly(Dest, [P(X, G - Hz.Gap / 2 - 2), P(X, G - Hz.Gap / 2 + 30), P(X + 26, G - Hz.Gap / 2 + 22)],
              Darken(Hex('#D03A2E'), Max(0.55, Sc.Shade)));
          end;
        end;
      okBamboo:
        if RowsHit(Hz.Y - 60, WaterY + 40) then
        begin
          N := Max(3, Round(Hz.W / 13));
          case Sc.FSeason of
            2: begin Stalk := Hex('#A8A040'); Leaf := Hex('#C89030'); end;
            3: begin Stalk := Hex('#7FA890'); Leaf := Hex('#E8EEF2'); end;
          else
            begin Stalk := Hex('#4E9A4A'); Leaf := Hex('#3C8040'); end;
          end;
          Stalk := Darken(Stalk, Max(0.45, Sc.Shade));
          Leaf := Darken(Leaf, Max(0.45, Sc.Shade));
          for J := 0 to N - 1 do
          begin
            BX := X - Hz.W + 2 * Hz.W * (J + 0.5) / N + 6 * (Hash01(Round(Hz.D) + J) - 0.5);
            BT := Hz.Y + 50 * Hash01(Round(Hz.D) * 3 + J);
            Sw := 5 * Sin(Sc.FTime * 1.3 + J * 1.7);
            // shadow, stalk (slightly bent by the wind), nodes, leaves
            DPoly(Dest, [P(BX + 2, WaterY + 30), P(BX + 16, WaterY + 30), P(BX + 15 + Sw, BT + 8), P(BX + 6 + Sw, BT + 8)],
              BGRA(0, 0, 20, 40));
            DPoly(Dest, [P(BX - 7, WaterY + 30), P(BX + 7, WaterY + 30), P(BX + 6 + Sw, BT), P(BX - 6 + Sw, BT)], Stalk);
            DPoly(Dest, [P(BX - 7, WaterY + 30), P(BX - 2, WaterY + 30), P(BX - 2 + Sw, BT), P(BX - 6 + Sw, BT)],
              Mix(Stalk, Hex('#FFFFFF'), 0.18));
            K2 := 0;
            Y0 := WaterY - 40;
            while Y0 > BT + 20 do
            begin
              F := Sw * (WaterY + 30 - Y0) / (WaterY + 30 - BT);
              Box(Dest, BX - 7 + F, Y0 - 2, BX + 7 + F, Y0 + 2, Darken(Stalk, 0.7));
              if (K2 mod 2 = J mod 2) and (Y0 < WaterY - 100) then
              begin
                SK := 1 - 2 * (K2 mod 2);
                DPoly(Dest, [P(BX + F, Y0), P(BX + F + 20 * SK, Y0 - 12), P(BX + F + 46 * SK, Y0 - 6),
                  P(BX + F + 18 * SK, Y0 + 2)], Leaf);
              end;
              Inc(K2);
              Y0 := Y0 - 62 - 10 * Hash01(J * 7 + K2);
            end;
            DPoly(Dest, [P(BX - 5 + Sw, BT + 2), P(BX + 5 + Sw, BT + 2), P(BX + Sw + 18, BT - 30)], Leaf);
            DPoly(Dest, [P(BX - 3 + Sw, BT + 6), P(BX + 3 + Sw, BT + 6), P(BX + Sw - 22, BT - 18)], Leaf);
          end;
        end;
    end;
  end;
  // the finish of a custom map: two red posts and a ribbon of lanterns
  if Sc.FFinishD > 0 then
  begin
    X := Sc.FFinishD - Sc.FScroll;
    if (X > Sc.FVisL - 60) and (X < Sc.FVisR + 60) then
    begin
      Box(Dest, X - 4, 40, X + 4, WaterY + 20, Darken(Hex('#B02820'), Max(0.5, Sc.Shade)));
      for J := 0 to 9 do
      begin
        Ell(Dest, X, 70 + J * 76, 10, 12, Darken(Hex('#D0302A'), Max(0.5, Sc.Shade)));
        if Sc.Night > 0.05 then Glow(Dest, X, 70 + J * 76, 22, WithAlpha(Hex('#FFB060'), Round(200 * Sc.Night)));
      end;
    end;
  end;
end;

procedure TPainter.DrawLanterns(Dest: TBGRABitmap);
var
  Sc: TGameScene;
  I: Integer;
  N, Sh, X, Y, Sw: Single;
  Red: TBGRAPixel;
begin
  Sc := FScene;
  N := Sc.Night;
  Sh := Sc.Shade;
  Red := Darken(Hex('#C8302A'), Sh);
  for I := 0 to High(Sc.FLants) do
  begin
    if not Sc.FLants[I].Alive then Continue;
    Sw := Sin(Sc.FTime * 2 + Sc.FLants[I].Phase);
    X := Sc.FLants[I].X - Sc.FScroll;          // (locals only: workers never write the scene)
    Y := Sc.FLants[I].Y + 6 * Sw;
    if (X < Sc.FVisL - 40) or (X > Sc.FVisR + 40) then Continue;
    if not RowsHit(Y - 16, Y + 22) then Continue;
    if FPart = 0 then
    begin
      Ell(Dest, X, Y, 9, 11, Mix(Red, Hex('#FFB060'), N * 0.6));
      Ell(Dest, X - 3, Y - 2, 3, 7, Mix(Red, Hex('#FF8060'), 0.35));
      Box(Dest, X - 5, Y - 13, X + 5, Y - 10, Darken(Hex('#E8B030'), Sh));
      Box(Dest, X - 5, Y + 10, X + 5, Y + 13, Darken(Hex('#E8B030'), Sh));
      Ln(Dest, X, Y + 13, X + Sw * 2, Y + 22, 1.4, Darken(Hex('#E8B030'), Sh));
    end
    else
    begin
      Glow(Dest, X, Y, 12 + 4 * N, WithAlpha(Hex('#FFC060'), Round(60 + 195 * N)));
      if N > 0.05 then Glow(Dest, X, Y, 42, WithAlpha(Hex('#FF7030'), Round(80 * N)));
    end;
  end;
end;

procedure TPainter.DrawHawks(Dest: TBGRABitmap);
var
  Sc: TGameScene;
  I: Integer;
  X, Y, Fl, Sh: Single;
  Body, Wing, Beak: TBGRAPixel;
begin
  Sc := FScene;
  if FPart <> 0 then Exit;
  Sh := Sc.Shade;
  Body := Darken(Hex('#5A4030'), Sh);
  Wing := Darken(Hex('#3E2C22'), Sh);
  Beak := Darken(Hex('#E8B030'), Sh);
  for I := 0 to High(Sc.FHawks) do
  begin
    if not Sc.FHawks[I].Alive then Continue;
    X := Sc.FHawks[I].X - Sc.FScroll;
    Y := Sc.FHawks[I].Y;
    if (X < Sc.FVisL - 60) or (X > Sc.FVisR + 60) then Continue;
    if not RowsHit(Y - 40, Y + 40) then Continue;
    Fl := Sin(Sc.FTime * 9 + Sc.FHawks[I].Phase);
    DPoly(Dest, [P(X - 30, Y), P(X - 10, Y - 7), P(X + 22, Y - 4), P(X + 34, Y - 9), P(X + 30, Y + 2),
      P(X + 8, Y + 7), P(X - 12, Y + 6)], Body);
    DPoly(Dest, [P(X - 4, Y - 4), P(X + 12, Y - 4), P(X + 22, Y - 4 - 34 * Fl), P(X + 2, Y - 4 - 30 * Fl)], Wing);
    DPoly(Dest, [P(X - 30, Y), P(X - 38, Y + 4), P(X - 28, Y + 3)], Beak);
    Ell(Dest, X - 24, Y - 3, 1.6, 1.6, Darken(Hex('#FFE070'), Max(0.7, Sh)));
  end;
end;

{ storm clouds, pinwheels and koi: in the shadowed hawk layer (part 1 = the
  lightning of the clouds) }
procedure TPainter.DrawHazards(Dest: TBGRABitmap);
const
  Blades: array[0..3] of string = ('#D8402E', '#F0B030', '#3A78C0', '#4E9A4A');
var
  Sc: TGameScene;
  I, J: Integer;
  O: TMapObj;
  X, Y, A, Sh, W, Fl: Single;
  Dark, Mid: TBGRAPixel;
begin
  Sc := FScene;
  Sh := Max(0.5, Sc.Shade);
  for I := 0 to High(Sc.FHaz) do
  begin
    O := Sc.FHaz[I].O;
    X := O.D - Sc.FScroll;
    W := O.W;
    case O.Kind of
      okCloud:
        begin
          if (X + W * 1.5 < Sc.FVisL) or (X - W * 1.5 > Sc.FVisR) then Continue;
          Y := O.Y + CloudOffset(O, Sc.FScroll);
          if not RowsHit(Y - W, WaterY) then Continue;
          // lightning now and then (from the clock: only a look, never a hit)
          Fl := Frac(Sc.FTime * 0.55 + Hash01(Round(O.D)));
          if FPart = 0 then
          begin
            Dark := Darken(Hex('#5A6070'), Sh);
            Mid := Darken(Hex('#757C8C'), Sh);
            for J := 0 to 5 do
              Ln(Dest, X - W * 0.8 + J * W * 0.32, Y + W * 0.45, X - W * 0.9 + J * W * 0.32, Y + W * 0.45 + 70 + 30 * Hash01(J),
                1.3, WithAlpha(Hex('#9AB0C8'), 150));
            Ell(Dest, X - W * 0.62, Y + W * 0.12, W * 0.62, W * 0.44, Dark);
            Ell(Dest, X + W * 0.6, Y + W * 0.16, W * 0.58, W * 0.42, Dark);
            Ell(Dest, X - W * 0.05, Y - W * 0.12, W * 0.74, W * 0.62, Mid);
            Ell(Dest, X - W * 0.3, Y - W * 0.3, W * 0.3, W * 0.22, Darken(Hex('#8A92A2'), Sh));
            if Fl < 0.07 then
              DPolyLine(Dest, [P(X, Y + W * 0.4), P(X - 12, Y + W * 0.4 + 40), P(X + 6, Y + W * 0.4 + 52),
                P(X - 8, Y + W * 0.4 + 100)], Hex('#FFF4C0'), 3);
          end
          else if Fl < 0.07 then
            Glow(Dest, X, Y + W * 0.3, W * 1.8, WithAlpha(Hex('#E8F0FF'), 170));
        end;
      okPinwheel:
        begin
          if FPart <> 0 then Continue;
          if (X + W < Sc.FVisL - 20) or (X - W > Sc.FVisR + 20) then Continue;
          if not RowsHit(O.Y - W, WaterY + 30) then Continue;
          A := PinwheelAngle(O, Sc.FScroll);
          Ln(Dest, X, O.Y, X, WaterY + 30, 6, Darken(Hex('#8A6038'), Sh));
          for J := 0 to 3 do
          begin
            Rot(Dest, [PointF(0, 0), PointF(W, 0), PointF(W * 0.42, W * 0.46)], X, O.Y, A + J * Pi / 2, 1,
              Darken(Hex(Blades[J]), Sh));
            Rot(Dest, [PointF(0, 0), PointF(W, 0), PointF(W * 0.55, -W * 0.12)], X, O.Y, A + J * Pi / 2, 1,
              Darken(Mix(Hex(Blades[J]), Hex('#FFFFFF'), 0.35), Sh));
          end;
          Ell(Dest, X, O.Y, 9, 9, Darken(Hex('#E8B030'), Sh));
        end;
      okKoi:
        begin
          if FPart <> 0 then Continue;
          KoiPos(O, Sc.FScroll, X, Y, A);
          X := X - Sc.FScroll;
          if (Y > WaterY + 26) or (X < Sc.FVisL - 60) or (X > Sc.FVisR + 60) then Continue;
          if not RowsHit(Y - 50, Y + 50) then Continue;
          Rot(Dest, [PointF(-22, 0), PointF(-44, -16), PointF(-36, 0), PointF(-44, 16)], X, Y, A, 1.2,
            Darken(Hex('#E86A2A'), Sh));
          Rot(Dest, [PointF(34, 0), PointF(20, -12), PointF(-6, -13), PointF(-26, -5), PointF(-26, 5), PointF(-6, 13),
            PointF(20, 12)], X, Y, A, 1.2, Darken(Hex('#F2EEE6'), Sh));
          Rot(Dest, [PointF(26, -4), PointF(12, -12), PointF(-2, -12), PointF(4, 2), PointF(18, 6)], X, Y, A, 1.2,
            Darken(Hex('#E8622A'), Sh));
          Rot(Dest, [PointF(-6, 4), PointF(-18, 10), PointF(-14, -2)], X, Y, A, 1.2, Darken(Hex('#D04A24'), Sh));
          Rot(Dest, [PointF(4, 10), PointF(-8, 22), PointF(-6, 10)], X, Y, A, 1.2, Darken(Hex('#E86A2A'), Sh));
          Rot(Dest, [PointF(25, -5), PointF(28, -5), PointF(28, -2), PointF(25, -2)], X, Y, A, 1.2, BGRA(30, 24, 20));
        end;
    end;
  end;
end;

{ hearts and slow-down bonuses (part 1: their light) }
procedure TPainter.DrawBonus(Dest: TBGRABitmap);
var
  Sc: TGameScene;
  I: Integer;
  X, Y, Sh: Single;
  C: TBGRAPixel;
begin
  Sc := FScene;
  Sh := Max(0.6, Sc.Shade);
  for I := 0 to High(Sc.FBonus) do
  begin
    if not Sc.FBonus[I].Alive then Continue;
    X := Sc.FBonus[I].X - Sc.FScroll;
    Y := Sc.FBonus[I].Y + 7 * Sin(Sc.FTime * 2.4 + Sc.FBonus[I].Phase);
    if (X < Sc.FVisL - 40) or (X > Sc.FVisR + 40) then Continue;
    if not RowsHit(Y - 24, Y + 24) then Continue;
    if Sc.FBonus[I].Kind = 0 then
    begin
      if FPart = 0 then
      begin
        C := Darken(Hex('#E0303A'), Sh);
        Ell(Dest, X - 8, Y - 5, 10, 10, C);
        Ell(Dest, X + 8, Y - 5, 10, 10, C);
        DPoly(Dest, [P(X - 17.5, Y - 1), P(X + 17.5, Y - 1), P(X, Y + 19)], C);
        Ell(Dest, X - 10, Y - 8, 3.5, 3, Darken(Hex('#FFB8B8'), Sh));
      end
      else
        Glow(Dest, X, Y, 26, WithAlpha(Hex('#FF7088'), 150));
    end
    else
    begin
      if FPart = 0 then
      begin
        Ell(Dest, X, Y, 17, 17, Darken(Hex('#3A7FC8'), Sh));
        Ell(Dest, X, Y, 13, 13, Darken(Hex('#5A9AD8'), Sh));
        C := Darken(Hex('#F4F0E6'), Sh);
        DPoly(Dest, [P(X - 7, Y - 9), P(X + 7, Y - 9), P(X, Y)], C);
        DPoly(Dest, [P(X - 7, Y + 9), P(X + 7, Y + 9), P(X, Y)], C);
        Box(Dest, X - 8, Y - 11, X + 8, Y - 9, C);
        Box(Dest, X - 8, Y + 9, X + 8, Y + 11, C);
      end
      else
        Glow(Dest, X, Y, 28, WithAlpha(Hex('#80C0FF'), 150));
    end;
  end;
end;

{ the ghost of a saved flight, raced against: a pale paper crane at the same
  distance (it flies the same river, so it is always at the crane's x) }
procedure TPainter.DrawGhost(Dest: TBGRABitmap);
var
  Sc: TGameScene;
  Y, Up, A, K: Single;
  Ok: Boolean;
  Paper: TBGRAPixel;
begin
  Sc := FScene;
  if not Sc.FRace then Exit;
  Y := Sc.GhostYAt(Sc.FScroll, Ok);
  if not Ok or not RowsHit(Y - 60, Y + 60) then Exit;
  K := 1.65;
  A := 0;
  Up := Cos(Min(1, Sc.FGhostFlapT / 0.35) * Pi);
  Paper := BGRA(220, 236, 255, 120);
  Rot(Dest, [PointF(-24, 2), PointF(0, -7), PointF(30, -2), PointF(0, 9)], CraneX, Y, A, K, Paper);
  Rot(Dest, [PointF(22, -3), PointF(40, -24), PointF(44, -23), PointF(30, 0)], CraneX, Y, A, K, Paper);
  Rot(Dest, [PointF(-22, 2), PointF(-46, -16), PointF(-38, -14), PointF(-16, -3)], CraneX, Y, A, K, Paper);
  Rot(Dest, [PointF(-8, -5), PointF(10, -5), PointF(2 + 8 * Up, -6 - 36 * Up), PointF(-10 + 4 * Up, -4 - 30 * Up)],
    CraneX, Y, A, K, Paper);
end;

{ The paper crane: tail, body, far wing (darker), neck and head with a red
  crown, near wing beating, crease lines; it tilts with its climb and blinks
  while it cannot be hurt. }
procedure TPainter.DrawCrane(Dest: TBGRABitmap);
var
  Sc: TGameScene;
  X, Y, A, K, Up, Sh: Single;
begin
  Sc := FScene;
  if FPart <> 0 then Exit;
  if (Sc.FState = gsOver) or (Sc.FEditMode and not Sc.FEditPlay) then Exit;
  if (Sc.FInvuln > 0) and (Frac(Sc.FInvuln * 6) < 0.4) then Exit;  // blink
  X := CraneX;
  Y := Sc.FY;
  if not RowsHit(Y - 60, Y + 60) then Exit;
  A := Sc.FTilt;
  K := 1.65;
  Sh := Max(0.62, Sc.Shade);
  // wing position: a fast down-stroke after a flap, then it lifts slowly
  Up := Cos(Min(1, Sc.FFlapT / 0.35) * Pi);   // 1 up .. -1 down
  if Sc.FState = gsDying then Up := Sin(Sc.FTime * 20);
  DrawCharacter(Dest, Sc.ShownChar, X, Y, A, K, Up, Sh);
end;

{ one character at X, Y (design), tilted A, scaled K, wings at Up (1 up .. -1 down) }
procedure TPainter.DrawCharacter(Dest: TBGRABitmap; Ch: Integer; X, Y, A, K, Up, Sh: Single);
var
  Paper, Fold, Crown: TBGRAPixel;
begin
  case Ch of
    1: begin DrawDragon(Dest, X, Y, A, K, Up, Sh); Exit; end;
    2: begin DrawPanda(Dest, X, Y, A, K, Up, Sh); Exit; end;
    3: begin DrawOwl(Dest, X, Y, A, K, Up, Sh); Exit; end;
    4: begin DrawPhoenix(Dest, X, Y, A, K, Up, Sh); Exit; end;
  end;
  Paper := Darken(Hex('#F6F2EA'), Sh);
  Fold := Darken(Hex('#D8D2C4'), Sh);
  Crown := Darken(Hex('#D42A20'), Sh);
  Rot(Dest, [PointF(-6, -4), PointF(12, -4), PointF(4 - 6 * Up, -4 - 30 * Up)], X, Y, A, K, Fold);
  Rot(Dest, [PointF(-22, 2), PointF(-46, -16), PointF(-38, -14), PointF(-16, -3)], X, Y, A, K, Fold);
  Rot(Dest, [PointF(-24, 2), PointF(0, -7), PointF(30, -2), PointF(0, 9)], X, Y, A, K, Paper);
  Rot(Dest, [PointF(0, 9), PointF(30, -2), PointF(-24, 2)], X, Y, A, K, Fold);
  Rot(Dest, [PointF(22, -3), PointF(40, -24), PointF(44, -23), PointF(30, 0)], X, Y, A, K, Paper);
  Rot(Dest, [PointF(40, -24), PointF(50, -21), PointF(42, -20)], X, Y, A, K, Darken(Hex('#2A2A2A'), Sh));
  Rot(Dest, [PointF(39, -26), PointF(43, -27), PointF(43, -23), PointF(40, -23)], X, Y, A, K, Crown);
  Rot(Dest, [PointF(-8, -5), PointF(10, -5), PointF(2 + 8 * Up, -6 - 36 * Up), PointF(-10 + 4 * Up, -4 - 30 * Up)],
    X, Y, A, K, Paper);
  Rot(Dest, [PointF(-8, -5), PointF(2 + 8 * Up, -6 - 36 * Up), PointF(-1 + 5 * Up, -5 - 30 * Up)], X, Y, A, K,
    Mix(Paper, Fold, 0.6));
end;

{ The character card: a small flying character beside every name and the
  highlighted one big on a round sky stage, all beating their wings (live,
  on top of the cached card). }
procedure TPainter.DrawCharBoard(Dest: TBGRABitmap);
var
  Sc: TGameScene;
  I: Integer;
  T, CX, CY, Bob, Up: Single;
begin
  Sc := FScene;
  T := Sc.FMenuT;
  for I := 0 to CharCount - 1 do
  begin
    CX := Sc.FCardX0 + 132;
    CY := Sc.FItemY0 + (I + 0.5) * Sc.FItemH;
    if not RowsHit(CY - 26, CY + 26) then Continue;
    Ell(Dest, CX, CY, 34, 21, IfThen(I = Sc.FSel, Hex('#C8E0F0'), Hex('#E2ECF0')));
    // the highlighted one flaps faster
    if I = Sc.FSel then Up := Sin(T * 9 + I) else Up := Sin(T * 4 + I * 1.3);
    DrawCharacter(Dest, I, CX + 2, CY + 4 + 2 * Sin(T * 3 + I), -0.05, 0.42, Up, 1);
  end;
  if (Sc.FSel < 0) or (Sc.FSel >= CharCount) then Exit;
  CX := Sc.FCardX1 - 165;
  CY := Sc.FItemY0 + 2.6 * Sc.FItemH;
  if not RowsHit(CY - 120, CY + 120) then Exit;
  // the stage: a red ring around a sky disc, two paper clouds, a shadow
  Ell(Dest, CX, CY, 104, 104, Hex('#B22822'));
  Ell(Dest, CX, CY, 98, 98, Hex('#F6EEDE'));
  Ell(Dest, CX, CY, 92, 92, Hex('#BCD8EC'));
  Ell(Dest, CX - 46 + 8 * Sin(T * 0.7), CY + 52, 30, 10, Hex('#FFFFFF'));
  Ell(Dest, CX + 40 - 8 * Sin(T * 0.6), CY - 58, 24, 8, Hex('#F4F8FA'));
  Bob := 9 * Sin(T * 2.2);
  Ell(Dest, CX, CY + 74, 50 - Bob, 6, BGRA(40, 60, 90, 50));
  // a full flap: a quick down-stroke, then a slow lift
  Up := Cos(Min(1, Frac(T * 1.25) / 0.35) * Pi);
  DrawCharacter(Dest, Sc.FSel, CX + 2, CY + 12 + Bob, -0.08 - Bob * 0.01, 1.5, Up, 1);
end;

{ the open menu's frame effect, title and items: every letter placed live
  from the glyph cache with its effect (the selected item has its own style) }
procedure TPainter.DrawMenuTexts(Dest: TBGRABitmap);
var
  Sc: TGameScene;
  Fx: TMenuFx;
  St: TTextStyle;
  I, TabP: Integer;
  Q: TPointF;
  T, Y, K: Single;
  It: string;
begin
  Sc := FScene;
  Fx := Sc.FFx.Menus[Sc.MenuStyle];
  T := Sc.FMenuT;
  K := Sc.FScale;
  if Fx.Frame.Fx <> ffNone then
  begin
    Q := P(Sc.FCardX0, Sc.FCardTop);
    if RowsHit(Sc.FCardTop - 40, Sc.FCardTop + Sc.FCardH + 40) then
      DrawFrameFx(Dest, Fx.Frame, Q.X, Q.Y, Sc.FCardW, Sc.FCardH, K, T);
  end;
  if RowsHit(Sc.FCardTop + 4, Sc.FCardTop + 18 + Fx.Title.Size * 1.5) then
  begin
    Q := P(Sc.FCardX0 + Sc.FCardW / 2, Sc.FCardTop + 18 + (44 - Fx.Title.Size) * 0.5);
    DrawFxText(Dest, Sc.FGlyphs, Fx.Title, K, Q.X, Q.Y, T, Sc.FCardTitle, 1);
  end;
  if Sc.FMenu = msSelect then Exit;
  for I := 0 to Min(Sc.FMenuN, Length(Sc.FItemTxt)) - 1 do
  begin
    if I = Sc.FSel then St := Fx.Sel else St := Fx.Item;
    Y := Sc.FItemY0 + I * Sc.FItemH + (Sc.FItemH - St.Size * 1.36) / 2;
    if not RowsHit(Y - 16, Y + St.Size * 1.6 + 16) then Continue;
    It := Sc.FItemTxt[I];
    TabP := Pos(#9, It);
    if TabP > 0 then
    begin
      Q := P(Sc.FCardX0 + 110, Y);
      DrawFxText(Dest, Sc.FGlyphs, St, K, Q.X, Q.Y, T, Copy(It, 1, TabP - 1), 0, I * 0.9);
      Q := P(Sc.FCardX0 + Sc.FCardW / 2 + 190, Y);
      DrawFxText(Dest, Sc.FGlyphs, St, K, Q.X, Q.Y, T, Copy(It, TabP + 1, MaxInt), 1, I * 0.9 + 0.5);
    end
    else
    begin
      Q := P(Sc.FCardX0 + Sc.FCardW / 2, Y);
      DrawFxText(Dest, Sc.FGlyphs, St, K, Q.X, Q.Y, T, It, 1, I * 0.9);
    end;
  end;
end;

{ Select Paper card: the cards side by side, the chosen one lifted with a red
  frame; every player's character flies on its card. }
procedure TPainter.DrawSelectCards(Dest: TBGRABitmap);
var
  Sc: TGameScene;
  I: Integer;
  X, Y, T, Up: Single;
  Q: TPointF;
  Fr: TBGRAPixel;
  St: TTextStyle;
begin
  Sc := FScene;
  T := Sc.FMenuT;
  if Length(Sc.FSelSpr) < Sc.SelCount then Exit;
  for I := Sc.FSelTop to Min(Sc.SelCount, Sc.FSelTop + SelVisible) - 1 do
  begin
    X := Sc.SelCardX(I);
    Y := SelY;
    if I = Sc.FSel then Y := Y - 22 + 4 * Sin(T * 3);
    if not RowsHit(Y - 10, Y + SelCardH + 20) then Continue;
    Q := P(X, Y);
    if FRaster then BlendBitmap(Dest, Round(Q.X), Round(Q.Y), Sc.FSelSpr[I]);
    if I = Sc.FSel then
    begin
      Fr := BGRA(196, 44, 34, 230);
      Box(Dest, X - 7, Y - 7, X + SelCardW + 7, Y - 3, Fr);
      Box(Dest, X - 7, Y + SelCardH + 3, X + SelCardW + 7, Y + SelCardH + 7, Fr);
      Box(Dest, X - 7, Y - 7, X - 3, Y + SelCardH + 7, Fr);
      Box(Dest, X + SelCardW + 3, Y - 7, X + SelCardW + 7, Y + SelCardH + 7, Fr);
      DPoly(Dest, [P(X + SelCardW / 2 - 12, Y + SelCardH + 16), P(X + SelCardW / 2 + 12, Y + SelCardH + 16),
        P(X + SelCardW / 2, Y + SelCardH + 30)], Fr);
    end;
    if I < Length(Sc.FSelPlayers) then
    begin
      if I = Sc.FSel then Up := Cos(Min(1, Frac(T * 1.3) / 0.35) * Pi) else Up := Sin(T * 4 + I * 1.7);
      DrawCharacter(Dest, Sc.FSelPlayers[I].Character, X + SelCardW / 2 + 2, Y + 128 + 5 * Sin(T * 2.2 + I),
        -0.06, IfThen(I = Sc.FSel, 1.12, 0.95), Up, 1);
    end;
  end;
  // more cards to the left / right
  Fr := BGRA(196, 44, 34, 200);
  if Sc.FSelTop > 0 then
  begin
    X := Sc.SelCardX(Sc.FSelTop) - 30;
    DPoly(Dest, [P(X, SelY + SelCardH / 2 - 20), P(X, SelY + SelCardH / 2 + 20), P(X - 18, SelY + SelCardH / 2)], Fr);
  end;
  if Sc.FSelTop + SelVisible < Sc.SelCount then
  begin
    X := Sc.SelCardX(Sc.FSelTop + SelVisible - 1) + SelCardW + 30;
    DPoly(Dest, [P(X, SelY + SelCardH / 2 - 20), P(X, SelY + SelCardH / 2 + 20), P(X + 18, SelY + SelCardH / 2)], Fr);
  end;
  // the Quit button (first entry only): a small paper card, red when chosen
  if Sc.SelHasQuit and RowsHit(SelQuitY - 30, SelQuitY + SelQuitH + 20) then
  begin
    X := DesignW / 2 - SelQuitW / 2;
    if Sc.FSel = Sc.SelCount then Y := SelQuitY - 6 + 2 * Sin(T * 3) else Y := SelQuitY;
    Box(Dest, X + 5, Y + 7, X + SelQuitW + 5, Y + SelQuitH + 7, BGRA(0, 0, 0, 60));
    Box(Dest, X, Y, X + SelQuitW, Y + SelQuitH, BGRA(246, 238, 222, 250));
    if Sc.FSel = Sc.SelCount then Fr := BGRA(196, 44, 34, 235) else Fr := BGRA(178, 40, 34, 160);
    Box(Dest, X, Y, X + SelQuitW, Y + 3, Fr);
    Box(Dest, X, Y + SelQuitH - 3, X + SelQuitW, Y + SelQuitH, Fr);
    Box(Dest, X, Y, X + 3, Y + SelQuitH, Fr);
    Box(Dest, X + SelQuitW - 3, Y, X + SelQuitW, Y + SelQuitH, Fr);
    if Sc.FSel = Sc.SelCount then
    begin
      Box(Dest, X + 6, Y + 6, X + SelQuitW - 6, Y + SelQuitH - 6, BGRA(178, 40, 34, 30));
      DPoly(Dest, [P(X - 26, Y + SelQuitH / 2 - 9), P(X - 10, Y + SelQuitH / 2), P(X - 26, Y + SelQuitH / 2 + 9)], Fr);
      DPoly(Dest, [P(X + SelQuitW + 26, Y + SelQuitH / 2 - 9), P(X + SelQuitW + 10, Y + SelQuitH / 2),
        P(X + SelQuitW + 26, Y + SelQuitH / 2 + 9)], Fr);
      St := Sc.FFx.Menus[Sc.MenuStyle].Sel;
    end
    else
      St := Sc.FFx.Menus[Sc.MenuStyle].Item;
    Q := P(DesignW / 2, Y + (SelQuitH - St.Size * 1.36) / 2);
    if FRaster then DrawFxText(Dest, Sc.FGlyphs, St, Sc.FScale, Q.X, Q.Y, T, 'Quit', 1);
  end;
end;

{ ---------- the other characters (same size and hit outline as the crane) ---------- }

{ an ellipse in the character's own (rotated) coordinates }
procedure TPainter.COval(B: TBGRABitmap; CX, CY, RX, RY, X, Y, A, K: Single; C: TBGRAPixel);
var
  I: Integer;
  Pts: array[0..13] of TPointF;
begin
  for I := 0 to 13 do
    Pts[I] := PointF(CX + RX * Cos(I * 2 * Pi / 14), CY + RY * Sin(I * 2 * Pi / 14));
  Rot(B, Pts, X, Y, A, K, C);
end;

{ a red and gold paper dragon: a waving body of scales behind the head }
procedure TPainter.DrawDragon(Dest: TBGRABitmap; X, Y, A, K, Up, Sh: Single);
var
  I: Integer;
  T, BX, BY, R: Single;
  Red, Gold, Dark: TBGRAPixel;
begin
  T := FScene.FTime;
  Red := Darken(Hex('#D23A2C'), Sh);
  Gold := Darken(Hex('#F0B830'), Sh);
  Dark := Darken(Hex('#8A1E18'), Sh);
  // the body from the tail to the neck
  for I := 9 downto 0 do
  begin
    BX := -6 - I * 7.5;
    BY := 5 * Sin(T * 7 - I * 0.8) + I * 0.6;
    R := 9 - I * 0.6;
    if I = 9 then
      Rot(Dest, [PointF(BX - 4, BY), PointF(BX - 18, BY - 9), PointF(BX - 12, BY), PointF(BX - 18, BY + 9)], X, Y, A, K, Gold);
    Rot(Dest, [PointF(BX - 2, BY - R - 5), PointF(BX + 3, BY - R + 1), PointF(BX - 5, BY - R + 1)], X, Y, A, K, Gold);
    COval(Dest, BX, BY, R * 0.9, R, X, Y, A, K, IfThen(Odd(I), Red, Dark));
    COval(Dest, BX + 1, BY + R * 0.45, R * 0.6, R * 0.35, X, Y, A, K, Gold);
  end;
  // little legs with claws, paddling with the flap
  Rot(Dest, [PointF(-4, 6), PointF(0, 6), PointF(-2 + 4 * Up, 16), PointF(-6 + 4 * Up, 16)], X, Y, A, K, Dark);
  Rot(Dest, [PointF(-34, 7), PointF(-30, 7), PointF(-32 - 4 * Up, 17), PointF(-36 - 4 * Up, 17)], X, Y, A, K, Dark);
  // head: jaw, snout, horns, whiskers, eye
  Rot(Dest, [PointF(2, -6), PointF(26, -8), PointF(36, -3), PointF(34, 4), PointF(18, 8), PointF(2, 8)], X, Y, A, K, Red);
  Rot(Dest, [PointF(18, 3), PointF(36, 1), PointF(32, 8), PointF(16, 9)], X, Y, A, K, Gold);
  Rot(Dest, [PointF(8, -6), PointF(4, -22), PointF(12, -8)], X, Y, A, K, Gold);
  Rot(Dest, [PointF(14, -7), PointF(14, -20), PointF(19, -8)], X, Y, A, K, Gold);
  Rot(Dest, [PointF(34, -1), PointF(48, -10 + 4 * Sin(T * 5)), PointF(35, 1)], X, Y, A, K, Gold);
  Rot(Dest, [PointF(33, 3), PointF(46, 10 + 4 * Sin(T * 5 + 1)), PointF(33, 5)], X, Y, A, K, Gold);
  COval(Dest, 20, -2, 3, 3, X, Y, A, K, Darken(Hex('#FFF4C0'), Sh));
  COval(Dest, 21, -2, 1.5, 1.8, X, Y, A, K, BGRA(20, 16, 12));
  // a small gold fin beats like a wing
  Rot(Dest, [PointF(-14, -8), PointF(-2, -8), PointF(-6 + 6 * Up, -10 - 24 * Up)], X, Y, A, K, Gold);
end;

{ a panda pedalling a bicycle with paper wings }
procedure TPainter.DrawPanda(Dest: TBGRABitmap; X, Y, A, K, Up, Sh: Single);
var
  T, PA: Single;
  White, Black, Frame, Paper, Fold: TBGRAPixel;
begin
  T := FScene.FTime;
  PA := T * 9;                       // the pedals
  White := Darken(Hex('#F4F2EC'), Sh);
  Black := Darken(Hex('#26242A'), Sh);
  Frame := Darken(Hex('#2E78C0'), Sh);
  Paper := Darken(Hex('#F4C4D0'), Sh);   // pink paper wings
  Fold := Darken(Hex('#DC98AC'), Sh);
  // far wing
  Rot(Dest, [PointF(-12, -2), PointF(2, -2), PointF(-6 - 8 * Up, -4 - 30 * Up), PointF(-20 - 4 * Up, -2 - 24 * Up)],
    X, Y, A, K, Fold);
  // wheels (tyre, rim, hub) and the frame
  COval(Dest, -20, 14, 11, 11, X, Y, A, K, Black);
  COval(Dest, -20, 14, 7.5, 7.5, X, Y, A, K, Darken(Hex('#C8C4BC'), Sh));
  COval(Dest, 22, 14, 11, 11, X, Y, A, K, Black);
  COval(Dest, 22, 14, 7.5, 7.5, X, Y, A, K, Darken(Hex('#C8C4BC'), Sh));
  Rot(Dest, [PointF(-20, 13), PointF(0, 13), PointF(-6, -2), PointF(-9, -2)], X, Y, A, K, Frame);
  Rot(Dest, [PointF(-1, 12), PointF(22, 13), PointF(13, -4), PointF(10, -4)], X, Y, A, K, Frame);
  Rot(Dest, [PointF(-8, -3), PointF(13, -5), PointF(13, -2), PointF(-8, 0)], X, Y, A, K, Frame);
  Rot(Dest, [PointF(12, -5), PointF(16, -12), PointF(19, -11), PointF(15, -4)], X, Y, A, K, Black);
  COval(Dest, 0, 13, 3, 3, X, Y, A, K, Black);
  // the leg on the pedal going round
  Rot(Dest, [PointF(-4, -4), PointF(2, -4), PointF(Cos(PA) * 6 + 2, 13 + Sin(PA) * 6), PointF(Cos(PA) * 6 - 3, 13 + Sin(PA) * 6)],
    X, Y, A, K, Black);
  // body, arm, head with ears and eye patches
  COval(Dest, -4, -12, 11, 12, X, Y, A, K, White);
  Rot(Dest, [PointF(-2, -16), PointF(4, -18), PointF(17, -11), PointF(14, -8)], X, Y, A, K, Black);
  COval(Dest, 4, -28, 10, 9, X, Y, A, K, White);
  COval(Dest, -2, -36, 3.5, 3.5, X, Y, A, K, Black);
  COval(Dest, 9, -36, 3.5, 3.5, X, Y, A, K, Black);
  COval(Dest, 7, -28, 3, 3.6, X, Y, A, K, Black);
  COval(Dest, 7.5, -28.5, 1.1, 1.1, X, Y, A, K, White);
  COval(Dest, 13, -24, 2, 1.6, X, Y, A, K, Black);
  // near paper wing on the back
  Rot(Dest, [PointF(-14, -14), PointF(2, -14), PointF(-4 + 8 * Up, -16 - 34 * Up), PointF(-18 + 4 * Up, -14 - 28 * Up)],
    X, Y, A, K, Paper);
  Rot(Dest, [PointF(-14, -14), PointF(-4 + 8 * Up, -16 - 34 * Up), PointF(-9 + 6 * Up, -15 - 28 * Up)], X, Y, A, K,
    Mix(Paper, Fold, 0.6));
end;

{ a brown owl with big golden eyes }
procedure TPainter.DrawOwl(Dest: TBGRABitmap; X, Y, A, K, Up, Sh: Single);
var
  Brown, DarkB, Belly, Gold: TBGRAPixel;
begin
  Brown := Darken(Hex('#8A5E3A'), Sh);
  DarkB := Darken(Hex('#5E3C24'), Sh);
  Belly := Darken(Hex('#E8D2A8'), Sh);
  Gold := Darken(Hex('#F2C230'), Sh);
  // far wing, tail, body, belly with feather marks
  Rot(Dest, [PointF(-8, -6), PointF(8, -6), PointF(0 - 6 * Up, -8 - 30 * Up), PointF(-14 - 4 * Up, -6 - 24 * Up)],
    X, Y, A, K, DarkB);
  Rot(Dest, [PointF(-14, 4), PointF(-30, 0), PointF(-32, 8), PointF(-14, 10)], X, Y, A, K, DarkB);
  COval(Dest, 0, 2, 18, 14, X, Y, A, K, Brown);
  COval(Dest, 6, 6, 10, 8, X, Y, A, K, Belly);
  Rot(Dest, [PointF(2, 3), PointF(4, 6), PointF(6, 3)], X, Y, A, K, DarkB);
  Rot(Dest, [PointF(7, 7), PointF(9, 10), PointF(11, 7)], X, Y, A, K, DarkB);
  // head with ear tufts, eyes and beak
  COval(Dest, 14, -12, 13, 11, X, Y, A, K, Brown);
  Rot(Dest, [PointF(4, -18), PointF(2, -32), PointF(10, -21)], X, Y, A, K, DarkB);
  Rot(Dest, [PointF(18, -21), PointF(24, -33), PointF(25, -18)], X, Y, A, K, DarkB);
  COval(Dest, 11, -13, 5.5, 5.5, X, Y, A, K, Gold);
  COval(Dest, 21, -13, 5.5, 5.5, X, Y, A, K, Gold);
  COval(Dest, 12, -13, 2.6, 2.8, X, Y, A, K, BGRA(20, 16, 12));
  COval(Dest, 22, -13, 2.6, 2.8, X, Y, A, K, BGRA(20, 16, 12));
  Rot(Dest, [PointF(15, -9), PointF(19, -9), PointF(17, -3)], X, Y, A, K, Darken(Hex('#E8902A'), Sh));
  // near wing
  Rot(Dest, [PointF(-10, -2), PointF(8, -2), PointF(2 + 8 * Up, -4 - 36 * Up), PointF(-12 + 4 * Up, -2 - 30 * Up)],
    X, Y, A, K, Brown);
  Rot(Dest, [PointF(-10, -2), PointF(2 + 8 * Up, -4 - 36 * Up), PointF(-4 + 6 * Up, -3 - 30 * Up)], X, Y, A, K, DarkB);
end;

{ a phoenix: red and gold, a long tail of flowing feathers }
procedure TPainter.DrawPhoenix(Dest: TBGRABitmap; X, Y, A, K, Up, Sh: Single);
const
  TailCols: array[0..3] of string = ('#D8402E', '#F0B030', '#8A3AA8', '#E86A2A');
var
  I, J: Integer;
  T, W: Single;
  Pts: array[0..9] of TPointF;
  Red, Gold, Orange: TBGRAPixel;
begin
  T := FScene.FTime;
  Red := Darken(Hex('#D23A2C'), Sh);
  Gold := Darken(Hex('#F2C030'), Sh);
  Orange := Darken(Hex('#EE7A2A'), Sh);
  // the tail feathers: ribbons that wave behind
  for I := 0 to 3 do
  begin
    for J := 0 to 4 do
    begin
      W := 7 * Sin(T * 5 - J * 0.9 + I * 0.7);
      Pts[J] := PointF(-14 - J * 13, -2 + I * 3 + W + J * (I - 1.5) * 2.4);
      Pts[9 - J] := PointF(-14 - J * 13, -2 + I * 3 + W + J * (I - 1.5) * 2.4 + 4 - J * 0.5);
    end;
    Rot(Dest, Pts, X, Y, A, K, Darken(Hex(TailCols[I]), Sh));
    COval(Dest, Pts[4].X - 3, (Pts[4].Y + Pts[5].Y) / 2, 5, 3.5, X, Y, A, K, Gold);
  end;
  // far wing, body, neck, head with crest and beak
  Rot(Dest, [PointF(-6, -4), PointF(12, -4), PointF(4 - 6 * Up, -4 - 30 * Up), PointF(-12 - 6 * Up, -2 - 22 * Up)],
    X, Y, A, K, Orange);
  COval(Dest, 0, 0, 18, 9, X, Y, A, K, Red);
  COval(Dest, 4, 4, 11, 4, X, Y, A, K, Gold);
  Rot(Dest, [PointF(12, -4), PointF(28, -18), PointF(34, -14), PointF(20, 2)], X, Y, A, K, Red);
  COval(Dest, 32, -17, 6, 5, X, Y, A, K, Red);
  Rot(Dest, [PointF(29, -21), PointF(24, -34), PointF(31, -22)], X, Y, A, K, Gold);
  Rot(Dest, [PointF(31, -22), PointF(31, -36), PointF(34, -21)], X, Y, A, K, Gold);
  Rot(Dest, [PointF(33, -21), PointF(38, -33), PointF(36, -19)], X, Y, A, K, Gold);
  Rot(Dest, [PointF(37, -18), PointF(46, -15), PointF(37, -14)], X, Y, A, K, Gold);
  COval(Dest, 34, -18, 1.4, 1.4, X, Y, A, K, BGRA(20, 16, 12));
  // near wing: red with a gold edge
  Rot(Dest, [PointF(-8, -5), PointF(10, -5), PointF(2 + 8 * Up, -6 - 38 * Up), PointF(-14 + 2 * Up, -4 - 30 * Up)],
    X, Y, A, K, Red);
  Rot(Dest, [PointF(2 + 8 * Up, -6 - 38 * Up), PointF(-14 + 2 * Up, -4 - 30 * Up), PointF(-8 + 4 * Up, -4 - 24 * Up),
    PointF(3 + 6 * Up, -6 - 30 * Up)], X, Y, A, K, Gold);
end;

procedure TPainter.DrawParticles(Dest: TBGRABitmap);
var
  Sc: TGameScene;
  I: Integer;
  F: Single;
begin
  Sc := FScene;
  for I := 0 to High(Sc.FParts) do
    with Sc.FParts[I] do
    begin
      if Life <= 0 then Continue;
      if not RowsHit(Y - 20, Y + 20) then Continue;
      F := Life / MaxLife;
      if Kind = 0 then
        Glow(Dest, X, Y, Size * (0.5 + F), WithAlpha(C, Round(255 * F)))
      else
        DPoly(Dest, [P(X + Cos(Spin) * Size, Y + Sin(Spin) * Size), P(X - Sin(Spin) * Size * 0.6, Y + Cos(Spin) * Size * 0.6),
          P(X - Cos(Spin) * Size, Y - Sin(Spin) * Size)], WithAlpha(C, Round(255 * Min(1, F * 2))));
    end;
end;

procedure TPainter.DrawWeather(Dest: TBGRABitmap);
const
  LeafCols: array[0..3] of string = ('#C8402A', '#E07A2A', '#E8B030', '#A8302A');
var
  Sc: TGameScene;
  I: Integer;
  T, N, X, Y, Span, H1, H2, H3, Spd, Len, VX, P0, R, Sw, Ang, Bl: Single;
  C: TBGRAPixel;
  Pts: array of TPointF;
begin
  Sc := FScene;
  T := Sc.FTime;
  N := Sc.Night;
  Span := Sc.FVisR - Sc.FVisL + 160;
  case Sc.FSeason of
    1: begin
         VX := -160;
         C := Mix(BGRA(214, 224, 238), BGRA(170, 186, 214), N);
         for I := 0 to 399 do
         begin
           H1 := Hash01(I * 3 + 11);
           H2 := Hash01(I * 3 + 12);
           H3 := Hash01(I * 3 + 13);
           Spd := 560 + 280 * H3;
           Len := 12 + 16 * H3;
           P0 := PFrac(H2 + T * Spd / (DesignH + 80));
           Y := -40 + P0 * (DesignH + 80);
           if not RowsHit(Y, Y + Len) then Continue;
           X := Sc.FVisL - 80 + PFrac(H1 + (VX * P0 * (DesignH + 80) / Spd - Sc.FScroll * 0.6) / Span) * Span;
           RainStreak(Dest, X, Y, VX * Len / Spd, Len, 0.9 + 0.6 * H3, WithAlpha(C, Round(70 + 90 * H3)));
         end;
         if Sc.FFlash > 0.01 then
         begin
           if Sc.FBoltOn and (Length(Sc.FBolt) > 1) and RowsHit(0, Base1) then
           begin
             SetLength(Pts, Length(Sc.FBolt));
             for I := 0 to High(Pts) do Pts[I] := P(Sc.FBolt[I].X, Sc.FBolt[I].Y);
             DPolyLine(Dest, Pts, BGRA(190, 200, 255, 90), Max(2, S(8)));
             DPolyLine(Dest, Pts, BGRA(255, 255, 255, 245), Max(1, S(2.4)));
           end;
           if FRaster then
             Dest.FillRect(0, 0, Dest.Width, Dest.Height, BGRA(225, 230, 255, Round(80 * Sc.FFlash)),
               dmDrawWithTransparency);
         end;
       end;
    3: begin
         C := Mix(BGRA(255, 255, 255), BGRA(214, 224, 245), N);
         for I := 0 to 379 do
         begin
           H1 := Hash01(I * 3 + 41);
           H2 := Hash01(I * 3 + 42);
           H3 := Hash01(I * 3 + 43);
           Spd := 22 + 60 * H3;
           R := 1 + 2.6 * H3;
           P0 := PFrac(H2 + T * Spd / (DesignH + 40));
           Y := -20 + P0 * (DesignH + 40);
           if not RowsHit(Y - R, Y + R) then Continue;
           Sw := Sin(T * (0.8 + H1) + I) * (6 + 14 * H3);
           X := Sc.FVisL - 80 + PFrac(H1 - Sc.FScroll * (0.3 + 0.5 * H3) / Span) * Span + Sw;
           Ell(Dest, X, Y, R, R, WithAlpha(C, Round(150 + 100 * H3)));
         end;
       end;
    2: for I := 0 to 99 do
       begin
         H1 := Hash01(I * 3 + 61);
         H2 := Hash01(I * 3 + 62);
         H3 := Hash01(I * 3 + 63);
         Spd := 30 + 40 * H3;
         R := 4 + 3.5 * H3;
         P0 := PFrac(H2 + T * Spd / (DesignH + 60));
         Y := -30 + P0 * (DesignH + 60);
         if not RowsHit(Y - R, Y + R) then Continue;
         Sw := Sin(T * (1.1 + H1) + I) * (18 + 26 * H3);
         X := Sc.FVisL - 80 + PFrac(H1 - Sc.FScroll * (0.4 + 0.4 * H3) / Span) * Span + Sw;
         Ang := T * (1.5 + 2.5 * H1) + I;
         C := Darken(Hex(LeafCols[I mod 4]), Sc.Shade);
         DPoly(Dest, [P(X + Cos(Ang) * R, Y + Sin(Ang) * R * 0.6),
           P(X - Sin(Ang) * R * 0.45, Y + Cos(Ang) * R * 0.27),
           P(X - Cos(Ang) * R, Y - Sin(Ang) * R * 0.6),
           P(X + Sin(Ang) * R * 0.45, Y - Cos(Ang) * R * 0.27)], C);
       end;
  else
    if N > 0.05 then  // summer nights: fireflies drifting past
      for I := 0 to 59 do
      begin
        H1 := Hash01(I * 3 + 81);
        H2 := Hash01(I * 3 + 82);
        H3 := Hash01(I * 3 + 83);
        X := Sc.FVisL - 40 + PFrac(H1 - Sc.FScroll * 0.9 / Span) * Span + 30 * Sin(T * (0.3 + 0.4 * H2) + I);
        Y := WaterY - 20 - H3 * 300 + 14 * Sin(T * (0.5 + 0.5 * H1) + I * 1.3);
        Bl := Sin(T * (1.5 + 2 * H2) + I * 2.1);
        if Bl <= 0 then Continue;
        Glow(Dest, X, Y, 6, WithAlpha(Hex('#D8FF6A'), Round(255 * N * Bl * Bl * Bl)));
      end;
  end;
end;

procedure TPainter.RenderBand(Dest: TBGRABitmap; ATop: Integer);
var
  LY0, LY1: Single;
  Sc: TGameScene;
  Y, W, H, A, M, R, MT, MB, LTop, LH: Integer;
  T0: Double;
  Q: TPointF;

  procedure Mark(Id: TLayerId);
  var
    T: Double;
  begin
    T := HiResMs;
    LayerMs[Id] := LayerMs[Id] + (T - T0);
    T0 := T;
  end;

  procedure Pair(const Arr: array of TBGRABitmap; const Pos: TPoint; const Svg: array of string);
  begin
    if FSvg <> nil then FSvg.Raw(Svg[M]);
    if not FRaster then Exit;
    BlendBitmap(Dest, Pos.X, Pos.Y - ATop, Arr[Sc.FFrom]);
    if (Sc.FFrom <> Sc.FTo) and (A > 0) then
      BlendBitmap(Dest, Pos.X, Pos.Y - ATop, Arr[Sc.FTo], A);
  end;

  { a tileable strip, scrolled by Shift design px }
  procedure Strip(const Arr: array of TBGRABitmap; const Pos: TPoint; const Svg: array of string; Shift: Single);
  var
    X0, X: Integer;
    Off: Single;
  begin
    if (Arr[Sc.FFrom] = nil) or (Sc.FStripW <= 0) then Exit;
    Off := PFrac(Shift / Period) * Sc.FStripW;
    X0 := Round(Sc.FOffX - Off);
    while X0 > 0 do X0 := X0 - Sc.FStripW;
    if FSvg <> nil then
    begin
      X := X0;
      while X < W do
      begin
        FSvg.Raw(Format('<g transform="translate(%d,0)">', [X - Sc.FStripPad]) + LineEnding + Svg[M] + '</g>');
        X := X + Sc.FStripW;
      end;
    end;
    if not FRaster then Exit;
    X := X0;
    while X < W do
    begin
      BlendBitmap(Dest, X, Pos.Y - ATop, Arr[Sc.FFrom]);
      if (Sc.FFrom <> Sc.FTo) and (A > 0) then
        BlendBitmap(Dest, X, Pos.Y - ATop, Arr[Sc.FTo], A);
      X := X + Sc.FStripW;
    end;
  end;

  procedure Shadowed(Id: TLayerId; Y0, Y1: Single; Proc: TDrawProc);
  begin
    TargetBand(ATop, H);
    if RowsHit(Y0, Y1 + 30) then
    begin
      if FRaster then
      begin
        if (FLayer.Width <> W) or (FLayer.Height <> LH) then FLayer.SetSize(W, LH);
        FLayerTop := LTop;
        FRowA := Floor(Sc.FOffY + (Y0 - 12) * Sc.FScale) - LTop;
        FRowB := Ceil(Sc.FOffY + (Y1 + 12) * Sc.FScale) - LTop;
      end
      else
        FLayerTop := 0;
      FPart := 0;
      BeginLayer;
      Proc(FLayer);
      CompositeLayer(Dest, ATop, LayerDepth[Id]);
      TargetBand(ATop, H);
    end;
    FPart := 1;
    Proc(Dest);
    FPart := 0;
  end;

  procedure Sprite(Spr: TBGRABitmap; const Svg: string; DX, DY: Single; Center: Boolean);
  begin
    if Spr = nil then Exit;
    if Center then Q := PointF(Round((W - Spr.Width) / 2), Round(P(0, DY).Y))
    else Q := P(DX, DY);
    if FSvg <> nil then
      FSvg.Raw(Format('<g transform="translate(%s,%s)">', [FSvg.N(Round(Q.X)), FSvg.N(Round(Q.Y))]) +
        LineEnding + Svg + '</g>');
    if FRaster then BlendBitmap(Dest, Round(Q.X), Round(Q.Y), Spr);
  end;

begin
  Sc := FScene;
  W := Sc.FWidth;
  if Dest <> nil then H := Dest.Height else H := Sc.FHeight;
  T0 := HiResMs;
  A := Round(255 * Sc.FBlend);
  M := Sc.CurrentMode;
  R := Max(1, Round(S(7) * MaxDepth / 4));
  MB := (2 * R + 3) * 4;
  MT := Round(S(6) * MaxDepth) + MB;
  LTop := Floor((ATop - MT) / 4) * 4;
  LH := ATop + H + MB - LTop;
  TargetBand(ATop, H);

  if Sc.LayerOn[lySky] then
  begin
    if FSvg <> nil then FSvg.Raw(Sc.FSvgSky[M]);
    if FRaster then
    begin
      for Y := 0 to H - 1 do
        if ATop + Y < Sc.FHeight then
          Move(RowPtr(Sc.FSky[Sc.FFrom], ATop + Y)^, RowPtr(Dest, Y)^, W * SizeOf(TBGRAPixel));
      if (Sc.FFrom <> Sc.FTo) and (A > 0) then
        BlendBitmap(Dest, 0, -ATop, Sc.FSky[Sc.FTo], A);
    end;
  end
  else if FRaster then
    if Sc.TransparentBack then Dest.FillTransparent else Dest.Fill(BGRA(150, 170, 180));
  Mark(lySky);
  if Sc.LayerOn[lyStars] then DrawStars(Dest);
  Mark(lyStars);
  if Sc.LayerOn[lyClouds] then DrawClouds(Dest);
  Mark(lyClouds);
  if Sc.LayerOn[lyFarPeaks] then Strip(Sc.FR0, Sc.FR0Pos, Sc.FSvgR0, Sc.FScroll * Par0);
  Mark(lyFarPeaks);
  if Sc.LayerOn[lyMist] then DrawMist(Dest, 0);
  Mark(lyMist);
  if Sc.LayerOn[lyMidPeaks] then Strip(Sc.FR1, Sc.FR1Pos, Sc.FSvgR1, Sc.FScroll * Par1);
  Mark(lyMidPeaks);
  if Sc.LayerOn[lyMist] then DrawMist(Dest, 1);
  Mark(lyMist);
  if Sc.LayerOn[lyRiver] then
  begin
    Pair(Sc.FRiver, Sc.FRiverPos, Sc.FSvgRiver);
    DrawWaves(Dest);
  end;
  Mark(lyRiver);
  if Sc.LayerOn[lyObstacles] then
  begin
    FPart := 0;
    DrawObstacles(Dest);
  end;
  Mark(lyObstacles);
  if Sc.LayerOn[lyMist] then DrawMist(Dest, 2);
  Mark(lyMist);
  // the shadow layers only clear and composite the rows their visible things use
  if Sc.LayerOn[lyLanterns] then
  begin
    if Sc.LayerRows(0, LY0, LY1) then Shadowed(lyLanterns, LY0, LY1, @DrawLanterns);
    if Sc.LayerRows(1, LY0, LY1) then Shadowed(lyLanterns, LY0, LY1, @DrawBonus);
  end;
  Mark(lyLanterns);
  if Sc.LayerRows(2, LY0, LY1) and Sc.LayerOn[lyHawks] then Shadowed(lyHawks, LY0, LY1, @DrawHawks);
  if Sc.LayerOn[lyHawks] then
  begin
    if Sc.LayerRows(3, LY0, LY1) then Shadowed(lyHawks, LY0, LY1, @DrawHazards);
  end;
  Mark(lyHawks);
  if Sc.LayerOn[lyPlayer] then
  begin
    TargetBand(ATop, H);
    DrawGhost(Dest);
    Shadowed(lyPlayer, Sc.FY - 70, Sc.FY + 70, @DrawCrane);
  end;
  Mark(lyPlayer);
  TargetBand(ATop, H);
  if Sc.LayerOn[lyParticles] then DrawParticles(Dest);
  Mark(lyParticles);
  if Sc.LayerOn[lyWeather] then DrawWeather(Dest);
  if FRaster and (Sc.FSnap <> nil) and (Sc.FSnapFade > 0) then
    BlendBitmap(Dest, 0, -ATop, Sc.FSnap, Round(255 * Sc.FSnapFade));
  Mark(lyWeather);
  if Sc.FShowCaption and Sc.FHudOn and Sc.LayerOn[lyHUD] and (Sc.FMenu = msNone) then
    Sprite(Sc.FHud, Sc.FSvgHud, 16, 14, False);
  Mark(lyHUD);
  if Sc.LayerOn[lyCaption] and (Sc.FCard <> nil) then
  begin
    Sprite(Sc.FCard, Sc.FSvgCard, 0, Sc.FCardTop, True);
    if FRaster and (Sc.FMenu <> msNone) then DrawMenuTexts(Dest);
    if Sc.FMenu = msSelect then DrawSelectCards(Dest);
    // the selected item: a red paper tab on both sides, gently bobbing
    if (Sc.FMenuN > 0) and (Sc.FSel >= 0) and (Sc.FMenu <> msSelect) then
    begin
      // the highlight bar under the selected item, then the item sprites
      Box(Dest, Sc.FCardX0 + 60, Sc.FItemY0 + Sc.FSel * Sc.FItemH + 4, Sc.FCardX1 - 60,
        Sc.FItemY0 + (Sc.FSel + 1) * Sc.FItemH - 2, BGRA(178, 40, 34, 26));
      // (the items' letters are drawn by DrawMenuTexts)
      Q.Y := Sc.FItemY0 + (Sc.FSel + 0.5) * Sc.FItemH;
      Q.X := 3 * Sin(Sc.FMenuT * 5);
      DPoly(Dest, [P(Sc.FCardX0 + 30 + Q.X, Q.Y - 9), P(Sc.FCardX0 + 46 + Q.X, Q.Y), P(Sc.FCardX0 + 30 + Q.X, Q.Y + 9)],
        BGRA(196, 44, 34, 235));
      DPoly(Dest, [P(Sc.FCardX1 - 30 - Q.X, Q.Y - 9), P(Sc.FCardX1 - 46 - Q.X, Q.Y), P(Sc.FCardX1 - 30 - Q.X, Q.Y + 9)],
        BGRA(196, 44, 34, 235));
      Box(Dest, Sc.FCardX0 + 54, Q.Y + 15, Sc.FCardX1 - 54, Q.Y + 17, BGRA(196, 44, 34, 120));
      if Sc.FMenu = msCharacter then DrawCharBoard(Dest);   // over the selection marks
    end;
  end;
  Mark(lyCaption);
  if Dest <> nil then Dest.InvalidateBitmap;
end;

{ ====================================================================== }
{ TGameScene                                                              }
{ ====================================================================== }

constructor TGameScene.Create;
begin
  inherited Create;
  FShowCaption := True;
  FillChar(LayerOn, SizeOf(LayerOn), 1);
  FVisL := 0;
  FVisR := DesignW;
  FScale := 1;
  AutoSeconds := 30;
  FadeSeconds := 3;
  FAuto := True;
  FFrom := 0;
  FTo := 0;
  FSeason := 0;
  FPendingSeason := -1;
  FFlashT := 10;
  FFlashNext := 5;
  FCutter := TPainter.Create(Self);
  FAcc := TBGRABitmap.Create(1, 1);
  FCache := TStringList.Create;
  FCache.Sorted := True;
  FList := TStringList.Create;
  FListNames := TStringList.Create;
  FMap := TPCMap.Create;
  FPlayer := nil;
  FFx := TMenuFxSet.Create;
  FGlyphs := TGlyphCache.Create;
  LoadMenuFx;
  FMapMusic := -1;
  FRng := 20261016;
  MakePalettes;
  Generate;
  FMusicVol := 7;
  FSfxVol := 8;
  FDifficulty := 1;
  FHudOn := True;
  FVSyncWanted := True;
  FPlayTrack := 1;
  LoadSettings;
  FDiffUser := FDifficulty;
  LoadScores;
  FSeed := 20261016;
  ResetWorld;
  FState := gsTitle;
  FAutoPilot := True;
  OpenMenu(msSelect);    // who is flying: always chosen before the main menu
  FSelCanBack := False;
end;

destructor TGameScene.Destroy;
begin
  FreeSelect;
  FFx.Free;
  FGlyphs.Free;
  FreeResources;
  FHud.Free;
  FCard.Free;
  FreeItems;
  ClearCache;
  FCache.Free;
  FList.Free;
  FListNames.Free;
  ClearShapeLib;
  FMap.Free;
  FPlayer.Free;
  FCutter.Free;
  FAcc.Free;
  FSnap.Free;
  FStaticSvg.Free;
  inherited Destroy;
end;

function TGameScene.P(X, Y: Single): TPointF;
begin
  Result := FCutter.P(X, Y);
end;

function TGameScene.S(V: Single): Single;
begin
  Result := V * FScale;
end;

function TGameScene.Rnd: Single;
begin
  FRng := FRng * 1664525 + 1013904223;
  Result := (FRng shr 8) / 16777216;
end;

procedure TGameScene.MakePalettes;
var
  I: Integer;

  procedure Rng(var Pl: TPal; const A, B, C: string);
  begin
    Pl.Range[0] := Hex(A); Pl.Range[1] := Hex(B); Pl.Range[2] := Hex(C);
  end;

begin
  with FPal[0] do
  begin
    SkyTop := Hex('#6C8CC8'); SkyBot := Hex('#F6C49A'); Glow := Hex('#FFD6A8'); SunC := Hex('#FFE3B0');
    Haze := Hex('#F6E2DA'); Water1 := Hex('#8FA6C8'); Water2 := Hex('#4E6A8E');
    Foliage := Hex('#5E8A5A'); Foliage2 := Hex('#7AA060'); Rock := Hex('#8A8078'); Lit := Hex('#FFD8B8');
    CloudLit := Hex('#FFE0D0'); CloudShade := Hex('#C8A0B0');
    SunX := 1250; SunY := 330; SunR := 38; MistK := 1.3; Moon := False;
  end;
  Rng(FPal[0], '#CDB8C8', '#A69CB6', '#6E7E8C');
  with FPal[1] do
  begin
    SkyTop := Hex('#3C86D0'); SkyBot := Hex('#CFE8F2'); Glow := Hex('#FFFFFF'); SunC := Hex('#FFF4CC');
    Haze := Hex('#F2F8F8'); Water1 := Hex('#5AA0B8'); Water2 := Hex('#2C6A84');
    Foliage := Hex('#3F8A48'); Foliage2 := Hex('#68A858'); Rock := Hex('#8C8C84'); Lit := Hex('#FFF6DC');
    CloudLit := Hex('#FFFFFF'); CloudShade := Hex('#C4D4DC');
    SunX := 1250; SunY := 120; SunR := 30; MistK := 0.85; Moon := False;
  end;
  Rng(FPal[1], '#B4D2CC', '#86B6AA', '#4E8A7A');
  with FPal[2] do
  begin
    SkyTop := Hex('#070B1C'); SkyBot := Hex('#22305A'); Glow := Hex('#3A4A7A'); SunC := Hex('#F4F0DC');
    Haze := Hex('#6A7AA6'); Water1 := Hex('#18264A'); Water2 := Hex('#08101E');
    Foliage := Hex('#1A3030'); Foliage2 := Hex('#22403A'); Rock := Hex('#2A2E3E'); Lit := Hex('#8A9AC8');
    CloudLit := Hex('#3A4676'); CloudShade := Hex('#1C2244');
    SunX := 1300; SunY := 120; SunR := 26; MistK := 0.7; Moon := True;
  end;
  Rng(FPal[2], '#2C3C62', '#223156', '#24324E');
  for I := 0 to 2 do
  begin
    FPal[I].Shade := ModeShade[I];
    SeasonTint(FPal[I], I);
  end;
end;

procedure TGameScene.SeasonTint(var Pl: TPal; M: Integer);
var
  I: Integer;
  K: Single;
begin
  K := ModeShade[M];
  Pl.Snow := Darken(Hex('#F2F6FA'), Max(0.5, K));
  Pl.SunHidden := False;
  case FSeason of
    1: begin
         if M = 2 then
         begin
           Pl.SkyTop := Hex('#0A0D15');
           Pl.SkyBot := Hex('#262A36');
         end
         else
         begin
           Pl.SkyTop := Darken(GreyMix(Pl.SkyTop, 0.75), 0.7);
           Pl.SkyBot := Darken(GreyMix(Pl.SkyBot, 0.7), 0.8);
           Pl.Glow := GreyMix(Pl.Glow, 0.6);
         end;
         Pl.SunHidden := True;
         for I := 0 to 2 do
           Pl.Range[I] := Mix(Darken(GreyMix(Pl.Range[I], 0.45), 0.92), Pl.SkyBot, 0.15 * (2 - I) / 2);
         Pl.Haze := GreyMix(Pl.Haze, 0.6);
         Pl.MistK := Pl.MistK * 1.6;
         Pl.Water1 := Darken(GreyMix(Pl.Water1, 0.5), 0.85);
         Pl.Water2 := Darken(GreyMix(Pl.Water2, 0.5), 0.82);
         Pl.Foliage := Darken(Pl.Foliage, 0.8);
         Pl.Foliage2 := Darken(Pl.Foliage2, 0.8);
         Pl.Lit := GreyMix(Pl.Lit, 0.6);
         Pl.CloudLit := Darken(Hex('#AEB4BD'), K);
         Pl.CloudShade := Darken(Hex('#7A818C'), K);
       end;
    2: begin
         Pl.Foliage := Darken(Hex('#C8462A'), K);
         Pl.Foliage2 := Darken(Hex('#E8A830'), K);
         for I := 1 to 2 do
           Pl.Range[I] := Mix(Pl.Range[I], Darken(Hex('#9A7A48'), K), 0.2 + 0.08 * I);
         if M <> 2 then Pl.SkyBot := Mix(Pl.SkyBot, Hex('#F4D6A0'), 0.35)
         else
         begin
           Pl.SunR := 40;
           Pl.SunC := Hex('#FFE8B8');
         end;
       end;
    3: begin
         if M = 2 then
         begin
           Pl.SkyTop := Hex('#070C1C');
           Pl.SkyBot := Hex('#26324F');
           Pl.Snow := Hex('#5C6890');
         end
         else
         begin
           Pl.SkyTop := Mix(Pl.SkyTop, Hex('#93AACB'), 0.45);
           Pl.SkyBot := Mix(Pl.SkyBot, Hex('#E4ECF3'), 0.5);
           if M = 0 then Pl.Snow := Hex('#F2E4DE');
           Pl.CloudLit := Hex('#FFFFFF');
         end;
         for I := 0 to 2 do
           Pl.Range[I] := Mix(Pl.Range[I], Darken(Hex('#9AAAB8'), K), 0.35);
         Pl.Foliage := Pl.Snow;
         Pl.Foliage2 := Mix(Pl.Foliage2, Pl.Snow, 0.5);
         Pl.Water1 := Mix(Pl.Water1, Darken(Hex('#9DB8C8'), K), 0.45);
         Pl.Water2 := Mix(Pl.Water2, Darken(Hex('#5C7C93'), K), 0.45);
         Pl.CloudShade := Mix(Pl.CloudShade, Darken(Hex('#B4C2D0'), K), 0.5);
       end;
  end;
end;

{ the two tileable ranges (peaks spread over one Period), stars, clouds }
{ the two ranges of the background theme: (W min, W max, H min, H max, step) }
procedure TGameScene.GeneratePeaks;
const
  Shape: array[0..MapThemeCount - 1, 0..1, 0..4] of Single = (
    ((55, 105, 140, 310, 1.0), (49, 99, 110, 280, 1.0)),      // karst river
    ((150, 230, 110, 200, 0.8), (140, 210, 90, 170, 0.8)),    // great wall: rolling hills
    ((55, 100, 130, 250, 1.0), (180, 240, 25, 55, 0.9)),      // pagoda town: low ground for the houses
    ((170, 260, 110, 210, 0.75), (160, 240, 90, 170, 0.75)),  // rice terraces: round hills
    ((130, 200, 120, 200, 0.8), (170, 240, 30, 70, 0.9)),     // bamboo forest: low ground for the stalks
    ((42, 72, 220, 320, 1.15), (40, 68, 180, 270, 1.2)));     // yellow mountains: tall and narrow
var
  R: Integer;
  X, W: Single;
begin
  RandSeed := 1688 + FTheme * 977;
  for R := 0 to 1 do
  begin
    SetLength(FPeaks[R], 0);
    X := 0;
    while X < Period - 40 do
    begin
      W := RandRange(Round(Shape[FTheme, R, 0]), Round(Shape[FTheme, R, 1]));
      SetLength(FPeaks[R], Length(FPeaks[R]) + 1);
      FPeaks[R][High(FPeaks[R])].C := X;
      FPeaks[R][High(FPeaks[R])].W := W;
      FPeaks[R][High(FPeaks[R])].H := RandRange(Round(Shape[FTheme, R, 2]), Round(Shape[FTheme, R, 3]));
      X := X + W * RandRange(0.75, 1.3) * Shape[FTheme, R, 4];
    end;
  end;
end;

procedure TGameScene.Generate;
var
  I: Integer;
begin
  GeneratePeaks;
  RandSeed := 1688;
  SetLength(FStars, 200);
  for I := 0 to High(FStars) do
    with FStars[I] do
    begin
      X := RandRange(0, 1700);
      Y := RandRange(8, 420) * Power(Random, 0.3);
      R := RandRange(0.6, 1.7);
      Phase := RandRange(0, 6);
    end;
  SetLength(FClouds, 6);
  for I := 0 to High(FClouds) do
    AddCloud(I, RandRange(-200, 1800), RandRange(60, 280), RandRange(160, 300), RandRange(36, 62),
      RandRange(4, 10));
end;

procedure TGameScene.FreeResources;
var
  M, I: Integer;
begin
  for M := 0 to 2 do
  begin
    FreeAndNil(FSky[M]);
    FreeAndNil(FR0[M]);
    FreeAndNil(FR1[M]);
    FreeAndNil(FRiver[M]);
    for I := 0 to High(FClouds) do
      FreeAndNil(FClouds[I].Sprite[M]);
  end;
  FreeAndNil(FCaption);
end;

procedure TGameScene.Resize(AWidth, AHeight: Integer);
var
  T0: Double;
begin
  T0 := HiResMs;
  FreeAndNil(FSnap);
  FWidth := Max(1, AWidth);
  FHeight := Max(1, AHeight);
  FScale := Min(FWidth / DesignW, FHeight / DesignH);
  FOffX := Round((FWidth - DesignW * FScale) / 2);
  FOffY := Round((FHeight - DesignH * FScale) / 2);
  FVisL := -FOffX / FScale;
  FVisR := (FWidth - FOffX) / FScale;
  FreeResources;
  FCutter.FLayer.SetSize(FWidth, FHeight);
  FCutter.FLayerTop := 0;
  FCutter.FRowA := 0;
  FCutter.FRowB := MaxInt;
  FAcc.SetSize(FWidth, FHeight);
  FreeAndNil(FStaticSvg);
  if FRecordSvg then FStaticSvg := TSvgRecorder.Create('s');
  FCutter.FSvg := FStaticSvg;
  try
    RenderStatic;
  finally
    FCutter.FSvg := nil;
  end;
  FHudKey := '#';   // matches no state: rebuild on the next Prepare
  FCardKey := '#';
  FreeItems;
  ClearCache;       // the sprites belong to the old size
  FCacheWarm := False;
  StaticMs := HiResMs - T0;
  Inc(StaticCount);
end;

procedure TGameScene.RenderStatic;
var
  M, I, K, Mk, N, R, Pad, SW: Integer;
  Cut: TPainter;
  L, A, Tile: TBGRABitmap;
  Pl: TPal;
  X, Y, Rad: Single;
  Q: TPointF;
  C, SkyAtSun: TBGRAPixel;
  Pts: array of TPointF;
  Pos: TPoint;

  procedure Begin_;
  begin
    A.FillTransparent;
    Cut.FLayerTop := 0;
    Cut.TargetBand(0, FHeight);
    if FStaticSvg <> nil then Mk := FStaticSvg.Mark else Mk := 0;
  end;

  procedure Sheet;
  begin
    Cut.BeginLayer;
  end;

  procedure Stack(Depth: Single);
  begin
    Cut.CompositeLayer(A, 0, Depth);
    Cut.TargetBand(0, FHeight);
  end;

  { the height of a range's ridge at x (design), over the repeated peaks }
  function Ridge(R: Integer; Base, X: Single): Single;
  var
    J, K2: Integer;
    H: Single;
  begin
    H := 0;
    for K2 := -1 to 1 do
      for J := 0 to High(FPeaks[R]) do
        if Abs(X - FPeaks[R][J].C - K2 * Period) < FPeaks[R][J].W then
          H := Max(H, FPeaks[R][J].H * PeakF((X - FPeaks[R][J].C - K2 * Period) / FPeaks[R][J].W));
    Result := Base - H;
  end;

  { the landmarks of the background theme on a range (repeated like the peaks) }
  procedure ThemeDecor(R: Integer; Base: Single);
  var
    K2, J, N, T: Integer;
    X, X0, Y, Y2, H, W2, Lev: Single;
    Stone, Dark, Roof, Wall, Win, Green, Leaf: TBGRAPixel;
    TopE, BotE: array of TPointF;
  begin
    Stone := Mix(Pl.Range[R], Pl.Lit, 0.5);
    Dark := Darken(Pl.Range[R], 0.7);
    case FTheme of
      1: if R = 1 then    // the Great Wall along the ridge, watchtowers
         begin
           N := Round((Period + 2 * Pad / FScale + 40) / 5);
           SetLength(TopE, N);
           SetLength(BotE, N);
           for J := 0 to N - 1 do
           begin
             X := -Pad / FScale - 20 + J * 5;
             Y := Ridge(R, Base, X) + 4;
             TopE[J] := Cut.P(X, Y - 20);
             BotE[J] := Cut.P(X, Y + 2);
           end;
           Cut.EdgeBand(L, TopE, BotE, Stone);
           for J := 0 to N - 1 do
             if J mod 3 = 0 then
             begin
               X := -Pad / FScale - 20 + J * 5;
               Y := Ridge(R, Base, X) + 4;
               Cut.Box(L, X, Y - 28, X + 7, Y - 19, Stone);
               Cut.Box(L, X - 8, Y - 20, X + 8, Y - 18, Dark);
             end;
           for K2 := -1 to 1 do
             for J := 0 to 5 do
             begin
               X := J * Period / 6 + 80 * Hash01(J * 13) + K2 * Period;
               if (X < -Pad / FScale - 40) or (X > Period + Pad / FScale + 40) then Continue;
               Y := Ridge(R, Base, X) + 4;
               Cut.Box(L, X - 18, Y - 58, X + 18, Y, Stone);
               Cut.Box(L, X - 6, Y - 46, X + 6, Y - 30, Dark);
               Cut.DPoly(L, [Cut.P(X - 26, Y - 56), Cut.P(X + 26, Y - 56), Cut.P(X + 15, Y - 72), Cut.P(X - 15, Y - 72)],
                 Darken(Stone, 0.7));
             end;
         end;
      2: if R = 1 then    // a town of houses and pagodas
         begin
           Roof := Darken(Hex('#4A3A40'), Max(0.4, Pl.Shade));
           Wall := Mix(Pl.Range[R], Hex('#F0E6D0'), 0.35);
           Win := Hex('#FFC860');
           for K2 := -1 to 1 do
           begin
             X := 0;
             T := 0;
             while X < Period do
             begin
               X0 := X + K2 * Period;
               W2 := 60 + 40 * Hash01(T * 7 + 1);
               if (X0 + W2 > -Pad / FScale - 30) and (X0 < Period + Pad / FScale + 30) then
               begin
                 Y := Ridge(R, Base, X0 + W2 / 2) + 6;
                 if T mod 5 = 2 then
                 begin
                   // a pagoda of four tiers
                   for J := 0 to 3 do
                   begin
                     H := W2 * (1 - 0.16 * J);
                     Y2 := Y - J * 34;
                     Cut.Box(L, X0 + W2 / 2 - H * 0.36, Y2 - 30, X0 + W2 / 2 + H * 0.36, Y2, Wall);
                     Cut.DPoly(L, [Cut.P(X0 + W2 / 2 - H * 0.62, Y2 - 26), Cut.P(X0 + W2 / 2 - H * 0.52, Y2 - 32),
                       Cut.P(X0 + W2 / 2 + H * 0.52, Y2 - 32), Cut.P(X0 + W2 / 2 + H * 0.62, Y2 - 26),
                       Cut.P(X0 + W2 / 2 + H * 0.3, Y2 - 40), Cut.P(X0 + W2 / 2 - H * 0.3, Y2 - 40)], Roof);
                     if Pl.Moon then Cut.Box(L, X0 + W2 / 2 - 4, Y2 - 22, X0 + W2 / 2 + 4, Y2 - 12, Win);
                   end;
                   Cut.Box(L, X0 + W2 / 2 - 2, Y - 166, X0 + W2 / 2 + 2, Y - 134, Roof);
                 end
                 else
                 begin
                   H := 40 + 34 * Hash01(T * 11 + 3);
                   Cut.Box(L, X0 + 6, Y - H, X0 + W2 - 6, Y + 8, Wall);
                   Cut.DPoly(L, [Cut.P(X0 - 6, Y - H + 2), Cut.P(X0, Y - H - 4), Cut.P(X0 + W2 / 2, Y - H - 24),
                     Cut.P(X0 + W2, Y - H - 4), Cut.P(X0 + W2 + 6, Y - H + 2), Cut.P(X0 + W2 / 2, Y - H - 12)], Roof);
                   if Pl.Moon or (Hash01(T * 5) < 0.3) then
                     Cut.Box(L, X0 + W2 / 2 - 6, Y - H + 12, X0 + W2 / 2 + 6, Y - H + 24,
                       IfThen(Pl.Moon, Win, Dark));
                 end;
               end;
               X := X + W2 + 6 + 26 * Hash01(T * 3 + 2);
               Inc(T);
             end;
           end;
         end;
      3: begin           // rice terraces: level lines across the hills
           Lev := Base - 10;
           while Lev > Base - 220 do
           begin
             X := -Pad / FScale - 20;
             while X < Period + Pad / FScale + 20 do
             begin
               if Ridge(R, Base, X) < Lev - 3 then
                 Cut.Ln(L, X, Lev + 2 * Sin(X * 0.03 + Lev), X + 9, Lev + 2 * Sin((X + 9) * 0.03 + Lev), 2.2,
                   Mix(Pl.Range[R], Pl.Lit, 0.65));
               X := X + 9;
             end;
             Lev := Lev - 15 + 3 * R;
           end;
         end;
      4: if R = 1 then    // a bamboo forest
         begin
           Green := Mix(Pl.Foliage, Pl.Range[R], 0.35);
           Leaf := Mix(Pl.Foliage2, Pl.Range[R], 0.3);
           for K2 := -1 to 1 do
             for J := 0 to 69 do
             begin
               X := J * Period / 70 + 12 * Hash01(J * 7) + K2 * Period;
               if (X < -Pad / FScale - 20) or (X > Period + Pad / FScale + 20) then Continue;
               Y := Ridge(R, Base, X) + 10;
               H := 120 + 160 * Hash01(J * 3 + 1);
               Cut.Box(L, X - 3, Y - H, X + 3, Y, IfThen(Odd(J), Green, Darken(Green, 0.86)));
               Y2 := Y - 30;
               while Y2 > Y - H + 10 do
               begin
                 Cut.Box(L, X - 3.5, Y2, X + 3.5, Y2 + 2, Darken(Green, 0.7));
                 Y2 := Y2 - 34;
               end;
               Cut.DPoly(L, [Cut.P(X, Y - H + 4), Cut.P(X + 22, Y - H - 6), Cut.P(X + 4, Y - H + 10)], Leaf);
               Cut.DPoly(L, [Cut.P(X, Y - H + 16), Cut.P(X - 22, Y - H + 4), Cut.P(X - 4, Y - H + 22)], Leaf);
             end;
         end;
      5: begin            // yellow mountains: pines on the tops, a temple on the far range
           Green := Darken(Mix(Pl.Foliage, Hex('#203828'), 0.4), 0.9);
           for K2 := -1 to 1 do
             for J := 0 to High(FPeaks[R]) do
             begin
               X := FPeaks[R][J].C + K2 * Period;
               if (X < -Pad / FScale - 40) or (X > Period + Pad / FScale + 40) then Continue;
               Y := Base - FPeaks[R][J].H + 4;
               if (R = 0) and (J mod 7 = 3) then
               begin
                 Cut.Box(L, X - 16, Y - 22, X + 16, Y + 2, Mix(Pl.Range[R], Hex('#F0E0C0'), 0.3));
                 Cut.DPoly(L, [Cut.P(X - 24, Y - 20), Cut.P(X + 24, Y - 20), Cut.P(X + 14, Y - 32), Cut.P(X - 14, Y - 32)],
                   Darken(Hex('#7A3A2A'), Max(0.4, Pl.Shade)));
               end
               else if J mod 2 = 0 then
               begin
                 Cut.Box(L, X - 1.5, Y - 22, X + 1.5, Y, Darken(Green, 0.7));
                 Cut.Ell(L, X, Y - 22, 20, 5, Green);
                 Cut.Ell(L, X + 3, Y - 14, 16, 4, Green);
                 Cut.Ell(L, X - 2, Y - 29, 12, 3.5, Green);
               end;
             end;
         end;
    end;
  end;

  { one tile of a range: the peaks of one Period, repeated left and right so the
    shadows wrap too, drawn on a wider layer and cut back to exactly one tile }
  function CutStrip(R: Integer; Y0, Y1: Single; out Pos: TPoint): TBGRABitmap;
  var
    K2, J: Integer;
    Base, Shift: Single;
    Full: TBGRABitmap;
  begin
    if R = 0 then Base := Base0 else Base := Base1;
    A.SetSize(SW + 2 * Pad, FHeight);
    L.SetSize(SW + 2 * Pad, FHeight);
    Begin_;
    Sheet;
    Cut.FOrgX := Pad;  // design x 0 = pixel Pad
    Cut.Box(L, -Pad / FScale - 10, Base - 6, Period + Pad / FScale + 10, IfThen(R = 0, Base1 + 30, RiverTop + 20),
      Pl.Range[R]);
    for K2 := -1 to 1 do
      for J := 0 to High(FPeaks[R]) do
        with FPeaks[R][J] do
        begin
          Shift := K2 * Period;
          if (C + Shift + W < -Pad / FScale - 20) or (C + Shift - W > Period + Pad / FScale + 20) then Continue;
          Cut.CutPeak(L, C + Shift, W, H, Base, True, Pl.Range[R], Pl, R, J * 7 + R);
        end;
    ThemeDecor(R, Base);
    Cut.DPolyG(L, [Cut.P(-Pad / FScale - 10, Base - 110), Cut.P(Period + Pad / FScale + 10, Base - 110),
      Cut.P(Period + Pad / FScale + 10, Base + 8), Cut.P(-Pad / FScale - 10, Base + 8)],
      MakeGrad(WithAlpha(Pl.Haze, 0), WithAlpha(Pl.Haze, Round(Min(230, (150 - R * 25) * Pl.MistK))), False,
      Cut.P(0, Base - 110), Cut.P(0, Base)));
    Stack(0.3 + 0.1 * R);
    Grain(A);
    Pos.X := 0;
    Pos.Y := EnsureRange(Floor(P(0, Y0).Y), 0, FHeight - 1);
    Full := TBGRABitmap(A.GetPart(Rect(Pad, Pos.Y, Pad + SW, EnsureRange(Ceil(P(0, Y1).Y), Pos.Y + 1, FHeight))));
    Full.LoadFromBitmapIfNeeded;
    Result := Full;
  end;

begin
  Mk := 0;
  Cut := FCutter;
  L := Cut.FLayer;
  A := FAcc;
  SW := Max(1, Round(Period * FScale));
  Pad := Round(160 * FScale) + 8;
  FStripW := SW;
  FStripPad := Pad;
  for M := 0 to 2 do
  begin
    Pl := FPal[M];
    RandSeed := 4242;
    A.SetSize(FWidth, FHeight);
    L.SetSize(FWidth, FHeight);

    { sky }
    Begin_;
    Cut.DPoly(A, [PointF(0, 0), PointF(FWidth, 0), PointF(FWidth, FHeight), PointF(0, FHeight)], Pl.SkyTop);
    for K := 0 to 6 do
    begin
      Sheet;
      N := Ceil((FVisR - FVisL + 80) / 16) + 1;
      SetLength(Pts, N + 2);
      for I := 0 to N - 1 do
      begin
        X := FVisL - 40 + I * 16;
        Y := 40 + K * 72 + 10 * Sin(X * 0.004 * (1 + K * 0.3) + K * 1.7) + 5 * Sin(X * 0.011 + K);
        Pts[I] := P(X, Y);
      end;
      Pts[N] := P(FVisR + 40, DesignH + 40);
      Pts[N + 1] := P(FVisL - 40, DesignH + 40);
      Cut.DPoly(L, Pts, Mix(Pl.SkyTop, Pl.SkyBot, (K + 1) / 7));
      Stack(0.3);
    end;
    SkyAtSun := Mix(Pl.SkyTop, Pl.SkyBot, EnsureRange((Pl.SunY - 40) / 504 + 0.1, 0, 1));
    Q := P(Pl.SunX, Pl.SunY);
    if Pl.SunHidden then
    begin
      for K := 0 to 1 do
      begin
        Sheet;
        C := Mix(Pl.CloudShade, Pl.CloudLit, 0.15 + K * 0.45);
        Cut.Box(L, FVisL - 60, -60, FVisR + 60, 40 + K * 55, C);
        X := Floor((FVisL - 60) / 55) * 55;
        I := 0;
        while X < FVisR + 60 do
        begin
          Cut.DEllipse(L, P(X, 0).X, P(0, 40 + K * 55 + 6 * Hash01(I + K * 50)).Y, S(42 + 22 * Hash01(I * 3 + K)),
            S(24 + 10 * Hash01(I * 5 + K)), C);
          X := X + 55;
          Inc(I);
        end;
        Stack(0.45);
      end;
      Grain(A);
    end
    else
    begin
      for K := 2 downto 0 do
      begin
        Sheet;
        Rad := Pl.SunR * (1.45 + K * 0.7);
        Cut.DEllipse(L, Q.X, Q.Y, S(Rad), S(Rad), Mix(SkyAtSun, Pl.SunC, 0.22 + (2 - K) * 0.16));
        Stack(0.22);
      end;
      Sheet;
      Cut.DEllipse(L, Q.X, Q.Y, S(Pl.SunR), S(Pl.SunR), Pl.SunC);
      if Pl.Moon then
      begin
        Cut.DEllipse(L, Q.X - S(6), Q.Y - S(4), S(5), S(5), Darken(Pl.SunC, 0.88));
        Cut.DEllipse(L, Q.X + S(7), Q.Y + S(6), S(3.5), S(3.5), Darken(Pl.SunC, 0.88));
      end;
      Stack(0.4);
      Grain(A);
      Cut.Glow(A, Pl.SunX, Pl.SunY, Pl.SunR * 7, WithAlpha(Pl.Glow, IfThen(M = 2, 45, 80)));
    end;
    FSky[M] := TBGRABitmap(A.Duplicate);
    FSky[M].LoadFromBitmapIfNeeded;
    FSvgSky[M] := TakeSvg(Mk);

    { river water }
    Begin_;
    Cut.Box(A, FVisL - 20, RiverTop - 2, FVisR + 20, DesignH + 20, Pl.Water1);
    Grain(A);
    FRiver[M] := Crop(RiverTop - 4, DesignH + 2, FRiverPos);
    FSvgRiver[M] := TakeSvg(Mk);


    { the two scrolling ranges }
    FR0[M] := CutStrip(0, Base0 - 330, Base1 + 10, Pos);
    FR0Pos := Pos;
    FSvgR0[M] := TakeSvg(Mk);
    FR1[M] := CutStrip(1, Base1 - 300, RiverTop + 6, Pos);
    FR1Pos := Pos;
    FSvgR1[M] := TakeSvg(Mk);
    Cut.FOrgX := FOffX;
  end;
  A.SetSize(FWidth, FHeight);
  L.SetSize(FWidth, FHeight);
  // clouds for the other palettes were cut with palette 0: cut all three now
  for M := 0 to 2 do
    for I := 0 to High(FClouds) do
      FreeAndNil(FClouds[I].Sprite[M]);
  CutCloudSprites;
end;

{ ---------- game ---------- }

{ a fresh river: random (from FSeed) or the custom map in FMap }
procedure TGameScene.ResetWorld;
var
  O: TMapObjArray;
begin
  SetLength(FObs, 0);
  SetLength(FLants, 0);
  SetLength(FHawks, 0);
  SetLength(FBonus, 0);
  SetLength(FHaz, 0);
  FSlowT := 0;
  SetLength(FShapes, 0);
  SetLength(FParts, 0);
  FScroll := 0;
  FY := 380;
  FVY := 0;
  FTilt := 0;
  FFlapT := 1;
  FInvuln := 0;
  FSpeed := 230;
  FDist := 0;
  FScore := 0;
  FLanternsGot := 0;
  FLives := 3;
  FNewBest := False;
  FWon := False;
  FFinishD := 0;
  SetLength(FRec, 0);
  SetLength(FRecFlaps, 0);
  FRecT := 0;
  if FMapMode = 1 then
  begin
    O := Copy(FMap.Objs);
    AddObjs(O);
    FFinishD := FMap.Length_;
  end
  else
  begin
    ClearShapeLib;
    GenInit(FGen, FSeed, FDifficulty);
    SpawnAhead;
  end;
end;

{ the random river is generated a little ahead of the window }
procedure TGameScene.SpawnAhead;
var
  O: TMapObjArray;
begin
  if FMapMode <> 0 then Exit;
  SetLength(O, 0);
  while FGen.D - FScroll < DesignW + 500 do
    GenNext(FGen, O);
  AddObjs(O);
end;

procedure TGameScene.ClearShapeLib;
var
  I: Integer;
begin
  for I := 0 to High(FShapeLib) do FShapeLib[I].Free;
  SetLength(FShapeLib, 0);
end;

{ a shape of the map's library, loaded from the shapes folder on first use }
function TGameScene.ShapeIndex(const AName: string): Integer;
var
  I: Integer;
  Sh: TPCShape;
begin
  for I := 0 to High(FShapeLib) do
    if SameText(FShapeLib[I].Name, AName) then Exit(I);
  Sh := TPCShape.Create;
  try
    if FileExists(DataDir('shapes') + AName) then Sh.LoadFromFile(DataDir('shapes') + AName)
    else MakeShapePreset(Sh, 'Rock');
  except
    MakeShapePreset(Sh, 'Rock');
  end;
  Sh.Name := AName;
  SetLength(FShapeLib, Length(FShapeLib) + 1);
  FShapeLib[High(FShapeLib)] := Sh;
  Result := High(FShapeLib);
end;

{ map objects into the game's arrays (world coordinates) }
procedure TGameScene.AddObjs(const Objs: TMapObjArray);
var
  I: Integer;
  Ob: TObstacle;
  It: TItem;
  Si: TShapeInst;
begin
  for I := 0 to High(Objs) do
    with Objs[I] do
      case Kind of
        okPillar:
          begin
            Ob.X := D;
            Ob.W := W;
            Ob.GapY := GapY;
            Ob.Gap := Gap;
            Ob.HasTop := Top;
            Ob.HasBottom := Bottom;
            Ob.Passed := False;
            Ob.Seed := Round(Scale) + I * 7;
            SetLength(FObs, Length(FObs) + 1);
            FObs[High(FObs)] := Ob;
          end;
        okLantern, okHawk:
          begin
            It.X := D;
            It.Y := Y;
            It.Phase := Frac(D * 0.013) * 6;
            It.Alive := True;
            if Kind = okLantern then
            begin
              SetLength(FLants, Length(FLants) + 1);
              FLants[High(FLants)] := It;
            end
            else
            begin
              SetLength(FHawks, Length(FHawks) + 1);
              FHawks[High(FHawks)] := It;
            end;
          end;
        okHeart, okSlow:
          begin
            It.X := D;
            It.Y := Y;
            It.Phase := Frac(D * 0.017) * 6;
            It.Alive := True;
            It.Kind := Ord(Kind = okSlow);
            SetLength(FBonus, Length(FBonus) + 1);
            FBonus[High(FBonus)] := It;
          end;
        okSwing, okBamboo, okCloud, okPinwheel, okKoi:
          begin
            SetLength(FHaz, Length(FHaz) + 1);
            FHaz[High(FHaz)].O := Objs[I];
            FHaz[High(FHaz)].Passed := False;
          end;
        okShape:
          begin
            Si.X := D;
            Si.Y := Y;
            Si.Scale := Max(0.05, Scale);
            Si.Flip := Flip;
            Si.Solid := Solid;
            Si.Lib := ShapeIndex(Shape);
            SetLength(FShapes, Length(FShapes) + 1);
            FShapes[High(FShapes)] := Si;
          end;
      end;
end;

function TGameScene.DataDir(const Sub: string): string;
begin
  Result := PCRoot + Sub + PathDelim;
end;

{ Random map / Play again }
procedure TGameScene.StartGame;
begin
  if FReplay or FRace then
  begin
    StartGhost(FGhostFile, FRace);
    Exit;
  end;
  if FMapMode = 1 then
  begin
    StartMapObj(FMap, 0);
    Exit;
  end;
  StartRandom(LongWord(Round(FTime * 1000) + Random(100000)) xor $5EED);
end;

procedure TGameScene.BeginRun;
begin
  if FSeasonChoice = 4 then SetSeason(Random(4), True);  // random season every flight
  if not FEditMode then SetTheme(RunTheme, True);
  FState := gsPlay;
  FStateT := 0;
  FAutoPilot := False;
  FRunHearts := 0;
  FRunSlows := 0;
  FRunPassed := 0;
  FRunLost := 0;
  FRunTime := 0;
  Inc(FGames);
  FPlayTrack := 1 + FGames mod 2;
  FHudKey := '#';
  FCardKey := '#';
  FMsg := '';
  OpenMenu(msNone);
  if not FEditMode then Snd(Ord(sfStart), 0.8);
end;

procedure TGameScene.StartRandom(ASeed: LongWord);
begin
  FMapMode := 0;
  FMapMusic := -1;
  FReplay := False;
  FRace := False;
  if not (FReplay or FRace) then FDifficulty := FDiffUser;
  FSeed := ASeed;
  ResetWorld;
  FLives := MaxLives;
  BeginRun;
end;

{ a custom map, from the start or (editor test flight) from a distance }
procedure TGameScene.StartMapObj(M: TPCMap; FromD: Single);
var
  Song: string;
begin
  if M <> FMap then FMap.Assign(M);
  FMapMode := 1;
  ClearShapeLib;
  ResetWorld;
  if FromD > 0 then
  begin
    FScroll := Max(0, FromD - CraneX);
    FDist := FScroll / 10;
  end;
  if FMap.Lives > 0 then FLives := Min(FMap.Lives, MaxHearts) else FLives := MaxLives;
  if FMap.Season >= 0 then SetSeason(FMap.Season, True);
  if FMap.TimeOfDay >= 0 then
  begin
    FAuto := False;
    SetModeInstant(FMap.TimeOfDay);
  end;
  FMapMusic := -1;
  Song := FMap.Music;
  if Copy(Song, 1, 8) = 'builtin:' then FMapMusic := EnsureRange(StrToIntDef(Copy(Song, 9, 3), 0), 0, 6)
  else if (Song <> '') and (Audio <> nil) and not FExportCopy then
    if FileExists(DataDir('music') + Song) then
    begin
      Audio.PlaySongFile(DataDir('music') + Song);
      FMapMusic := 7;
    end;
  BeginRun;
end;

procedure TGameScene.StartMapFile(const AFile: string);
begin
  FPendingMap := AFile;
end;

function TGameScene.MaxLives: Integer;
begin
  Result := DiffLives[FDifficulty];
end;

{ called from the input handler, possibly while the workers draw: only queue }
procedure TGameScene.Flap;
begin
  KeyInput(gkFlap);
end;

procedure TGameScene.DoFlap;
begin
  if (FState = gsPlay) and not FReplay then
  begin
    FVY := -440;
    FFlapT := 0;
    Snd(Ord(sfFlap), 0.55, 0.92 + 0.16 * Random);
    SetLength(FRecFlaps, Length(FRecFlaps) + 1);
    FRecFlaps[High(FRecFlaps)] := FScroll;
  end;
end;

{ a new obstacle at X: the gap gets narrower and the pillars wider as the
  speed rises; sometimes only a pillar or only a hanging rock; a lantern in the
  gap or beside it; later on, hawks }
procedure TGameScene.SpawnObstacle(X: Single);
begin
  SpawnAhead;   // (kept for compatibility: the generator decides)
end;

procedure TGameScene.Burst(X, Y: Single; Kind, N: Integer; C: TBGRAPixel);
var
  I: Integer;
  A, V: Single;
  Pt: TParticle;
begin
  for I := 0 to N - 1 do
  begin
    A := Random * 2 * Pi;
    V := 80 + Random * 220;
    Pt.X := X;
    Pt.Y := Y;
    Pt.VX := Cos(A) * V;
    Pt.VY := Sin(A) * V - 60;
    Pt.MaxLife := 0.5 + Random * 0.6;
    Pt.Life := Pt.MaxLife;
    Pt.Size := 4 + Random * 6;
    Pt.Spin := Random * 6;
    Pt.Kind := Kind;
    Pt.C := C;
    SetLength(FParts, Length(FParts) + 1);
    FParts[High(FParts)] := Pt;
  end;
end;

{ is a design point inside a pillar, a hanging rock or the river? }
{ is a design point (screen x) inside a pillar, a rock, a solid shape or the river? }
{ distance from a point to a segment }
function SegDist(PX, PY, AX, AY, BX, BY: Single): Single;
var
  T, L: Single;
begin
  L := Sqr(BX - AX) + Sqr(BY - AY);
  if L < 1e-6 then T := 0 else T := EnsureRange(((PX - AX) * (BX - AX) + (PY - AY) * (BY - AY)) / L, 0, 1);
  Result := Sqrt(Sqr(PX - AX - T * (BX - AX)) + Sqr(PY - AY - T * (BY - AY)));
end;

function TGameScene.Collides(PX, PY: Single): Boolean;
var
  I, J: Integer;
  U, X, F, LX, LY, G, A, KX, KY: Single;
  Sh: TPCShape;
  Ob: TObstacle;
  O: TMapObj;
begin
  Result := PY > WaterY + 4;
  if Result then Exit;
  for I := 0 to High(FObs) do
  begin
    Ob := FObs[I];
    X := Ob.X - FScroll;
    if Abs(PX - X) < Ob.W then
    begin
      U := (PX - X) / Ob.W;
      if Ob.HasBottom and (PY > WaterY + 30 - (WaterY + 30 - (Ob.GapY + Ob.Gap / 2)) * PeakF(U) + 3) then Exit(True);
      if Ob.HasTop and (PY < -30 + ((Ob.GapY - Ob.Gap / 2) + 30) * PeakF(U / 0.92) - 3) then Exit(True);
    end;
  end;
  for I := 0 to High(FHaz) do
  begin
    O := FHaz[I].O;
    X := O.D - FScroll;
    if Abs(PX - X) > 260 then Continue;
    case O.Kind of
      okSwing:
        if Abs(PX - X) < O.W then
        begin
          G := O.GapY + SwingOffset(O, FScroll);
          U := (PX - X) / O.W;
          if O.Bottom and (PY > WaterY + 30 - (WaterY + 30 - (G + O.Gap / 2)) * PeakF(U) + 3) then Exit(True);
          if O.Top and (PY < -30 + ((G - O.Gap / 2) + 30) * PeakF(U / 0.92) - 3) then Exit(True);
        end;
      okBamboo:
        if (Abs(PX - X) < O.W - 4) and (PY > O.Y + 12) then Exit(True);
      okCloud:
        begin
          G := O.Y + CloudOffset(O, FScroll);
          if Sqr((PX - X) / (O.W * 1.2)) + Sqr((PY - G) / (O.W * 0.62)) < 1 then Exit(True);
        end;
      okPinwheel:
        if Sqr(PX - X) + Sqr(PY - O.Y) < Sqr(O.W + 12) then
        begin
          if Sqr(PX - X) + Sqr(PY - O.Y) < Sqr(12) then Exit(True);
          A := PinwheelAngle(O, FScroll);
          for J := 0 to 3 do
            if SegDist(PX, PY, X, O.Y, X + O.W * 0.9 * Cos(A + J * Pi / 2 + 0.2),
              O.Y + O.W * 0.9 * Sin(A + J * Pi / 2 + 0.2)) < 11 then Exit(True);
        end;
      okKoi:
        begin
          KoiPos(O, FScroll, KX, KY, A);
          KX := KX - FScroll;
          LX := (PX - KX) * Cos(A) + (PY - KY) * Sin(A);
          LY := -(PX - KX) * Sin(A) + (PY - KY) * Cos(A);
          if (KY < WaterY + 20) and (Sqr(LX / 40) + Sqr(LY / 15) < 1) then Exit(True);
        end;
    end;
  end;
  for I := 0 to High(FShapes) do
    if FShapes[I].Solid then
    begin
      Sh := FShapeLib[FShapes[I].Lib];
      if FShapes[I].Flip then F := -1 else F := 1;
      LX := (PX - (FShapes[I].X - FScroll)) / FShapes[I].Scale * F;
      LY := (PY - FShapes[I].Y) / FShapes[I].Scale;
      for J := 0 to High(Sh.Polys) do
        if (Length(Sh.Polys[J].Pts) >= 3) and PointInPoly(Sh.Polys[J].Pts, LX, LY) then Exit(True);
    end;
end;

procedure TGameScene.Hit;
begin
  Burst(CraneX, FY, 1, 18, Darken(Hex('#F6F2EA'), Max(0.6, Shade)));
  Snd(Ord(sfHit), 0.9);
  Dec(FLives);
  Inc(FRunLost);
  if FLives <= 0 then
  begin
    FState := gsDying;
    FStateT := 0;
    FVY := -220;
    Snd(Ord(sfFall), 0.6);
  end
  else
  begin
    FInvuln := 1.8;
    FVY := -320;
  end;
end;

procedure TGameScene.UpdateGame(DT: Single);
var
  I, J: Integer;
  Target, A, PX, PY, SX, NewY: Single;
  Next: Integer;
  Ok: Boolean;
  Pts: array[0..5] of TPointF;
begin
  FStateT := FStateT + DT;
  if FEditMode and not FEditPlay then Exit;   // the editor holds the world still
  case FState of
    gsPlay:
      begin
        if FMapMode = 1 then FSpeed := FMap.SpeedAt(FScroll + CraneX)
        else FSpeed := RandomSpeedAt(FScroll + CraneX, FDifficulty);
        // slow-down bonus: the river eases back to its speed in the last second
        if FSlowT > 0 then
        begin
          FSpeed := FSpeed * (1 - (1 - SlowFactor) * Min(1, FSlowT));
          FSlowT := Max(0, FSlowT - DT);
        end;
        FRunTime := FRunTime + DT;
      end;
    gsDying: FSpeed := Max(80, FSpeed - 200 * DT);
  else
    FSpeed := 200;
  end;
  FScroll := FScroll + FSpeed * DT;
  if FState = gsPlay then FDist := FScroll / 10;
  SpawnAhead;

  // autopilot: aim at the middle of the next gap (menus, exports)
  if FAutoPilot and ((FState = gsTitle) or (FState = gsPlay)) then
  begin
    Next := -1;
    for I := 0 to High(FObs) do
      if (FObs[I].X - FScroll + FObs[I].W > CraneX - 30) and ((Next < 0) or (FObs[I].X < FObs[Next].X)) then Next := I;
    if Next >= 0 then Target := FObs[Next].GapY + 25 else Target := 420;
    if (FY > Target) and (FVY > -60) then
    begin
      FVY := -440;
      FFlapT := 0;
    end;
  end;

  // the crane: physics, or the recorded path of a replay
  if FState <> gsOver then
  begin
    if FReplay and (FState = gsPlay) then
    begin
      NewY := GhostYAt(FScroll, Ok);
      if not Ok then
      begin
        FinishRun(False);   // the recording ends here
        Exit;
      end;
      FVY := (NewY - FY) / Max(0.001, DT);
      FY := NewY;
      while (FGhostFlapI <= High(FGhostFlaps)) and (FGhostFlaps[FGhostFlapI] <= FScroll) do
      begin
        FFlapT := 0;
        Snd(Ord(sfFlap), 0.45, 1.0);
        Inc(FGhostFlapI);
      end;
    end
    else
    begin
      FVY := Min(620, FVY + 1500 * DT);
      FY := FY + FVY * DT;
      if FY < 30 then
      begin
        FY := 30;
        FVY := Max(0, FVY);
      end;
    end;
    FFlapT := FFlapT + DT;
    FTilt := EnsureRange(FVY * 0.0011, -0.45, 0.7);
    if FState = gsDying then FTilt := FTilt + FStateT * 4;
  end;
  if FRace then
  begin
    FGhostFlapT := FGhostFlapT + DT;
    while (FGhostFlapJ <= High(FGhostFlaps)) and (FGhostFlaps[FGhostFlapJ] <= FScroll) do
    begin
      FGhostFlapT := 0;
      Inc(FGhostFlapJ);
    end;
  end;
  // the ghost of this flight: a sample every 1/30 s
  if (FState = gsPlay) and not FReplay then
  begin
    FRecT := FRecT + DT;
    if FRecT >= 1 / GhostRate then
    begin
      FRecT := FRecT - 1 / GhostRate;
      SetLength(FRec, Length(FRec) + 1);
      FRec[High(FRec)] := PointF(FScroll, FY);
    end;
  end;
  // while blinking after a hit the river throws the crane back up
  if (FState = gsPlay) and (FInvuln > 0) and (FY > WaterY - 20) and not FReplay then FVY := -460;
  if FInvuln > 0 then FInvuln := FInvuln - DT;
  if (FState = gsDying) and (FY > WaterY + 20) then
  begin
    Burst(CraneX, WaterY, 1, 12, Darken(Hex('#BFE0F0'), Max(0.6, Shade)));
    Snd(Ord(sfSplash), 0.9);
    FinishRun(False);
  end;

  // hawks fly against the crane once they are near (a fixed design distance,
  // so every window size sees the same flight)
  for I := 0 to High(FHawks) do
    with FHawks[I] do
      if X - FScroll < DesignW + 100 then
      begin
        X := X - 140 * DT;
        Y := Y + Sin(FTime * 2.2 + Phase) * 90 * DT;
      end;
  // drop what is far behind
  J := 0;
  for I := 0 to High(FObs) do
    if FObs[I].X - FScroll + FObs[I].W > FVisL - 150 then
    begin
      FObs[J] := FObs[I];
      Inc(J);
    end;
  SetLength(FObs, J);
  J := 0;
  for I := 0 to High(FLants) do
    if FLants[I].Alive and (FLants[I].X - FScroll > FVisL - 60) then
    begin
      FLants[J] := FLants[I];
      Inc(J);
    end;
  SetLength(FLants, J);
  J := 0;
  for I := 0 to High(FBonus) do
    if FBonus[I].Alive and (FBonus[I].X - FScroll > FVisL - 60) then
    begin
      FBonus[J] := FBonus[I];
      Inc(J);
    end;
  SetLength(FBonus, J);
  J := 0;
  for I := 0 to High(FHaz) do
    if FHaz[I].O.D - FScroll + 260 > FVisL - 150 then
    begin
      FHaz[J] := FHaz[I];
      Inc(J);
    end;
  SetLength(FHaz, J);
  J := 0;
  for I := 0 to High(FHawks) do
    if FHawks[I].Alive and (FHawks[I].X - FScroll > FVisL - 80) then
    begin
      FHawks[J] := FHawks[I];
      Inc(J);
    end;
  SetLength(FHawks, J);

  // particles (screen coordinates)
  J := 0;
  for I := 0 to High(FParts) do
    with FParts[I] do
    begin
      Life := Life - DT;
      if Life <= 0 then Continue;
      X := X + VX * DT - FSpeed * DT * 0.5;
      Y := Y + VY * DT;
      VY := VY + 300 * DT;
      Spin := Spin + DT * 8;
      FParts[J] := FParts[I];
      Inc(J);
    end;
  SetLength(FParts, J);

  if FState <> gsPlay then
  begin
    if (FState = gsTitle) and Collides(CraneX, FY) then FVY := -440;  // the autopilot never dies
    Exit;
  end;

  // the finish line of a custom map
  if (FFinishD > 0) and (FScroll + CraneX >= FFinishD) then
  begin
    Inc(FScore, 20);
    Snd(Ord(sfNewBest), 0.8);
    FinishRun(True);
    Exit;
  end;
  // score: passed obstacles
  for I := 0 to High(FObs) do
    if not FObs[I].Passed and (FObs[I].X - FScroll + FObs[I].W < CraneX - 20) then
    begin
      FObs[I].Passed := True;
      Inc(FScore);
      Inc(FRunPassed);
      Snd(Ord(sfPass), 0.45);
    end;
  for I := 0 to High(FHaz) do
    if not FHaz[I].Passed and (FHaz[I].O.D - FScroll + 60 < CraneX - 20) then
    begin
      FHaz[I].Passed := True;
      Inc(FScore);
      Inc(FRunPassed);
      Snd(Ord(sfPass), 0.45);
    end;
  // bonuses: a heart is one more life, the hourglass slows the river
  for I := 0 to High(FBonus) do
  begin
    SX := FBonus[I].X - FScroll;
    if FBonus[I].Alive and (Sqr(SX - CraneX) + Sqr(FBonus[I].Y + 7 * Sin(FTime * 2.4 + FBonus[I].Phase) - FY) < Sqr(46)) then
    begin
      FBonus[I].Alive := False;
      Inc(FScore, 3);
      if FBonus[I].Kind = 0 then
      begin
        if FLives < MaxHearts then Inc(FLives);
        Inc(FRunHearts);
        Burst(SX, FBonus[I].Y, 0, 18, Hex('#FF7088'));
        Snd(Ord(sfLantern), 0.8, 1.5);
      end
      else
      begin
        FSlowT := SlowSeconds;
        Inc(FRunSlows);
        Burst(SX, FBonus[I].Y, 0, 18, Hex('#80C0FF'));
        Snd(Ord(sfLantern), 0.8, 0.7);
      end;
    end;
  end;
  // lanterns
  for I := 0 to High(FLants) do
  begin
    SX := FLants[I].X - FScroll;
    with FLants[I] do
      if Alive and (Sqr(SX - CraneX) + Sqr(Y + 6 * Sin(FTime * 2 + Phase) - FY) < Sqr(42)) then
      begin
        Alive := False;
        Inc(FScore, 5);
        Inc(FLanternsGot);
        Burst(SX, Y, 0, 16, Hex('#FFC060'));
        Snd(Ord(sfLantern), 0.7, 1 + 0.06 * (FLanternsGot mod 5));
      end;
  end;
  if FInvuln > 0 then Exit;
  // the crane's outline against pillars, rocks, shapes, the river and hawks
  A := FTilt;
  Pts[0] := PointF(36, -2);
  Pts[1] := PointF(-30, 0);
  Pts[2] := PointF(0, 9);
  Pts[3] := PointF(0, -8);
  Pts[4] := PointF(46, -24);
  Pts[5] := PointF(-40, -14);
  for I := 0 to 5 do
  begin
    PX := CraneX + (Pts[I].X * Cos(A) - Pts[I].Y * Sin(A)) * 1.45;
    PY := FY + (Pts[I].X * Sin(A) + Pts[I].Y * Cos(A)) * 1.45;
    if Collides(PX, PY) then
    begin
      Hit;
      Exit;
    end;
  end;
  for I := 0 to High(FHawks) do
  begin
    SX := FHawks[I].X - FScroll;
    with FHawks[I] do
      if Alive and (Abs(SX - CraneX) < 46) and (Abs(Y - FY) < 26) then
      begin
        Alive := False;
        Burst(SX, Y, 1, 10, Darken(Hex('#5A4030'), Shade));
        Hit;
        Exit;
      end;
  end;
end;

{ the end of a flight: game over, map complete or the end of a replay }
procedure TGameScene.FinishRun(Won: Boolean);
begin
  FState := gsOver;
  FStateT := 0;
  FWon := Won;
  if FEditMode then Exit;
  if not Won then Snd(Ord(sfGameOver), 0.8);
  if not FReplay then
  begin
    AddScore;
    if FNewBest then Snd(Ord(sfNewBest), 0.8);
    RecordFlight;
  end;
end;

{ the flight into the player's statistics file }
procedure TGameScene.RecordFlight;
var
  F: TFlight;
begin
  if (FPlayer = nil) or FExportCopy or FEditMode then Exit;
  F := Default(TFlight);
  if FMapMode = 1 then F.MapName := FMap.Name else F.MapName := RandomMapName;
  F.Dist := Round(FDist);
  F.Score := FScore;
  F.Lanterns := FLanternsGot;
  F.Hearts := FRunHearts;
  F.Slows := FRunSlows;
  F.Passed := FRunPassed;
  F.LivesLost := FRunLost;
  F.Seconds := FRunTime;
  F.Won := FWon;
  FPlayer.RecordFlight(F);
  try
    FPlayer.SaveToFile(FPlayer.FileName);
  except
  end;
end;

{ no player yet: choose one (or type a new name), then Action starts }
procedure TGameScene.RequirePlayer(Action: Integer);
begin
  FPendingStart := Action;
  OpenMenu(msSelect);
  FSelCanBack := False;
  FMsg := 'Who is flying?';
end;

procedure TGameScene.SetPlayer(APlayer: TPCPlayer);
begin
  if APlayer <> FPlayer then FreeAndNil(FPlayer);
  FPlayer := APlayer;
  if FPlayer <> nil then FCharacter := FPlayer.Character else FCharacter := 0;
  SaveSettings;
end;

procedure TGameScene.DoPendingStart;
var
  A: Integer;
begin
  A := FPendingStart;
  FPendingStart := 0;
  FReplay := False;
  FRace := False;
  FDifficulty := FDiffUser;
  case A of
    1: begin
         FMapMode := 0;
         StartGame;
       end;
    2: try
         FMap.LoadFromFile(FPendingFile);
         StartMapObj(FMap, 0);
       except
         on E: Exception do
         begin
           FMsg := 'cannot open: ' + E.Message;
           OpenMenu(msMaps);
         end;
       end;
  else
    OpenMenu(msMain);
  end;
end;

procedure TGameScene.LoadMenuFx;
var
  F: string;
begin
  F := PCRoot + 'menufx.pcmenufx';
  FFxAge := FileAge(F);
  if FFxAge = -1 then
    FFx.Defaults
  else
    try
      FFx.LoadFromFile(F);
    except
      FFx.Defaults;
    end;
  Inc(FFxVersion);
  FCardKey := '#';
  if FCache <> nil then ClearCache;   // the cards' frames
end;

function TGameScene.MenuStyle: Integer;
begin
  Result := EnsureRange(FMenu - 1, 0, MenuFxCount - 1);
end;

procedure TGameScene.FreeSelect;
var
  I: Integer;
begin
  for I := 0 to High(FSelPlayers) do FSelPlayers[I].Free;
  SetLength(FSelPlayers, 0);
  for I := 0 to High(FSelSpr) do FSelSpr[I].Free;
  SetLength(FSelSpr, 0);
  FSelSprScale := 0;
end;

{ every player file as a paper card, the latest flight first; the current player is selected }
procedure TGameScene.LoadSelect;
var
  SR: TSearchRec;
  PL, T: TPCPlayer;
  I, J: Integer;
begin
  FreeSelect;
  if FindFirst(DataDir('players') + '*.pcplayer', faAnyFile, SR) = 0 then
  begin
    repeat
      PL := TPCPlayer.Create('');
      try
        PL.LoadFromFile(DataDir('players') + SR.Name);
        SetLength(FSelPlayers, Length(FSelPlayers) + 1);
        FSelPlayers[High(FSelPlayers)] := PL;
      except
        PL.Free;
      end;
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  for I := 1 to High(FSelPlayers) do
  begin
    T := FSelPlayers[I];
    J := I - 1;
    while (J >= 0) and (FSelPlayers[J].Last < T.Last) do
    begin
      FSelPlayers[J + 1] := FSelPlayers[J];
      Dec(J);
    end;
    FSelPlayers[J + 1] := T;
  end;
  FSel := 0;
  if FPlayer <> nil then
    for I := 0 to High(FSelPlayers) do
      if SameText(ExtractFileName(FSelPlayers[I].FileName), ExtractFileName(FPlayer.FileName)) then FSel := I;
  FSelTop := Max(0, FSel - SelVisible + 1);
  FCardKey := '#';
end;

{ the paper cards show a Quit button until the main menu has been reached }
function TGameScene.SelHasQuit: Boolean;
begin
  Result := not FReachedMain;
end;

function TGameScene.SelCount: Integer;
begin
  Result := Length(FSelPlayers) + 1;   // + the New player card
end;

{ the left edge (design x) of card I: the shown cards are centred }
function TGameScene.SelCardX(I: Integer): Single;
var
  N: Integer;
begin
  N := Min(SelVisible, SelCount - FSelTop);
  Result := DesignW / 2 - (N * SelCardW + (N - 1) * SelGap) / 2 + (I - FSelTop) * (SelCardW + SelGap);
end;

{ '2026-10-16 11:35' -> '16 Oct 2026   11:35' }
function NiceWhen(const S: string): string;
const
  Mon: array[1..12] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
var
  M: Integer;
begin
  Result := S;
  if Length(S) < 10 then Exit;
  M := StrToIntDef(Copy(S, 6, 2), 0);
  if (M < 1) or (M > 12) then Exit;
  Result := IntToStr(StrToIntDef(Copy(S, 9, 2), 1)) + ' ' + Mon[M] + ' ' + Copy(S, 1, 4);
  if Length(S) >= 16 then Result := Result + '   ' + Copy(S, 12, 5);
end;

{ the paper cards as sprites (main thread); the characters are drawn live on them }
procedure TGameScene.MakeSelectCards;
var
  I: Integer;
  B: TBGRABitmap;
  PL: TPCPlayer;
  Nm: string;
  Ink, Soft, Red: TBGRAPixel;
begin
  if (Length(FSelSpr) = SelCount) and (FSelSprScale = FScale) then Exit;
  for I := 0 to High(FSelSpr) do FSelSpr[I].Free;
  SetLength(FSelSpr, SelCount);
  FSelSprScale := FScale;
  Ink := BGRA(48, 40, 52);
  Soft := BGRA(120, 96, 88);
  Red := BGRA(178, 40, 34);
  for I := 0 to SelCount - 1 do
  begin
    B := TBGRABitmap.Create(Max(1, Round(S(SelCardW + 12))), Max(1, Round(S(SelCardH + 14))));
    B.FillRoundRectAntialias(S(8), S(12), S(SelCardW + 10), S(SelCardH + 12), S(12), S(12), BGRA(0, 0, 0, 70));
    B.FillRoundRectAntialias(S(1), S(1), S(SelCardW), S(SelCardH), S(12), S(12), BGRA(246, 238, 222, 250));
    ChineseFrame(B, SelCardW, SelCardH, False);
    B.FontName := 'Segoe UI';
    B.FontQuality := fqSystem;
    if I < Length(FSelPlayers) then
    begin
      PL := FSelPlayers[I];
      // the sky disc the character flies in (drawn live)
      B.FillEllipseAntialias(S(SelCardW / 2), S(122), S(76), S(76), Red);
      B.FillEllipseAntialias(S(SelCardW / 2), S(122), S(72), S(72), BGRA(246, 238, 222));
      B.FillEllipseAntialias(S(SelCardW / 2), S(122), S(68), S(68), BGRA(188, 216, 236));
      B.FillEllipseAntialias(S(SelCardW / 2 - 30), S(160), S(22), S(7), BGRA(255, 255, 255));
      Nm := PL.Name;
      if Length(Nm) > 16 then Nm := Copy(Nm, 1, 15) + '...';
      B.FontStyle := [fsBold];
      B.FontHeight := Max(8, Round(S(27)));
      B.TextOut(S(SelCardW / 2), S(212), Nm, Ink, taCenter);
      B.FontStyle := [];
      B.FontHeight := Max(6, Round(S(15)));
      B.TextOut(S(SelCardW / 2), S(248), CharNames[PL.Character], Red, taCenter);
      if PL.Games > 0 then
      begin
        B.TextOut(S(SelCardW / 2), S(272), 'last flight finished', Soft, taCenter);
        B.FontStyle := [fsBold];
        B.FontHeight := Max(6, Round(S(17)));
        B.TextOut(S(SelCardW / 2), S(291), NiceWhen(PL.Last), Ink, taCenter);
        B.FontStyle := [];
        B.FontHeight := Max(6, Round(S(14)));
        B.TextOut(S(SelCardW / 2), S(314), Format('%d flights   best %d m', [PL.Games, PL.BestDist]), Soft, taCenter);
      end
      else
      begin
        B.TextOut(S(SelCardW / 2), S(278), 'no flights yet', Soft, taCenter);
        B.TextOut(S(SelCardW / 2), S(300), 'since ' + NiceWhen(PL.Created), Soft, taCenter);
      end;
    end
    else
    begin
      // the New player card: a big red plus
      B.FillEllipseAntialias(S(SelCardW / 2), S(122), S(60), S(60), Red);
      B.FillRectAntialias(S(SelCardW / 2 - 34), S(116), S(SelCardW / 2 + 34), S(128), BGRA(246, 238, 222));
      B.FillRectAntialias(S(SelCardW / 2 - 6), S(88), S(SelCardW / 2 + 6), S(156), BGRA(246, 238, 222));
      B.FontStyle := [fsBold];
      B.FontHeight := Max(8, Round(S(27)));
      B.TextOut(S(SelCardW / 2), S(212), 'New player', Ink, taCenter);
      B.FontStyle := [];
      B.FontHeight := Max(6, Round(S(15)));
      B.TextOut(S(SelCardW / 2), S(258), 'make a new paper card:', Soft, taCenter);
      B.TextOut(S(SelCardW / 2), S(280), 'a name and a character', Soft, taCenter);
    end;
    B.LoadFromBitmapIfNeeded;
    B.InvalidateBitmap;
    FSelSpr[I] := B;
  end;
end;

function TGameScene.LayerRows(Which: Integer; out Y0, Y1: Single): Boolean;
var
  I: Integer;
  X, A, B, KX, KY, Ang: Single;
  O: TMapObj;

  procedure Take(Lo, Hi: Single);
  begin
    if Lo < Y0 then Y0 := Lo;
    if Hi > Y1 then Y1 := Hi;
  end;

begin
  Y0 := 1E9;
  Y1 := -1E9;
  case Which of
    0: for I := 0 to High(FLants) do
         if FLants[I].Alive then
         begin
           X := FLants[I].X - FScroll;
           if (X > FVisL - 60) and (X < FVisR + 60) then Take(FLants[I].Y - 34, FLants[I].Y + 34);
         end;
    1: for I := 0 to High(FBonus) do
         if FBonus[I].Alive then
         begin
           X := FBonus[I].X - FScroll;
           if (X > FVisL - 60) and (X < FVisR + 60) then Take(FBonus[I].Y - 36, FBonus[I].Y + 36);
         end;
    2: for I := 0 to High(FHawks) do
         if FHawks[I].Alive then
         begin
           X := FHawks[I].X - FScroll;
           if (X > FVisL - 80) and (X < FVisR + 80) then Take(FHawks[I].Y - 50, FHawks[I].Y + 20);
         end;
    3: for I := 0 to High(FHaz) do
       begin
         O := FHaz[I].O;
         X := O.D - FScroll;
         case O.Kind of
           okCloud:
             if (X + O.W * 1.5 > FVisL) and (X - O.W * 1.5 < FVisR) then
             begin
               A := O.Y + CloudOffset(O, FScroll);
               Take(A - O.W, A + O.W * 0.45 + 110);
             end;
           okPinwheel:
             if (X + O.W > FVisL - 20) and (X - O.W < FVisR + 20) then Take(O.Y - O.W, WaterY + 30);
           okKoi:
             begin
               KoiPos(O, FScroll, KX, KY, Ang);
               B := KX - FScroll;
               if (KY <= WaterY + 26) and (B > FVisL - 60) and (B < FVisR + 60) then Take(KY - 60, KY + 60);
             end;
         end;
       end;
  end;
  Result := Y1 > Y0;
end;

{ the character drawn: the highlighted one while choosing }
function TGameScene.ShownChar: Integer;
begin
  if (FMenu = msCharacter) and (FSel < CharCount) then Result := FSel else Result := FCharacter;
end;

{ main thread, workers idle: a pending season, the HUD and the screen card }
procedure TGameScene.Prepare;
begin
  FMenuT := HiResMs / 1000;
  // the Menu FX Editor saved new effects: take them (checked twice a second)
  Inc(FFxCheck);
  if (FFxCheck mod 30 = 0) and not FExportCopy and (FileAge(PCRoot + 'menufx.pcmenufx') <> FFxAge) then LoadMenuFx;
  HandleInput;
  if FPendingMap <> '' then
  begin
    try
      FMap.LoadFromFile(FPendingMap);
      StartMapObj(FMap, 0);
    except
      on E: Exception do FMsg := E.Message;
    end;
    FPendingMap := '';
  end;
  if (FPendingSeason >= 0) or (FPendingTheme >= 0) then ApplySeason;
  if (FState = gsOver) and (FMenu = msNone) and (FStateT > 0.9) and not FEditMode then OpenMenu(msOver);
  if (FState = gsOver) and FEditMode and FEditPlay and (FStateT > 1.6) then EditorStop;  // back to the editor
  SyncAudio;
  if FWidth > 1 then
  begin
    if not FCacheWarm then WarmCache;
    MakeHud;
    MakeCard;
  end;
end;

procedure TGameScene.Snd(Sfx: Integer; Vol: Single; Pitch: Single);
begin
  if (Audio <> nil) and not FExportCopy then Audio.Play(TSfx(Sfx), Vol, 0, Pitch);
end;

{ the tune for the moment: the menu theme in the menus, otherwise by season and
  time of day (or the one chosen in the settings) }
function TGameScene.WantedTrack: Integer;
begin
  if FMusicChoice > 0 then Exit(FMusicChoice - 1);
  if FState = gsTitle then Exit(0);
  if (FMapMode = 1) and (FMapMusic >= 0) then Exit(FMapMusic);
  case FSeason of
    1: Result := 4;
    2: if CurrentMode = 2 then Result := 2 else Result := 5;
    3: Result := 6;
  else
    if CurrentMode = 2 then Result := 3 else Result := FPlayTrack;
  end;
end;

procedure TGameScene.SyncAudio;
begin
  if (Audio = nil) or FExportCopy then Exit;
  Audio.SetVolumes(FMusicVol / 10, FSfxVol / 10);
  Audio.PlayMusic(WantedTrack);
  if FMenu = msPause then Audio.SetDuck(0.35)
  else if FState = gsOver then Audio.SetDuck(0.5)
  else Audio.SetDuck(1);
  if FSeason = 1 then
  begin
    if FMenu = msPause then Audio.SetRain(0.35) else Audio.SetRain(1);
  end
  else
    Audio.SetRain(0);
end;

procedure TGameScene.KeyInput(Code: Integer);
begin
  SetLength(FInput, Length(FInput) + 1);
  FInput[High(FInput)].Kind := 0;
  FInput[High(FInput)].Code := Code;
end;

function TGameScene.TextEntry: Boolean;
begin
  Result := FMenu = msNewName;
end;

procedure TGameScene.TextInput(const AText: string);
begin
  if FMenu <> msNewName then Exit;
  if Length(FNameEdit + AText) <= 40 then FNameEdit := FNameEdit + AText;
  FCardKey := '#';
end;

procedure TGameScene.MouseInput(Kind: Integer; PX, PY: Single);
begin
  if (Kind = 1) and (Length(FInput) > 0) and (FInput[High(FInput)].Kind = 1) then
  begin  // only the newest position matters
    FInput[High(FInput)].X := PX;
    FInput[High(FInput)].Y := PY;
    Exit;
  end;
  SetLength(FInput, Length(FInput) + 1);
  FInput[High(FInput)].Kind := Kind;
  FInput[High(FInput)].X := PX;
  FInput[High(FInput)].Y := PY;
end;

{ which menu item is under a window pixel (-1: none) }
function TGameScene.ItemAt(PX, PY: Single): Integer;
var
  DX, DY: Single;
  I: Integer;
begin
  Result := -1;
  if (FMenuN <= 0) or (FScale <= 0) then Exit;
  DX := (PX - FOffX) / FScale;
  DY := (PY - FOffY) / FScale;
  if FMenu = msSelect then
  begin
    for I := FSelTop to Min(SelCount, FSelTop + SelVisible) - 1 do
      if (DX >= SelCardX(I)) and (DX <= SelCardX(I) + SelCardW) and (DY >= SelY - 24) and (DY <= SelY + SelCardH) then
        Exit(I);
    if SelHasQuit and (Abs(DX - DesignW / 2) <= SelQuitW / 2) and (DY >= SelQuitY) and (DY <= SelQuitY + SelQuitH) then
      Exit(SelCount);
    Exit;
  end;
  if (DX < FCardX0) or (DX > FCardX1) or (DY < FItemY0) then Exit;
  Result := Floor((DY - FItemY0) / FItemH);
  if Result >= FMenuN then Result := -1;
end;

procedure TGameScene.HandleInput;
var
  I, K: Integer;
  Ev: TInputEv;
begin
  for I := 0 to High(FInput) do
  begin
    Ev := FInput[I];
    case Ev.Kind of
      0: if FMenu = msNone then
         begin
           if FEditMode then
           begin
             if Ev.Code = gkBack then EditorStop else if Ev.Code in [gkFlap, gkOk, gkUp] then DoFlap;
           end
           else if FState = gsPlay then
             case Ev.Code of
               gkFlap, gkOk, gkUp: DoFlap;
               gkBack, gkErase: OpenMenu(msPause);
             end;
         end
         else
           MenuKey(Ev.Code);
      1: begin
           K := ItemAt(Ev.X, Ev.Y);
           if (K >= 0) and (K <> FSel) then
           begin
             FSel := K;
             Snd(Ord(sfMenuMove), 0.35);
           end;
         end;
      2: if FMenu = msNone then
         begin
           if FState = gsPlay then DoFlap;
         end
         else
         begin
           K := ItemAt(Ev.X, Ev.Y);
           if K >= 0 then
           begin
             FSel := K;
             // settings: a click on the left half lowers a value, on the right half raises it
             if (FMenu = msSettings) and (K < FMenuN - 1) then
             begin
               if (Ev.X - FOffX) / FScale < (FCardX0 + FCardX1) / 2 + 60 then MenuActivate(-1)
               else MenuActivate(1);
             end
             else
               MenuActivate(0);
           end;
         end;
    end;
  end;
  SetLength(FInput, 0);
end;

procedure TGameScene.OpenMenu(M: Integer);
begin
  if (M in [msSettings, msHelp, msScores, msCredits]) and not (FMenu in [msSettings, msHelp, msScores, msCredits]) then
    FMenuPrev := FMenu;
  if M in [msMaps, msSaves, msGhosts, msPlayers] then LoadList(M);
  FMenu := M;
  FSel := 0;
  FCardKey := '#';
  FShowPause := M = msPause;
  if M = msMain then FReachedMain := True;
  if M = msSelect then
  begin
    FSelCanBack := FPlayer <> nil;   // from a menu; the start and "who is flying?" clear it
    LoadSelect;
  end;
end;

{ the files of a list menu, newest first (maps by name) }
procedure TGameScene.LoadList(M: Integer);
var
  Dir, Ext, Txt: string;
  SR: TSearchRec;
  SL: TStringList;
  I: Integer;
begin
  FList.Clear;
  FListNames.Clear;
  FListTop := 0;
  case M of
    msMaps: begin Dir := DataDir('maps'); Ext := '*.pcmap'; end;
    msSaves: begin Dir := DataDir('saves'); Ext := '*.pcsave'; end;
    msPlayers: begin Dir := DataDir('players'); Ext := '*.pcplayer'; end;
  else
    begin Dir := DataDir('ghosts'); Ext := '*.pcghost'; end;
  end;
  if FindFirst(Dir + Ext, faAnyFile, SR) = 0 then
  begin
    repeat
      FList.Add(Dir + SR.Name);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  FList.Sort;
  if not (M in [msMaps, msPlayers]) then
    for I := 0 to FList.Count div 2 - 1 do FList.Exchange(I, FList.Count - 1 - I);  // newest first
  SL := TStringList.Create;
  try
    for I := 0 to FList.Count - 1 do
    begin
      Txt := ChangeFileExt(ExtractFileName(FList[I]), '');
      try
        SL.LoadFromFile(FList[I]);
        if SL.Values['name'] <> '' then Txt := SL.Values['name'];
      except
      end;
      FListNames.Add(Txt);
    end;
  finally
    SL.Free;
  end;
end;

function TGameScene.ListVisible: Integer;
begin
  Result := Min(ListRows, FList.Count - FListTop);
end;

procedure TGameScene.GoMainMenu;
begin
  FReplay := False;
  FRace := False;
  FDifficulty := FDiffUser;
  FMapMode := 0;
  FMapMusic := -1;
  FState := gsTitle;
  FStateT := 0;
  FAutoPilot := True;
  FSeed := 20261016;
  ResetWorld;
  OpenMenu(msMain);
end;


procedure TGameScene.MenuBack;
var
  KeepBack: Boolean;
begin
  // main menu: Esc first moves the cursor to Quit, Esc on Quit ends the game
  if FMenu = msMain then
  begin
    if FSel <> FMenuN - 1 then
    begin
      FSel := FMenuN - 1;
      Snd(Ord(sfMenuMove), 0.5);
    end
    else
      FQuit := True;
    Exit;
  end;
  Snd(Ord(sfMenuBack), 0.6);
  case FMenu of
    msSettings, msHelp, msScores, msCredits:
      begin
        if FMenu = msSettings then SaveSettings;
        if FMenuPrev = msNone then FMenuPrev := msMain;
        OpenMenu(FMenuPrev);
      end;
    msPause: OpenMenu(msNone);
    msOver: GoMainMenu;
    msMaps, msSaves, msGhosts: OpenMenu(msMain);
    msSaveItem: OpenMenu(msSaves);
    msGhostItem: OpenMenu(msGhosts);
    msPlayers, msStats:
      begin
        FPendingStart := 0;
        OpenMenu(msMain);
      end;
    msPlayerItem: OpenMenu(msMain);
    msNewName:
      begin
        KeepBack := FSelCanBack;
        OpenMenu(msSelect);
        FSelCanBack := KeepBack;
      end;
    msCharacter: if FCharBack = msPlayerItem then OpenMenu(msPlayerItem) else OpenMenu(msMain);
    msSelect: if FPlayer <> nil then
      begin
        FPendingStart := 0;
        OpenMenu(msMain);
      end;
  end;
end;

procedure TGameScene.MenuKey(Code: Integer);
var
  IsList: Boolean;
begin
  if FMenuN <= 0 then Exit;
  if FMenu = msSelect then
  begin
    case Code of
      gkLeft: FSel := (FSel - 1 + FMenuN) mod FMenuN;
      gkRight: FSel := (FSel + 1) mod FMenuN;
      gkDown: if SelHasQuit then FSel := SelCount else FSel := (FSel + 1) mod FMenuN;    // down to Quit
      gkUp: if SelHasQuit and (FSel = SelCount) then FSel := FSelTop else FSel := (FSel - 1 + FMenuN) mod FMenuN;
      gkOk, gkFlap: MenuActivate(0);
      gkBack, gkErase:
        if SelHasQuit then
        begin
          // first entry: Esc goes to Quit, Esc on Quit ends the game
          if FSel <> SelCount then
          begin
            FSel := SelCount;
            Snd(Ord(sfMenuMove), 0.5);
          end
          else
            FQuit := True;
        end
        else if FSelCanBack and (FPlayer <> nil) then MenuBack;
    end;
    if (Code in [gkLeft, gkUp, gkRight, gkDown]) and (FSel < SelCount) then
    begin
      if FSel < FSelTop then FSelTop := FSel;
      if FSel >= FSelTop + SelVisible then FSelTop := FSel - SelVisible + 1;
    end;
    if Code in [gkLeft, gkUp, gkRight, gkDown] then Snd(Ord(sfMenuMove), 0.4);
    Exit;
  end;
  IsList := FMenu in [msMaps, msSaves, msGhosts, msPlayers];
  case Code of
    gkUp:
      begin
        if IsList and (FSel = 0) and (FListTop > 0) then
        begin
          Dec(FListTop);
          FCardKey := '#';
        end
        else
          FSel := (FSel - 1 + FMenuN) mod FMenuN;
        Snd(Ord(sfMenuMove), 0.4);
      end;
    gkDown:
      begin
        if IsList and (FSel = ListVisible - 1) and (FListTop + ListRows < FList.Count) then
        begin
          Inc(FListTop);
          FCardKey := '#';
        end
        else
          FSel := (FSel + 1) mod FMenuN;
        Snd(Ord(sfMenuMove), 0.4);
      end;
    gkLeft: if FMenu = msSettings then MenuActivate(-1);
    gkRight: if FMenu = msSettings then MenuActivate(1);
    gkOk: MenuActivate(0);
    gkFlap: if FMenu <> msNewName then MenuActivate(0);
    gkBack: MenuBack;
    gkErase:
      if FMenu = msNewName then
      begin
        // one UTF-8 letter off the end
        while (FNameEdit <> '') and ((Ord(FNameEdit[Length(FNameEdit)]) and $C0) = $80) do
          Delete(FNameEdit, Length(FNameEdit), 1);
        if FNameEdit <> '' then Delete(FNameEdit, Length(FNameEdit), 1);
        FCardKey := '#';
      end
      else
        MenuBack;
  end;
end;

{ Dir: 0 Enter / click, -1 / +1 left / right (settings values) }
{ Dir: 0 Enter / click, -1 / +1 left / right (settings values) }
procedure TGameScene.MenuActivate(Dir: Integer);
var
  Idx: Integer;
  NewP: TPCPlayer;
begin
  if FMenu = msSettings then
  begin
    if FSel = FMenuN - 1 then
    begin
      if Dir = 0 then MenuBack;
      Exit;
    end;
    if Dir = 0 then Dir := 1;
    ChangeSetting(FSel, Dir);
    Snd(Ord(sfMenuMove), 0.5, 1 + 0.08 * Dir);
    SaveSettings;
    Exit;
  end;
  if Dir <> 0 then Exit;
  Snd(Ord(sfMenuSelect), 0.6);
  // list menus: an entry, or Back (the last item)
  if FMenu = msSelect then
  begin
    if SelHasQuit and (FSel = SelCount) then
    begin
      FQuit := True;
      Exit;
    end;
    if FSel < Length(FSelPlayers) then
    begin
      NewP := TPCPlayer.Create('');
      try
        NewP.LoadFromFile(FSelPlayers[FSel].FileName);
        SetPlayer(NewP);
        FMsg := '';
        if FPendingStart <> 0 then DoPendingStart else OpenMenu(msMain);
      except
        on E: Exception do
        begin
          NewP.Free;
          FMsg := 'cannot open: ' + E.Message;
        end;
      end;
    end
    else
    begin
      FNameEdit := '';
      OpenMenu(msNewName);
    end;
    FCardKey := '#';
    Exit;
  end;
  if FMenu = msPlayers then
  begin
    if FSel < ListVisible then
    begin
      NewP := TPCPlayer.Create('');
      try
        NewP.LoadFromFile(FList[FListTop + FSel]);
        SetPlayer(NewP);
        OpenMenu(msPlayerItem);
      except
        on E: Exception do
        begin
          NewP.Free;
          FMsg := 'cannot open: ' + E.Message;
        end;
      end;
    end
    else if FSel = ListVisible then
    begin
      FNameEdit := '';
      OpenMenu(msNewName);
    end
    else
      MenuBack;
    FCardKey := '#';
    Exit;
  end;
  if FMenu in [msMaps, msSaves, msGhosts] then
  begin
    if FSel >= ListVisible then
    begin
      MenuBack;
      Exit;
    end;
    Idx := FListTop + FSel;
    FSelFile := FList[Idx];
    case FMenu of
      msMaps:
        if FPlayer = nil then
        begin
          FPendingFile := FSelFile;
          RequirePlayer(2);
        end
        else
        try
          FReplay := False;
          FRace := False;
          FDifficulty := FDiffUser;
          FMap.LoadFromFile(FSelFile);
          StartMapObj(FMap, 0);
        except
          on E: Exception do
          begin
            FMsg := 'cannot open: ' + E.Message;
            FCardKey := '#';
          end;
        end;
      msSaves: OpenMenu(msSaveItem);
      msGhosts: OpenMenu(msGhostItem);
    end;
    Exit;
  end;
  case FMenu of
    msMain:
      case FSel of
        0: begin
             FPendingStart := 0;
             if FPlayer <> nil then OpenMenu(msPlayerItem) else OpenMenu(msSelect);
           end;
        1: begin
             FPendingStart := 0;
             OpenMenu(msSelect);    // the paper cards (Esc comes back here)
           end;
        2: if FPlayer = nil then RequirePlayer(1) else
           begin
             FPendingStart := 1;
             DoPendingStart;
           end;
        3: OpenMenu(msMaps);
        4: OpenMenu(msSaves);
        5: OpenMenu(msGhosts);
        6: OpenMenu(msStats);
        7: OpenMenu(msSettings);
        8: OpenMenu(msHelp);
        9: OpenMenu(msScores);
        10: OpenMenu(msCredits);
        11: FQuit := True;
      end;
    msPlayerItem:
      case FSel of
        0: OpenMenu(msSelect);
        1: begin
             FCharBack := msPlayerItem;
             OpenMenu(msCharacter);
             FSel := FCharacter;
           end;
        2: OpenMenu(msStats);
        3: if FPlayer <> nil then
           begin
             DeleteFile(FPlayer.FileName);
             FMsg := 'deleted player ' + FPlayer.Name;
             SetPlayer(nil);
             OpenMenu(msSelect);
           end;
        4: MenuBack;
      end;
    msNewName:
      if FSel = 0 then
      begin
        FNameEdit := Trim(FNameEdit);
        if not ValidPlayerName(FNameEdit) then FMsg := 'type a name first'
        else if FileExists(PlayerFileName(PCRoot, FNameEdit)) then FMsg := 'that name is taken - choose it in the list'
        else
        begin
          NewP := TPCPlayer.Create(FNameEdit);
          try
            NewP.SaveToFile(PlayerFileName(PCRoot, FNameEdit));
            SetPlayer(NewP);
            FMsg := '';
            FCharBack := msMain;
            OpenMenu(msCharacter);
            FSel := 0;
          except
            on E: Exception do
            begin
              NewP.Free;
              FMsg := 'cannot save: ' + E.Message;
            end;
          end;
        end;
      end
      else
        MenuBack;
    msCharacter:
      if FSel < CharCount then
      begin
        FCharacter := FSel;
        if FPlayer <> nil then
        begin
          FPlayer.Character := FSel;
          try
            FPlayer.SaveToFile(FPlayer.FileName);
          except
          end;
        end;
        if FPendingStart <> 0 then DoPendingStart
        else if FCharBack = msPlayerItem then OpenMenu(msPlayerItem)
        else OpenMenu(msMain);
      end
      else
        MenuBack;
    msStats: MenuBack;
    msPause:
      case FSel of
        0: OpenMenu(msNone);
        1: if FReplay then FMsg := 'a replay cannot be saved' else SaveGame;
        2: StartGame;
        3: OpenMenu(msSettings);
        4: OpenMenu(msHelp);
        5: GoMainMenu;
      end;
    msOver:
      case FSel of
        0: StartGame;
        1: if FReplay then FMsg := 'this is a replay already' else SaveGhost;
        2: OpenMenu(msScores);
        3: GoMainMenu;
      end;
    msSaveItem:
      case FSel of
        0: LoadGame(FSelFile);
        1: begin
             DeleteFile(FSelFile);
             FMsg := 'deleted ' + ExtractFileName(FSelFile);
             OpenMenu(msSaves);
           end;
        2: MenuBack;
      end;
    msGhostItem:
      case FSel of
        0: StartGhost(FSelFile, False);
        1: StartGhost(FSelFile, True);
        2: begin
             DeleteFile(FSelFile);
             FMsg := 'deleted ' + ExtractFileName(FSelFile);
             OpenMenu(msGhosts);
           end;
        3: MenuBack;
      end;
    msHelp, msScores, msCredits: MenuBack;
  end;
  FCardKey := '#';
end;

procedure TGameScene.ChangeSetting(I, Dir: Integer);
begin
  case I of
    0: FMusicVol := EnsureRange(FMusicVol + Dir, 0, 10);
    1: FSfxVol := EnsureRange(FSfxVol + Dir, 0, 10);
    2: FMusicChoice := (FMusicChoice + Dir + TrackCount + 1) mod (TrackCount + 1);
    3: begin
         FDiffUser := (FDiffUser + Dir + 3) mod 3;
         if not (FReplay or FRace) then FDifficulty := FDiffUser;
       end;
    4: begin
         FSeasonChoice := (FSeasonChoice + Dir + 5) mod 5;
         if FSeasonChoice < 4 then SetSeason(FSeasonChoice, True);
       end;
    5: begin
         FTimeChoice := (FTimeChoice + Dir + 4) mod 4;
         FAuto := FTimeChoice = 0;
         if FTimeChoice > 0 then SetMode(FTimeChoice - 1);
       end;
    6: begin
         FThemeChoice := (FThemeChoice + Dir + MapThemeCount + 1) mod (MapThemeCount + 1);
         if FThemeChoice > 0 then SetTheme(FThemeChoice - 1, True);
       end;
    7: FHudOn := not FHudOn;
    8: FFullWanted := not FFullWanted;
    9: FVSyncWanted := not FVSyncWanted;
  end;
end;

function TGameScene.MenuItem(I: Integer): string;
const
  L = #$E2#$97#$80'  ';
  R = '  '#$E2#$96#$B6;

  function OnOff(B: Boolean): string;
  begin
    if B then Result := 'On' else Result := 'Off';
  end;

begin
  Result := '';
  case FMenu of
    msMain:
      case I of
        0: if FPlayer = nil then Result := 'Player' + #9 + '(choose or create)'
           else Result := 'Player' + #9 + FPlayer.Name + '  -  ' + CharNames[FCharacter];
        1: Result := 'Change player';
        2: Result := 'Random map';
        3: Result := 'Custom maps';
        4: Result := 'Saved games';
        5: Result := 'Ghosts';
        6: Result := 'Statistics';
        7: Result := 'Settings';
        8: Result := 'How to play';
        9: Result := 'High scores';
        10: Result := 'Credits';
        11: Result := 'Quit';
      end;
    msPlayers:
      if I < ListVisible then Result := FListNames[FListTop + I]
      else if I = ListVisible then Result := '+  New player'
      else Result := 'Back';
    msPlayerItem:
      case I of
        0: Result := 'Switch player (paper cards)';
        1: Result := 'Character' + #9 + CharNames[FCharacter];
        2: Result := 'Statistics';
        3: Result := 'Delete player';
        4: Result := 'Back';
      end;
    msNewName:
      case I of
        0: Result := 'OK';
        1: Result := 'Back';
      end;
    msCharacter:
      if I < CharCount then Result := CharNames[I] else Result := 'Back';
    msSelect:
      if I = SelCount then Result := 'Quit' else Result := '';
    msPause:
      case I of
        0: Result := 'Resume';
        1: Result := 'Save game';
        2: Result := 'Restart';
        3: Result := 'Settings';
        4: Result := 'How to play';
        5: Result := 'Main menu';
      end;
    msOver:
      case I of
        0: if FReplay then Result := 'Replay again' else Result := 'Play again';
        1: Result := 'Save ghost';
        2: Result := 'High scores';
        3: Result := 'Main menu';
      end;
    msSaveItem:
      case I of
        0: Result := 'Continue';
        1: Result := 'Delete';
        2: Result := 'Back';
      end;
    msGhostItem:
      case I of
        0: Result := 'Replay (watch)';
        1: Result := 'Race against it';
        2: Result := 'Delete';
        3: Result := 'Back';
      end;
    msMaps, msSaves, msGhosts:
      if I < ListVisible then Result := FListNames[FListTop + I]
      else Result := 'Back';
    msSettings:
      case I of
        0: Result := 'Music volume' + #9 + L + IntToStr(FMusicVol * 10) + '%' + R;
        1: Result := 'Sound volume' + #9 + L + IntToStr(FSfxVol * 10) + '%' + R;
        2: if FMusicChoice = 0 then Result := 'Music' + #9 + L + 'Auto (by scene)' + R
           else Result := 'Music' + #9 + L + TrackNames[FMusicChoice - 1] + R;
        3: Result := 'Difficulty' + #9 + L + DiffNames[FDiffUser] + Format(' (%d lives)', [DiffLives[FDiffUser]]) + R;
        4: if FSeasonChoice = 4 then Result := 'Season' + #9 + L + 'Random' + R
           else Result := 'Season' + #9 + L + SeasonNames[FSeasonChoice] + R;
        5: Result := 'Time of day' + #9 + L + TimeChoiceNames[FTimeChoice] + R;
        6: if FThemeChoice = 0 then Result := 'Background' + #9 + L + 'Random' + R
           else Result := 'Background' + #9 + L + MapThemeNames[FThemeChoice - 1] + R;
        7: Result := 'Show HUD' + #9 + L + OnOff(FHudOn) + R;
        8: Result := 'Full screen' + #9 + L + OnOff(FFullWanted) + R;
        9: Result := 'VSync' + #9 + L + OnOff(FVSyncWanted) + R;
        10: Result := 'Back';
      end;
  else
    if I = 0 then Result := 'Back';
  end;
end;

{ ---------- settings and high scores on disk ---------- }

procedure TGameScene.LoadSettings;
var
  SL: TStringList;
  F: string;
begin
  F := PCRoot + 'papercrane.ini';
  if not FileExists(F) then Exit;
  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(F);
      FMusicVol := EnsureRange(StrToIntDef(SL.Values['music_volume'], FMusicVol), 0, 10);
      FSfxVol := EnsureRange(StrToIntDef(SL.Values['sound_volume'], FSfxVol), 0, 10);
      FMusicChoice := EnsureRange(StrToIntDef(SL.Values['music'], 0), 0, TrackCount);
      FDifficulty := EnsureRange(StrToIntDef(SL.Values['difficulty'], 1), 0, 2);
      FSeasonChoice := EnsureRange(StrToIntDef(SL.Values['season'], 0), 0, 4);
      FTimeChoice := EnsureRange(StrToIntDef(SL.Values['time'], 0), 0, 3);
      FHudOn := SL.Values['hud'] <> '0';
      FThemeChoice := EnsureRange(StrToIntDef(SL.Values['background'], 0), 0, MapThemeCount);
      FFullWanted := SL.Values['fullscreen'] = '1';
      FVSyncWanted := SL.Values['vsync'] <> '0';
      if (SL.Values['player'] <> '') and FileExists(PlayerFolder(PCRoot) + SL.Values['player']) then
      begin
        FPlayer := TPCPlayer.Create('');
        try
          FPlayer.LoadFromFile(PlayerFolder(PCRoot) + SL.Values['player']);
          FCharacter := FPlayer.Character;
        except
          FreeAndNil(FPlayer);
        end;
      end;
    except
    end;
  finally
    SL.Free;
  end;
  FAuto := FTimeChoice = 0;
  if FTimeChoice > 0 then SetModeInstant(FTimeChoice - 1);
  if FSeasonChoice < 4 then SetSeason(FSeasonChoice, False);
end;

procedure TGameScene.SaveSettings;
var
  SL: TStringList;
begin
  if FExportCopy then Exit;
  SL := TStringList.Create;
  try
    SL.Add('music_volume=' + IntToStr(FMusicVol));
    SL.Add('sound_volume=' + IntToStr(FSfxVol));
    SL.Add('music=' + IntToStr(FMusicChoice));
    SL.Add('difficulty=' + IntToStr(FDiffUser));
    SL.Add('season=' + IntToStr(FSeasonChoice));
    SL.Add('time=' + IntToStr(FTimeChoice));
    SL.Add('hud=' + IntToStr(Ord(FHudOn)));
    SL.Add('background=' + IntToStr(FThemeChoice));
    SL.Add('fullscreen=' + IntToStr(Ord(FFullWanted)));
    SL.Add('vsync=' + IntToStr(Ord(FVSyncWanted)));
    if FPlayer <> nil then SL.Add('player=' + ExtractFileName(FPlayer.FileName));
    try
      SL.SaveToFile(PCRoot + 'papercrane.ini');
    except
    end;
  finally
    SL.Free;
  end;
end;

procedure TGameScene.LoadScores;
var
  SL, Parts: TStringList;
  I: Integer;
  F: string;
  R: TScoreRec;
begin
  SetLength(FScores, 0);
  FBest := 0;
  F := PCRoot + 'papercrane_scores.txt';
  if not FileExists(F) then Exit;
  SL := TStringList.Create;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ';';
    Parts.StrictDelimiter := True;
    try
      SL.LoadFromFile(F);
      for I := 0 to SL.Count - 1 do
      begin
        Parts.DelimitedText := SL[I];
        if Parts.Count < 6 then Continue;
        R.Score := StrToIntDef(Parts[0], 0);
        R.Dist := StrToIntDef(Parts[1], 0);
        R.Lanterns := StrToIntDef(Parts[2], 0);
        R.Season := EnsureRange(StrToIntDef(Parts[3], 0), 0, 3);
        R.Difficulty := EnsureRange(StrToIntDef(Parts[4], 1), 0, 2);
        R.When := Parts[5];
        if Length(FScores) < 10 then
        begin
          SetLength(FScores, Length(FScores) + 1);
          FScores[High(FScores)] := R;
        end;
      end;
    except
    end;
  finally
    Parts.Free;
    SL.Free;
  end;
  if Length(FScores) > 0 then FBest := FScores[0].Score;
end;

procedure TGameScene.SaveScores;
var
  SL: TStringList;
  I: Integer;
begin
  if FExportCopy then Exit;
  SL := TStringList.Create;
  try
    for I := 0 to High(FScores) do
      with FScores[I] do
        SL.Add(Format('%d;%d;%d;%d;%d;%s', [Score, Dist, Lanterns, Season, Difficulty, When]));
    try
      SL.SaveToFile(PCRoot + 'papercrane_scores.txt');
    except
    end;
  finally
    SL.Free;
  end;
end;

{ a finished flight goes into the top 10 (rank shown on the game over card) }
procedure TGameScene.AddScore;
var
  I, Pos: Integer;
  R: TScoreRec;
begin
  FRank := -1;
  if FReplay or FEditMode then
  begin
    FNewBest := False;
    Exit;
  end;
  FNewBest := FScore > FBest;
  if FNewBest then FBest := FScore;
  if (FScore <= 0) or FExportCopy then Exit;
  Pos := Length(FScores);
  for I := 0 to High(FScores) do
    if FScore > FScores[I].Score then
    begin
      Pos := I;
      Break;
    end;
  if Pos >= 10 then Exit;
  R.Score := FScore;
  R.Dist := Round(FDist);
  R.Lanterns := FLanternsGot;
  R.Season := FSeason;
  R.Difficulty := FDifficulty;
  R.When := FormatDateTime('yyyy-mm-dd hh:nn', Now);
  SetLength(FScores, Length(FScores) + 1);
  for I := High(FScores) downto Pos + 1 do FScores[I] := FScores[I - 1];
  FScores[Pos] := R;
  if Length(FScores) > 10 then SetLength(FScores, 10);
  FRank := Pos;
  SaveScores;
end;

{ ---------- saved games (.pcsave) ---------- }

procedure TGameScene.SaveGame;
var
  SL: TStringList;
  I: Integer;
  FN, Line: string;
  FS: TFormatSettings;

  function F(V: Single): string;
  begin
    Result := FloatToStrF(V, ffFixed, 9, 2, FS);
  end;

begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  ForceDirectories(DataDir('saves'));
  FN := DataDir('saves') + 'save_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.pcsave';
  SL := TStringList.Create;
  try
    SL.Add('PCSAVE 1');
    if FMapMode = 1 then
      SL.Add('name=' + Format('%s - %d m, %d pts (%s)', [FMap.Name, Round(FDist), FScore, FormatDateTime('mm-dd hh:nn', Now)]))
    else
      SL.Add('name=' + Format('Random #%d - %d m, %d pts (%s)', [FSeed mod 100000, Round(FDist), FScore,
        FormatDateTime('mm-dd hh:nn', Now)]));
    SL.Add('mode=' + IntToStr(FMapMode));
    SL.Add('map=' + FMap.FileName);
    SL.Add('seed=' + IntToStr(FSeed));
    SL.Add(Format('gen=%d;%s;%d;%d', [FGen.State, F(FGen.D), FGen.Count, FGen.Difficulty]));
    SL.Add('difficulty=' + IntToStr(FDifficulty));
    SL.Add('season=' + IntToStr(FSeason));
    SL.Add('time=' + IntToStr(CurrentMode));
    SL.Add('theme=' + IntToStr(FTheme));
    SL.Add('scroll=' + F(FScroll));
    SL.Add(Format('crane=%s;%s;%s', [F(FY), F(FVY), F(FInvuln)]));
    SL.Add(Format('score=%d;%d;%d', [FScore, FLives, FLanternsGot]));
    for I := 0 to High(FObs) do
      with FObs[I] do
        SL.Add(Format('obs=%s;%s;%s;%s;%d;%d;%d;%d', [F(X), F(W), F(GapY), F(Gap), Ord(HasTop), Ord(HasBottom),
          Ord(Passed), Seed]));
    for I := 0 to High(FLants) do
      if FLants[I].Alive then SL.Add(Format('lant=%s;%s', [F(FLants[I].X), F(FLants[I].Y)]));
    for I := 0 to High(FHawks) do
      if FHawks[I].Alive then SL.Add(Format('hawk=%s;%s', [F(FHawks[I].X), F(FHawks[I].Y)]));
    for I := 0 to High(FBonus) do
      if FBonus[I].Alive then SL.Add(Format('bonus=%d;%s;%s', [FBonus[I].Kind, F(FBonus[I].X), F(FBonus[I].Y)]));
    for I := 0 to High(FHaz) do
      with FHaz[I].O do
        SL.Add(Format('haz=%d;%s;%s;%s;%s;%s;%s;%d;%d;%d', [Ord(Kind), F(D), F(Y), F(W), F(GapY), F(Gap), F(Amp),
          Ord(Top), Ord(Bottom), Ord(FHaz[I].Passed)]));
    SL.Add('slow=' + F(FSlowT));
    // the flight so far, so a ghost can still be saved after continuing
    Line := '';
    for I := 0 to High(FRec) do
    begin
      Line := Line + F(FRec[I].X) + ',' + F(FRec[I].Y) + ' ';
      if (I mod 40 = 39) or (I = High(FRec)) then
      begin
        SL.Add('rec=' + Trim(Line));
        Line := '';
      end;
    end;
    for I := 0 to High(FRecFlaps) do SL.Add('flap=' + F(FRecFlaps[I]));
    SL.SaveToFile(FN);
    FMsg := 'saved: ' + ExtractFileName(FN);
  finally
    SL.Free;
  end;
  FCardKey := '#';
end;

procedure ParsePairs(const V: string; var Arr: TPointFArray; const FS: TFormatSettings);
var
  P: TStringList;
  I, C: Integer;
begin
  P := TStringList.Create;
  try
    P.Delimiter := ' ';
    P.StrictDelimiter := True;
    P.DelimitedText := V;
    for I := 0 to P.Count - 1 do
    begin
      C := Pos(',', P[I]);
      if C = 0 then Continue;
      SetLength(Arr, Length(Arr) + 1);
      Arr[High(Arr)] := PointF(StrToFloatDef(Copy(P[I], 1, C - 1), 0, FS), StrToFloatDef(Copy(P[I], C + 1, 99), 0, FS));
    end;
  finally
    P.Free;
  end;
end;

procedure TGameScene.LoadGame(const AFile: string);
var
  SL, Parts: TStringList;
  I: Integer;
  K, V: string;
  Ob: TObstacle;
  It: TItem;
  Hz: THazard;
  FS: TFormatSettings;
  Rec: TPointFArray;

  function N(Idx: Integer; Def: Single): Single;
  begin
    if Idx < Parts.Count then Result := StrToFloatDef(Parts[Idx], Def, FS) else Result := Def;
  end;

begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SL := TStringList.Create;
  Parts := TStringList.Create;
  try
    try
      Parts.Delimiter := ';';
      Parts.StrictDelimiter := True;
      SL.LoadFromFile(AFile);
      FReplay := False;
      FRace := False;
      FMapMode := StrToIntDef(SL.Values['mode'], 0);
      FDifficulty := EnsureRange(StrToIntDef(SL.Values['difficulty'], 1), 0, 2);
      FSeed := StrToInt64Def(SL.Values['seed'], 1);
      if FMapMode = 1 then
      begin
        FMap.LoadFromFile(SL.Values['map']);
        StartMapObj(FMap, 0);
      end
      else
        StartRandom(FSeed);
      FDifficulty := EnsureRange(StrToIntDef(SL.Values['difficulty'], 1), 0, 2);
      SetLength(FObs, 0);
      SetLength(FLants, 0);
      SetLength(FHawks, 0);
      SetLength(FBonus, 0);
      SetLength(FHaz, 0);
      SetLength(Rec, 0);
      SetLength(FRecFlaps, 0);
      for I := 1 to SL.Count - 1 do
      begin
        K := SL.Names[I];
        V := SL.ValueFromIndex[I];
        Parts.DelimitedText := V;
        if K = 'gen' then
        begin
          FGen.State := StrToInt64Def(Parts[0], 1);
          FGen.D := N(1, 1060);
          FGen.Count := Round(N(2, 0));
          FGen.Difficulty := Round(N(3, 1));
        end
        else if K = 'scroll' then FScroll := N(0, 0)
        else if K = 'crane' then
        begin
          FY := N(0, 380);
          FVY := N(1, 0);
          FInvuln := Max(1.2, N(2, 0));   // a moment of safety after loading
        end
        else if K = 'score' then
        begin
          FScore := Round(N(0, 0));
          FLives := Round(N(1, 3));
          FLanternsGot := Round(N(2, 0));
        end
        else if K = 'season' then SetSeason(EnsureRange(StrToIntDef(V, 0), 0, 3), False)
        else if K = 'theme' then SetTheme(EnsureRange(StrToIntDef(V, 0), 0, MapThemeCount - 1), False)
        else if K = 'time' then SetModeInstant(EnsureRange(StrToIntDef(V, 1), 0, 2))
        else if K = 'obs' then
        begin
          Ob.X := N(0, 0); Ob.W := N(1, 70); Ob.GapY := N(2, 400); Ob.Gap := N(3, 250);
          Ob.HasTop := (Parts.Count > 4) and (Parts[4] = '1');
          Ob.HasBottom := (Parts.Count > 5) and (Parts[5] = '1');
          Ob.Passed := (Parts.Count > 6) and (Parts[6] = '1');
          Ob.Seed := Round(N(7, 0));
          SetLength(FObs, Length(FObs) + 1);
          FObs[High(FObs)] := Ob;
        end
        else if (K = 'lant') or (K = 'hawk') then
        begin
          It.X := N(0, 0);
          It.Y := N(1, 400);
          It.Phase := Frac(It.X * 0.013) * 6;
          It.Alive := True;
          if K = 'lant' then
          begin
            SetLength(FLants, Length(FLants) + 1);
            FLants[High(FLants)] := It;
          end
          else
          begin
            SetLength(FHawks, Length(FHawks) + 1);
            FHawks[High(FHawks)] := It;
          end;
        end
        else if K = 'bonus' then
        begin
          It.Kind := Round(N(0, 0));
          It.X := N(1, 0);
          It.Y := N(2, 400);
          It.Phase := Frac(It.X * 0.017) * 6;
          It.Alive := True;
          SetLength(FBonus, Length(FBonus) + 1);
          FBonus[High(FBonus)] := It;
        end
        else if K = 'haz' then
        begin
          Hz := Default(THazard);
          Hz.O.Kind := TMapObjKind(EnsureRange(Round(N(0, 6)), Ord(okSwing), Ord(High(TMapObjKind))));
          Hz.O.D := N(1, 0);
          Hz.O.Y := N(2, 400);
          Hz.O.W := N(3, 80);
          Hz.O.GapY := N(4, 400);
          Hz.O.Gap := N(5, 280);
          Hz.O.Amp := N(6, 0);
          Hz.O.Top := (Parts.Count > 7) and (Parts[7] = '1');
          Hz.O.Bottom := (Parts.Count > 8) and (Parts[8] = '1');
          Hz.Passed := (Parts.Count > 9) and (Parts[9] = '1');
          Hz.O.Scale := 1;
          SetLength(FHaz, Length(FHaz) + 1);
          FHaz[High(FHaz)] := Hz;
        end
        else if K = 'slow' then FSlowT := N(0, 0)
        else if K = 'rec' then ParsePairs(V, Rec, FS)
        else if K = 'flap' then
        begin
          SetLength(FRecFlaps, Length(FRecFlaps) + 1);
          FRecFlaps[High(FRecFlaps)] := N(0, 0);
        end;
      end;
      FRec := Rec;
      FDist := FScroll / 10;
      FHudKey := '#';
      OpenMenu(msPause);   // the flight waits under the pause card: Resume to go on
      FMsg := 'loaded: press Resume';
    except
      on E: Exception do
      begin
        FMsg := 'cannot load: ' + E.Message;
        OpenMenu(msSaves);
      end;
    end;
  finally
    Parts.Free;
    SL.Free;
  end;
end;

{ ---------- ghosts (.pcghost) ---------- }

procedure TGameScene.SaveGhost;
var
  SL: TStringList;
  I: Integer;
  FN, Line: string;
  FS: TFormatSettings;
begin
  if Length(FRec) < 2 then
  begin
    FMsg := 'the flight was too short for a ghost';
    FCardKey := '#';
    Exit;
  end;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  ForceDirectories(DataDir('ghosts'));
  FN := DataDir('ghosts') + 'ghost_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.pcghost';
  SL := TStringList.Create;
  try
    SL.Add('PCGHOST 1');
    if FMapMode = 1 then
      SL.Add('name=' + Format('%s - %d pts, %d m (%s)', [FMap.Name, FScore, Round(FDist), FormatDateTime('mm-dd hh:nn', Now)]))
    else
      SL.Add('name=' + Format('Random #%d - %d pts, %d m (%s)', [FSeed mod 100000, FScore, Round(FDist),
        FormatDateTime('mm-dd hh:nn', Now)]));
    SL.Add('mode=' + IntToStr(FMapMode));
    SL.Add('map=' + FMap.FileName);
    SL.Add('seed=' + IntToStr(FSeed));
    SL.Add('difficulty=' + IntToStr(FDifficulty));
    SL.Add('season=' + IntToStr(FSeason));
    SL.Add('time=' + IntToStr(CurrentMode));
    SL.Add(Format('result=%d;%d;%d', [FScore, Round(FDist), FLanternsGot]));
    Line := '';
    for I := 0 to High(FRec) do
    begin
      Line := Line + FloatToStrF(FRec[I].X, ffFixed, 9, 1, FS) + ',' + FloatToStrF(FRec[I].Y, ffFixed, 8, 1, FS) + ' ';
      if (I mod 40 = 39) or (I = High(FRec)) then
      begin
        SL.Add('rec=' + Trim(Line));
        Line := '';
      end;
    end;
    for I := 0 to High(FRecFlaps) do SL.Add('flap=' + FloatToStrF(FRecFlaps[I], ffFixed, 9, 1, FS));
    SL.SaveToFile(FN);
    FMsg := 'ghost saved: ' + ExtractFileName(FN);
  finally
    SL.Free;
  end;
  FCardKey := '#';
end;

{ replay a ghost (the crane follows the recording) or race against it }
procedure TGameScene.StartGhost(const AFile: string; Race: Boolean);
var
  SL: TStringList;
  I: Integer;
  K, V: string;
  FS: TFormatSettings;
  Rec: TPointFArray;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(AFile);
      if (SL.Count = 0) or (Copy(SL[0], 1, 7) <> 'PCGHOST') then raise Exception.Create('not a ghost file');
      SetLength(Rec, 0);
      SetLength(FGhostFlaps, 0);
      for I := 1 to SL.Count - 1 do
      begin
        K := SL.Names[I];
        V := SL.ValueFromIndex[I];
        if K = 'rec' then ParsePairs(V, Rec, FS)
        else if K = 'flap' then
        begin
          SetLength(FGhostFlaps, Length(FGhostFlaps) + 1);
          FGhostFlaps[High(FGhostFlaps)] := StrToFloatDef(V, 0, FS);
        end;
      end;
      FGhost := Rec;
      FGhostFile := AFile;
      FGhostFlapI := 0;
      FGhostFlapJ := 0;
      FDifficulty := EnsureRange(StrToIntDef(SL.Values['difficulty'], 1), 0, 2);
      SetSeason(EnsureRange(StrToIntDef(SL.Values['season'], FSeason), 0, 3), True);
      if StrToIntDef(SL.Values['mode'], 0) = 1 then
      begin
        FMap.LoadFromFile(SL.Values['map']);
        FReplay := False;
        FRace := False;
        StartMapObj(FMap, 0);
      end
      else
        StartRandom(StrToInt64Def(SL.Values['seed'], 1));
      FDifficulty := EnsureRange(StrToIntDef(SL.Values['difficulty'], 1), 0, 2);
      FReplay := not Race;
      FRace := Race;
      FGhostFile := AFile;
      if FReplay then FInvuln := 0;
      FMsg := '';
    except
      on E: Exception do
      begin
        FMsg := 'cannot open the ghost: ' + E.Message;
        FCardKey := '#';
      end;
    end;
  finally
    SL.Free;
  end;
end;

function TGameScene.GhostYAt(D: Single; out Ok: Boolean): Single;
var
  Lo, Hi, Mid: Integer;
  T: Single;
begin
  Ok := False;
  Result := 380;
  if Length(FGhost) < 2 then Exit;
  if (D < FGhost[0].X) or (D > FGhost[High(FGhost)].X) then
  begin
    if D < FGhost[0].X then
    begin
      Ok := True;
      Result := FGhost[0].Y;
    end;
    Exit;
  end;
  Lo := 0;
  Hi := High(FGhost);
  while Hi - Lo > 1 do
  begin
    Mid := (Lo + Hi) div 2;
    if FGhost[Mid].X <= D then Lo := Mid else Hi := Mid;
  end;
  T := (D - FGhost[Lo].X) / Max(0.01, FGhost[Hi].X - FGhost[Lo].X);
  Result := FGhost[Lo].Y + (FGhost[Hi].Y - FGhost[Lo].Y) * T;
  Ok := True;
end;

{ ---------- Map Editor 1: the game as a live preview ---------- }

procedure TGameScene.EditorShowMap(M: TPCMap);
var
  KeepScroll: Single;
begin
  KeepScroll := FScroll;
  FEditMode := True;
  FEditPlay := False;
  FMap.Assign(M);
  FMapMode := 1;
  SetTheme(RunTheme, False);
  FReplay := False;
  FRace := False;
  FMenu := msNone;
  FCardKey := '#';
  ClearShapeLib;
  ResetWorld;
  FScroll := KeepScroll;
  FState := gsTitle;
  FAutoPilot := False;
  if FMap.Season >= 0 then SetSeason(FMap.Season, False);
  if FMap.TimeOfDay >= 0 then
  begin
    FAuto := False;
    SetModeInstant(FMap.TimeOfDay);
  end;
end;

procedure TGameScene.EditorPlayFrom(M: TPCMap; FromD: Single);
begin
  FEditMode := True;
  FEditPlay := True;
  StartMapObj(M, FromD);
  FY := 380;
end;

procedure TGameScene.EditorStop;
begin
  FEditPlay := False;
  FState := gsTitle;
  EditorShowMap(FMap);
end;

function TGameScene.EditorPlaying: Boolean;
begin
  Result := FEditMode and FEditPlay;
end;

procedure TGameScene.LoadBest;
var
  SL: TStringList;
  F: string;
begin
  FBest := 0;
  F := PCRoot + 'papercrane_best.txt';
  if not FileExists(F) then Exit;
  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(F);
      if SL.Count > 0 then FBest := StrToIntDef(Trim(SL[0]), 0);
    except
      FBest := 0;
    end;
  finally
    SL.Free;
  end;
end;

procedure TGameScene.SaveBest;
var
  SL: TStringList;
begin
  if FExportCopy then Exit;
  SL := TStringList.Create;
  try
    SL.Add(IntToStr(FBest));
    try
      SL.SaveToFile(PCRoot + 'papercrane_best.txt');
    except
    end;
  finally
    SL.Free;
  end;
end;

{ HUD card: score, best, lanterns, lives (paper hearts), distance, season.
  Built on the main thread (Prepare) only when its text changes. }
procedure TGameScene.MakeHud;
var
  Key, Line: string;
  I: Integer;
  Svg: TSvgRecorder;
  X: Single;
begin
  Key := Format('%d|%d|%d|%d|%d|%d|%d|%d|%d', [FScore, FBest, FLanternsGot, FLives, Round(FDist), FSeason, FState,
    FDifficulty, Ceil(FSlowT)]);
  if (Key = FHudKey) and (FHud <> nil) then Exit;
  FHudKey := Key;
  FreeAndNil(FHud);
  FHud := TBGRABitmap.Create(Max(1, Round(S(780))), Max(1, Round(S(64))));
  FHud.FillRoundRectAntialias(S(4), S(6), S(778), S(62), S(10), S(10), BGRA(0, 0, 0, 55));
  FHud.FillRoundRectAntialias(S(1), S(1), S(772), S(56), S(10), S(10), BGRA(246, 238, 222, 235));
  FHud.RoundRectAntialias(S(6), S(6), S(766), S(51), S(6), S(6), BGRA(178, 40, 34, 200), Max(1, S(1.2)));
  FHud.FontName := 'Segoe UI';
  FHud.FontQuality := fqSystem;
  FHud.FontStyle := [fsBold];
  FHud.FontHeight := Max(8, Round(S(24)));
  Line := Format('Score %d', [FScore]);
  FHud.TextOut(S(18), S(14), Line, BGRA(48, 40, 52));
  FHud.FontStyle := [];
  FHud.FontHeight := Max(7, Round(S(17)));
  FHud.TextOut(S(160), S(19), Format('Best %d   Lanterns %d   %d m   %s',
    [FBest, FLanternsGot, Round(FDist), SeasonNames[FSeason]]), BGRA(120, 50, 40));
  if FSlowT > 0 then
  begin
    FHud.FontStyle := [fsBold];
    FHud.TextOut(S(500), S(19), Format('SLOW %ds', [Ceil(FSlowT)]), BGRA(40, 100, 180));
    FHud.FontStyle := [];
  end;
  for I := 0 to Max(MaxLives, FLives) - 1 do
  begin
    X := 618 + I * 24;
    if I < FLives then
    begin
      FHud.FillEllipseAntialias(S(X - 4), S(24), S(6), S(6), BGRA(212, 42, 32));
      FHud.FillEllipseAntialias(S(X + 4), S(24), S(6), S(6), BGRA(212, 42, 32));
      FHud.FillPolyAntialias([PointF(S(X - 10), S(26)), PointF(S(X + 10), S(26)), PointF(S(X), S(38))], BGRA(212, 42, 32));
    end
    else
      FHud.EllipseAntialias(S(X), S(28), S(8), S(8), BGRA(150, 130, 120), Max(1, S(1.4)));
  end;
  FHud.LoadFromBitmapIfNeeded;
  FHud.InvalidateBitmap;
  FSvgHud := '';
  if FRecordSvg then
  begin
    Svg := TSvgRecorder.Create('h');
    try
      Svg.RoundRect(S(1), S(1), S(552), S(56), S(10), S(10), BGRA(246, 238, 222, 235));
      Svg.Text(S(18), S(14), Format('Score %d', [FScore]), 'Segoe UI', Max(8, Round(S(24))), True, BGRA(48, 40, 52), False);
      Svg.Text(S(160), S(19), Format('Best %d   Lanterns %d   %d m   %s', [FBest, FLanternsGot, Round(FDist),
        SeasonNames[FSeason]]), 'Segoe UI', Max(7, Round(S(17))), False, BGRA(120, 50, 40), False);
      FSvgHud := Svg.Take(0);
    finally
      Svg.Free;
    end;
  end;
end;

{ The title / pause / game over card (main thread, when it changes). }
{ The menu card (main thread, only when it changes): a title, info lines and
  the items; for settings "label  < value >" in two columns; high scores as a
  table. The selection marker is drawn live in RenderBand. }
procedure TGameScene.MakeCard;
const
  ScoreTabs: array[0..6] of Single = (44, 92, 180, 290, 400, 500, 600);
  StatsTabs: array[0..6] of Single = (60, 380, 470, 570, 670, 770, 860);
  StatsHead = 'Map'#9'Flights'#9'Best'#9'Score'#9'Bonus'#9'Done';
var
  TabX: array[0..6] of Single;
  Key, Title, It, Lab, Val: string;
  Info: array of string;
  I, K, TabP, NInfo: Integer;
  CW, CH, Y, InfoH, ItemsTop: Single;
  Col: TBGRAPixel;
  Svg: TSvgRecorder;
  Table: Boolean;

  procedure AddInfo(const S: string);
  begin
    SetLength(Info, Length(Info) + 1);
    Info[High(Info)] := S;
  end;

begin
  // the selection is not part of the card: moving it costs nothing (RenderBand
  // picks the selected item sprite and draws the highlight live)
  Key := IntToStr(FFxVersion) + '|' + FMsg + '|' + FNameEdit + '|' + IntToStr(FCharacter) + '|' + IfThen(FPlayer <> nil, '1', '0') + '|' +
    IfThen(FMenu = msCharacter, IntToStr(FSel), '') + '|' + IntToStr(Length(FSelPlayers)) + IfThen(FSelCanBack, 'b', '') +
    IfThen(SelHasQuit, 'q', '') + '|' +
    IntToStr(FListTop) + '|' + IntToStr(FList.Count) + Format('|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d', [FMenu, FMusicVol, FSfxVol,
    FMusicChoice, FDifficulty, FSeasonChoice, FTimeChoice + 10 * FThemeChoice, Ord(FHudOn), Ord(FFullWanted), Ord(FVSyncWanted),
    FScore, FBest, FRank, Length(FScores), FSeason, FWidth, FHeight]);
  if Key = FCardKey then
  begin
    MakeItems;   // a changed value only rebuilds its own item
    Exit;
  end;
  FCardKey := Key;
  FreeAndNil(FCard);
  FreeItems;
  FSvgCard := '';
  FMenuN := 0;
  if FMenu = msNone then Exit;
  SetLength(Info, 0);
  Table := False;
  case FMenu of
    msMain:
      begin
        Title := 'PAPER CRANE  ' + #$E7#$BA#$B8#$E9#$B9#$A4;
        AddInfo('A papercut flight up the Li river');
        AddInfo(Format('Best %d     %s     %s', [FBest, DiffNames[FDiffUser], SeasonNames[FSeason]]));
        FMenuN := 12;
      end;
    msPause:
      begin
        Title := 'PAUSED';
        AddInfo(Format('Score %d     %d m     lanterns %d', [FScore, Round(FDist), FLanternsGot]));
        if FMapMode = 1 then AddInfo(Format('Map: %s     %d of %d m', [FMap.Name, Round(FDist), Round(FMap.Length_ / 10)]))
        else if FReplay then AddInfo('Replay of a ghost')
        else AddInfo(Format('Random map  #%d', [FSeed mod 100000]));
        FMenuN := 6;
      end;
    msOver:
      begin
        if FWon then Title := 'MAP COMPLETE!'
        else if FReplay then Title := 'END OF THE REPLAY'
        else Title := 'GAME OVER';
        AddInfo(Format('Score %d     lanterns %d     %d m', [FScore, FLanternsGot, Round(FDist)]));
        if FNewBest then AddInfo('NEW BEST!')
        else if FRank >= 0 then AddInfo(Format('Rank #%d in the high scores     best %d', [FRank + 1, FBest]))
        else AddInfo(Format('Best %d', [FBest]));
        if (FPlayer <> nil) and not FReplay then
        begin
          if FMapMode = 1 then K := FPlayer.MapIndex(FMap.Name, False) else K := FPlayer.MapIndex(RandomMapName, False);
          if K >= 0 then
            AddInfo(Format('%s here: best %d m, best score %d, %d flights', [FPlayer.Name, FPlayer.Maps[K].BestDist,
              FPlayer.Maps[K].BestScore, FPlayer.Maps[K].Plays]));
        end;
        FMenuN := 4;
      end;
    msMaps, msSaves, msGhosts:
      begin
        case FMenu of
          msMaps: Title := 'CUSTOM MAPS';
          msSaves: Title := 'SAVED GAMES';
        else
          Title := 'GHOSTS';
        end;
        if FList.Count = 0 then
          case FMenu of
            msMaps: AddInfo('No maps yet - make one with a map editor (maps folder)');
            msSaves: AddInfo('No saved games - pause a flight and choose Save game');
          else
            AddInfo('No ghosts - after a flight choose Save ghost');
          end
        else
          AddInfo(Format('%d - %d of %d   (Up / Down scroll the list)', [FListTop + 1, FListTop + ListVisible,
            FList.Count]));
        FMenuN := ListVisible + 1;
      end;
    msPlayers:
      begin
        Title := 'PLAYERS';
        if FList.Count = 0 then AddInfo('No players yet - make one')
        else AddInfo(Format('%d - %d of %d', [FListTop + 1, FListTop + ListVisible, FList.Count]));
        FMenuN := ListVisible + 2;
      end;
    msPlayerItem:
      begin
        if FPlayer <> nil then
        begin
          Title := UpperCase(FPlayer.Name);
          AddInfo(Format('%s   -   %d flights, best %d m, best score %d', [CharNames[FCharacter], FPlayer.Games,
            FPlayer.BestDist, FPlayer.BestScore]));
        end
        else
          Title := 'PLAYER';
        FMenuN := 5;
      end;
    msNewName:
      begin
        Title := 'NEW PLAYER';
        AddInfo('Type your name, then Enter   (Backspace deletes, Esc back)');
        AddInfo(FNameEdit + '_');
        FMenuN := 2;
      end;
    msCharacter:
      begin
        Title := 'CHOOSE YOUR CHARACTER';
        AddInfo('Up / Down to look at them, Enter to fly with one');
        AddInfo(CharNames[EnsureRange(FSel, 0, CharCount - 1)] + ': ' + CharInfo[EnsureRange(FSel, 0, CharCount - 1)]);
        FMenuN := CharCount + 1;
      end;
    msSelect:
      begin
        Title := 'SELECT YOUR PAPER CARD';
        AddInfo('Left / Right choose a player,  Enter or click to fly' + IfThen(FSelCanBack, ',  Esc back', '') +
          IfThen(SelHasQuit, ',  Esc twice quits', ''));
        FMenuN := SelCount + Ord(SelHasQuit);
        if SelHasQuit then
        begin
          FGlyphs.Prepare(FFx.Menus[MenuStyle].Item, FScale, 'Quit');
          FGlyphs.Prepare(FFx.Menus[MenuStyle].Sel, FScale, 'Quit');
        end;
      end;
    msStats:
      begin
        Title := 'STATISTICS';
        Table := True;
        if FPlayer = nil then AddInfo('No player chosen - choose one in Player')
        else
          with FPlayer do
          begin
            AddInfo(Format('%s  -  %s  -  since %s', [Name, CharNames[Character], Created]));
            AddInfo(Format('%d flights   %d maps completed   %d lives lost   %s in the air', [Games, Wins, Deaths,
              FormatPlayTime(Seconds)]));
            AddInfo(Format('Distance %d m (best %d m)   Score %d (best %d)   obstacles passed %d', [Distance, BestDist,
              Score, BestScore, Passed]));
            AddInfo(Format('Lanterns %d (best %d)   Hearts %d   Hourglasses %d   best bonus in a flight %d', [Lanterns,
              BestLanterns, Hearts, Slows, BestBonus]));
            if Length(Maps) > 0 then
            begin
              AddInfo(StatsHead);
              for I := 0 to Min(7, High(Maps)) do
                with Maps[I] do
                  AddInfo(Format('%s'#9'%d'#9'%d m'#9'%d'#9'%d'#9'%d', [Copy(Name, 1, 26), Plays, BestDist, BestScore,
                    BestBonus, Completed]));
            end;
          end;
        FMenuN := 1;
      end;
    msSaveItem, msGhostItem:
      begin
        if FMenu = msSaveItem then Title := 'SAVED GAME' else Title := 'GHOST';
        AddInfo(FListNames[EnsureRange(FList.IndexOf(FSelFile), 0, FListNames.Count - 1)]);
        if FMenu = msSaveItem then FMenuN := 3 else FMenuN := 4;
      end;
    msSettings:
      begin
        Title := 'SETTINGS';
        AddInfo('Up / Down choose,  Left / Right or click change,  Esc back');
        FMenuN := 11;
      end;
    msHelp:
      begin
        Title := 'HOW TO PLAY';
        AddInfo('Space, Up, W or a mouse click: beat the wings and climb.');
        AddInfo('Fly through the gaps between the stone pillars and the hanging rocks.');
        AddInfo('Every obstacle passed +1, every red lantern +5.');
        AddInfo('Hawks fly against you - keep away. The river runs ever faster.');
        AddInfo('A hit costs a life and gives a moment of safety (the crane blinks).');
        AddInfo('Esc or P: pause.   1 2 3 4: season.   M D N A: time of day.');
        AddInfo('Easy: 5 lives, wide gaps.   Normal: 3.   Hard: 2, fast and narrow.');
        AddInfo('Random map: an endless river.  Custom maps: made in the map editors.');
        AddInfo('Pause > Save game, Saved games > Continue / Delete.');
        AddInfo('Game over > Save ghost, Ghosts > Replay / Race / Delete.');
        AddInfo('Player: a name and a character; Statistics keeps every flight.');
        AddInfo('Hearts: one more life.  Hourglass: the river slows down.');
        FMenuN := 1;
      end;
    msScores:
      begin
        Title := 'HIGH SCORES';
        Table := True;
        if Length(FScores) = 0 then AddInfo('No flights yet - be the first!')
        else
          for I := 0 to High(FScores) do
            with FScores[I] do
              AddInfo(Format('%d'#9'%d'#9'%d m'#9'%d'#9'%s'#9'%s'#9'%s',
                [I + 1, Score, Dist, Lanterns, Copy(SeasonNames[Season], 1, 6), DiffNames[Difficulty], When]));
        FMenuN := 1;
      end;
    msCredits:
      begin
        Title := 'CREDITS';
        AddInfo('Paper Crane - a papercut flying game');
        AddInfo('Made with Lazarus / Free Pascal, BGRABitmap and SDL3');
        AddInfo('Every pixel cut on all CPU cores, 60 Hz vsync');
        AddInfo('Music: 7 tunes composed and synthesised in code');
        AddInfo('(guzheng, pipa, dizi, erhu, bells, drums - pentatonic modes)');
        AddInfo('Sound effects synthesised in code, no sound files');
        FMenuN := 1;
      end;
  end;
  if FMsg <> '' then AddInfo(FMsg);
  if FSel >= FMenuN then FSel := FMenuN - 1;
  NInfo := Length(Info);
  if FMenu = msStats then TabX := StatsTabs else TabX := ScoreTabs;
  CW := 860;
  if Table then InfoH := 30 else InfoH := 32;
  FItemH := 46;
  ItemsTop := 98 + NInfo * InfoH + 14;
  if Table then ItemsTop := ItemsTop + 30;
  CH := ItemsTop + FMenuN * FItemH + 40;
  if FMenu = msSelect then CH := ItemsTop + 4;
  FCardTop := Max(20, (DesignH - CH) / 2);
  if FMenu = msSelect then
  begin
    FCardTop := 40;
    MakeSelectCards;
  end;
  FCardW := CW;
  FCardX0 := DesignW / 2 - CW / 2;
  FCardX1 := DesignW / 2 + CW / 2;
  FItemY0 := FCardTop + ItemsTop;
  FCard := BlankCard(CW, CH, FFx.Menus[MenuStyle].Frame);
  FCardTitle := Title;
  FCardH := CH;
  if FGlyphScale <> FScale then
  begin
    FGlyphs.Clear;
    FGlyphScale := FScale;
  end;
  FGlyphs.Prepare(FFx.Menus[MenuStyle].Title, FScale, Title);
  FCard.FontName := 'Segoe UI';
  FCard.FontQuality := fqSystem;  // GDI text: many times faster than fine antialiasing
  FCard.FontStyle := [fsBold];
  FCard.FontHeight := Max(10, Round(S(44)));
  FCard.FontStyle := [];
  FCard.FontHeight := Max(7, Round(S(IfThen(Table, 18, 20))));
  if (FMenu = msScores) and Table and (NInfo > 0) and (Length(FScores) > 0) then
  begin
    FCard.FontStyle := [fsBold];
    Info := Concat(['#'#9'Score'#9'Distance'#9'Lanterns'#9'Season'#9'Level'#9'Date'], Info);
    NInfo := Length(Info);
  end;
  for I := 0 to NInfo - 1 do
  begin
    Y := 92 + I * InfoH;
    if Table and (Pos(#9, Info[I]) > 0) then
    begin
      It := Info[I] + #9;
      K := 0;
      while (Pos(#9, It) > 0) and (K < 7) do
      begin
        TabP := Pos(#9, It);
        FCard.TextOut(S(TabX[K]), S(Y), Copy(It, 1, TabP - 1),
          IfThen((I = 0) or (Info[I] = StatsHead), BGRA(178, 40, 34), BGRA(80, 60, 56)), taLeftJustify);
        Delete(It, 1, TabP);
        Inc(K);
      end;
      FCard.FontStyle := [];
    end
    else
    begin
      if (FMenu = msOver) and (I = 1) and FNewBest then Col := BGRA(196, 44, 34) else Col := BGRA(80, 60, 56);
      FCard.TextOut(S(CW / 2), S(Y), Info[I], Col, taCenter);
    end;
  end;
  FCard.LoadFromBitmapIfNeeded;
  FCard.InvalidateBitmap;
  if FRecordSvg then
  begin
    Svg := TSvgRecorder.Create('c');
    try
      Svg.RoundRect(S(1), S(1), S(CW), S(CH), S(14), S(14), BGRA(246, 238, 222, 245));
      Svg.Text(S(CW / 2), S(18), Title, 'Segoe UI', Max(10, Round(S(44))), True, BGRA(48, 40, 52), True);
      for I := 0 to FMenuN - 1 do
        Svg.Text(S(CW / 2), S(ItemsTop + I * FItemH + 8), StringReplace(MenuItem(I), #9, '   ', []), 'Segoe UI',
          Max(8, Round(S(25))), I = FSel, BGRA(64, 50, 56), True);
      FSvgCard := Svg.Take(0);
    finally
      Svg.Free;
    end;
  end;
  MakeItems;
end;

procedure TGameScene.FreeItems;
begin
  SetLength(FItemSpr, 0);   // the sprites belong to the cache
  SetLength(FItemTxt, 0);
end;

procedure TGameScene.ClearCache;
var
  I: Integer;
begin
  if FGlyphs <> nil then FGlyphs.Clear;
  if FCache = nil then Exit;
  for I := 0 to FCache.Count - 1 do
    FCache.Objects[I].Free;
  FCache.Clear;
end;

{ one menu item as a sprite (Sel 0 normal, 1 selected), cached by its text }
function TGameScene.ItemSprite(const It: string; Sel: Integer): TBGRABitmap;
var
  Key: string;
  I, TabP: Integer;
  Col: TBGRAPixel;
begin
  Key := 'i' + IntToStr(Sel) + '|' + It;
  I := FCache.IndexOf(Key);
  if I >= 0 then Exit(TBGRABitmap(FCache.Objects[I]));
  Result := TBGRABitmap.Create(Max(1, Round(S(860))), Max(1, Round(S(46))));
  Result.FontName := 'Segoe UI';
  Result.FontQuality := fqSystem;
  Result.FontHeight := Max(8, Round(S(25)));
  if Sel = 1 then
  begin
    Result.FontStyle := [fsBold];
    Col := BGRA(178, 40, 34);
  end
  else
  begin
    Result.FontStyle := [];
    Col := BGRA(64, 50, 56);
  end;
  TabP := Pos(#9, It);
  if TabP > 0 then
  begin
    Result.TextOut(S(110), S(8), Copy(It, 1, TabP - 1), Col, taLeftJustify);
    Result.TextOut(S(860 / 2 + 190), S(8), Copy(It, TabP + 1, MaxInt), Col, taCenter);
  end
  else
    Result.TextOut(S(860 / 2), S(8), It, Col, taCenter);
  Result.LoadFromBitmapIfNeeded;
  Result.InvalidateBitmap;
  FCache.AddObject(Key, Result);
end;

{ A Chinese frame on a card of CW x CH design px: a red double border with a
  key fret band (hui wen) between, ruyi cloud corners and a knot under the title. }
procedure TGameScene.ChineseFrame(B: TBGRABitmap; CW, CH: Single; Knot: Boolean);
const
  U = 11;          // one fret unit
  Out0 = 9;        // the outer border
  Band = 14;       // the fret band starts here
var
  Red, Gold, Pale: TBGRAPixel;
  A, Len: Single;
  Side, I: Integer;
  Pts: array of TPointF;

  { a point at a (along the side) and b (inwards) on side 0 top, 1 bottom, 2 left, 3 right }
  function Q(Sd: Integer; AA, BB: Single): TPointF;
  begin
    case Sd of
      0: Result := PointF(S(AA), S(Band + BB));
      1: Result := PointF(S(AA), S(CH - Band - BB));
      2: Result := PointF(S(Band + BB), S(AA));
    else
      Result := PointF(S(CW - Band - BB), S(AA));
    end;
  end;

  procedure Corner(X, Y: Single);
  begin
    // a ruyi cloud: three lobes and a diamond with a gold heart
    B.FillEllipseAntialias(S(X), S(Y), S(11), S(11), Red);
    B.FillEllipseAntialias(S(X - 9), S(Y), S(6), S(6), Red);
    B.FillEllipseAntialias(S(X + 9), S(Y), S(6), S(6), Red);
    B.FillEllipseAntialias(S(X), S(Y - 9), S(6), S(6), Red);
    B.FillEllipseAntialias(S(X), S(Y + 9), S(6), S(6), Red);
    B.FillPolyAntialias([PointF(S(X), S(Y - 7)), PointF(S(X + 7), S(Y)), PointF(S(X), S(Y + 7)), PointF(S(X - 7), S(Y))],
      Pale);
    B.FillEllipseAntialias(S(X), S(Y), S(2.6), S(2.6), Gold);
  end;

begin
  Red := BGRA(178, 40, 34, 230);
  Gold := BGRA(222, 170, 50, 255);
  Pale := BGRA(246, 238, 222, 255);
  // outer and inner borders
  B.RoundRectAntialias(S(Out0), S(Out0), S(CW - Out0), S(CH - Out0), S(6), S(6), Red, Max(1, S(2.2)));
  B.RectangleAntialias(S(Band + U + 5), S(Band + U + 5), S(CW - Band - U - 5), S(CH - Band - U - 5),
    BGRA(178, 40, 34, 150), Max(1, S(1)));
  // the key fret on all four sides
  for Side := 0 to 3 do
  begin
    if Side < 2 then Len := CW else Len := CH;
    A := Band + 22;
    SetLength(Pts, 9);
    while A + U < Len - Band - 22 do
    begin
      Pts[0] := Q(Side, A, U);
      Pts[1] := Q(Side, A, 0);
      Pts[2] := Q(Side, A + U, 0);
      Pts[3] := Q(Side, A + U, U * 0.78);
      Pts[4] := Q(Side, A + U * 0.28, U * 0.78);
      Pts[5] := Q(Side, A + U * 0.28, U * 0.3);
      Pts[6] := Q(Side, A + U * 0.68, U * 0.3);
      Pts[7] := Q(Side, A + U * 0.68, U * 0.55);
      Pts[8] := Q(Side, A + U * 0.5, U * 0.55);
      B.DrawPolyLineAntialias(Pts, Red, Max(1, S(1.3)), False);
      B.DrawLineAntialias(Pts[0].X, Pts[0].Y, Q(Side, A + U * 1.35, U).X, Q(Side, A + U * 1.35, U).Y, Red, Max(1, S(1.3)));
      A := A + U * 1.35;
    end;
  end;
  Corner(Out0 + 12, Out0 + 12);
  Corner(CW - Out0 - 12, Out0 + 12);
  Corner(Out0 + 12, CH - Out0 - 12);
  Corner(CW - Out0 - 12, CH - Out0 - 12);
  if not Knot then Exit;
  // a little knot under the title: a line, diamonds and a red tassel bead
  B.DrawLineAntialias(S(CW / 2 - 150), S(82), S(CW / 2 - 16), S(82), BGRA(178, 40, 34, 170), Max(1, S(1.2)));
  B.DrawLineAntialias(S(CW / 2 + 16), S(82), S(CW / 2 + 150), S(82), BGRA(178, 40, 34, 170), Max(1, S(1.2)));
  for I := -1 to 1 do
    B.FillPolyAntialias([PointF(S(CW / 2 + I * 150), S(76)), PointF(S(CW / 2 + I * 150 + 6), S(82)),
      PointF(S(CW / 2 + I * 150), S(88)), PointF(S(CW / 2 + I * 150 - 6), S(82))], Red);
  B.FillEllipseAntialias(S(CW / 2), S(82), S(4), S(4), Gold);
end;

{ the empty paper card (shadow, paper, red border) of a size, cached }
function TGameScene.BlankCard(CW, CH: Single; const Fr: TFrameStyle): TBGRABitmap;
var
  Key: string;
  I: Integer;
  B: TBGRABitmap;
begin
  Key := Format('c%dx%d|%d|%s%s%s|%d', [Round(CW), Round(CH), Ord(Fr.Kind), ColorHex(Fr.Color), ColorHex(Fr.Color2),
    ColorHex(Fr.Paper), FFxVersion]);
  I := FCache.IndexOf(Key);
  if I >= 0 then
    B := TBGRABitmap(FCache.Objects[I])
  else
  begin
    B := TBGRABitmap.Create(Max(1, Round(S(CW + 12))), Max(1, Round(S(CH + 14))));
    B.FillRoundRectAntialias(S(8), S(12), S(CW + 10), S(CH + 12), S(14), S(14), BGRA(0, 0, 0, 70));
    B.FillRoundRectAntialias(S(1), S(1), S(CW), S(CH), S(14), S(14), Fr.Paper);
    DrawFrameStatic(B, Fr, 0, 0, CW, CH, FScale, 82);
    B.LoadFromBitmapIfNeeded;
    FCache.AddObject(Key, B);
  end;
  Result := TBGRABitmap(B.Duplicate);
end;

{ after a resize (main thread, workers idle): every menu's items and cards are
  made in advance, so opening a menu later only puts cached pieces together }
procedure TGameScene.WarmCache;
var
  M, I, KeepMenu, KeepSel: Integer;
  KeepKey: string;
begin
  FCacheWarm := True;
  KeepMenu := FMenu;
  KeepSel := FSel;
  KeepKey := FCardKey;
  for M := msMain to msCredits do
  begin
    FMenu := M;
    FCardKey := '#';
    MakeCard;            // fills the cache with this menu's card size and items
    for I := 0 to FMenuN - 1 do
    begin
      FGlyphs.Prepare(FFx.Menus[MenuStyle].Item, FScale, MenuItem(I));
      FGlyphs.Prepare(FFx.Menus[MenuStyle].Sel, FScale, MenuItem(I));
    end;
  end;
  FMenu := KeepMenu;
  FSel := KeepSel;
  FCardKey := '#';
  MakeCard;
end;

{ every menu item as two small sprites (normal / selected); an item is only
  drawn again when its text changes (a settings value) }
procedure TGameScene.MakeItems;
var
  I: Integer;
  It: string;
begin
  if Length(FItemSpr) <> FMenuN then
  begin
    SetLength(FItemSpr, FMenuN);
    SetLength(FItemTxt, FMenuN);
    for I := 0 to FMenuN - 1 do
      FItemTxt[I] := #0;
  end;
  for I := 0 to FMenuN - 1 do
  begin
    It := MenuItem(I);
    if It = FItemTxt[I] then Continue;
    FItemTxt[I] := It;
    if FGlyphScale <> FScale then
    begin
      FGlyphs.Clear;
      FGlyphScale := FScale;
    end;
    FGlyphs.Prepare(FFx.Menus[MenuStyle].Item, FScale, It);
    FGlyphs.Prepare(FFx.Menus[MenuStyle].Sel, FScale, It);
  end;
end;

procedure TGameScene.Update(DT: Single);
var
  I: Integer;
  X, Y: Single;
begin
  // a season change still fades out under the pause card
  if FSnap <> nil then
  begin
    FSnapFade := FSnapFade - DT / 1.4;
    if FSnapFade <= 0 then FreeAndNil(FSnap);
  end;
  if FMenu in [msPause, msSaveItem] then Exit;  // the world stands still under the pause card
  FTime := FTime + DT;
  if FSeason = 1 then
  begin
    FFlashNext := FFlashNext - DT;
    if FFlashNext <= 0 then
    begin
      FFlashT := 0;
      FFlashNext := RandRange(8, 15);
      Snd(Ord(sfThunder), 0.8, 0.85 + 0.3 * Random);
      X := RandRange(FVisL + 120, FVisR - 120);
      Y := 20;
      SetLength(FBolt, 0);
      while Y < Base0 - 140 do
      begin
        SetLength(FBolt, Length(FBolt) + 1);
        FBolt[High(FBolt)] := PointF(X, Y);
        X := X + RandRange(-30, 30);
        Y := Y + RandRange(22, 42);
      end;
    end;
    FFlashT := FFlashT + DT;
    if FFlashT < 0.07 then FFlash := 1
    else if FFlashT < 0.13 then FFlash := 0.15
    else if FFlashT < 0.2 then FFlash := 0.85
    else FFlash := Max(0, 0.85 * (1 - (FFlashT - 0.2) / 0.4));
    FBoltOn := FFlashT < 0.3;
  end
  else
    FFlash := 0;
  if FTo <> FFrom then
  begin
    FBlend := FBlend + DT / Max(0.1, FadeSeconds);
    if FBlend >= 1 then
    begin
      FFrom := FTo;
      FBlend := 0;
    end;
  end;
  if FAuto then
  begin
    FAutoTimer := FAutoTimer + DT;
    if (FAutoTimer > AutoSeconds) and (FFrom = FTo) then
      SetMode((FTo + 1) mod 3);
  end;
  UpdateGame(DT);
  for I := 0 to High(FClouds) do
    with FClouds[I] do
    begin
      OX := OX - (FSpeed * 0.2 - Speed) * DT;
      if MaxX + OX < FVisL - 20 then OX := FVisR + 20 - MinX;
    end;
end;

procedure TGameScene.CopyStateFrom(Src: TGameScene);
var
  I: Integer;
begin
  FTime := Src.FTime;
  FFrom := Src.FFrom;
  FTo := Src.FTo;
  FBlend := Src.FBlend;
  FAuto := Src.FAuto;
  FAutoTimer := Src.FAutoTimer;
  AutoSeconds := Src.AutoSeconds;
  FadeSeconds := Src.FadeSeconds;
  FScroll := Src.FScroll;
  FState := Src.FState;
  if FState = gsOver then FState := gsTitle;
  FStateT := Src.FStateT;
  FY := Src.FY;
  FVY := Src.FVY;
  FTilt := Src.FTilt;
  FFlapT := Src.FFlapT;
  FInvuln := Src.FInvuln;
  FSpeed := Src.FSpeed;
  FDist := Src.FDist;
  FLives := Src.FLives;
  FScore := Src.FScore;
  FBest := Src.FBest;
  FLanternsGot := Src.FLanternsGot;
  FObs := Copy(Src.FObs);
  FLants := Copy(Src.FLants);
  FHawks := Copy(Src.FHawks);
  FBonus := Copy(Src.FBonus);
  FHaz := Copy(Src.FHaz);
  FSlowT := Src.FSlowT;
  FCharacter := Src.FCharacter;
  FFx.Assign(Src.FFx);
  Inc(FFxVersion);
  FParts := Copy(Src.FParts);
  FRng := Src.FRng;
  FAutoPilot := True;   // an export flies by itself
  FExportCopy := True;
  FMenu := Src.FMenu;
  if FMenu = msPause then FMenu := msNone;
  FSel := Src.FSel;
  FScores := Copy(Src.FScores);
  FDifficulty := Src.FDifficulty;
  FHudOn := Src.FHudOn;
  FHudKey := '#';   // matches no state: rebuild on the next Prepare
  FCardKey := '#';
  for I := 0 to Min(High(FClouds), High(Src.FClouds)) do
    FClouds[I].OX := Src.FClouds[I].OX;
  FFlash := Src.FFlash;
  FFlashT := Src.FFlashT;
  FFlashNext := Src.FFlashNext;
  FBolt := Copy(Src.FBolt);
  FBoltOn := Src.FBoltOn;
  if Src.FSeason <> FSeason then
  begin
    FSeason := Src.FSeason;
    MakePalettes;
    if FWidth > 1 then Resize(FWidth, FHeight);
  end;
end;

function TGameScene.SpriteCount: Integer;
begin
  Result := Length(FClouds) * 3;
end;

function TGameScene.SpriteBytes: Int64;
var
  I, M: Integer;
begin
  Result := 0;
  for I := 0 to High(FClouds) do
    for M := 0 to 2 do
      if FClouds[I].Sprite[M] <> nil then
        Inc(Result, Int64(FClouds[I].Sprite[M].NbPixels) * 4);
  if FHud <> nil then Inc(Result, Int64(FHud.NbPixels) * 4);
  if FCard <> nil then Inc(Result, Int64(FCard.NbPixels) * 4);
end;

function TGameScene.StaticBytes: Int64;
var
  M: Integer;

  procedure Add(B: TBGRABitmap);
  begin
    if B <> nil then Inc(Result, Int64(B.NbPixels) * 4);
  end;

begin
  Result := 0;
  for M := 0 to 2 do
  begin
    Add(FSky[M]); Add(FR0[M]); Add(FR1[M]); Add(FRiver[M]);
  end;
  Add(FCutter.FLayer); Add(FAcc);
end;

function TGameScene.DescribeParams: string;
var
  SL: TStringList;
  Id: TLayerId;
  M: Integer;

  function F(V: Single): string;
  begin
    Result := FormatFloat('0.##', V);
  end;

begin
  SL := TStringList.Create;
  try
    SL.Add('GAME');
    SL.Add(Format('  state %s, score %d, best %d, lives %d, lanterns %d, distance %s m',
      [StateNames[FState], FScore, FBest, FLives, FLanternsGot, F(FDist)]));
    SL.Add(Format('  speed %s design px/s (230 .. 440, +0.12 per m), crane y %s, vy %s, tilt %s',
      [F(FSpeed), F(FY), F(FVY), F(FTilt)]));
    SL.Add(Format('  menu %s (item %d of %d), difficulty %s, music %s, high scores %d',
      [MenuNames[FMenu], FSel + 1, FMenuN, DiffNames[FDifficulty], IfThen(FMusicChoice = 0, 'auto',
      TrackNames[Max(0, FMusicChoice - 1)]), Length(FScores)]));
    SL.Add(Format('  obstacles %d, lanterns %d, hawks %d, particles %d, autopilot %s',
      [Length(FObs), Length(FLants), Length(FHawks), Length(FParts), IfThen(FAutoPilot, 'on', 'off')]));
    SL.Add('  physics: gravity 1500, flap -440, max fall 620; gap 270 -> 180; spacing 440 -> 300');
    SL.Add('');
    SL.Add('DESIGN SPACE');
    SL.Add(Format('  %d x %d; ranges tile every %d px (parallax %s / %s), water y %d, crane x %d',
      [DesignW, DesignH, Period, F(Par0), F(Par1), WaterY, CraneX]));
    SL.Add(Format('  window %d x %d, scale %s, strip tile %d px, visible x %s .. %s',
      [FWidth, FHeight, FormatFloat('0.0000', FScale), FStripW, F(FVisL), F(FVisR)]));
    SL.Add('');
    SL.Add(Format('SEASON  %s  (1 summer, 2 rainy, 3 autumn, 4 winter)', [SeasonNames[FSeason]]));
    SL.Add('');
    SL.Add('TIME OF DAY');
    SL.Add(Format('  now: %s -> %s, blend %s, night %s, auto %s (%s s each)',
      [ModeNames[FFrom], ModeNames[FTo], F(FBlend), F(Night), IfThen(FAuto, 'on', 'off'), F(AutoSeconds)]));
    for M := 0 to 2 do
      SL.Add(Format('  %-8s lights %s, shade %s, mist %s', [ModeNames[M], F(ModeNight[M]),
        F(ModeShade[M]), F(FPal[M].MistK)]));
    SL.Add('');
    SL.Add('LAYERS (back to front)');
    for Id := Low(TLayerId) to High(TLayerId) do
      SL.Add(Format('  %-14s %-18s %s', [LayerNames[Id], LayerKinds[Id], LayerNotes[Id]]));
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
