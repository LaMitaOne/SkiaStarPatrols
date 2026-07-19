{*******************************************************************************
  Star Patrols (Side-Scroller Shooter Edition)
********************************************************************************
  A high-performance, thread-safe 2D space shooter engine built on Skia4Delphi.

  Author:  Lara Miriam Tamy Reschke
  License: MIT

  Key Features:
  - R-Type Style Physics: Constant auto-scroll camera. The ship has minimum
    forward thrust. Left brakes, Right boosts. Player cannot leave screen bounds.
  - Advanced Visuals: 3-Layer parallax starfields, massive glowing planets,
    and dynamic particle systems for explosions and engine trails.
  - Enemies: Asteroids (static drift), Sinus-wave Fighters, and Diving Interceptors.
  - Combat: Player shooting with collision detection and score system.
*******************************************************************************}

unit SkiaStarPatrols;

interface

uses
  System.SysUtils, System.Types, System.Classes, System.Math,
  System.Generics.Collections, System.UITypes, System.SyncObjs, FMX.Types,
  FMX.Controls, FMX.Forms, FMX.Skia, Winapi.MMSystem, System.Skia;

const
  // --- Engine Constants ---
  TILE_SIZE = 32;           // Pixel size of the grid tiles used for asteroids

  // --- Physics & Movement ---
  GRAVITY = 0.0;            // No gravity in space
  ACCEL = 50.0;             // How fast the ship accelerates when pressing Left/Right
  MAX_SPEED = 8.0;          // Maximum horizontal velocity (boosting right)
  MAX_SPEED_Y = 6.0;        // Maximum vertical velocity (up/down) - slightly slower for precision
  MIN_FORWARD_SPEED = 2.0;  // The constant auto-scroll speed of the camera/ship
  FRICTION = 0.88;          // Space drag (slows ship to 0 when no keys are pressed)
  BULLET_SPEED = 20.0;      // Velocity of player projectiles

