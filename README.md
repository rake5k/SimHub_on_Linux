- A bash script to install SimHub and it's dotnet48 dependency.
- Works for most games. Even LMU custom Proton GE.
- There is also a branch here that installs CrewChief.
- You never have to run any of this as root. Do not run as root, this is Linux :)

## I highly recommend you use the bellow recommended Proton per game, SimHUB installation in other versions usually fails due to dotnet incompatibilities:
- LMU -> [GE-Proton10-34-LMU-hid_fixes](https://github.com/srounce/proton-ge-custom/releases/tag/GE-Proton10-34-LMU-hid_fixes-vr) (or later) Add then Select in the Steam Interface
- rFacto2 -> [GE-Proton10-34](https://github.com/GloriousEggroll/proton-ge-custom/releases/tag/GE-Proton10-34) (or later) Add then Select in the Steam Interface
- AC EVO ->  Proton 11.0 (Select in the Steam Interface)
- Raceroom -> Proton Experimental (Select in the Steam Interface)

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

## Running:
![Select Steam Game](running.png)

Some details:
It works but you have to install dotnet48 and SimHUB for every game prefix.
So if you have 5 race games installed, you have to install dotnet48 and SimHUB 5 times each.
There is not really so many simulators, at least for me its no big deal, as long as it works.

There is a few other options out there that bridge the shared memory from the proton prefix to
other prefixes, I tried it but it was not super easy, this script in the end does not rely on
any additional software thats not packaged on distros which makes it usually more streamlined.
