<#
.SYNOPSIS
  Run this script interactively to bootstrap a workstation: install Az, Microsoft.Graph, ExchangeOnlineManagement, etc.
.DESCRIPTION
  This script intentionally calls the installer helpers from MyAdminTools module. Run it manually (not at module import).
#>

# Load module (per-user module path)
Import-Module MyAdminTools -ErrorAction Stop

# Prepare session
Ensure-Tls12 | Out-Null
Ensure-NuGetProvider | Out-Null
Ensure-PSGalleryTrusted | Out-Null

# Install recommended modules (per-user)
Write-Host "Installing Az.Accounts and Az.Resources..."
Install-ModuleIfMissing -Name Az.Accounts -Scope CurrentUser -AllowClobber
Install-ModuleIfMissing -Name Az.Resources -Scope CurrentUser

Write-Host "Installing Microsoft.Graph..."
Install-ModuleIfMissing -Name Microsoft.Graph -Scope CurrentUser -AllowClobber

Write-Host "Installing ExchangeOnlineManagement..."
Install-ModuleIfMissing -Name ExchangeOnlineManagement -Scope CurrentUser

Write-Host "Bootstrap complete. Start a new PowerShell session to load newly installed modules."
# End of bootstrap scriptMicrosoft.Graph.Authentication Connect-MgGraph -Scopes "Application.Read.All","Directory.Read.All"