##############################################
# script setup with folder picker            #
##############################################

# Global variable to store the AES key
$aesKey = $null

function Get-AES-Key
{
	param (
        [string]$AESDumpsterPath,
        [string]$installPath,
        [string]$aesKeySavedPath
    )
	
	$binariesPath = Join-Path -Path $installPath -ChildPath "Stalker2\Binaries\"
	$Win64Path = Join-Path -Path $binariesPath -ChildPath "Win64\"
	$WinGDKPath = Join-Path -Path $binariesPath -ChildPath "WinGDK\"
	$stalkerExe = $null
    $exeName = $null
	# Define paths
	if (Test-Path $Win64Path) {
		$stalkerExe = Join-Path -Path $Win64Path -ChildPath "Stalker2-Win64-Shipping.exe"
        $exeName = "Stalker2-Win64-Shipping.exe"
	}
	if (Test-Path $WinGDKPath) {
		$stalkerExe = Join-Path -Path $WinGDKPath -ChildPath "Stalker2-WinGDK-Shipping.exe"
        $exeName = "Stalker2-WinGDK-Shipping.exe"
	}
	
	$copiedExe = Join-Path -Path $AESDumpsterPath -ChildPath $exeName
	$aesDumpsterExe = Join-Path -Path $AESDumpsterPath -ChildPath "AESDumpster-Win64.exe"

	# Ensure the AESDumpster directory exists
	if (!(Test-Path $AESDumpsterPath)) {
		New-Item -ItemType Directory -Path $AESDumpsterPath | Out-Null
	}

	# Copy the Stalker2 executable to AESDumpster directory
    if (Test-Path $stalkerExe) {
        Copy-Item -Path $stalkerExe -Destination $copiedExe -Force
    } else {
        Write-Output "Source executable not found: $stalkerExe"
        return
    }

    # Debugging: Confirm file was copied
    if (!(Test-Path $copiedExe)) {
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
        [string]$unpackedDir
    )
	
	# Run the unpack command
    Write-Host "Unpacking pakchunk0-Windows.pak. This may take some time..." -ForegroundColor Yellow
    $arguments = "--aes-key $aesKey unpack `"$pakDir\pakchunk0-Windows.pak`""
    Start-Process -FilePath "$RepackPath\repak.exe" -ArgumentList $arguments -Wait -NoNewWindow
    
	if (Test-Path $unpackedDir) {
		Write-Host "Cleaning up useless files. This may take some time..." -ForegroundColor Yellow
        # Delete all files that are not .cfg
        Get-ChildItem -Path $unpackedDir -Recurse -File | Where-Object { $_.Extension -ne ".cfg" } | Remove-Item -Force
        # Recursively delete empty folders until no more remain
		do {
			$emptyFolders = Get-ChildItem -Path $unpackedDir -Recurse -Directory | Where-Object { (Get-ChildItem -Path $_.FullName).Count -eq 0 }
			$emptyFolders | Remove-Item -Force
		} while ($emptyFolders.Count -gt 0)

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
        $currentPath = Join-Path -Path $currentPath -ChildPath $folder
        # Check if the folder exists
        if (-not (Test-Path -Path $currentPath)) {
            # Create the folder if it does not exist
            New-Item -ItemType Directory -Path $currentPath | Out-Null
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
        [string]$mergeType
    )

    ###############################
    #   Setup and mod unpacking   #
    ###############################

    # Define the merged folder name
    $mergedFolderName = "zzzzzzzzzz_MERGED_MOD"
    $tempModFolder = "C:\S2SMM"
    $mergedFolderPath = Join-Path -Path $tempModFolder -ChildPath $mergedFolderName

    # Create the merged folder
    if (-not (Test-Path $mergedFolderPath)) {
        New-Item -ItemType Directory -Path $mergedFolderPath | Out-Null
    }

    # Prepare paths for unpacking
    if (-not (Test-Path $tempModFolder)) {
        New-Item -ItemType Directory -Path $tempModFolder | Out-Null
        # empty the folder if not empty
        Remove-Item -Path $tempModFolder\* -Recurse -Force -Confirm:$false
    }

    $unpackedDirs = @{}
    foreach ($mod in $conflictingMods) {
        $tempModPath = Join-Path -Path $tempModFolder -ChildPath $mod.Name
        Move-Item -Path $mod.FullName -Destination $tempModPath -Force
        $unpackDir = Join-Path -Path $tempModFolder -ChildPath $mod.BaseName
        if (-not (Test-Path $unpackDir)) {
            # Unpack the mod `.pak` file into its own folder
            Write-Host "Unpacking $($mod.Name)..."
            $arguments = "unpack `"$tempModPath`""
            Start-Process -FilePath "$RepackPath\repak.exe" -ArgumentList $arguments -Wait -NoNewWindow
        }
        $unpackedDirs[$mod.FullName] = $unpackDir
    }

    # Copy everything from all mods to the merged folder
    foreach ($mod in $conflictingMods) {
        # List all folders in the mod folder non-recursively
        $modFiles = Get-ChildItem -Path $unpackedDirs[$mod.FullName]
        foreach ($modFile in $modFiles) {
            Copy-Item -Path $modFile.FullName -Destination $mergedFolderPath -Recurse -Force
        }
    }

    # Rechercher de manière récursive tous les fichiers en conflit dans le tableau conflictingFiles dans le dossier et ses sous-dossiers
    foreach ($conflictingFile in $conflictingFiles) {
        $conflictingFileFullPaths = Get-ChildItem -Path $mergedFolderPath -Recurse -Filter $conflictingFile -File
        foreach ($conflictingFileFullPath in $conflictingFileFullPaths) {
            Remove-Item -Path $conflictingFileFullPath.FullName -Force
        }
    }

    foreach ($conflictingFile in $conflictingFiles) {
        # Find the base file from the original unpacked directory
        $baseFilePath = Get-ChildItem -Path $unpackedDir -Recurse -Filter $conflictingFile | Select-Object -First 1
        if (-not $baseFilePath) {
            Write-Host "Base file for $conflictingFile not found in $unpackedDir." -ForegroundColor Red
            continue
        }

        # Collect paths of the conflicting files
        $filePaths = @()
        foreach ($mod in $conflictingMods) {
            $modFile = Get-ChildItem -Path $unpackedDirs[$mod.FullName] -Recurse -Filter $conflictingFile | Select-Object -First 1
            if ($modFile) {
                $filePaths += $modFile.FullName
            }
        }

        ###############################
        #  Run kdiff3 to merge files  #
        ###############################
        $basePakName = "pakchunk0-Windows"
        $baseRelativePath = $baseFilePath.FullName.Substring($baseFilePath.FullName.IndexOf("pakchunk0-Windows") + $basePakName.Length)
        $mergedRelativePath = Split-Path -Path $baseRelativePath -Parent
        $mergedAbsolutePath = Join-Path -Path $mergedFolderPath -ChildPath $mergedRelativePath
        $outputFile = Join-Path -Path $mergedAbsolutePath -ChildPath $conflictingFile

        # Ensure the merged folder structure exists before merging, if not we will not be able to save the merged file
        Ensure-MergedFolderStructure -mergedRelativePath $mergedRelativePath -mergedFolderPath $mergedFolderPath

        Write-Host "Merging $conflictingFile..."
        $auto = ""
        if ($mergeType -eq "2") {
            $auto = "--auto"
        }

        # Prepare kdiff3 arguments for manual merging
        Write-Host "Starting manual merge. Please complete the merge and close kdiff3 to continue..."
        $modName0 = Split-Path -Path $conflictingMods[0] -Leaf
        $modName1 = Split-Path -Path $conflictingMods[1] -Leaf
        Write-Host "Merging $modName0 and $modName1 with base..."
        # Start kdiff3 process and wait for it to finish
        $filePath0 = $filePaths[0]
        $filePath1 = $filePaths[1]
        $arguments = "`"$($baseFilePath.FullName)`" `"$filePath0`" `"$filePath1`" -o `"$outputFile`" $auto"
        Start-Process -FilePath "$kdiff3Folder\kdiff3.exe" -ArgumentList $arguments -Wait -NoNewWindow

        # Merge the resulting file with the remaining mods
        for ($i = 2; $i -lt $filePaths.Count; $i++) {
            # Rename the output file by adding a suffix _merged
            $mergedFile = "$($baseFilePath.BaseName)_merged.cfg"
            $outputDirectory = Split-Path -Path $conflictingFileFullPath -Parent
            $mergedFilePath = Join-Path -Path $outputDirectory -ChildPath $mergedFile
            Rename-Item -Path $outputFile -NewName $mergedFile -Force
            $modName = Split-Path -Path $conflictingMods[$i] -Leaf
            Write-Host "Merging merged file and $modName with base..."
            $filePathI = $filePaths[$i]
            $arguments = "`"$($baseFilePath.FullName)`" `"$mergedFilePath`" `"$filePathI`" -o `"$outputFile`" $auto"
            Start-Process -FilePath "$kdiff3Folder\kdiff3.exe" -ArgumentList $arguments -Wait -NoNewWindow
            # Delete the merged file
            Remove-Item -Path $mergedFilePath -Force
        }

        Write-Host "Manual merge completed for $conflictingFile." -ForegroundColor Green
    }

    Write-Host "Packing merged files into $mergedFolderName.pak..."
    $arguments = "pack `"$mergedFolderPath`""
    Start-Process -FilePath "$RepackPath\repak.exe" -ArgumentList $arguments -Wait -NoNewWindow
    Write-Host "Merged mod created: $mergedFolderName.pak" -ForegroundColor Green

    #move back all the pak files to the mod folder
    $tempPakFiles = Get-ChildItem -Path $tempModFolder -Filter *.pak
    foreach ($tempPakFile in $tempPakFiles) {
        Move-Item -Path $tempPakFile.FullName -Destination $modFolder -Force
    }
    foreach ($mod in $conflictingMods) {
        $unpackDir = Join-Path -Path $tempModFolder -ChildPath $mod.BaseName
        Remove-Item -Path $unpackDir -Recurse -Force -Confirm:$false
    }
    # Remove the merged folder if it exists
    if(Test-Path $mergedFolderPath) {
        Remove-Item -Path $mergedFolderPath -Recurse -Force -Confirm:$false
    }
    # Copy back all .pak files from the temporary folder to the real mod folder
    $tempPakFiles = Get-ChildItem -Path $tempModFolder -Filter *.pak
    foreach ($tempPakFile in $tempPakFiles) {
        Move-Item -Path $tempPakFile.FullName -Destination $modFolder -Force
    }

    Write-Host "Done"
}

################
# script start #
################

$KDiff3Folder = ".\KDiff3-0.9.98"
if (-Not (Test-Path $KDiff3Folder)) {
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
if (-Not (Test-Path $AESDumpsterPath)) {
	Write-Host "Getting AESDumpster..."
	Invoke-WebRequest -UserAgent "Wget" -Uri https://github.com/GHFear/AESDumpster/releases/download/1.2.5/AESDumpster-Win64.exe -OutFile AESDumpster-Win64.exe
	New-Item -Path $AESDumpsterPath -ItemType Directory
	Move-Item -Path .\AESDumpster-Win64.exe -Destination $AESDumpsterPath
}
else{
	Write-Host "AESDumpster found"
}

$RepackPath = ".\repak_cli-x86_64-pc-windows-msvc"
if (-Not (Test-Path $RepackPath)) {
	Write-Host "Getting Repack..."
	Invoke-WebRequest -UserAgent "Wget" -Uri https://github.com/trumank/repak/releases/download/v0.2.2/repak_cli-x86_64-pc-windows-msvc.zip -OutFile repak_cli-x86_64-pc-windows-msvc.zip
	Expand-Archive .\repak_cli-x86_64-pc-windows-msvc.zip -DestinationPath .\repak_cli-x86_64-pc-windows-msvc
	Remove-Item -Path .\repak_cli-x86_64-pc-windows-msvc.zip -Force
}
else{
	Write-Host "Repack found"
}

Write-Host "`nSelect folder containing Stalker2.exe"

