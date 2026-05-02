#!/bin/sh

# SimHUB Version that will be downloaded
version=9.11.11

#Run the populate script:
source ./shared_functions.sh

#Check if tools like protontricks are installed:
check_tools

#Parse and list installed games:
installed_games_detection

#Check .NET installation for selected game
dotnet_installed

# Ask if user wants to install SimHub
echo
printf "${YELLOW}Install SimHub-$version for $selected_name? (y/N): ${NC}"
read -r install_simhub

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
    clean_tmp
    exit 1
fi

echo -e "${GREEN}Download completed. Extracting...${NC}"

# Extract the zip file
if command -v unzip > /dev/null 2>&1; then
    unzip -q "SimHub.$version.zip"
else
    echo -e "${RED}Error: unzip not found!${NC}"
    clean_tmp
    exit 1
fi

# Find the SimHub Setup executable
SIMHUB_SETUP_EXE=$(find "$TEMP_DIR" -name "SimHubSetup_*.exe" -type f)

if [ -z "$SIMHUB_SETUP_EXE" ]; then
    echo -e "${RED}Error: SimHubSetup_*.exe not found in extracted files!${NC}"
    clean_tmp
    exit 1
fi

# Display tips before installation
echo -e "${CYAN}==========================================${NC}"
echo -e "${RED}IMPORTANT TIPS BEFORE SIMHUB INSTALLATION${NC}"
echo -e "${CYAN}==========================================${NC}"
echo "1. On the Installer, make sure to uncheck: Install Microsoft .Net and C++ redistributable"
echo "2. If you run SimHUB from the installer the game wont start due locked prefix: Close SimHUB, start the game, start SimHUB."
echo -e "${CYAN}==========================================${NC}"
echo
printf "${MAGENTA}Press Enter to start the SimHub installer...${NC}"
read -r dummy

echo -e "Installing SimHub... If rundll32.exe popups appear click No"
#Seems setting windows11 is sometimes required, probable depends on proton version:
#protontricks "$game_id" -q win11 >/dev/null 2>&1;

# Run the SimHUB installer
if protontricks-launch --appid "$game_id" "$SIMHUB_SETUP_EXE" >/dev/null 2>&1; then
    echo -e "${GREEN}SimHub installation completed successfully!${NC}"
    echo
    echo -e "Tip: To run it later with automatic game detection, run the other script called ${GREEN}runsimhub2.sh${NC}"
    echo -e "Tip: You can add the ${GREEN}runsimhub2.sh${NC} as a menu launcher."
    echo "Tip: If you have more games, the created menu entries are unreliable due to different game prefixes."
    echo "Tip: If in the future, after game updates, SimHUB fails to start, run this script again and re-install dotnet48 only."
    
    # Check if game_id requires additional configuration
    if [ "$game_id" = "211500" ]; then
        echo
        echo -e "${GREEN}No additional SimHub configuration is required for this game.${NC}"
    fi
    
    if [ "$game_id" = "2399420" ]; then
        echo
        echo -e "run ${GREEN} runsimhub2.sh${NC} and it will do all LMU needed configs."
    fi
else
    echo
    echo -e "${RED}SimHub installation failed or cancelled${NC}"
fi

clean_tmp() {
    rm -rf "$TEMP_DIR"
    rm -f /tmp/steam_games_$$
}

clean_tmp