type
  // --- Enums ---
  TGameState = (gsPlaying, gsDead, gsWin);
  TTileType = (ttEmpty, ttAsteroid);
  TAudioEffect = (afNone, afShoot, afExplosion, afCrate, afPortal, afWin, afDie);
  TEnemyKind = (ekAsteroid, ekFighter, ekDiver);

  // --- Records ---
  TTile = record
    TileType: TTileType;
    Solid: Boolean;
  end;

  TActor = record
    Pos: TPointF;
    Vel: TPointF;
    Width: Single;
    Height: Single;
  end;

  TParticle = record
    Pos: TPointF;
    Vel: TPointF;
    Life: Single;
    Color: TAlphaColor;
    Size: Single;
  end;

  TBullet = record
    Pos: TPointF;
    Vel: TPointF;
    Life: Single;
    IsPlayer: Boolean;
  end;

  TEnemy = record
    Pos: TPointF;
    Vel: TPointF;
    Width: Single;
    Height: Single;
    Phase: Single;       // Used for sinus-wave movement timing
    Kind: TEnemyKind;
    StartY: Single;      // Initial Y position for wave calculation
    HasDived: Boolean;   // AI state flag for Divers
  end;

  TGate = record
    Pos: TPointF;
    Width: Single;
    Height: Single;
    Phase: Single;
  end;

  // --- Main Game Class ---
  TStarPatrolsGame = class(TSkCustomControl)
  private
    { Threading & Timing }
    FThread: TThread;
    FActive: Boolean;
    FLock: TCriticalSection;

    { Input }
    FKeys: set of Byte;

    { Game State }
    FMenuActive: Boolean;
    FScore: Integer;
    FLevel: Integer;
    FGameState: TGameState;
    FDeadTime: Single;
    FWinTime: Single;
    FAnimPhase: Single;

    { Entities }
    FPlayer: TActor;
    FTiles: TArray<TTile>;
    FEnemies: TList<TEnemy>;
    FBullets: TList<TBullet>;
    FGate: TGate;
    FParticles: TList<TParticle>;

    { World & Camera }
    FMapCols: Integer;
    FMapRows: Integer;
    FCameraX: Single;

    { Parallax Backgrounds }
    FStarsFar: TArray<TPointF>;
    FStarsMid: TArray<TPointF>;
    FStarsNear: TArray<TPointF>;
    FPlanets: TArray<TPointF>;

    { Core Methods }
    procedure PlayEffect(Effect: TAudioEffect);
    procedure DoPhysicsUpdate(DeltaSec: Double);
    procedure UpdateCamera;
    procedure SafeInvalidate;
    procedure StartThread;
    procedure StopThread;

    { World Generation }
    procedure GenerateProceduralMap;
    procedure GenerateBackgroundElements;

    { Logic & Collision }
    procedure CheckEnemyCollisions;
    procedure CheckBulletCollisions;
    procedure CheckGateCollision;
    procedure UpdateEnemies(DeltaSec: Double);
    procedure UpdateBullets(DeltaSec: Double);
    procedure UpdateParticles(DeltaTime: Single);
    procedure SpawnExplosion(const X, Y: Single; Color: TAlphaColor);
    procedure FireBullet;

    { Rendering Routines }
    procedure DrawBackgrounds(const ACanvas: ISkCanvas; const ADest: TRectF);
    procedure DrawTileMap(const ACanvas: ISkCanvas);
    procedure DrawEnemies(const ACanvas: ISkCanvas);
    procedure DrawBullets(const ACanvas: ISkCanvas);
    procedure DrawGate(const ACanvas: ISkCanvas);
    procedure DrawParticles(const ACanvas: ISkCanvas);
    procedure DrawUI(const ACanvas: ISkCanvas);
    procedure DrawMenu(const ACanvas: ISkCanvas; const ADest: TRectF);
    procedure DrawStarship(const ACanvas: ISkCanvas; const Pos: TPointF; const VelY: Single);
  protected
    procedure Draw(const ACanvas: ISkCanvas; const ADest: TRectF; const AOpacity: Single); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
    procedure KeyUp(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
  end;

implementation

{ =============================================================================
  HELPER: TILE COLLISION CHECK
  Checks if a specific world coordinate is inside a solid tile (asteroid).
============================================================================= }
function IsSolidTile(const Tiles: TArray<TTile>; Cols, Rows: Integer; const AX, AY: Single): Boolean;
var
  Col, Row: Integer;
begin
  Col := Trunc(AX / TILE_SIZE);
  Row := Trunc(AY / TILE_SIZE);
  // If out of bounds, it's not solid (open space)
  if (Col < 0) or (Col >= Cols) or (Row < 0) or (Row >= Rows) then
    Exit(False);
  Result := Tiles[Row * Cols + Col].Solid;
end;

{ =============================================================================
  WORLD GENERATION
============================================================================= }
procedure TStarPatrolsGame.GenerateProceduralMap;
var
  C, R: Integer;
  Enemy: TEnemy;
  AsteroidCount: Integer;
begin
  // 1. Clear the map grid
  for R := 0 to FMapRows - 1 do
    for C := 0 to FMapCols - 1 do
    begin
      FTiles[R * FMapCols + C].TileType := ttEmpty;
      FTiles[R * FMapCols + C].Solid := False;
    end;

  // Clear entity lists and reset state
  FEnemies.Clear;
  FBullets.Clear;
  FGameState := gsPlaying;
  FDeadTime := 0;
  FWinTime := 0;

  // Reset camera position for the new level
  FCameraX := 0;

  // 2. Generate Asteroid Fields (Scale count with current level)
  AsteroidCount := 30 + FLevel * 5;
  while AsteroidCount > 0 do
  begin
    C := 20 + Random(FMapCols - 40);
    R := Random(FMapRows);
    FTiles[R * FMapCols + C].TileType := ttAsteroid;
    FTiles[R * FMapCols + C].Solid := True;
    Dec(AsteroidCount);
  end;

  // 3. Spawn Enemy Waves randomly across the map
  for C := 15 to FMapCols - 20 do
  begin
    if Random(10) = 0 then
    begin
      Enemy.Pos := PointF(C * TILE_SIZE, Random(FMapRows * TILE_SIZE));
      Enemy.Vel := PointF(-50 - Random(30), 0); // Move left towards player
      Enemy.Width := 32;
      Enemy.Height := 32;
      Enemy.Phase := Random(100);
      Enemy.HasDived := False;

      // Randomize enemy type
      case Random(3) of
        0: Enemy.Kind := ekAsteroid;
        1: begin
             Enemy.Kind := ekFighter;
             Enemy.StartY := Enemy.Pos.Y; // Store Y for sinus movement
           end;
        2: Enemy.Kind := ekDiver;
      end;
      FEnemies.Add(Enemy);
    end;
  end;

  // 4. Generate Level Exit (Warp Gate)
  FGate.Pos := PointF((FMapCols - 10) * TILE_SIZE, (FMapRows / 2) * TILE_SIZE - 48);
  FGate.Width := 64;
  FGate.Height := 96;
  FGate.Phase := 0;

  // 5. Spawn Player at center-left
  FPlayer.Pos := PointF(100, (FMapRows / 2) * TILE_SIZE);
  FPlayer.Vel := TPointF.Create(MIN_FORWARD_SPEED, 0); // Initial boost
end;

procedure TStarPatrolsGame.GenerateBackgroundElements;
var
  I: Integer;
begin
  // 3 Layers of stars for parallax depth
  SetLength(FStarsFar, 150);
  for I := 0 to High(FStarsFar) do
    FStarsFar[I] := PointF(Random(FMapCols * TILE_SIZE * 2), Random(800));

  SetLength(FStarsMid, 80);
  for I := 0 to High(FStarsMid) do
    FStarsMid[I] := PointF(Random(FMapCols * TILE_SIZE * 2), Random(800));

  SetLength(FStarsNear, 40);
  for I := 0 to High(FStarsNear) do
    FStarsNear[I] := PointF(Random(FMapCols * TILE_SIZE * 2), Random(800));

  // Generate massive planets spread evenly across the map
  SetLength(FPlanets, 5);
  for I := 0 to High(FPlanets) do
    FPlanets[I] := PointF(I * (FMapCols * TILE_SIZE div 4) + Random(500), Random(300) + 100);
end;

{ =============================================================================
  LOGIC & AI
============================================================================= }
procedure TStarPatrolsGame.UpdateCamera;
var
  ScreenWidth: Single;
begin
  if FDeadTime > 0 then Exit;
  ScreenWidth := Width;

  // R-TYPE AUTO-SCROLL: The camera constantly moves forward, pushing the player.
  // It ignores the player's X position entirely for scrolling forward.
  FCameraX := FCameraX + (MIN_FORWARD_SPEED * TILE_SIZE) * 0.016; // Approx 60FPS scroll speed

  // Hard stops for map boundaries
  if FCameraX < 0 then FCameraX := 0;
  if FCameraX > (FMapCols * TILE_SIZE) - ScreenWidth then
    FCameraX := (FMapCols * TILE_SIZE) - ScreenWidth;
end;

procedure TStarPatrolsGame.SpawnExplosion(const X, Y: Single; Color: TAlphaColor);
var
  I: Integer;
  P: TParticle;
begin
  // Generate 20 random particles bursting outward
  for I := 0 to 20 do
  begin
    P.Pos := PointF(X, Y);
    P.Vel := PointF((Random - 0.5) * 500, (Random - 0.5) * 500);
    P.Life := 0.8;
    P.Color := Color;
    P.Size := 4 + Random * 6;
    FParticles.Add(P);
  end;
end;

procedure TStarPatrolsGame.FireBullet;
var
  B: TBullet;
begin
  // Spawn bullet at the ship's nose
  B.Pos := PointF(FPlayer.Pos.X + FPlayer.Width, FPlayer.Pos.Y + FPlayer.Height / 2);
  B.Vel := PointF(BULLET_SPEED * TILE_SIZE, 0);
  B.Life := 2.0;
  B.IsPlayer := True;
  FBullets.Add(B);
  PlayEffect(afShoot);
end;

procedure TStarPatrolsGame.CheckBulletCollisions;
var
  I, J: Integer;
  B: TBullet;
  E: TEnemy;
  R1, R2: TRectF;
begin
  for I := FBullets.Count - 1 downto 0 do
  begin
    B := FBullets[I];
    R1 := TRectF.Create(B.Pos.X, B.Pos.Y, B.Pos.X + 12, B.Pos.Y + 4);

    // Check collision with solid map tiles (Asteroids)
    if IsSolidTile(FTiles, FMapCols, FMapRows, B.Pos.X, B.Pos.Y) then
    begin
      SpawnExplosion(B.Pos.X, B.Pos.Y, TAlphaColors.Orange);
      FBullets.Delete(I);
      Continue;
    end;

    // Check collision with enemy ships
    for J := FEnemies.Count - 1 downto 0 do
    begin
      E := FEnemies[J];
      R2 := TRectF.Create(E.Pos.X, E.Pos.Y, E.Pos.X + E.Width, E.Pos.Y + E.Height);
      if R1.IntersectsWith(R2) then
      begin
        SpawnExplosion(E.Pos.X + E.Width/2, E.Pos.Y + E.Height/2, TAlphaColors.Yellow);
        FEnemies.Delete(J);
        FBullets.Delete(I);
        Inc(FScore);
        PlayEffect(afExplosion);
        Break;
      end;
    end;
  end;
end;

procedure TStarPatrolsGame.CheckGateCollision;
var
  R, R2: TRectF;
begin
  if FGameState <> gsPlaying then Exit;
  R := TRectF.Create(FPlayer.Pos.X, FPlayer.Pos.Y, FPlayer.Pos.X + FPlayer.Width, FPlayer.Pos.Y + FPlayer.Height);
  R2 := TRectF.Create(FGate.Pos.X, FGate.Pos.Y, FGate.Pos.X + FGate.Width, FGate.Pos.Y + FGate.Height);
  if R.IntersectsWith(R2) then
  begin
    FGameState := gsWin;
    FWinTime := 2.0;
    SpawnExplosion(FGate.Pos.X + FGate.Width / 2, FGate.Pos.Y + FGate.Height / 2, TAlphaColors.Cyan);
    PlayEffect(afPortal);
  end;
end;

procedure TStarPatrolsGame.CheckEnemyCollisions;
var
  I: Integer;
  E: TEnemy;
  R, R2: TRectF;
begin
  if FGameState <> gsPlaying then Exit;
  R := TRectF.Create(FPlayer.Pos.X, FPlayer.Pos.Y, FPlayer.Pos.X + FPlayer.Width, FPlayer.Pos.Y + FPlayer.Height);

  // Check collision with map tiles
  if IsSolidTile(FTiles, FMapCols, FMapRows, FPlayer.Pos.X + FPlayer.Width/2, FPlayer.Pos.Y + FPlayer.Height/2) then
  begin
    SpawnExplosion(FPlayer.Pos.X + FPlayer.Width/2, FPlayer.Pos.Y + FPlayer.Height/2, TAlphaColors.Red);
    FGameState := gsDead;
    FDeadTime := 1.5;
    FPlayer.Pos.X := -1000; // Hide player off-screen
    FScore := 0;
    PlayEffect(afDie);
    Exit;
  end;

  // Check collision with enemy ships
  for I := FEnemies.Count - 1 downto 0 do
  begin
    E := FEnemies[I];
    R2 := TRectF.Create(E.Pos.X, E.Pos.Y, E.Pos.X + E.Width, E.Pos.Y + E.Height);
    if R.IntersectsWith(R2) then
    begin
      SpawnExplosion((R.Left + R.Right) / 2, (R.Top + R.Bottom) / 2, TAlphaColors.Red);
      FEnemies.Delete(I);
      FGameState := gsDead;
      FDeadTime := 1.5;
      FPlayer.Pos.X := -1000;
      FScore := 0;
      PlayEffect(afDie);
      Exit;
    end;
  end;
end;

procedure TStarPatrolsGame.UpdateEnemies(DeltaSec: Double);
var
  I: Integer;
  E: TEnemy;
begin
  for I := FEnemies.Count - 1 downto 0 do
  begin
    E := FEnemies[I];
    E.Phase := E.Phase + DeltaSec * 3;

    case E.Kind of
      ekAsteroid:
        // Move straight left
        E.Pos := E.Pos + TPointF.Create(E.Vel.X * DeltaSec, 0);

      ekFighter:
        begin
          // Move left, but bob up and down in a sinus wave
          E.Pos.X := E.Pos.X + E.Vel.X * DeltaSec;
          E.Pos.Y := E.StartY + Sin(E.Phase * 2) * 60;
        end;

      ekDiver:
        begin
          E.Pos.X := E.Pos.X + E.Vel.X * DeltaSec;
          // AI: If player is within 400px, calculate a Y-velocity towards the player and dive
          if not E.HasDived then
          begin
            if E.Pos.X < FPlayer.Pos.X + 400 then
            begin
              E.Vel.Y := (FPlayer.Pos.Y - E.Pos.Y) * 0.5;
              E.HasDived := True;
            end;
          end
          else
            E.Pos.Y := E.Pos.Y + E.Vel.Y * DeltaSec; // Continue diving trajectory
        end;
    end;

    // Despawn if off screen left
    if E.Pos.X < FCameraX - 100 then
    begin
      FEnemies.Delete(I);
      Continue;
    end;
    FEnemies[I] := E;
  end;
end;

procedure TStarPatrolsGame.UpdateBullets(DeltaSec: Double);
var
  I: Integer;
  B: TBullet;
begin
  for I := FBullets.Count - 1 downto 0 do
  begin
    B := FBullets[I];
    B.Pos := B.Pos + TPointF.Create(B.Vel.X * DeltaSec, B.Vel.Y * DeltaSec);
    B.Life := B.Life - DeltaSec;
    // Despawn if expired or off screen right
    if (B.Life <= 0) or (B.Pos.X > FCameraX + Width + 100) then
      FBullets.Delete(I)
    else
      FBullets[I] := B;
  end;
end;

procedure TStarPatrolsGame.UpdateParticles(DeltaTime: Single);
var
  I: Integer;
  P: TParticle;
  ThrustPos: TPointF;
begin
  ThrustPos := PointF(FPlayer.Pos.X, FPlayer.Pos.Y + FPlayer.Height / 2);

  // Spawn engine trail particles if playing
  if FGameState = gsPlaying then
  begin
    for I := 0 to 3 do
    begin
      P.Pos := ThrustPos + PointF(Random(4), (Random - 0.5) * 10);
      P.Vel := PointF(-200 - Random(100), (Random - 0.5) * 40);
      P.Life := 0.3 + Random * 0.2;
      // Randomize between Cyan and Orange flames
      if Random(2) = 0 then
        P.Color := $FF00FFFF
      else
        P.Color := $FFFF8800;
      P.Size := 6 + Random * 4;
      FParticles.Add(P);
    end;
  end;

  // Update existing particles
  for I := FParticles.Count - 1 downto 0 do
  begin
    P := FParticles[I];
    P.Pos.X := P.Pos.X + P.Vel.X * DeltaTime;
    P.Pos.Y := P.Pos.Y + P.Vel.Y * DeltaTime;
    P.Life := P.Life - (0.8 * DeltaTime);
    if P.Life <= 0 then
      FParticles.Delete(I)
    else
      FParticles[I] := P;
  end;
end;

{ =============================================================================
  PHYSICS & INPUT UPDATE LOOP
============================================================================= }
procedure TStarPatrolsGame.DoPhysicsUpdate(DeltaSec: Double);
var
  Left, Right, Up, Down, Shoot: Boolean;
  AccelThisFrame: Single;
begin
  if not FActive then Exit;
  if FMenuActive then Exit;

  // --- WIN STATE ---
  if FGameState = gsWin then
  begin
    FWinTime := FWinTime - DeltaSec;
    UpdateParticles(DeltaSec);
    FGate.Phase := FGate.Phase + DeltaSec * 20;
    if FWinTime <= 0 then
    begin
      Inc(FLevel);
      GenerateProceduralMap;
    end;
    Exit;
  end;

  // --- DEAD STATE ---
  if FGameState = gsDead then
  begin
    FDeadTime := FDeadTime - DeltaSec;
    UpdateParticles(DeltaSec);
    if FDeadTime <= 0 then
    begin
      FGameState := gsPlaying;
      FPlayer.Pos := PointF(100, (FMapRows / 2) * TILE_SIZE);
      FPlayer.Vel := TPointF.Create(MIN_FORWARD_SPEED, 0);
    end;
    Exit;
  end;

  // --- INPUT READING (Thread-Safe) ---
  FLock.Acquire;
  try
    Left := Byte(vkLeft) in FKeys;
    Right := Byte(vkRight) in FKeys;
    Up := Byte(vkUp) in FKeys;
    Down := Byte(vkDown) in FKeys;
    Shoot := Byte(vkSpace) in FKeys;
  finally
    FLock.Release;
  end;

  AccelThisFrame := ACCEL * DeltaSec;

  // --- R-TYPE STYLE MOVEMENT ---
  if Left then
    FPlayer.Vel.X := FPlayer.Vel.X - AccelThisFrame // Brake down to 0
  else if Right then
    FPlayer.Vel.X := FPlayer.Vel.X + AccelThisFrame // Boost forward
  else
    FPlayer.Vel.X := FPlayer.Vel.X * FRICTION;      // Natural drag to 0

  // Y Movement (Up/Down) with slightly reduced max speed for precision
  if Up then
    FPlayer.Vel.Y := Max(FPlayer.Vel.Y - AccelThisFrame, -MAX_SPEED_Y)
  else if Down then
    FPlayer.Vel.Y := Min(FPlayer.Vel.Y + AccelThisFrame, MAX_SPEED_Y)
  else
    FPlayer.Vel.Y := FPlayer.Vel.Y * FRICTION;

  // Apply Velocity to Position
  FPlayer.Pos.X := FPlayer.Pos.X + FPlayer.Vel.X * TILE_SIZE * DeltaSec;
  FPlayer.Pos.Y := FPlayer.Pos.Y + FPlayer.Vel.Y * TILE_SIZE * DeltaSec;

  // Screen Bounds Y (Top and Bottom)
  if FPlayer.Pos.Y < 0 then
  begin
    FPlayer.Pos.Y := 0;
    FPlayer.Vel.Y := 0;
  end;
  if FPlayer.Pos.Y > Height - FPlayer.Height then
  begin
    FPlayer.Pos.Y := Height - FPlayer.Height;
    FPlayer.Vel.Y := 0;
  end;

  // Screen Bounds X.
  // Player can move backward, but NOT outside the camera's left edge.
  if FPlayer.Pos.X < FCameraX then
  begin
    FPlayer.Pos.X := FCameraX;
    if FPlayer.Vel.X < 0 then FPlayer.Vel.X := 0;
  end;
  // Hard stop at right edge of the screen
  if FPlayer.Pos.X > FCameraX + Width - FPlayer.Width then
  begin
    FPlayer.Pos.X := FCameraX + Width - FPlayer.Width;
    if FPlayer.Vel.X > 0 then FPlayer.Vel.X := 0;
  end;

  // --- SHOOTING ---
  if Shoot and (FGameState = gsPlaying) then
    FireBullet;

  // --- UPDATE WORLD ---
  UpdateBullets(DeltaSec);
  CheckBulletCollisions;
  CheckEnemyCollisions;
  CheckGateCollision;
  UpdateEnemies(DeltaSec);
  UpdateParticles(DeltaSec);
  UpdateCamera;
end;

{ =============================================================================
  RENDERING ROUTINES
============================================================================= }
procedure TStarPatrolsGame.DrawUI(const ACanvas: ISkCanvas);
var
  Font: TSkFont;
  Paint: ISkPaint;
  Txt: string;
begin
  Txt := 'Score: ' + IntToStr(FScore) + ' | Sector: ' + IntToStr(FLevel);
  Font := TSkFont.Create;
  try
    Paint := TSkPaint.Create;
    Paint.Style := TSkPaintStyle.Fill;
    Paint.AntiAlias := True;

    // Draw shadow
    Paint.Color := TAlphaColors.Black;
    Paint.Alpha := 150;
    ACanvas.DrawSimpleText(Txt, 12, 42, Font, Paint);

    // Draw text
    Paint.Color := TAlphaColors.Cyan;
    Paint.Alpha := 255;
    ACanvas.DrawSimpleText(Txt, 10, 40, Font, Paint);
  finally
    Font.Free;
  end;
end;

procedure TStarPatrolsGame.DrawBackgrounds(const ACanvas: ISkCanvas; const ADest: TRectF);
var
  Paint: ISkPaint;
  Colors: TArray<TAlphaColor>;
  I: Integer;
  StarX, StarY: Single;
begin
  // Deep Space Gradient
  Colors := [$FF050510, $FF0f0c29, $FF000000];
  Paint := TSkPaint.Create;
  Paint.Shader := TSkShader.MakeGradientLinear(PointF(0, 0), PointF(0, ADest.Height), Colors, nil, TSkTileMode.Clamp);
  ACanvas.DrawPaint(Paint);
  Paint.Shader := nil;

  Paint.AntiAlias := True;
  Paint.Style := TSkPaintStyle.Fill;

  // Massive Distant Planets (Slowest Parallax)
  Paint.MaskFilter := TSkMaskFilter.MakeBlur(TSkBlurStyle.Normal, 8.0);
  for I := 0 to High(FPlanets) do
  begin
    StarX := FPlanets[I].X - FCameraX * 0.05;
    StarY := FPlanets[I].Y;
    if (StarX < -400) or (StarX > Width + 400) then Continue;

    case I mod 3 of
      0: begin // Mars-like
           Paint.Color := $FFcc4400;
           ACanvas.DrawCircle(PointF(StarX, StarY), 200, Paint);
           Paint.Color := $FF882200;
           ACanvas.DrawCircle(PointF(StarX - 40, StarY - 30), 150, Paint);
         end;
      1: begin // Neptune-like
           Paint.Color := $FF0044aa;
           ACanvas.DrawCircle(PointF(StarX, StarY), 250, Paint);
           Paint.Color := $FF0022aa;
           ACanvas.DrawCircle(PointF(StarX - 50, StarY - 40), 180, Paint);
         end;
      2: begin // Alien World
           Paint.Color := $FF44ddaa;
           ACanvas.DrawCircle(PointF(StarX, StarY), 180, Paint);
           Paint.Color := $FF22aa88;
           ACanvas.DrawCircle(PointF(StarX - 30, StarY - 20), 120, Paint);
         end;
    end;
  end;
  Paint.MaskFilter := nil;

  // Far Stars (10% scroll speed)
  for I := 0 to High(FStarsFar) do
  begin
    StarX := FStarsFar[I].X - FCameraX * 0.1;
    StarY := FStarsFar[I].Y;
    if StarX < -10 then StarX := StarX + (FMapCols * TILE_SIZE);
    if StarX > Width + 10 then Continue;
    Paint.Color := $FF555566;
    ACanvas.DrawCircle(PointF(StarX, StarY), 1.0, Paint);
  end;

  // Mid Stars (30% scroll speed)
  for I := 0 to High(FStarsMid) do
  begin
    StarX := FStarsMid[I].X - FCameraX * 0.3;
    StarY := FStarsMid[I].Y;
    if StarX < -10 then StarX := StarX + (FMapCols * TILE_SIZE);
    if StarX > Width + 10 then Continue;
    Paint.Color := $FFAAAAAA;
    ACanvas.DrawCircle(PointF(StarX, StarY), 1.5, Paint);
  end;

  // Near Stars (60% scroll speed)
  for I := 0 to High(FStarsNear) do
  begin
    StarX := FStarsNear[I].X - FCameraX * 0.6;
    StarY := FStarsNear[I].Y;
    if StarX < -10 then StarX := StarX + (FMapCols * TILE_SIZE);
    if StarX > Width + 10 then Continue;
    Paint.Color := $FFFFFFFF;
    ACanvas.DrawCircle(PointF(StarX, StarY), 2.5, Paint);
  end;
end;

procedure TStarPatrolsGame.DrawTileMap(const ACanvas: ISkCanvas);
var
  Paint, GlowPaint: ISkPaint;
  TileRect: TRectF;
  C, R: Integer;
begin
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;

  // Glow paint for neon outline
  GlowPaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  GlowPaint.StrokeWidth := 2.0;
  GlowPaint.AntiAlias := True;
  GlowPaint.MaskFilter := TSkMaskFilter.MakeBlur(TSkBlurStyle.Solid, 4.0);

  // Iterate through grid and draw solid tiles
  for R := 0 to FMapRows - 1 do
    for C := 0 to FMapCols - 1 do
    begin
      if FTiles[R * FMapCols + C].Solid then
      begin
        TileRect := TRectF.Create(C * TILE_SIZE, R * TILE_SIZE, (C + 1) * TILE_SIZE, (R + 1) * TILE_SIZE);
        // Cull off-screen tiles for performance
        if (TileRect.Right < FCameraX - 50) or (TileRect.Left > FCameraX + Width + 50) then Continue;

        Paint.Color := $FF4a4a5e;
        ACanvas.DrawRoundRect(TileRect, 8, 8, Paint);
        GlowPaint.Color := $FF888899;
        ACanvas.DrawRoundRect(TileRect, 8, 8, GlowPaint);
      end;
    end;
end;

procedure TStarPatrolsGame.DrawGate(const ACanvas: ISkCanvas);
var
  Paint: ISkPaint;
  Center: TPointF;
  PhaseOffset: Single;
begin
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;
  Center := PointF(FGate.Pos.X + FGate.Width / 2, FGate.Pos.Y + FGate.Height / 2);
  Paint.Style := TSkPaintStyle.Fill;
  Paint.MaskFilter := TSkMaskFilter.MakeBlur(TSkBlurStyle.Solid, 25.0);

  // Pulsating color effect
  if Sin(FGate.Phase * 2) > 0 then
    Paint.Color := $FF00FFFF
  else
    Paint.Color := $FFFF00FF;

  Paint.Alpha := 180;
  PhaseOffset := Sin(FGate.Phase) * 0.2;

  // Draw pulsing oval
  ACanvas.Save;
  ACanvas.Translate(Center.X, Center.Y);
  ACanvas.Scale(1.0 + PhaseOffset, 1.0 - PhaseOffset);
  ACanvas.DrawOval(TRectF.Create(-45, -70, 45, 70), Paint);
  ACanvas.Restore;
end;

procedure TStarPatrolsGame.DrawMenu(const ACanvas: ISkCanvas; const ADest: TRectF);
var
  Paint: ISkPaint;
  Font: TSkFont;
  Rect: TRectF;
  CenterX, CenterY: Single;
begin
  // Dim background
  Paint := TSkPaint.Create;
  Paint.Color := $AA000000;
  ACanvas.DrawPaint(Paint);

  CenterX := ADest.Width / 2;
  CenterY := ADest.Height / 2;
  Rect := TRectF.Create(CenterX - 150, CenterY - 100, CenterX + 150, CenterY + 100);

  // Dialog box
  Paint.Color := $FF1a1a2e;
  Paint.AntiAlias := True;
  ACanvas.DrawRoundRect(Rect, 20, 20, Paint);
  Paint.Style := TSkPaintStyle.Stroke;
  Paint.StrokeWidth := 3;
  Paint.Color := $FF00ffff;
  ACanvas.DrawRoundRect(Rect, 20, 20, Paint);

  // Menu Text
  Font := TSkFont.Create;
  try
    Paint := TSkPaint.Create(TSkPaintStyle.Fill);
    Paint.AntiAlias := True;
    Paint.Color := TAlphaColors.White;
    ACanvas.DrawSimpleText('STAR PATROL', CenterX - 70, CenterY - 50, Font, Paint);
    Paint.Color := TAlphaColors.Yellow;
    ACanvas.DrawSimpleText('ESC - Resume', CenterX - 65, CenterY + 10, Font, Paint);
    ACanvas.DrawSimpleText('R - Restart Sector', CenterX - 80, CenterY + 40, Font, Paint);
  finally
    Font.Free;
  end;
end;

procedure TStarPatrolsGame.DrawEnemies(const ACanvas: ISkCanvas);
var
  E: TEnemy;
  Paint, GlowPaint: ISkPaint;
  Center: TPointF;
  PB: ISkPathBuilder;
begin
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;

  GlowPaint := TSkPaint.Create(Paint);
  GlowPaint.MaskFilter := TSkMaskFilter.MakeBlur(TSkBlurStyle.Solid, 6.0);

  for E in FEnemies do
  begin
    Center := PointF(E.Pos.X + E.Width / 2, E.Pos.Y + E.Height / 2);
    // Cull off-screen
    if (E.Pos.X < FCameraX - 100) or (E.Pos.X > FCameraX + Width + 100) then Continue;

    case E.Kind of
      ekAsteroid:
        begin
          Paint.Color := $FF555555;
          GlowPaint.Color := $FF999999;
          ACanvas.DrawCircle(Center, E.Width / 2, GlowPaint);
          ACanvas.DrawCircle(Center, E.Width / 2 - 2, Paint);
          // Draw craters for detail
          Paint.Color := $FF333333;
          Paint.Style := TSkPaintStyle.Fill;
          ACanvas.DrawCircle(PointF(Center.X-5, Center.Y-5), 3, Paint);
          ACanvas.DrawCircle(PointF(Center.X+8, Center.Y+2), 4, Paint);
          ACanvas.DrawCircle(PointF(Center.X-2, Center.Y+8), 2, Paint);
        end;

      ekFighter:
        begin
          Paint.Color := $FF880000;
          GlowPaint.Color := $FFFF0000;
          // Draw angular ship body
          PB := TSkPathBuilder.Create;
          PB.MoveTo(E.Pos.X, Center.Y);
          PB.LineTo(E.Pos.X + E.Width * 0.8, E.Pos.Y);
          PB.LineTo(E.Pos.X + E.Width, E.Pos.Y);
          PB.LineTo(E.Pos.X + E.Width * 0.4, Center.Y);
          PB.LineTo(E.Pos.X + E.Width, E.Pos.Y + E.Height);
          PB.LineTo(E.Pos.X + E.Width * 0.8, E.Pos.Y + E.Height);
          PB.LineTo(E.Pos.X, Center.Y);
          ACanvas.DrawPath(PB.Snapshot, GlowPaint);
          ACanvas.DrawPath(PB.Snapshot, Paint);

          // Engine glow at the back
          Paint.Color := $FFFF8800;
          ACanvas.DrawCircle(PointF(E.Pos.X + E.Width - 2, Center.Y), 3, Paint);
        end;

      ekDiver:
        begin
          Paint.Color := $FF005500;
          GlowPaint.Color := $FF00FF00;
          // Draw sleek interceptor body
          PB := TSkPathBuilder.Create;
          PB.MoveTo(E.Pos.X + E.Width, Center.Y);
          PB.LineTo(E.Pos.X, E.Pos.Y);
          PB.LineTo(E.Pos.X + E.Width * 0.4, Center.Y);
          PB.LineTo(E.Pos.X, E.Pos.Y + E.Height);
          PB.LineTo(E.Pos.X + E.Width, Center.Y);
          ACanvas.DrawPath(PB.Snapshot, GlowPaint);
          ACanvas.DrawPath(PB.Snapshot, Paint);

          // Cockpit
          Paint.Color := $FFAAFFAA;
          ACanvas.DrawCircle(PointF(Center.X + 4, Center.Y), 3, Paint);
        end;
    end;
  end;
end;

procedure TStarPatrolsGame.DrawBullets(const ACanvas: ISkCanvas);
var
  B: TBullet;
  Paint: ISkPaint;
begin
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  // Heavy blur and alpha for neon plasma effect
  Paint.MaskFilter := TSkMaskFilter.MakeBlur(TSkBlurStyle.Solid, 15.0);
  Paint.Alpha := 180;

  for B in FBullets do
  begin
    // Outer red glow
    Paint.Color := $FFFF0000;
    ACanvas.DrawRect(TRectF.Create(B.Pos.X, B.Pos.Y, B.Pos.X + 15, B.Pos.Y + 6), Paint);

    // Inner bright yellow core
    Paint.Color := $FFFFFF00;
    Paint.Alpha := 220;
    ACanvas.DrawRect(TRectF.Create(B.Pos.X, B.Pos.Y + 1, B.Pos.X + 8, B.Pos.Y + 5), Paint);

    Paint.Alpha := 180; // Reset for next bullet
  end;
end;

procedure TStarPatrolsGame.DrawParticles(const ACanvas: ISkCanvas);
var
  P: TParticle;
  Paint: ISkPaint;
  AlphaVal: Integer;
begin
  if FParticles.Count = 0 then Exit;
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  Paint.MaskFilter := TSkMaskFilter.MakeBlur(TSkBlurStyle.Solid, 3.0);

  for P in FParticles do
  begin
    Paint.Color := P.Color;
    AlphaVal := Round(P.Life * 180);
    if AlphaVal > 255 then AlphaVal := 255;
    if AlphaVal < 0 then AlphaVal := 0;
    Paint.Alpha := AlphaVal;
    // Shrink particle as life decreases
    ACanvas.DrawCircle(P.Pos, P.Size * P.Life, Paint);
  end;
end;

procedure TStarPatrolsGame.DrawStarship(const ACanvas: ISkCanvas; const Pos: TPointF; const VelY: Single);
var
  Paint, GlowPaint: ISkPaint;
  PB: ISkPathBuilder;
  BankAngle: Single;
  Center: TPointF;
begin
  Paint := TSkPaint.Create;
  Paint.Style := TSkPaintStyle.Fill;
  Paint.AntiAlias := True;
  Paint.Color := $FFcccccc;

  GlowPaint := TSkPaint.Create(Paint);
  GlowPaint.MaskFilter := TSkMaskFilter.MakeBlur(TSkBlurStyle.Solid, 6.0);
  GlowPaint.Color := $FF00ffff;

  Center := PointF(Pos.X + FPlayer.Width / 2, Pos.Y + FPlayer.Height / 2);

  // Calculate banking angle based on vertical velocity for visual feedback
  BankAngle := VelY * 5.0;

  ACanvas.Save;
  ACanvas.Translate(Center.X, Center.Y);
  ACanvas.Rotate(BankAngle);

  // Draw angular wings
  PB := TSkPathBuilder.Create;
  PB.MoveTo(-10, 0);
  PB.LineTo(15, -20);
  PB.LineTo(5, -5);
  PB.LineTo(15, 20);
  PB.LineTo(-10, 0);
  ACanvas.DrawPath(PB.Snapshot, GlowPaint);
  ACanvas.DrawPath(PB.Snapshot, Paint);

  // Draw round main body
  Paint.Color := $FFeeeeee;
  ACanvas.DrawOval(TRectF.Create(-15, -8, 10, 8), GlowPaint);
  ACanvas.DrawOval(TRectF.Create(-15, -8, 10, 8), Paint);

  // Draw cockpit
  Paint.Color := $FF0088ff;
  ACanvas.DrawCircle(PointF(-2, 0), 4, Paint);
  Paint.Color := $FF00ffff;
  ACanvas.DrawCircle(PointF(-2, 0), 2, Paint);

  ACanvas.Restore;
end;

procedure TStarPatrolsGame.Draw(const ACanvas: ISkCanvas; const ADest: TRectF; const AOpacity: Single);
begin
  // Draw fixed background (not affected by camera translate)
  DrawBackgrounds(ACanvas, ADest);

  // Apply camera translation
  ACanvas.Save;
  ACanvas.Translate(-FCameraX, 0);
  FLock.Acquire;
  try
    DrawTileMap(ACanvas);
    DrawGate(ACanvas);
    DrawEnemies(ACanvas);
    DrawBullets(ACanvas);
    DrawParticles(ACanvas);

    if FGameState = gsPlaying then
    begin
      FAnimPhase := FAnimPhase + 0.1;
      DrawStarship(ACanvas, FPlayer.Pos, FPlayer.Vel.Y);
    end;

    FGate.Phase := FGate.Phase + 0.05;
  finally
    FLock.Release;
    ACanvas.Restore;
  end;

  // Draw UI on top (fixed to screen)
  DrawUI(ACanvas);
  if FMenuActive then
    DrawMenu(ACanvas, ADest);
end;

{ =============================================================================
  LIFECYCLE & THREADING
============================================================================= }
procedure TStarPatrolsGame.SafeInvalidate;
begin
  if csDestroying in ComponentState then Exit;
  TThread.Queue(nil,
    procedure
    begin
      if not (csDestroying in ComponentState) and Assigned(Self) then
      begin
        Redraw;
        Repaint;
      end;
    end);
end;

procedure TStarPatrolsGame.StartThread;
begin
  if Assigned(FThread) then Exit;
  // Run game loop in anonymous thread to keep UI responsive
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      LastTime, NowTime, DeltaMS: Cardinal;
    begin
      LastTime := TThread.GetTickCount;
      while not TThread.CheckTerminated do
      begin
        NowTime := TThread.GetTickCount;
        DeltaMS := NowTime - LastTime;
        if DeltaMS = 0 then DeltaMS := 1;
        LastTime := NowTime;
        if FActive then
        begin
          DoPhysicsUpdate(DeltaMS / 1000);
          SafeInvalidate;
        end;
        Sleep(12); // ~60-80 FPS cap to save CPU
      end;
    end);
  FThread.FreeOnTerminate := True;
  FThread.Start;
