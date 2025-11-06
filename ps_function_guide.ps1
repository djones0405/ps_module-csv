<#
.SYNOPSIS
  Helper functions and bootstrap checks for PowerShell AD/Azure administration (Windows 11).

DIRECTIONS / SAVE & USAGE INSTRUCTIONS (put these comments at the top so they're always visible)
- Recommended save location (per-user):
    Save this file to:
      $env:USERPROFILE\Documents\PowerShell\CheatSheet_AD_Azure.ps1
    Example:
      New-Item -ItemType Directory -Path "$env:USERPROFILE\Documents\PowerShell" -Force
      # edit and save file to the path above

- How to load the file into your current session (dot‑source):
    . "$env:USERPROFILE\Documents\PowerShell\CheatSheet_AD_Azure.ps1"
  After dot-sourcing the functions are available in the current session (non-persistent).

- How to auto-load on PowerShell start (add to your profile):
    if (-not (Test-Path -Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force }
    # add this line once to your profile (idempotent)
    $line = '. "$env:USERPROFILE\Documents\PowerShell\CheatSheet_AD_Azure.ps1"'
    if (-not (Select-String -Path $PROFILE -Pattern [regex]::Escape($line) -Quiet)) {
        Add-Content -Path $PROFILE -Value $line
    }

- Convert to a proper module (recommended for reuse & sharing):
    # create module folder (per-user)
    $moduleFolder = Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules\MyAdminTools\1.0.0'
    New-Item -ItemType Directory -Path $moduleFolder -Force | Out-Null
    # copy this file into the module as a .psm1 and create a manifest
    Copy-Item -Path "$env:USERPROFILE\Documents\PowerShell\CheatSheet_AD_Azure.ps1" `
              -Destination (Join-Path $moduleFolder 'MyAdminTools.psm1') -Force
    New-ModuleManifest -Path (Join-Path $moduleFolder 'MyAdminTools.psd1') `
        -RootModule 'MyAdminTools.psm1' -ModuleVersion '1.0.0' -Author 'YourName'

    # then import the module
    Import-Module MyAdminTools
    Get-Command -Module MyAdminTools

- Adding new functions to this cheatsheet:
  * If you keep it as a .ps1 script (dot-sourced):
      - Open the file and add a new function block anywhere in the file (preferably near other helpers).
      - Save the file, then re-dot-source it:
          . "$env:USERPROFILE\Documents\PowerShell\CheatSheet_AD_Azure.ps1"
      - The updated functions will replace the definitions in your session.
  * If you convert to a module (.psm1):
      - Add the function to the .psm1 file.
      - Add the function name to Export-ModuleMember, for example:
            Export-ModuleMember -Function Test-IsElevated, Ensure-PSVersion, Get-MyThing
      - Bump version in the manifest as needed and re-import:
            Import-Module MyAdminTools -Force
  * Best practice:
      - Keep functions small and single-purpose.
      - Add comment-based help to each function for Get-Help support.
      - Write unit tests where possible (Pester) and store scripts in source control.

- Permissions, ExecutionPolicy and install scope:
    * For per-user installs and no Admin:
        - Use -Scope CurrentUser when running Install-Module.
        - Example: Install-Module -Name Az.Resources -Scope CurrentUser
    * To install RSAT / system components:
        - You must run PowerShell elevated (Administrator).
        - Example (Windows 11, Admin):
            Add-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'
    * Recommended ExecutionPolicy for daily use:
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force

- Quick verification / test commands after saving & loading:
    # dot-source and test
    . "$env:USERPROFILE\Documents\PowerShell\CheatSheet_AD_Azure.ps1"
    Test-IsElevated
    Ensure-PSVersion -MinimumMajor 5
    Ensure-Tls12
    Ensure-NuGetProvider
    Ensure-PSGalleryTrusted

- Notes:
    * ActiveDirectory module is Windows-only (requires RSAT or domain controller).
    * In PowerShell 7+ you can proxy WinPS modules with:
        Import-Module ActiveDirectory -UseWindowsPowerShell
      (only valid in pwsh on Windows; not available in Windows PowerShell 5.1)
    * Keep secrets out of scripts. Use Key Vault or secure prompts for credentials.

# End of header instructions
# -------------------------
# Helper functions
# -------------------------
function Test-IsElevated {
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Ensure-PSVersion {
    param([int] $MinimumMajor = 5)
    $pv = $PSVersionTable.PSVersion
    if ($pv.Major -lt $MinimumMajor) {
        Write-Error "PowerShell $MinimumMajor or later is required. You are running $pv."
        return $false
    }
    Write-Host "PowerShell version OK: $pv"
    return $true
}

function Ensure-Tls12 {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-Host "TLS 1.2 enabled for the session."
        return $true
    } catch {
        Write-Warning "Could not enable TLS 1.2: $_"
        return $false
    }
}

function Ensure-NuGetProvider {
    try {
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Write-Host "Installing NuGet provider..."
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        }
        Write-Host "NuGet provider is available."
        return $true
    } catch {
        Write-Warning "Ensure-NuGetProvider failed: $_"
        return $false
    }
}

function Ensure-PSGalleryTrusted {
    try {
        $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if (-not $repo) {
            Register-PSRepository -Default
            $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        }
        if ($repo -and $repo.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Write-Host "PSGallery set to Trusted."
        } else {
            Write-Host "PSGallery already trusted."
        }
        return $true
    } catch {
        Write-Warning "Could not ensure PSGallery trusted: $_"
        return $false
    }
}

function Install-ModuleIfMissing {
    param(
        [Parameter(Mandatory=$true)][string] $Name,
        [string] $MinimumVersion = '',
        [ValidateSet('CurrentUser','AllUsers')][string] $Scope = 'CurrentUser',
        [switch] $AllowClobber
    )
    try {
        $installed = Get-InstalledModule -Name $Name -ErrorAction SilentlyContinue
        if ($installed) {
            if ($MinimumVersion -and ([version]$installed.Version -lt [version]$MinimumVersion)) {
                Write-Host "Updating $Name to meet minimum version $MinimumVersion..."
                Update-Module -Name $Name -Force -ErrorAction SilentlyContinue
            } else {
                Write-Host "$Name already installed (version $($installed.Version))."
                return $true
            }
        } else {
            $params = @{ Name = $Name; Scope = $Scope; Force = $true }
            if ($AllowClobber) { $params['AllowClobber'] = $true }
            Write-Host "Installing module $Name (Scope=$Scope)..."
            Install-Module @params -ErrorAction Stop
        }
        return $true
    } catch {
        Write-Warning "Install-ModuleIfMissing failed for $Name: $_"
        return $false
    }
}

function Ensure-AzModule {
    param(
        [ValidateSet('Full','ResourcesOnly')]
        [string] $Mode = 'ResourcesOnly'
    )
    if ($Mode -eq 'Full') {
        Install-ModuleIfMissing -Name Az -Scope CurrentUser -AllowClobber
    } else {
        Install-ModuleIfMissing -Name Az.Resources -Scope CurrentUser
        Install-ModuleIfMissing -Name Az.Accounts -Scope CurrentUser -AllowClobber
    }
    # Import modules if available (non-fatal)
    Import-Module Az.Resources -ErrorAction SilentlyContinue
    Import-Module Az.Accounts -ErrorAction SilentlyContinue
}

function Ensure-MicrosoftGraph {
    Install-ModuleIfMissing -Name Microsoft.Graph -Scope CurrentUser -AllowClobber
    # optionally import common submodules
    Import-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue
    Import-Module Microsoft.Graph.Groups -ErrorAction SilentlyContinue
}

function Ensure-AzureADModule {
    Install-ModuleIfMissing -Name AzureAD -Scope CurrentUser
    Import-Module AzureAD -ErrorAction SilentlyContinue
}

function Ensure-ActiveDirectoryModule {
    $mod = Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue
    if ($mod) {
        Write-Host "ActiveDirectory module available (version $($mod.Version))."
        return $true
    }

    Write-Warning "ActiveDirectory module not found. RSAT must be installed on Windows."
    if (-not $IsWindows) {
        Write-Warning "ActiveDirectory is Windows-only."
        return $false
    }

    if (-not (Test-IsElevated)) {
        Write-Warning "Installing RSAT requires Administrator. Re-run PowerShell elevated to install."
        return $false
    }

    try {
        Write-Host "Attempting to install RSAT Active Directory tools..."
        $capName = 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'
        $cap = Get-WindowsCapability -Online -Name $capName -ErrorAction SilentlyContinue
        if ($cap -and $cap.State -ne 'Installed') {
            Add-WindowsCapability -Online -Name $capName
            Write-Host "RSAT Active Directory tools installed. Restart PowerShell to use ActiveDirectory module."
        } elseif ($cap -and $cap.State -eq 'Installed') {
            Write-Host "RSAT already installed."
        } else {
            Write-Warning "RSAT capability not found; install via Settings -> Optional features."
        }
        return $true
    } catch {
        Write-Warning "Failed to install RSAT: $_"
        return $false
    }
}
# -------------------------
# End of helper functions
# -------------------------