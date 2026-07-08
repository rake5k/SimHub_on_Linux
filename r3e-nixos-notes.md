# R3E telemetry on NixOS — findings and recipes

Reference for running RaceRoom Racing Experience (AppID 211500, GE-Proton10-34)
with CrewChief, SimHub, and dash.exe (SealHUD / user refers to it as ReHUD) on
NixOS. Every claim below was verified by reproduction on host `altair`
(NixOS 26.05, glibc 2.42, kernel 7.0.12, niri/XWayland).

## Architecture (recap)

Pressure-vessel gives each Proton session a private tmpfs `/tmp`. R3E's
telemetry is a Wine named file mapping (`$R3E`), scoped to the wineserver whose
socket lives in that private `/tmp`. Any telemetry consumer must therefore run
inside the game's own sandbox. `r3e_launch_helpers.sh`, referenced from the
Steam launch options (`bash -c '<helper> & exec %command%'`), runs inside the
sandbox and launches the consumers there. Post-hoc launching
(`protontricks-launch --appid`) creates a new sandbox and can never see the
mapping. See `r3e-proton-shm-fix-design.md`.

## Hard constraint: SimHub vs. R3E

- SimHub's UI is WPF. WPF only runs on the real Microsoft .NET CLR, never on
  wine-mono (`PresentationCore` load fails, mono asserts).
- The real CLR requires a native Microsoft `mscoree.dll` shim; with wine's
  builtin mscoree, .NET apps run on wine-mono.
- **A native `mscoree.dll` in the prefix `system32`/`syswow64` stops R3E's
  VMProtect launcher from starting — even with no DllOverrides set.** Verified
  both directions: native file present → `RRRE64.exe` never starts; GE builtin
  restored → game launches.
- SimHub and R3E therefore exclude each other in one prefix via the system32
  route. Decision: run **CrewChief + dash.exe only** for R3E. SimHub stays
  supported for other games via the existing scripts.
- Current attempt (unproven): native `mscoree.dll` in each app's own directory
  plus per-app `HKCU\Software\Wine\AppDefaults\<exe>\DllOverrides
  "mscoree"="native,builtin"`. Wine searches the application directory first
  for native DLLs; whether this holds for mscoree is not yet confirmed.

Reference file sizes for identification:

| mscoree.dll | size (bytes) |
|---|---|
| GE-Proton10-34 builtin x64 | 701451 |
| GE-Proton10-34 builtin x86 | 651011 |
| UMU-Proton-9 builtin x64 | 599603 |
| native MS (from dotNetFx40) x64 | 444752 |
| native MS (from dotNetFx40) x86 | 297808 |

## NixOS-specific breakage (host-side wine)

1. **wine 10 (GE-Proton10-x) + glibc 2.42**: 32-bit processes segfault in
   `__memcpy_ssse3` inside `server_get_name_info` ← `NtQueryInformationFile`
   ← `get_std_handle` when a std handle is a regular file (pipes are fine).
   Breaks all host-side protontricks/winetricks use with wine 10.
   wine 9 (UMU-Proton-9.0-4e) is immune. Repro:
   `steam-run .../GE-Proton10-34/files/bin/wine cmd.exe /c echo x > /tmp/f`
   → rc=139.
2. **nixpkgs `steam-run` ships no 32-bit freetype/fontconfig** → wine GUI
   processes (msiexec, uninstaller, installers) hang at 0% CPU. Fixed
   declaratively in nixcfg (`81e61bdd`):
   `programs.steam.package = pkgs.steam.override { extraLibraries = p: [ p.freetype p.fontconfig ]; }`.
   `steam-run` inherits the override via `cfg.package.run`.
3. **Proton wine `fs_get_gpus` (winex11) deadlocks 32-bit GUI processes** on a
   mutex with any X display (real XWayland `:0` and Xvfb alike). Workaround
   for headless installs: null display driver
   (`HKCU\Software\Wine\Drivers "Graphics"="null"`); remove the key afterwards.
4. **Proton's winecfg ignores `/v`** and opens its GUI → every winetricks verb
   that calls `w_set_winver`/`w_store_winver` hangs. Set winver via
   `wine64 reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' ...`
   instead — and also the 32-bit view (`/reg:32`): wine reports the
   `Wow6432Node` version to 32-bit processes (InnoSetup saw WinXP while
   `cmd /c ver` reported win10).
