# R3E telemetry — session hand-over

State after the 2026-07-07/08 session. Read `r3e-nixos-notes.md` first for the
full findings; this file is only what a new session needs to continue.

## Where things stand

- **R3E launches** with plain launch options
  (`DXVK_FRAME_RATE=145 gamemoderun %command%`) after the prefix revert
  (GE builtin mscoree in system32, no global/leftover overrides).
- **Prefix 211500 contains:** .NET 4.8 (real CLR, 704 MB, machine.config
  fixed), CrewChief 4.19.2.48, SimHub 9.11.11 (installed but not launched),
  wine-mono removed, winver win10 both registry views.
- **Helper** (`r3e_launch_helpers.sh`, commit `06a437e`): waits for the real
  game process, then launches **CrewChief + dash.exe only**, with app-dir
  native mscoree + per-app overrides. SimHub intentionally skipped.
- **nixcfg** commit `81e61bdd` adds 32-bit freetype/fontconfig to steam;
  **not yet activated** — until `sudo nixos-rebuild switch`, use the ad-hoc
  build at `/tmp/steam-run-ft/bin/steam-run` (rebuild it after reboot with
  `nix build --impure --expr 'with import <nixpkgs> {}; (steam.override { extraLibraries = p: [ p.freetype p.fontconfig ]; }).run' -o /tmp/steam-run-ft`
  with `NIXPKGS_ALLOW_UNFREE=1`).

## Immediately pending (blocked on user test)

Two-step test, in order:

1. Plain options → R3E must launch (baseline; last confirmed after revert).
2. Helper options
   (`bash -c '"/home/christian/code/SimHub_on_Linux/r3e_launch_helpers.sh" & DXVK_FRAME_RATE=145 gamemoderun %command%'`)
   → R3E must still launch; ~15 s later CrewChief appears.

Outcomes and next actions:

- **Game + CrewChief up:** check CrewChief runs on the real CLR (no
  "Failed to load user settings" loop, no mono-style stack traces in
  `Documents/CrewChiefV4/DebugLogs/ErrorLog.txt`). Then the only remaining
  functional test is a driven lap: CrewChief spotter/engineer must react.
  **End-to-end SHM telemetry has never been verified in this project.**
- **Game up, CrewChief on mono again:** the app-dir native mscoree approach
  failed (wine may force system32 for mscoree). Fall back options:
  (a) copy native mscoree into app dir under a different loading strategy,
  (b) accept CrewChief-on-CLR is impossible without system32 and evaluate
  CrewChief under wine-mono, (c) native-Linux consumer via UDP bridge
  (approach B in `r3e-proton-shm-handoff.md`).
- **Game does not start with helper:** helper still interferes; inspect
  `~/.cache/simhub-on-linux/r3e_launch_helpers.log` for ordering
  (`RRRE64.exe detected` must appear well after `socket found`, and the game
  window must exist before `[launch]` lines).

## Known-good rollback

- R3E-safe prefix state: `system32/mscoree.dll` = 701451 bytes (GE builtin),
  `syswow64` = 651011, no `"mscoree"=` line in `user.reg`'s global
  `DllOverrides`, no `AppDefaults\RRRE*` entries.
- `user.reg` backups in the prefix: `user.reg.bak-perapp` (before per-app
  override experiment), `user.reg.bak-ccdash` (before CrewChief+dash-only
  overrides). Restore only with all wineservers dead
  (sweep `/proc/*/exe` for `*Proton*|*/wine*`).
- Prefix backups from before this project: `compatdata/211500.bak2`,
  `211500.bak3` (May 2026, no .NET). Full reset path: delete
  `compatdata/211500`, let Steam recreate, reinstall .NET per
  `r3e-nixos-notes.md` recipe, reinstall CrewChief.

## Backlog (after telemetry works)

1. `sudo nixos-rebuild switch` on altair (activates steam-run freetype fix),
   then remove `/tmp/steam-run-ft` dependency.
2. Refactor `Install_Simhub_Linux.sh` / `Install_CrewChief_Linux.sh` /
   `shared_functions.sh` onto the working recipe (wine 9 + null driver +
   reg-based winver); they still call protontricks paths that fail on this
   system (wine-10 glibc crash, winecfg hang). Drop the uncommitted stash
   `install failing` afterwards.
3. Decide SimHub's fate for R3E (currently dropped; revisit only with a
   solution that keeps native mscoree out of system32).
4. Update README for the R3E CrewChief-only behavior.
5. Branch `nixos-support` holds one amended commit `06a437e` on top of the
   docs commits; push only after the functional test passes.

## Session artifacts

- `~/.cache/simhub-on-linux/`: `native-mscoree/` (stash), `dotnet48-manual.sh`
  (install recipe), `verify.sh`, `find-game.sh`, per-app logs, helper log.
- Memory file `simhub-r3e-nixos-state` mirrors this hand-over.
