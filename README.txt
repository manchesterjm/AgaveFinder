AGAVE FINDER - Dune: Awakening (single-player)
==============================================

Find the Oodham agave you can pick. Every agave plant near you that has seeds gets a small green distance over it
("24 m", "1.15 km"), drawn through hills and rock like a map marker. Plants without seeds show nothing.

WHAT THIS DOES
- A marker shows only while its plant has seeds. Pick a plant and its marker disappears; when the plant regrows,
  the marker comes back. The mod reads each plant's seeds from the game itself - there is no timer to drift.
- The distance updates as you move, so you can walk straight to the nearest one.
- Ships with the spots of 75 agave plants around the Hagga Basin, so markers show from your first launch. Any plant
  it has not seen before is added the first time you pass near it (Mods\AgaveFinder\agave_positions.txt).
- Marker Range: only plants within this distance of you show a marker (50-2000 m, default 100).
- Agave Markers: switch the markers off and on without restarting.
- No game files or save data are changed. Nothing in the game is written - the mod only reads.

REQUIREMENTS
- WPS Dune Launcher 1.1.1+ (https://www.nexusmods.com/duneawakening/mods/18).
  UE4SS is bundled with the launcher - do NOT install it separately.
- Optional, for in-game settings that apply live: NBS Settings (https://www.nexusmods.com/duneawakening/mods/80, opens with F10)
  or Native Mod Settings (https://www.nexusmods.com/duneawakening/mods/34, Settings > Mods) - either one, or both.
  Without them, change the settings in mod.ini (restart the game after editing).
- Single-player only (mods do not run on online servers).

INSTALL (manually - NOT with Vortex)
1. Close the game and the launcher.
2. Extract the ZIP into the WPS launcher folder (where WPS_Dune.exe is) - the mod lands in Mods\AgaveFinder.
3. Start WPS_Dune.exe, click Refresh, enable "Agave Finder", start the game through the launcher.

NOTES
- The mod has a small native part, dlls\main.dll. The game keeps each plant's seeds where scripts cannot see them,
  so the DLL reads that one number for the Lua side. It only reads memory, and it checks the data looks right
  before trusting it. If a game update changes it, the DLL returns nothing and every plant in range shows its
  marker instead (the log says so) - nothing breaks. Source and build script: Mods\AgaveFinder\native.
- A plant only regrows while a player is near it (the game's rule, about 10 m). A plant you picked and walked away
  from keeps no marker until you go back and it regrows.
- A plant the mod has not been near yet this session shows its marker until it is read.
- Some agave plants stop regrowing in the base game. Those have no seeds, so they get no marker.
- Log for bug reports: Mods\AgaveFinder\agave_finder.log (starts fresh each launch).
- Scripts\nbs_settings_client.lua is by Null Boundary Studios, included unchanged with their permission (see
  the header of that file). It only talks to NBS Settings and Mod Settings; without them it does nothing.

VERSION HISTORY
- 1.1.0  Works with NBS Settings: the settings show in its F10 menu and apply live, with an on/off line on its
         Status page. Mod Settings keeps working, and a change made in one menu no longer stops the other
         from applying. The menus are answered from the main menu on, not only once you are in the world.
- 1.0.0  First public release.
