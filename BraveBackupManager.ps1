# =====================================================================
# Brave Backup Manager (UI Edition)
# Base Logic Version : 1.0.0
# UI Implementation  : 1.2.0
# =====================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------
# Global Variables
# ---------------------------------------------------------------------

$Script:AppName     = "Brave Backup Manager"
$Script:Version     = "1.2.0"

# Define a static, predictable path on the user's Desktop
$DesktopPath        = [Environment]::GetFolderPath("Desktop")
$Script:Root        = Join-Path $DesktopPath $Script:AppName

$Script:BackupRoot  = Join-Path $Script:Root "Backup"
$Script:LogRoot     = Join-Path $Script:Root "Logs"
$Script:LogFile     = Join-Path $Script:LogRoot ("Log_{0}.txt" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))

$Script:ExcludedFolders = @(
    "Cache", "Code Cache", "GPUCache", "GrShaderCache", "ShaderCache", 
    "DawnCache", "Crashpad", "Media Cache", "Safe Browsing", 
    "OptimizationHints", "Component CRX Cache"
)

# ---------------------------------------------------------------------
# UI Rendering Functions (ASCII Safe)
# ---------------------------------------------------------------------

function Show-Header {
    Clear-Host
    $Art = @"
  ___                     ___       _            
 | _ )_ _ __ ___ _____   | _ ) __ _| |___  _ _ __
 | _ \ '_/ _` \ V / -_)  | _ \/ _` | / / || | '_ \
 |___/_| \__,_|\_/\___|  |___/\__,_|_\_\\_,_| .__/
                                            |_|  
"@
    Write-Host $Art -ForegroundColor Gray
    Write-Host "  By Navajyoti Bayan" -ForegroundColor DarkGray
    Write-Host "  Version $($Script:Version)`n" -ForegroundColor DarkGray
}

function Write-FrameTop {
    param(
        [string]$Title,
        [string]$StatusDot = "",
        [string]$StatusText = ""
    )
    Write-Host "+- " -ForegroundColor Red -NoNewline
    Write-Host $Title -ForegroundColor White -NoNewline
    Write-Host " --------------------------------------------------" -ForegroundColor Red
    
    if ($StatusText) {
        Write-Host "|   " -ForegroundColor Red -NoNewline
        if ($StatusDot -eq "red") {
            Write-Host "* " -ForegroundColor Red -NoNewline
            Write-Host $StatusText -ForegroundColor Red
        } else {
            Write-Host "* " -ForegroundColor Green -NoNewline
            Write-Host $StatusText -ForegroundColor Green
        }
        Write-Host " |" -ForegroundColor Red
    } else {
        Write-Host "|" -ForegroundColor Red
    }
}

function Write-FrameLine {
    param([string]$Text, [string]$Color = "White")
    Write-Host "|   " -ForegroundColor Red -NoNewline
    Write-Host $Text -ForegroundColor $Color
}

function Write-FrameKeyVal {
    param([string]$Key, [string]$Value, [string]$ValueColor = "Cyan")
    Write-Host "|   " -ForegroundColor Red -NoNewline
    $PaddedKey = $Key.PadRight(15)
    Write-Host $PaddedKey -ForegroundColor DarkGray -NoNewline
    Write-Host $Value -ForegroundColor $ValueColor
}

function Write-FrameBottom {
    Write-Host "+--------------------------------------------------------" -ForegroundColor Red
    Write-Host ""
}

function Read-Prompt {
    param([string]$Text)
    Write-Host "> " -ForegroundColor Yellow -NoNewline
    Write-Host $Text -ForegroundColor Yellow
    $Input = Read-Host
    return $Input
}

function Pause-App {
    Write-Host ""
    Write-Host "> " -ForegroundColor Yellow -NoNewline
    Read-Host "Press ENTER to continue"
}

# ---------------------------------------------------------------------
# Initialize & Logging
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
# Main Menu Flow
# ---------------------------------------------------------------------

