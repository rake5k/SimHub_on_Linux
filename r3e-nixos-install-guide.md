# RaceRoom + CrewChief on NixOS — install guide

Step-by-step reproduction of the working setup: RaceRoom Racing Experience
(Steam AppID 211500, GE-Proton) with CrewChief on the real .NET CLR and the
SealHUD overlay (`dash.exe`), sharing the game's shared-memory telemetry
inside its Proton sandbox. Verified end-to-end (spotter reacts to a driven
lap) on NixOS 26.05, glibc 2.42, X11/XWayland, 2026-07-09.

Background for every non-obvious step is in `r3e-nixos-notes.md`. Read the
[Troubleshooting](#troubleshooting) table before deviating.

Path conventions: Steam at `~/.local/share/Steam` (alias `~/.steam/steam`),
this repo at `~/code/SimHub_on_Linux`. Adjust to taste.

## 1. NixOS configuration

Steam with 32-bit freetype/fontconfig (plain nixpkgs `steam-run` ships
neither; wine GUI processes hang at 0% CPU without them), plus gamemode and
the tools used below:

```nix
programs.steam = {
  enable = true;
  package = pkgs.steam.override {
    extraLibraries = p: [ p.freetype p.fontconfig ];
  };
};
programs.gamemode.enable = true;
environment.systemPackages = with pkgs; [ p7zip msitools ];
```

Rebuild (`sudo nixos-rebuild switch`). `steam-run` inherits the override.
Without a rebuild, an ad-hoc equivalent works:

```sh
NIXPKGS_ALLOW_UNFREE=1 nix build --impure \
  --expr 'with import <nixpkgs> {}; (steam.override { extraLibraries = p: [ p.freetype p.fontconfig ]; }).run' \
  -o /tmp/steam-run-ft
# then use /tmp/steam-run-ft/bin/steam-run below
```

## 2. Proton versions

Two Proton builds into `~/.local/share/Steam/compatibilitytools.d/`:

- **GE-Proton10-x** (game runtime) — https://github.com/GloriousEggroll/proton-ge-custom/releases
- **UMU-Proton-9.0-x** (host-side installer wine ONLY) — https://github.com/Open-Wine-Components/umu-proton/releases

Why two: wine 10 on glibc 2.42 segfaults in 32-bit processes whenever a std
handle is file-backed, which breaks all host-side installer work; wine 9 is
immune (notes, breakage 1). The game itself runs fine on GE-Proton10.

If the GE version differs from `GE-Proton10-34`, update the hardcoded
fallback path in `r3e_launch_helpers.sh` (section 3 of the script).

## 3. Install R3E and create the prefix

1. Install RaceRoom Racing Experience in Steam.
2. Game properties → Compatibility → force `GE-Proton10-34`.
3. Launch the game once to the menu, then quit. This creates and initializes
   `~/.local/share/Steam/steamapps/compatdata/211500/pfx`.

## 4. Download the payloads

```sh
mkdir -p ~/.cache/winetricks/dotnet40 ~/.cache/winetricks/dotnet48 \
         ~/.cache/simhub-on-linux ~/.cache/dash
```

| File | Target | Source |
|---|---|---|
| `dotNetFx40_Full_x86_x64.exe` | `~/.cache/winetricks/dotnet40/` | Microsoft; canonical URL in the winetricks `dotnet40` verb |
| `ndp48-x86-x64-allos-enu.exe` | `~/.cache/winetricks/dotnet48/` | Microsoft; canonical URL in the winetricks `dotnet48` verb |
| `CrewChiefV4.msi` | `~/.cache/simhub-on-linux/` | https://thecrewchief.org/ |
| `dash.zip` → extract | `~/.cache/dash/` | https://sealhud.github.io/dash.zip |

Do NOT run winetricks against the prefix — its `winecfg /v` calls hang under
Proton and its wine-10 usage segfaults (notes, breakage 1 and 4). Only the
cached files are used, by the script below.

## 5. Install .NET Framework 4.8 into the prefix

Precondition for every host-side prefix operation: no wine process may hold
the prefix. Sweep by executable, not by name (wine cmdlines are
Windows-style and evade `pkill -f`):

```sh
for d in /proc/[0-9]*; do
  case "$(readlink "$d/exe" 2>/dev/null)" in
    *Proton*|*/wine*) kill -9 "${d#/proc/}" ;;
  esac
done
```

Then run the recipe (a winetricks-dotnet48 replay that avoids winecfg, uses
the null display driver against the winex11 32-bit mutex deadlock, and sets
Windows versions via `reg add`):

```sh
steam-run ./r3e_dotnet48_install.sh   # ~10 min, ends with "done"
```

It verifies itself by listing
`.../Microsoft.NET/Framework64/v4.0.30319/mscorlib.dll` at the end. The
script leaves winver at win10 and removes the null-driver key.

Adjust `W=` in the script if the UMU-Proton directory name differs.

## 6. Extract and stash native mscoree + machine.config

The quiet ndp48 install deploys neither `machine.config` (.NET config system
throws `ConfigurationErrorsException` without it) nor `mscoree.dll` (Windows
inbox file). Both are in the dotNetFx40 payload:

```sh
cd "$(mktemp -d)"
7z x ~/.cache/winetricks/dotnet40/dotNetFx40_Full_x86_x64.exe
msiextract netfx_Core_x64.msi

S=~/.cache/simhub-on-linux/native-mscoree; mkdir -p "$S"
cp Windows/System64/mscoree.dll "$S/mscoree.dll.x64"   # 444752 bytes
cp Windows/System/mscoree.dll   "$S/mscoree.dll.x86"   # 297808 bytes
# machine.config (35955 bytes, same content both arches) — find it in the
# extracted tree:
find . -name machine.config
cp <x64 copy> "$S/machine.config.x64"
cp <x86 copy> "$S/machine.config.x86"
```

Deploy machine.config into the prefix and stash GE-Proton's builtin mscoree
(the helper restores/swaps these files at every launch, so the stash names
matter):

```sh
P=~/.local/share/Steam/steamapps/compatdata/211500/pfx
cp "$S/machine.config.x64" "$P/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/Config/machine.config"
cp "$S/machine.config.x86" "$P/drive_c/windows/Microsoft.NET/Framework/v4.0.30319/Config/machine.config"
cp "$P/drive_c/windows/system32/mscoree.dll" "$S/mscoree.dll.ge-builtin.x64"  # 701451 bytes
cp "$P/drive_c/windows/syswow64/mscoree.dll" "$S/mscoree.dll.ge-builtin.x86"  # 651011 bytes
```

Size mismatch on the builtin copies means the prefix was contaminated by
another wine version — see [Troubleshooting](#troubleshooting).

Do NOT copy the native mscoree into system32/syswow64 here: with it in
place, R3E's VMProtect launcher does not start. The helper swaps it in
after the game is up (launch-time-only check, verified).

## 7. Install CrewChief

Same environment rules as step 5 (sweep first; wine 9; null driver for the
GUI-less install):

```sh
W=~/.local/share/Steam/compatibilitytools.d/UMU-Proton-9.0-4e/files/bin
export WINEPREFIX=~/.local/share/Steam/steamapps/compatdata/211500/pfx
export WINEDEBUG=-all WINEFSYNC=0 WINEESYNC=0

steam-run "$W/wine64" reg add 'HKCU\Software\Wine\Drivers' /v Graphics /d null /f
steam-run "$W/wine" msiexec /i ~/.cache/simhub-on-linux/CrewChiefV4.msi /qn
steam-run "$W/wineserver" -w
steam-run "$W/wine64" reg delete 'HKCU\Software\Wine\Drivers' /v Graphics /f
steam-run "$W/wineserver" -w
```

Result: `$WINEPREFIX/drive_c/Program Files (x86)/Britton IT Ltd/CrewChiefV4/`.

(SimHub install works the same way with `SimHubSetup_*.exe /VERYSILENT
/SUPPRESSMSGBOXES /NORESTART`, but InnoSetup additionally requires win10 in
the 32-bit registry view — `reg add ... /reg:32` — and SimHub is NOT
launched for R3E; see the hard constraint in the notes.)

## 8. Per-app mscoree overrides

CrewChief and dash.exe must load the native mscoree (real CLR); R3E must
keep wine's builtin. Per-app `DllOverrides` in `HKCU` do exactly that once
the native file is in system32/syswow64 (the helper's job).

Sweep wine processes (step 5 snippet) — the registry file must not be open —
then append to `$WINEPREFIX/user.reg`:

```
[Software\\Wine\\AppDefaults\\CrewChiefV4.exe\\DllOverrides]
"mscoree"="native,builtin"

[Software\\Wine\\AppDefaults\\dash.exe\\DllOverrides]
"mscoree"="native,builtin"
```

Direct text edit avoids running any wine against the prefix (wine-version
drift, notes breakage 7). Keep a backup of `user.reg` first.

## 9. Steam launch options

In Steam → R3E → Properties → Launch Options, as ONE line:

```
/home/<user>/code/SimHub_on_Linux/r3e_launch_helpers.sh & DXVK_FRAME_RATE=145 gamemoderun %command%
```

`DXVK_FRAME_RATE`/`gamemoderun` are optional; the helper part is not.
Rules that this line already obeys — violate them and the game dies
instantly at launch:

- No quotes anywhere. Steam feeds the line to `sh -c`; `%command%` expands
  to text that itself contains single quotes, so any `bash -c '…%command%…'`
  wrapper produces `sh: unexpected EOF`.
- No line breaks (beware terminal copy-paste wrapping).

Verify the stored value if in doubt (Steam must be fully shut down to edit
it on disk): `userdata/<id>/config/localconfig.vdf` → apps → 211500 →
`LaunchOptions`.

## 10. First launch and verification

Start R3E from Steam. Expected helper timeline in
`~/.cache/simhub-on-linux/r3e_launch_helpers.log`:

```
== r3e_launch_helpers.sh starting (pid=…, mnt_ns=…)   # inside the game's bwrap
WINEPREFIX=…/compatdata/211500/pfx
wineserver socket found: /tmp/.wine-1000/server-…
waiting for RRRE64.exe process (…)
RRRE64.exe detected; settling 15s …                    # 20 s – 5 min (cold VMProtect start)
restored native mscoree (system32) / (syswow64)
[launch] CrewChief -> …
[launch] dash.exe  -> …
== helpers spawned, exiting
```

Checks:

- CrewChief window appears ~15–30 s after the game window. First run after
  an install/update may recreate its settings and exit once — restart the
  game via Steam, second run is stable.
- In CrewChief, set the game selection to RaceRoom, enable the desired
  spotter/engineer, and save.
- Liveness: judge by the process list and
  `Documents/CrewChiefV4/DebugLogs/ErrorLog.txt` inside the prefix — NOT by
  CrewChief's stdout (it always goes silent early). A wine process whose
  argv[0] ends in `CrewChiefV4.exe` must exist.
- Functional test: drive a lap; the spotter must call cars alongside and the
  engineer must react to session events.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Game dies instantly; `sh: unexpected EOF` in `~/.local/share/Steam/logs/console-linux.txt` | Broken launch options (quotes/line break) | Re-paste per step 9; check `localconfig.vdf` with Steam shut down |
| Game never starts, only wineserver + winedevice | Native mscoree was in system32 at launch | The helper's start-phase restores the builtin — check it ran at all (log); manual fix: copy `mscoree.dll.ge-builtin.*` back per step 6 paths |
| Helper: `FATAL: STEAM_COMPAT_DATA_PATH not set` | Helper run outside Steam / options on wrong game | Launch via Steam entry for AppID 211500 |
| Helper: `RRRE64.exe not seen after 600s` but game visibly runs | Detection regression | Game process has argv[0] `…RRRE64.exe` but comm `MainThread`; never match comm or `pgrep -f` |
| CrewChief prints `Configuration system failed to initialize`, exits | App ran on wine-mono, not the CLR | Native mscoree missing in system32/syswow64 at app start, or per-app override missing (step 8) |
| CrewChief exits right after start, `Failed to load user settings` | user.config written by an earlier mono run | Delete `AppData/Local/Britton_IT_Ltd/CrewChiefV4.exe_Url_*/<ver>/user.config` in the prefix; restart game |
| CrewChief crashes c0000005 shortly after start | In-app update check (wine NTLM/HTTP) | Helper already passes `SKIP_UPDATES`; update CrewChief only via its MSI (step 7) |
| CrewChief crashes `Illegal characters in path` | Non-UTF-8 locale (Steam launches with C locale) | Helper forces `LC_ALL=C.UTF-8`; keep that logic |
| Wine operations hang; later wineservers never start | Orphan wine processes hold the prefix | Sweep via `/proc/*/exe` (step 5 snippet) |
| system32 DLL sizes drift from the table in the notes | UMU-wine run against the prefix | Harmless for the game (GE refreshes on next start); re-stash `ge-builtin` copies only from a clean GE-refreshed prefix |
| Everything up, no spotter audio | Wrong game selected in CrewChief, audio device, or telemetry not flowing | Check CrewChief console in its UI during a session |

## Maintenance

- **CrewChief update**: never let the in-app updater run (crashes; and a
  mono-launched updater poisons user.config). Download the new MSI and
  repeat step 7, then delete the versioned `user.config` if the first run
  self-exits.
- **GE-Proton update**: update the fallback path in `r3e_launch_helpers.sh`,
  re-stash `mscoree.dll.ge-builtin.*` from the refreshed prefix (sizes
  change between GE versions).
- **Full prefix reset**: delete `compatdata/211500`, launch the game once,
  redo steps 5–8.
