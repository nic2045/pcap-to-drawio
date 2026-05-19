param(
    [int]$Interface = 0
)

$tshark  = "tshark.exe"
$pcapDir = Join-Path $PSScriptRoot "..\pcap"

if ($Interface -eq 0) {
    Write-Host "Available interfaces:"
    & $tshark -D
    Write-Host ""
    $Interface = Read-Host "Enter interface number"
}

$outFile = Join-Path $pcapDir "capture.pcap"

Write-Host "Capturing on interface $Interface -> $outFile"
Write-Host "Press Ctrl+C to stop."

& $tshark `
    -i $Interface `
    -b filesize:500000 `
    -b files:30 `
    -f "(tcp[tcpflags] & tcp-syn != 0 and tcp[tcpflags] & tcp-ack == 0) or udp" `
    -w $outFile
