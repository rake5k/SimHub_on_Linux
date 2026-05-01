#!/bin/bash

#Run the populate script:
source ./shared_functions.sh

#Get ID of running game:
running_game_id

#If running Game is LMU check if all configs are done:
check_LMU

# Check if SimHub install exists
SIMHUB_EXE="$STEAM_DIR/steamapps/compatdata/$game/pfx/drive_c/Program Files (x86)/SimHub/SimHubWPF.exe"

if [[ ! -f "$SIMHUB_EXE" ]]; then
    echo "SimHub is not installed for this game."
    echo "You need to run Install_Simhub_Linux.sh."
    read -p "Press ENTER to exit..."
    exit 1
fi

###############################################
# Launch SimHub normally for detected game
###############################################
echo "Launching SimHub..."
export PYTHONWARNINGS="ignore::UserWarning"
protontricks-launch --appid "$game" "$SIMHUB_EXE" >/dev/null 2>&1 &
echo "SimHub has been launched!"

#If running Game is Raceroom launch dash.exe for SealHUD
check_Raceroom
