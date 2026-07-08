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
