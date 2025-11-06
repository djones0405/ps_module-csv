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
    - Connecting to Microsoft Graph and Azure AD services.
#>

#region Helper Functionality - Module Management

function Ensure-ModuleStructure {
    <#
    .SYNOPSIS
        Ensures a PowerShell module structure exists and creates the necessary .psm1 file.
    .DESCRIPTION
        Dynamically creates a folder structure for the module inside the
        `$HOME\Documents\WindowsPowerShell\Modules` directory.
    .PARAMETER ModuleName
        The name of the module.
    .PARAMETER ModuleVersion
        The version of the module (e.g., "1.0.0").
    .EXAMPLE
        Ensure-ModuleStructure -ModuleName "CustomAdminTools" -ModuleVersion "1.0.0"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        
        [Parameter(Mandatory = $true)]
        [string]$ModuleVersion
    )

    # Define paths dynamically
    $currentUser = $env:USERNAME
    $modulePath = "C:\Users\$currentUser\Documents\WindowsPowerShell\Modules\$ModuleName\$ModuleVersion"
    $moduleFile = Join-Path -Path $modulePath -ChildPath "$ModuleName.psm1"

    # Ensure the directory exists
    if (-not (Test-Path -Path $modulePath)) {
        New-Item -ItemType Directory -Force -Path $modulePath | Out-Null
        Write-Host "Created directory: $modulePath" -ForegroundColor Green
    } else {
        Write-Host "Directory already exists: $modulePath" -ForegroundColor Yellow
    }

    # Create or overwrite the .psm1 file
    if (-not (Test-Path -Path $moduleFile)) {
        New-Item -ItemType File -Force -Path $moduleFile | Out-Null
        Write-Host "Created .psm1 file: $moduleFile" -ForegroundColor Green
    } else {
        Write-Host "The .psm1 file already exists: $moduleFile" -ForegroundColor Yellow
    }

    # Open file in editor
    Invoke-Item -Path $moduleFile
    Write-Host "Your module file is ready for editing at: $moduleFile" -ForegroundColor Cyan
}

function Install-RequiredModule {
    <#
    .SYNOPSIS
        Ensures that the specified module is installed and imports it if available.
    .DESCRIPTION
        Verifies whether the specified PowerShell module is installed. If not installed,
        it attempts to fetch it from the PowerShell Gallery. Finally, it imports the module.
    .PARAMETER ModuleName
        The name of the module to install and import.
    .EXAMPLE
        Install-RequiredModule -ModuleName "AzureAD"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ModuleName
    )

    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Host "The module '$ModuleName' is not installed. Installing..." -ForegroundColor Yellow
        try {
            Install-Module -Name $ModuleName -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host "The module '$ModuleName' successfully installed." -ForegroundColor Green
        } catch {
            Write-Host "Error: Failed to install the module '$ModuleName'. $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }

    try {
        Import-Module -Name $ModuleName -ErrorAction Stop
        Write-Host "The module '$ModuleName' successfully imported." -ForegroundColor Green
    } catch {
        Write-Host "Error: Could not import the module '$ModuleName'. Please investigate further." -ForegroundColor Red
    }
}

function Show-AvailableModules {
    <#
    .SYNOPSIS
        Displays all available PowerShell modules installed on the system.
    .DESCRIPTION
        Lists the modules available to the current PowerShell session, optionally filtered by name.
    .PARAMETER Filter
        A filter that gets applied to module names (e.g., "Azure").
    .EXAMPLE
        Show-AvailableModules
    .EXAMPLE
        Show-AvailableModules -Filter "Azure"
    #>
    [CmdletBinding()]
    param(
        [string]$Filter
    )

    Write-Host "Available PowerShell modules on your system:" -ForegroundColor Cyan
    $modules = Get-Module -ListAvailable

    if ($Filter) {
        $modules = $modules | Where-Object { $_.Name -like "*$Filter*" }
    }

    $modules | Select-Object Name, Version, Path | Format-Table -AutoSize
}

#endregion

#region Module Search and Repository Management Functions

function Search-AzureModules {
    <#
    .SYNOPSIS
        Searches for "Azure" modules in the PowerShell Gallery.
    .DESCRIPTION
        Searches and displays a limited list of Azure-related modules from the gallery.
    .PARAMETER MaxResults
        The maximum number of results to display.
    .EXAMPLE
        Search-AzureModules
    .EXAMPLE
        Search-AzureModules -MaxResults 5
    #>
    [CmdletBinding()]
    param(
        [int]$MaxResults = 20
    )

    Write-Host "Searching for Azure modules in the PowerShell Gallery..." -ForegroundColor Cyan
    Find-Module -Name "*Azure*" | Select-Object Name, Version, Description | Select-Object -First $MaxResults | Format-Table -AutoSize
}

function List-PSRepositories {
    <#
    .SYNOPSIS
        Lists registered repositories in PowerShell.
    .DESCRIPTION
        Displays all available repositories registered in the PowerShell environment.
    .EXAMPLE
        List-PSRepositories
    #>
    Write-Host "Listing registered PowerShell repositories..." -ForegroundColor Cyan
    $repositories = Get-PSRepository -ErrorAction SilentlyContinue

    if (-not $repositories) {
        Write-Host "No repositories registered." -ForegroundColor Yellow
        return
    }

    $repositories | Format-Table -AutoSize
}

#endregion

#region Microsoft Integration (Connection Helpers)

function Connect-MyGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph API.
    .EXAMPLE
        Connect-MyGraph
    #>
    [CmdletBinding()]
    param()

    Install-RequiredModule -ModuleName "Microsoft.Graph.Authentication"
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
}

#endregion

#region Export Functions and Initialization

Export-ModuleMember -Function Ensure-ModuleStructure, Install-RequiredModule, Show-AvailableModules, Search-AzureModules, List-PSRepositories, Connect-MyGraph

# Display module information
Ensure-ModuleStructure -ModuleName "ImprovedAdminTools" -ModuleVersion "1.0.0"

#endregion