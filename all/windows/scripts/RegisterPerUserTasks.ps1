# Register per-user scheduled tasks for power management.
# Run from admin PowerShell while logged in as the target user.
# See power-settings.md for details.

$ErrorActionPreference = "Stop"
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$shortUser = $user.Split('\')[-1]

# GHelperResumeRestart — restart GHelper after:
#   1. AC plug-in during Modern Standby (Kernel-Power Event 105)
#   2. User session switch (TerminalServices Event 25 — session reconnect)
$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=105]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-TerminalServices-LocalSessionManager/Operational"&gt;&lt;Select Path="Microsoft-Windows-TerminalServices-LocalSessionManager/Operational"&gt;*[System[EventID=25]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$sid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\PowerScripts\RestartGHelperOnAC.ps1"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$taskName = "GHelperResumeRestart-$shortUser"
Register-ScheduledTask -TaskName $taskName -Xml $taskXml -Force | Out-Null
Write-Host "Registered $taskName for $user"

# Add more per-user tasks here as needed.

Write-Host "Done."