$installPath = $null
$pakDir = $null
$modFolder = $null
$gameSavedPath = ".\gamepath.txt"
# Check if the file exists
if (Test-Path $gameSavedPath) {
	Write-Output "Game path file found"
	# Read the key from the file
	$installPath = Get-Content $gameSavedPath
	if ($installPath) {
        $pakDir = Join-Path -Path $installPath -ChildPath "Stalker2\Content\Paks"
        $modFolder = Join-Path -Path $pakDir -ChildPath "~mods"
		Write-Output "Game path loaded: $installPath"
	}
} else {
	Write-Output "Game path file not found."

    # Prompt user to select folder containing Stalker2.exe
    Add-Type -AssemblyName System.Windows.Forms
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = "Select folder containing Stalker2.exe"
    $folderDialog.ShowNewFolderButton = $false

    if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $installPath = $folderDialog.SelectedPath
        # Define the pak and mod folders based on the selected path
        $pakDir = Join-Path -Path $installPath -ChildPath "Stalker2\Content\Paks"
        $modFolder = Join-Path -Path $pakDir -ChildPath "~mods"
        #write the game path
        $installPath | Out-File $gameSavedPath
        Write-Output "Game path saved"
    } else {
        Write-Host "No folder selected. Exiting script." -ForegroundColor Red
        pause
        exit
    }
}

