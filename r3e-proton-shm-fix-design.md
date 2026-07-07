# R3E + Proton SHM Telemetry — Design

Companion to [`r3e-proton-shm-handoff.md`](r3e-proton-shm-handoff.md). Read the
handoff first for problem analysis and root cause; this document specifies the
chosen fix.

## Scope

Personal fork only. R3E (`AppID 211500`) only. Other games in the repo
(`LMU 2399420`, `AC EVO 3058630`, `rFactor 2 365960`, `AC1 244210`) are
untouched and keep current behavior.

## Goal

When R3E runs via Steam Proton, make SimHub, CrewChief, and dash.exe (SealHUD)
see R3E's `$R3E` shared-memory section so they receive live telemetry. The
existing `runsimhub2.sh` / `runcrewchief.sh` post-hoc launch path is broken
because `protontricks-launch --appid` creates a new pressure-vessel session
with its own private `/tmp`, so the spawned wine processes start a fresh
wineserver and cannot resolve R3E's named file mapping.

## Approach

Steam launch-options wrapper (approach A in the handoff doc). Set R3E's Steam
launch options to a `bash -c '<helper> & exec %command%'` form. Steam evaluates
the whole launch-options string inside the same pressure-vessel session as
R3E, so the backgrounded helper inherits R3E's mount namespace, sees R3E's
`/tmp/.wine-1000/server-…/socket`, connects to R3E's wineserver, and can open
named mappings.

### Verified premise

Approach A's premise was confirmed empirically before this design was written:

- Probe launch options on R3E:
  `bash -c '(sleep 8 && { echo "mnt_ns=$(readlink /proc/self/ns/mnt)"; ls -la /tmp/.wine-1000/; } > "$HOME/r3e-sandbox-probe.log") & DXVK_FRAME_RATE=145 gamemoderun %command%'`
- Probe captured mnt ns `mnt:[4026532743]`; host mnt ns is `mnt:[4026531832]`
  — different namespace, i.e. inside the pressure-vessel bwrap.
- Probe saw `/tmp/.wine-1000/server-35-29ef865/` (R3E's wineserver dir; hash
  `29ef865` matches the `/dev/shm/wine-29ef865-fsync` filename in the handoff
  doc). Host has no `/tmp/.wine-1000/` (private tmpfs, as predicted).
- Conclusion: a process launched via the launch-options bash sees R3E's
  wineserver socket and can open `$R3E`.

## Components

### New file: `r3e_launch_helpers.sh`

In-bwrap helper, lives in the repo, runs inside R3E's pressure-vessel session
(because the launch-options bash inherits the bwrap and the repo path is under
`$HOME` which bwrap bind-mounts).

Responsibilities, in order:

1. Truncate `$HOME/.cache/simhub-on-linux/r3e_launch_helpers.log` and redirect
   the script's own stdout/stderr to it. Host-visible for `tail -f` debugging.
2. Refuse to run if `$STEAM_COMPAT_DATA_PATH` is not present or does not end
   in `/211500`. Log and exit 2.
3. Poll for `/tmp/.wine-1000/server-*/socket` up to 60 s. If absent, log and
   exit 3.
4. Discover the wine binary. Try candidates in order, stop at first that
   works:
   - `$STEAM_COMPAT_TOOL_PATHS`-derived `wine64`,
   - hardcoded `$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-34/files/bin/wine64`.

   `protontricks-launch` is deliberately not a candidate: it is a Nix-store
   binary, and inside the Steam Runtime container `LD_LIBRARY_PATH` makes its
   Nix bash resolve the runtime's older glibc, failing with
   `symbol lookup error: __nptl_change_stack_perm, version GLIBC_PRIVATE`
   (observed in the 2026-05-31 acceptance test). Proton's own `wine64` is
   built for the runtime and, with `WINEPREFIX` set, connects to the running
   wineserver. Children are launched with `LD_PRELOAD=` to drop the 32-bit
   `gameoverlayrenderer.so` that otherwise floods the log.

   Log which candidate won. If none works, log and exit 4.
