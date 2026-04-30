#!/bin/sh

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# SimHUB Version that will be downloaded
version=9.11.11

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

# Steam directory
STEAM_DIR="$HOME/.steam/steam"

# Parse manifest files and extract game info
echo -e "${CYAN}Scanning for installed games...${NC}"
index=0

for manifest in "$STEAM_DIR"/steamapps/appmanifest_*.acf; do
    if [ -f "$manifest" ]; then
        # Extract app ID from filename (appmanifest_XXXXX.acf)
        app_id=$(basename "$manifest" | sed 's/appmanifest_//;s/.acf//')

        # Extract game name from manifest file
        game_name=$(grep -m1 '"name"' "$manifest" | awk -F'"' '{print $4}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Filter out entries containing Steam or Proton
        if echo "$game_name" | grep -qi "Steam\|Proton"; then
            continue
        fi

        # Index:
        if [ -n "$game_name" ]; then
            # Store in temporary file instead of arrays (more portable)
            echo "$app_id|$game_name" >> /tmp/steam_games_$$
            index=$((index + 1))
        fi
    fi
done

# Check if any games were indexed:
if [ $index -eq 0 ]; then
    echo -e "${RED}No games found in Steam directory.${NC}"
    echo
    echo -e "${YELLOW}NOTE:${NC} If your game is not listed, you need to run it at least once"
    echo "and close it. This creates the necessary Proton/Wine prefix files."
    echo
    rm -f /tmp/steam_games_$$
    exit 1
fi

# Display menu
echo
echo -e "${CYAN}=== Available Games ===${NC}"
awk -F'|' '{print NR-1 "] " $1 " - " $2}' /tmp/steam_games_$$

echo
echo -e "${YELLOW}NOTE:${NC} If your game is not listed, you need to run it at least once"
echo "and close it. This creates the necessary Proton/Wine prefix files."
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
selected_id=$(echo "$selected_line" | awk -F'|' '{print $1}')
selected_name=$(echo "$selected_line" | awk -F'|' '{print $2}')

echo -e "${GREEN}You selected:${NC}"
echo -e "${BLUE}ID:${NC} $selected_id"
echo -e "${BLUE}Name:${NC} $selected_name"
echo

# Extract the path for the Proton Version used by the selected game:
PROTON_VERSION=$(cat "$STEAM_DIR/steamapps/compatdata/$selected_id/config_info" \
    | grep pfx | cut -d/ -f7- | sed 's|/files/share/default_pfx/.*||')

# Extracted path looks like:
# /compatibilitytools.d/GE-Proton10-34-LMU-hid_fixes
# /Steam/steamapps/common/Proton Hotfix
# Others, depending on what Proton is in use.

if [ -z "$PROTON_VERSION" ]; then
    echo -e "${RED}ERROR: Could not detect Proton version from config_info.${NC}"
    exit 1
fi

# Set the PROTON path variables to what the selected game uses:
PROTON_DIR="$STEAM_DIR/$PROTON_VERSION"
PROTON_WINE="$PROTON_DIR/files/bin/wine"

# Since we use winetricks:
export WINEPREFIX="$STEAM_DIR/steamapps/compatdata/$selected_id/pfx"
export STEAM_COMPAT_DATA_PATH="$STEAM_DIR/steamapps/compatdata/$selected_id"

# Sometimes the used proton variable is empty, lets make sure to populate it with in-use Proton:
export PROTON_VERSION=$(basename "$PROTON_DIR")

# Normalize Proton Experimental naming
if [ "$PROTON_VERSION" = "Proton - Experimental" ]; then
    PROTON_VERSION="Proton Experimental"
fi

get_game_proton_best_version() {
    case "$selected_id" in
        211500)   echo "Proton Experimental" ;; # R3
        2399420)  echo "GE-Proton10-34-LMU-hid_fixes or later" ;; # LMU
        3058630)  echo "Proton 11.0" ;; # AC EVO
        365960)   echo "GE-Proton10-34 or later" ;; # rF2
        *)        echo "Game not tested" ;;
    esac
}

# Print the attention message
echo -e "${YELLOW}################### ATTENTION ##################${NC}"
echo -e "${BLUE}PROTON_VERSION:${NC} $PROTON_VERSION"
echo -e "${BLUE}GAME REQUIRES:${NC} $(get_game_proton_best_version)"
echo -e "${YELLOW}#### MAKE SURE GAME IS USING THE REQUIRED #####${NC}"
echo
echo -e "${GREEN}IF BOTH LINES ARE SIMILAR/EQUAL NO ACTION IS NEEDED.${NC}"
echo -e "${GREEN}IF THERE IS A MISMATCH CHANGE THE GAME USED PROTON ON THE STEAM UI.${NC}"

