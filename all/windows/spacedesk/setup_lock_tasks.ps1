# Setup scheduled tasks for Spacedesk lock/unlock display handling
# Run this script as admin to recreate the tasks after a reinstall
#
# What this does:
#   - On screen lock: switches display to "PC screen only" to avoid black screen on wake
#   - On screen unlock: switches back to "Extend" mode after 3 seconds
#
# Triggered by: Win+L, Start > Lock, Ctrl+Alt+Del > Lock, auto-lock timeout
#
# Related issue: When Spacedesk runs a virtual display (iPad as second screen),
# locking the laptop causes GPU to struggle reinitializing two monitors on wake,
# resulting in a black screen. This fixes it by cleanly removing the virtual
# display before sleep.

$vbsPath = "$PSScriptRoot\run_hidden.vbs"
$userName = $env:USERNAME

# Remove old tasks if they exist
Unregister-ScheduledTask -TaskName "SpacedeskOnLock" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "SpacedeskOnUnlock" -Confirm:$false -ErrorAction SilentlyContinue

$lockXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <SessionStateChangeTrigger>
      <Enabled>true</Enabled>
      <StateChange>SessionLock</StateChange>
    </SessionStateChangeTrigger>
  </Triggers>
  <Principals>
    <Principal>
      <UserId>$userName</UserId>
      <LogonType>InteractiveToken</LogonType>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <ExecutionTimeLimit>PT30S</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>wscript.exe</Command>
      <Arguments>"$vbsPath" lock</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$unlockXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <SessionStateChangeTrigger>
      <Enabled>true</Enabled>
      <StateChange>SessionUnlock</StateChange>
    </SessionStateChangeTrigger>
  </Triggers>
  <Principals>
    <Principal>
      <UserId>$userName</UserId>
      <LogonType>InteractiveToken</LogonType>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <ExecutionTimeLimit>PT30S</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>wscript.exe</Command>
      <Arguments>"$vbsPath" unlock</Arguments>
    </Exec>
  </Actions>
</Task>
"@

Register-ScheduledTask -TaskName "SpacedeskOnLock" -Xml $lockXml -Force
Register-ScheduledTask -TaskName "SpacedeskOnUnlock" -Xml $unlockXml -Force

Write-Host "Tasks created:"
Get-ScheduledTask -TaskName "SpacedeskOn*" | Format-Table TaskName, State -AutoSize
