#!/usr/bin/env bash
# Manual replay of winetricks dotnet48 for the R3E prefix (wine9, no winecfg,
# null display driver to dodge Proton fs_get_gpus deadlock in 32-bit GUI procs).
set -u
# Override with R3E_PROTON_BIN=<proton>/files/bin (must be a wine9-based Proton).
W=${R3E_PROTON_BIN:-$HOME/.local/share/Steam/compatibilitytools.d/UMU-Proton-9.0-4e/files/bin}
export WINEPREFIX=$HOME/.local/share/Steam/steamapps/compatdata/211500/pfx
export WINEDEBUG=-all WINEFSYNC=0 WINEESYNC=0
K='HKLM\Software\Microsoft\Windows NT\CurrentVersion'

step() { echo "== [$(date +%H:%M:%S)] $*"; }
die() { echo "FATAL: $*" >&2; exit 1; }

# Installer exit codes: 0 = success, 3010 = success + reboot required.
check_rc() { # $1: rc, $2: label
    [ "$1" -eq 0 ] || [ "$1" -eq 3010 ] || \
        die "$2 installer failed (rc=$1). Prefix is left with null display driver and a non-win10 winver — fix the cause and re-run this script."
}

[ -x "$W/wine64" ] || die "wine64 not found at $W — set R3E_PROTON_BIN to <proton>/files/bin (see r3e-nixos-install-guide.md)"
[ -d "$WINEPREFIX" ] || die "prefix $WINEPREFIX missing — run R3E once from Steam first"

# Write/delete $K values in BOTH registry views — 32-bit processes read
# Wow6432Node (notes breakage 4: InnoSetup saw WinXP while cmd/ver saw win10).
reg_add_both() {
    "$W/wine64" reg add "$K" "$@" /f
    "$W/wine64" reg add "$K" "$@" /f /reg:32
}
reg_del_both() { # $1: value name
    "$W/wine64" reg delete "$K" /v "$1" /f 2>/dev/null
    "$W/wine64" reg delete "$K" /v "$1" /f /reg:32 2>/dev/null
}

set_winver() { # $1: xp64|win7|win10
    case "$1" in
        xp64)  ver=5.2;  build=3790;  csd="Service Pack 2"; csdhex=0x200; prod="Microsoft Windows XP"; major=;;
        win7)  ver=6.1;  build=7601;  csd="Service Pack 1"; csdhex=0x100; prod="Microsoft Windows 7"; major=;;
        win10) ver=6.3;  build=19045; csd="";               csdhex=0x0;   prod="Microsoft Windows 10"; major=10;;
    esac
    reg_add_both /v CurrentVersion /d "$ver"
    reg_add_both /v CurrentBuild /d "$build"
    reg_add_both /v CurrentBuildNumber /d "$build"
    reg_add_both /v ProductName /d "$prod"
    if [ -n "$csd" ]; then
        reg_add_both /v CSDVersion /d "$csd"
    else
        reg_del_both CSDVersion
    fi
    if [ -n "$major" ]; then
        reg_add_both /v CurrentMajorVersionNumber /t REG_DWORD /d "$major"
        reg_add_both /v CurrentMinorVersionNumber /t REG_DWORD /d 0
    else
        reg_del_both CurrentMajorVersionNumber
        reg_del_both CurrentMinorVersionNumber
    fi
    "$W/wine64" reg add 'HKLM\System\CurrentControlSet\Control\Windows' /v CSDVersion /t REG_DWORD /d "$csdhex" /f
    "$W/wine64" reg add 'HKLM\System\CurrentControlSet\Control\ProductOptions' /v ProductType /d WinNT /f
    "$W/wineserver" -w
    step "winver -> $1; ver reports: $("$W/wine64" cmd /c ver 2>/dev/null | tr -d '\r' | tr -s '\n' ' ')"
}

step "set null display driver"
"$W/wine64" reg add 'HKCU\Software\Wine\Drivers' /v Graphics /d null /f
"$W/wineserver" -w

step "set winver xp64 (for dotnet40)"
set_winver xp64

step "install dotnet40 (quiet)"
cd "$HOME/.cache/winetricks/dotnet40" \
    || die "installer cache ~/.cache/winetricks/dotnet40 missing — stage the installers first (r3e-nixos-install-guide.md step 4)"
WINEDLLOVERRIDES=fusion=b "$W/wine" dotNetFx40_Full_x86_x64.exe /q /c:"install.exe /q"
rc=$?
step "dotnet40 installer rc=$rc"
"$W/wineserver" -w
check_rc "$rc" dotnet40

"$W/wine64" reg add 'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4\Full' /v Install /t REG_DWORD /d 1 /f
"$W/wine64" reg add 'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4\Full' /v Version /d "4.0.30319" /f

step "set winver win7 (for dotnet48)"
set_winver win7

step "install dotnet48 (quiet)"
cd "$HOME/.cache/winetricks/dotnet48" \
    || die "installer cache ~/.cache/winetricks/dotnet48 missing — stage the installers first (r3e-nixos-install-guide.md step 4)"
WINEDLLOVERRIDES=fusion=b "$W/wine" ndp48-x86-x64-allos-enu.exe /sfxlang:1027 /q /norestart
rc=$?
step "dotnet48 installer rc=$rc"
"$W/wineserver" -w
check_rc "$rc" dotnet48

step "mscoree=native override + marker + winver win10 + remove null driver"
"$W/wine64" reg add 'HKCU\Software\Wine\DllOverrides' /v '*mscoree' /d native /f
touch "$WINEPREFIX/drive_c/windows/dotnet48.installed.workaround"
set_winver win10
"$W/wine64" reg delete 'HKCU\Software\Wine\Drivers' /v Graphics /f
"$W/wineserver" -w

step "verify"
mscorlib="$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/mscorlib.dll"
ls -la "$mscorlib" || die "mscorlib.dll missing after install — .NET 4.8 is NOT usable in this prefix"
step "done"
