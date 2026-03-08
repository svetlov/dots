# Hibernate if battery < 15% and user idle > 60 minutes
Add-Type @"
using System;
using System.Runtime.InteropServices;

public struct LASTINPUTINFO {
    public uint cbSize;
    public uint dwTime;
}

public class IdleTime {
    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    public static uint GetIdleMinutes() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        GetLastInputInfo(ref lii);
        return (uint)((Environment.TickCount - lii.dwTime) / 60000);
    }
}
"@

$battery = Get-CimInstance -ClassName Win32_Battery
if (-not $battery) { exit }

$pct = $battery.EstimatedChargeRemaining
$charging = $battery.BatteryStatus -eq 2  # 2 = AC/charging
$idleMin = [IdleTime]::GetIdleMinutes()

if ((-not $charging) -and ($pct -lt 15) -and ($idleMin -ge 60)) {
    # Log and hibernate
    $msg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Battery=${pct}% Idle=${idleMin}min - Hibernating"
    $msg | Out-File -Append "$env:ProgramData\PowerScripts\hibernate.log"
    & shutdown /h
}
