#Requires -version 5.1
##############################################
# script setup with folder picker            #
##############################################

function Test-LongPath {
    param (
        [string]$Path
    )
    try {
        [System.IO.Directory]::Exists($Path) -or [System.IO.File]::Exists($Path)
    } catch {
        Write-Host "Error checking path: $_" -ForegroundColor Red
        $false
    }
}

$IsGamePassVersion = $false

# Global variable to store the AES key
$aesKey = $null

function Get-AES-Key
{
	param (
        [string]$AESDumpsterPath,
        [string]$installPath,
        [string]$aesKeySavedPath
    )
	
	$binariesPath = [System.IO.Path]::Combine($installPath,"Stalker2\Binaries\")
    $Win64Path = [System.IO.Path]::Combine($binariesPath,"Win64\")
    $WinGDKPath = [System.IO.Path]::Combine($binariesPath,"WinGDK\")
    $stalkerExe = $null
    $exeName = $null
    # Define paths
    if ($IsGamePassVersion) {
        $stalkerExe = [System.IO.Path]::Combine($WinGDKPath,"Stalker2-WinGDK-Shipping.exe")
        $exeName = "Stalker2-WinGDK-Shipping.exe"
    }
    else {
        $stalkerExe = [System.IO.Path]::Combine($Win64Path,"Stalker2-Win64-Shipping.exe")
        $exeName = "Stalker2-Win64-Shipping.exe"
    }
    
    $copiedExe = [System.IO.Path]::Combine($AESDumpsterPath,$exeName)

	# Ensure the AESDumpster directory exists
	if (!(Test-LongPath -Path $AESDumpsterPath)) {
		New-Item -ItemType Directory -Path $AESDumpsterPath | Out-Null
	}

	# Copy the Stalker2 executable to AESDumpster directory
    if (Test-LongPath -Path $stalkerExe) {
        [System.IO.File]::Copy($stalkerExe, $copiedExe, $true)
    } else {
        Write-Output "Source executable not found: $stalkerExe"
        return
    }

    # Debugging: Confirm file was copied
    if (!(Test-LongPath -Path $copiedExe)) {
        Write-Output "Failed to copy the executable to $AESDumpsterPath."
        return
    }

	# Run AESDumpster and capture the output
	Write-Output "Running AESDumpster..."
	$aesOutput = cmd /c "echo | $aesDumpsterExe $copiedExe" 2>&1

	# Extract the AES key using a regex
	$keyPattern = "0x[0-9A-F]{64}"
	$aesKey = ($aesOutput -join "`n") -match $keyPattern | Out-Null
	$aesKey = $matches[0]

	# Display the AES key
	if ($aesKey) {
		Write-Output "Extracted AES Key: $aesKey"
		#write the key
		$aesKey | Out-File $aesKeySavedPath
		Write-Output "AES Key saved"
	} else {
		Write-Output "No AES Key found in the output."
	}
	Write-Host 
	# Optional: Clean up the copied executable
    Remove-Item -Path $copiedExe -Force
}

function Unpack-And-Clean {
    param (
        [string]$RepackPath,
        [string]$pakDir,
        [string]$basePakdDir
    )
	
	# Run the unpack command
    Write-Host "Unpacking pakchunk0-Windows.pak. This may take some time..." -ForegroundColor Yellow
    $pakchunk0 = [System.IO.Path]::Combine($pakDir,"pakchunk0-Windows.pak")
    $pakchunk0 = $pakchunk0.Substring(4)
    & $RepackExe --aes-key $aesKey "unpack" $pakchunk0
    
	if (Test-LongPath -Path $basePakdDir) {
        Write-Host "Cleaning up useless files. This may take some time..." -ForegroundColor Yellow
        # Delete all files that are not .cfg or .ini files
        $files = [System.IO.Directory]::GetFiles($basePakdDir, "*", [System.IO.SearchOption]::AllDirectories)
        foreach ($file in $files) {
            $file = [System.IO.FileInfo]::new($file)
            $extension = $file.Extension
            if ($extension -ne ".cfg" -and $extension -ne ".ini") {
                [System.IO.File]::Delete($file.FullName)
            }
        }
        # delete all empty folders and subfolders
        $dirs = [System.IO.Directory]::GetDirectories($basePakdDir, "*", [System.IO.SearchOption]::AllDirectories)
        $dirs = $dirs | Sort-Object -Property Length -Descending     
        foreach ($dir in $dirs) {
            if (Test-LongPath -Path $dir -and ) {
                $filesInDir = [System.IO.Directory]::GetFiles($dir, "*", [System.IO.SearchOption]::AllDirectories)
                $fileCount = $filesInDir.Length
                if(($fileCount -eq 0))
                {
                    [System.IO.Directory]::Delete($dir, $true)
                }
            }
        }
        Write-Host "Cleanup complete." -ForegroundColor Green
    } else {
        Write-Host "Unpacked directory not found. Ensure the unpack step was successful." -ForegroundColor Red
    }
}

function Ensure-MergedFolderStructure {
    param (
        [string]$mergedRelativePath,
        [string]$mergedFolderPath
    )
    # Make sure that every subfolder of the merged folder exists
    $folders = $mergedRelativePath.Split('\')
    $currentPath = $mergedFolderPath
    # Iterate through each folder in the relative path
    foreach ($folder in $folders) {
        # Construct the full path for the current folder
        $currentPath = [System.IO.Path]::Combine($currentPath,$folder)
        # Check if the folder exists
        if (-not (Test-LongPath -Path $currentPath)) {
            # Create the folder if it does not exist
            [System.IO.Directory]::CreateDirectory($currentPath)
        }
    }
}

function Copy-LongPathDirectory {
    param (
        [System.IO.DirectoryInfo]$sourcePath,
        [System.IO.DirectoryInfo]$destinationPath
    )

    # Create the destination directory if it doesn't exist
    $destinationDir = [System.IO.Path]::Combine($destinationPath.FullName, $sourcePath.Name)
    if (-not (Test-Path -Path $destinationDir)) {
        [System.IO.Directory]::CreateDirectory($destinationDir) | Out-Null
    }

    # Get all files and directories in the source directory
    $items = [System.IO.Directory]::EnumerateFileSystemEntries($sourcePath.FullName, '*', [System.IO.SearchOption]::AllDirectories)

    foreach ($item in $items) {
        $relativePath = $item.Substring($sourcePath.FullName.Length + 1)
        $destinationItemPath = [System.IO.Path]::Combine($destinationDir, $relativePath)

        if ([System.IO.Directory]::Exists($item)) {
            [System.IO.Directory]::CreateDirectory($destinationItemPath) | Out-Null
        } elseif ([System.IO.File]::Exists($item)) {
            try {
                [System.IO.File]::Copy($item, $destinationItemPath, $true)
            } catch {
                Write-Host "Skipping file $item because it is being used by another process."
            }
        }
    }
}

function Resolve-Conflict-And-Merge {
    param (
        [string]$modFolder,
        [string]$unpackedDir,
        [string]$KDiff3Folder,
        [string]$RepackPath,
        [System.Collections.ArrayList]$conflictingFiles,
        [System.Collections.ArrayList]$conflictingMods,
        [string]$mergeType,
        [switch]$OnlyConflicts
    )

    ###############################
    #   Setup and mod unpacking   #
    ###############################

    # Define the merged folder name
    $mergedFolderName = "zzzzzzzzzz_MERGED_MOD"
    $tempModFolder = "\\?\C:\S2SMM"
    $mergedFolderPath = [System.IO.Path]::Combine($tempModFolder,$mergedFolderName)

    # Prepare paths for unpacking
    if (-not (Test-LongPath -Path $tempModFolder)) {
        [System.IO.Directory]::CreateDirectory($tempModFolder)
    }
    else {
        # empty the folder if not empty
        $tempModFolderFiles = [System.IO.Directory]::GetFiles($tempModFolder, "*", [System.IO.SearchOption]::TopDirectoryOnly)
        $tempModFolderDirs = [System.IO.Directory]::GetDirectories($tempModFolder, "*", [System.IO.SearchOption]::TopDirectoryOnly)
        foreach ($file in $tempModFolderFiles) {
            [System.IO.File]::Delete($file)
        }
        foreach ($dir in $tempModFolderDirs) {
            [System.IO.Directory]::Delete($dir, $true)
        }
    }

    # Create the merged folder
    if (-not (Test-LongPath -Path $mergedFolderPath)) {
        [System.IO.Directory]::CreateDirectory($mergedFolderPath)
    }

    #if a there is already a merged pak, rename it to _previous
    foreach ($mod in $conflictingMods) {
        if ($mod.BaseName -eq $mergedFolderName) {
            $renamedMod = $mergedFolderName+"_previous.pak"
            $renamedModPath = [System.IO.Path]::Combine($modFolder, $renamedMod)
            #Rename-Item -Path $mod.FullName -NewName  -Force
            [System.IO.File]::Move($mod.FullName, $renamedModPath)
            #$previousMergedPak = Get-Item -Path $modFolder\zzzzzzzzzz_MERGED_MOD_previous.pak
            $previousMergedPak = [System.IO.FileInfo]::new($renamedModPath)
            #replace the mod in the conflictingMods array
            $conflictingMods[$conflictingMods.IndexOf($mod)] = $previousMergedPak
            break
        }
    }

	$unpackedDirs = @{}
    foreach ($mod in $conflictingMods) {
        $tempModPath = [System.IO.Path]::Combine($tempModFolder,$mod.Name)
        [System.IO.File]::Move($mod.FullName, $tempModPath)
        $unpackDir = [System.IO.Path]::Combine($tempModFolder,$mod.BaseName)
        if (-not (Test-LongPath -Path $unpackDir)) {
            # Unpack the mod `.pak` file into its own folder
            Write-Host "Unpacking $($mod.Name)..."
            & $RepackExe unpack $tempModPath
        }
        $unpackedDirs[$mod.FullName] = $unpackDir
    }

    # Copy everything from all mods to the merged folder
    foreach ($mod in $conflictingMods) {
        $mod = [System.IO.FileInfo]::new($mod)
        # if user selected to merge completly or if this is a previous merged pak
        if (-not $OnlyConflicts -or $mod.BaseName -eq $mergedFolderName+"_previous") {
            # copy all top level files
            $modFiles = [System.IO.Directory]::GetFiles($unpackedDirs[$mod.FullName], "*", [System.IO.SearchOption]::AllDirectories)
            foreach ($modFile in $modFiles) {
                $modFile = [System.IO.FileInfo]::new($modFile)
                # if the file is in conflictingFiles array, skip it
                foreach ($conflictingFile in $conflictingFiles) {
                    $modFileRelativePath = $modFile.FullName.Substring($unpackedDirs[$mod.FullName].Length + 1)
                    if ($modFileRelativePath -eq $conflictingFile) {
                        continue
                    }
                }
                # make sure the folder structure exists
                $modDir = $modFile.Directory.FullName
                $modDirIndex = $modDir.IndexOf($mod.BaseName)
                $folderStructure = ($modDir.Substring($modDirIndex) -split '\\', 2)[1]
                Ensure-MergedFolderStructure -mergedRelativePath $folderStructure -mergedFolderPath $mergedFolderPath.Substring(4)
                $modFile = [System.IO.FileInfo]::new($modFile)
                $destinationPath = [System.IO.Path]::Combine($mergedFolderPath, $folderStructure)
                $destinationPath = [System.IO.Path]::Combine($destinationPath, $modFile.Name)
                $destinationFile = [System.IO.FileInfo]::new($destinationPath)
                [System.IO.File]::Copy($modFile, $destinationFile, $true)
            }
        }
    }

    foreach ($conflictingFile in $conflictingFiles) {
        # Collect paths of the conflicting files
        $filePaths = @()
        foreach ($mod in $conflictingMods) {
            $unpackedDir = $unpackedDirs[$mod.FullName]
            $modFile = [System.IO.Path]::Combine($unpackedDir, $conflictingFile)
            if ([System.IO.File]::Exists($modFile)) {
                $modFile = [System.IO.FileInfo]::new($modFile)
                $filePaths += $modFile.FullName
            }
        }

        ###############################
        #  Run kdiff3 to merge files  #
        ###############################
        $mergedAbsolutePath = $null
        #remove the files name from the path
        $conflictingFileName = [System.IO.Path]::GetFileName($conflictingFile)
        $ModRelativePath = $conflictingFile.Substring(0, $conflictingFile.LastIndexOf("\")+1)
        $baseAbsolutePath = [System.IO.Path]::Combine($basePakdDir,$ModRelativePath)
        $baseFilePath = [System.IO.Path]::Combine($baseAbsolutePath,$conflictingFileName)
        $mergedAbsolutePath = [System.IO.Path]::Combine($mergedFolderPath,$ModRelativePath)
        $outputFile = [System.IO.Path]::Combine($mergedAbsolutePath, $conflictingFileName)
        $outputFile = [System.IO.FileInfo]::new($outputFile)

        # Ensure the merged folder structure exists before merging, if not we will not be able to save the merged file
        Ensure-MergedFolderStructure -mergedRelativePath $ModRelativePath -mergedFolderPath $mergedFolderPath

        Write-Host 
        Write-Host "Merging $conflictingFile..."
        $auto = ""
        if ($mergeType -eq "2") {
            $auto = "--auto"
        }
        else {
            Write-Host "Manual merge mode. Please complete the merges and close kdiff3 to continue..."
            Write-Host 
        }

        # Prepare kdiff3 arguments for manual merging
        $modName0 = Split-Path -Path $conflictingMods[0] -Leaf
        $modName1 = Split-Path -Path $conflictingMods[1] -Leaf
        # Start kdiff3 process and wait for it to finish     
        if(Test-LongPath -Path $baseFilePath) {
            Write-Host "Merging $modName0 and $modName1 with base..."
            Write-Host 
            & $KDiff3Exe $($baseFilePath.Substring(4)) $($filePaths[0].Substring(4)) $($filePaths[1].Substring(4)) -o $($outputFile.FullName.Substring(4)) $auto | Out-Null
        }
        #if base file exists, use it as the first file to merge
        else { 
            Write-Host "Base file not found. Merging without base $modName0 and $modName1..."
            Write-Host 
            & $KDiff3Exe  $($filePaths[0].Substring(4)) $($filePaths[1].Substring(4)) -o $($outputFile.FullName.Substring(4)) $auto | Out-Null
        }
        # Merge the resulting file with the remaining mods
        for ($i = 2; $i -lt $filePaths.Count; $i++) {
            # Rename the output file by adding a suffix _merged
            $outputFileName = [System.IO.Path]::GetFileNameWithoutExtension($outputFile)
            $mergedFile = $outputFileName+"_merged.cfg"
            $mergedFilePath = [System.IO.Path]::Combine($mergedAbsolutePath,$mergedFile)
            # Rename the output file to the merged file name
            [System.IO.File]::Move($outputFile, $mergedFilePath)
            $modName = Split-Path -Path $conflictingMods[$i] -Leaf
            if(Test-LongPath -Path $baseFilePath) {
                Write-Host "Merging $mergedFile and $modName1 with base..."
                & $KDiff3Exe $($baseFilePath.Substring(4)) $($mergedFilePath.Substring(4)) $($filePaths[$i].Substring(4)) -o $($outputFile.FullName.Substring(4)) $auto | Out-Null
            }
            else {
                Write-Host "Base file not found. Merging without base $mergedFile and $modName..."
                & $KDiff3Exe $($mergedFilePath.Substring(4)) $($filePaths[$i].Substring(4)) -o $($outputFile.FullName.Substring(4)) $auto | Out-Null
            }
            Write-Host 
            # Delete the merged file
            [System.IO.File]::Delete($mergedFilePath)
            
        }

        Write-Host "Manual merge completed for $conflictingFile." -ForegroundColor Green
    }
    Write-Host 
    Write-Host "Packing merged files into $mergedFolderName.pak..."
    & $RepackExe pack $mergedFolderPath
    Write-Host "Merged mod created: $mergedFolderName.pak" -ForegroundColor Green
    Write-Host 

    # repack without the conflicting files
    if ($OnlyConflicts) {
        foreach ($mod in $conflictingMods) {
            $unpackDir = $unpackedDirs[$mod.FullName]
            # Skip deletion if the directory is the merge folder
            if ($unpackDir -eq $mergedFolderPath) {
                continue
            }
            #delte previous merged pak
            $previousMergeFolderName = $mergedFolderName+"_previous"
            if ($mod.BaseName -eq $previousMergeFolderName) {
                $ModToDeletePath = [System.IO.Path]::Combine($tempModFolder, $mod.Name)
                [System.IO.File]::Delete($ModToDeletePath)
                continue
            }
            foreach ($conflictingFile in $conflictingFiles) {
                $conflictingFileName = [System.IO.Path]::GetFileName($conflictingFile)
                $conflictingFileRelativePath = $conflictingFile.Substring(0, $conflictingFile.LastIndexOf("\")+1)
                $conflictingFilePath = [System.IO.Path]::Combine($unpackDir, $conflictingFileRelativePath)
                $conflictingFileFullPaths = $null
                if(Test-LongPath -Path $conflictingFilePath) {
                    $conflictingFileFullPaths = [System.IO.Directory]::GetFiles($conflictingFilePath, $conflictingFileName, [System.IO.SearchOption]::AllDirectories)
                }
                else {
                    $conflictingFileFullPaths = [System.IO.Directory]::GetFiles($unpackDir, $conflictingFileName, [System.IO.SearchOption]::AllDirectories)
                }
                foreach ($conflictingFileFullPath in $conflictingFileFullPaths) {
                    $conflictingFileFullPath = [System.IO.FileInfo]::new($conflictingFileFullPath)
                    [System.IO.File]::Delete($conflictingFileFullPath.FullName)
                }
            }
            # Repacking the mod
            Write-Host "Repacking $($mod.Name)..."
            & "$RepackPath\repak.exe" pack $unpackDir
            Write-Host 
            $yesToAll = $false
            # Check if the directory is empty after deleting conflicting files
            $filesInDir = [System.IO.Directory]::GetFiles($unpackDir, "*", [System.IO.SearchOption]::AllDirectories)
            if ($filesInDir.Length -eq 0) {
                if(-not $yesToAll)
                {
                    Write-Host 
                    Write-Host "No remaining files in $($mod.Name) after deleting conflicts."
                    $deleteEmptyPak = Read-Host "Do you want to delete the empty .pak file for $($mod.Name)? (yes (y) / yes to all (a) / no (n))"
                    if ($deleteEmptyPak -eq "all" -Or $deleteEmptyPak -eq "a") {
                        $yesToAll = $true
                    }
                    elseif ($deleteEmptyPak -ne "yes" -Or $deleteEmptyPak -ne "y"){
                        Write-Host "Keeping the empty .pak file."
                        Write-Host 
                        continue
                    } 
                }
                Write-Host 
                Write-Host "Deleting $($mod.Name) .pak file."
                # Delete the .pak file
                $modPath = [System.IO.Path]::Combine($tempModFolder,$mod.Name)
                [System.IO.File]::Delete($modPath)
                Write-Host 
            }
        }
    }

    #move back all the pak files to the mod folder
    $tempPakFiles = [System.IO.Directory]::GetFiles($tempModFolder, "*.pak", [System.IO.SearchOption]::AllDirectories)
    foreach ($tempPakFile in $tempPakFiles) {
        $tempPakFile = [System.IO.FileInfo]::new($tempPakFile)
         #delte previous merged pak
         $previousMergeFolderName = $mergedFolderName+"_previous"
         if ($tempPakFile.BaseName -eq $previousMergeFolderName) {
             [System.IO.File]::Delete($tempPakFile.FullName)
             continue
         }
        $tempPakFile = [System.IO.FileInfo]::new($tempPakFile)
        $modPakPath = [System.IO.Path]::Combine($modFolder, $tempPakFile.Name)
        [System.IO.File]::Move($tempPakFile.FullName, $modPakPath)
    }

    foreach ($mod in $conflictingMods) {
        $unpackDir = [System.IO.Path]::Combine($tempModFolder,$mod.BaseName)
        [System.IO.Directory]::Delete($unpackDir, $true)
    }
    # Remove the merged folder if it exists
    if(Test-LongPath $mergedFolderPath) {
        [System.IO.Directory]::Delete($mergedFolderPath, $true)
    }

    if (-not $OnlyConflicts) {
        ###############################
        #         Cleaning up         #
        ###############################
        Write-Host 
        Write-Host "Cleaning and backing up pak mods..."
        # Rename conflicting mods with .bak extension and move them to a backup folder
        $backupFolder = [System.IO.Path]::Combine($modFolder,"~backup")
        if (-not (Test-LongPath $backupFolder)) {
            [System.IO.Directory]::CreateDirectory($backupFolder)
        }
        foreach ($mod in $conflictingMods) {
            $modFileBak = "$($mod.BaseName).bak"
            $fullModFileBakPath = [System.IO.Path]::Combine($backupFolder, $modFileBak)
            if ($mod.BaseName -eq $previousMergeFolderName) {
                continue
            }
            # check if bak file already exists
            if (Test-LongPath $fullModFileBakPath) {
                [System.IO.File]::Delete($fullModFileBakPath)
            }
            # Rename the mod file to .bak and move to backup folder
            [System.IO.File]::Move($($mod.FullName), $fullModFileBakPath)
        }
    }

    # Copy back all .pak files from the temporary folder to the real mod folder
    $tempPakFiles = [System.IO.Directory]::GetFiles($tempModFolder, "*.pak", [System.IO.SearchOption]::AllDirectories)
    foreach ($tempPakFile in $tempPakFiles) {
        [System.IO.File]::Move($tempPakFile.FullName, $modFolder)
    }

    Write-Host "Done" -ForegroundColor Green
}

################
# script start #
################

$KDiff3Folder = ".\KDiff3-0.9.98"
$KDiff3Exe = [System.IO.Path]::Combine($KDiff3Folder,"kdiff3.exe")
if (-Not (Test-LongPath -Path $KDiff3Folder)) {
	Write-Host "Getting KDiff3..."
	#curl.exe -L https://downloads.sourceforge.net/kdiff3/KDiff3-0.9.98.zip# > KDiff3-0.9.98.zip 
	Invoke-WebRequest -UserAgent "Wget" -Uri https://downloads.sourceforge.net/kdiff3/KDiff3-0.9.98.zip -OutFile KDiff3-0.9.98.zip 
	Expand-Archive .\KDiff3-0.9.98.zip -DestinationPath .\
	Remove-Item -Path .\KDiff3-0.9.98.zip -Force
}
else{
	Write-Host "KDiff3 found"
}

$AESDumpsterPath = ".\AESDumpster"
$AESDumpsterExe = [System.IO.Path]::Combine($AESDumpsterPath,"AESDumpster-Win64.exe")
if (-Not (Test-LongPath -Path $AESDumpsterPath)) {
	Write-Host "Getting AESDumpster..."
	Invoke-WebRequest -UserAgent "Wget" -Uri https://github.com/GHFear/AESDumpster/releases/download/1.2.5/AESDumpster-Win64.exe -OutFile AESDumpster-Win64.exe
	New-Item -Path $AESDumpsterPath -ItemType Directory
	Move-Item -Path .\AESDumpster-Win64.exe -Destination $AESDumpsterPath
}
else{
	Write-Host "AESDumpster found"
}

$RepackPath = ".\repak_cli-x86_64-pc-windows-msvc"
$RepackExe = [System.IO.Path]::Combine($RepackPath,"repak.exe")
if (-Not (Test-LongPath -Path $RepackPath)) {
	Write-Host "Getting Repack..."
	Invoke-WebRequest -UserAgent "Wget" -Uri https://github.com/trumank/repak/releases/download/v0.2.2/repak_cli-x86_64-pc-windows-msvc.zip -OutFile repak_cli-x86_64-pc-windows-msvc.zip
	Expand-Archive .\repak_cli-x86_64-pc-windows-msvc.zip -DestinationPath .\repak_cli-x86_64-pc-windows-msvc
	Remove-Item -Path .\repak_cli-x86_64-pc-windows-msvc.zip -Force
}
else{
	Write-Host "Repack found"
}

Write-Host "`nSelect folder containing Stalker2.exe or gamelaunchhelper.exe (GamePass Version)"

$installPath = $null
$pakDir = $null
$modFolder = $null
$gameSavedPath = ".\gamepath.txt"
# Check if the file exists
if (Test-LongPath -Path $gameSavedPath) {
	Write-Output "Game path file found"
	# Read the key from the file
    $gamePathFileContent = Get-Content $gameSavedPath
    if($gamePathFileContent)
    {
        $installPath = [System.IO.DirectoryInfo]::new($gamePathFileContent)
        if (Test-LongPath -Path $installPath) {
            $pakDir = [System.IO.Path]::Combine($installPath,"Stalker2\Content\Paks")
            $modFolder = [System.IO.Path]::Combine($pakDir,"~mods")
            Write-Output "Game path loaded: $installPath"
        }
    }
} else {
	Write-Output "Game path file not found."

    # Prompt user to select folder containing Stalker2.exe
    Add-Type -AssemblyName System.Windows.Forms
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = "Select folder containing Stalker2.exe or gamelaunchhelper.exe (GamePass Version)"
    $folderDialog.ShowNewFolderButton = $false

    if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $installPath = [System.IO.DirectoryInfo]::new("\\?\" + $folderDialog.SelectedPath)
        # Define the pak and mod folders based on the selected path
        $pakDir = [System.IO.Path]::Combine($installPath,"Stalker2\Content\Paks")
        $modFolder = [System.IO.Path]::Combine($pakDir,"~mods")
        #write the game path
        $installPath | Out-File $gameSavedPath
        Write-Output "Game path saved"
    } else {
        Write-Host "No folder selected. Exiting script." -ForegroundColor Red
        pause
        exit
    }
}

$stalker2EXEPath = [System.IO.Path]::Combine($installPath, "Stalker2.exe")
$GamePassPath = [System.IO.Path]::Combine($installPath, "gamelaunchhelper.exe")

if (-Not (Test-LongPath -Path $stalker2EXEPath))
{
    if (-Not (Test-LongPath -Path $GamePassPath))
    {
        Write-Host "Wrong folder selected. Select the folder with Stalker2.exe or gamelaunchhelper.exe (GamePass Version). Exiting script." -ForegroundColor Red
        pause
        exit
    }
    else {
        $IsGamePassVersion = $true
    }
}


$aesKeySavedPath = ".\key.txt"
# Check if the file exists
if (Test-LongPath -Path $aesKeySavedPath) {
	Write-Output "AES Key file found"
	# Read the key from the file
	$aesKey = Get-Content $aesKeySavedPath
	if ($aesKey) {
		Write-Output "AES Key loaded: $aesKey"
	}
} else {
	Write-Warning "Key file not found."
}

if(-Not($aesKey))
{
	# Prompt user for the AES key or grab it using the function
	$aesKeyInput = Read-Host "`nEnter the AES key in hex format (or leave blank to grab it)"
	if ([string]::IsNullOrWhiteSpace($aesKeyInput)) {
		# User left input blank, so we call the function to get the key
		Get-AES-Key -AESDumpsterPath $AESDumpsterPath -installPath $installPath -aesKeySavedPath $aesKeySavedPath
	} else {
		# User provided the key in hex format
		$aesKey = $aesKeyInput
		#write the key
		$aesKey | Out-File $aesKeySavedPath
		Write-Output "AES Key saved"
	}
}

# find all .pak files in the mod folder
$pakFiles = [System.IO.Directory]::GetFiles($modFolder, "*.pak", [System.IO.SearchOption]::AllDirectories)
# Define the unpacked directory
$basePakdDir = $null
if($IsGamePassVersion)
{
    $basePakdDir = [System.IO.Path]::Combine($pakDir,"pakchunk0-WinGDK")
}
else {
    $basePakdDir = [System.IO.Path]::Combine($pakDir,"pakchunk0-Windows")
}


if (-Not (Test-LongPath -Path $basePakdDir)) {
    Write-Host "`nUnpacking default files..."
    Unpack-And-Clean -RepackPath $RepackPath -pakDir $pakDir -basePakdDir $basePakdDir
}
else {
    Write-Host "Unpacked pakchunk0-Windows found."
}
Write-Host 

# output how many we found
Write-Host "Total .pak files found: $($pakFiles.Count)" -ForegroundColor Cyan

$results = [System.Collections.Hashtable]::new()
$conflictingMods = [System.Collections.ArrayList]::new()
$conflictingFiles = [System.Collections.ArrayList]::new()
$modFileDictionary = [System.Collections.Hashtable]::new()

foreach ($pakFile in $pakFiles) {
    $pakFile = [System.IO.FileInfo]::new($pakFile)
    # list all files in the .pak file
    $rawOutput = & $RepackExe list $pakFile.FullName.Substring(4)

    # filter out everything but the file name
    $files = $rawOutput -replace '^.*"(?:.+/)*(.*)".*$', '$1'

    foreach ($file in $files) {
        #replace / with \
        $file = $file.Replace("/","\")
        # if files don't contains \ it mean it's at the root of the pak
        if ($file -notmatch "\\") {
            Write-Host 
            Write-Host "No folder structure for $file not found in $($pakFile.FullName.Substring(4))." -ForegroundColor Red
            # ask user if he wants to try to fecth the file path from the base pak
            $fetch = Read-Host "Do you want to try to fetch the file path from the base pak? (yes/no)"
            if ($fetch -eq "yes" -Or $fetch -eq "y") {
                $baseFilePath = [System.IO.Directory]::GetFiles($basePakdDir, $file, [System.IO.SearchOption]::AllDirectories) | Select-Object -First 1
                if (-not $baseFilePath) {
                    Write-Host "Base file for $conflictingFile not found in $basePakdDir." -ForegroundColor Red
                    continue
                }
                $baseFilePath = [System.IO.FileInfo]::new($baseFilePath)
                $basePakName = "pakchunk0-Windows"
                $baseRelativePath = $baseFilePath.FullName.Substring($baseFilePath.FullName.IndexOf($basePakName) + $basePakName.Length)
                $file = $baseRelativePath.TrimStart('\')
                Write-Host "File path fetched: $file"
            } else {
                Write-Host "Skipping $file." -ForegroundColor Cyan
                continue
            }
            Write-Host 
        }
        if ($results.ContainsKey($file)) {
            [void]$results[$file].Add($pakFile)
        } else {
            $list = [System.Collections.ArrayList]::new()
            [void]$list.Add($pakFile)
            $results[$file] = $list
        }
    }

    # Add to modFileDictionary
    $modFileDictionary[$pakFile] = $files
}

# do we have a conflict
$conflict = $false

foreach ($result in $results.GetEnumerator()) {
    # more than one mod changes the given file (aka conflict)
    if ($result.Value.Count -gt 1) {
        $conflict = $true
        [void]$conflictingFiles.Add($result.Name)
        foreach ($modFile in $result.Value) {
            if (-Not($conflictingMods.Contains($modFile))) {
                [void]$conflictingMods.Add($modFile)
            }
        }
    }
}

# Output conflicting mods and files
if ($conflict) {
    Write-Host "Conflicting mods:"
    foreach ($mod in $conflictingMods) {
        Write-Host "  - $($mod.FullName.Substring(4))"
    }
    Write-Host

    Write-Host "Conflicting files:"
    foreach ($file in $conflictingFiles) {
        Write-Host "  - $file"
    }
    Write-Host

    $mergeType = Read-Host "Do you want to merge all conflicting files? (manual merge (1) / auto merge (2) / skip (3))"
    if ($mergeType -eq "1" -or $mergeType -eq "2") {
        $onlyConflicts = Read-Host "Do you want to merge only the conflicting files? (yes/no)"
        $onlyConflictsSwitch = $false
        if ($onlyConflicts -eq "yes" -Or $onlyConflicts -eq "y") {
            $onlyConflictsSwitch = $true
        }
        Resolve-Conflict-And-Merge -modFolder $modFolder -unpackedDir $unpackedDir -KDiff3Folder $KDiff3Folder -RepackPath $RepackPath -conflictingFiles $conflictingFiles -conflictingMods $conflictingMods -mergeType $mergeType -OnlyConflicts:$onlyConflictsSwitch
    } else {
        Write-Host "Merge operation skipped." -ForegroundColor Cyan
    }
} else {
    Write-Host "No conflicts found." -ForegroundColor Green
}

pause
