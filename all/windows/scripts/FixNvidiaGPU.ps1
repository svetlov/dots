# Fix NVIDIA GPU Error 43 - Disable/Enable GPU
# Run as Administrator

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "This script requires administrator privileges. Restarting as admin..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "=== NVIDIA GPU Reset Tool ===" -ForegroundColor Cyan
Write-Host ""

# Find NVIDIA GPU
$nvidiaGpu = Get-PnpDevice -Class Display | Where-Object {$_.Name -like "*NVIDIA*"}

if ($null -eq $nvidiaGpu) {
    Write-Host "ERROR: Could not find NVIDIA GPU" -ForegroundColor Red
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

Write-Host "Found GPU: $($nvidiaGpu.Name)" -ForegroundColor Green
Write-Host "Status: $($nvidiaGpu.Status)" -ForegroundColor Yellow
Write-Host ""

# Disable GPU
Write-Host "Disabling GPU..." -ForegroundColor Yellow
try {
    Disable-PnpDevice -InstanceId $nvidiaGpu.InstanceId -Confirm:$false -ErrorAction Stop
    Write-Host "GPU disabled successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to disable GPU: $_" -ForegroundColor Red
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# Wait
Write-Host "Waiting 10 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Enable GPU
Write-Host "Enabling GPU..." -ForegroundColor Yellow
try {
    Enable-PnpDevice -InstanceId $nvidiaGpu.InstanceId -Confirm:$false -ErrorAction Stop
    Write-Host "GPU enabled successfully!" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to enable GPU: $_" -ForegroundColor Red
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# Wait a moment for driver to initialize
Write-Host "Waiting for driver to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

# Verify with nvidia-smi
Write-Host ""
Write-Host "=== Verifying GPU with nvidia-smi ===" -ForegroundColor Cyan
Write-Host ""

try {
    $nvidiaSmi = & nvidia-smi 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host $nvidiaSmi
        Write-Host ""
        Write-Host "=== SUCCESS! ===" -ForegroundColor Green
        Write-Host "GPU is working correctly!" -ForegroundColor Green
    } else {
        Write-Host "WARNING: nvidia-smi returned error code $LASTEXITCODE" -ForegroundColor Yellow
        Write-Host $nvidiaSmi
        Write-Host ""
        Write-Host "GPU may not be fully initialized yet. Try running nvidia-smi manually in a moment." -ForegroundColor Yellow
    }
} catch {
    Write-Host "WARNING: Could not run nvidia-smi" -ForegroundColor Yellow
    Write-Host "Error: $_" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Make sure nvidia-smi is in your PATH or try running it manually." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")