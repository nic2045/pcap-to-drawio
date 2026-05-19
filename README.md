# pcap-to-drawio

> Capture network traffic with tshark, extract unique connections, and visualize them as a color-coded draw.io diagram — in three PowerShell scripts.

[![CI - PowerShell](https://github.com/nic2045/pcap-to-drawio/actions/workflows/ci-powershell.yml/badge.svg)](https://github.com/nic2045/pcap-to-drawio/actions/workflows/ci-powershell.yml)
[![Latest release](https://img.shields.io/github/v/release/nic2045/pcap-to-drawio?sort=semver)](https://github.com/nic2045/pcap-to-drawio/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/powershell-5.1%2B-blue.svg)](scripts/)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://www.conventionalcommits.org/)

## Prerequisites

- [Wireshark / tshark](https://www.wireshark.org/) installed and on PATH
- PowerShell 5.1+
- [draw.io](https://app.diagrams.net/) (desktop or web) to open the output diagram

## Workflow

```
[Capture host]                        [Analysis machine]
start_capture.ps1                     generate_diagram.ps1
       |                                      |
extract_connections.ps1  --copy CSV-->  network_diagram.xml
       |
unique_connections.csv
```

### Step 1 — Capture traffic (on the monitored machine)

```powershell
# List interfaces and select interactively
.\scripts\start_capture.ps1

# Or specify the interface directly
.\scripts\start_capture.ps1 -Interface 9
```

Captures SYN-only TCP and all UDP traffic into rolling 500 MB files under `pcap/`.

### Step 2 — Extract unique connections (on the monitored machine)

```powershell
.\scripts\extract_connections.ps1
```

Reads all `pcap/*.pcap` files and writes `output/unique_connections.csv`.

### Step 3 — Generate the draw.io diagram (on the analysis machine)

Copy `unique_connections.csv` and optionally your `config/ip_mapping.csv` to the analysis machine, then:

```powershell
.\scripts\generate_diagram.ps1
```

Writes `output/network_diagram.xml`. Open in draw.io via **Extras > Edit Diagram > paste > OK**.

#### Optional parameters

```powershell
.\scripts\generate_diagram.ps1 `
    -CsvPath    "C:\path\to\unique_connections.csv" `
    -MappingCsv "C:\path\to\ip_mapping.csv" `
    -OutPath    "C:\path\to\diagram.xml"
```

## IP Mapping (`config/ip_mapping.csv`)

Maps IPs or CIDR ranges to human-readable names and security zones. Edit before running `generate_diagram.ps1`.

`ip_mapping.csv` is gitignored (contains sensitive network data). Copy the example to get started:

```powershell
Copy-Item config\ip_mapping.csv.example config\ip_mapping.csv
```

| Column | Description |
|--------|-------------|
| `ip`   | Exact IP or CIDR range (e.g. `192.168.1.0/24`) |
| `name` | Display label in the diagram |
| `zone` | `host` · `intern` · `dmz` · `extern` · `default` |

Zone colours in the diagram:

| Zone     | Colour |
|----------|--------|
| `host`   | Gold — the monitored machine (placed in center) |
| `intern` | Green |
| `dmz`    | Orange |
| `extern` | Red |
| `default`| Grey |

## Directory structure

```
pcap-to-drawio/
├── config/
│   └── ip_mapping.csv           # IP-to-name/zone mapping (edit this)
├── scripts/
│   ├── start_capture.ps1        # Start tshark capture
│   ├── extract_connections.ps1  # pcap -> CSV
│   └── generate_diagram.ps1     # CSV -> draw.io XML
├── pcap/                        # Capture files (git-ignored)
└── output/                      # Generated files (git-ignored)
```