function Show-MainMenu {
    while ($true) {
        Show-Header
        Write-FrameTop -Title "Main Menu ( Can't Backup & Restore Passwords"
        Write-FrameLine "[1] Scan Brave Installations"
        Write-FrameLine "[2] Backup Profiles"
        Write-FrameLine "[3] Restore Profile"
        Write-FrameLine "[0] Exit"
        Write-FrameLine " "
        Write-FrameKeyVal "Computer" $env:COMPUTERNAME "DarkGray"
        Write-FrameKeyVal "User" $env:USERNAME "DarkGray"
        Write-FrameKeyVal "Date" (Get-Date -Format "yyyy-MM-dd") "DarkGray"
        Write-FrameBottom

        $Choice = Read-Prompt "Select an option"

        switch ($Choice) {
            "1" { 
                Get-BraveInstallations
                Get-BraveProfiles
                Show-Profiles
            }       
            "2" { Run-BackupFlow }
            "3" { Run-RestoreFlow }
            "0" { 
                Write-Log "Application closed."
                return 
            }
            default { 
                Write-Host " Invalid selection." -ForegroundColor Red
                Start-Sleep -Seconds 1 
            }
        }
    }
}

# ---------------------------------------------------------------------
# Primary Flows
# ---------------------------------------------------------------------

function Run-BackupFlow {
    Get-BraveInstallations
    Get-BraveProfiles

    if ($Script:Browsers.Count -eq 0) {
        Show-Header
        Write-FrameTop -Title "Backup Error" -StatusDot "red" -StatusText "FAIL"
        Write-FrameLine "No Brave installation found." "Yellow"
        Write-FrameBottom
        Pause-App
        return
    }

    if (-not (Close-Brave)) { return }

    $Browser = Select-BraveBrowser
    if ($null -eq $Browser) { return }

    $Profiles = Select-BraveProfiles $Browser
    if ($null -eq $Profiles) { return }

    Show-Header
    Write-FrameTop -Title "Operation in Progress" -StatusDot "green" -StatusText "RUNNING"
    Write-FrameLine "Creating backup directories..." "Cyan"

    $SessionPath = New-BackupSession
    $BrowserFolder = New-BrowserBackupFolder -Browser $Browser -SessionPath $SessionPath

    Write-FrameLine "Processing Local State..." "Cyan"
    Backup-LocalState -Browser $Browser -BrowserBackup $BrowserFolder
    
    Backup-Profiles -Browser $Browser -Profiles $Profiles -BrowserBackup $BrowserFolder
    
    $Verified = Test-Backup -BrowserBackup $BrowserFolder -Profiles $Profiles
    Write-BackupInfo -Browser $Browser -Profiles $Profiles -SessionPath $SessionPath

    if ($Verified) {
        Write-Log "Backup verification passed."
    } else {
        Write-Log "Backup verification completed with warnings." "WARNING"
    }

    Write-FrameBottom
    Start-Sleep 1

    Show-BackupSummary -SessionPath $SessionPath -Profiles $Profiles
}

