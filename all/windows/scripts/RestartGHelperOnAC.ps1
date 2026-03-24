# Start or restart GHelper and recover NVIDIA dGPU after:
# 1. AC plug-in during Modern Standby (Event 105 + Event 506 check)
# 2. User session switch (Event 25 — session reconnect)
# Scoped to current session only — safe with multiple user sessions.
# If GHelper is not running in the current session, starts it fresh.
# After GHelper restart, checks if NVIDIA dGPU is in error state and cycles it.

$ghDefaultPath = "C:\Program Files\G-Helper\GHelper.exe"

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
    # GHelper not running in this session — start it fresh
    $ghPath = $ghDefaultPath
    if (Test-Path $ghPath) {
        Log "No GHelper in session $mySession, starting from $ghPath"
        Start-Process $ghPath
        Log "GHelper started"
    } else {
        Log "GHelper not found at $ghPath"
    }
}

# Recover NVIDIA dGPU if it's in error state (CM_PROB_FAILED_POST_START)
Start-Sleep 5
$nv = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "NVIDIA" }
if ($nv) {
    if ($nv.Status -ne "OK") {
        Log "NVIDIA GPU in error state: Status=$($nv.Status) Problem=$($nv.Problem) — attempting recovery"
        $maxAttempts = 3
        for ($i = 1; $i -le $maxAttempts; $i++) {
            Log "dGPU recovery attempt $i/$maxAttempts"
            Disable-PnpDevice -InstanceId $nv.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep 5
            Enable-PnpDevice -InstanceId $nv.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep 5
            $nv = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "NVIDIA" }
            if ($nv.Status -eq "OK") {
                Log "dGPU recovered on attempt $i"
                break
            }
            Log "dGPU still in error after attempt $i: Status=$($nv.Status)"
        }
        if ($nv.Status -ne "OK") {
            Log "dGPU recovery FAILED after $maxAttempts attempts — reboot required"
        }
    } else {
        Log "NVIDIA GPU status OK, no recovery needed"
    }
} else {
    Log "No NVIDIA GPU found (Eco mode?)"
}
