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

if ($nv.Problem -eq "CM_PROB_PHANTOM") {
    Log "NVIDIA GPU is phantom (G-Helper Eco mode), skipping"
    exit
}

# GPU is in error state — attempt recovery
Log "NVIDIA GPU in error state: Status=$($nv.Status) Problem=$($nv.Problem)"

$id = $nv.InstanceId

# Step 1: disable, then single enable (this is what works most reliably)
Log "Recovery: disable then fresh enable (pnputil)"
pnputil /disable-device $id 2>&1 | Out-Null
Start-Sleep 5
pnputil /enable-device $id 2>&1 | Out-Null
Start-Sleep 5
$nv = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "NVIDIA" }
if ($nv.Status -eq "OK") {
    Log "dGPU recovered after disable+enable"
    exit
}
Log "Still in error after disable+enable: Status=$($nv.Status) Problem=$($nv.Problem)"

# Step 2: if stuck in CM_PROB_DISABLED, just enable again
if ($nv.Problem -eq "CM_PROB_DISABLED") {
    Log "GPU stuck disabled, trying enable-only"
    pnputil /enable-device $id 2>&1 | Out-Null
    Start-Sleep 5
    $nv = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "NVIDIA" }
    if ($nv.Status -eq "OK") {
        Log "dGPU recovered after enable-only"
        exit
    }
    Log "Still in error after enable-only: Status=$($nv.Status) Problem=$($nv.Problem)"
}

# Step 3: last resort — pnputil restart-device
Log "Trying pnputil restart-device"
pnputil /restart-device $id 2>&1 | Out-Null
Start-Sleep 5
$nv = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match "NVIDIA" }
if ($nv.Status -eq "OK") {
    Log "dGPU recovered after restart-device"
    exit
}

Log 'Recovery FAILED - disabling GPU to prevent phantom power drain and thermal runaway'
pnputil /disable-device $id 2>&1 | Out-Null
Log 'dGPU disabled (reboot required to fully restore)'
