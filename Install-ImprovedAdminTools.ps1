# Install-ImprovedAdminTools.ps1
# Script to install the ImprovedAdminTools PowerShell module

# Ensure the system meets prerequisites
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "PowerShell 5.0 or later is required. Please upgrade your PowerShell version."
    return
}

# Define paths for installation and zip file
$ModulePath = Join-Path $HOME "Documents\PowerShell\Modules\ImprovedAdminTools"
$ZipFilePath = Join-Path $HOME "Desktop\ImprovedAdminTools.zip"

try {
    # Check if the module already exists
    if (Test-Path -Path $ModulePath) {
        $response = Read-Host "ImprovedAdminTools already exists. Do you want to overwrite it? (Y/N)"
        if ($response -notmatch "^(Y|y)$") {
            Write-Host "Installation skipped." -ForegroundColor Yellow
            return
        }

        # Remove the existing module
        Remove-Item -Recurse -Force -Path $ModulePath
        Write-Host "Existing module removed." -ForegroundColor Yellow
    }

    # Inform the user of the download process
    Write-Progress -Activity "Installing ImprovedAdminTools" -Status "Downloading ZIP file..."
    Invoke-WebRequest `
        -Uri "https://github.com/djones0405/ImprovedAdminTools/archive/main.zip" `
        -OutFile $ZipFilePath

    Write-Progress -Activity "Installing ImprovedAdminTools" -Status "Extracting ZIP file..."
    # Extract the ZIP file into the modules folder
    Expand-Archive -Path $ZipFilePath -DestinationPath (Join-Path $HOME "Documents\PowerShell\Modules") -Force

    # Verify installation completion
    if (Test-Path -Path $ModulePath) {
        Write-Host "ImprovedAdminTools installed successfully!" -ForegroundColor Green
        Write-Host "To load the module, use: 'Import-Module ImprovedAdminTools'." -ForegroundColor Cyan
    } else {
        Write-Error "Installation failed. The ImprovedAdminTools module is not available in the specified path."
    }
} catch {
    # Handle errors during the installation process
    Write-Error "An error occurred during installation: $($_.Exception.Message)"
} finally {
    # Cleanup temporary files
    if (Test-Path -Path $ZipFilePath) {
        Remove-Item -Path $ZipFilePath -Force
        Write-Host "Temporary files cleaned up." -ForegroundColor Yellow
    }
}