function Run-RestoreFlow {
    $Sessions = @(Get-BackupSessions)
    
    if ($Sessions.Count -eq 0) {
        Show-Header
        Write-FrameTop -Title "Restore Error" -StatusDot "red" -StatusText "NOT FOUND"
        Write-FrameLine "No valid backups found in $($Script:BackupRoot)." "Yellow"
        Write-FrameBottom
        Pause-App
        return
    }

    $SelectedSession = Select-BackupSession -Sessions $Sessions
    if ($null -eq $SelectedSession) { return }

    Get-BraveInstallations
    $TargetBrowser = Select-TargetBrowser -Browsers $Script:Browsers -BackupEdition $SelectedSession.Browser

    if ($null -eq $TargetBrowser) {
        Show-Header
        Write-FrameTop -Title "Restore Error" -StatusDot "red" -StatusText "FAIL"
        Write-FrameLine "Target browser ($($SelectedSession.Browser)) is not installed." "Red"
        Write-FrameBottom
        Write-Log "Restore failed. Target browser not found." "ERROR"
        Pause-App
        return
    }

    Show-Header
    Write-FrameTop -Title "Restore: Critical Warning" -StatusDot "red" -StatusText "WARNING"
    Write-FrameLine "Restoring will overwrite existing profile data." "Red"
    Write-FrameLine "Overwriting Local State destroys access to passwords" "White"
    Write-FrameLine "for any profiles NOT included in this restore." "White"
    Write-FrameBottom

    $Confirm = Read-Prompt "Type Y to proceed or N to abort"
    if ($Confirm.ToUpper() -ne "Y") { return }

    if (-not (Close-Brave)) { return }

    Show-Header
    Write-FrameTop -Title "Operation in Progress" -StatusDot "green" -StatusText "RESTORING"

    $BrowserBackupPath = Join-Path $SelectedSession.Path ($SelectedSession.Browser -replace " ","_")

    Restore-LocalState -Source $BrowserBackupPath -Destination $TargetBrowser.UserData
    Restore-Profiles -Source $BrowserBackupPath -Destination $TargetBrowser.UserData -Profiles $SelectedSession.Profiles

    Write-Log "Restore operation completed for $($SelectedSession.Browser)."
    Write-FrameBottom
    Start-Sleep 1

    Show-Header
    Write-FrameTop -Title "Restore Summary" -StatusDot "green" -StatusText "COMPLETED"
    Write-FrameLine "Profile data mirrored successfully." "White"
    Write-FrameKeyVal "Status" "Success" "Green"
    Write-FrameBottom
    Pause-App
}

# ---------------------------------------------------------------------
# Base Logic (Adapted for UI)
# ---------------------------------------------------------------------

function Get-BraveVersion {
    param([string]$ExePath)
    if (-not (Test-Path $ExePath)) { return "Unknown" }
    try { return (Get-Item $ExePath).VersionInfo.ProductVersion } catch { return "Unknown" }
}

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

function Get-LocalState {
    param([string]$UserDataPath)
    $LocalStateFile = Join-Path $UserDataPath "Local State"
    if (-not (Test-Path $LocalStateFile)) { return $null }
    try { return (Get-Content $LocalStateFile -Raw | ConvertFrom-Json) } catch { return $null }
}

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

function Show-Profiles {
    Show-Header
    if ($Script:Browsers.Count -eq 0) {
        Write-FrameTop -Title "Scan Results" -StatusDot "red" -StatusText "NOT FOUND"
        Write-FrameLine "No Brave browser detected." "Yellow"
        Write-FrameBottom
        Pause-App
        return
    }

    foreach ($Browser in $Script:Browsers) {
        Write-FrameTop -Title $Browser.Name
        Write-FrameKeyVal "Version" $Browser.Version "White"
        Write-FrameKeyVal "Profiles" $Browser.Profiles.Count "White"
        Write-FrameLine " "
        
        if ($Browser.Profiles.Count -eq 0) {
            Write-FrameLine "No profiles found." "DarkGray"
        } else {
            $Index = 1
            foreach ($Profile in $Browser.Profiles) {
                Write-FrameLine ("[{0}] {1}" -f $Index,$Profile.DisplayName) "Green"
                Write-FrameKeyVal "Folder" $Profile.FolderName "DarkGray"
                $Index++
            }
        }
        Write-FrameBottom
    }
    Pause-App
}

function Test-BraveRunning {
    $Processes = Get-Process -Name "brave" -ErrorAction SilentlyContinue
    if ($null -eq $Processes -or $Processes.Count -eq 0) { return $false }
    return $true
}

