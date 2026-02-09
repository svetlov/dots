<#
.SYNOPSIS
    Bootstrap script for Windows-side dotfiles (run from PowerShell, not WSL).
.DESCRIPTION
    Copies config files to the correct Windows locations.
    Symlinks don't work reliably from WSL to Windows, so we copy instead.
.USAGE
    powershell -NoProfile -ExecutionPolicy Bypass -File bootstrap-windows.ps1
#>

$ErrorActionPreference = "Stop"

$DotsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WinConfigDir = Join-Path $DotsDir "all\windows"
$UserHome = $env:USERPROFILE

function Info($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
    Write-Host ""
}

function Copy-Config($src, $dst) {
    if (Test-Path $src) {
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "  Copied $src -> $dst"
    } else {
        Write-Host "  Skipping $src (not found)" -ForegroundColor Yellow
    }
}

# .wslconfig
Info "Installing .wslconfig"
Copy-Config (Join-Path $WinConfigDir "wslconfig") (Join-Path $UserHome ".wslconfig")

# Wezterm
Info "Installing wezterm config"
Copy-Config (Join-Path $WinConfigDir "wezterm.lua") (Join-Path $UserHome ".wezterm.lua")

Info "Windows bootstrap complete!"
Write-Host "Note: .wslconfig changes require 'wsl --shutdown' to take effect."
