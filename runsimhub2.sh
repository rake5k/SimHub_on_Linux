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
check_tools() {
    echo -e "${CYAN}Checking for required tools...${NC}"
    missing_tools=0

    if ! command -v protontricks > /dev/null 2>&1; then
        echo -e "${RED}WARNING:${NC} protontricks is not installed"
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
}

install_ge_proton() {
    TARGET_DIR="$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-34"
    ARCHIVE_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton10-34/GE-Proton10-34.tar.gz"
    ARCHIVE_NAME="GE-Proton10-34.tar.gz"

    # Check if already installed
    if [ -d "$TARGET_DIR" ]; then
        return 0
    fi
    
    echo
    echo "GE-Proton10-34 is not installed. (Recommended, way better .NET compatibility)"
    printf "Download and install it now? (y/n): "
    read -r answer

    case "$answer" in
        y|Y|yes|YES)
            mkdir -p "$HOME/.local/share/Steam/compatibilitytools.d"
            cd "$HOME/.local/share/Steam/compatibilitytools.d" || {
                echo "Failed to enter compatibilitytools.d directory."
                return 1
            }

            # Download using wget or curl
            echo "Downloading $ARCHIVE_URL (~500MB)"
            if command -v wget >/dev/null 2>&1; then
                wget "$ARCHIVE_URL" -O "$ARCHIVE_NAME" > /dev/null 2>&1
            elif command -v curl >/dev/null 2>&1; then
                curl -L "$ARCHIVE_URL" -o "$ARCHIVE_NAME" > /dev/null 2>&1
            else
                echo "Neither wget nor curl is installed. Install one of them first."
                return 1
            fi
            echo "Unpacking..."
            # Extract
            tar -xvf "$ARCHIVE_NAME" > /dev/null 2>&1
            rm "$ARCHIVE_NAME"  > /dev/null 2>&1

            echo "GE-Proton10-34 installed successfully."
            echo "Restart Steam and select GE-Proton10-34 in the game's compatibility settings."
            ;;
        *)
            echo "Installation cancelled."
            ;;
    esac
}

#Custom proton for LMU
install_ge_proton_lmu() {
    game_id="$1"
    PROTON_NAME="GE-Proton10-34-LMU-hid_fixes"
    TARGET_DIR="$HOME/.local/share/Steam/compatibilitytools.d/${PROTON_NAME}"
    ARCHIVE_URL="https://github.com/JacKeTUs/proton-ge-custom/releases/download/GE-Proton10-34-LMU-hid_fixes/GE-Proton10-34-LMU-hid_fixes.tar.gz"
    ARCHIVE_NAME="${PROTON_NAME}.tar.gz"

    if [ -d "$TARGET_DIR" ]; then
        return 0
    fi

    echo
    echo "$PROTON_NAME is not installed for game ID: $game_id - LMU won't work without it."
    printf "Download and install it now? (y/n): "
    read -r answer

    case "$answer" in
        y|Y|yes|YES)
            mkdir -p "$HOME/.local/share/Steam/compatibilitytools.d"
            cd "$HOME/.local/share/Steam/compatibilitytools.d" || {
                echo "Failed to enter compatibilitytools.d directory."
                return 1
            }

            echo "Downloading $ARCHIVE_URL (~500MB)"
            if command -v wget >/dev/null 2>&1; then
                wget "$ARCHIVE_URL" -O "$ARCHIVE_NAME" > /dev/null 2>&1
            elif command -v curl >/dev/null 2>&1; then
                curl -L "$ARCHIVE_URL" -o "$ARCHIVE_NAME" > /dev/null 2>&1
            else
                echo "Neither wget nor curl is installed."
                return 1
            fi
            
            echo "Unpacking..."
            tar -xvf "$ARCHIVE_NAME"
            rm "$ARCHIVE_NAME"

            echo "$PROTON_NAME installed successfully."
            echo "Restart Steam and select \"$PROTON_NAME\" in the compatibility options for game ID $game_id."
            ;;
        *)
            echo "Installation cancelled."
            ;;
    esac
}

