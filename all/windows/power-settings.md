# Windows Power & Standby Settings

ASUS ROG with AMD Ryzen AI 9 HX 370 + RTX 5080 Laptop GPU, running GHelper.

## Hardware Constraints

- **Only Modern Standby (S0 Low Power Idle)** is available. S1/S2/S3 traditional sleep is not supported by hardware.
- **Hibernate** is enabled with 18h timeout on battery, never on AC. Previously disabled due to GHelper NVIDIA GPU re-enable issue — re-enabled 2026-03-08 to prevent dead battery on long standby. Revert if GHelper still breaks after hibernate resume.
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

## Changes Made (2026-03-08)

### 5. Enabled USB Selective Suspend (AC and battery)

**Why:** Sleep study showed all 4 USB xHCI controllers staying fully powered during Modern Standby (~125 min active time each), causing ~3.2%/h battery drain instead of the expected ~0.5-1%/h. The Logitech LIGHTSPEED Receiver specifically was blocking deeper CPU power states.

```powershell
powercfg /SETDCVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1
powercfg /SETACVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1
powercfg /SETACTIVE SCHEME_CURRENT
```

To re-disable:
```powershell
powercfg /SETDCVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /SETACVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /SETACTIVE SCHEME_CURRENT
```

**May be reset by:** Windows feature updates, power plan resets, new USB devices.

### 6. Disabled HP Print Scan Doctor wake tasks

**Why:** `Printer Health Monitor` and `Printer Health Monitor Logon` tasks were waking the system during Modern Standby (~54 min combined active time), running even without an HP printer connected.

```powershell
Disable-ScheduledTask -TaskPath "\HP\HP Print Scan Doctor\" -TaskName "Printer Health Monitor"
Disable-ScheduledTask -TaskPath "\HP\HP Print Scan Doctor\" -TaskName "Printer Health Monitor Logon"
```

**Note:** Actual printing still works — these are just HP diagnostic/telemetry tasks, not the print pipeline. Print Spooler (set to Manual in step 11) auto-starts when you print.

To re-enable:
```powershell
Enable-ScheduledTask -TaskPath "\HP\HP Print Scan Doctor\" -TaskName "Printer Health Monitor"
Enable-ScheduledTask -TaskPath "\HP\HP Print Scan Doctor\" -TaskName "Printer Health Monitor Logon"
```

### 7. Enabled hibernate with 18h battery timeout

**Why:** Even with USB selective suspend and WU fixes, Modern Standby still drains battery. Hibernate after 18h on battery prevents a dead battery when left unplugged overnight or over a weekend. On AC, hibernate never triggers.

```powershell
powercfg /hibernate on
powercfg /change hibernate-timeout-dc 1080
powercfg /change hibernate-timeout-ac 0
```

To revert (disable hibernate):
```powershell
powercfg /hibernate off
```

**Known issue:** GHelper may fail to re-enable NVIDIA GPU after hibernate resume. Monitor and revert if this occurs.

### 8. Standby battery budget: 70% drain allowed

**Why:** Windows Modern Standby has a built-in "Adaptive Hibernate" feature that forces hibernate when battery drain during standby exceeds a budget. The default is 5% per 12-hour window — far too aggressive, causing unexpected hibernate after ~2 hours of standby. Increased to 70% so the system stays in standby until battery reaches ~30% remaining (from full charge), then hibernates.

```powershell
# SUB_PRESENCE / STANDBYBUDGETPERCENT (powercfg requires GUIDs for these)
powercfg /setdcvalueindex SCHEME_CURRENT `
    8619b916-e004-4dd8-9b66-dae86f806698 `
    9fe527be-1b70-48da-930d-7bcf17b44990 70
powercfg /setactive SCHEME_CURRENT
```

Other protections still active: 18h hibernate timeout (step 7), critical battery hibernate at 2% (system default).

To verify:
```powershell
powercfg /qh SCHEME_CURRENT `
    8619b916-e004-4dd8-9b66-dae86f806698 `
    9fe527be-1b70-48da-930d-7bcf17b44990
# DC value should be 0x00000046 (70)
```

To revert to default (5%):
```powershell
powercfg /setdcvalueindex SCHEME_CURRENT `
    8619b916-e004-4dd8-9b66-dae86f806698 `
    9fe527be-1b70-48da-930d-7bcf17b44990 5
powercfg /setactive SCHEME_CURRENT
```

### 9. PCIe Link State Power Management: Off on AC

**Why:** NVIDIA dGPU (RTX 5080) frequently enters `CM_PROB_FAILED_POST_START` after Modern Standby resume, especially when external USB-C monitor is unplugged/replugged with lid closed. PCIe ASPM can prevent the lane from powering up in time, causing the GPU driver to fail initialization. Disabled on AC only — battery keeps maximum power savings since dGPU is off in Optimized mode anyway.

```powershell
powercfg /SETACVALUEINDEX SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0
powercfg /SETACTIVE SCHEME_CURRENT
```

