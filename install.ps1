# Brave Backup Manager Installer

$ErrorActionPreference = "Stop"

# Force TLS 1.2 for GitHub raw links
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$InstallDir = Join-Path $env:LOCALAPPDATA "BraveBackupManager"
$ScriptPath = Join-Path $InstallDir "BraveBackupManager.ps1"
$DownloadUrl = "https://raw.githubusercontent.com/F3aarLeSS/BraveBackupManager/main/BraveBackupManager.ps1"

# Create installation folder
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

Write-Host "`nDownloading Brave Backup Manager..." -ForegroundColor Cyan

try {
    # UseBasicParsing is critical to prevent IE engine dependency errors
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ScriptPath -UseBasicParsing
    Write-Host "Download complete.`n" -ForegroundColor Green
} catch {
    Write-Host "Failed to download the script. Error: $_" -ForegroundColor Red
    exit 1
}

# Launch the latest version bypassing local execution policy restrictions
powershell.exe -ExecutionPolicy Bypass -File $ScriptPath