$stalker2EXEPath = Join-Path -Path $installPath -ChildPath "Stalker2.exe"
if (-Not (Test-Path $stalker2EXEPath))
{
	Write-Host "Wrong folder selected. Select the folder with Stalker2.exe. Exiting script." -ForegroundColor Red
    pause
    exit
}

$aesKeySavedPath = ".\key.txt"
# Check if the file exists
if (Test-Path $aesKeySavedPath) {
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
$pakFiles = Get-ChildItem -Recurse -Path $modFolder -Filter "*.pak"
# Define the unpacked directory
$unpackedDir = Join-Path -Path $pakDir -ChildPath "pakchunk0-Windows"

if (-Not (Test-Path $unpackedDir)) {
    Write-Host "`nUnpacking default files..."
    Unpack-And-Clean -RepackPath $RepackPath -pakDir $pakDir -unpackedDir $unpackedDir
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
    # list all files in the .pak file
    $arguments = "list `"$($pakFile.FullName)`""
    $RepackEXE = "$RepackPath\repak.exe"
    $rawOutput = cmd /c "$RepackEXE $arguments" 2>&1
    
    # filter out everything but the file name
    $files = $rawOutput -replace '^.*"(?:.+/)*(.*)".*$', '$1'

    # check if files is not empty
    if (-Not($files.Count -eq 0)) {
        $files = Split-Path -Path $files -Leaf
    }

    foreach ($file in $files) {
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
        Write-Host "  - $($mod.FullName)"
    }
    Write-Host

    Write-Host "Conflicting files:"
    foreach ($file in $conflictingFiles) {
        Write-Host "  - $file"
    }
    Write-Host

    $mergeType = Read-Host "Do you want to merge all conflicting files? (manual merge (1) / auto merge (2) / skip (3))"
    if ($mergeType -eq "1" -or $mergeType -eq "2") {
        Resolve-Conflict-And-Merge -modFolder $modFolder -unpackedDir $unpackedDir -KDiff3Folder $KDiff3Folder -RepackPath $RepackPath -conflictingFiles $conflictingFiles -conflictingMods $conflictingMods -mergeType $mergeType
    } else {
        Write-Host "Merge operation skipped." -ForegroundColor Cyan
    }
} else {
    Write-Host "No conflicts found." -ForegroundColor Green
}

pause