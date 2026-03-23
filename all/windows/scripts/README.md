# Power Management Scripts

ASUS ROG Zephyrus G14 (GA403WW) — Windows 11 Home with GHelper.
Full documentation: see `power-settings.md` in the dots repo.

## Scripts

- **RestartGHelperOnAC.ps1** — Restarts GHelper after AC plug-in during Modern Standby, so `gpu_mode_force_set` re-enables the dGPU. Checks Event 506/507 to only fire after standby, not normal plug/unplug. Session-scoped.
- **RegisterPerUserTasks.ps1** — Registers per-user scheduled tasks. **Each user must run this once** from admin PowerShell.

## Setup

Each user account must do the following from admin PowerShell:

### 1. Register scheduled tasks

```powershell
powershell -ExecutionPolicy Bypass -File "C:\ProgramData\PowerScripts\RegisterPerUserTasks.ps1"
```

### 2. Force SearchHost and WezTerm to iGPU

Without this, SearchHost hangs during GPU switches (dGPU on/off), breaking Windows Search.

```powershell
$regPath = "HKCU:\SOFTWARE\Microsoft\DirectX\UserGpuPreferences"
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\SearchHost.exe" -Value "GpuPreference=1;" -Type String
Set-ItemProperty -Path $regPath -Name "C:\Program Files\WezTerm\wezterm-gui.exe" -Value "GpuPreference=1;" -Type String
```

If SearchHost is stuck after a GPU switch: `Stop-Process -Name SearchHost -Force` (Windows auto-restarts it).

## Uninstall

```powershell
# Per-user (run as each user, where $env:USERNAME is the current user):
Unregister-ScheduledTask -TaskName "GHelperResumeRestart-$env:USERNAME" -Confirm:$false

# Remove scripts directory (after unregistering all users' tasks):
Remove-Item "C:\ProgramData\PowerScripts" -Recurse -Force
```
