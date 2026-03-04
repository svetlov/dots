# Spacedesk iPad Setup (ASUS ROG Zephyrus G14 GA403WW)

## Setup
- **Spacedesk** for using iPad as second display over USB
- **iTunes 12.13.9** (Win32 standalone) provides stable USB driver (`usbaapl64.sys`)
  - Apple Devices (UWP/Store) was removed — its `AppleUsbFilter.dll` UMDF driver kept crashing
  - iTunes auto-updates via Apple Software Update

## Known Issues

### USB-C causes disconnects
iPad on USB-C triggers PD (Power Delivery) renegotiation which disrupts the USB data connection.
ASUS ROG BIOS has no USB-C PD control setting.
**Fix:** Use USB-A port for iPad (bandwidth is more than enough for Spacedesk).

### Black screen on wake from lock
Spacedesk virtual display confuses GPU on wake.
**Fix:** Scheduled tasks switch display to "PC screen only" on lock, back to "Extend" on unlock.

## Reinstall Steps
1. Install Spacedesk from https://www.spacedesk.net
2. Install iTunes (Win32 standalone): download `iTunes64Setup.exe` from Apple support, it auto-updates
3. Enable "USB Cable iOS" in Spacedesk Driver Console
4. Run `setup_lock_tasks.ps1` as admin to create lock/unlock scheduled tasks
5. Connect iPad via USB-A, open Spacedesk on iPad, connect

## Files
- `spacedesk_lock_handler.ps1` — switches display mode on lock/unlock
- `run_hidden.vbs` — VBS wrapper to launch PowerShell without flashing a terminal window
- `setup_lock_tasks.ps1` — creates the scheduled tasks (run as admin to recreate)
