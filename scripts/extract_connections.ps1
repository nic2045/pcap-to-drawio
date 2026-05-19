param(
    [string]$PcapDir = (Join-Path $PSScriptRoot "..\pcap"),
    [string]$OutCSV  = (Join-Path $PSScriptRoot "..\output\unique_connections.csv")
)

$tshark    = "tshark.exe"
$pcapFiles = Get-ChildItem "$PcapDir\*.pcap" | Select-Object -ExpandProperty FullName

if ($pcapFiles.Count -eq 0) {
    Write-Host "ERROR: No pcap files found in $PcapDir"
    exit 1
}

Write-Host "Processing $($pcapFiles.Count) file(s)..."

$seen = @{}
$rows = [System.Collections.Generic.List[string]]::new()

foreach ($pcap in $pcapFiles) {
    Write-Host "  -> $pcap"

    # TCP: SYN-only = new connection initiation
    $tcpLines = & $tshark -r $pcap -T fields `
        -e ip.src -e ip.dst -e tcp.dstport `
        -E separator="|" `
        -Y "tcp.flags.syn==1 and tcp.flags.ack==0" 2>$null

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

    # UDP: all unique src/dst/dstport
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
}

@("ip.src,ip.dst,port,proto") + $rows | Out-File -FilePath $OutCSV -Encoding UTF8

Write-Host ""
Write-Host "Done: $($rows.Count) unique connections -> $OutCSV"
Write-Host "Copy the CSV to the analysis machine and run csv_to_drawio.ps1."
