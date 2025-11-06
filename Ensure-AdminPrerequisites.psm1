# Set manifest path
$manifestPath = 'C:\Users\jodaniel\Documents\WindowsPowerShell\Modules\MyAdminTools\1.0.0\MyAdminTools.psd1'
Copy-Item -Path $manifestPath -Destination "$manifestPath.bak" -Force

# Import safely (PowerShell 7+)
$manifest = Import-PowerShellDataFile -Path $manifestPath

# Modify fields programmatically
$manifest.PowerShellVersion = '7.2'                # string
$manifest.CompatiblePSEditions = @('Core')         # array
# (modify other keys as needed)
# e.g. $manifest.FunctionsToExport = @('Test-IsElevated','Ensure-PSVersion')

# Serializer helpers
function ConvertValueToPsd1Literal {
    param($v)
    switch -regex ($v.GetType().FullName) {
        '^System.String$' {
            return "'$v'"
        }
        '^System.Boolean$' {
            return $v.ToString().ToLower()
        }
        default {
            # Array?
            if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
                $items = @()
                foreach ($item in $v) { $items += (ConvertValueToPsd1Literal $item) }
                return "@(" + ($items -join ", ") + ")"
            }
            # Hashtable (nested)
            elseif ($v -is [hashtable]) {
                $lines = "@{"
                foreach ($kv in $v.GetEnumerator()) {
                    $lines += "`r`n  $($kv.Key) = " + (ConvertValueToPsd1Literal $kv.Value)
                }
                $lines += "`r`n}"
                return $lines
            }
            else {
                # numbers, version objects, etc.
                return $v.ToString()
            }
        }
    }
}

# Build the .psd1 content from the hashtable
$lines = "@{`r`n"
foreach ($kv in $manifest.GetEnumerator()) {
    $key = $kv.Key
    $val = $kv.Value
    $literal = ConvertValueToPsd1Literal $val
    # Add comma after each entry (acceptable in psd1)
    $lines += "  $key = $literal`r`n"
}
$lines += "}"

# Write out the new manifest (overwrites original; backup created earlier)
Set-Content -Path $manifestPath -Value $lines -Encoding UTF8

Write-Host "Manifest written to $manifestPath (backup at $manifestPath.bak)"