param(
    [string]$CsvPath    = (Join-Path $PSScriptRoot "..\output\unique_connections.csv"),
    [string]$OutPath    = (Join-Path $PSScriptRoot "..\output\network_diagram.xml"),
    [string]$MappingCsv = (Join-Path $PSScriptRoot "..\config\ip_mapping.csv")
)

if (-not (Test-Path $CsvPath)) {
    Write-Host ("ERROR: CSV not found: {0}" -f $CsvPath)
    exit 1
}

# Zone styles (criticality: extern=red > dmz=orange > intern=green; host=gold/center)
$zoneStyles = @{
    "host"    = "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFD700;strokeColor=#B8860B;strokeWidth=3;fontStyle=1;fontSize=13;"
    "intern"  = "rounded=1;whiteSpace=wrap;html=1;fillColor=#90C890;strokeColor=#2E7D32;"
    "dmz"     = "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFB347;strokeColor=#CC6600;"
    "extern"  = "rounded=1;whiteSpace=wrap;html=1;fillColor=#FF8080;strokeColor=#CC0000;"
    "default" = "rounded=1;whiteSpace=wrap;html=1;fillColor=#f5f5f5;strokeColor=#666666;"
}

# Load mapping (optional)
$mapping = @{}
if (Test-Path $MappingCsv) {
    $lineNum = 1
    Import-Csv $MappingCsv | ForEach-Object {
        $lineNum++
        $ip   = $_.ip.Trim()
        $name = $_.name.Trim()
        $zone = if ($_.zone) { $_.zone.Trim().ToLower() } else { "default" }

        if ([string]::IsNullOrWhiteSpace($ip)) {
            Write-Warning ("Line {0} skipped: IP is empty" -f $lineNum)
            return
        }

        if ($ip -match ";") {
            Write-Warning ("Line {0} skipped: semicolon instead of comma in '{1}' - check CSV delimiter" -f $lineNum, $ip)
            return
        }

        $validZones = @("host", "intern", "dmz", "extern", "default")
        if ($zone -notin $validZones) {
            Write-Warning ("Line {0}: unknown zone '{1}' for {2} - using 'default'" -f $lineNum, $zone, $ip)
            $zone = "default"
        }

        $mapping[$ip] = @{ name = $name; zone = $zone }
    }
    Write-Host ("Mapping loaded: {0} entries" -f $mapping.Count)
} else {
    Write-Host "No mapping found - using IPs only"
}

function ConvertTo-IPLong {
    param([string]$ip)
    try {
        $parts = $ip.Trim() -split "\."
        if ($parts.Count -ne 4) { return $null }
        return ([long]$parts[0] -shl 24) + ([long]$parts[1] -shl 16) + ([long]$parts[2] -shl 8) + [long]$parts[3]
    } catch { return $null }
}

function Test-IPInCIDR {
    param([string]$ip, [string]$cidr)
    try {
        $parts   = $cidr -split "/"
        $network = ConvertTo-IPLong $parts[0]
        $prefix  = [int]$parts[1]
        $mask    = if ($prefix -eq 0) { 0 } else { [long]([uint32]0xFFFFFFFF -shl (32 - $prefix)) }
        $ipLong  = ConvertTo-IPLong $ip
        if ($null -eq $ipLong -or $null -eq $network) { return $false }
        return ($ipLong -band $mask) -eq ($network -band $mask)
    } catch { return $false }
}

function Get-IPMapping {
    param([string]$ip)
    if ($mapping.ContainsKey($ip)) { return $mapping[$ip] }
    foreach ($key in $mapping.Keys) {
        if ($key -match "/" -and (Test-IPInCIDR -ip $ip -cidr $key)) {
            return $mapping[$key]
        }
    }
    return $null
}

$rows = Import-Csv -Path $CsvPath

if ($rows.Count -eq 0) {
    Write-Host "ERROR: No connections found in CSV."
    exit 1
}

# Collect unique IPs
$ips = @{}
foreach ($row in $rows) {
    if ($row.'ip.src') { $ips[$row.'ip.src'] = $true }
    if ($row.'ip.dst') { $ips[$row.'ip.dst'] = $true }
}
$ipList = $ips.Keys | Sort-Object

