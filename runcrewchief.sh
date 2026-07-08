#!/usr/bin/env bash

#Run the populate script:
source ./shared_functions.sh

#List installed games:
if [[ "$1" == "-l" ]]; then
    protontricks -l |grep -vi Protontricks
    exit 0
fi

#Get ID of running game, adds the ability to run the without the game running.
if [[ -n "$1" ]]; then
    # User provided an AppID → no need to auto-detect
    game="$1"
else
    # No AppID provided → detect running game
    running_game_id
fi

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

# Check if CrewChief install exists
CrewChief_EXE="$STEAM_DIR/steamapps/compatdata/$game/pfx/drive_c/Program Files (x86)/Britton IT Ltd/CrewChiefV4/CrewChiefV4.exe"

if [[ ! -f "$CrewChief_EXE" ]]; then
    echo "CrewChief is not installed for this game."
    echo "You need to run Install_CrewChief_Linux.sh."
    read -p "Press ENTER to exit..."
    exit 1
fi

###############################################
# Launch CrewChief normally for detected game
###############################################
echo "Launching CrewChief..."
export PYTHONWARNINGS="ignore::UserWarning"
steam-run protontricks-launch --appid "$game" "$CrewChief_EXE" >/dev/null 2>&1 &
echo "CrewChief has been launched!"