#Print and select games
installed_games_detection() {
    echo -e "${CYAN}Scanning for installed games...${NC}"
    echo -e "${YELLOW}NOTE:${NC} If your game is not listed, you need to run it at least once."
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
    
    echo
    echo -e "${GREEN}You selected:${NC}"
    echo -e "${BLUE}ID:${NC} $game_id"
    echo -e "${BLUE}Name:${NC} $selected_name"
    test_proton
        
    # Check if game is running
    if pgrep -f "$game_id" > /dev/null 2>&1; then
        echo
        echo -e "${RED}ERROR: The game is currently running!${NC}"
        echo "This locks the game prefix and .NET install doesnt work"
        echo "Please close the game before installing .NET."
        echo
        printf "${MAGENTA}Press Enter to exit...${NC}"
        read -r dummy
        rm -f /tmp/steam_games_$$
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
    
    #Offer to install GE Proton if not already present:
    if [ "$game_id" = "2399420" ]; then
        install_ge_proton_lmu "$game_id"
    else
        install_ge_proton "$game_id"
    fi
}

##.NET functions:
dotnet_installed() {
    # Check if a protontricks installed dotnet48 is present:
    DOTNET_DIR="$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework/v4.0.30319"

    if [ -f "$DOTNET_DIR/mscorlib.dll" ] && [ $(stat -c%s "$DOTNET_DIR/mscorlib.dll") -gt 1000000 ]; then
        echo
        echo -e "${GREEN}Microsoft .NET Framework 4.8 appears to already be installed.${NC}"
        echo "A reinstall may be a good idea if app stopped working or install fails."

        if [ "$game_id" -eq 244210 ]; then #AC1
        echo
            echo -e "${RED}### IMPORTANT ###${NC}"
            echo "AC used with GE-Proton10-34 automatically installs a working .NET via protontricks,"
            echo "you usually dont need to reinstall it."
            echo -e "${RED}### IMPORTANT ###${NC}"
            echo
        fi
        
        printf "${YELLOW}Do you want to reinstall dotnet48 (y/N): ${NC}"
        read -r answer

        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            install_dotnet
        else
            echo -e "${CYAN}Skipping dotnet48 reinstallation.${NC}"
        fi
    else
        # Ask if user wants to install dotnet48
        echo
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
    echo "Please be patient and do not interrupt the process. (~5min)"
    protontricks "$game_id" -q --force dotnet48 > /dev/null 2>&1
    install_result=$?
    
    
    if [ "$install_result" -eq 0 ]; then
        echo -e "${GREEN}.NET 4.8 installed successfully.${NC}"
    else
        echo -e "${RED}.NET 4.8 installation failed (exit code $install_result).${NC}"
        echo
        test_proton
    fi
}

test_proton() {
    config_file="$STEAM_DIR/steamapps/compatdata/$game_id/config_info"
    if [ -f "$config_file" ]; then
        pfx=$(grep default_pfx "$config_file")
    else
        echo
        echo -e "${RED}ERROR: Could not detect Proton version from config_info."
        echo -e "You need to run the game at least once to create the prefix, exiting.${NC}"
        exit 1
    fi

    # Extract line containing game PROTON path:
    tmp="${pfx%/files/share/default_pfx/*}"
    # extract only the last path component

    PROTON_VERSION="${tmp##*/}"

    case "$game_id" in
        211500)   match_proton "RaceRoom" \
                            "GE-Proton10" ;;
                            
        2399420)  match_proton "LMU" \
                            "GE-Proton10-34-LMU-hid_fixes" ;;
                            
        3058630)  match_proton "AC EVO" \
                            "GE-Proton10" ;;
                            
        365960)   match_proton "rFactor 2" \
                            "GE-Proton10" ;;
                            
        244210)   match_proton "AC1" \
                            "GE-Proton10" ;;
        *)
    echo -e "${YELLOW}Unknown gameID:${NC} $game_id"
    ;;
esac
}

#Identifies Proton used by game, suggests changes if needed:
match_proton() {
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
        echo -e "You are using a tested Proton version for $game: ${GREEN} ${PROTON_VERSION}${NC}"
    else
        echo -e "${RED}BIG WARNING:${NC} $game was tested with this Proton(s):"
        for e in "${expected_list[@]}"; do
            echo -e "  - ${GREEN}$e${NC}"
        done
        echo  "But you are using:"
        echo -e "${RED}  - $PROTON_VERSION${NC}"
        echo -e "The script won't abort, but compatibility is not guaranteed. Likely the app won't start!"
    fi
}
