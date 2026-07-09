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

# Check if SimHub install exists
SIMHUB_EXE="$STEAM_DIR/steamapps/compatdata/$game/pfx/drive_c/Program Files (x86)/SimHub/SimHubWPF.exe"

if [[ ! -f "$SIMHUB_EXE" ]]; then
    echo "SimHub is not installed for this game."
    echo "You need to run Install_Simhub_Linux.sh."
    read -rp "Press ENTER to exit..."
    exit 1
fi

###############################################
# Launch SimHub normally for detected game
###############################################
echo "Launching SimHub..."
export PYTHONWARNINGS="ignore::UserWarning"
$STEAM_RUN protontricks-launch --appid "$game" "$SIMHUB_EXE" >/dev/null 2>&1 &
echo "SimHub has been launched!"