5. **Steam launches the helper with a C locale.** Wine then mis-decodes
   non-ASCII filenames; .NET raises "Illegal characters in path" (CrewChief
   crashes enumerating `sounds/driver_names/*.wav` — brzeziński.wav etc.).
   The helper exports `LC_ALL=C.UTF-8` when the effective locale is not UTF-8.
6. **Process hygiene:** wine client processes show Windows-style cmdlines
   (`explorer.exe /desktop`, `msiexec /x{...}`, `start.exe /exec`) that plain
   `pkill -f` patterns miss. Orphans hold the prefix lock and wedge every later
   wineserver. Sweep via `/proc/*/exe` matching `*Proton*|*/wine*`.
7. **Wine-version drift:** running UMU-Proton-9 wine against the GE-Proton10
   prefix rewrites system DLLs/registry with wine-9 versions; GE-Proton then
   refreshes them back on the next game start. For registry changes prefer
   direct `user.reg` text edits while no wineserver runs.

## Working dotnet48 install recipe (host-side)

`~/.cache/simhub-on-linux/dotnet48-manual.sh` — replay of the winetricks
dotnet48 verb without winecfg:

- wine: UMU-Proton-9.0-4e (`files/bin/wine`), via freetype-fixed `steam-run`.
- null display driver on; `WINEDLLOVERRIDES=fusion=b`; fsync/esync off.
- winver via reg (both views): xp64 → run `dotNetFx40_Full_x86_x64.exe /q
  /c:"install.exe /q"` → NDP v4 Full reg keys → win7 → run
  `ndp48-x86-x64-allos-enu.exe /sfxlang:1027 /q /norestart` → win10 restore.
- The installers do NOT deploy `machine.config` in this mode → .NET's
  configuration system throws `ConfigurationErrorsException` (SimHub startup
  crash). Copy `Config/machine.config` for both arches from the dotNetFx40
  payload (`7z x` the exe, `msiextract netfx_Core_x64.msi`).
- `ndp48` does not ship `mscoree.dll` (Windows inbox file). The native shim is
  in the dotNetFx40 payload: `Windows/System64/mscoree.dll` (x64),
  `Windows/System/mscoree.dll` (x86).
- Extracted artifacts are stashed in `~/.cache/simhub-on-linux/native-mscoree/`
  (`mscoree.dll.{x64,x86}`, `machine.config.{x64,x86}`).

## App-specific notes

- **CrewChief** logs to `Documents/CrewChiefV4/DebugLogs/ErrorLog.txt` and its
  in-app console, not stdout. Its stdout always ends at `Boot trace MW 2`,
  even when fully running — do not judge liveness from the helper's per-app
  log. A mono run corrupts `AppData/Local/Britton_IT_Ltd/.../user.config`; the
  next CLR run shows "Failed to load user settings", recreates it, and exits
  once (by design).
- **SimHub** first-run crash signature `ConfigurationErrorsException` =
  missing `machine.config`. Working state confirmed once (window, web server
  on :8888) while native mscoree was global — before the R3E conflict was
  known.
- **dash.exe** is the Sector3 `r3e-api` C# sample. It polls for the game
  process and dereferences a null mapping on exit
  (`NullReferenceException at R3E.Sample.Dispose`) when the game/SHM was
  never found. Harmless; disappears once the game runs.

## Helper design (`r3e_launch_helpers.sh`)

1. Refuse to run unless `STEAM_COMPAT_DATA_PATH` ends in `/211500`.
2. Force UTF-8 locale.
3. Wait for the wineserver socket in `/tmp/.wine-1000/`.
4. Wait for the game: match `/proc/*/comm == RRRE64*`. Do NOT use
   `pgrep -f RRRE64` — Steam's reaper/proton wrapper argv contains
   `RRRE64.exe` long before the game process exists. Launching apps during
   VMProtect startup prevents the game from starting. Settle 15 s.
5. Restore `machine.config` (both arches) and app-dir `mscoree.dll` for
   CrewChief and dash.exe. Never write to `system32`.
6. Launch CrewChief and dash.exe via the Proton `wine64` from
   `STEAM_COMPAT_TOOL_PATHS`, with `WINEFSYNC=1 WINEESYNC=1` (the game's
   wineserver runs fsync; Proton's env is not inherited), `LD_PRELOAD=''`,
   stdout piped (not file-redirected — see breakage item 1) into per-app logs
   under `~/.cache/simhub-on-linux/`.
7. SimHub is not launched for R3E (see hard constraint).

Diagnostics: `~/.cache/simhub-on-linux/verify.sh` (run while the game is up),
`~/.cache/simhub-on-linux/find-game.sh` (identify the real game process).
