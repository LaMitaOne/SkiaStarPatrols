# SkiaStarPatrols
A 2D side-scrolling space shooter prototype built entirely with Skia4Delphi.

RADStudio FMX / Skia4Delphi Arcade Space Shooter "Star Patrols"

A high-performance, thread-safe 2D side-scrolling space shooter built entirely with Skia4Delphi. A retro R-Type style arcade experience, featuring procedural generation, zero-gravity physics, AI enemies, and heavy neon visual effects. Enjoy! :D

<img width="638" height="506" alt="Unbenannt" src="https://github.com/user-attachments/assets/80df8016-b5be-40aa-8b12-8f5b126c2114" />


🎮 Gameplay Features

     R-Type Style Physics: Constant forward auto-scroll. The ship has minimum forward thrust—use "Left" to brake against the camera scroll, and "Right" to boost ahead.
     Advanced Visuals: 3-Layer parallax starfields, massive glowing blurred planets, and dynamic particle systems for engine trails and explosions.
     Enemies & AI: Encounter static-drifting Asteroids, red Fighters that fly in sinus-wave patterns, and green Diving Interceptors that calculate your Y-position and dive-bomb you when you get close.
     Combat: Fire neon plasma bullets to destroy enemies and asteroids. Collisions trigger satisfying particle bursts.
     Warp Gates: Survive the sector to reach the Wormhole at the end of the map to warp to the next, more difficult sector.
     Procedural Generation: Every sector is randomly generated with scaling difficulty (more enemies and asteroids per level).

🕹️ Controls

     Move Up/Down: W/S or Up/Down Arrows
     Brake / Boost: A/D or Left/Right Arrows
     Shoot: Space
     Pause Menu: M or Escape
     Reset Sector: R (While paused)

🛠️ Technical Details

     Renderer: Pure Skia Canvas (No Game Engine, no FMX shapes). Everything is drawn using paths, masks, and shaders.
     Threading: Physics and AI run on a background thread for consistent FPS, synchronized safely with the main rendering thread.
     Visual Effects: Heavy use of TSkMaskFilter for glowing neon UI, blurry space clouds, plasma bullets, and engine exhaust flames.
     Single-File Architecture: The complete game engine, including rendering and logic, is contained in one highly commented file.

📦 What's Inside

     SkiaStarPatrols.pas: The complete space shooter engine in a single file.
     Sample project and executable included.

🚀 Getting Started

    Open the project in RAD Studio (Delphi).
    Ensure you have the Skia4Delphi library installed.
    Run and play!

---- Latest Changes

v 0.1: Initial Release

     Implemented R-Type style auto-scroll camera (pushes player forward).
     Added player shooting mechanics with plasma bullets.
     Added 3 enemy types (Asteroid, Sinus-Fighter, Diving Interceptor) with unique movement patterns.
     Designed 3-layer parallax space background with massive distant planets.
     Overhauled ship rendering with banking animations and continuous engine particle trails.
     Added audio effects for shooting, explosions, and portal jumps.

License

MIT License - Do whatever you want with it. Credits appreciated but not required.

Happy hunting! 🚀👾
