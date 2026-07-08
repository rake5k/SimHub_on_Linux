#!/usr/bin/env bash
# Manual replay of winetricks dotnet48 for the R3E prefix (wine9, no winecfg,
# null display driver to dodge Proton fs_get_gpus deadlock in 32-bit GUI procs).
set -u
W=$HOME/.local/share/Steam/compatibilitytools.d/UMU-Proton-9.0-4e/files/bin
export WINEPREFIX=$HOME/.local/share/Steam/steamapps/compatdata/211500/pfx
export WINEDEBUG=-all WINEFSYNC=0 WINEESYNC=0
K='HKLM\Software\Microsoft\Windows NT\CurrentVersion'

step() { echo "== [$(date +%H:%M:%S)] $*"; }

set_winver() { # $1: xp64|win7|win10
    case "$1" in
        xp64)  ver=5.2;  build=3790;  csd="Service Pack 2"; csdhex=0x200; prod="Microsoft Windows XP"; major=;;
        win7)  ver=6.1;  build=7601;  csd="Service Pack 1"; csdhex=0x100; prod="Microsoft Windows 7"; major=;;
        win10) ver=6.3;  build=19045; csd="";               csdhex=0x0;   prod="Microsoft Windows 10"; major=10;;
    esac
    "$W/wine64" reg add "$K" /v CurrentVersion /d "$ver" /f
    "$W/wine64" reg add "$K" /v CurrentBuild /d "$build" /f
    "$W/wine64" reg add "$K" /v CurrentBuildNumber /d "$build" /f
    "$W/wine64" reg add "$K" /v ProductName /d "$prod" /f
    if [ -n "$csd" ]; then
        "$W/wine64" reg add "$K" /v CSDVersion /d "$csd" /f
    else
        "$W/wine64" reg delete "$K" /v CSDVersion /f 2>/dev/null
    fi
    if [ -n "$major" ]; then
        "$W/wine64" reg add "$K" /v CurrentMajorVersionNumber /t REG_DWORD /d "$major" /f
        "$W/wine64" reg add "$K" /v CurrentMinorVersionNumber /t REG_DWORD /d 0 /f
    else
        "$W/wine64" reg delete "$K" /v CurrentMajorVersionNumber /f 2>/dev/null
        "$W/wine64" reg delete "$K" /v CurrentMinorVersionNumber /f 2>/dev/null
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
cd "$HOME/.cache/winetricks/dotnet40" || exit 1
WINEDLLOVERRIDES=fusion=b "$W/wine" dotNetFx40_Full_x86_x64.exe /q /c:"install.exe /q"
step "dotnet40 installer rc=$?"
"$W/wineserver" -w

"$W/wine64" reg add 'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4\Full' /v Install /t REG_DWORD /d 1 /f
"$W/wine64" reg add 'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4\Full' /v Version /d "4.0.30319" /f

step "set winver win7 (for dotnet48)"
set_winver win7

step "install dotnet48 (quiet)"
cd "$HOME/.cache/winetricks/dotnet48" || exit 1
WINEDLLOVERRIDES=fusion=b "$W/wine" ndp48-x86-x64-allos-enu.exe /sfxlang:1027 /q /norestart
step "dotnet48 installer rc=$?"
"$W/wineserver" -w

step "mscoree=native override + marker + winver win10 + remove null driver"
"$W/wine64" reg add 'HKCU\Software\Wine\DllOverrides' /v '*mscoree' /d native /f
touch "$WINEPREFIX/drive_c/windows/dotnet48.installed.workaround"
set_winver win10
"$W/wine64" reg delete 'HKCU\Software\Wine\Drivers' /v Graphics /f
"$W/wineserver" -w

step "verify"
ls -la "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/mscorlib.dll"
step "done"