Also set TDR (Timeout Detection and Recovery) to 10s (default 2s) to give the GPU more time to initialize after resume:

```powershell
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
New-ItemProperty -Path $regPath -Name "TdrDelay" -Value 10 -PropertyType DWord -Force
New-ItemProperty -Path $regPath -Name "TdrDdiDelay" -Value 10 -PropertyType DWord -Force
# Reboot required
```

To revert:
```powershell
powercfg /SETACVALUEINDEX SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 1
powercfg /SETACTIVE SCHEME_CURRENT
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "TdrDelay","TdrDdiDelay"
```

### 10. Windows Update: AC-only, once per day

**Why:** MoUsoCoreWorker (Update Orchestrator) was scanning during Modern Standby on battery (~47 min active time). Default scan interval was every 6 hours; several tasks had `DisallowStartIfOnBatteries=false`.

**Problem:** Update Orchestrator tasks are owned by TrustedInstaller. Must modify via XML export/reimport running as SYSTEM (one-shot scheduled task). Norton may flag the SYSTEM script as `IDP.HELU.PSD11` — this is a false positive on a script modifying system tasks.

Changes applied:
- All Update Orchestrator tasks: `DisallowStartIfOnBatteries=true`, `StopIfGoingOnBatteries=true`
- `Schedule Scan` interval: PT6H -> P1D (24h)

Tasks modified: `Schedule Scan`, `Schedule Scan Static Task`, `USO_UxBroker`, `Report policies`, `Start Oobe Expedite Work`, `StartOobeAppsScan_LicenseAccepted`, `UIEOrchestrator`, `UUS Failover Task`.

To verify:
```powershell
foreach ($name in @("Schedule Scan", "Schedule Scan Static Task", "USO_UxBroker")) {
    $t = Get-ScheduledTask -TaskName $name -TaskPath "\Microsoft\Windows\UpdateOrchestrator\"
    "$name : DisallowBattery=$($t.Settings.DisallowStartIfOnBatteries) Interval=$(($t.Triggers | % { $_.Repetition.Interval }) -join ',')"
}
```

**May be reset by:** Windows feature updates, cumulative updates that replace task definitions.

### 11. Battery power plan optimizations

**Why:** Multiple power plan settings were identical for AC and battery — no power savings when unplugged.

```powershell
# EPP: max energy savings on battery (0=perf, 100=savings)
powercfg -attributes SUB_PROCESSOR PERFEPP -ATTRIB_HIDE
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR PERFEPP 100

# CPU boost: Efficient Enabled on battery (0=off, 1=on, 3=efficient)
powercfg -attributes SUB_PROCESSOR PERFBOOSTMODE -ATTRIB_HIDE
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 3

# Max processor state: 80% on battery
powercfg -attributes SUB_PROCESSOR PROCTHROTTLEMAX -ATTRIB_HIDE
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 80

# Core parking: aggressive on battery (10% min active cores)
powercfg -attributes SUB_PROCESSOR CPMINCORES -ATTRIB_HIDE
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 10

# Display brightness: 90% on battery (was 80%), dimmed 30% (was 50%)
powercfg /SETDCVALUEINDEX SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 17aaa29b-8b43-4b94-aafe-35f64daaf1ee 90
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_VIDEO VIDEODIMLEVEL 30

# Adaptive brightness: ON for battery
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_VIDEO ADAPTBRIGHT 1

# WiFi: Maximum Power Saving on battery (0=max perf, 3=max savings)
powercfg /SETDCVALUEINDEX SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 3

powercfg /SETACTIVE SCHEME_CURRENT
```

**May be reset by:** Windows feature updates, power plan resets.

### 12. Disabled unnecessary services and startup items

**Why:** Multiple services and startup apps running constantly with no benefit.

Services disabled:
- **GlideX** (4 services) — ASUS cross-device feature, not used
- **DiagTrack** — Microsoft telemetry, constant data collection
- **HP Print Scan Doctor Service** — no HP printer connected
- **AUEPLauncher** — AMD telemetry uploader
- **MapsBroker** — Downloaded Maps Manager

Services set to Manual (will auto-start when needed):
- **Print Spooler** — starts automatically when you print
- **ASUSSystemAnalysis**, **ASUSSystemDiagnosis** — ASUS telemetry

Startup items removed:
- **AMDNoiseSuppression** — AI noise suppression, only needed during calls (was registered 3x)
- **Virtual Pet** — ASUS cosmetic desktop widget

```powershell
# To re-enable a service:
Set-Service <ServiceName> -StartupType Automatic
Start-Service <ServiceName>

# To re-add AMDNoiseSuppression to startup:
# Reinstall AMD Noise Suppression from AMD Adrenalin software
```

### 13. GHelper: Optimized GPU mode + force set on startup

**Why:** The RTX 5080 dGPU was always on in Standard mode, drawing ~5W at idle even during desktop use. Optimized mode auto-switches: Eco (dGPU off) on battery, Standard (dGPU on) on AC.

