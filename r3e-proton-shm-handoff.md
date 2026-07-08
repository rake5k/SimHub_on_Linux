# R3E + Proton SHM Telemetry — Session Handoff

## Goal
Make external telemetry consumers (CrewChief, SimHub, or a custom Linux dashboard)
receive R3E (RaceRoom Racing Experience) shared-memory data when R3E is running via
Steam Proton on Linux. Previous attempt: the project
[srlemke/SimHub_on_Linux](https://github.com/srlemke/SimHub_on_Linux) — does not work
for R3E (does not deliver telemetry; SimHub starts but receives nothing).

## Environment
- Host: NixOS, user `christian` (uid 1000)
- Steam dir: `/home/christian/.local/share/Steam`
- R3E AppID: `211500`
- Proton: `GE-Proton10-34` at
  `~/.local/share/Steam/compatibilitytools.d/GE-Proton10-34/`
- R3E WINEPREFIX: `~/.local/share/Steam/steamapps/compatdata/211500/pfx/`
- Sync mode in this prefix: `WINENTSYNC=1 WINEESYNC=1 WINEFSYNC=1`
- protontricks / protontricks-launch are installed and on PATH

## Established facts (verified this session)

1. R3E launches with no special flags — just `RRRE64.exe`.
2. `RRRE64.exe` is wrapped by `protect.dll` / `protect.exe` (VMProtect-style).
   No `$R3E` / `$Race$` literal is visible in any binary on disk → static analysis
   cannot confirm or deny that R3E creates a named mapping.
3. R3E's `/proc/<pid>/maps` contains many `memfd:wine-mapping (deleted)` regions —
   consistent with modern Wine implementing `CreateFileMapping(NULL, …, name)` via
   `memfd_create`. Cannot identify *which* memfd corresponds to the R3E SHM from
   outside without wineserver access.
4. R3E runs inside a pressure-vessel sandbox with a **private tmpfs at `/tmp`**:
   ```
   /tmp rw,nosuid,nodev,relatime - tmpfs tmpfs rw,mode=755,uid=1000,gid=100
   ```
   The wineserver socket lives at
   `/tmp/.wine-1000/server-34-<id>/socket` inside that tmpfs and is therefore
   invisible from the host.
5. `/dev/shm` *is* shared with the host (`master:14`), so fsync metadata
   (e.g. `/dev/shm/wine-29ef865-fsync`) is visible — but modern Wine does **not**
   put named file mappings in `/dev/shm`. They use memfd, scoped to the wineserver.
6. `srlemke/SimHub_on_Linux` is **not** native Linux. Its two launch scripts
   (`runsimhub2.sh`, `runcrewchief.sh`) reduce to:
   ```bash
   protontricks-launch --appid "$game" "$EXE" >/dev/null 2>&1 &
   ```
   It runs the Windows SimHub / CrewChief under Proton, targeting the same
   WINEPREFIX as the running game.
7. **`protontricks-launch --appid` does not share the running game's sandbox.**
   It spawns a fresh `bwrap`/pressure-vessel session with its own private `/tmp`,
   so a new wineserver starts. Empirically demonstrated: see "Probe results".
8. Therefore SimHub/CrewChief launched this way for R3E will start fine but
   cannot see R3E's named file mapping. No issues are filed about this on the
   repo, but the launcher never verifies connectivity, so silence is expected.

## Root cause (one-liner)

Pressure-vessel gives each Proton session a private `tmpfs /tmp`, which means
each session has its own wineserver socket and its own kernel-object namespace.
R3E's telemetry SHM is a Wine named file-mapping (wineserver-scoped). Any reader
not in R3E's sandbox sees a different wineserver and cannot resolve the name.

## Probe used (still on disk)

`/tmp/r3e-probe/probe.c` — calls `OpenFileMappingA` on candidate names, writes
results to `C:\probe.out` inside the prefix. Built with:

```bash
nix shell nixpkgs#pkgsCross.mingwW64.buildPackages.gcc --command bash -c '
  x86_64-w64-mingw32-gcc -O2 -s -o probe.exe probe.c \
    -L/nix/store/1wgzp6d17dx2kh4w17qndysm7khjy25a-mcfgthread-x86_64-w64-mingw32-2.1.1/lib'
```

Names tested: `$R3E`, `Local\$R3E`, `Global\$R3E`, `$Race$`, `Local\$Race$`,
`$RaceRoom$`. The official R3E API header
(`sector3-studios/r3e-api/r3e.h`) defines the section as `$R3E`.

## Probe results (with R3E running, PID 13230)

Launched via:
```
protontricks-launch --no-term --appid 211500 /home/christian/probe.exe
```

Wine banner included:
```
fsync: warning: a previous shm file /wine-29ef865-fsync was not properly removed
fsync: up and running.
```
(i.e. a *new* wineserver started; it did not connect to R3E's.)

`C:\probe.out` content:
```
FAIL $R3E                     err=2
FAIL Local\$R3E               err=2
FAIL Global\$R3E              err=2
FAIL $Race$                   err=2
FAIL Local\$Race$             err=2
FAIL $RaceRoom$               err=2
```

`err=2` = `ERROR_FILE_NOT_FOUND`. Adding `--no-bwrap` made no difference.

## Approaches that will NOT work
- Running CrewChief / SimHub natively on Linux against R3E's SHM.
- Running them via `protontricks-launch --appid 211500` (= what
  `SimHub_on_Linux` does). Wrong sandbox.
- Side-launching via Lutris / Heroic / manual Proton invocation after R3E is up.
  Same sandbox problem.
- Looking in `/dev/shm` for the section. Not how modern Wine backs named mappings.

## Approaches that should work — in priority order

### A. Steam launch-options wrapper (lowest effort, most reliable)
Set R3E's Steam launch options to something like:
```
bash -c 'wine "/path/to/SimHub/SimHubWPF.exe" & exec %command%'
```
Steam wraps the whole command in one pressure-vessel session, so the wrapped wine
process shares R3E's `/tmp` and wineserver. SimHub must be installed inside
R3E's prefix (Install_Simhub_Linux.sh from the repo already does that). Replace
SimHub with CrewChief or a custom Wine-side bridge as needed.

This is also the right way to patch `srlemke/SimHub_on_Linux` properly: install
a launch-option wrapper instead of post-hoc `protontricks-launch`.

### B. Wine-side telemetry bridge over UDP/TCP
Small Win32 app (~150 lines of C) that:
- Opens `$R3E` via `OpenFileMappingA`
- `MapViewOfFile` and copies the struct each tick
- Sends over UDP to `127.0.0.1:<port>` (host loopback is shared)

Launched the same way as (A). Native Linux consumers then read UDP and never
touch the Wine namespace. Cleanest if you want native Linux dashboards.

The R3E shared struct layout is in
`https://github.com/sector3-studios/r3e-api/blob/master/r3e.h` — copy verbatim,
no reverse engineering needed.

### C. nsenter into R3E's mount namespace
`nsenter -t <r3e-pid> -m -- …` while R3E is running. Pressure-vessel uses user
namespaces, so this *may* work unprivileged on this kernel; if not, requires
`CAP_SYS_ADMIN`. Brittle. Use only as last-resort diagnostic, not as a real
solution.

## What is on disk from this session
- `/tmp/r3e-probe/probe.c` — the probe source
- `/tmp/r3e-probe/probe.exe` — built binary (43.5 KB PE32+)
- Prefix-side copy at `…/compatdata/211500/pfx/drive_c/probe.exe` and the
  output `…/probe.out` were deleted at end of session.

## Open questions worth answering in the next session
- Confirm the R3E SHM name is actually `$R3E` (per `r3e-api/r3e.h`) and not a
  newer variant by running the probe via approach (A) — same sandbox — and
  checking which name resolves.
- Sketch the UDP bridge in C (~150 LOC) and the Linux-side consumer.
- Decide whether to upstream a fix to `srlemke/SimHub_on_Linux` (launch-options
  wrapper) or to publish a standalone bridge.

## User context
- Senior NixOS user, comfortable with low-level investigation, sim-racer
  (R3E + likely LMU based on the script's LMU references).
- Was running R3E live during this investigation.
- Prior attempt used `srlemke/SimHub_on_Linux` and found no telemetry reached
  SimHub.
