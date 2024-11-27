# Stalker2SimpleModMerger For Vortex

**Version intended to work with Vortex**

It's a simple PowerShell script that will download [repak](https://github.com/trumank/repak), [KDiff3](https://kdiff3.sourceforge.net/) and [AESDumpster](https://github.com/GHFear/AESDumpster) to detect and merge your mod.

It's based on the [mod conflict detection script](https://www.nexusmods.com/stalker2heartofchornobyl/mods/290)

**UTILISATION :**

1. **Backup manually your mods before doing anything**
2. Double clic on the shortcut **Run SMM**
3. Wait for the script to download repak, KDiff3﻿ and AESDumpster
4. Select the folder containing **Stalker2.exe**
5. The program will try to get the key for you game using AESDumpster, you have also the choice to enter the key manually
6. The will then analyze you mods to finds conflict
7. You can choose to skip the conflict, merge it with KDiff3 interface manually, or let KDiff3 try to merge automatically
8. Your merged mod will be backup in a **~backup** folder and named **.bak**


**Troubleshooting:**

- You may need to be admin or to have the right to run script on your computer for it to work properly
- Once obtained your AES Key will be saved in key.txt, delete this file if you need to change your key
- If you have trouble with the folder picker, create a gamepath.txt and manually past your game path
- You can manually download repak, KDiff3 and AESDumpster if the download is not working and place them next to the ps1 file in a 'AESDumpster' folder, a 'KDiff3-0.9.98' folder and a 'repak_cli-x86_64-pc-windows-msvc' folder



**Credit** : Alan Paradis, ﻿GHFear for [AESDumpster](https://github.com/GHFear/AESDumpster), Truman Kilen for [repak](https://github.com/trumank/repak), Joachim Eibl for [KDiff3](https://kdiff3.sourceforge.net/), DaPutzy for [mod conflict detection script](https://www.nexusmods.com/stalker2heartofchornobyl/mods/290)
