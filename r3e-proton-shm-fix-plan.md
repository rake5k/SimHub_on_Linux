# R3E + Proton SHM Telemetry — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make SimHub, CrewChief, and dash.exe receive R3E telemetry on this NixOS fork by routing them into R3E's Proton pressure-vessel session via Steam launch options.

**Architecture:** Add an in-bwrap helper script (`r3e_launch_helpers.sh`) that R3E's Steam launch options reference via `bash -c '<helper> & exec %command%'`. The existing `runsimhub2.sh` / `runcrewchief.sh` switch to print-and-exit for R3E (AppID 211500), instructing the user to paste the launch-options string into Steam. Non-R3E behavior is unchanged.

**Tech Stack:** Bash, shellcheck, Steam Proton (GE-Proton10-34), wine64, pressure-vessel.

**Spec:** [`r3e-proton-shm-fix-design.md`](r3e-proton-shm-fix-design.md) (committed at `313bf49`).

**Repo state at plan-time:**
- Branch `nixos-support`, diverged from `origin/nixos-support` (5 vs 3).
- HEAD: `313bf49 Document R3E SHM problem and chosen fix`.
- Commit `549ecfa WIP` contains the nsenter prototype that must be reverted in Task 1.
- One stash exists (`stash@{0}: install failing`) — unrelated; leave alone.

**Working directory for all tasks:** `/home/christian/code/SimHub_on_Linux`.

**Note on tests:** This repo has no test framework. "Verification" steps use `shellcheck` for static checks and direct script invocation for smoke tests. The functional acceptance test (Task 6) is manual because it requires launching R3E via Steam.

---

## Task 1: Revert the WIP nsenter prototype

**Files:**
- Modify: `runcrewchief.sh` (via `git revert`)

- [ ] **Step 1: Confirm the WIP commit is the one to revert**

```bash
git log --oneline 549ecfa -1
```
Expected: `549ecfa WIP`

```bash
git show --stat 549ecfa
```
Expected: shows changes to `runcrewchief.sh` adding `sudo nsenter` lines.

- [ ] **Step 2: Revert the WIP commit**

```bash
git revert --no-edit 549ecfa
```
Expected: creates a new commit `Revert "WIP"` that removes the `sudo nsenter` block from `runcrewchief.sh` and restores `steam-run protontricks-launch --appid "$game" "$CrewChief_EXE" …`.

- [ ] **Step 3: Verify `runcrewchief.sh` no longer contains nsenter**

```bash
grep -n "nsenter\|RACEROOM_PID" runcrewchief.sh
```
Expected: no matches.

```bash
grep -n "steam-run protontricks-launch --appid" runcrewchief.sh
```
Expected: exactly one match in the "Launch CrewChief normally" block.

- [ ] **Step 4: shellcheck the file**

```bash
shellcheck runcrewchief.sh
```
Expected: exits 0 with no new warnings.

(Skip commit — `git revert` already created one.)

---

## Task 2: Create `r3e_launch_helpers.sh`

**Files:**
- Create: `r3e_launch_helpers.sh`

- [ ] **Step 1: Write the helper script**

