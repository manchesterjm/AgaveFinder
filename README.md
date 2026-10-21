# Agave Finder (Dune: Awakening, single-player)

Source for the Nexus Mods release: https://www.nexusmods.com/duneawakening/mods/78

Shows the distance to every agave plant near you that has seeds, over the plant. A UE4SS Lua mod
(`Scripts/`) plus one small native helper (`dlls/main.dll`). Player-facing details are in `README.txt`.

## What the DLL does

The game keeps each agave plant's "harvests left" in a private map that Lua cannot see.
`native/seeds.cpp` registers one Lua function, `AgaveSeedsLeft(componentAddress, plantCount)`, that reads
those numbers and returns them.

- **Read-only.** Every read goes through `ReadProcessMemory` on the game's own process, so a bad address fails
  the read instead of crashing. Nothing in the game is written.
- **Small imports.** The only system imports are `ReadProcessMemory`, `GetProcessHeap`, `HeapAlloc` and `HeapFree`
  (kernel32). There is no networking, no file access and no process or thread creation.
- **No C runtime.** It is built with `/NODEFAULTLIB`; the only other imports are the UE4SS v3.0.1 mod interface.

## Build

You need `clang-cl`, `lld-link`, `llvm-dlltool` and `llvm-readobj` (LLVM, any recent version), plus `UE4SS.dll`
v3.0.1 (Git f58e8f84), the version bundled with the WPS Dune Launcher. Its exports are used to make the import
library.

```sh
native/build.sh /path/to/UE4SS.dll
```

This writes `dlls/main.dll`. The build is reproducible (`/Brepro`), so rebuilding gives a byte-identical file:

```
sha256(dlls/main.dll) = 9f7e948ecb1b169ae5fe39f1969b94a44ecc82902572ee1d76d187f8aebc6871
```

## Layout

| Path                              | What                                                                     |
| --------------------------------- | ------------------------------------------------------------------------ |
| `Scripts/main.lua`                | Settings (mod.ini / NBS Settings / Mod Settings), log, the marker loop   |
| `Scripts/nbs_settings_client.lua` | NBS Settings client by Null Boundary Studios, unchanged, with permission |
| `Scripts/markers.lua`             | Plant positions, seed reads, the distance markers                        |
| `native/seeds.cpp`                | The native seed reader (source of `dlls/main.dll`)                       |
| `native/build.sh`                 | Builds `dlls/main.dll`                                                   |
| `agave_positions.txt`             | The 75 known plant positions                                             |
| `mod.ini`, `mod.json`             | Launcher metadata and default settings                                   |
