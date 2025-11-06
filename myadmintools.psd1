@{
  Description = 'MyAdminTools admin helpers'
  CompatiblePSEditions = @('Core')
  PowerShellVersion = '7.2'
  FunctionsToExport = @('Test-IsElevated', 'Ensure-PSVersion', 'Ensure-Tls12', 'Ensure-NuGetProvider', 'Ensure-PSGalleryTrusted')
  GUID = '00000000-0000-0000-0000-000000000000'
  Author = 'djones0405'
  FileList = @('MyAdminTools.psm1')
  RootModule = 'MyAdminTools.psm1'
  ModuleVersion = '1.0.0'
}