Create `r3e_launch_helpers.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# r3e_launch_helpers.sh — in-bwrap helper for R3E (AppID 211500).
#
# Runs inside R3E's Proton pressure-vessel session (because Steam evaluates the
# launch-options bash inside the bwrap). Waits for R3E's wineserver to be up,
# discovers a wine launcher, then backgrounds SimHub, CrewChief, and dash.exe
# in the same bwrap so they share R3E's wineserver and can open $R3E SHM.
#
# See r3e-proton-shm-fix-design.md for the why.

set -u

R3E_APPID="211500"
LOG_DIR="$HOME/.cache/simhub-on-linux"
LOG_FILE="$LOG_DIR/r3e_launch_helpers.log"

mkdir -p "$LOG_DIR"
# Truncate and redirect own stdout/stderr to the log.
: > "$LOG_FILE"
exec >>"$LOG_FILE" 2>&1

ts() { date +%H:%M:%S; }
log() { echo "[$(ts)] $*"; }

log "== r3e_launch_helpers.sh starting (pid=$$, mnt_ns=$(readlink /proc/self/ns/mnt))"

# --- 1. Validate AppID context ------------------------------------------------
if [[ -z "${STEAM_COMPAT_DATA_PATH:-}" ]]; then
    log "FATAL: STEAM_COMPAT_DATA_PATH not set (launch options pasted to wrong game?)"
    exit 2
fi
if [[ "$(basename "$STEAM_COMPAT_DATA_PATH")" != "$R3E_APPID" ]]; then
    log "FATAL: STEAM_COMPAT_DATA_PATH=$STEAM_COMPAT_DATA_PATH does not end in /$R3E_APPID"
    exit 2
fi

WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx"
log "WINEPREFIX=$WINEPREFIX"

# --- 2. Wait for wineserver socket --------------------------------------------
log "waiting for wineserver socket in /tmp/.wine-1000/ (up to 60s)..."
socket=""
deadline=$(( $(date +%s) + 60 ))
while [[ -z "$socket" && $(date +%s) -lt $deadline ]]; do
    socket=$(ls /tmp/.wine-1000/server-*/socket 2>/dev/null | head -1)
    [[ -z "$socket" ]] && sleep 1
done
if [[ -z "$socket" ]]; then
    log "FATAL: no wineserver socket found after 60s"
    exit 3
fi
log "wineserver socket found: $socket"

# --- 3. Discover wine launcher ------------------------------------------------
wine_launcher_cmd=()
wine_strategy=""

if command -v protontricks-launch >/dev/null 2>&1; then
    wine_launcher_cmd=(protontricks-launch --no-bwrap --appid "$R3E_APPID")
    wine_strategy="protontricks-launch --no-bwrap"
elif [[ -n "${STEAM_COMPAT_TOOL_PATHS:-}" ]]; then
    proton_root="${STEAM_COMPAT_TOOL_PATHS%%:*}"
    candidate="$proton_root/files/bin/wine64"
    if [[ -x "$candidate" ]]; then
        wine_launcher_cmd=("$candidate")
        wine_strategy="STEAM_COMPAT_TOOL_PATHS -> $candidate"
    fi
fi

if [[ ${#wine_launcher_cmd[@]} -eq 0 ]]; then
    fallback="$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-34/files/bin/wine64"
    if [[ -x "$fallback" ]]; then
        wine_launcher_cmd=("$fallback")
        wine_strategy="hardcoded fallback -> $fallback"
    fi
fi

if [[ ${#wine_launcher_cmd[@]} -eq 0 ]]; then
    log "FATAL: no usable wine launcher found (tried protontricks-launch, STEAM_COMPAT_TOOL_PATHS, GE-Proton10-34 fallback)"
    exit 4
fi
log "wine launcher: ${wine_launcher_cmd[*]} (strategy: $wine_strategy)"

# --- 4. Launch helpers --------------------------------------------------------
launch_one() {
    local label="$1"
    local exe="$2"

    if [[ ! -f "$exe" ]]; then
        log "[skip] $label not installed in prefix ($exe)"
        return
    fi
    if pgrep -f "$(basename "$exe")" >/dev/null 2>&1; then
        log "[skip] $label already running"
        return
    fi
    log "[launch] $label -> $exe"
    WINEPREFIX="$WINEPREFIX" "${wine_launcher_cmd[@]}" "$exe" >>"$LOG_FILE" 2>&1 &
}

launch_one "SimHub"    "$WINEPREFIX/drive_c/Program Files (x86)/SimHub/SimHubWPF.exe"
launch_one "CrewChief" "$WINEPREFIX/drive_c/Program Files (x86)/Britton IT Ltd/CrewChiefV4/CrewChiefV4.exe"
launch_one "dash.exe"  "$HOME/.cache/dash/dash.exe"

log "== helpers spawned, exiting"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x r3e_launch_helpers.sh
```

- [ ] **Step 3: Verify with shellcheck**

