# R3E telemetry — session hand-over

State after the 2026-07-08 late session. Read `r3e-nixos-notes.md` first for
the full findings; this file is only what a new session needs to continue.

## Where things stand

- **Working end-to-end** (verified 2026-07-08 ~23:55): R3E + CrewChief
  (real CLR, UI up, `SKIP_UPDATES`) + dash.exe, all launched by the helper
  from the Steam launch options. Stable > 3 min; a driven lap (spotter audio,
  live telemetry) is the only remaining functional test.
- **Launch options** are set in Steam (written directly to
  `userdata/5051778/config/localconfig.vdf` while Steam was down):
  `/home/christian/code/SimHub_on_Linux/r3e_launch_helpers.sh & DXVK_FRAME_RATE=145 gamemoderun %command%`
  — quote-free form; the old `bash -c '...'` form breaks (see notes).
- **Helper strategy changed**: builtin mscoree at game launch → native
  swapped into system32/syswow64 after the game is up → apps launched →
  builtin restored on game exit. App-dir mscoree disproven; VMProtect check
  proven launch-time-only. Game detection now matches wine-process argv[0]
  (comm is renamed to `MainThread` by R3E's CEF frontend), timeout 600 s.
- **Prefix 211500 contains:** .NET 4.8 (real CLR, machine.config fixed),
  CrewChief 4.19.4.0 (updated from 4.19.2.48 on 2026-07-08; fresh
  CLR-written `4.19.4.0/user.config`, mono-written one saved as
  `user.config.mono-bak`), SimHub 9.11.11 (installed, not launched),
  winver win10 both views, per-app mscoree overrides for
  CrewChiefV4.exe/dash.exe.
- **nixcfg** commit `81e61bdd` (32-bit freetype/fontconfig for steam) still
  **not activated** — `sudo nixos-rebuild switch` pending; ad-hoc build at
  `/tmp/steam-run-ft/bin/steam-run` (rebuild after reboot:
  `NIXPKGS_ALLOW_UNFREE=1 nix build --impure --expr 'with import <nixpkgs> {}; (steam.override { extraLibraries = p: [ p.freetype p.fontconfig ]; }).run' -o /tmp/steam-run-ft`).

## Immediately pending

1. **User drives a lap**: CrewChief spotter/engineer must react. End-to-end
   SHM telemetry has never been verified in this project. If CrewChief is
   silent: check audio device, `Documents/CrewChiefV4/DebugLogs/ErrorLog.txt`,
   and that CrewChief's game selection is RaceRoom (last console log showed
   profile game "PCARS" — may need switching in the CrewChief UI once).
2. `sudo nixos-rebuild switch` on altair, then drop `/tmp/steam-run-ft`.

## Known-good rollback

- R3E-safe prefix state: `system32/mscoree.dll` = 701451 bytes (GE builtin),
  `syswow64` = 651011. Native = 444752/297808. Stash (incl. GE builtins and
  machine.config) at `~/.cache/simhub-on-linux/native-mscoree/`. The helper's
  section 2a self-heals the prefix at every launch.
- `user.reg` backups in the prefix: `user.reg.bak-perapp`, `user.reg.bak-ccdash`.
  Restore only with all wineservers dead (sweep `/proc/*/exe` for
  `*Proton*|*/wine*`).
- Prefix backups from before this project: `compatdata/211500.bak2`, `.bak3`
  (May 2026, no .NET).
- Steam launch options backup: `/tmp/localconfig.vdf.bak` (pre-fix copy).

## Backlog (after telemetry works)

1. Refactor `Install_Simhub_Linux.sh` / `Install_CrewChief_Linux.sh` /
   `shared_functions.sh` onto the working recipe (wine 9 + null driver +
   reg-based winver); they still call protontricks paths that fail on this
   system. Drop the uncommitted stash `install failing` afterwards.
2. SimHub for R3E: the post-launch mscoree swap may make WPF viable again —
   untested, revisit on demand.
3. Update README for the R3E CrewChief-only behavior.
4. Push `nixos-support` after the lap test passes.
5. CrewChief updates are skipped (`SKIP_UPDATES`) because the in-app update
   check crashes (c0000005, wine NTLM/HTTP). To update CrewChief: run its
   installer/updater outside the game session, then delete the new
   mono-written `user.config` if it self-exits on next CLR run.

## Session artifacts

- `~/.cache/simhub-on-linux/`: `native-mscoree/` (stash incl. `ge-builtin`
  copies), `dotnet48-manual.sh`, `verify.sh`, `find-game.sh`, per-app logs,
  helper log.
- Memory file `simhub-r3e-nixos-state` mirrors this hand-over.