5. For each of:
   - `$WINEPREFIX/drive_c/Program Files (x86)/SimHub/SimHubWPF.exe`,
   - `$WINEPREFIX/drive_c/Program Files (x86)/Britton IT Ltd/CrewChiefV4/CrewChiefV4.exe`,
   - `$HOME/.cache/dash/dash.exe`

   where `$WINEPREFIX = $STEAM_COMPAT_DATA_PATH/pfx`:
   - if the `.exe` does not exist, log `[skip] <name> not installed in prefix`
     and move on;
   - if a same-named process is already running (`pgrep -f <basename>`), log
     `[skip] <name> already running` and move on;
   - else log `[launch] <name>` and spawn it in background via the discovered
     wine binary, with `WINEPREFIX` set, output appended to the log.
6. Return (background children continue running for R3E's session; bwrap
   teardown on R3E exit kills them).

### Changed: `runsimhub2.sh` and `runcrewchief.sh`

When the resolved `game` is `211500`, both scripts print the exact
launch-options string to stdout with a short instruction:

> Paste this into Steam → R3E → Properties → Launch Options, save, and start
> R3E. SimHub, CrewChief, and dash.exe will launch automatically if installed.

…then exit 0. They do not call `protontricks-launch`, do not invoke
`check_Raceroom`, and do not modify Steam config.

For any other AppID, both scripts behave exactly as today.

The launch-options string printed by the run* scripts has the form:

```
bash -c '"<absolute path to r3e_launch_helpers.sh>" & DXVK_FRAME_RATE=145 gamemoderun %command%'
```

The helper path is derived at print time from the script's own location
(`realpath` on `$0`'s directory) so the printed string is correct regardless
of where the repo is cloned. The user pastes it verbatim.

The leading env (`DXVK_FRAME_RATE=145`) and wrapper (`gamemoderun`) are
hardcoded defaults — they happen to match the user's current R3E launch
options and are useful generic defaults for sim racing. The run* scripts do
not read the user's existing launch options. If the user wants different env
or wrappers, they edit the string by hand in Steam — the print is a starting
point, not a contract.

### Changed: `shared_functions.sh`

Delete `check_Raceroom`. dash.exe is now launched by the helper instead of by
the run* scripts. Remove the call to `check_Raceroom` from `runsimhub2.sh`
and `runcrewchief.sh`.

### Reverted: uncommitted `sudo nsenter` change

The uncommitted prototype in `runcrewchief.sh` (`sudo nsenter -m -t <RRRE64-pid> protontricks-launch …`)
is reverted before the new logic is applied. Cleanest diff, no two-code-paths.

## Acceptance test

1. `./runsimhub2.sh 211500` prints the launch-options string and exits 0.
2. Paste the printed string into Steam → R3E → Properties → Launch Options
   (replaces the current probe string), close Steam.
3. Start R3E from Steam. Wait for the main menu.
4. `tail -n +1 ~/.cache/simhub-on-linux/r3e_launch_helpers.log` shows:
   - `wineserver socket found: /tmp/.wine-1000/server-XX-…/socket`
   - `wine binary: <chosen candidate>`
   - one `[launch] X` or `[skip] X …` line per helper.
5. SimHub displays live R3E telemetry; CrewChief reacts to laps; dash.exe
   overlays. (Functional check — the only one that matters.)

## Failure modes

| Condition                                            | Helper behavior              | Exit code |
|------------------------------------------------------|------------------------------|-----------|
| `$STEAM_COMPAT_DATA_PATH` missing or wrong AppID     | Log, do nothing              | 2         |
| Wineserver socket absent after 60 s                  | Log, do nothing              | 3         |
| No usable wine binary                                | Log, do nothing              | 4         |
| Specific `.exe` missing from prefix                  | Log `[skip]`, continue       | (n/a)     |
| Specific `.exe` already running                      | Log `[skip]`, continue       | (n/a)     |
| SimHub crashes after launch / .NET not installed     | Out of scope (install scripts cover this) | (n/a) |

## Cleanup at end of implementation

- Delete `~/r3e-sandbox-probe.log` (verification artifact).
- User pastes the new launch-options string into Steam (replaces the probe
  string still in `localconfig.vdf`).

## Out of scope

- Auto-editing `localconfig.vdf` (decided: print-and-paste only).
- Fallback path for "user started R3E without setting launch options" (decided:
  no fallback; `nsenter` prototype reverted).
- Any game other than R3E.
- Upstreaming to `srlemke/SimHub_on_Linux`.
- A native-Linux SHM consumer or UDP bridge (approach B in the handoff doc).