```bash
shellcheck r3e_launch_helpers.sh
```
Expected: exits 0 with no warnings.

- [ ] **Step 4: Smoke test (helper refuses to run outside R3E's bwrap)**

```bash
unset STEAM_COMPAT_DATA_PATH; ./r3e_launch_helpers.sh; echo "exit=$?"
cat ~/.cache/simhub-on-linux/r3e_launch_helpers.log
```
Expected: `exit=2`, log contains `FATAL: STEAM_COMPAT_DATA_PATH not set`.

- [ ] **Step 5: Smoke test (helper refuses wrong AppID)**

```bash
STEAM_COMPAT_DATA_PATH=/tmp/123456 ./r3e_launch_helpers.sh; echo "exit=$?"
cat ~/.cache/simhub-on-linux/r3e_launch_helpers.log
```
Expected: `exit=2`, log contains `does not end in /211500`.

- [ ] **Step 6: Commit**

```bash
git add r3e_launch_helpers.sh
git commit -m "Add r3e_launch_helpers.sh for in-bwrap telemetry helpers"
```

---

## Task 3: Switch `runsimhub2.sh` to print launch-options for R3E

**Files:**
- Modify: `runsimhub2.sh` (insert R3E branch between the AppID-resolution block and `check_LMU`)

- [ ] **Step 1: Read the current state of the file**

```bash
cat runsimhub2.sh
```
Note: the existing structure is `source shared_functions.sh` → `-l` handling → AppID detection → `check_LMU` → SimHub launch → `check_Raceroom`.

- [ ] **Step 2: Insert the R3E print-and-exit block after `check_LMU`-prep and before SimHub-EXE lookup**

Replace the lines from `#If running Game is LMU check if all configs are done:` down through `check_LMU` with this block (the R3E early-exit must come BEFORE `check_LMU` so R3E's "not LMU" no-op stays free, and BEFORE the SimHub EXE existence check which is irrelevant for R3E because we don't launch from here):

```bash
#If running Game is LMU check if all configs are done:
check_LMU

###############################################
# R3E (AppID 211500): SHM telemetry requires #
# the Steam launch-options wrapper — print    #
# the string and exit.                        #
###############################################
if [[ "$game" = "211500" ]]; then
    script_dir="$(realpath "$(dirname "$0")")"
    helper="$script_dir/r3e_launch_helpers.sh"
    if [[ ! -x "$helper" ]]; then
        echo "ERROR: $helper missing or not executable."
        echo "Run: chmod +x \"$helper\""
        exit 1
    fi
    cat <<EOF

R3E telemetry note:
SimHub, CrewChief, and dash.exe must run in R3E's Proton sandbox to see its
shared-memory section. They cannot be launched post-hoc because the sandbox
has a private /tmp. Paste the following into Steam → R3E → Properties →
Launch Options (replacing any existing value), save, close Steam, and start
R3E from Steam:

bash -c '"$helper" & DXVK_FRAME_RATE=145 gamemoderun %command%'

SimHub, CrewChief, and dash.exe will launch automatically if installed.
Helper log: ~/.cache/simhub-on-linux/r3e_launch_helpers.log
EOF
    exit 0
fi
```

Use Edit with `old_string` = the existing block:
```
#If running Game is LMU check if all configs are done:
check_LMU
```
and `new_string` = the block above.

- [ ] **Step 3: Verify with shellcheck**

```bash
shellcheck runsimhub2.sh
```
Expected: exits 0 with no new warnings vs. the baseline (Task 1).

- [ ] **Step 4: Smoke test (R3E branch prints the expected string)**

```bash
./runsimhub2.sh 211500
```
Expected output:
- Contains the line `bash -c '"<absolute path>/r3e_launch_helpers.sh" & DXVK_FRAME_RATE=145 gamemoderun %command%'`.
- `<absolute path>` is the realpath of the repo (`/home/christian/code/SimHub_on_Linux`).
- Script exits 0.
- Does NOT run `protontricks-launch` (verify with `pgrep -f SimHubWPF.exe` — no new process).

- [ ] **Step 5: Smoke test (non-R3E AppID still goes through old path)**

```bash
./runsimhub2.sh 2399420  # LMU; SimHub likely not installed for LMU prefix
```
Expected: behaves exactly as before Task 3 — runs `check_LMU`, then either prompts about missing SimHub install OR launches via `steam-run protontricks-launch`. Critically, does NOT print the R3E launch-options string.

- [ ] **Step 6: Commit**

```bash
git add runsimhub2.sh
git commit -m "Print Steam launch-options string for R3E in runsimhub2.sh"
```

---

## Task 4: Switch `runcrewchief.sh` to print launch-options for R3E

**Files:**
- Modify: `runcrewchief.sh` (same pattern as Task 3)

- [ ] **Step 1: Insert the R3E print-and-exit block in the same position**

In `runcrewchief.sh`, after `check_LMU` and before `# Check if CrewChief install exists`, insert the same block as Task 3 Step 2. Use Edit with `old_string`:
```
#If running Game is LMU check if all configs are done:
check_LMU
```
and `new_string`:
```
#If running Game is LMU check if all configs are done:
check_LMU

###############################################
# R3E (AppID 211500): SHM telemetry requires #
# the Steam launch-options wrapper — print    #
# the string and exit.                        #
###############################################
if [[ "$game" = "211500" ]]; then
    script_dir="$(realpath "$(dirname "$0")")"
    helper="$script_dir/r3e_launch_helpers.sh"
    if [[ ! -x "$helper" ]]; then
        echo "ERROR: $helper missing or not executable."
        echo "Run: chmod +x \"$helper\""
        exit 1
    fi
    cat <<EOF

R3E telemetry note:
SimHub, CrewChief, and dash.exe must run in R3E's Proton sandbox to see its
shared-memory section. They cannot be launched post-hoc because the sandbox
has a private /tmp. Paste the following into Steam → R3E → Properties →
Launch Options (replacing any existing value), save, close Steam, and start
R3E from Steam:

bash -c '"$helper" & DXVK_FRAME_RATE=145 gamemoderun %command%'

SimHub, CrewChief, and dash.exe will launch automatically if installed.
Helper log: ~/.cache/simhub-on-linux/r3e_launch_helpers.log
EOF
    exit 0
fi
```

- [ ] **Step 2: Verify with shellcheck**

```bash
shellcheck runcrewchief.sh
```
Expected: exits 0.

- [ ] **Step 3: Smoke test (R3E branch)**

```bash
./runcrewchief.sh 211500
```
Expected: prints the same launch-options string as `./runsimhub2.sh 211500`, exits 0, no `protontricks-launch` spawned.

- [ ] **Step 4: Smoke test (non-R3E branch unchanged)**

```bash
./runcrewchief.sh 2399420
```
Expected: goes through CrewChief-EXE existence check and either prompts or launches via `steam-run protontricks-launch`. Does NOT print the R3E string.

- [ ] **Step 5: Commit**

```bash
git add runcrewchief.sh
git commit -m "Print Steam launch-options string for R3E in runcrewchief.sh"
```

---

## Task 5: Remove `check_Raceroom`

**Files:**
- Modify: `shared_functions.sh` (delete function `check_Raceroom`)
- Modify: `runsimhub2.sh` (remove call site)
- Modify: `runcrewchief.sh` (remove call site)

- [ ] **Step 1: Verify call sites before removal**

```bash
grep -n "check_Raceroom" runsimhub2.sh runcrewchief.sh shared_functions.sh
```
Expected: one call in `runsimhub2.sh`, one in `runcrewchief.sh`, one definition in `shared_functions.sh`.

- [ ] **Step 2: Remove the call in `runsimhub2.sh`**

Use Edit with `old_string`:
```
#If running Game is Raceroom launch dash.exe for SealHUD
check_Raceroom
```
and `new_string`: (empty)

If the surrounding blank lines look off after the edit, also remove the trailing blank line via a follow-up Edit if needed (read the file first to be sure).

- [ ] **Step 3: Remove the call in `runcrewchief.sh`**

Use Edit with the same `old_string` / `new_string` as Step 2.

- [ ] **Step 4: Delete the function from `shared_functions.sh`**

Use Edit with `old_string` = the entire `check_Raceroom` function block including its leading comment header:
```
###############################################
# RaceRoom Dash support (AppId 211500)
###############################################
check_Raceroom() {
    if [[ "$game" = "211500" ]]; then
    
    # Check if dash.exe is already running
    if pgrep -f "dash.exe" >/dev/null; then
        echo "RaceRoom dash.exe is already running!"
        exit 1
    fi
    
        echo
        echo "RaceRoom Racing Experience detected, launching Dash (For SealHUD)"
        echo ""

        CACHE_DIR="$HOME/.cache/dash"
        mkdir -p "$CACHE_DIR"

        DASH_EXE=$(find "$CACHE_DIR" -name "dash.exe" -type f 2>/dev/null | head -1)

        if [[ -z "$DASH_EXE" ]]; then
            echo "Downloading Dash..."

            if command -v wget >/dev/null; then
                wget -q "https://sealhud.github.io/dash.zip" -O "$CACHE_DIR/dash.zip"
            else
                curl -sL -o "$CACHE_DIR/dash.zip" "https://sealhud.github.io/dash.zip"
            fi

            if [[ ! -f "$CACHE_DIR/dash.zip" ]]; then
                echo "Error: Failed to download dash.zip!"
                exit 1
            fi

            echo "Extracting Dash..."
            unzip -q "$CACHE_DIR/dash.zip" -d "$CACHE_DIR"
            rm -f "$CACHE_DIR/dash.zip"

            DASH_EXE=$(find "$CACHE_DIR" -name "dash.exe" -type f 2>/dev/null | head -1)

            if [[ -z "$DASH_EXE" ]]; then
                echo "Error: dash.exe not found in extracted files!"
                exit 1
            fi
        else
            echo "Using cached Dash..."
        fi

        sleep 2

        echo "Launching dash.exe, don't forget the SealHUD entry in the Game launcher in Steam."
        WINEDEBUG=-all steam-run protontricks-launch --appid "$game" "$DASH_EXE" 2>/dev/null
    fi
}
```

⚠ Before editing, **read the function from the current file** to be sure the block matches exactly — if there were any earlier edits, the content may differ. Use:

```bash
sed -n '/^# RaceRoom Dash support/,/^}/p' shared_functions.sh
```

Then pass the exact captured block as `old_string`.

`new_string`: (empty)

If dash.exe was previously downloaded into `~/.cache/dash/` by the old code path, that cache is still used by the new helper (which expects the file at the same path). The helper does NOT download — that's a one-time step the user did long ago via the old `check_Raceroom`. Note this in the commit message.

- [ ] **Step 5: Verify all three files**

```bash
grep -n "check_Raceroom" runsimhub2.sh runcrewchief.sh shared_functions.sh
```
Expected: no matches.

```bash
shellcheck runsimhub2.sh runcrewchief.sh shared_functions.sh
```
Expected: exits 0.

- [ ] **Step 6: Commit**

```bash
git add runsimhub2.sh runcrewchief.sh shared_functions.sh
git commit -m "Remove check_Raceroom (dash.exe now launched by r3e_launch_helpers.sh)

Note: dash.exe must already be in ~/.cache/dash/dash.exe. The download path
in check_Raceroom is removed because the helper runs inside the Proton bwrap
and shouldn't be downloading things at runtime. If dash.exe isn't cached,
install it manually once (download from https://sealhud.github.io/dash.zip
and extract dash.exe into ~/.cache/dash/)."
```

---

## Task 6: Manual acceptance test

This task is manual because it requires Steam + R3E.

- [ ] **Step 1: Print the launch-options string**

```bash
./runsimhub2.sh 211500
```
Copy the `bash -c '…'` line from the output.

- [ ] **Step 2: Paste into Steam**

- Open Steam.
- Right-click RaceRoom Racing Experience → Properties → Launch Options.
- Replace the current value (the probe string from the verification phase) with the copied string.
- Close the Properties dialog (Steam saves on close).
- Quit Steam completely (so it persists `localconfig.vdf` on exit).

- [ ] **Step 3: Verify Steam saved the new launch options**

```bash
grep -A1 'LaunchOptions' ~/.steam/steam/userdata/5051778/config/localconfig.vdf | grep -B1 r3e_launch_helpers
```
Expected: one match showing the new value, no longer containing `r3e-sandbox-probe.log`.

- [ ] **Step 4: Pre-launch log truncation check**

```bash
rm -f ~/.cache/simhub-on-linux/r3e_launch_helpers.log
```
(Helper truncates anyway, but starting empty makes interpretation easier.)

- [ ] **Step 5: Start R3E from Steam and wait for the main menu**

Manual. Open Steam, click Play on R3E, wait until the R3E UI is fully loaded.

- [ ] **Step 6: Read the helper log**

```bash
cat ~/.cache/simhub-on-linux/r3e_launch_helpers.log
```
Expected lines (in order):
- `[HH:MM:SS] == r3e_launch_helpers.sh starting (pid=…, mnt_ns=mnt:[…])`
- `[HH:MM:SS] WINEPREFIX=/home/christian/.local/share/Steam/steamapps/compatdata/211500/pfx`
- `[HH:MM:SS] wineserver socket found: /tmp/.wine-1000/server-XX-…/socket`
- `[HH:MM:SS] wine launcher: … (strategy: …)`
- `[launch] SimHub …` or `[skip] SimHub …` (whichever applies)
- `[launch] CrewChief …` or `[skip] CrewChief …`
- `[launch] dash.exe …` or `[skip] dash.exe …`
- `[HH:MM:SS] == helpers spawned, exiting`

If any FATAL line appears, stop and debug — the helper log tells you which step failed and why.

- [ ] **Step 7: Functional verification (the only thing that matters)**

- SimHub window appears and shows live R3E telemetry (speed, RPM, gear, etc.) while you drive a session.
- CrewChief reacts to in-race events (lap times, position changes).
- dash.exe overlay appears in R3E (SealHUD).

If any of these is broken, note which one in the log file; the helper log will say if the helper itself failed, vs. if launch succeeded but the app didn't connect to telemetry (latter is a SimHub/CrewChief configuration issue, not this fix).

- [ ] **Step 8: Quit R3E. Verify background helpers exit with the bwrap**

```bash
pgrep -af "SimHubWPF.exe|CrewChiefV4.exe|dash.exe"
```
Expected: no matches (bwrap teardown killed them).

- [ ] **Step 9: Cleanup**

```bash
rm -f ~/r3e-sandbox-probe.log
```
(verification artifact from the design phase).

- [ ] **Step 10: Review new commits, then ask the user about push**

```bash
git log --oneline origin/nixos-support..HEAD
```
Show the new commits to the user and ask whether to push. The branch is
diverged from origin (`5 vs 3` per plan header at start) — confirm with the
user whether they want a plain push, a rebase, or to leave the branch local.
Do not push without explicit consent (per user's CLAUDE.md).

---

## Done

If all of Task 6 passed, the spec is satisfied. The R3E telemetry path now works on NixOS without `sudo`, without auto-editing Steam config, and without depending on any approach beyond Steam's own launch-options mechanism.

Future maintenance touchpoints:
- If the Proton version in the prefix changes from GE-Proton10-34, the helper's hardcoded fallback path goes stale. The first two discovery strategies (protontricks-launch, STEAM_COMPAT_TOOL_PATHS) should pick up new versions automatically; the fallback is only a safety net.
- If R3E's anti-cheat or VMProtect wrapper changes its named-mapping behavior, no script change can fix that — it'd require a new probe pass (see handoff doc).
- If Steam restructures pressure-vessel to wrap `%command%` separately from launch-options bash, approach A breaks and you'd fall back to approach B/C from the handoff doc. The verification probe pattern (mnt-ns comparison) is what you'd re-run to detect this.