echo
echo -e "${CYAN}PROTON_DIR:${NC} $PROTON_DIR"
echo -e "${CYAN}PROTON_WINE:${NC} $PROTON_WINE"
echo -e "${CYAN}GAME PREFIX:${NC} $WINEPREFIX"
echo

# Check if game is running
if pgrep -f "$selected_id" > /dev/null 2>&1; then
    echo
    echo -e "${RED}ERROR: The game is currently running!${NC}"
    echo "Please close the game before installing SimHub or dotnet48."
    echo
    printf "${MAGENTA}Press Enter to exit...${NC}"
    read -r dummy
    rm -f /tmp/steam_games_$$
    exit 1
fi

echo -e "${GREEN}Game is not running, continuing...${NC}"

# Check if game has been run at least once (Proton prefix exists)
PROTON_PREFIX="$STEAM_DIR/steamapps/compatdata/$selected_id/pfx"

if [ ! -d "$PROTON_PREFIX" ]; then
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

echo -e "${GREEN}Game prefix found, continuing...${NC}"
echo

## .NET:
dotnet_installed() {
    # Check if a winetricks installed dotnet48 is present:
    DOTNET_DIR="$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework/v4.0.30319"

    if [ -f "$DOTNET_DIR/mscorlib.dll" ] && [ $(stat -c%s "$DOTNET_DIR/mscorlib.dll") -gt 1000000 ]; then
        return 0 # Already installed
    else
        return 1 # Not installed
    fi
}

install_dotnet() {
    echo -e "${CYAN}Installing dotnet48...${NC}"
    echo "This may take 5 minutes or more depending on your hardware."
    echo "Please be patient and do not interrupt the process."
    echo
    echo -e "${YELLOW}NOTE:${NC} A popup may appear saying 'Failed to start rundll32.exe'."
    echo "This is normal and can be safely ignored. Those errors are not uncommon"
    echo "and you can always ignore by clicking No"
    echo
    "$WINE" reg delete "HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4" /f >/dev/null 2>&1 || true
    "$WINE" reg delete "HKLM\\Software\\Wow6432Node\\Microsoft\\NET Framework Setup\\NDP\\v4" /f >/dev/null 2>&1 || true
    echo -e "${CYAN}Cleared old invalid .NET registry entries. Now running dotnet48 installer, wait... (~5 min)${NC}"
    WINEPREFIX="$WINEPREFIX" winetricks -q -f dotnet48 > /dev/null 2>&1
    install_result=$?
}

if dotnet_installed; then
    echo -e "${GREEN}Microsoft .NET Framework 4.8 appears to already be installed.${NC}"
    echo "A reinstall may be a good idea if the Windows app is not working properly."
    echo
    printf "${YELLOW}Do you want to reinstall dotnet48 (y/N): ${NC}"
    read -r answer

    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        install_dotnet
    else
        echo -e "${CYAN}Skipping reinstallation.${NC}"
    fi
fi

if ! dotnet_installed; then
    # Ask if user wants to install dotnet48
    printf "${YELLOW}Install dotnet48 for $selected_name? (y/N): ${NC}"
    read -r install_dotnet
fi

if [ "$install_dotnet" = "y" ] || [ "$install_dotnet" = "Y" ]; then
    install_dotnet
elif ! dotnet_installed; then
    echo -e "${RED}dotnet48 installation not present!${NC}"
    echo -e "${RED}WARNING:${NC} dotnet48 is required for SimHub-$version to work!"
    echo
    echo -e "${YELLOW}Tip:${NC} Some games need to run at least 2 times for the dotnet48 to install properly."
    echo "Maybe start/stop the game and run this script again."
    echo
    printf "${MAGENTA}Press Enter to exit...${NC}"
    read -r dummy
    rm -f /tmp/steam_games_$$
    exit 1
fi

if ! dotnet_installed; then
    echo -e "${RED}dotnet48 missing, try again.${NC}"
    exit 1
fi

echo

## SIMHUB:
# Ask if user wants to install SimHub
printf "${YELLOW}Install SimHub-$version for $selected_name? (y/N): ${NC}"
read -r install_simhub
echo

