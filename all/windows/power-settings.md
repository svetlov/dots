# Windows Power & Standby Settings

ASUS ROG with AMD Ryzen AI 9 HX 370 + RTX 5080 Laptop GPU, running GHelper.

## Hardware Constraints

- **Only Modern Standby (S0 Low Power Idle)** is available. S1/S2/S3 traditional sleep is not supported by hardware.
- **Hibernate** is disabled because it breaks NVIDIA GPU driver re-enable via GHelper.
- Closing the lid always triggers Modern Standby regardless of Windows power settings. The lid close action setting is ignored on S0-only systems.
- GHelper's `clamshell_default_lid_action` controls what happens on lid close when clamshell mode is inactive (default: 1 = Sleep = Modern Standby). Config: `%APPDATA%\GHelper\config.json`.

## Changes Made (2026-03-01)

### 1. Disabled WSAIFabricSvc (Windows AI Fabric Service)

**Why:** Recall was already disabled, but the service kept running and accumulated ~3400 CPU seconds during standby.

```powershell
Stop-Service WSAIFabricSvc -Force
Set-Service WSAIFabricSvc -StartupType Disabled
```

To re-enable:
```powershell
Set-Service WSAIFabricSvc -StartupType Manual
Start-Service WSAIFabricSvc
```

### 2. Disabled IndexerAutomaticMaintenance scheduled task

**Why:** SearchIndexer was burning ~1000 CPU seconds during Modern Standby doing background indexing.

```powershell
Disable-ScheduledTask -TaskName "IndexerAutomaticMaintenance" -TaskPath "\Microsoft\Windows\Shell\"
```

To re-enable:
```powershell
Enable-ScheduledTask -TaskName "IndexerAutomaticMaintenance" -TaskPath "\Microsoft\Windows\Shell\"
```

### 3. Disabled Windows automatic maintenance during standby

**Why:** Windows runs maintenance tasks during Modern Standby, causing high CPU and fan noise with lid closed.

```powershell
# Registry key (requires admin):
# HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance
# MaintenanceDisabled = 1 (DWORD)
$path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance"
if (!(Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
Set-ItemProperty -Path $path -Name "MaintenanceDisabled" -Value 1 -Type DWord
```

To re-enable:
```powershell
Set-ItemProperty -Path $path -Name "MaintenanceDisabled" -Value 0 -Type DWord
```

### 4. Enabled network connectivity during Modern Standby on AC power

**Why:** Network was disabled during standby for both AC and battery. Changed to keep network alive on AC so the laptop stays connected when lid is closed on power cord. Battery stays disconnected to save power.

**Problem:** The registry key `HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\381b4222-f694-41f0-9685-ff5bb260df2e\f15576e8-98b7-4186-b944-eafa664402d9` is owned by SYSTEM with Administrators having only ReadKey. Even elevated PowerShell cannot write to it directly. Must run as SYSTEM.

```powershell
# Run from admin PowerShell — creates a one-shot SYSTEM scheduled task:
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument @"
-NoProfile -Command "Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\381b4222-f694-41f0-9685-ff5bb260df2e\f15576e8-98b7-4186-b944-eafa664402d9' -Name ACSettingIndex -Value 1 -Type DWord; powercfg /setactive SCHEME_CURRENT"
"@
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "SetNetworkStandby" -Action $action -Principal $principal -Force
Start-ScheduledTask -TaskName "SetNetworkStandby"
Start-Sleep 3
Unregister-ScheduledTask -TaskName "SetNetworkStandby" -Confirm:$false
```

**Values:** ACSettingIndex: 0=Disabled, 1=Enabled, 2=Managed by Windows. DCSettingIndex left at 0.

**May be reset by:** Windows feature updates, power plan resets. Verify with `powercfg /a` — should show "Standby (S0 Low Power Idle) Network Connected" as available.

## Verification

```powershell
# Check standby network state:
powercfg /a

# Check WSAIFabricSvc:
Get-Service WSAIFabricSvc | Select-Object Status, StartType

# Check indexer task:
Get-ScheduledTask -TaskName "IndexerAutomaticMaintenance" | Select-Object State

# Check maintenance:
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" -Name MaintenanceDisabled -ErrorAction SilentlyContinue
```

## Background: The Fan Problem

With lid closed on AC, fans would spin up aggressively and CPU would drop immediately when the lid was opened. This was NOT malware — it was Windows running background maintenance during Modern Standby (WSAIFabricSvc, SearchIndexer, automatic maintenance, DCOM retry loops). Opening the lid exits Modern Standby, which deprioritizes those tasks.