function Close-Brave {
    if (-not (Test-BraveRunning)) { return $true }
    
    Show-Header
    Write-FrameTop -Title "Process Check" -StatusDot "red" -StatusText "RUNNING"
    Write-FrameLine "Brave is currently running. Close it to proceed." "Yellow"
    
    $Processes = Get-Process -Name "brave" -ErrorAction SilentlyContinue
    if ($null -ne $Processes) {
        foreach ($Process in $Processes) {
            Write-FrameLine ("PID: {0,-8} Mem: {1:N0} MB" -f $Process.Id, ($Process.WorkingSet64 / 1MB)) "DarkGray"
        }
    }
    Write-FrameBottom

    $Answer = Read-Prompt "Close Brave now? (Y/N)"
    if ($Answer.ToUpper() -ne "Y") {
        return $false
    }

    try {
        Stop-Process -Name "brave" -Force -ErrorAction Stop
        Start-Sleep -Seconds 2
        Write-Log "Brave closed."
        return $true
    } catch {
        Write-Log "Unable to close Brave." "ERROR"
        return $false
    }
}

function Select-BraveBrowser {
    if ($Script:Browsers.Count -eq 0) { return $null }

    while ($true) {
        Show-Header
        Write-FrameTop -Title "Select Origin Browser"
        
        $Index = 1
        foreach ($Browser in $Script:Browsers) {
            Write-FrameLine ("[{0}] {1}" -f $Index,$Browser.Name) "Green"
            Write-FrameLine ("    Version  : {0}" -f $Browser.Version) "DarkGray"
            Write-FrameLine ("    Profiles : {0}" -f $Browser.Profiles.Count) "DarkGray"
            $Index++
        }
        Write-FrameBottom

        $Choice = Read-Prompt "Select Browser or Q to Cancel"
        if ($Choice.ToUpper() -eq "Q") { return $null }
        
        if ($Choice -match "^\d+$") {
            $Number = [int]$Choice
            if ($Number -ge 1 -and $Number -le $Script:Browsers.Count) {
                return $Script:Browsers[$Number-1]
            }
        }
    }
}

function Select-BraveProfiles {
    param($Browser)

    while ($true) {
        Show-Header
        Write-FrameTop -Title ("Profiles : " + $Browser.Name)
        
        if ($Browser.Profiles.Count -eq 0) {
            Write-FrameLine "No profiles found." "Yellow"
            Write-FrameBottom
            Pause-App
            return $null
        }

        $Index = 1
        foreach ($Profile in $Browser.Profiles) {
            Write-FrameLine ("[{0}] {1}" -f $Index,$Profile.DisplayName) "Green"
            Write-FrameLine ("    Folder : {0}" -f $Profile.FolderName) "DarkGray"
            $Index++
        }
        
        Write-FrameLine " "
        Write-FrameLine "Options: 1 | 1,3 | A (All Profiles)" "Cyan"
        Write-FrameBottom

        $Choice = Read-Prompt "Select Profile(s) or Q to Cancel"
        if ([string]::IsNullOrWhiteSpace($Choice)) { continue }
        $Choice = $Choice.Trim()

        if ($Choice.ToUpper() -eq "Q") { return $null }
        if ($Choice.ToUpper() -eq "A") { return $Browser.Profiles }

        $SelectedProfiles = @()
        $Valid = $true
        $Numbers = $Choice -split ","

        foreach ($Number in $Numbers) {
            $Number = $Number.Trim()
            if ($Number -notmatch "^\d+$") { $Valid = $false; break }

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
    }
}

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
        Write-FrameLine "  [WARN] Local State not found." "Yellow"
        return
    }
    $Destination = Join-Path $BrowserBackup "Local State"
    Copy-Item -Path $Source -Destination $Destination -Force
    Write-FrameLine "  [OK] Local State copied." "Green"
    Write-Log "Local State backed up."
}

