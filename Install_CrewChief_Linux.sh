#!/usr/bin/env bash

#Run the populate script:
source "$(dirname "$0")/shared_functions.sh" || exit 1

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
    TEMP_DIR="$HOME/.cache/crewchief_install_$$"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR" || exit 1

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
        exit 1
    fi

    # Log outside $TEMP_DIR so it survives the cleanup below
    INSTALL_LOG="$HOME/.cache/simhub-on-linux/install_crewchief.log"
    mkdir -p "$(dirname "$INSTALL_LOG")"

    echo "Extracting CrewChief..."
    unzip -q "CrewChiefV4.zip" > "$INSTALL_LOG" 2>&1

    # Find the EXE inside the extracted folder
    CC_EXE=$(find "$TEMP_DIR" -name "CrewChiefV4.exe" -type f)

    if [ -z "$CC_EXE" ]; then
        echo "Error: CrewChiefV4.exe not found in extracted files!"
        echo "See $INSTALL_LOG"
        cd /
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    echo "Installing CrewChief..."
    echo ""
    echo -e "${RED}Make sure to press the update CrewChief Option! - This is effectivelly the installer!${NC}"

    #Running the installer:
    if $STEAM_RUN protontricks-launch --appid "$game_id" "$CC_EXE" >> "$INSTALL_LOG" 2>&1; then
        echo -e "${GREEN}CrewChief installer finished.${NC}"
    else
        echo -e "${RED}CrewChief installation failed! See $INSTALL_LOG${NC}"
    fi

    rm -rf "$TEMP_DIR"
fi
