#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$PcapDir = (Join-Path $PSScriptRoot "..\pcap"),
    [string]$OutCSV  = (Join-Path $PSScriptRoot "..\output\unique_connections.csv")
)

$ErrorActionPreference = 'Stop'

$tshark = "tshark.exe"

if (-not (Get-Command $tshark -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: '$tshark' not found. Install Wireshark and ensure tshark is on PATH."
    exit 1
}

if (-not (Test-Path $PcapDir)) {
    Write-Host "ERROR: pcap directory not found: $PcapDir"
    exit 1
}

$outDir = Split-Path $OutCSV -Parent
if (-not (Test-Path $outDir)) {
    Write-Host "ERROR: Output directory not found: $outDir"
    exit 1
}

$pcapFiles = Get-ChildItem "$PcapDir\*.pcap" | Select-Object -ExpandProperty FullName

if ($pcapFiles.Count -eq 0) {
    Write-Host "ERROR: No pcap files found in $PcapDir"
    exit 1
}

Write-Host "Processing $($pcapFiles.Count) file(s)..."

# Hashtable deduplication: key = "PROTO|src|dst|port" avoids sorting/grouping overhead.
$seen = @{}
# Collect all rows in memory, then write once — avoids repeated file-open on -Append.
$rows = [System.Collections.Generic.List[string]]::new()

foreach ($pcap in $pcapFiles) {
    Write-Host "  -> $pcap"

    try {
        # TCP: SYN without ACK = first packet of a new connection (3-way handshake step 1).
        # Filtering here instead of post-processing cuts memory usage on large captures.
        $tcpLines = & $tshark -r $pcap -T fields `
            -e ip.src -e ip.dst -e tcp.dstport `
            -E separator="|" `
            -Y "tcp.flags.syn==1 and tcp.flags.ack==0" 2>$null  # suppress tshark stderr

        foreach ($line in $tcpLines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $key = "TCP|$line"
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $parts = $line -split "\|"
                if ($parts.Count -ge 3) {
                    $rows.Add("$($parts[0]),$($parts[1]),$($parts[2]),TCP")
                }
            }
        }

        # UDP: no handshake concept, so every unique src/dst/dstport triple is a flow.
        $udpLines = & $tshark -r $pcap -T fields `
            -e ip.src -e ip.dst -e udp.dstport `
            -E separator="|" `
            -Y "udp" 2>$null

        foreach ($line in $udpLines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $key = "UDP|$line"
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $parts = $line -split "\|"
                if ($parts.Count -ge 3) {
                    $rows.Add("$($parts[0]),$($parts[1]),$($parts[2]),UDP")
                }
            }
        }
    } catch {
        Write-Warning "Failed to process '$pcap': $_"
    }
}

if ($rows.Count -eq 0) {
    Write-Host "WARNING: No connections extracted. Check pcap content and tshark filters."
    exit 0
}

try {
    @("ip.src,ip.dst,port,proto") + $rows | Out-File -FilePath $OutCSV -Encoding UTF8
} catch {
    Write-Host "ERROR: Could not write output file '$OutCSV': $_"
    exit 1
}

Write-Host ""
Write-Host "Done: $($rows.Count) unique connections -> $OutCSV"
Write-Host "Copy the CSV to the analysis machine and run generate_diagram.ps1."