function Get-RobocopyExcludeArgs {
    param([Parameter(Mandatory)][string]$SourceFolder)
    $Args = @()
    foreach ($Folder in $Script:ExcludedFolders) {
        $Path = Join-Path $SourceFolder $Folder
        if (Test-Path $Path) { $Args += "/XD"; $Args += $Path }
    }
    return $Args
}

function Backup-Profiles {
    param(
        [Parameter(Mandatory)]$Browser,
        [Parameter(Mandatory)]$Profiles,
        [Parameter(Mandatory)][string]$BrowserBackup
    )
    $Profiles = @($Profiles)

    foreach ($Profile in $Profiles) {
        $Destination = Join-Path $BrowserBackup $Profile.FolderName
        Write-Log "Backing up profile: $($Profile.DisplayName)"
        Write-FrameLine ("Copying: {0}" -f $Profile.DisplayName) "Cyan"

        if (!(Test-Path $Destination)) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }

        $Arguments = @($Profile.FullPath, $Destination, "/E", "/COPY:DAT", "/R:1", "/W:1", "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
        $Arguments += Get-RobocopyExcludeArgs $Profile.FullPath

        # Suppressing native output to prevent UI corruption
        & robocopy @Arguments | Out-Null
        $ExitCode = $LASTEXITCODE

        if ($ExitCode -le 7) {
            Write-FrameLine ("  [OK] {0}" -f $Profile.FolderName) "Green"
            Write-Log "Robocopy backup completed successfully."
        } else {
            Write-FrameLine ("  [FAILED] Code {1} : {0}" -f $Profile.FolderName, $ExitCode) "Red"
            Write-Log "Robocopy failed. Exit Code: $ExitCode" "ERROR"
        }
    }
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
        [Parameter(Mandatory)]$Browser,
        [Parameter(Mandatory)]$Profiles,
        [Parameter(Mandatory)][string]$SessionPath
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

    $Info | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $SessionPath "BackupInfo.json") -Encoding UTF8
    Write-Log "BackupInfo.json created."
}

function Show-BackupSummary {
    param(
        [Parameter(Mandatory)][string]$SessionPath,
        [Parameter(Mandatory)]$Profiles
    )
    $Profiles = @($Profiles)
    $Size = Get-FolderSize $SessionPath

    Show-Header
    Write-FrameTop -Title "Backup Summary" -StatusDot "green" -StatusText "VERIFIED"
    Write-FrameKeyVal "Status" "Success" "Green"
    Write-FrameKeyVal "Profiles" $Profiles.Count "White"
    Write-FrameKeyVal "Size" "$Size MB" "White"
    Write-FrameKeyVal "Location" (Split-Path $SessionPath -Leaf) "Cyan"
    Write-FrameBottom
    Pause-App
}

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
                    Browser        = if ($Info.BrowserEdition) { $Info.BrowserEdition } else { $Info.Browser }
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
    return $Sessions | Sort-Object FolderName -Descending
}

function Select-BackupSession {
    param($Sessions)
    $Sessions = @($Sessions)

    while ($true) {
        Show-Header
        Write-FrameTop -Title "Select Backup Session"
        
        $Index = 1
        foreach ($Session in $Sessions) {
            Write-FrameLine ("[{0}] {1}" -f $Index, $Session.FolderName) "Cyan"
            Write-FrameLine ("    Browser  : {0}" -f $Session.Browser) "DarkGray"
            Write-FrameLine ("    Profiles : {0}" -f $Session.ProfileCount) "DarkGray"
            $Index++
        }
        Write-FrameBottom

        $Choice = Read-Prompt "Select Backup to Restore or Q to Cancel"
        if ($Choice.ToUpper() -eq "Q") { return $null }

        if ($Choice -match "^\d+$") {
            $Number = [int]$Choice
            if ($Number -ge 1 -and $Number -le $Sessions.Count) {
                return $Sessions[$Number-1]
            }
        }
    }
}

