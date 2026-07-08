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

# Steam launches this helper with a C locale. wine then mis-decodes non-ASCII
# filenames (e.g. CrewChief's accented driver-name .wav files), which .NET
# rejects as "Illegal characters in path" and CrewChief crashes on startup.
# Force a UTF-8 locale for the wine children unless one is already active.
if ! locale charmap 2>/dev/null | grep -qi 'utf-*8'; then
    export LC_ALL="C.UTF-8"
    log "forced LC_ALL=C.UTF-8 (was non-UTF-8; wine needs it for non-ASCII filenames)"
fi

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

# --- 2a. Ensure R3E-safe mscoree BEFORE the game starts -------------------------
# R3E's VMProtect launcher refuses to start when a native MS mscoree.dll sits
# in system32 (even with no DllOverride). The game has not started yet at this
# point, so put GE-Proton's builtin back in case a previous session left the
# native one in place (see section 4 for the full story).
NET_STASH="$HOME/.cache/simhub-on-linux/native-mscoree"
ensure_builtin_mscoree() {
    local arch dir src dst
    for arch in x64 x86; do
        [[ "$arch" == x64 ]] && dir=system32 || dir=syswow64
        src="$NET_STASH/mscoree.dll.ge-builtin.$arch"
        dst="$WINEPREFIX/drive_c/windows/$dir/mscoree.dll"
        if [[ -f "$src" ]] && ! cmp -s "$src" "$dst" 2>/dev/null; then
            cp -f "$src" "$dst" && log "restored GE builtin mscoree ($dir)"
        fi
    done
}
ensure_builtin_mscoree

# --- 2. Wait for wineserver socket --------------------------------------------
log "waiting for wineserver socket in /tmp/.wine-1000/ (up to 60s)..."
socket=""
deadline=$(( $(date +%s) + 60 ))
while [[ -z "$socket" && $(date +%s) -lt $deadline ]]; do
    socket=$(find /tmp/.wine-1000 -maxdepth 2 -path '*/server-*/socket' 2>/dev/null | head -1)
    [[ -z "$socket" ]] && sleep 1
done
if [[ -z "$socket" ]]; then
    log "FATAL: no wineserver socket found after 60s"
    exit 3
fi
log "wineserver socket found: $socket"

# --- 2b. Wait for R3E (RRRE64.exe) to be running ------------------------------
# The wineserver socket appears early, before the game itself starts. Launching
# apps into R3E's wineserver *during* the game's VMProtect startup prevents the
# game from starting at all. Detection: a wine process whose argv[0] is the
# game exe. Do NOT match comm (R3E's CEF frontend renames its main thread to
# "MainThread", so comm is never "RRRE64.exe") and do NOT pgrep -f the whole
# cmdline (Steam's reaper/proton wrappers carry RRRE64.exe in their argv long
# before the game exists) — requiring exe=wine + argv[0]=game excludes both.
wine_proc_running() { # <exe basename, case-insensitive>
    local want d exe arg0
    want="${1,,}"
    for d in /proc/[0-9]*; do
        exe=$(readlink "$d/exe" 2>/dev/null) || continue
        case "$exe" in *Proton*|*/wine*) ;; *) continue ;; esac
        IFS= read -r -d '' arg0 < "$d/cmdline" 2>/dev/null || continue
        case "${arg0,,}" in *"$want") return 0 ;; esac
    done
    return 1
}
game_running() { wine_proc_running "rrre64.exe"; }
log "waiting for RRRE64.exe process (comm match, up to 600s)..."
game_deadline=$(( $(date +%s) + 600 ))
until game_running; do
    if [[ $(date +%s) -ge $game_deadline ]]; then
        log "FATAL: RRRE64.exe not seen after 600s; not launching helpers"
        exit 5
    fi
    sleep 2
done
log "RRRE64.exe detected; settling 15s before launching helpers"
sleep 15

# --- 3. Discover wine launcher ------------------------------------------------
# Do NOT use protontricks-launch here: it is a Nix-store binary, and inside the
# Steam Runtime container LD_LIBRARY_PATH makes its Nix bash load the runtime's
# older glibc -> "symbol lookup error: __nptl_change_stack_perm". Proton's own
# wine64 is built for this runtime and connects to the running wineserver.
wine_launcher_cmd=()
wine_strategy=""

if [[ -n "${STEAM_COMPAT_TOOL_PATHS:-}" ]]; then
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
    log "FATAL: no usable wine launcher found (tried STEAM_COMPAT_TOOL_PATHS, GE-Proton10-34 fallback)"
    exit 4
fi
log "wine launcher: ${wine_launcher_cmd[*]} (strategy: $wine_strategy)"

