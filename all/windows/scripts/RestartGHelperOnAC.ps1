# Restart GHelper after:
# 1. AC plug-in during Modern Standby (Event 105 + Event 506 check)
# 2. User session switch (Event 25 — session reconnect)
# Scoped to current session only — safe with multiple user sessions.

$logFile = "$env:ProgramData\PowerScripts\ghelper-restart.log"
function Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') $msg" | Out-File -Append $logFile
}

Log "Script started (PID=$PID)"
$shouldRestart = $false
$trigger = "none"

# Check trigger 1: power source change during standby
$event105 = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=105} -MaxEvents 1 -ErrorAction SilentlyContinue
if ($event105) {
    $age = ((Get-Date) - $event105.TimeCreated).TotalSeconds
    Log "Event 105 at $($event105.TimeCreated.ToString('HH:mm:ss.fff')), age=${age}s"
    if ($age -lt 30) {
        $lastStandby = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=506,507} -MaxEvents 20 -ErrorAction SilentlyContinue |
            Where-Object { $_.TimeCreated -lt $event105.TimeCreated } |
            Select-Object -First 1
        if ($lastStandby) {
            Log "Last standby event before 105: Event $($lastStandby.Id) at $($lastStandby.TimeCreated.ToString('HH:mm:ss.fff'))"
        } else {
            Log "No standby event found before 105"
        }
        if ($lastStandby -and $lastStandby.Id -eq 506) {
            $battery = Get-CimInstance Win32_Battery
            Log "Battery status: $($battery.BatteryStatus) (2=AC)"
            if ($battery.BatteryStatus -eq 2) {
                $shouldRestart = $true
                $trigger = "standby-ac-plugin"
            }
        }
    } else {
        Log "Event 105 too old (${age}s > 30s), skipping"
    }
}

# Check trigger 2: session reconnect (user switch)
$event25 = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'; Id=25} -MaxEvents 1 -ErrorAction SilentlyContinue
if ($event25 -and ((Get-Date) - $event25.TimeCreated).TotalSeconds -lt 30) {
    $shouldRestart = $true
    $trigger = "session-reconnect"
    Log "Event 25 (session reconnect) at $($event25.TimeCreated.ToString('HH:mm:ss.fff'))"
}

if (-not $shouldRestart) {
    Log "No restart needed (trigger=$trigger), exiting"
    exit
}

Log "Will restart GHelper (trigger=$trigger), waiting 3s..."
Start-Sleep 3

$mySession = (Get-Process -Id $PID).SessionId
Log "My session: $mySession"
$gh = Get-Process GHelper -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $mySession }
if ($gh) {
    $ghPath = $gh[0].Path
    Log "Killing GHelper PID=$($gh[0].Id) Path=$ghPath"
    $gh | Stop-Process -Force
    Start-Sleep 2
    Log "Starting GHelper from $ghPath"
    Start-Process $ghPath
    Log "GHelper restarted"
} else {
    Log "No GHelper found in session $mySession"
}
