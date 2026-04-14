# Check NVIDIA dGPU health and disable if stuck in error state.
# Prevents phantom power drain (20-30W) and thermal runaway with lid closed.
# Triggered by: standby exit (Event 507), power source change (Event 105),
#               session reconnect (Event 25), lid open/close.
# Runs as SYSTEM — no session scope needed.

$logFile = "$env:ProgramData\PowerScripts\gpu-health.log"
function Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') $msg" | Out-File -Append $logFile
}

Log "GPU health check started"

$nv = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "NVIDIA" }
if (-not $nv) {
    Log "No NVIDIA GPU found (Eco mode or removed), OK"
    exit
}

if ($nv.Status -eq "OK") {
    Log "NVIDIA GPU status OK"
    exit
}

if ($nv.Problem -eq "CM_PROB_DISABLED") {
    Log "NVIDIA GPU already disabled (intentional), skipping"
    exit
}

# GPU is in error state — attempt recovery
Log "NVIDIA GPU in error state: Status=$($nv.Status) Problem=$($nv.Problem)"

$maxAttempts = 3
for ($i = 1; $i -le $maxAttempts; $i++) {
    Log "Recovery attempt $i/$maxAttempts"
    Disable-PnpDevice -InstanceId $nv.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep 5
    Enable-PnpDevice -InstanceId $nv.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep 5
    $nv = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "NVIDIA" }
    if ($nv.Status -eq "OK") {
        Log "dGPU recovered on attempt $i"
        exit
    }
    Log "Still in error after attempt $i: Status=$($nv.Status)"
}

Log "Recovery FAILED — disabling GPU to prevent phantom power drain and thermal runaway"
Disable-PnpDevice -InstanceId $nv.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
Log "dGPU disabled (reboot required to fully restore)"
