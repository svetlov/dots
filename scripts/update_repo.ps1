param(
  [switch]$Force
)

# NOTE To run this in windows terminal use:
#  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/update_repo.ps1 [-Force]


#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 1) Exit if there are uncommitted changes (ignore untracked by default).
$gitStatus = git status --porcelain --untracked-files=no
if ($gitStatus -and -not $Force) {
  Write-Warning "Repository has uncommitted changes. Re-run with -Force to update anyway."
  exit 1
}

# 2) Start ssh-agent if not running.
$agent = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
if (-not $agent) {
  Write-Warning "ssh-agent service is not available on this system."
  exit 1
}
if ($agent.Status -ne "Running") {
  try {
    Start-Service -Name "ssh-agent" -ErrorAction Stop
  } catch {
    # Fall through to verification below and provide a clearer error if agent is still unavailable.
  }
}

# Prefer Windows OpenSSH tools to avoid Git Bash shims.
$sshAdd = Join-Path $env:WINDIR "System32\OpenSSH\ssh-add.exe"
$sshKeygen = Join-Path $env:WINDIR "System32\OpenSSH\ssh-keygen.exe"
if (-not (Test-Path $sshAdd)) { $sshAdd = "ssh-add" }
if (-not (Test-Path $sshKeygen)) { $sshKeygen = "ssh-keygen" }

# Ensure SSH_AUTH_SOCK is set for the Windows agent pipe if missing.
if (-not $env:SSH_AUTH_SOCK) {
  $env:SSH_AUTH_SOCK = "\\.\pipe\openssh-ssh-agent"
}

# Verify agent is available (service start can fail on locked-down systems).
$agentOk = $true
try {
  $agentCheck = & $sshAdd -L 2>&1
  if ($LASTEXITCODE -ne 0 -and ($agentCheck -notmatch "no identities")) {
    $agentOk = $false
  }
} catch {
  $agentOk = $false
}
if (-not $agentOk) {
  Write-Warning "ssh-agent is not running or cannot be accessed. Try starting it as admin or enable the service: `Get-Service ssh-agent | Set-Service -StartupType Automatic`."
  exit 1
}

# 3) Add key if not already loaded.
$keyPath = Join-Path $env:USERPROFILE ".ssh/github.ed25519"
if (-not (Test-Path $keyPath)) {
  Write-Warning "SSH key not found at $keyPath"
  exit 1
}

$loadedKeys = & $sshAdd -L 2>$null
$publicKey = & $sshKeygen -y -f $keyPath 2>$null
if (-not $publicKey) {
  Write-Warning "Unable to read public key from $keyPath"
  exit 1
}
if ($loadedKeys -notmatch [regex]::Escape($publicKey)) {
  & $sshAdd $keyPath | Out-Null
}

# 4) Pull latest changes.
$gitSsh = "C:/Windows/System32/OpenSSH/ssh.exe -i $($keyPath -replace '\\','/') -o IdentitiesOnly=yes"
$env:GIT_SSH_COMMAND = $gitSsh
git pull
