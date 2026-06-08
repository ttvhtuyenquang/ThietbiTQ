<# :
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content '%~f0') -join [char]10)"
exit /b
#>

# ──────────────────────────────────────────────────────────────────────────────
# VNPost Device Inventory – Thu thập thông tin máy tính
# URL: https://nguyennam90.github.io/Check_thiet_bi/
# ──────────────────────────────────────────────────────────────────────────────

$ServerUrl = "https://nguyennam90.github.io/Check_thiet_bi"

# ── 1. Tự đăng ký giao thức vnpost:// (chạy ngầm, không hỏi người dùng) ────
try {
    $installDir = Join-Path $env:LOCALAPPDATA "VNPost"
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null

    # Sao chép bat file vào thư mục ổn định
    $selfBat = $MyInvocation.MyCommand.Path
    if (-not $selfBat) { $selfBat = $PSCommandPath }
    if ($selfBat -and (Test-Path $selfBat)) {
        Copy-Item -Path $selfBat -Destination (Join-Path $installDir "lay_thong_tin.bat") -Force
    }

    $installedBat = Join-Path $installDir "lay_thong_tin.bat"
    $cmdValue = "`"cmd.exe`" /c start /min `"`" `"$installedBat`""

    $regBase = "HKCU:\SOFTWARE\Classes\vnpost"
    New-Item -Path $regBase -Force | Out-Null
    Set-ItemProperty -Path $regBase -Name "(Default)"    -Value "URL:VNPost Device Inventory"
    Set-ItemProperty -Path $regBase -Name "URL Protocol" -Value ""
    New-Item -Path "$regBase\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path "$regBase\shell\open\command" -Name "(Default)" -Value $cmdValue
} catch { <# Bỏ qua lỗi đăng ký – không ảnh hưởng thu thập dữ liệu #> }

# ── 2. Thu thập thông tin phần cứng từ Windows WMI/CIM ──────────────────────
$cpu      = Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name
$cs       = Get-CimInstance Win32_ComputerSystem | Select-Object -First 1
$bios     = Get-CimInstance Win32_BIOS | Select-Object -First 1
$os       = Get-CimInstance Win32_OperatingSystem | Select-Object -First 1
$disk     = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Measure-Object -Property Size -Sum
$adapter  = Get-CimInstance Win32_NetworkAdapterConfiguration |
              Where-Object { $_.IPEnabled -eq $true -and $_.IPAddress } |
              Select-Object -First 1

$manufacturer = $cs.Manufacturer.Trim()
$model        = $cs.Model.Trim()
$ram          = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$serial       = $bios.SerialNumber.Trim()
$os_name      = "$($os.Caption) $($os.Version)".Trim()
$disk_size    = [math]::Round($disk.Sum / 1GB, 0)
$ip           = ($adapter.IPAddress | Where-Object { $_ -match '^\d+\.' } | Select-Object -First 1)
$mac          = $adapter.MACAddress
$machineType  = if ($cs.PCSystemType -eq 2) { "Laptop" } else { "Desktop" }

$office = Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match "Microsoft 365|Microsoft Office" } |
    Select-Object -First 1 -ExpandProperty DisplayName

$antivirus = Get-CimInstance `
    -Namespace "root\SecurityCenter2" `
    -ClassName AntiVirusProduct `
    -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty displayName

# ── 3. Mã hóa URL params ────────────────────────────────────────────────────
Add-Type -AssemblyName System.Web
function Encode-Param($val) {
    if ($null -eq $val) { return "" }
    return [System.Web.HttpUtility]::UrlEncode($val.ToString())
}

$params = @(
    "hostname=$(Encode-Param $env:COMPUTERNAME)",
    "cpu=$(Encode-Param $cpu)",
    "hang=$(Encode-Param $manufacturer)",
    "model=$(Encode-Param $model)",
    "ram=$(Encode-Param ($ram.ToString() + ' GB'))",
    "disk=$(Encode-Param ($disk_size.ToString() + ' GB'))",
    "serial=$(Encode-Param $serial)",
    "os=$(Encode-Param $os_name)",
    "ip=$(Encode-Param $ip)",
    "mac=$(Encode-Param $mac)",
    "loaiMay=$(Encode-Param $machineType)",
    "office=$(Encode-Param $office)",
    "antivirus=$(Encode-Param ($antivirus -join ', '))"
)

# ── 4. Mở trình duyệt với form đã điền sẵn ──────────────────────────────────
$targetUrl = "$ServerUrl/?" + ($params -join "&")
Start-Process $targetUrl
