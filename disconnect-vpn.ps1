# Disconnect NordVPN on logoff
Stop-Process -Name "NordVPN" -Force -ErrorAction SilentlyContinue
& "C:\Program Files\NordVPN\nordvpn-service.exe" --disconnect 2>$null
