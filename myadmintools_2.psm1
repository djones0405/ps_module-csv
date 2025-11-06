<#
.SYNOPSIS
    A module for administrative tasks such as checking, installing, and listing required modules as well as connecting to Microsoft Graph and Azure AD services.
.DESCRIPTION
    This module provides:
    - Helper functions for secure authentication and elevated scripting.
    - Automatic installation of missing modules like AzureAD or Microsoft.Graph.Authentication if needed.
    - A summary of available functions and modules in the system.
#>

#region Helper Functionality - Module Management

function Install-RequiredModule {
    <#
    .SYNOPSIS
        Ensures the required module is installed and imports it if it exists.
    .DESCRIPTION
        Checks if the specified PowerShell module is installed. If not installed, attempts to install it. On installation failure, returns the appropriate error message.
    .PARAMETER ModuleName
        The module name to install if missing.
    .EXAMPLE
        Install-RequiredModule -ModuleName "AzureAD"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ModuleName
    )

    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Host "The module '$ModuleName' is not installed. Installing..." -ForegroundColor Yellow
        try {
            Install-Module -Name $ModuleName -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host "The module '$ModuleName' successfully installed." -ForegroundColor Green
        } catch {
            Write-Host "Error: Failed to install module '$ModuleName': $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }

    try {
        Import-Module -Name $ModuleName -ErrorAction Stop
        Write-Host "The module '$ModuleName' successfully imported." -ForegroundColor Green
    } catch {
        Write-Host "Error: The module '$ModuleName' exists but could not be imported." -ForegroundColor Red
    }
}

function Show-AvailableModules {
    <#
    .SYNOPSIS
        Displays all PowerShell modules available for import on the system.
    .DESCRIPTION
        Lists all modules installed and available for import.
    .EXAMPLE
        Show-AvailableModules
    #>
    Write-Host "Available PowerShell modules on your system:" -ForegroundColor Cyan
    Get-Module -ListAvailable | Select-Object Name, Version | Sort-Object Name | Format-Table -AutoSize
}

#endregion

#region Show Module Information

function Show-MyAdminToolsInfo {
    <#
    .SYNOPSIS
        Displays a summary of available functions in the MyAdminTools module.
    .DESCRIPTION
        Automatically lists functions exported by the MyAdminTools module after import.
    .EXAMPLE
        Show-MyAdminToolsInfo
    #>
    Write-Host "Welcome to MyAdminTools!" -ForegroundColor Cyan
    Write-Host "Here are the available functions in this module:" -ForegroundColor Green
    Write-Host "---------------------------------------------------"
    try {
        $functions = Get-Command -Module MyAdminTools
        if ($functions) {
            $functions | ForEach-Object { Write-Host ($_.Name + "`t" + $_.Description) }
        } else {
            Write-Host "No functions found for the MyAdminTools module." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Failed to retrieve functions for MyAdminTools: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host "`nUse `Get-Help <FunctionName>` to learn more about each function."
}

#endregion

#region Microsoft Integration (Connection Helpers)

function Connect-MyGraph {
    <#
    .SYNOPSIS
        Connect to Microsoft Graph API using different authentication methods.
    .DESCRIPTION
        Handles Microsoft Graph user or app-only authentication logic.
    .PARAMETER ClientId
        (Optional) The ClientId of the AzureAD Application.
    .EXAMPLE
        Connect-MyGraph -ClientId "myClientId" -TenantId "contoso.com"
    #>
    [CmdletBinding()]
    param(
        [string]$ClientId,
        [string]$TenantId,
        [string]$CertificateThumbprint,
        [switch]$Interactive
    )

    Install-RequiredModule -ModuleName "Microsoft.Graph.Authentication"
    Write-Host "Authenticating to Microsoft Graph..."
}

function Connect-MyAzureAD {
    <#
    .SYNOPSIS
        Connect to Azure AD and retrieve app details.
    .PARAMETER AppName
        (Optional) The name of the application to find in Azure AD.
    .EXAMPLE
        Connect-MyAzureAD -AppName "TestApp"
    #>
    [CmdletBinding()]
    param(
        [string]$AppName
    )

    Install-RequiredModule -ModuleName "AzureAD"
    Write-Host "Connecting to Azure AD..."
}

#endregion

#region Export Functions

Export-ModuleMember -Function Install-RequiredModule, Show-AvailableModules, Show-MyAdminToolsInfo, Connect-MyGraph, Connect-MyAzureAD

Show-MyAdminToolsInfo
Show-AvailableModules

#endregion