end;

procedure TStarPatrolsGame.StopThread;
begin
  FActive := False;
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    Sleep(50);
  end;
end;

constructor TStarPatrolsGame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLock := TCriticalSection.Create;
  Align := TAlignLayout.Client;
  HitTest := True;
  CanFocus := True;
  TabStop := True;

  FActive := True;
  FLevel := 1;
  FGameState := gsPlaying;
  FMapCols := 200;
  FMapRows := 18;
  FCameraX := 0;

  FParticles := TList<TParticle>.Create;
  FEnemies := TList<TEnemy>.Create;
  FBullets := TList<TBullet>.Create;
  SetLength(FTiles, FMapCols * FMapRows);

  FPlayer.Width := 30;
  FPlayer.Height := 30;

  GenerateBackgroundElements;
  GenerateProceduralMap;
  StartThread;
end;

destructor TStarPatrolsGame.Destroy;
begin
  StopThread;
  FreeAndNil(FLock);
  FreeAndNil(FParticles);
  FreeAndNil(FEnemies);
  FreeAndNil(FBullets);
  inherited;
end;

{ =============================================================================
  AUDIO
============================================================================= }
procedure TStarPatrolsGame.PlayEffect(Effect: TAudioEffect);
var
  FileName, BasePath: string;
  Flags: Cardinal;
