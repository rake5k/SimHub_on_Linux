- A bash script to install SimHub and it's dotnet48 dependency for Steam games running under Proton/Wine.
- Works for all games. Even LMU custom Proton GE.
- For Proton consider using https://github.com/gloriouseggroll/proton-ge-custom/releases as those builds are much more compatible with dotne48 compared to the default ones installed by Steam. Its quite simple, dowload a release like GE-Proton10-34.tar.gz and unpack it to ~/.steam/steam/compatibilitytools.d/ restart steam and it should appear as option.
- This also works if you only want to install dotnet48 into a Steam game. You can also opt to only reinstall/fix dotnet48 on a prefix.
- There is also a branch here that installs CrewChief.
- You never have to run any of this as root. Do not run as root, this is Linux :)

![Select Steam Game](screenshot.png)

## Requirements, those are automatically checked:

- `protontricks`
- `wget` or `curl`
- `unzip`

## Features:

- `Scans installed Steam games`
- `Checks if game has been run before to confirm a populated game prefix exists`
- `Installs dotnet48 if not already present, clears Steam fake-dotnet stub`
- `Downloads and installs SimHub 9.11.11`
- `Gives instructions on what SimHub components to install`
- `Detects installed game used proton version, even LMU custom Proton-GE`
- `Automatically adds plugins and configures LMU`
- `Automatically adds dash.exe for RaceRomm SealHUD usage`

## How to Install && run. Copy Pasta should work:
```bash
git clone https://github.com/srlemke/SimHub_on_Linux.git
cd SimHub_on_Linux/
chmod +x Install_Simhub_Linux.sh runsimhub2.sh
./Install_Simhub_Linux.sh
./runsimhub2.sh
```

- You probably can add runsimhub2.sh command to a menu laucher with icon.
- If it fails, try the above tip about using Proton-GE as it is waaaay more compatible and usually newer.

## Running:
![Select Steam Game](running.png)

Some details:
It works but you have to install dotnet48 and SimHUB for every game prefix.
So if you have 5 race games installed, you have to install dotnet48 and SimHUB 5 times each.
There is not really so many simulators, at least for me its no big deal, as long as it works.

There is a few other options out there that bridge the shared memory from the proton prefix to
other prefixes, I tried it but it was not super easy, this script in the end does not rely on
any additional software thats not packaged on distros which makes it usually more streamlined.