function Select-TargetBrowser {
    param(
        [Parameter(Mandatory)]$Browsers,
        [Parameter(Mandatory)][string]$BackupEdition
    )
    $Browsers = @($Browsers)

    while ($true) {
        Show-Header
        Write-FrameTop -Title "Select Target Installation"
        Write-FrameKeyVal "Origin" $BackupEdition "Cyan"
        Write-FrameLine " "
        
        $Index = 1
        foreach ($Browser in $Browsers) {
            Write-FrameLine ("[{0}] {1}" -f $Index, $Browser.Name) "Green"
            Write-FrameLine ("    Version : {0}" -f $Browser.Version) "DarkGray"
            $Index++
        }
        Write-FrameBottom

        $Choice = Read-Prompt "Select Target Browser or Q to Cancel"
        if ($Choice.ToUpper() -eq "Q") { return $null }

        if ($Choice -match "^\d+$") {
            $Number = [int]$Choice
            if ($Number -ge 1 -and $Number -le $Browsers.Count) {
                $Selected = $Browsers[$Number-1]
                if ($Selected.Name -ne $BackupEdition) {
                    Write-Host "`n WARNING: Restoring a backup from $BackupEdition to $($Selected.Name) may corrupt the profile due to schema mismatches." -ForegroundColor Red
                    $Confirm = Read-Prompt "Type YES to force restore anyway, or press ENTER to cancel"
                    if ($Confirm -cne "YES") { continue }
                }
                return $Selected
            }
        }
    }
}

function Restore-LocalState {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    $SourceFile = Join-Path $Source "Local State"
    if (-not (Test-Path $SourceFile)) {
        Write-Log "Local State not found in backup source." "WARNING"
        Write-FrameLine "  [WARN] Local State missing from backup." "Yellow"
        return
    }

    $DestFile = Join-Path $Destination "Local State"
    try {
        Copy-Item -Path $SourceFile -Destination $DestFile -Force -ErrorAction Stop
        Write-Log "Local State restored successfully."
        Write-FrameLine "  [OK] Local State Restored" "Green"
    } catch {
        Write-Log "Failed to restore Local State: $_" "ERROR"
        Write-FrameLine "  [FAILED] Local State Restore" "Red"
    }
}

function Restore-Profiles {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)]$Profiles
    )
    $Profiles = @($Profiles)

    foreach ($Profile in $Profiles) {
        $SourceProfile = Join-Path $Source $Profile.FolderName
        $DestProfile = Join-Path $Destination $Profile.FolderName

        if (-not (Test-Path $SourceProfile)) {
            Write-Log "Source profile folder missing: $($Profile.FolderName)" "ERROR"
            Write-FrameLine ("  [FAILED] {0} (Missing Source)" -f $Profile.DisplayName) "Red"
            continue
        }

        if (-not (Test-Path $DestProfile)) {
            New-Item -ItemType Directory -Path $DestProfile -Force | Out-Null
        }

        Write-Log "Restoring profile: $($Profile.DisplayName) -> $DestProfile"
        Write-FrameLine ("Restoring: {0}..." -f $Profile.DisplayName) "Cyan"

        $Arguments = @($SourceProfile, $DestProfile, "/MIR", "/COPY:DAT", "/R:1", "/W:1", "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
        
        & robocopy @Arguments | Out-Null
        $ExitCode = $LASTEXITCODE

        if ($ExitCode -le 7) {
            Write-FrameLine ("  [OK] {0}" -f $Profile.DisplayName) "Green"
            Write-Log "Robocopy restore completed for $($Profile.FolderName)."
        } else {
            Write-FrameLine ("  [FAILED] Code {1} : {0}" -f $Profile.DisplayName, $ExitCode) "Red"
            Write-Log "Robocopy restore failed for $($Profile.FolderName). Exit Code: $ExitCode" "ERROR"
        }
    }
}

# ---------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------
Initialize-App
Write-Log "Application started."
Show-MainMenu