begin
  if Effect = afNone then Exit;
  BasePath := ExtractFilePath(ParamStr(0));

  // Map enum to filename
  case Effect of
    afShoot:      FileName := 'Game Design Sound Effects - Pavs Music\05 - Equip.wav';
    afExplosion:  FileName := 'Game Design Sound Effects - Pavs Music\47 - Crunch.wav';
    afPortal:     FileName := 'Game Design Sound Effects - Pavs Music\12 - TingaLing.wav';
    afDie:        FileName := 'Game Design Sound Effects - Pavs Music\03 - Crush.wav';
  else
    FileName := '';
  end;

  if FileName = '' then Exit;
  FileName := BasePath + FileName;
  if not FileExists(FileName) then Exit;

  // Play asynchronously without stopping the game
  Flags := SND_ASYNC or SND_FILENAME or SND_NODEFAULT;
  PlaySound(PChar(FileName), 0, Flags);
end;

{ =============================================================================
  INPUT HANDLING
============================================================================= }
procedure TStarPatrolsGame.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
var
  GameKey: Byte;
begin
  // Toggle Menu
  if (Key = vkEscape) or (KeyChar = 'M') or (KeyChar = 'm') then
  begin
    FMenuActive := not FMenuActive;
    Key := 0; KeyChar := #0; Redraw; Repaint; Exit;
  end;

  // Menu Inputs
  if FMenuActive then
  begin
    if (KeyChar = 'R') or (KeyChar = 'r') then
    begin
      FLevel := 1;
      GenerateProceduralMap;
      FMenuActive := False; Key := 0; KeyChar := #0; Redraw; Repaint;
    end;
    Exit;
  end;

  // Map standard arrow keys and WASD to internal GameKey set
  GameKey := 0;
  case Key of
    $25: GameKey := $25; // vkLeft
    $27: GameKey := $27; // vkRight
    $26: GameKey := $26; // vkUp
    $28: GameKey := $28; // vkDown
    $20: GameKey := $20; // vkSpace
  end;

  if GameKey = 0 then
  begin
    case KeyChar of
      'A', 'a': GameKey := $25;
      'D', 'd': GameKey := $27;
      'W', 'w': GameKey := $26;
      'S', 's': GameKey := $28;
      ' ':      GameKey := $20;
    end;
  end;

  if GameKey > 0 then
  begin
    FLock.Acquire;
    try Include(FKeys, GameKey); finally FLock.Release; end;
    Key := 0; KeyChar := #0;
  end;
  inherited;
end;

procedure TStarPatrolsGame.KeyUp(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
var
  GameKey: Byte;
begin
  if FMenuActive then Exit;

  GameKey := 0;
  case Key of
    $25: GameKey := $25;
    $27: GameKey := $27;
    $26: GameKey := $26;
    $28: GameKey := $28;
    $20: GameKey := $20;
  end;

  if GameKey = 0 then
  begin
    case KeyChar of
      'A', 'a': GameKey := $25;
      'D', 'd': GameKey := $27;
      'W', 'w': GameKey := $26;
      'S', 's': GameKey := $28;
      ' ':      GameKey := $20;
    end;
  end;

  if GameKey > 0 then
  begin
    FLock.Acquire;
    try Exclude(FKeys, GameKey); finally FLock.Release; end;
    Key := 0; KeyChar := #0;
  end;
  inherited;
end;

end.
