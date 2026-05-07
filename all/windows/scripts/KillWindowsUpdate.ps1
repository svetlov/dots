# Kill Windows Update and re-enabled services on every login.
# Windows Update Medic (WaaSMedicSvc) re-enables update services,
# and Windows/driver updates re-enable telemetry services.

$logFile = "$env:ProgramData\PowerScripts\kill-wu.log"
function Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" | Out-File -Append $logFile
}

Log 'Killing Windows Update services...'

# Stop and disable Windows Update
Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
Set-Service wuauserv -StartupType Disabled -ErrorAction SilentlyContinue
Log "wuauserv: $((Get-Service wuauserv).Status) / $(( Get-Service wuauserv).StartType)"

# Stop and disable Update Orchestrator
Stop-Service UsoSvc -Force -ErrorAction SilentlyContinue
Set-Service UsoSvc -StartupType Disabled -ErrorAction SilentlyContinue
Log "UsoSvc: $((Get-Service UsoSvc).Status) / $((Get-Service UsoSvc).StartType)"

# Disable Update Medic via registry (protected service, can't use Set-Service)
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' -Name 'Start' -Value 4 -Type DWord
Stop-Service WaaSMedicSvc -Force -ErrorAction SilentlyContinue
Log "WaaSMedicSvc: disabled via registry, stopped"

# Ensure registry policies are set
$auPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
Set-ItemProperty $auPath -Name 'NoAutoUpdate' -Value 1 -Type DWord
Set-ItemProperty $auPath -Name 'AUOptions' -Value 1 -Type DWord
Log 'Registry policies confirmed'

# Kill services that get re-enabled by driver/Windows updates
Stop-Service AUEPLauncher -Force -ErrorAction SilentlyContinue
Set-Service AUEPLauncher -StartupType Disabled -ErrorAction SilentlyContinue
Log "AUEPLauncher (AMD telemetry): $((Get-Service AUEPLauncher).Status) / $((Get-Service AUEPLauncher).StartType)"

Log 'Done'
