# Scripts

ASUS ROG Zephyrus G14 (GA403WW) — Windows 11 Home with GHelper.

## Power Management

- **RestartGHelperOnAC.ps1** — Restarts GHelper after AC plug-in during Modern Standby and recovers NVIDIA dGPU if it's in error state (`CM_PROB_FAILED_POST_START`). Session-scoped.
- **RegisterPerUserTasks.ps1** — Registers per-user scheduled tasks. **Each user must run this once** from admin PowerShell.

Full documentation: see `power-settings.md` in the dots repo.

## Key Remapping (keyremap.ahk)

AutoHotkey v2 script replacing PowerToys Keyboard Manager. KBM injects characters via clipboard + Ctrl+V, which breaks in terminals (WezTerm, Windows Terminal). AHK uses `SendInput`/`SendText` which works everywhere.

Mappings:
- CapsLock → Esc
- LShift+Backspace → Delete, RShift+Backspace → CapsLock, Ctrl+Backspace → Delete
- LAlt+{A,C,F,X,Z} → Ctrl+{A,C,F,X,Z} (macOS-like shortcuts)
- LAlt+Q → Alt+F4, LAlt+R → Ctrl+R, LAlt+V → Ctrl+V
- LAlt+Shift+Z → Ctrl+Shift+Z (redo)
- LShift+ISO key (SC056) → tilde, LShift+Esc → backtick

**Requires:** [AutoHotkey v2](https://www.autohotkey.com/) (`winget install AutoHotkey.AutoHotkey`)

Runs on login via copy in `shell:startup`.

## DLNA TV Streaming (Play on LG TV)

Right-click context menu for streaming video files to LG B2 TV via DLNA.

- **play_on_tv.ps1** — Starts HTTP server, sends DLNA SOAP commands (Stop → SetAVTransportURI → Play) to TV
- **serve_video.js** — Node.js HTTP file server with range request support (needed for seeking). Serves raw file without re-muxing, preserving all audio/subtitle tracks
- **register_tv_menu.ps1** — Registers "Play on LG TV" in Explorer context menu for video extensions (.mkv, .mp4, .avi, etc.)
- **kill_port.ps1** — Kills any process on port 8080 (cleanup utility)

**Requires:** Node.js, NordVPN must be off (blocks SSDP/UPnP discovery)

**Setup:**
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\seva\workspace\dots\all\windows\scripts\register_tv_menu.ps1"
```

## Per-User Setup

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
