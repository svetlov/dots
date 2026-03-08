# Restart GHelper after:
# 1. AC plug-in during Modern Standby (Event 105 + Event 506 check)
# 2. User session switch (Event 25 — session reconnect)
# Scoped to current session only — safe with multiple user sessions.

$shouldRestart = $false

# Check trigger 1: power source change during standby
$event105 = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=105} -MaxEvents 1 -ErrorAction SilentlyContinue
if ($event105 -and ((Get-Date) - $event105.TimeCreated).TotalSeconds -lt 30) {
    $lastStandby = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=506,507} -MaxEvents 20 -ErrorAction SilentlyContinue |
        Where-Object { $_.TimeCreated -lt $event105.TimeCreated } |
        Select-Object -First 1
    if ($lastStandby -and $lastStandby.Id -eq 506) {
        $battery = Get-CimInstance Win32_Battery
        if ($battery.BatteryStatus -eq 2) { $shouldRestart = $true }
    }
}

# Check trigger 2: session reconnect (user switch)
$event25 = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'; Id=25} -MaxEvents 1 -ErrorAction SilentlyContinue
if ($event25 -and ((Get-Date) - $event25.TimeCreated).TotalSeconds -lt 30) {
    $shouldRestart = $true
}

if (-not $shouldRestart) { exit }

Start-Sleep 3

$mySession = (Get-Process -Id $PID).SessionId
$gh = Get-Process GHelper -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $mySession }
if ($gh) {
    $ghPath = $gh[0].Path
    $gh | Stop-Process -Force
    Start-Sleep 2
    Start-Process $ghPath
}
