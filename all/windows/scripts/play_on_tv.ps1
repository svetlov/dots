param([string]$FilePath)

$tvIP = "192.168.1.106"
$pcIP = "192.168.1.110"
$port = 8080
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Discover TV DLNA port via SSDP (port changes on TV reboot)
$udp = New-Object System.Net.Sockets.UdpClient
$udp.Client.ReceiveTimeout = 3000
$msg = "M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: `"ssdp:discover`"`r`nMX: 2`r`nST: urn:schemas-upnp-org:service:AVTransport:1`r`n`r`n"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
$ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse('239.255.255.250'), 1900)
$udp.Send($bytes, $bytes.Length, $ep) | Out-Null
$tvPort = $null
try {
    while ($true) {
        $rep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $data = $udp.Receive([ref]$rep)
        if ($rep.Address.ToString() -eq $tvIP) {
            $text = [System.Text.Encoding]::UTF8.GetString($data)
            if ($text -match 'LOCATION:\s*http://[^:]+:(\d+)/') { $tvPort = $Matches[1]; break }
        }
    }
} catch {}
$udp.Close()
if (-not $tvPort) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("TV not found on network. Is it on? Is NordVPN off?", "Play on TV", 0, 16)
    exit 1
}
$controlURL = "http://${tvIP}:${tvPort}/AVTransport/78783ef6-91e4-382b-7403-bb0acecc752f/control.xml"

# Kill any previous server on this port
$conns = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
foreach ($c in $conns) {
    if ($c.OwningProcess -gt 0) {
        Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
    }
}
Stop-Process -Name vlc -Force -ErrorAction SilentlyContinue
Start-Sleep 1

# Start node HTTP file server (serves raw file with range support)
$serverScript = Join-Path $scriptDir "serve_video.js"
Start-Process node -ArgumentList "`"$serverScript`" `"$FilePath`"" -WindowStyle Hidden
Start-Sleep 2

$ext = [System.IO.Path]::GetExtension($FilePath).TrimStart('.')
$mimeMap = @{ mkv='video/x-matroska'; mp4='video/mp4'; avi='video/x-msvideo'; mov='video/quicktime'; wmv='video/x-ms-wmv'; webm='video/webm'; m4v='video/mp4'; ts='video/mp2t' }
$mime = if ($mimeMap[$ext]) { $mimeMap[$ext] } else { 'video/mp4' }

$mediaURL = "http://${pcIP}:${port}/video"
$fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)

# Stop any current TV playback
$stopBody = @"
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
    </u:Stop>
  </s:Body>
</s:Envelope>
"@

$headers = @{ "Content-Type" = "text/xml; charset=utf-8"; "SOAPAction" = '"urn:schemas-upnp-org:service:AVTransport:1#Stop"' }
try { Invoke-WebRequest -Uri $controlURL -Method POST -Body $stopBody -Headers $headers -UseBasicParsing | Out-Null } catch {}
Start-Sleep 1

$setURIBody = @"
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <CurrentURI>$mediaURL</CurrentURI>
      <CurrentURIMetaData>&lt;DIDL-Lite xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot; xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot;&gt;&lt;item id=&quot;0&quot; parentID=&quot;-1&quot; restricted=&quot;1&quot;&gt;&lt;dc:title&gt;$fileName&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.videoItem&lt;/upnp:class&gt;&lt;res protocolInfo=&quot;http-get:*:${mime}:DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000000000000000000000000000&quot;&gt;$mediaURL&lt;/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</CurrentURIMetaData>
    </u:SetAVTransportURI>
  </s:Body>
</s:Envelope>
"@

$playBody = @"
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <Speed>1</Speed>
    </u:Play>
  </s:Body>
</s:Envelope>
"@

$headers = @{ "Content-Type" = "text/xml; charset=utf-8"; "SOAPAction" = '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"' }
try {
    Invoke-WebRequest -Uri $controlURL -Method POST -Body $setURIBody -Headers $headers -UseBasicParsing | Out-Null
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("Failed to send to TV: $_", "Play on TV", 0, 16)
    exit 1
}

Start-Sleep 2

$headers["SOAPAction"] = '"urn:schemas-upnp-org:service:AVTransport:1#Play"'
try {
    Invoke-WebRequest -Uri $controlURL -Method POST -Body $playBody -Headers $headers -UseBasicParsing | Out-Null
} catch {}
