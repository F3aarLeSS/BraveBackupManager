```powershell
# Brave Backup Manager Installer

$InstallDir = Join-Path $env:LOCALAPPDATA "BraveBackupManager"
$ScriptPath = Join-Path $InstallDir "BraveBackupManager.ps1"

$DownloadUrl = "https://raw.githubusercontent.com/F3aarLeSS/BraveBackupManager/main/BraveBackupManager.ps1"

# Create installation folder
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

Write-Host ""
Write-Host "Downloading Brave Backup Manager..." -ForegroundColor Cyan

Invoke-WebRequest `
    -Uri $DownloadUrl `
    -OutFile $ScriptPath

Write-Host "Download complete." -ForegroundColor Green
Write-Host ""

# Launch the latest version
powershell.exe `
    -ExecutionPolicy Bypass `
    -File $ScriptPath
```
