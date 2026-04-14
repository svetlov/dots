# Toggle DevicePasswordLessBuildVersion on lock/unlock
# Lock (Event 4800):  set to 0 → password default at lock screen
# Unlock (Event 4801): set to 2 → face default for in-session apps
param([string]$Action)

$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device"

if ($Action -eq "lock") {
    Set-ItemProperty -Path $regPath -Name "DevicePasswordLessBuildVersion" -Value 0 -Type DWord
} elseif ($Action -eq "unlock") {
    Set-ItemProperty -Path $regPath -Name "DevicePasswordLessBuildVersion" -Value 2 -Type DWord
}
