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
	# Define paths
	if (Test-Path $Win64Path) {
		$stalkerExe = Join-Path -Path $Win64Path -ChildPath "Stalker2-Win64-Shipping.exe"
	}
	if (Test-Path $WinGDKPath)
	{
		$stalkerExe = Join-Path -Path $WinGDKPath -ChildPath "Stalker2-Win64-Shipping.exe"
	}
	
	$copiedExe = Join-Path -Path $AESDumpsterPath -ChildPath "Stalker2-Win64-Shipping.exe"
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
    & "$RepackPath\repak.exe" --aes-key $aesKey unpack "$pakDir\pakchunk0-Windows.pak"
    
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

function Resolve-Conflict-And-Merge {
    param (
        [string]$modFolder,
        [string]$unpackedDir,
        [string]$KDiff3Folder,
        [string]$RepackPath,
        [string]$conflictingFile,
        [System.Collections.ArrayList]$conflictingMods,
		[string]$mergeType
    )

    # Define the merged folder name
    $mergedFolderName = ($conflictingMods | ForEach-Object { $_.BaseName }) -join "_"
    $mergedFolderPath = Join-Path -Path $modFolder -ChildPath $mergedFolderName

    # Create the merged folder
    if (-not (Test-Path $mergedFolderPath)) {
        New-Item -ItemType Directory -Path $mergedFolderPath | Out-Null
    }

    # Prepare paths for unpacking
    $unpackedDirs = @{}
    foreach ($mod in $conflictingMods) {
        $unpackDir = Join-Path -Path $modFolder -ChildPath $mod.BaseName
        if (-not (Test-Path $unpackDir)) {
            # Unpack the mod `.pak` file into its own folder
            Write-Host "Unpacking $($mod.Name)..."
            & "$repackPath\repak.exe" unpack $mod.FullName
        }
        $unpackedDirs[$mod.FullName] = $unpackDir
    }

    # Find the base file from the original unpacked directory
    $baseFilePath = Get-ChildItem -Path $unpackedDir -Recurse -Filter $conflictingFile | Select-Object -First 1
    if (-not $baseFilePath) {
        Write-Host "Base file for $conflictingFile not found in $unpackedDir." -ForegroundColor Red
        return
    }

    # Collect paths of the conflicting files
    $filePaths = @()
    foreach ($mod in $conflictingMods) {
        $modFile = Get-ChildItem -Path $unpackedDirs[$mod.FullName] -Recurse -Filter $conflictingFile | Select-Object -First 1
        if ($modFile) {
            $filePaths += $modFile.FullName
        }
    }

    #copy everythign from all mods to the merged folder using
    foreach ($mod in $conflictingMods) {
        # list all folder in the mod folder non recursively
        $modFiles = Get-ChildItem -Path $unpackedDirs[$mod.FullName]
        foreach ($modFile in $modFiles) {
            Copy-Item -Path $modFile.FullName -Destination $mergedFolderPath -Recurse -Force
        }
    }

    #delete the conflicting file from the merged folder
    $conflictingFileFullPath = Join-Path -Path $mergedFolderPath -ChildPath $conflictingFile
    if (Test-Path $conflictingFileFullPath) {
        Remove-Item -Path $conflictingFileFullPath -Force
    }

	Write-Host 
    # Run kdiff3 to merge files
    $outputFile = Join-Path -Path $mergedFolderPath -ChildPath $conflictingFile
    Write-Host "Merging $conflictingFile..."
    Write-Host 
    $auto = ""
    if($mergeType -eq "2")
    {
        $auto = "--auto"
    }

    # Prepare kdiff3 arguments for manual merging
    Write-Host "Starting manual merge. Please complete the merge and close kdiff3 to continue..."
    Write-Host 
    $modName0 = Split-Path -Path $conflictingMods[0] -Leaf
    $modName1 = Split-Path -Path $conflictingMods[1] -Leaf
    Write-Host "Merging $modName0 and $modName1 with base..."
    # Start kdiff3 process and wait for it to finish
    & "$kdiff3Folder\kdiff3.exe" $baseFilePath.FullName $filePaths[0] $filePaths[1] "-o" $outputFile $auto | Out-Null
    Write-Host 
    # Merge the resulting file with the remaining mods
    for ($i = 2; $i -lt $filePaths.Count; $i++) {
        #Rename the output file by adding a suffix _merged
        $mergedFile = "$($baseFilePath.BaseName)_merged.cfg"
        $outputDirectory = Split-Path -Path $conflictingFileFullPath -Parent
        $mergedFilePath = Join-Path -Path $outputDirectory -ChildPath $mergedFile
        Rename-Item -Path $outputFile -NewName $mergedFile -Force
        $modName = Split-Path -Path $conflictingMods[$i] -Leaf
        Write-Host "Merging merged file and $modName with base..."
        & "$KDiff3Folder\kdiff3.exe" $baseFilePath.FullName $mergedFilePath $filePaths[$i] "-o" $outputFile $auto | Out-Null
        # Delete the merged file
        Remove-Item -Path $mergedFilePath -Force
        Write-Host 
    }
	
    Write-Host "Manual merge completed for $conflictingFile." -ForegroundColor Green
    Write-Host
	
	pause
	Write-Host 

    # Pack the merged folder into a `.pak` file
    Write-Host "Packing merged files into $mergedFolderName.pak..."
    & "$repackPath\repak.exe" pack $mergedFolderPath
    Write-Host 
    Write-Host "Merged mod created: $mergedFolderName.pak" -ForegroundColor Green
    Write-Host 
	
	foreach ($mod in $conflictingMods) {
		$unpackDir = Join-Path -Path $modFolder -ChildPath $mod.BaseName
		Remove-Item -Path $unpackDir -Recurse -Force -Confirm:$false
	}
	Remove-Item -Path $mergedFolderPath -Recurse -Force -Confirm:$false

	Write-Host "Cleaning and backing up pak mods..."
    #rename conflicting mods with .bak extension and move them to a backup folder
    $backupFolder = Join-Path -Path $modFolder -ChildPath "~backup"
    if (-not (Test-Path $backupFolder)) {
        New-Item -ItemType Directory -Path $backupFolder | Out-Null
    }
    foreach ($mod in $conflictingMods) {
        $modFileBak = "$($mod.BaseName).bak"
        $fullModFileBakPath = Join-Path -Path $modFolder -ChildPath $modFileBak
        Rename-Item -Path $($mod.FullName) -NewName $modFileBak -Force
        Move-Item -Path $fullModFileBakPath -Destination $backupFolder -Force
    }
	Write-Host "Done"
	Write-Host 
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

# Prompt user to select folder containing Stalker2.exe
Add-Type -AssemblyName System.Windows.Forms
$folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$folderDialog.Description = "Select folder containing Stalker2.exe"
$folderDialog.ShowNewFolderButton = $false

if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $installPath = $folderDialog.SelectedPath
    # Define the pak and mod folders based on the selected path
    $pakDir = Join-Path -Path $installPath -ChildPath "Stalker2\Content\Paks\"
    $modFolder = Join-Path -Path $pakDir -ChildPath "~mods\"
} else {
    Write-Host "No folder selected. Exiting script." -ForegroundColor Red
    pause
    exit
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
else
{
	Write-Host "Unpacked pakchunk0-Windows found."
}
Write-Host 

# output how many we found
Write-Host "Total .pak files found: $($pakFiles.Count)" -ForegroundColor Cyan

$results = [System.Collections.Hashtable]::new()

foreach ($pakFile in $pakFiles) {
    # list all files in the .pak file
    $rawOutput = .\repak_cli-x86_64-pc-windows-msvc\repak.exe list $pakFile.FullName

    # filter out everything but the file name
    $files = $rawOutput -replace '^.*"(?:.+/)*(.*)".*$', '$1'

    foreach ($file in $files) {
        if ($results.ContainsKey($file)) {
            [void]$results[$file].Add($pakFile)
        } else {
            $list = [System.Collections.ArrayList]::new()
            [void]$list.Add($pakFile)
            $results[$file] = $list
        }
    }
}

# do we have a conflict
$conflict = $false

foreach ($result in $results.GetEnumerator()) {
    # more than one mod changes the given file (aka conflict)
    if ($result.Value.Count -gt 1) {
        $conflict = $true
        Write-Host "Conflict in file: $($result.Name) - by mods:"
        foreach ($modFile in $result.Value) {
            # remove absolute path before printing
            $modPretty = $modFile.FullName.Replace($modFolder, "")
            Write-Host "  - $modPretty"
        }
		Write-Host
		# Prompt user for merge
		$mergeType = Read-Host "Do you want to merge files? (manual merge (1) / auto merge (2) / skip (3)"
		if ($mergeType -eq "1" -or $mergeType -eq "2") {
			Resolve-Conflict-And-Merge -modFolder $modFolder -unpackedDir $unpackedDir -KDiff3Folder $KDiff3Folder -RepackPath $RepackPath -conflictingFile $result.Name -conflictingMods $result.Value -mergeType $mergeType
		} else {
			Write-Host "Merge operation skipped." -ForegroundColor Cyan
		}
        Write-Host
    }
}

if (-not $conflict) {
    Write-Host "No conflicts found among the mod files." -ForegroundColor Green
}

pause