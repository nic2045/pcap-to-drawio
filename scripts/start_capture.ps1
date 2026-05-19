#Requires -Version 5.1
[CmdletBinding()]
param(
    # Pass -Interface <n> to skip the interactive prompt.
    # Run without arguments on first use to see available interface numbers.
    [int]$Interface = 0
)

$ErrorActionPreference = 'Stop'

$tshark  = "tshark.exe"
$pcapDir = Join-Path $PSScriptRoot "..\pcap"

if (-not (Get-Command $tshark -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: '$tshark' not found. Install Wireshark and ensure tshark is on PATH."
    exit 1
}

if (-not (Test-Path $pcapDir)) {
    Write-Host "ERROR: Output directory not found: $pcapDir"
    exit 1
}

if ($Interface -eq 0) {
    Write-Host "Available interfaces:"
    & $tshark -D
    Write-Host ""
    $raw = Read-Host "Enter interface number"
    if (-not [int]::TryParse($raw, [ref]$Interface) -or $Interface -le 0) {
        Write-Host "ERROR: Invalid interface number '$raw'."
        exit 1
    }
}

$outFile = Join-Path $pcapDir "capture.pcap"

Write-Host "Capturing on interface $Interface -> $outFile"
Write-Host "Press Ctrl+C to stop."

# BPF filter rationale:
#   TCP SYN-only  — captures connection initiation without the full handshake/data,
#                   keeping file size small while preserving all unique endpoints.
#   UDP (all)     — UDP is connectionless, so every packet is a potential new flow.
#
# Ring buffer: 30 files x 500 MB = up to 15 GB retained before oldest is overwritten.
& $tshark `
    -i $Interface `
    -b filesize:500000 `
    -b files:30 `
    -f "(tcp[tcpflags] & tcp-syn != 0 and tcp[tcpflags] & tcp-ack == 0) or udp" `
    -w $outFile

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: tshark exited with code $LASTEXITCODE."
    exit $LASTEXITCODE
}
