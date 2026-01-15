#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 1) Exit if there are uncommitted changes.
$gitStatus = git status --porcelain
if ($gitStatus) {
  Write-Warning "Repository has uncommitted changes. Aborting update."
  exit 1
}

# 2) Start ssh-agent if not running.
$agent = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
if (-not $agent) {
  Write-Warning "ssh-agent service is not available on this system."
  exit 1
}
if ($agent.Status -ne "Running") {
  Start-Service -Name "ssh-agent"
}

# 3) Add key if not already loaded.
$keyPath = Join-Path $env:USERPROFILE ".ssh/github.ed25519"
if (-not (Test-Path $keyPath)) {
  Write-Warning "SSH key not found at $keyPath"
  exit 1
}

$loadedKeys = ssh-add -L 2>$null
$publicKey = ssh-keygen -y -f $keyPath 2>$null
if (-not $publicKey) {
  Write-Warning "Unable to read public key from $keyPath"
  exit 1
}
if ($loadedKeys -notmatch [regex]::Escape($publicKey)) {
  ssh-add $keyPath | Out-Null
}

# 4) Pull latest changes.
git pull
