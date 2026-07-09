#!/usr/bin/env bash

#Run the populate script:
source "$(dirname "$0")/shared_functions.sh" || exit 1

#List installed games:
if [[ "$1" == "-l" ]]; then
    protontricks -l |grep -vi Protontricks
    exit 0
fi

#Get ID of running game; a passed AppID allows running without the game running.
if [[ -n "$1" ]]; then
    # User provided an AppID → no need to auto-detect
    game="$1"
else
    # No AppID provided → detect running game
    running_game_id
fi

#If running Game is LMU check if all configs are done:
check_LMU

#If running game is R3E print the launch-options instructions and exit:
check_Raceroom

# Check if CrewChief install exists
CrewChief_EXE="$STEAM_DIR/steamapps/compatdata/$game/pfx/drive_c/Program Files (x86)/Britton IT Ltd/CrewChiefV4/CrewChiefV4.exe"

if [[ ! -f "$CrewChief_EXE" ]]; then
    echo "CrewChief is not installed for this game."
    echo "You need to run Install_CrewChief_Linux.sh."
    read -rp "Press ENTER to exit..."
    exit 1
fi

###############################################
# Launch CrewChief normally for detected game
###############################################
echo "Launching CrewChief..."
export PYTHONWARNINGS="ignore::UserWarning"
$STEAM_RUN protontricks-launch --appid "$game" "$CrewChief_EXE" >/dev/null 2>&1 &
echo "CrewChief has been launched!"
