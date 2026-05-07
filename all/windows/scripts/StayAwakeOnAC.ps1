# StayAwakeOnAC.ps1
# Holds ES_SYSTEM_REQUIRED power request while on AC power.
# This prevents Modern Standby from reaching DRIPS (GPU power-gating)
# while still allowing the display to turn off.
# On battery, the request is released so normal standby works.

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PowerState {
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);
    public const uint ES_CONTINUOUS      = 0x80000000;
    public const uint ES_SYSTEM_REQUIRED = 0x00000001;
}
"@

$logFile = "C:\ProgramData\PowerScripts\stay-awake.log"
function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    "$ts $msg" | Out-File -Append -FilePath $logFile -Encoding utf8
}

$lastState = $null

Log "StayAwakeOnAC started"

while ($true) {
    $status = Get-CimInstance -ClassName BatteryStatus -Namespace root/WMI -ErrorAction SilentlyContinue
    $onAC = ($null -eq $status) -or (-not $status.Discharging)

    if ($onAC -and $lastState -ne "AC") {
        [PowerState]::SetThreadExecutionState(
            [PowerState]::ES_CONTINUOUS -bor [PowerState]::ES_SYSTEM_REQUIRED
        ) | Out-Null
        Log "ON AC - holding SYSTEM_REQUIRED (blocking DRIPS)"
        $lastState = "AC"
    }
    elseif (-not $onAC -and $lastState -ne "DC") {
        [PowerState]::SetThreadExecutionState([PowerState]::ES_CONTINUOUS) | Out-Null
        Log "ON BATTERY - released SYSTEM_REQUIRED (normal standby)"
        $lastState = "DC"
    }

    Start-Sleep -Seconds 30
}