if [ "$install_simhub" = "y" ] || [ "$install_simhub" = "Y" ]; then
    echo -e "${CYAN}Downloading SimHub-$version...${NC}"

    # Create temporary directory for download
    TEMP_DIR="/tmp/simhub_install_$$"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"

    # Download SimHub
    if command -v wget > /dev/null 2>&1; then
        wget -q "https://github.com/SHWotever/SimHub/releases/download/$version/SimHub.$version.zip"
    elif command -v curl > /dev/null 2>&1; then
        curl -sL -o "SimHub.$version.zip" "https://github.com/SHWotever/SimHub/releases/download/$version/SimHub.$version.zip"
    fi
else
    echo -e "${CYAN}SimHub-$version install cancelled, bye.${NC}"
    exit 1
fi

# Check if download was successful
if [ ! -f "SimHub.$version.zip" ]; then
    echo -e "${RED}Error: Failed to download SimHub!${NC}"
    cd /
    rm -rf "$TEMP_DIR"
    rm -f /tmp/steam_games_$$
    exit 1
fi

echo -e "${GREEN}Download completed. Extracting...${NC}"

# Extract the zip file
if command -v unzip > /dev/null 2>&1; then
    unzip -q "SimHub.$version.zip"
else
    echo -e "${RED}Error: unzip not found!${NC}"
    cd /
    rm -rf "$TEMP_DIR"
    rm -f /tmp/steam_games_$$
    exit 1
fi

# Find the SimHub Setup executable
SIMHUB_SETUP_EXE=$(find "$TEMP_DIR" -name "SimHubSetup_*.exe" -type f)

if [ -z "$SIMHUB_SETUP_EXE" ]; then
    echo -e "${RED}Error: SimHubSetup_*.exe not found in extracted files!${NC}"
    cd /
    rm -rf "$TEMP_DIR"
    rm -f /tmp/steam_games_$$
    exit 1
fi

# Display tips before installation
echo
echo -e "${CYAN}==========================================${NC}"
echo -e "${YELLOW}IMPORTANT TIPS BEFORE SIMHUB INSTALLATION${NC}"
echo -e "${CYAN}==========================================${NC}"
echo
echo -e "${GREEN}1. Make sure to uncheck: Install Microsoft .Net and C++ redistributable${NC}"
echo
echo -e "${GREEN}2. Do not run SimHub from the installer at the end, uncheck that option.${NC}"
echo -e "${RED}   Otherwise it locks the game prefix and you won't be able to start the game via Steam.${NC}"
echo -e "${GREEN}   - In case you did run it, close it and the game should start.${NC}"
echo
echo -e "${YELLOW}If you have more games, the created menu entries are unreliable due to different game prefixes.${NC}"
echo -e "${GREEN}Run it with the other provided script (runsimhub2.sh), it auto-detects the running game and proton version.${NC}"
echo -e "${CYAN}==========================================${NC}"
echo
printf "${MAGENTA}Press Enter to start the SimHub installer...${NC}"
read -r dummy
echo

echo -e "${CYAN}Installing SimHub... If rundll32.exe errors appear, you can ignore them by clicking No.${NC}"

# Run the installer
WINEPREFIX="$WINEPREFIX" winetricks -q win11 > /dev/null 2>&1
"$PROTON_WINE" "$SIMHUB_SETUP_EXE" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}SimHub installation completed successfully!${NC}"
    echo "You can update it to the latest version normally via the SimHub UI"
    echo
    echo -e "${YELLOW}To run it later with automatic game detection, run the other script called runsimhub2.sh${NC}"
    echo "You can add the runsimhub2.sh as a menu launcher"
    echo -e "${YELLOW}If in the future SimHUB randomly fails to start, run this script again and re-install dotnet48, some game/steam updates mess it.${NC}"

    # Cleanup SimHub downloaded files
    rm -rf "$TEMP_DIR"

    # Check if selected_id requires additional configuration
    if [ "$selected_id" = "2399420" ] || [ "$selected_id" = "211500" ]; then
        echo -e "${GREEN}No additional SimHub configuration is required for this game.${NC}"
    else
        echo -e "${YELLOW}You may need to configure SimHub for this game.${NC}"
        echo "In most cases, this can be done directly via SimHub:"
        echo
        echo -e "${GREEN}Game Config option -> Configure Game Now.${NC}"
    fi
else
    echo
    echo -e "${RED}SimHub installation failed or cancelled${NC}"
fi

echo

# Cleanup Global
rm -f /tmp/steam_games_$$
