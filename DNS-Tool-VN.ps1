# DNS Changer Tool v3.0 - PowerShell Version
# Hỗ trợ thay đổi DNS và chuẩn bị file GoodbyeDPI để chạy thủ công.

param(
    [switch]$RunAsAdmin
)

# Thiết lập console
$Host.UI.RawUI.WindowTitle = "DNS Changer Tool v3.0"
$Host.UI.RawUI.BackgroundColor = "Black"
$Host.UI.RawUI.ForegroundColor = "Green"
Clear-Host

# Kiểm tra quyền Administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Chạy lại với quyền Administrator
function Start-AsAdmin {
    if (-not (Test-Administrator)) {
        Write-Host "=====================================================" -ForegroundColor Red; Write-Host "CANH BAO" -ForegroundColor Red
        Write-Host "=====================================================" -ForegroundColor Red; Write-Host "Tool nay can quyen Administrator!" -ForegroundColor Yellow
        Write-Host "Dang khoi dong lai voi quyen Administrator..." -ForegroundColor Yellow; Write-Host "=====================================================" -ForegroundColor Red
        try {
            Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`" -RunAsAdmin"
            exit
        }
        catch {
            Write-Host "Khong the khoi dong lai voi quyen Administrator." -ForegroundColor Red
            Read-Host "Nhan Enter de thoat"
            exit 1
        }
    }
}

# Lấy danh sách Network Adapter
function Get-ActiveNetworkAdapter {
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false }
        if ($adapters.Count -eq 0) {
            $adapters = Get-NetAdapter | Where-Object { $_.Virtual -eq $false } | Select-Object -First 1
        }
        if ($adapters -is [array]) { return $adapters[0] }
        return $adapters
    }
    catch {
        Write-Host "[LOI] Khong the lay thong tin network adapter: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Thiết lập DNS
function Set-CustomDNS {
    param(
        [string]$AdapterName,
        [string]$PrimaryIPv4,
        [string]$SecondaryIPv4,
        [string]$PrimaryIPv6,
        [string]$SecondaryIPv6,
        [string]$ProviderName
    )
    $success = $true
    Write-Host "Dang ap dung cau hinh DNS $ProviderName..." -ForegroundColor Cyan; Write-Host ""
    Write-Host "Dang cai dat IPv4 DNS servers..." -ForegroundColor Yellow
    try {
        Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ServerAddresses ($PrimaryIPv4, $SecondaryIPv4) -ErrorAction Stop
        Write-Host "[OK] Primary IPv4 DNS: $PrimaryIPv4" -ForegroundColor Green
        Write-Host "[OK] Secondary IPv4 DNS: $SecondaryIPv4" -ForegroundColor Green
    }
    catch {
        Write-Host "[LOI] Khong the cai dat IPv4 DNS: $($_.Exception.Message)" -ForegroundColor Red
        $success = $false
    }
    Write-Host ""; Write-Host "Dang cai dat IPv6 DNS servers..." -ForegroundColor Yellow
    try {
        Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ServerAddresses ($PrimaryIPv6, $SecondaryIPv6) -ErrorAction Stop
        Write-Host "[OK] Primary IPv6 DNS: $PrimaryIPv6" -ForegroundColor Green
        Write-Host "[OK] Secondary IPv6 DNS: $SecondaryIPv6" -ForegroundColor Green
    }
    catch {
        Write-Host "[CANH BAO] Khong the cai dat IPv6 DNS. $($_.Exception.Message)" -ForegroundColor Yellow
    }
    if($success){Write-Host "Cai dat DNS thanh cong!" -ForegroundColor Green}
    return $success
}

# Reset DNS về mặc định
function Reset-DNSToDefault {
    param([string]$AdapterName)
    Write-Host "Dang reset DNS ve cai dat mac dinh..." -ForegroundColor Cyan; Write-Host ""
    try {
        Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ResetServerAddresses -ErrorAction Stop
        Write-Host "[OK] IPv4 DNS da reset ve mac dinh" -ForegroundColor Green
        try {
            Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ResetServerAddresses -AddressFamily IPv6 -ErrorAction Stop
            Write-Host "[OK] IPv6 DNS da reset ve mac dinh" -ForegroundColor Green
        }
        catch {
             Write-Host "[CANH BAO] Khong the reset IPv6 DNS (co the IPv6 khong duoc ho tro)." -ForegroundColor Yellow
        }
        return $true
    }
    catch {
        Write-Host "[LOI] Khong the reset DNS: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Kiểm tra DNS hiện tại
function Show-CurrentDNS {
    param([string]$AdapterName)
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "             KIEM TRA DNS HIEN TAI" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan; Write-Host ""
    try {
        Write-Host "Cau hinh IPv4 DNS:" -ForegroundColor Yellow; Write-Host "==================" -ForegroundColor Yellow
        $ipv4DNS = Get-DnsClientServerAddress -InterfaceAlias $AdapterName -AddressFamily IPv4
        if ($ipv4DNS.ServerAddresses.Count -gt 0) {
            foreach($dns in $ipv4DNS.ServerAddresses) { Write-Host "DNS Server: $dns" -ForegroundColor White }
        } else { Write-Host "Khong co DNS nao duoc cau hinh (tu dong)" -ForegroundColor Gray }
        Write-Host ""
        Write-Host "Cau hinh IPv6 DNS:" -ForegroundColor Yellow; Write-Host "==================" -ForegroundColor Yellow
        $ipv6DNS = Get-DnsClientServerAddress -InterfaceAlias $AdapterName -AddressFamily IPv6
        if ($ipv6DNS.ServerAddresses.Count -gt 0) {
            foreach($dns in $ipv6DNS.ServerAddresses) { Write-Host "DNS Server: $dns" -ForegroundColor White }
        } else { Write-Host "Khong co DNS nao duoc cau hinh (tu dong)" -ForegroundColor Gray }
    }
    catch { Write-Host "[LOI] Khong the lay thong tin DNS: $($_.Exception.Message)" -ForegroundColor Red }
}

# Xóa DNS Cache
function Clear-DNSCache {
    try {
        Clear-DnsClientCache -ErrorAction Stop
        Write-Host "[OK] DNS cache da duoc xoa" -ForegroundColor Green
    }
    catch { Write-Host "[LOI] Khong the xoa DNS cache: $($_.Exception.Message)" -ForegroundColor Red }
}

# Chức năng mới: Tải và giải nén GoodbyeDPI ra Desktop, sau đó hướng dẫn người dùng.
function Prepare-GoodbyeDPI {
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "     CHUAN BI GOODBYEDPI (TAI & GIAI NEN)" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan; Write-Host ""
    
    $desktopPath = [System.Environment]::GetFolderPath('Desktop')
    $extractPath = Join-Path $desktopPath "GoodbyeDPI_Files"
    $url = "https://dl.revolt.vn/Fix_steam.zip"
    $zipPath = Join-Path $env:TEMP "Fix_steam.zip"

    try {
        if (Test-Path $extractPath) {
            Write-Host "Da tim thay thu muc 'GoodbyeDPI_Files' tren Desktop." -ForegroundColor Yellow
            $overwrite = Read-Host "Ban co muon xoa thu muc cu va tai lai khong? (y/n)"
            if ($overwrite -ne 'y') {
                Write-Host "Huy bo thao tac." -ForegroundColor Red
                return
            }
            Write-Host "Dang xoa thu muc cu..." -ForegroundColor Yellow
            Remove-Item -Path $extractPath -Recurse -Force
        }

        Write-Host "[1/3] Dang tai file GoodbyeDPI..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
        Write-Host "[OK] Da tai file thanh cong." -ForegroundColor Green; Write-Host ""

        Write-Host "[2/3] Dang giai nen file ra Desktop..." -ForegroundColor Yellow
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force -ErrorAction Stop
        Write-Host "[OK] Da giai nen thanh cong vao thu muc '$extractPath'" -ForegroundColor Green; Write-Host ""

        Write-Host "[3/3] Dang don dep file tam..." -ForegroundColor Yellow
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Da don dep xong." -ForegroundColor Green; Write-Host ""

        Write-Host "=====================================================" -ForegroundColor Green
        Write-Host "              HOAN TAT - HUONG DAN SU DUNG" -ForegroundColor Green
        Write-Host "=====================================================" -ForegroundColor Green
        Write-Host "Tool da tai va giai nen file vao thu muc:" -ForegroundColor White
        Write-Host "$extractPath" -ForegroundColor Cyan; Write-Host ""
        Write-Host "Buoc tiep theo ban can lam:" -ForegroundColor Yellow
        Write-Host "1. Mo thu muc tren." -ForegroundColor White
        Write-Host "2. Tim va chay file 'Run.cmd' bang quyen admin ." -ForegroundColor White
        Write-Host "3. Khi thay dong chu 'Filtered Activated, GoodbyeDPI is running' la xong." -ForegroundColor White
        Write-Host "4. DE NGUYEN cua so 'Run.bat' do, sau khi khong muon dung nua thi TAT di." -ForegroundColor White; Write-Host ""
        Write-Host "(Luu y: Neu bi loi hien ra web w3c tren app revoltG thi xoa file di)." -ForegroundColor Magenta
        Write-Host "=====================================================" -ForegroundColor Green
    }
    catch {
        Write-Host ""; Write-Host "[LOI NGHIEM TRONG]" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
    }
}


# Menu chính
function Show-MainMenu {
    param([string]$AdapterName)
    while ($true) {
        Clear-Host
        Write-Host "=====================================================" -ForegroundColor Green
        Write-Host "            DNS CHANGER TOOL v3.0" -ForegroundColor Green
        Write-Host "=====================================================" -ForegroundColor Green; Write-Host ""
        Write-Host "Card mang hien tai: $AdapterName" -ForegroundColor White; Write-Host ""
        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host "                  MENU CHINH" -ForegroundColor Cyan
        Write-Host "=====================================================" -ForegroundColor Cyan; Write-Host ""
        Write-Host "[1] Cloudflare DNS" -ForegroundColor White
        Write-Host "[2] Google DNS" -ForegroundColor White
        Write-Host "[3] AdGuard DNS" -ForegroundColor White
        Write-Host "[4] OpenDNS" -ForegroundColor White
        Write-Host "[5] Reset DNS (Tu dong)" -ForegroundColor White; Write-Host ""
        Write-Host "=====================================================" -ForegroundColor Magenta
        Write-Host "                TIEN ICH KHAC" -ForegroundColor Magenta
        Write-Host "=====================================================" -ForegroundColor Magenta; Write-Host ""
        Write-Host "[6] Tai & chuan bi GoodbyeDPI (dung thu cong)" -ForegroundColor White
        Write-Host "[7] Kiem tra DNS hien tai" -ForegroundColor White
        Write-Host "[8] Xoa DNS Cache" -ForegroundColor White
        Write-Host "[0] Thoat" -ForegroundColor Red; Write-Host ""
        Write-Host "=====================================================" -ForegroundColor Green
        
        $choice = Read-Host "Nhap lua chon cua ban (0-8)"
        Clear-Host
        
        switch ($choice) {
            "1" { Set-CustomDNS -AdapterName $AdapterName -PrimaryIPv4 "1.1.1.1" -SecondaryIPv4 "1.0.0.1" -PrimaryIPv6 "2606:4700:4700::1111" -SecondaryIPv6 "2606:4700:4700::1001" -ProviderName "Cloudflare"; if ($?) { Clear-DNSCache } }
            "2" { Set-CustomDNS -AdapterName $AdapterName -PrimaryIPv4 "8.8.8.8" -SecondaryIPv4 "8.8.4.4" -PrimaryIPv6 "2001:4860:4860::8888" -SecondaryIPv6 "2001:4860:4860::8844" -ProviderName "Google"; if ($?) { Clear-DNSCache } }
            "3" { Set-CustomDNS -AdapterName $AdapterName -PrimaryIPv4 "94.140.14.14" -SecondaryIPv4 "94.140.15.15" -PrimaryIPv6 "2a10:50c0::ad1:ff" -SecondaryIPv6 "2a10:50c0::ad2:ff" -ProviderName "AdGuard"; if ($?) { Clear-DNSCache } }
            "4" { Set-CustomDNS -AdapterName $AdapterName -PrimaryIPv4 "208.67.222.222" -SecondaryIPv4 "208.67.220.220" -PrimaryIPv6 "2620:119:35::35" -SecondaryIPv6 "2620:119:53::53" -ProviderName "OpenDNS"; if ($?) { Clear-DNSCache } }
            "5" { Reset-DNSToDefault -AdapterName $AdapterName; if ($?) { Clear-DNSCache } }
            "6" { Prepare-GoodbyeDPI }
            "7" { Show-CurrentDNS -AdapterName $AdapterName }
            "8" { Clear-DNSCache }
            "0" { Write-Host "Cam on ban da su dung!"; Start-Sleep -Seconds 1; exit 0 }
            default { Write-Host "Lua chon khong hop le!" -ForegroundColor Red; Start-Sleep -Seconds 2 }
        }
        if($choice -ne '0' -and $choice -in '1'..'8'){ Write-Host ""; Read-Host "Nhan Enter de tro ve menu chinh" }
    }
}

# Main execution
try {
    if (-not $RunAsAdmin) { Start-AsAdmin }
    $adapter = Get-ActiveNetworkAdapter
    if (-not $adapter) {
        Write-Host "[LOI] Khong tim thay network adapter nao!" -ForegroundColor Red
        Read-Host "Nhan Enter de thoat"; exit 1
    }
    Show-MainMenu -AdapterName $adapter.Name
}
catch {
    Write-Host "[LOI NGHIEM TRONG] $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Nhan Enter de thoat"; exit 1
}