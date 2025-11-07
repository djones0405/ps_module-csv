<#
SafeModuleCopy.ps1
 - Interactive copy from PowerShell module folder to PSGallery, with reporting and user usage guidance at end.
 - Handles drive/UNC space, avoids reparse points.
 - Shows progress, logs actions.
 - Allows "Skip All" for conflicts.
 - Launches log in Notepad for user review upon completion.
#>

function Choose-FolderDialog($prompt, $defaultPath) {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $prompt
    $dialog.SelectedPath = $defaultPath
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    } else {
        Write-Host "No folder selected. Exiting." -ForegroundColor Red
        return $null
    }
}

function Get-FreeSpaceGB($path) {
    $root = [System.IO.Path]::GetPathRoot($path)
    if ($root -match "^[a-zA-Z]:\\$") {
        $drv = $root.Substring(0, 1)
        $drive = Get-PSDrive -Name $drv -ErrorAction SilentlyContinue
        if ($drive) { return [math]::Round($drive.Free/1GB,2) }
    } elseif ($root -match "^\\\\") {
        # Network/UNC path: can't get disk space with Get-PSDrive or Scripting.FileSystemObject reliably
        try {
            # Try WMI if possible
            $computer = $root.Split('\')[2]
            $share = $root.Split('\')[3]
            $wmiQry = "win32_logicaldisk"
            $disks = Get-WmiObject -Class $wmiQry -ComputerName $computer -ErrorAction SilentlyContinue
            foreach ($disk in $disks) {
                # Just report all for user
                Write-Host ("Remote disk {0} free: {1} GB" -f $disk.DeviceID, [math]::Round($disk.FreeSpace/1GB,2))
            }
        } catch {}
    }
    return $null
}

$defaultSource = "C:\Users\jodaniel\Documents\WindowsPowerShell\"
$defaultDest   = "\\HQ3AIFVID01\AI-Repository\PSGallery"
$moduleExtensions = @(".ps1",".psm1",".psd1") # change for other types

Write-Host "---------------------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "INTERACTIVE MODULE COPYING SCRIPT [IMPROVED]" -ForegroundColor White
Write-Host "Default source: $defaultSource" -ForegroundColor Cyan
Write-Host "Default dest:   $defaultDest" -ForegroundColor Cyan
Write-Host "You can change these destinations if you wish." -ForegroundColor Yellow
Write-Host "File types: $($moduleExtensions -join ', ') (change in script for more)" -ForegroundColor Yellow
Write-Host "---------------------------------------------------------------------------------" -ForegroundColor Cyan

$sourcePath = Read-Host "Enter source directory or leave blank for default [$defaultSource]"
if ([string]::IsNullOrWhiteSpace($sourcePath)) { $sourcePath = $defaultSource }
if (!(Test-Path $sourcePath)) {
    Write-Host "Source folder does not exist: $sourcePath" -ForegroundColor Red
    $sourcePath = Choose-FolderDialog "Choose a source folder" $defaultSource
    if (!$sourcePath) { return }
}

$destPath = Read-Host "Enter destination directory or leave blank for default [$defaultDest]"
if ([string]::IsNullOrWhiteSpace($destPath)) { $destPath = $defaultDest }
if (!(Test-Path $destPath)) {
    Write-Host "Destination folder does not exist: $destPath" -ForegroundColor Red
    $destPath = Choose-FolderDialog "Choose a destination folder for PSGallery" $defaultDest
    if (!$destPath) { return }
}

# Disk space check (works local, offers info for remote, doesn't block remote UNC usage)
$srcSpace = Get-FreeSpaceGB $sourcePath
$dstSpace = Get-FreeSpaceGB $destPath
Write-Host "`nSource drive has approx $srcSpace GB free, Destination drive has approx $dstSpace GB free." -ForegroundColor Cyan
$totalSizeNeededGB = "{0:N2}" -f ((Get-ChildItem $sourcePath -File -Recurse | Measure-Object -Property Length -Sum).Sum/1GB)
Write-Host "Total source data size (GB): $totalSizeNeededGB" -ForegroundColor Cyan
if ($dstSpace -ne $null -and $dstSpace -lt [double]$totalSizeNeededGB) {
    Write-Host "WARNING: Destination disk may not have enough space!" -ForegroundColor Red
    $cont = Read-Host "Continue anyway? [Y/N]"
    if ($cont -notmatch "^(Y|y)$") { return }
}

Write-Host "`nCopying contents from source: $sourcePath" -ForegroundColor Cyan
Write-Host "                  to dest: $destPath" -ForegroundColor Cyan
Write-Host "You will be prompted for each file/folder conflict. Option to skip all." -ForegroundColor Yellow

# Get all files/folders, avoiding reparse points and filtering extensions
$items = Get-ChildItem $sourcePath -Recurse -Force | Where-Object { 
    -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and 
    (($moduleExtensions -contains $_.Extension) -or $_.PSIsContainer)
}

$copied  = @()
$skipped = @()
$errored = @()
$total   = $items.Count
$index   = 0
$skipAllConflicts = $false

# Log file for summary
$logPath = "$env:TEMP\SafeModuleCopy-log-$((Get-Date).ToString('yyyyMMdd-HHmmss')).txt"
Add-Content -Path $logPath -Value ("--- SafeModuleCopy run at "+(Get-Date))

foreach ($item in $items) {
    $index++
    Write-Host ("Progress: $index / $total [" +
        [math]::Round($index/$total*100,1) + "%]") -ForegroundColor Magenta

    # Robust relative path extraction
    $relativePath = $null
    if ($item.FullName.StartsWith($sourcePath)) {
        $relativePath = $item.FullName.Substring($sourcePath.Length)
        if ($relativePath.StartsWith("\") -or $relativePath.StartsWith("/")) {
            $relativePath = $relativePath.Substring(1)
        }
    } else {
        $relativePath = $item.Name
    }
    $targetFull = Join-Path $destPath $relativePath

    if (!(Test-Path $targetFull)) {
        try {
            if ($item.PSIsContainer) {
                Write-Host "Creating folder: $targetFull" -ForegroundColor Green
                New-Item -ItemType Directory -Path $targetFull -Force | Out-Null
                $copied += "[Folder] $targetFull"
                Add-Content -Path $logPath -Value "Copied folder: $targetFull"
            } else {
                Write-Host "Copying new file: $targetFull" -ForegroundColor Green
                Copy-Item -Path $item.FullName -Destination $targetFull
                $copied += "[File]   $targetFull"
                Add-Content -Path $logPath -Value "Copied file:   $targetFull"
            }
        } catch {
            Write-Host "ERROR: Failed to create/copy: $targetFull" -ForegroundColor Red
            $errored += "$targetFull :: $($_.Exception.Message)"
            Add-Content -Path $logPath -Value "ERROR copying $targetFull :: $($_.Exception.Message)"
        }
    } else {
        Write-Host ""
        Write-Host "CONFLICT: $targetFull already exists." -ForegroundColor Yellow
        if ($skipAllConflicts) {
            Write-Host "Skipping due to user Skip All setting: $targetFull" -ForegroundColor Yellow
            $skipped += $targetFull
            Add-Content -Path $logPath -Value "Skipped (conflict): $targetFull"
            continue
        }
        $action = Read-Host "Skip [S], Overwrite [O], Change Destination [D], Rename File [R], Cancel [C], or Skip All [A]?"
        switch ($action.ToUpper()) {
            'S' { Write-Host "Skipping: $targetFull" -ForegroundColor Yellow; $skipped += $targetFull; Add-Content -Path $logPath -Value "Skipped (by user): $targetFull" }
            'A' { 
                Write-Host "User selected Skip All for remainder of conflicts." -ForegroundColor Yellow
                $skipAllConflicts = $true
                Write-Host "Skipping: $targetFull" -ForegroundColor Yellow
                $skipped += $targetFull
                Add-Content -Path $logPath -Value "Skipped (now skipping all): $targetFull"
            }
            'O' {
                try {
                    if ($item.PSIsContainer) { 
                        Write-Host "Folder already exists: $targetFull (no overwrite performed)" -ForegroundColor Yellow
                        $skipped += $targetFull; Add-Content -Path $logPath -Value "Skipped (folder conflict): $targetFull"
                    } else {
                        Write-Host "Overwriting file: $targetFull" -ForegroundColor Red
                        $conf = Read-Host "Are you sure you want to overwrite? Y/N"
                        if ($conf -notmatch "^(Y|y)$") { Write-Host "Overwrite cancelled, skipping."; $skipped += $targetFull; continue }
                        Copy-Item $item.FullName $targetFull -Force
                        $copied += "[File-overwritten] $targetFull"
                        Add-Content -Path $logPath -Value "Overwritten file: $targetFull"
                    }
                } catch {
                    Write-Host "ERROR: Failed to overwrite: $targetFull" -ForegroundColor Red
                    $errored += "$targetFull :: $($_.Exception.Message)"
                    Add-Content -Path $logPath -Value "ERROR overwriting $targetFull :: $($_.Exception.Message)"
                }
            }
            'D' {
                $newDest = Read-Host "Enter new destination PATH for this item"
                if ([string]::IsNullOrWhiteSpace($newDest)) { Write-Host "No path given. Skipping." -ForegroundColor Yellow; $skipped += $targetFull; Add-Content -Path $logPath -Value "Skipped (bad dest): $targetFull" }
                elseif (!(Test-Path (Split-Path $newDest -Parent))) { Write-Host "Parent folder of new destination does not exist. Skipping." -ForegroundColor Red; $skipped += $targetFull; Add-Content -Path $logPath -Value "Skipped (invalid dest): $targetFull" }
                else {
                    try {
                        if ($item.PSIsContainer) { New-Item -ItemType Directory -Path $newDest -Force | Out-Null }
                        else { Copy-Item -Path $item.FullName -Destination $newDest }
                        Write-Host "Copied to new destination: $newDest" -ForegroundColor Green
                        $copied += "[File/Folder-moved] $newDest"
                        Add-Content -Path $logPath -Value "Moved to $newDest"
                    } catch {
                        Write-Host "ERROR: Failed to copy to new destination: $newDest" -ForegroundColor Red
                        $errored += "$newDest :: $($_.Exception.Message)"
                        Add-Content -Path $logPath -Value "ERROR moving $targetFull to $newDest :: $($_.Exception.Message)"
                    }
                }
            }
            'R' {
                $newFilename = Read-Host "Enter new file name (just the name, not path)"
                $newFullPath = Join-Path (Split-Path $targetFull -Parent) $newFilename
                if ([string]::IsNullOrWhiteSpace($newFilename)) { Write-Host "No new name specified. Skipping." -ForegroundColor Yellow; $skipped += $targetFull; Add-Content -Path $logPath -Value "Skipped (bad rename): $targetFull" }
                elseif (Test-Path $newFullPath) { Write-Host "New name already exists at $newFullPath. Skipping." -ForegroundColor Red; $skipped += $targetFull; Add-Content -Path $logPath -Value "Skipped (rename conflict): $targetFull" }
                else {
                    try {
                        Copy-Item -Path $item.FullName -Destination $newFullPath
                        Write-Host "Copied with new file name: $newFullPath" -ForegroundColor Green
                        $copied += "[File-renamed] $newFullPath"
                        Add-Content -Path $logPath -Value "Renamed to $newFullPath"
                    } catch {
                        Write-Host "ERROR: Failed to copy as new file: $newFullPath" -ForegroundColor Red
                        $errored += "$newFullPath :: $($_.Exception.Message)"
                        Add-Content -Path $logPath -Value "ERROR renaming $targetFull to $newFullPath :: $($_.Exception.Message)"
                    }
                }
            }
            'C' { Write-Host "User cancelled copying process." -ForegroundColor Red; Add-Content -Path $logPath -Value "User cancelled at index $index ($targetFull)."; break }
            default { Write-Host "Invalid answer, skipping: $targetFull" -ForegroundColor Yellow; $skipped += $targetFull; Add-Content -Path $logPath -Value "Skipped (invalid input): $targetFull" }
        }
    }
}

Write-Host ""
Write-Host "================== Copy Summary ==================" -ForegroundColor Cyan
Write-Host "`nItems COPIED:" -ForegroundColor Green
if ($copied.Count -eq 0) { Write-Host "None copied." -ForegroundColor Yellow }
else { $copied | ForEach-Object { Write-Host $_ -ForegroundColor Green } }
Write-Host "`nItems SKIPPED (already existed OR by user):" -ForegroundColor Yellow
if ($skipped.Count -eq 0) { Write-Host "None skipped." -ForegroundColor Green }
else { $skipped | ForEach-Object { Write-Host $_ -ForegroundColor Yellow } }
Write-Host "`nItems with ERRORS:" -ForegroundColor Red
if ($errored.Count -eq 0) { Write-Host "No errors." -ForegroundColor Green }
else { $errored | ForEach-Object { Write-Host $_ -ForegroundColor Red } }
Write-Host "`nDONE: Copy operation complete." -ForegroundColor Cyan

# Launch Notepad with log for user review
Write-Host "`nLaunching log file in Notepad for review...`n" -ForegroundColor Cyan
Start-Process notepad.exe $logPath

# Usage instructions (in white)
Write-Host "---------------------------------------------------------------------------------" -ForegroundColor White
Write-Host "USAGE INSTRUCTIONS (Client for PSGallery):" -ForegroundColor White
Write-Host " - Next, to use installed modules from the gallery on a client machine:" -ForegroundColor White
Write-Host "   1. Register PSGallery repository:" -ForegroundColor White
Write-Host "      Register-PSRepository -Name 'MyCompanyPSRepo' -SourceLocation '$destPath' -InstallationPolicy Trusted" -ForegroundColor White
Write-Host "   2. To install a module from the gallery, run:" -ForegroundColor White
Write-Host "      Install-Module -Name <ModuleName> -Repository MyCompanyPSRepo" -ForegroundColor White
Write-Host "   3. To update your module, run:" -ForegroundColor White
Write-Host "      Update-Module -Name <ModuleName>" -ForegroundColor White
Write-Host "   4. After install, use Import-Module <ModuleName> to make commands available." -ForegroundColor White
Write-Host "---------------------------------------------------------------------------------" -ForegroundColor White
Write-Host "Log file shows every copy event, error, and skip; saved at: $logPath" -ForegroundColor White
Write-Host "You may close Notepad after review." -ForegroundColor White
Write-Host "---------------------------------------------------------------------------------" -ForegroundColor White