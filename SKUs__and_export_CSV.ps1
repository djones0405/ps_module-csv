# fetch SKUs and export to CSV
$response = Invoke-MgGraphRequest -Method Get -Uri "https://graph.microsoft.com/v1.0/subscribedSkus"
$response.value |
  Select-Object skuPartNumber,
    @{Name='Enabled'; Expression = { $_.prepaidUnits.enabled }},
    @{Name='Consumed'; Expression = { $_.consumedUnits }},
    @{Name='Available'; Expression = { ($_.prepaidUnits.enabled) - ($_.consumedUnits) }} |
  Export-Csv -Path "C:\Temp\SubscribedSkus.csv" -NoTypeInformation -Encoding UTF8