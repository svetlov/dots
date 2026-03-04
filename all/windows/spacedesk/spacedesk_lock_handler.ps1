# Spacedesk Lock/Unlock Display Handler
# Called with argument "lock" or "unlock"
# Prevents black screen on wake by switching display mode before sleep
param([string]$action)

if ($action -eq "lock") {
    # Switch to PC screen only before sleep/lock
    & "C:\Windows\System32\DisplaySwitch.exe" /internal
}
elseif ($action -eq "unlock") {
    # Re-enable extend mode after unlock
    Start-Sleep -Seconds 3
    & "C:\Windows\System32\DisplaySwitch.exe" /extend
}
