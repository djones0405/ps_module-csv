<#
Create-PSGalleryRepo.ps1

Safely and interactively create/manage a private PowerShell module gallery folder for use with Register-PSRepository/Publish-Module.
NEW: After gallery creation, finds PowerShell modules under all user directories, offers to copy them to the gallery.
 - Duplicates will be silently skipped (but logged).
 - Includes major steps & logs every key event or error.
 - Opens log file in Notepad at end.
 - Prints client usage instructions at end in white.

USAGE:
Run as a user with permissions to create and set permissions on the network share.
#>

param(
    [string]$RepoPath = "\\HQ3AIFVID01\AI-Repository\PSGallery",
    [string]$InitialModulePath = "",      # e.g. "C:\Modules\ImprovedAdminTools" or "" to skip
    [string]$AllowedReadGroup = "Domain Users",
    [string]$AllowedAdminGroup = "Domain Admins"
)

function Choose-FolderDialog {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Choose a location for your private PowerShell Gallery"
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    } else {
        Write-Host "No folder was selected. Script will now exit." -ForegroundColor Red
        return $null
    }
}

# Logging setup
$logPath = "$env:TEMP\Create-PSGalleryRepo-log-$((Get-Date).ToString('yyyyMMdd-HHmmss')).txt"
Add-Content -Path $logPath -Value ("--- Create-PSGalleryRepo run at "+(Get-Date))
function Log($text) { Add-Content -Path $logPath -Value $text }

Write-Host "---------------------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "CREATING PRIVATE POWERSHELL MODULE GALLERY" -ForegroundColor Cyan
Write-Host "Target folder path: $RepoPath" -ForegroundColor Cyan
Write-Host "Initial module to publish (optional): $InitialModulePath" -ForegroundColor Cyan
Write-Host "---------------------------------------------------------------------------------"

# Confirm intended repo path if folder already exists
if (Test-Path $RepoPath) {
    Write-Host "NOTE: Your target gallery folder already exists: $RepoPath" -ForegroundColor Yellow
    $useExisting = Read-Host "Do you want to use this directory ($RepoPath) as your private gallery? (Y/N)"
    Log "User found existing PSGallery folder $RepoPath; response: $useExisting"
    if ($useExisting -notmatch "^(Y|y)$") {
        Write-Host "Please select a different directory as your private PSGallery." -ForegroundColor Cyan
        $newRepoPath = Choose-FolderDialog
        if (-not $newRepoPath) { Write-Host "No valid path chosen, exiting." -ForegroundColor Red; Log "No valid directory chosen, script exited."; return }
        $RepoPath = $newRepoPath
        Write-Host "Gallery path updated: $RepoPath" -ForegroundColor Cyan
        Log "Repo path updated by user: $RepoPath"
    }
}

# Create directory if needed
if (!(Test-Path $RepoPath)) {
    Write-Host "Folder does NOT exist. It will be created: $RepoPath" -ForegroundColor Green
    try {
        New-Item -ItemType Directory -Force -Path $RepoPath | Out-Null
        Write-Host "Folder created: $RepoPath" -ForegroundColor Green
        Log "Created gallery folder: $RepoPath"
    } catch {
        Write-Host "ERROR: Could not create folder $RepoPath" -ForegroundColor Red
        Log "ERROR: Could not create folder $RepoPath"
        return
    }
} else {
    Write-Host "Using existing folder for gallery: $RepoPath" -ForegroundColor Green
    Log "Using existing folder: $RepoPath"
}

# NTFS permissions step
Write-Host ("Setting NTFS permissions for folder: " + $RepoPath) -ForegroundColor Cyan
Write-Host ("Read access will be granted to: " + $AllowedReadGroup) -ForegroundColor Cyan
Write-Host ("Modify access will be granted to: " + $AllowedAdminGroup) -ForegroundColor Cyan
try {
    $acl = Get-Acl $RepoPath
    $readRule = New-Object System.Security.AccessControl.FileSystemAccessRule($AllowedReadGroup,"Read","ContainerInherit,ObjectInherit","None","Allow")
    $acl.SetAccessRule($readRule)
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule($AllowedAdminGroup,"Modify","ContainerInherit,ObjectInherit","None","Allow")
    $acl.SetAccessRule($adminRule)
    Set-Acl -Path $RepoPath -AclObject $acl
    Write-Host "NTFS permissions SUCCESS: Read ($AllowedReadGroup), Modify ($AllowedAdminGroup)" -ForegroundColor Green
    Log "Set NTFS permissions on $RepoPath for $AllowedReadGroup (Read) and $AllowedAdminGroup (Modify)."
} catch {
    Write-Host "ERROR: Could not set NTFS permissions! Please set them manually if you lack permission." -ForegroundColor Red
    Log "ERROR: Could not set NTFS permissions at $RepoPath"
}

# Handle initial module copy, always referencing $RepoPath
if ($InitialModulePath -and (Test-Path $InitialModulePath)) {
    $destModule = Join-Path $RepoPath (Split-Path $InitialModulePath -Leaf)
    if (Test-Path $destModule) {
        Write-Host "WARNING! Target for module initial copy already exists: $destModule" -ForegroundColor Yellow
        $okOverwrite = Read-Host "OVERWRITE all files at $destModule with files from $InitialModulePath? (Y/N)"
        Log "Module $InitialModulePath exists at $destModule; user chose: $okOverwrite"
        if ($okOverwrite -notmatch "^(Y|y)$") {
            Write-Host "Skipping copy. You can manually copy/publish your module later." -ForegroundColor Yellow
            Log "Copy SKIPPED for module transfer to $destModule"
        } else {
            Write-Host "Copying module files ... Overwriting contents at: $destModule" -ForegroundColor Green
            Copy-Item -Path $InitialModulePath -Destination $destModule -Recurse -Force
            Write-Host "Module copied to: $destModule" -ForegroundColor Green
            Log "Module $InitialModulePath OVERWRITTEN/copied to $destModule"
        }
    } else {
        Write-Host "Copying initial module to gallery: $destModule" -ForegroundColor Green
        Copy-Item -Path $InitialModulePath -Destination $destModule -Recurse -Force
        Write-Host "Module copied to: $destModule" -ForegroundColor Green
        Log "Module $InitialModulePath copied to new location: $destModule"
    }
} else {
    Write-Host "No initial module copied. (Set -InitialModulePath if desired)" -ForegroundColor Yellow
    Log "No initial module copied to gallery."
}

