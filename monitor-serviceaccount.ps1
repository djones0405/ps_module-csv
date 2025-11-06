<#
    Monitor-ServiceAccount-Lockout.ps1

    PURPOSE:
    Monitors a specified Active Directory service account for lockout events (Event ID 4740) by querying the Security event log every 5 minutes.
    When a lockout is detected, the script identifies the device (Caller Computer Name) that caused the lockout and sends an alert email to the helpdesk.
    All actions and errors are logged with debug-level detail to a specified log file.

    USAGE:
      1. Configure the variables:
          - $ServiceAccount: The service account to monitor (e.g., "MFDSCAN")
          - $EmailTo: Email recipient for alerts (e.g., "helpdesk@youragency.com")
          - $EmailFrom: Sender email address for alerts
          - $SmtpServer: SMTP server for sending email
          - $LogFile: Path to the log file (e.g., "C:\Temp\ServiceAccountLockoutMonitor.log")
      2. Schedule this script to run every 5 minutes using Windows Task Scheduler.
      3. Ensure the script runs with appropriate privileges to read the Security event log.

    LOGGING:
    - All operations, including queries, email attempts, and errors, are logged to the file specified by $LogFile and to the PowerShell debug stream.

    TESTING:
    - For testing, you can simulate an event or comment/uncomment the Send-MailMessage line.
    - Review $LogFile for debug output.

    AUTHOR:
    - Danny Jones

#>

# Configurable variables
$ServiceAccount = "MFDSCAN"
$EmailTo = "helpdesk@ahca.myflorida.com"
$EmailFrom = "alert@ahca.myflorida.com"
$SmtpServer = "smtp.ahca.myflorida.com"
$LogFile = "C:\logfiles\ServiceAccountLockoutMonitor.log"
$DebugPreference = "Continue" # Enables debug logging

function Write-DebugLog {
    param(
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"
    Write-Debug $entry
    Add-Content -Path $LogFile -Value $entry
}

Write-DebugLog "==== Script execution started ===="

try {
    Write-DebugLog "Querying Security event log for lockout events (Event ID 4740) for account '$ServiceAccount' in the last 5 minutes."
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        Id = 4740
        StartTime = (Get-Date).AddMinutes(-5)
    } | Where-Object { $_.Properties[0].Value -eq $ServiceAccount }

    if ($events.Count -gt 0) {
        Write-DebugLog "Found $($events.Count) lockout event(s) for account '$ServiceAccount'."
        foreach ($event in $events) {
            $device = $event.Properties[1].Value
            $time = $event.TimeCreated
            $body = @"
Service account '$ServiceAccount' was locked out.

Time: $time
Device (Caller Computer Name): $device

This likely means the scanner at device '$device' has an incorrect password configured. Please check and update the credentials on this scanner to prevent further disruptions.
"@
            Write-DebugLog "Preparing to send alert email for lockout from device '$device' at '$time'."
            Write-DebugLog "Email body:`n$body"
            try {
                Send-MailMessage -To $EmailTo -From $EmailFrom -Subject "ALERT: Scanner Service Account Locked Out" -Body $body -SmtpServer $SmtpServer
                Write-DebugLog "Email successfully sent to $EmailTo."
            } catch {
                Write-DebugLog "ERROR: Failed to send email. $_"
            }
        }
    } else {
        Write-DebugLog "No lockout events found for account '$ServiceAccount' in the last 5 minutes."
    }
} catch {
    Write-DebugLog "ERROR: Exception occurred - $_"
}

Write-DebugLog "==== Script execution finished ===="