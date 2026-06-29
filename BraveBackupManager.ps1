# =====================================================================
# Brave Backup Manager
# Version : 1.0.0
# =====================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------
# Global Variables
# ---------------------------------------------------------------------

$Script:AppName     = "Brave Backup Manager"
$Script:Version     = "1.0.0"

if ($PSCommandPath) {
    $Script:Root = Split-Path -Parent $PSCommandPath
} else {
    $Script:Root = $PWD.Path
}

$Script:BackupRoot  = Join-Path $Script:Root "Backup"
$Script:LogRoot     = Join-Path $Script:Root "Logs"
$Script:LogFile     = Join-Path $Script:LogRoot ("Log_{0}.txt" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))

# ---------------------------------------------------------------------
# Initialize
# ---------------------------------------------------------------------

function Initialize-App {

    foreach ($Folder in @($Script:BackupRoot, $Script:LogRoot)) {

        if (-not (Test-Path $Folder)) {
            New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        }

    }

    try {
        $Host.UI.RawUI.WindowTitle = "$($Script:AppName) v$($Script:Version)"
    } catch {}

}

# ---------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------

function Write-Log {

    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[{0}] [{1}] {2}" -f $Time, $Level, $Message
    Add-Content -Path $Script:LogFile -Value $Line

}

# ---------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------

function Show-Banner {

    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "                 BRAVE BACKUP MANAGER" -ForegroundColor White
    Write-Host "                    Version $($Script:Version)" -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("Computer : {0}" -f $env:COMPUTERNAME)
    Write-Host ("User     : {0}" -f $env:USERNAME)
    Write-Host ("Date     : {0}" -f (Get-Date))
    Write-Host ""

}

# ---------------------------------------------------------------------
# Pause
# ---------------------------------------------------------------------

function Pause-App {

    Write-Host ""
    Read-Host "Press ENTER to continue"

}

# ---------------------------------------------------------------------
# Main Menu
# ---------------------------------------------------------------------

