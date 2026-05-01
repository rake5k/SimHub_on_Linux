#!/bin/sh

# Steam directory
STEAM_DIR="$HOME/.steam/steam"

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Check for required tools
echo -e "${CYAN}Checking for required tools...${NC}"
missing_tools=0

if ! command -v protontricks > /dev/null 2>&1; then
    echo -e "${RED}WARNING:${NC} protontricks is not installed"
    missing_tools=1
fi

if ! command -v winetricks > /dev/null 2>&1; then
    echo -e "${RED}WARNING:${NC} winetricks is not installed"
    missing_tools=1
fi

if ! command -v wget > /dev/null 2>&1 && ! command -v curl > /dev/null 2>&1; then
    echo -e "${RED}WARNING:${NC} wget or curl is not installed (needed for downloads)"
    missing_tools=1
fi

if [ $missing_tools -eq 1 ]; then
    echo
    printf "${YELLOW}Continue anyway? (y/N): ${NC}"
    read -r reply
    echo
    if [ "$reply" != "y" ] && [ "$reply" != "Y" ]; then
        exit 1
    fi
fi

# Parse manifest files and extract game info
echo -e "${CYAN}Scanning for installed games...${NC}"
index=0

for manifest in "$STEAM_DIR"/steamapps/appmanifest_*.acf; do
    if [ -f "$manifest" ]; then
        # Extract game ID from filename (appmanifest_XXXXX.acf)
        game_id=$(basename "$manifest" | sed 's/appmanifest_//;s/.acf//')

        # Extract game name from manifest file
        game_name=$(grep -m1 '"name"' "$manifest" | awk -F'"' '{print $4}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Filter out entries containing Steam or Proton
        if echo "$game_name" | grep -qi "Steam\|Proton"; then
            continue
        fi

        # Index:
        if [ -n "$game_name" ]; then
            # Store in temporary file instead of arrays (more portable)
            echo "$game_id|$game_name" >> /tmp/steam_games_$$
            index=$((index + 1))
        fi
    fi
done

# Check if any games were indexed:
if [ $index -eq 0 ]; then
    echo -e "${RED}No games found in Steam directory.${NC}"
    echo
    echo -e "${YELLOW}NOTE:${NC} If your game is not listed, you need to run it at least once."
    echo
    rm -f /tmp/steam_games_$$
    exit 1
fi

# Display menu
echo
echo -e "${CYAN}=== Available Games ===${NC}"
awk -F'|' '{print NR-1 "] " $1 " - " $2}' /tmp/steam_games_$$

echo
echo -e "${YELLOW}NOTE:${NC} If your game is not listed, you need to run it at least once."
echo

# Get user selection
printf "${CYAN}Select a game (0-$((index - 1))): ${NC}"
read -r selection

# Validate selection
if ! [ "$selection" -ge 0 ] 2>/dev/null || [ "$selection" -ge "$index" ]; then
    echo -e "${RED}Invalid selection, closing.${NC}"
    rm -f /tmp/steam_games_$$
    exit 1
fi

# Display selected game
selected_line=$(sed -n "$((selection + 1))p" /tmp/steam_games_$$)
game_id=$(echo "$selected_line" | awk -F'|' '{print $1}')
selected_name=$(echo "$selected_line" | awk -F'|' '{print $2}')

echo -e "${GREEN}You selected:${NC}"
echo -e "${BLUE}ID:${NC} $game_id"
echo -e "${BLUE}Name:${NC} $selected_name"

#Get Proton Version used by this game:
pfx=$(grep default_pfx "$STEAM_DIR"/steamapps/compatdata/"$game_id"/config_info)

# strip everything up to the Proton folder
tmp="${pfx%/files/share/default_pfx/*}"

# extract only the last path component
PROTON_VERSION="${tmp##*/}"

if [ -z "$PROTON_VERSION" ]; then
    echo -e "${RED}ERROR: Could not detect Proton version from config_info.${NC}"
    exit 1
fi

# Check/populate if game has been run at least once (WINEPREFIX exists)
WINEPREFIX="$STEAM_DIR/steamapps/compatdata/$game_id/pfx"
export WINEPREFIX

if [ ! -d "$WINEPREFIX" ]; then
    echo
    echo -e "${RED}ERROR: Game has never been run before!${NC}"
    echo "Please run the game at least once and close it."
    echo "This creates the necessary Proton/Wine prefix files."
    echo
    printf "${MAGENTA}Press Enter to exit...${NC}"
    read -r dummy
    rm -f /tmp/steam_games_$$
    exit 1
fi

##.NET functions:
dotnet_installed() {
    # Check if a winetricks installed dotnet48 is present:
    DOTNET_DIR="$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework/v4.0.30319"

    if [ -f "$DOTNET_DIR/mscorlib.dll" ] && [ $(stat -c%s "$DOTNET_DIR/mscorlib.dll") -gt 1000000 ]; then
        echo
        echo -e "${GREEN}Microsoft .NET Framework 4.8 appears to already be installed.${NC}"
        echo "A reinstall may be a good idea if app stopped working or install fails."
        echo
        printf "${YELLOW}Do you want to reinstall dotnet48 (y/N): ${NC}"
        read -r answer

        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            install_dotnet
        else
            echo -e "${CYAN}Skipping dotnet48 reinstallation.${NC}"
        fi
    else
        # Ask if user wants to install dotnet48
        printf "${YELLOW}Install dotnet48 for $selected_name? (Required) (y/N): ${NC}"
        read -r answer
        
        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            install_dotnet
        else
            echo -e "${CYAN}Skipping Installation. SimHUB and CrewChief won't work!${NC}"
        fi
    fi
}

install_dotnet() {
    echo -e "${CYAN}Installing dotnet48...${NC}"
    echo "Please be patient and do not interrupt the process."
    wine reg delete "HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4" /f >/dev/null 2>&1 || true
    wine reg delete "HKLM\\Software\\Wow6432Node\\Microsoft\\NET Framework Setup\\NDP\\v4" /f >/dev/null 2>&1 || true
    echo -e "${CYAN}Cleared old invalid .NET registry entries. Now running dotnet48 installer, wait... (~5 min)${NC}"
    winetricks -q -f dotnet48 > /dev/null 2>&1
    install_result=$?
    
    if [ "$install_result" -eq 0 ]; then
        echo -e "${GREEN}.NET 4.8 installed successfully.${NC}"
    else
        echo -e "${RED}.NET 4.8 installation failed (exit code $install_result).${NC}"
        echo "This usually means Wine or winetricks hit an error."
        echo "You may need to rerun the script or check your Wine prefix."
    fi
}

#Identifies Proton used by game, suggests changes if needed:
check_proton() {
    local game="$1"
    shift
    local expected_list=("$@")

    local match=false
    for expected in "${expected_list[@]}"; do
        if [[ "$PROTON_VERSION" == *"$expected"* ]]; then
            match=true
            break
        fi
    done

    if [[ "$match" == true ]]; then
        echo -e "${GREEN}You are using a tested Proton version for $game: ${PROTON_VERSION}${NC}"
    else
        echo -e "${RED}BIG WARNING:${NC} $game was tested with:"
        for e in "${expected_list[@]}"; do
            echo -e "  - ${GREEN}$e${NC}"
        done
        echo -e "But you are using: ${RED}$PROTON_VERSION${NC}"
        echo -e "The script won't abort, but compatibility is not guaranteed. Likely the app won't work!"
    fi
}

case "$game_id" in
    211500)   check_proton "RaceRoom" \
                        "Proton Experimental" \
                        "11.0" ;;
    2399420)  check_proton "LMU" \
                        "GE-Proton10-34-LMU-hid_fixes" ;;
    3058630)  check_proton "AC EVO (Unreliable ATM)" \
                        "11.0" ;;
    365960)   check_proton "rFactor 2" \
                        "GE-Proton10" ;;
    244210)   check_proton "AC1" \
                        "GE-Proton10" ;;
    *)
        echo -e "${YELLOW}Unknown gameID:${NC} $game_id"
        ;;
esac

#Check dotnet
dotnet_installed
