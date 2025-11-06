<#
.SYNOPSIS
    A module for administrative tasks such as improving module management, automating script creation,
    and managing PowerShell modules and repositories.
.DESCRIPTION
    This module provides utilities for:
    - Dynamically creating module structures and handling .psm1 files.
    - Checking, installing, and importing required modules.
    - Searching for modules in the PowerShell Gallery.
    - Managing PowerShell repositories.
    - Connecting to Microsoft Exchange Online, Microsoft Graph, and Azure AD services.
    - Displaying summaries of available functions and help examples.
#>

#region Helper Functionality - Module Management

function Ensure-ModuleStructure {
    <#
    .SYNOPSIS
        Ensures a PowerShell module structure exists and creates the necessary .psm1 file.
    .DESCRIPTION
        Dynamically creates a folder structure and initializes the module `.psm1` file.
    .PARAMETER ModuleName
        The name of the module.
    .PARAMETER ModuleVersion
        The module version, e.g., "1.0.0".
    .EXAMPLE
        Ensure-ModuleStructure -ModuleName "MyAdminTools" -ModuleVersion "1.0.0"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ModuleName,
        [Parameter(Mandatory = $true)][string]$ModuleVersion
    )

    $currentUser = $env:USERNAME
    $modulePath = "C:\Users\$currentUser\Documents\WindowsPowerShell\Modules\$ModuleName\$ModuleVersion"
    $moduleFile = Join-Path $modulePath "$ModuleName.psm1"

    if (-not (Test-Path $modulePath)) {
        New-Item -ItemType Directory -Force -Path $modulePath | Out-Null
        Write-Host "Created directory: $modulePath" -ForegroundColor Green
    } else {
        Write-Host "Directory already exists: $modulePath" -ForegroundColor Yellow
    }

    if (-not (Test-Path $moduleFile)) {
        New-Item -ItemType File -Force -Path $moduleFile | Out-Null
        Write-Host "Created .psm1 file: $moduleFile" -ForegroundColor Green
    } else {
        Write-Host "The .psm1 file already exists: $moduleFile" -ForegroundColor Yellow
    }
    Invoke-Item $moduleFile
}

function Install-RequiredModule {
    <#
    .SYNOPSIS
        Ensures a required module is installed and imports it.
    .PARAMETER ModuleName
        The name of the required module.
    .EXAMPLE
        Install-RequiredModule -ModuleName "AzureAD"
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ModuleName)

    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Host "Installing module '$ModuleName'..." -ForegroundColor Yellow
        try {
            Install-Module -Name $ModuleName -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host "Module '$ModuleName' was successfully installed." -ForegroundColor Green
        } catch {
            Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }
    Import-Module -Name $ModuleName -ErrorAction Stop
    Write-Host "Module '$ModuleName' imported successfully." -ForegroundColor Green
}

function Show-AvailableModules {
    <#
    .SYNOPSIS
        Lists all modules installed locally.
    .EXAMPLE
        Show-AvailableModules
    #>
    Write-Host "Installed PowerShell Modules:" -ForegroundColor Cyan
    Get-Module -ListAvailable | Select-Object Name, Version, Path | Format-Table -AutoSize
}

#endregion

#region Additional and Missing Functions

function Register-NewPSRepository {
    <#
    .SYNOPSIS
        Registers a new PowerShell repository.
    .PARAMETER Name
        The name of the repository.
    .PARAMETER SourceLocation
        URL for the repository’s source location.
    .PARAMETER InstallationPolicy
        Either "Trusted" or "Untrusted".
    .EXAMPLE
        Register-NewPSRepository -Name "TestRepo" -SourceLocation "https://example.com/"
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$SourceLocation,
        [ValidateSet("Trusted", "Untrusted")][string]$InstallationPolicy = "Trusted"
    )
    Register-PSRepository -Name $Name -SourceLocation $SourceLocation -InstallationPolicy $InstallationPolicy
    Write-Host "Registered new repository '$Name'" -ForegroundColor Green
}

function Search-ModulesByTag {
    <#
    .SYNOPSIS
        Searches the PowerShell Gallery for modules by tag.
    .PARAMETER Tag
        The tag to search for.
    .EXAMPLE
        Search-ModulesByTag -Tag "Security"
    #>
    [CmdletBinding()]
    param([string]$Tag)
    Find-Module -Tag $Tag | Select-Object Name, Version | Format-Table -AutoSize
}

#endregion

#region Initialization

Export-ModuleMember -Function *

Show-ImprovedAdminToolsInfo
#endregion