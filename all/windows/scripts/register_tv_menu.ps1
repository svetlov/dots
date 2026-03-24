$scriptPath = 'C:\Users\seva\workspace\dots\all\windows\scripts\play_on_tv.ps1'
$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" `"%1`""

# Remove old entry
Remove-Item -Path 'HKCU:\Software\Classes\*\shell\PlayOnTV' -Recurse -Force -ErrorAction SilentlyContinue

# Register for each video extension directly
$extensions = @('.mkv', '.mp4', '.avi', '.mov', '.wmv', '.webm', '.m4v', '.ts')

foreach ($ext in $extensions) {
    $path = "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\PlayOnTV"
    New-Item -Path "$path\command" -Force | Out-Null
    Set-ItemProperty -Path $path -Name '(default)' -Value 'Play on LG TV'
    Set-ItemProperty -Path $path -Name 'Icon' -Value 'C:\Program Files\VideoLAN\VLC\vlc.exe'
    Set-ItemProperty -Path "$path\command" -Name '(default)' -Value $command
}

Write-Output "Context menu 'Play on LG TV' registered for video files."