# --- 4. Restore native .NET files ---------------------------------------------
# CrewChief and dash.exe need the real .NET CLR (wine-mono's config system
# fails to initialize -> apps self-exit). Wine loads mscoree by explicit
# system32 path, so an app-dir native mscoree is NEVER picked up (proven via
# WINEDEBUG=+loaddll) — the native dll must sit in system32/syswow64, chosen
# per-app via HKCU\AppDefaults\<exe>\DllOverrides mscoree=native,builtin
# (R3E has no override and keeps using the builtin).
# BUT: a native mscoree in system32 at GAME LAUNCH stops R3E's VMProtect
# launcher, even with no override. Mid-session the swap is harmless (verified
# live). Hence: builtin at launch (section 2a), native swapped in only after
# the game is up, builtin restored after a grace period (section 5b).
# machine.config is .NET-only (R3E never reads it) and may be clobbered by
# GE-Proton's prefix refresh, so restore it each launch.
restore_net_file() { # <stash-file> <dest-path> <label>
    local src="$1" dst="$2" label="$3"
    if [[ -f "$src" ]] && ! cmp -s "$src" "$dst" 2>/dev/null; then
        mkdir -p "$(dirname "$dst")"
        cp -f "$src" "$dst" && log "restored $label"
    fi
}
if [[ -f "$NET_STASH/mscoree.dll.x86" ]]; then
    restore_net_file "$NET_STASH/machine.config.x64" "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/Config/machine.config" "machine.config (64-bit)"
    restore_net_file "$NET_STASH/machine.config.x86" "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework/v4.0.30319/Config/machine.config" "machine.config (32-bit)"
    restore_net_file "$NET_STASH/mscoree.dll.x64" "$WINEPREFIX/drive_c/windows/system32/mscoree.dll" "native mscoree (system32)"
    restore_net_file "$NET_STASH/mscoree.dll.x86" "$WINEPREFIX/drive_c/windows/syswow64/mscoree.dll" "native mscoree (syswow64)"
else
    log "WARNING: native .NET stash missing ($NET_STASH); .NET apps may run under wine-mono"
fi

# --- 5. Launch helpers --------------------------------------------------------
launch_one() {
    local label="$1"
    local exe="$2"
    shift 2  # remaining args are passed to the exe

    if [[ ! -f "$exe" ]]; then
        log "[skip] $label not installed in prefix ($exe)"
        return
    fi
    # Wine-process check only — pgrep -f would match ANY process whose argv
    # mentions the exe name (e.g. a shell monitoring this very setup).
    if wine_proc_running "$(basename "$exe")"; then
        log "[skip] $label already running"
        return
    fi
    log "[launch] $label -> $exe (log: $LOG_DIR/$label.log)"
    # LD_PRELOAD= drops the 32-bit gameoverlayrenderer.so that floods the log.
    # WINEFSYNC/WINEESYNC must match R3E's wineserver (Proton enables fsync,
    # but its env is not inherited by the launch-options bash).
    # Pipe (not file-redirect) stdout: wine 10 + glibc 2.42 segfaults querying
    # the name of file-backed std handles in 32-bit processes. Each child gets
    # its own log so failures can be attributed to a specific app.
    LD_PRELOAD='' WINEFSYNC=1 WINEESYNC=1 WINEPREFIX="$WINEPREFIX" \
        "${wine_launcher_cmd[@]}" "$exe" "$@" 2>&1 | cat >"$LOG_DIR/$label.log" &
}

# SimHub is intentionally NOT launched: its WPF UI requires the native mscoree
# in system32, which breaks R3E's VMProtect launcher (see section 4). Telemetry
# is provided by CrewChief; dash.exe (SealHUD) is the overlay.
# SKIP_UPDATES: CrewChief's startup update check crashes under this wine
# (c0000005 during the NTLM/HTTP path; ntlm_auth is broken inside the runtime).
log "[skip] SimHub disabled (WPF needs system32 native mscoree, which breaks R3E)"
launch_one "CrewChief" "$WINEPREFIX/drive_c/Program Files (x86)/Britton IT Ltd/CrewChiefV4/CrewChiefV4.exe" SKIP_UPDATES
launch_one "dash.exe"  "$HOME/.cache/dash/dash.exe"

# --- 5b. Restore R3E-safe mscoree once the game exits --------------------------
# The on-disk mscoree only matters for NEW .NET processes (running apps keep
# the mapped native copy), but leave it untouched during the session to avoid
# any interaction with the game. Restoring after game exit keeps the prefix
# safe for a plain (helper-less) game launch. Section 2a re-does this at every
# helper start anyway, in case this guard never fires (crash, reboot).
(
    while game_running; do sleep 30; done
    ensure_builtin_mscoree
    log "== game exited; builtin mscoree restored, background guard done"
) &

log "== helpers spawned, exiting"