# README creation step
$readmePath = Join-Path $RepoPath "README.txt"
if (!(Test-Path $readmePath)) {
    Write-Host "Creating README.txt in: $readmePath" -ForegroundColor Green
    Set-Content -Path $readmePath -Value @"
This folder is a private PowerShell module gallery for your organization or team.
Admins should use Publish-Module from PowerShell to upload packages here.
Users should use Register-PSRepository and Install-Module to fetch modules from this folder.

More info: https://docs.microsoft.com/en-us/powershell/gallery/how-to/publish-an-item?view=powershellget-1.0.0
"@
    Write-Host "README.txt created in gallery folder." -ForegroundColor Green
    Log "README.txt created at $readmePath"
} else {
    Write-Host "README.txt already exists in $RepoPath. No changes made." -ForegroundColor Yellow
    Log "README.txt exists at $readmePath"
}

# Offer to copy all discovered PowerShell modules from all user profiles
$userDirs = Get-ChildItem C:\Users -Directory -ErrorAction SilentlyContinue
foreach ($user in $userDirs) {
    $modRoot = "$($user.FullName)\Documents\WindowsPowerShell\Modules"
    if (Test-Path $modRoot) {
        $mods = Get-ChildItem $modRoot -Directory -ErrorAction SilentlyContinue
        if ($mods) {
            Write-Host "`nFound modules in ${modRoot}:" -ForegroundColor Cyan
            $foundMods = $mods | ForEach-Object { $_.Name }
            Write-Host ("  " + ($foundMods -join ", ")) -ForegroundColor Cyan
            $copyConfirm = Read-Host "Copy these modules to PSGallery? (Y/N)"
            if ($copyConfirm -match "^(Y|y)$") {
                foreach ($mod in $mods) {
                    $destMod = Join-Path $RepoPath $mod.Name
                    if (Test-Path $destMod) {
                        Write-Host "Skipping duplicate module '$($mod.Name)' (already in PSGallery)" -ForegroundColor Yellow
                        Log "Skipped duplicate module '$($mod.FullName)' => $destMod (already exists)"
                        continue
                    }
                    try {
                        Write-Host "Copying module '$($mod.Name)' from $modRoot to $RepoPath ..." -ForegroundColor Green
                        Copy-Item $mod.FullName -Destination $destMod -Recurse
                        Log "Copied module '$($mod.FullName)' => $destMod"
                    } catch {
                        Write-Host "ERROR copying module '$($mod.Name)': $($_.Exception.Message)" -ForegroundColor Red
                        Log "ERROR copying module '$($mod.FullName)' => $destMod : $($_.Exception.Message)"
                    }
                }
            }
            else {
                Write-Host "Skipping modules from $modRoot." -ForegroundColor Yellow
                Log "User skipped copying modules from $modRoot"
            }
        }
    }
}

Write-Host "---------------------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "`nNEXT STEPS for all admins/users:" -ForegroundColor Cyan
Write-Host "  PSGallery folder:        $RepoPath" -ForegroundColor White
Write-Host "  Example Publish-Module:  Publish-Module -Path <ModuleFolder> -Repository MyCompanyPSRepo" -ForegroundColor White
Write-Host "  To register on a workstation (once):" -ForegroundColor Yellow
Write-Host "    Register-PSRepository -Name 'MyCompanyPSRepo' -SourceLocation '$RepoPath' -InstallationPolicy Trusted" -ForegroundColor White
Write-Host "    Install-Module -Name ImprovedAdminTools -Repository MyCompanyPSRepo" -ForegroundColor White
Write-Host "`nReview NTFS and share permissions for best security (read for users, write/admin for maintainers)." -ForegroundColor Cyan
Write-Host "DONE." -ForegroundColor Green

Write-Host "---------------------------------------------------------------------------------" -ForegroundColor White
Write-Host "USAGE INSTRUCTIONS (Client for PSGallery):" -ForegroundColor White
Write-Host " - To use the company's PSGallery, register on any client machine as follows:" -ForegroundColor White
Write-Host "     Register-PSRepository -Name 'MyCompanyPSRepo' -SourceLocation '$RepoPath' -InstallationPolicy Trusted" -ForegroundColor White
Write-Host " - To publish a module, run:" -ForegroundColor White
Write-Host "     Publish-Module -Path <ModuleFolder> -Repository MyCompanyPSRepo" -ForegroundColor White
Write-Host " - To install a published module, run:" -ForegroundColor White
Write-Host "     Install-Module -Name <ModuleName> -Repository MyCompanyPSRepo" -ForegroundColor White
Write-Host " - After install, use Import-Module <ModuleName> to load it." -ForegroundColor White
Write-Host "---------------------------------------------------------------------------------" -ForegroundColor White
Write-Host "Log file shows every creation/copy event and error at: $logPath" -ForegroundColor White
Write-Host "Launching log file in Notepad for review..." -ForegroundColor White
Start-Process notepad.exe $logPath
Write-Host "You may close Notepad after review." -ForegroundColor White
Write-Host "---------------------------------------------------------------------------------" -ForegroundColor White