function Show-MainMenu {

    while ($true) {

        Show-Banner

        Write-Host "1. Scan Brave"
        Write-Host "2. Backup"
        Write-Host "3. Restore"
        Write-Host "0. Exit"
        Write-Host ""

        $Choice = Read-Host "Select"

        switch ($Choice) {

            "1" {
                Get-BraveInstallations
                Get-BraveProfiles
                Show-Profiles
            }       

            "2" {
                Get-BraveInstallations
                Get-BraveProfiles

                if ($Script:Browsers.Count -eq 0) {
                    Write-Host "`nNo Brave installation found." -ForegroundColor Yellow
                    Pause-App
                    break
                }

                if (-not (Close-Brave)) { break }

                $Browser = Select-BraveBrowser
                if ($null -eq $Browser) { break }

                $Profiles = Select-BraveProfiles $Browser
                if ($null -eq $Profiles) { break }

                Show-SelectedProfiles $Profiles

                $SessionPath = New-BackupSession
                $BrowserFolder = New-BrowserBackupFolder -Browser $Browser -SessionPath $SessionPath

                Backup-LocalState -Browser $Browser -BrowserBackup $BrowserFolder
                Backup-Profiles -Browser $Browser -Profiles $Profiles -BrowserBackup $BrowserFolder
                
                $Verified = Test-Backup -BrowserBackup $BrowserFolder -Profiles $Profiles

                Write-BackupInfo -Browser $Browser -Profiles $Profiles -SessionPath $SessionPath

                if ($Verified) {
                    Write-Log "Backup verification passed."
                } else {
                    Write-Log "Backup verification completed with warnings." "WARNING"
                }

                Show-BackupSummary -SessionPath $SessionPath -Profiles $Profiles
            }

            "3" {
                # FLaw 1 Corrected: Force array evaluation to prevent Strict Mode failure
                $Sessions = @(Get-BackupSessions)
                
                if ($Sessions.Count -eq 0) {
                    Write-Host "`nNo valid backups found in $($Script:BackupRoot)." -ForegroundColor Yellow
                    Pause-App
                    break
                }

                $SelectedSession = Select-BackupSession -Sessions $Sessions
                if ($null -eq $SelectedSession) { break }

                Get-BraveInstallations

                $TargetBrowser = Select-TargetBrowser `
                    -Browsers $Script:Browsers `
                    -BackupEdition $SelectedSession.Browser

                if ($null -eq $TargetBrowser) {
                    Write-Host "`nTarget browser ($($SelectedSession.Browser)) is not installed on this system." -ForegroundColor Red
                    Write-Log "Restore failed. Target browser not found." "ERROR"
                    Pause-App
                    break
                }

                Write-Host "`nWARNING: Restoring will overwrite existing profile data and the Local State file." -ForegroundColor Yellow
                Write-Host "Overwriting Local State will destroy access to passwords for any profiles NOT included in this restore." -ForegroundColor Red
                $Confirm = Read-Host "Are you sure you want to proceed? (Y/N)"
                
                if ($Confirm.ToUpper() -ne "Y") {
                    Write-Host "Restore aborted." -ForegroundColor Yellow
                    Pause-App
                    break
                }

                if (-not (Close-Brave)) { break }

                $BrowserBackupPath = Join-Path $SelectedSession.Path ($SelectedSession.Browser -replace ' ','_')

                Restore-LocalState -Source $BrowserBackupPath -Destination $TargetBrowser.UserData
                Restore-Profiles -Source $BrowserBackupPath -Destination $TargetBrowser.UserData -Profiles $SelectedSession.Profiles

                Write-Host "`n==============================================" -ForegroundColor Green
                Write-Host "RESTORE COMPLETED" -ForegroundColor Green
                Write-Host "==============================================" -ForegroundColor Green
                Write-Log "Restore operation completed for $($SelectedSession.Browser)."
                Pause-App
            }

            "0" {
                Write-Log "Application closed."
                return
            }

            default {
                Write-Host "`nInvalid selection." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ---------------------------------------------------------------------
# Backup Session Management
# ---------------------------------------------------------------------

function Get-BackupSessions {
    
    $Sessions = @()
    if (-not (Test-Path $Script:BackupRoot)) { return $Sessions }

    $Folders = Get-ChildItem -Path $Script:BackupRoot -Directory -ErrorAction SilentlyContinue

    foreach ($Folder in $Folders) {
        $JsonPath = Join-Path $Folder.FullName "BackupInfo.json"
        
        if (Test-Path $JsonPath) {
            try {
                $Info = Get-Content $JsonPath -Raw | ConvertFrom-Json
                $SessionObj = [PSCustomObject]@{
                    Path           = $Folder.FullName
                    FolderName     = $Folder.Name
                    Date           = $Info.BackupDate
                    Browser        = if ($Info.BrowserEdition) {
                        $Info.BrowserEdition
                    } else {
                        $Info.Browser
                    }
                    BrowserVersion = $Info.BrowserVersion
                    ProfileCount   = $Info.ProfileCount
                    Profiles       = $Info.Profiles
                }
                $Sessions += $SessionObj
            } catch {
                Write-Log "Corrupt BackupInfo.json found in $($Folder.Name)." "WARNING"
            }
        }
    }

    # Sort descending by name (timestamp)
    return $Sessions | Sort-Object FolderName -Descending
}

function Select-BackupSession {
    
    param($Sessions)

    $Sessions = @($Sessions)

    while ($true) {
        Show-Banner
        Write-Host "Available Backup Sessions"
        Write-Host ""

        $Index = 1
        foreach ($Session in $Sessions) {
            Write-Host ("[{0}] {1} ({2})" -f $Index, $Session.FolderName, $Session.Browser) -ForegroundColor Green
            Write-Host ("     Date     : {0}" -f $Session.Date)
            Write-Host ("     Profiles : {0}" -f $Session.ProfileCount)
            Write-Host ""
            $Index++
        }

        Write-Host "[Q] Cancel"
        Write-Host ""

        $Choice = Read-Host "Select Backup to Restore"

        if ($Choice.ToUpper() -eq "Q") { return $null }

        if ($Choice -match '^\d+$') {
            $Number = [int]$Choice
            if ($Number -ge 1 -and $Number -le $Sessions.Count) {
                return $Sessions[$Number-1]
            }
        }

        Write-Host "`nInvalid selection." -ForegroundColor Red
        Start-Sleep 1
    }
}

# FLaw 2 Corrected: Added missing Select-TargetBrowser function
function Select-TargetBrowser {
    
    param(
        [Parameter(Mandatory)]$Browsers,
        [Parameter(Mandatory)][string]$BackupEdition
    )

    $Browsers = @($Browsers)

    while ($true) {
        Show-Banner
        Write-Host "Backup Origin : $BackupEdition" -ForegroundColor Cyan
        Write-Host "------------------------------------------------------------"
        Write-Host "Select target installation for restore:`n"

        $Index = 1
        foreach ($Browser in $Browsers) {
            Write-Host ("[{0}] {1}" -f $Index, $Browser.Name) -ForegroundColor Green
            Write-Host ("     Version : {0}" -f $Browser.Version)
            Write-Host ("     Path    : {0}`n" -f $Browser.UserData)
            $Index++
        }

        Write-Host "[Q] Cancel`n"

        $Choice = Read-Host "Select Target Browser"

        if ($Choice.ToUpper() -eq "Q") { return $null }

        if ($Choice -match '^\d+$') {
            $Number = [int]$Choice
            if ($Number -ge 1 -and $Number -le $Browsers.Count) {
                $Selected = $Browsers[$Number-1]
                
                # Cross-channel safeguard
                if ($Selected.Name -ne $BackupEdition) {
                    Write-Host "`nWARNING: Restoring a backup from $BackupEdition to $($Selected.Name) may corrupt the profile due to underlying Chromium schema mismatches." -ForegroundColor Red
                    $Confirm = Read-Host "Type 'YES' to force restore anyway, or press ENTER to cancel"
                    if ($Confirm -cne "YES") { continue }
                }
                
                return $Selected
            }
        }

        Write-Host "`nInvalid selection." -ForegroundColor Red
        Start-Sleep 1
    }
}

# ---------------------------------------------------------------------
# Restore Logic
# ---------------------------------------------------------------------

function Restore-LocalState {

    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $SourceFile = Join-Path $Source "Local State"
    if (-not (Test-Path $SourceFile)) {
        Write-Log "Local State not found in backup source." "WARNING"
        return
    }

    $DestFile = Join-Path $Destination "Local State"
    
    try {
        Copy-Item -Path $SourceFile -Destination $DestFile -Force -ErrorAction Stop
        Write-Log "Local State restored successfully."
        Write-Host "[OK] Local State Restored" -ForegroundColor Green
    } catch {
        Write-Log "Failed to restore Local State: $_" "ERROR"
        Write-Host "[FAILED] Local State Restore" -ForegroundColor Red
    }
}

function Restore-Profiles {
    
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)]$Profiles
    )

    $Profiles = @($Profiles)
    $Total = $Profiles.Count
    $Current = 0

    foreach ($Profile in $Profiles) {
        $Current++
        $Percent = [math]::Round(($Current / $Total) * 100)

        Write-Progress -Activity "Restoring Brave Profiles" -Status $Profile.DisplayName -PercentComplete $Percent

        $SourceProfile = Join-Path $Source $Profile.FolderName
        $DestProfile = Join-Path $Destination $Profile.FolderName

        if (-not (Test-Path $SourceProfile)) {
            Write-Log "Source profile folder missing: $($Profile.FolderName)" "ERROR"
            Write-Host "[FAILED] $($Profile.DisplayName) (Missing Source)" -ForegroundColor Red
            continue
        }

        if (-not (Test-Path $DestProfile)) {
            New-Item -ItemType Directory -Path $DestProfile -Force | Out-Null
        }

        Write-Log "Restoring profile: $($Profile.DisplayName) -> $DestProfile"

        # Using /MIR for restore to completely mirror the backup and wipe corrupted newer files
        $Arguments = @(
            $SourceProfile
            $DestProfile
            "/MIR"
            "/COPY:DAT"
            "/R:1"
            "/W:1"
            "/NFL"
            "/NDL"
            "/NJH"
            "/NJS"
            "/NP"
        )

        Write-Host "Restoring: $($Profile.DisplayName)..." -ForegroundColor Cyan
        & robocopy @Arguments
        $ExitCode = $LASTEXITCODE

        if ($ExitCode -le 7) {
            Write-Host ("[OK] {0}" -f $Profile.DisplayName) -ForegroundColor Green
            Write-Log "Robocopy restore completed for $($Profile.FolderName)."
        } else {
            Write-Host ("[FAILED] {0} (Robocopy Code: $ExitCode)" -f $Profile.DisplayName) -ForegroundColor Red
            Write-Log "Robocopy restore failed for $($Profile.FolderName). Exit Code: $ExitCode" "ERROR"
        }
    }

    Write-Progress -Activity "Restoring Brave Profiles" -Completed
}

# ---------------------------------------------------------------------
# Get Brave Version
# ---------------------------------------------------------------------

function Get-BraveVersion {
    param([string]$ExePath)
    if (-not (Test-Path $ExePath)) { return "Unknown" }
    try { return (Get-Item $ExePath).VersionInfo.ProductVersion } catch { return "Unknown" }
}

# ---------------------------------------------------------------------
# Scan Brave Installations
# ---------------------------------------------------------------------

function Get-BraveInstallations {
    $Script:Browsers = @()
    $BrowserList = @(
        @{ Name = "Brave Stable"; UserData = Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data"; Exe = Join-Path $env:ProgramFiles "BraveSoftware\Brave-Browser\Application\brave.exe" },
        @{ Name = "Brave Beta"; UserData = Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser-Beta\User Data"; Exe = Join-Path $env:ProgramFiles "BraveSoftware\Brave-Browser-Beta\Application\brave.exe" },
        @{ Name = "Brave Dev"; UserData = Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser-Dev\User Data"; Exe = Join-Path $env:ProgramFiles "BraveSoftware\Brave-Browser-Dev\Application\brave.exe" },
        @{ Name = "Brave Nightly"; UserData = Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser-Nightly\User Data"; Exe = Join-Path $env:ProgramFiles "BraveSoftware\Brave-Browser-Nightly\Application\brave.exe" }
    )

    foreach ($Browser in $BrowserList) {
        if (Test-Path $Browser.UserData) {
            $Object = [PSCustomObject]@{
                Name     = $Browser.Name
                Version  = Get-BraveVersion $Browser.Exe
                UserData = $Browser.UserData
                Exe      = $Browser.Exe
            }
            $Script:Browsers += $Object
        }
    }
}

# ---------------------------------------------------------------------
# Show Browser List
# ---------------------------------------------------------------------

function Show-BrowserList {
    Show-Banner
    Write-Host "Detected Brave Browsers`n"

    if ($Script:Browsers.Count -eq 0) {
        Write-Host "No Brave browser detected.`n" -ForegroundColor Yellow
        Pause-App
        return
    }

    foreach ($Browser in $Script:Browsers) {
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host ("Name      : {0}" -f $Browser.Name) -ForegroundColor Green
        Write-Host ("Version   : {0}" -f $Browser.Version)
        Write-Host ("User Data : {0}" -f $Browser.UserData)
        Write-Host ("EXE Path  : {0}" -f $Browser.Exe)
        Write-Host ""
    }
    Pause-App
}

# ---------------------------------------------------------------------
# Read Local State
# ---------------------------------------------------------------------

function Get-LocalState {
    param([string]$UserDataPath)
    $LocalStateFile = Join-Path $UserDataPath "Local State"
    if (-not (Test-Path $LocalStateFile)) { return $null }
    try { return (Get-Content $LocalStateFile -Raw | ConvertFrom-Json) } catch { return $null }
}

# ---------------------------------------------------------------------
# Get Friendly Profile Name
# ---------------------------------------------------------------------

function Get-FriendlyProfileName {
    param($LocalState, [string]$FolderName)
    if ($null -eq $LocalState) { return $FolderName }
    try {
        if ($null -ne $LocalState.profile.info_cache) {
            foreach ($Property in $LocalState.profile.info_cache.PSObject.Properties) {
                if ($Property.Name -eq $FolderName -and -not [string]::IsNullOrWhiteSpace($Property.Value.name)) {
                    return $Property.Value.name
                }
            }
        }
    } catch {}
    return $FolderName
}

# ---------------------------------------------------------------------
# Detect Profiles
# ---------------------------------------------------------------------

function Get-BraveProfiles {
    foreach ($Browser in $Script:Browsers) {
        $Browser | Add-Member -MemberType NoteProperty -Name Profiles -Value @() -Force
        $LocalState = Get-LocalState $Browser.UserData
        $Folders = Get-ChildItem -Path $Browser.UserData -Directory -ErrorAction SilentlyContinue

        foreach ($Folder in $Folders) {
            $IsProfile = $false
            if ($Folder.Name -eq "Default" -or $Folder.Name -match "^Profile [0-9]+$") { $IsProfile = $true }
            if (-not $IsProfile) { continue }

            $DisplayName = Get-FriendlyProfileName -LocalState $LocalState -FolderName $Folder.Name
            $Profile = [PSCustomObject]@{
                BrowserName = $Browser.Name
                BrowserPath = $Browser.UserData
                DisplayName = $DisplayName
                FolderName  = $Folder.Name
                FullPath    = $Folder.FullName
            }
            $Browser.Profiles += $Profile
        }
    }
}

# ---------------------------------------------------------------------
# Show Profiles
# ---------------------------------------------------------------------

function Show-Profiles {
    Show-Banner
    if ($Script:Browsers.Count -eq 0) {
        Write-Host "No Brave browser detected." -ForegroundColor Yellow
        Pause-App
        return
    }

    foreach ($Browser in $Script:Browsers) {
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host $Browser.Name -ForegroundColor Green
        Write-Host "Version : $($Browser.Version)"
        Write-Host "Profiles: $($Browser.Profiles.Count)"
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""

        if ($Browser.Profiles.Count -eq 0) {
            Write-Host "No profiles found.`n" -ForegroundColor Yellow
            continue
        }

        $Index = 1
        foreach ($Profile in $Browser.Profiles) {
            Write-Host ("[{0}] {1}" -f $Index,$Profile.DisplayName) -ForegroundColor White
            Write-Host ("     Folder : {0}" -f $Profile.FolderName) -ForegroundColor DarkGray
            Write-Host ""
            $Index++
        }
    }
    Pause-App
}

# ---------------------------------------------------------------------
# Check if Brave is Running
# ---------------------------------------------------------------------

function Test-BraveRunning {
    $Processes = Get-Process -Name "brave" -ErrorAction SilentlyContinue
    if ($null -eq $Processes -or $Processes.Count -eq 0) { return $false }
    return $true
}

function Show-BraveProcesses {
    $Processes = Get-Process -Name "brave" -ErrorAction SilentlyContinue
    if ($null -eq $Processes) { return }

    Write-Host "`nRunning Brave Processes"
    Write-Host "------------------------------------------------"
    foreach ($Process in $Processes) {
        Write-Host ("PID : {0,-8} Memory : {1:N0} MB" -f $Process.Id, ($Process.WorkingSet64 / 1MB))
    }
    Write-Host ""
}

function Close-Brave {
    if (-not (Test-BraveRunning)) { return $true }
    Show-BraveProcesses

    $Answer = Read-Host "Brave is running. Close it now? (Y/N)"
    if ($Answer.ToUpper() -ne "Y") {
        Write-Host "`nOperation cancelled." -ForegroundColor Yellow
        Pause-App
        return $false
    }

    try {
        Stop-Process -Name "brave" -Force -ErrorAction Stop
        Start-Sleep -Seconds 2
        Write-Host "`nBrave closed successfully." -ForegroundColor Green
        Write-Log "Brave closed."
        return $true
    } catch {
        Write-Host "`nUnable to close Brave." -ForegroundColor Red
        Write-Log "Unable to close Brave." "ERROR"
        Pause-App
        return $false
    }
}

# ---------------------------------------------------------------------
# Select Browser
# ---------------------------------------------------------------------

function Select-BraveBrowser {
    if ($Script:Browsers.Count -eq 0) { return $null }

    while ($true) {
        Show-Banner
        Write-Host "Available Brave Installations`n"

        $Index = 1
        foreach ($Browser in $Script:Browsers) {
            Write-Host ("[{0}] {1}" -f $Index,$Browser.Name) -ForegroundColor Green
            Write-Host ("     Version  : {0}" -f $Browser.Version)
            Write-Host ("     Profiles : {0}" -f $Browser.Profiles.Count)
            Write-Host ""
            $Index++
        }

        Write-Host "[Q] Cancel`n"
        $Choice = Read-Host "Select Browser"

        if ($Choice.ToUpper() -eq "Q") { return $null }

        if ($Choice -match '^\d+$') {
            $Number = [int]$Choice
            if ($Number -ge 1 -and $Number -le $Script:Browsers.Count) {
                return $Script:Browsers[$Number-1]
            }
        }

        Write-Host "`nInvalid selection." -ForegroundColor Red
        Start-Sleep 1
    }
}

# ---------------------------------------------------------------------
# Profile Menu / Selection
# ---------------------------------------------------------------------

function Show-ProfileMenu {
    param($Browser)
    Show-Banner
    Write-Host ("Browser : {0}" -f $Browser.Name) -ForegroundColor Cyan
    Write-Host ("Version : {0}`n" -f $Browser.Version)

    if ($Browser.Profiles.Count -eq 0) {
        Write-Host "No profiles found." -ForegroundColor Yellow
        Pause-App
        return
    }

    $Index = 1
    foreach ($Profile in $Browser.Profiles) {
        Write-Host ("[{0}] {1}" -f $Index,$Profile.DisplayName) -ForegroundColor Green
        Write-Host ("     Folder : {0}`n" -f $Profile.FolderName)
        $Index++
    }

    Write-Host "----------------------------------------------"
    Write-Host "A = Backup ALL Profiles"
    Write-Host "Q = Cancel`n"
    Write-Host "Examples: 1 | 1,3 | A`n"
}

function Select-BraveProfiles {
    param($Browser)

    while ($true) {
        Show-ProfileMenu $Browser
        $Choice = Read-Host "Select Profile(s)"

        if ([string]::IsNullOrWhiteSpace($Choice)) { continue }
        $Choice = $Choice.Trim()

        if ($Choice.ToUpper() -eq "Q") { return $null }
        if ($Choice.ToUpper() -eq "A") { return $Browser.Profiles }

        $SelectedProfiles = @()
        $Valid = $true
        $Numbers = $Choice -split ","

        foreach ($Number in $Numbers) {
            $Number = $Number.Trim()
            if ($Number -notmatch '^\d+$') { $Valid = $false; break }

            $Index = [int]$Number
            if ($Index -lt 1 -or $Index -gt $Browser.Profiles.Count) { $Valid = $false; break }

            $Profile = $Browser.Profiles[$Index - 1]
            $Exists = $false

            foreach ($ExistingProfile in $SelectedProfiles) {
                if ($ExistingProfile.FolderName -eq $Profile.FolderName) { $Exists = $true; break }
            }

            if (-not $Exists) { $SelectedProfiles += $Profile }
        }

        if ($Valid) { return $SelectedProfiles }

        Write-Host "`nInvalid selection." -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
}

function Show-SelectedProfiles {
    param($Profiles)
    Show-Banner

    if ($null -eq $Profiles) {
        Write-Host "No profile selected." -ForegroundColor Yellow
        Pause-App
        return
    }

    Write-Host "Selected Profiles`n"
    $Count = 1

    foreach ($Profile in $Profiles) {
        Write-Host ("[{0}] {1}" -f $Count,$Profile.DisplayName) -ForegroundColor Green
        Write-Host ("     Folder  : {0}" -f $Profile.FolderName)
        Write-Host ("     Browser : {0}`n" -f $Profile.BrowserName)
        $Count++
    }
    Pause-App
}

# ---------------------------------------------------------------------
# Backup File/Folder Management
# ---------------------------------------------------------------------

function New-BackupSession {
    $TimeStamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $SessionPath = Join-Path $Script:BackupRoot $TimeStamp
    if (!(Test-Path $SessionPath)) { New-Item -ItemType Directory -Path $SessionPath -Force | Out-Null }
    return $SessionPath
}

function New-BrowserBackupFolder {
    param(
        [Parameter(Mandatory)]$Browser,
        [Parameter(Mandatory)][string]$SessionPath
    )
    $FolderName = $Browser.Name.Replace(" ","_")
    $BrowserBackup = Join-Path $SessionPath $FolderName
    if (!(Test-Path $BrowserBackup)) { New-Item -ItemType Directory -Path $BrowserBackup -Force | Out-Null }
    return $BrowserBackup
}

function Backup-LocalState {
    param(
        [Parameter(Mandatory)]$Browser,
        [Parameter(Mandatory)][string]$BrowserBackup
    )
    $Source = Join-Path $Browser.UserData "Local State"
    if (!(Test-Path $Source)) {
        Write-Log "Local State not found for $($Browser.Name)." "WARNING"
        return
    }
    $Destination = Join-Path $BrowserBackup "Local State"
    Copy-Item -Path $Source -Destination $Destination -Force
    Write-Log "Local State backed up."
}

# ---------------------------------------------------------------------
# Robocopy Backup Logic
# ---------------------------------------------------------------------

$Script:ExcludedFolders = @(
    "Cache", "Code Cache", "GPUCache", "GrShaderCache", "ShaderCache", 
    "DawnCache", "Crashpad", "Media Cache", "Safe Browsing", 
    "OptimizationHints", "Component CRX Cache"
)

function Get-RobocopyExcludeArgs {
    param([Parameter(Mandatory)][string]$SourceFolder)
    $Args = @()
    foreach ($Folder in $Script:ExcludedFolders) {
        $Path = Join-Path $SourceFolder $Folder
        if (Test-Path $Path) { $Args += "/XD"; $Args += $Path }
    }
    return $Args
}

function Invoke-BraveRobocopy {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    if (!(Test-Path $Destination)) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }

    $Arguments = @($Source, $Destination, "/E", "/COPY:DAT", "/R:1", "/W:1", "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
    $Arguments += Get-RobocopyExcludeArgs $Source

    Write-Host "`nCopying : $($Profile.DisplayName) -> $(Split-Path $Source -Leaf)" -ForegroundColor Cyan
    & robocopy @Arguments
    $ExitCode = $LASTEXITCODE

    if ($ExitCode -le 7) {
        Write-Log "Robocopy backup completed successfully."
        return $true
    }
    Write-Log "Robocopy failed. Exit Code: $ExitCode" "ERROR"
    return $false
}

function Backup-Profiles {
    param(
        [Parameter(Mandatory)]$Browser,
        [Parameter(Mandatory)]$Profiles,
        [Parameter(Mandatory)][string]$BrowserBackup
    )
    $Profiles = @($Profiles)
    $Total = $Profiles.Count
    $Current = 0

    foreach ($Profile in $Profiles) {
        $Current++
        $Percent = [math]::Round(($Current / $Total) * 100)
        Write-Progress -Activity "Backing up Brave Profiles" -Status $Profile.DisplayName -PercentComplete $Percent

        $Destination = Join-Path $BrowserBackup $Profile.FolderName
        Write-Log "Backing up profile: $($Profile.DisplayName)"

        $Success = Invoke-BraveRobocopy -Source $Profile.FullPath -Destination $Destination

        if ($Success) {
            Write-Host ("[OK] {0}" -f $Profile.DisplayName) -ForegroundColor Green
        } else {
            Write-Host ("[FAILED] {0}" -f $Profile.DisplayName) -ForegroundColor Red
        }
    }
    Write-Progress -Activity "Backing up Brave Profiles" -Completed
}

function Get-FolderSize {
    param([Parameter(Mandatory)][string]$Folder)
    if (!(Test-Path $Folder)) { return 0 }
    $Size = (Get-ChildItem $Folder -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($null -eq $Size) { $Size = 0 }
    return [math]::Round($Size / 1MB,2)
}

function Test-Backup {
    param(
        [Parameter(Mandatory)][string]$BrowserBackup,
        [Parameter(Mandatory)]$Profiles
    )
    $Profiles = @($Profiles)
    $Passed = $true

    foreach ($Profile in $Profiles) {
        $Folder = Join-Path $BrowserBackup $Profile.FolderName
        if (!(Test-Path $Folder)) {
            Write-Log "Missing profile folder: $($Profile.FolderName)" "ERROR"
            $Passed = $false
            continue
        }

        $CriticalFiles = @("Bookmarks", "Preferences", "History", "Login Data", "Web Data")
        foreach ($File in $CriticalFiles) {
            $Path = Join-Path $Folder $File
            if (!(Test-Path $Path)) { Write-Log "$($Profile.DisplayName) : Missing $File" "WARNING" }
        }
    }
    return $Passed
}

function Write-BackupInfo {

    param(
        [Parameter(Mandatory)]
        $Browser,

        [Parameter(Mandatory)]
        $Profiles,

        [Parameter(Mandatory)]
        [string]$SessionPath
    )

    $Profiles = @($Profiles)

    $Info = [ordered]@{

        BackupFormatVersion  = 1
        BackupManagerVersion = $Script:Version
        BackupID             = (Get-Date).ToString("yyyyMMddHHmmss")
        BackupDate           = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

        BrowserEdition       = $Browser.Name
        BrowserVersion       = $Browser.Version
        BrowserUserDataPath  = $Browser.UserData
        BrowserUserDataFolder= Split-Path $Browser.UserData -Leaf

        ComputerName         = $env:COMPUTERNAME
        WindowsUser          = $env:USERNAME

        ProfileCount         = $Profiles.Count
        BackupSizeMB         = Get-FolderSize $SessionPath

        Profiles             = @()

    }

    foreach ($Profile in $Profiles) {

        $Info.Profiles += [ordered]@{

            DisplayName = $Profile.DisplayName
            FolderName  = $Profile.FolderName
            RelativePath = $Profile.FolderName

        }

    }

    $Info |
        ConvertTo-Json -Depth 5 |
        Set-Content `
            -Path (Join-Path $SessionPath "BackupInfo.json") `
            -Encoding UTF8

    Write-Log "BackupInfo.json created."

}

function Show-BackupSummary {
    param(
        [Parameter(Mandatory)][string]$SessionPath,
        [Parameter(Mandatory)]$Profiles
    )
    $Profiles = @($Profiles)
    Show-Banner
    $Size = Get-FolderSize $SessionPath

    Write-Host "==============================================" -ForegroundColor Green
    Write-Host "BACKUP COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host ("Profiles Backed Up : {0}" -f $Profiles.Count)
    Write-Host ("Backup Size        : {0} MB" -f $Size)
    Write-Host ("Location           : {0}" -f $SessionPath)
    Write-Host ""
    Pause-App
}

# ---------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------

Initialize-App
Write-Log "Application started."
Show-MainMenu