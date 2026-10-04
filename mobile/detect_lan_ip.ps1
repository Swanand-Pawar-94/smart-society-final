# ============================================================
# Smart Society - LAN IP Detection Helper
# ============================================================
# Detects the active physical Wi-Fi or Ethernet IPv4 address
# for connecting the physical Android phone to the PC backend.
# ============================================================

param(
    [string]$OutputFile = ""
)

$ErrorActionPreference = 'SilentlyContinue'

# 1. Query all active IPv4 addresses
$allIps = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.IPAddress -notmatch '^(127\.|169\.254\.)'
}

# 2. Filter out virtual, loopback, and VPN adapters
$candidates = $allIps | Where-Object {
    $_.InterfaceAlias -notmatch '(Loopback|vEthernet|VirtualBox|VMware|WSL|Docker|Bluetooth|Tailscale|ZeroTier|Hyper-V)' -and
    $_.IPAddress -match '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)'
} | Sort-Object -Property @{
    Expression = {
        if ($_.InterfaceAlias -like '*Wi-Fi*' -or $_.InterfaceAlias -like '*WLAN*' -or $_.InterfaceAlias -like '*Wireless*') { 0 }
        elseif ($_.InterfaceAlias -like '*Ethernet*' -or $_.InterfaceAlias -like '*Eth*') { 1 }
        else { 2 }
    }
}

# Fallback: if strict filter found nothing, look at any non-loopback private IP
if (-not $candidates) {
    $candidates = $allIps | Where-Object {
        $_.IPAddress -match '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)'
    }
}

$chosenIp = $null

if (-not $candidates) {
    Write-Host "[WARNING] Could not automatically detect a private LAN IP address." -ForegroundColor Yellow
    Write-Host "Please enter your PC's IP address manually (from ipconfig):" -ForegroundColor Cyan
    $chosenIp = Read-Host "PC IP"
} elseif ($candidates.Count -eq 1 -or ($candidates | Measure-Object).Count -eq 1) {
    $single = $candidates | Select-Object -First 1
    $chosenIp = $single.IPAddress
    Write-Host "[OK] Detected active adapter: $($single.InterfaceAlias) -> $chosenIp" -ForegroundColor Green
} else {
    # Multiple candidates: check if top candidate is clearly active Wi-Fi
    $wifiCandidate = $candidates | Where-Object { $_.InterfaceAlias -like '*Wi-Fi*' -or $_.InterfaceAlias -like '*WLAN*' } | Select-Object -First 1
    if ($wifiCandidate) {
        $chosenIp = $wifiCandidate.IPAddress
        Write-Host "[OK] Detected Wi-Fi adapter: $($wifiCandidate.InterfaceAlias) -> $chosenIp" -ForegroundColor Green
    } else {
        Write-Host "Multiple network adapters detected:" -ForegroundColor Cyan
        $i = 1
        foreach ($c in $candidates) {
            Write-Host "  [$i] $($c.IPAddress) ($($c.InterfaceAlias))"
            $i++
        }
        $selection = Read-Host "Select adapter [1-$($candidates.Count)] (Default: 1)"
        if ([string]::IsNullOrWhiteSpace($selection) -or -not [int]::TryParse($selection, [ref]$null)) {
            $chosenIp = ($candidates | Select-Object -First 1).IPAddress
        } else {
            $idx = [int]$selection - 1
            if ($idx -ge 0 -and $idx -lt $candidates.Count) {
                $chosenIp = $candidates[$idx].IPAddress
            } else {
                $chosenIp = ($candidates | Select-Object -First 1).IPAddress
            }
        }
    }
}

$chosenIp = $chosenIp.Trim()

if ($OutputFile -and $chosenIp) {
    [System.IO.File]::WriteAllText($OutputFile, $chosenIp)
}

Write-Output $chosenIp