`gpu_mode_force_set` ensures GHelper re-sends the ACPI disable/enable command on every startup — without it, Windows may re-initialize the dGPU during boot, ignoring the Optimized setting.

Config: `%APPDATA%\GHelper\config.json`
```json
{
  "gpu_mode_force_set": 1
}
```

GPU mode set to **Optimized** via GHelper UI.

To verify dGPU is off on battery:
```powershell
# Should fail with "couldn't communicate with NVIDIA driver" when dGPU is off:
nvidia-smi
```

### 14. Forced SearchHost and WezTerm to iGPU

**Why:** `SearchHost.exe` was the sole process keeping the RTX 5080 at 23W on AC despite 0% GPU utilization. WezTerm (GPU-accelerated terminal) would hang when the dGPU toggled on/off during power source changes.

```powershell
$regPath = "HKCU:\SOFTWARE\Microsoft\DirectX\UserGpuPreferences"
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\SearchHost.exe" -Value "GpuPreference=1;" -Type String
Set-ItemProperty -Path $regPath -Name "C:\Program Files\WezTerm\wezterm-gui.exe" -Value "GpuPreference=1;" -Type String
```

`GpuPreference=1` = Power Saving (integrated GPU). Same as Settings → Display → Graphics → app → Power Saving.

### 15. Auto-restart GHelper after standby AC plug-in

**Why:** GHelper misses the AC plug-in event during Modern Standby, so the dGPU stays off after sleep+replug. A per-user scheduled task triggers on Kernel-Power Event 105 (power source change), checks the event log to determine if the system was in Modern Standby when plugged in, and restarts GHelper if so.

**How it works:** Two triggers, one script:
1. **Kernel-Power Event 105** (power source change) — script checks if the most recent Event 506/507 before Event 105 was a 506 (entering Modern Standby). If yes and on AC → restart GHelper.
2. **TerminalServices Event 25** (session reconnect) — fires on user switch (not normal unlock). GHelper in the reconnecting session may have missed power events while disconnected → always restart.

GHelper restart is session-scoped (safe with multiple users). Both users share the same GHelper config via symlink — see step 16.

Scripts at `C:\ProgramData\PowerScripts\`:
- `RestartGHelperOnAC.ps1` — handles both triggers
- `RegisterPerUserTasks.ps1` — registers the task

**Must be registered per-user** — see [Per-User Setup](#per-user-setup).

### 16. Disabled WiFi Wake on Magic Packet

**Why:** Keeps WiFi radio partially active during sleep, draining battery.

```powershell
Set-NetAdapterPowerManagement -Name "WiFi" -WakeOnMagicPacket Disabled
```

To re-enable:
```powershell
Set-NetAdapterPowerManagement -Name "WiFi" -WakeOnMagicPacket Enabled
```

### 17. Shared GHelper config across users

**Why:** Both user accounts run GHelper, which controls system-level hardware (GPU mode, fan curves, performance profiles). Separate configs would conflict. A single config file in the repo is the source of truth, symlinked from both users' `%APPDATA%\GHelper\config.json`.

Config at `C:\Users\seva\workspace\dots\all\windows\ghelper-config.json`. Changes made via GHelper UI by either user are written to the repo file.

`vsvetlov` has ReadAndExecute traverse access on the parent directories and FullControl on the config file.

To set up (already done):
```powershell
# Back up and symlink each user's config:
$repoConfig = "C:\Users\seva\workspace\dots\all\windows\ghelper-config.json"
# seva:
New-Item -ItemType SymbolicLink -Path "$env:APPDATA\GHelper\config.json" -Target $repoConfig -Force
# vsvetlov (from their session or with their path):
New-Item -ItemType SymbolicLink -Path "C:\Users\svetl\AppData\Roaming\GHelper\config.json" -Target $repoConfig -Force
```

## Per-User Setup

Some tasks run per-user (InteractiveToken). **Each user account must register them independently** by running from admin PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\ProgramData\PowerScripts\RegisterPerUserTasks.ps1"
```

Script source: [`scripts/RegisterPerUserTasks.ps1`](scripts/RegisterPerUserTasks.ps1). Registers:
- **GHelperResumeRestart** (per-user, step 14) — restarts GHelper after standby AC plug-in, scoped to current session.

To unregister:
```powershell
Unregister-ScheduledTask -TaskName "GHelperResumeRestart" -Confirm:$false
```

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

# Check USB selective suspend (1 = enabled):
powercfg /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226

# Check HP printer tasks:
Get-ScheduledTask -TaskPath "\HP\HP Print Scan Doctor\" | Select-Object TaskName, State

# Run sleep study to check drain rates:
powercfg /sleepstudy
```

## Background: The Fan Problem

With lid closed on AC, fans would spin up aggressively and CPU would drop immediately when the lid was opened. This was NOT malware — it was Windows running background maintenance during Modern Standby (WSAIFabricSvc, SearchIndexer, automatic maintenance, DCOM retry loops). Opening the lid exits Modern Standby, which deprioritizes those tasks.
