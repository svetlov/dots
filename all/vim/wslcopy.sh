#!/usr/bin/env bash
# WSL clipboard bridge: copy (default) or paste (--paste)

POWERSHELL='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'

if [ "$1" = "--paste" ]; then
    "$POWERSHELL" -NoLogo -NoProfile -c '[Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))'
else
    sed 's/\r$//' | "$POWERSHELL" -NoProfile -Command '[Console]::In.ReadToEnd() | Set-Clipboard'
fi