Write-Host ("IPs found:    {0}" -f $ipList.Count)
Write-Host ("Connections:  {0}" -f $rows.Count)

# Circle layout — host in center, all others on the ring
$cx = 600
$cy = 400
$ipCoords = @{}

$hostIPs    = @($ipList | Where-Object { $m = Get-IPMapping -ip $_; $m -and $m.zone -eq "host" })
$nonHostIPs = @($ipList | Where-Object { $m = Get-IPMapping -ip $_; -not ($m -and $m.zone -eq "host") })
$radius = [Math]::Max(200, [Math]::Min(350, $nonHostIPs.Count * 35))
$n      = $nonHostIPs.Count

for ($i = 0; $i -lt $n; $i++) {
    $angle = 2 * [Math]::PI * $i / $n
    $x = [Math]::Round($cx + $radius * [Math]::Cos($angle)) - 60
    $y = [Math]::Round($cy + $radius * [Math]::Sin($angle)) - 20
    $ipCoords[$nonHostIPs[$i]] = @{ X = $x; Y = $y; Id = ("node_{0}" -f $i) }
}

$hostIdx = $n
foreach ($hip in $hostIPs) {
    $offX = ($hostIdx - $n) * 180
    $ipCoords[$hip] = @{ X = ($cx - 80 + $offX); Y = ($cy - 35); Id = ("node_{0}" -f $hostIdx) }
    $hostIdx++
}

# Build XML
$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine('<mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" page="1" pageWidth="1169" pageHeight="827">')
[void]$sb.AppendLine('  <root>')
[void]$sb.AppendLine('    <mxCell id="0" />')
[void]$sb.AppendLine('    <mxCell id="1" parent="0" />')

foreach ($ip in $ipList) {
    $c      = $ipCoords[$ip]
    $map    = Get-IPMapping -ip $ip
    $label  = if ($map) { ("{0}&#xa;{1}" -f $ip, $map.name) } else { $ip }
    $zone   = if ($map) { $map.zone } else { "default" }
    $style  = if ($zoneStyles.ContainsKey($zone)) { $zoneStyles[$zone] } else { $zoneStyles["default"] }
    $height = if ($zone -eq "host") { "60" } elseif ($map) { "56" } else { "40" }
    $width  = if ($zone -eq "host") { "160" } else { "120" }

    [void]$sb.AppendLine(('    <mxCell id="{0}" value="{1}" style="{2}" vertex="1" parent="1">' -f $c.Id, $label, $style))
    [void]$sb.AppendLine(('      <mxGeometry x="{0}" y="{1}" width="{2}" height="{3}" as="geometry" />' -f $c.X, $c.Y, $width, $height))
    [void]$sb.AppendLine('    </mxCell>')
}

$seenEdges = @{}
$edgeIdx   = 0

foreach ($row in $rows) {
    $src   = $row.'ip.src'
    $dst   = $row.'ip.dst'
    $port  = $row.'port'
    $proto = $row.'proto'

    if (-not $src -or -not $dst) { continue }
    if (-not $ipCoords.ContainsKey($src) -or -not $ipCoords.ContainsKey($dst)) { continue }

    $edgeKey = ("{0}|{1}|{2}|{3}" -f $src, $dst, $port, $proto)
    if ($seenEdges.ContainsKey($edgeKey)) { continue }
    $seenEdges[$edgeKey] = $true

    $label = if ($port) { ("{0}/{1}" -f $proto, $port) } else { $proto }
    $srcId = $ipCoords[$src].Id
    $dstId = $ipCoords[$dst].Id

    [void]$sb.AppendLine(('    <mxCell id="edge_{0}" value="{1}" style="edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;" edge="1" source="{2}" target="{3}" parent="1">' -f $edgeIdx, $label, $srcId, $dstId))
    [void]$sb.AppendLine('      <mxGeometry as="geometry" />')
    [void]$sb.AppendLine('    </mxCell>')
    $edgeIdx++
}

[void]$sb.AppendLine('  </root>')
[void]$sb.AppendLine('</mxGraphModel>')

$sb.ToString() | Out-File -FilePath $OutPath -Encoding UTF8

Write-Host ""
Write-Host ("Done: {0}" -f $OutPath)
Write-Host "In draw.io: Extras > Edit Diagram > paste content > OK"
