#!/usr/bin/env bash

sed 's/\r$//' | powershell.exe -NoProfile -Command '[Console]::In.ReadToEnd() | Set-Clipboard'
