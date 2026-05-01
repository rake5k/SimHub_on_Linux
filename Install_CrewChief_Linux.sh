#!/bin/sh

#Run the populate script:
source ./shared_functions.sh

#Check if tools like protontricks are installed:
check_tools

#Parse and list installed games:
installed_games_detection

#Check .NET installation for selected game
dotnet_installed

###########################################
# CREWCHIEF INSTALLER
###########################################
echo
printf "${YELLOW}Install CrewChief for $selected_name? (y/N): ${NC}"
read -r install_cc

if [ "$install_cc" = "y" ] || [ "$install_cc" = "Y" ]; then
    echo "Downloading CrewChief..."
    TEMP_DIR="/tmp/crewchief_install_$$"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"

    # Download CrewChief ZIP
    if which wget > /dev/null 2>&1; then
        wget -q "http://thecrewchief.org/downloads/CrewChiefV4.zip"
    else
        curl -sL -o "CrewChiefV4.zip" "http://thecrewchief.org/downloads/CrewChiefV4.zip"
    fi

    if [ ! -f "CrewChiefV4.zip" ]; then
        echo "Error: Failed to download CrewChief!"
        cd /
        rm -rf "$TEMP_DIR"
        return
    fi

    echo "Extracting CrewChief..."
    unzip -q "CrewChiefV4.zip" > /dev/null 2>&1

    # Find the EXE inside the extracted folder
    CC_EXE=$(find "$TEMP_DIR" -name "CrewChiefV4.exe" -type f)

    if [ -z "$CC_EXE" ]; then
        echo "Error: CrewChiefV4.exe not found in extracted files!"
        cd /
        rm -rf "$TEMP_DIR"
        return
    fi

    echo "Installing CrewChief..."
    echo ""
    echo -e "${RED}Make sure to press the update CrewChief Option! - This is effectivelly the installer!${NC}"

    #Running the installer:
    protontricks-launch --appid "$game_id" "$CC_EXE" > /dev/null 2>&1

    rm -rf "$TEMP_DIR"
fi
