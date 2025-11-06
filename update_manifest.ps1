<#
.SYNOPSIS
  Safely update a module .psd1 manifest keys (PowerShellVersion, CompatiblePSEditions, FunctionsToExport).

.DESCRIPTION
  - Creates a .bak
  - Loads manifest using Import-PowerShellDataFile when available
  - Optionally bootstraps TLS/NuGet/PowerShellGet if requested (-Bootstrap)
  - Updates keys; ensures FunctionsToExport contains given function names
  - Serializes safely (escapes single quotes), writes tmp file with UTF8 (no BOM), validates, atomically replaces
.PARAMETER ManifestPath
  Path to the module .psd1 manifest to update (required)
.PARAMETER PowerShellVersion
  Value to set for PowerShellVersion in the manifest (default '7.2')
.PARAMETER CompatiblePSEditions
  Array of CompatiblePSEditions to set (default 'Core')
.PARAMETER EnsureFunctions
  Functions that must appear in FunctionsToExport (merged with any existing entries)
.PARAMETER Bootstrap
  If set, attempt to set TLS and install NuGet provider and PowerShellGet if Import-PowerShellDataFile is missing.
.EXAMPLE
  .\Update-ModuleManifest.ps1 -ManifestPath .\MyModule\MyModule.psd1 -Bootstrap
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)][string] $ManifestPath,
    [string] $PowerShellVersion = '7.2',
    [string[]] $CompatiblePSEditions = @('Core'),
    [string[]] $EnsureFunctions = @('Connect-MyGraph','Connect-MyExchange'),
    [switch] $Bootstrap
)

function Ensure-Preflight {
    param()

    # Ensure TLS 1.2 and NuGet provider (no-op if present)
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
    } catch {
        Write-Verbose "Install-PackageProvider failed: $($_.Exception.Message)"
    }

    # Ensure PowerShellGet (so Import-PowerShellDataFile is present on older hosts)
    $ipdf = Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue
    if (-not $ipdf) {
        try {
            Install-Module -Name PowerShellGet -Scope CurrentUser -Force -ErrorAction Stop -AllowClobber | Out-Null
        } catch {
            Write-Verbose "Failed to install PowerShellGet: $($_.Exception.Message)"
        }
    }
}

# Simple serializer for psd1 values
function ConvertValueToPsd1Literal {
    param($v)
    if ($null -eq $v) { return "$null" }
    if ($v -is [string]) {
        $escaped = $v -replace "'", "''"
        return "'$escaped'"
    }
    if ($v -is [bool]) { return $v.ToString().ToLower() }
    if ($v -is [version] -or $v -is [int] -or $v -is [double]) { return $v.ToString() }

    if ($v -is [System.Collections.IDictionary]) {
        $entries = @()
        foreach ($kv in $v.GetEnumerator()) {
            $key = $kv.Key
            $val = ConvertValueToPsd1Literal $kv.Value
            $entries += ("  {0} = {1}" -f $key, $val)
        }
        return "@{" + [System.Environment]::NewLine + ($entries -join [System.Environment]::NewLine) + [System.Environment]::NewLine + "}"
    }

    if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
        $items = @()
        foreach ($item in $v) { $items += (ConvertValueToPsd1Literal $item) }
        # render short list inline if small
        if ($items.Count -le 3) {
            return "@(" + ($items -join ", ") + ")"
        } else {
            $lines = "@(" + [System.Environment]::NewLine
            foreach ($it in $items) { $lines += "  $it," + [System.Environment]::NewLine }
            $lines = $lines.TrimEnd([System.Environment]::NewLine)
            $lines += [System.Environment]::NewLine + ")"
            return $lines
        }
    }

    # Fallback
    $escaped = ($v.ToString()) -replace "'", "''"
    return "'$escaped'"
}

if (-not (Test-Path -Path $ManifestPath -PathType Leaf)) {
    throw "Manifest not found: $ManifestPath"
}

if ($Bootstrap) {
    Write-Verbose "Bootstrapping prerequisites..."
    Ensure-Preflight
}

# Ensure Import-PowerShellDataFile is available
$ipdf = Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue
if (-not $ipdf) {
    throw "Import-PowerShellDataFile not available. Run in PowerShell 7+ or re-run with -Bootstrap to attempt to install prerequisites."
}

# Make a backup
$bak = "$ManifestPath.bak"
if ($PSCmdlet.ShouldProcess("Create backup", $bak)) {
    Copy-Item -Path $ManifestPath -Destination $bak -Force
}

# Load manifest
try {
    $manifest = Import-PowerShellDataFile -Path $ManifestPath -ErrorAction Stop
} catch {
    throw "Failed to import manifest: $($_.Exception.Message)"
}

# Update fields
$manifest.PowerShellVersion = $PowerShellVersion
$manifest.CompatiblePSEditions = $CompatiblePSEditions

# Ensure FunctionsToExport contains required names
if ($manifest.ContainsKey('FunctionsToExport')) {
    $existing = $manifest.FunctionsToExport
    if (-not ($existing -is [System.Collections.IEnumerable] -and -not ($existing -is [string]))) {
        $existing = ,$existing
    }
    $merged = ($existing + $EnsureFunctions) | Select-Object -Unique
    $manifest.FunctionsToExport = $merged
} else {
    $manifest.FunctionsToExport = $EnsureFunctions
}

# Ordered key emission
$orderedKeys = @('RootModule','ModuleVersion','GUID','Author','CompanyName','Copyright','Description','PowerShellVersion','CompatiblePSEditions','FunctionsToExport','CmdletsToExport','VariablesToExport','AliasesToExport','FileList','RequiredModules','RequiredAssemblies','ScriptsToProcess','PrivateData')

$lines = "@{" + [System.Environment]::NewLine
foreach ($k in $orderedKeys) {
    if ($manifest.ContainsKey($k)) {
        $literal = ConvertValueToPsd1Literal $manifest[$k]
        $lines += "  $k = $literal" + [System.Environment]::NewLine
    }
}
# emit remaining keys
foreach ($kv in $manifest.GetEnumerator() | Where-Object { $orderedKeys -notcontains $_.Key }) {
    $k = $kv.Key
    $literal = ConvertValueToPsd1Literal $kv.Value
    $lines += "  $k = $literal" + [System.Environment]::NewLine
}
$lines += "}" + [System.Environment]::NewLine

# Write to temp file with UTF8 no BOM
$tmp = "$ManifestPath.tmp"
try {
    $enc = New-Object System.Text.UTF8Encoding($false)  # no BOM
    [System.IO.File]::WriteAllText($tmp, $lines, $enc)
} catch {
    Set-Content -Path $tmp -Value $lines -Encoding UTF8
}

# Validate by attempting to import the temp manifest
try {
    Import-PowerShellDataFile -Path $tmp -ErrorAction Stop | Out-Null
} catch {
    # restore from backup
    Copy-Item -Path $bak -Destination $ManifestPath -Force
    Remove-Item -Path $tmp -ErrorAction SilentlyContinue
    throw "Validation failed after update. Manifest restored from backup. Error: $($_.Exception.Message)"
}

# Replace manifest atomically
if ($PSCmdlet.ShouldProcess($ManifestPath, "Replace manifest with updated version")) {
    Move-Item -Path $tmp -Destination $ManifestPath -Force
    Write-Host "Manifest updated: $ManifestPath (backup: $bak)"
}