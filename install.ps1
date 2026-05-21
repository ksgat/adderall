$ErrorActionPreference = "Stop"

$AppName = "adderall"
$CommandName = "adderall"

$InstallDir = Join-Path $env:LOCALAPPDATA $AppName
$ScriptPath = Join-Path $InstallDir "$AppName.ps1"
$CommandPath = Join-Path $InstallDir "$CommandName.cmd"
$TrayScriptPath = Join-Path $InstallDir "$AppName-tray.ps1"
$TrayLaunchShortcutPath = Join-Path ([Environment]::GetFolderPath("Programs")) "adderall Tray.lnk"

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

@'
param(
    [string] $Command,
    [switch] $d,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments
)

$ErrorActionPreference = "Stop"

$SubgroupButtons = "4f971e89-eebd-4455-a8de-9e59040e7347"
$LidAction = "5ca83367-6e45-459f-a27b-476b1d01c936"
$DoNothing = 0
$Sleep = 1
$SubgroupSleep = "238c9fa8-0aad-41ed-83f4-97be242c8f20"
$StandbyIdle = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da"
$SubgroupDisplay = "7516b95f-f776-4464-8c53-06167f40cc99"
$VideoIdle = "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"
$DisplayStatePath = Join-Path $PSScriptRoot "display-state.json"
$TrayScriptPath = Join-Path $PSScriptRoot "adderall-tray.ps1"
$TrayPidPath = Join-Path $PSScriptRoot "adderall-tray.pid"
$TrayStartupShortcutPath = Join-Path ([Environment]::GetFolderPath("Startup")) "adderall Tray.lnk"
$TrayLaunchShortcutPath = Join-Path ([Environment]::GetFolderPath("Programs")) "adderall Tray.lnk"
$DefaultSleepAC = 1800
$DefaultSleepDC = 900
$DefaultDisplayAC = 900
$DefaultDisplayDC = 300

function Get-PowerSettingValue {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("AC", "DC")]
        [string] $PowerMode,

        [Parameter(Mandatory = $true)]
        [string] $Subgroup,

        [Parameter(Mandatory = $true)]
        [string] $Setting
    )

    $Query = powercfg /QH SCHEME_CURRENT $Subgroup $Setting
    $Pattern = "Current $PowerMode Power Setting Index:\s+0x([0-9a-fA-F]+)"
    $Match = $Query | Select-String -Pattern $Pattern

    if (!$Match) {
        throw "Could not read $PowerMode value for $Subgroup/$Setting."
    }

    return [Convert]::ToUInt32($Match.Matches[0].Groups[1].Value, 16)
}

function Set-PowerSettingValue {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("AC", "DC")]
        [string] $PowerMode,

        [Parameter(Mandatory = $true)]
        [string] $Subgroup,

        [Parameter(Mandatory = $true)]
        [string] $Setting,

        [Parameter(Mandatory = $true)]
        [uint32] $Value
    )

    if ($PowerMode -eq "AC") {
        powercfg /SETACVALUEINDEX SCHEME_CURRENT $Subgroup $Setting $Value | Out-Null
    }
    else {
        powercfg /SETDCVALUEINDEX SCHEME_CURRENT $Subgroup $Setting $Value | Out-Null
    }
}

function Get-RestoreValue {
    param(
        [object] $State,
        [string] $PropertyName,
        [uint32] $DefaultValue
    )

    if ($State -and $State.PSObject.Properties.Name -contains $PropertyName) {
        $Value = [uint32]$State.$PropertyName

        if ($Value -gt 0) {
            return $Value
        }
    }

    return $DefaultValue
}

function Format-Minutes {
    param([uint32] $Seconds)

    if ($Seconds -eq 0) {
        return "Never"
    }

    return "$([int]($Seconds / 60)) min"
}

function Get-LidLabel {
    param([uint32] $Value)

    switch ($Value) {
        0 { "Do nothing" }
        1 { "Sleep" }
        2 { "Hibernate" }
        3 { "Shut down" }
        default { "Unknown ($Value)" }
    }
}

function Get-DisplayState {
    return [ordered]@{
        SleepAC = Get-PowerSettingValue -PowerMode AC -Subgroup $SubgroupSleep -Setting $StandbyIdle
        SleepDC = Get-PowerSettingValue -PowerMode DC -Subgroup $SubgroupSleep -Setting $StandbyIdle
        DisplayAC = Get-PowerSettingValue -PowerMode AC -Subgroup $SubgroupDisplay -Setting $VideoIdle
        DisplayDC = Get-PowerSettingValue -PowerMode DC -Subgroup $SubgroupDisplay -Setting $VideoIdle
    }
}

function Test-DisplayDisabled {
    param([object] $State)

    return ($State.SleepAC -eq 0 -and $State.SleepDC -eq 0 -and $State.DisplayAC -eq 0 -and $State.DisplayDC -eq 0)
}

function Save-DisplayState {
    param([object] $State)

    $StoredState = [ordered]@{
        Version = 1
        EnabledAt = (Get-Date).ToString("o")
        SleepAC = $State.SleepAC
        SleepDC = $State.SleepDC
        DisplayAC = $State.DisplayAC
        DisplayDC = $State.DisplayDC
    }

    $StoredState | ConvertTo-Json | Set-Content -LiteralPath $DisplayStatePath -Encoding UTF8
}

function Set-DisplayDisabled {
    param([switch] $SaveCurrent)

    $Current = Get-DisplayState

    if ($SaveCurrent -and !(Test-DisplayDisabled -State $Current)) {
        Save-DisplayState -State $Current
    }

    Set-PowerSettingValue -PowerMode AC -Subgroup $SubgroupSleep -Setting $StandbyIdle -Value 0
    Set-PowerSettingValue -PowerMode DC -Subgroup $SubgroupSleep -Setting $StandbyIdle -Value 0
    Set-PowerSettingValue -PowerMode AC -Subgroup $SubgroupDisplay -Setting $VideoIdle -Value 0
    Set-PowerSettingValue -PowerMode DC -Subgroup $SubgroupDisplay -Setting $VideoIdle -Value 0
}

function Restore-DisplayDefaults {
    $State = $null

    if (Test-Path -LiteralPath $DisplayStatePath) {
        $State = Get-Content -LiteralPath $DisplayStatePath -Raw | ConvertFrom-Json
    }

    $RestoreSleepAC = Get-RestoreValue -State $State -PropertyName SleepAC -DefaultValue $DefaultSleepAC
    $RestoreSleepDC = Get-RestoreValue -State $State -PropertyName SleepDC -DefaultValue $DefaultSleepDC
    $RestoreDisplayAC = Get-RestoreValue -State $State -PropertyName DisplayAC -DefaultValue $DefaultDisplayAC
    $RestoreDisplayDC = Get-RestoreValue -State $State -PropertyName DisplayDC -DefaultValue $DefaultDisplayDC

    Set-PowerSettingValue -PowerMode AC -Subgroup $SubgroupSleep -Setting $StandbyIdle -Value $RestoreSleepAC
    Set-PowerSettingValue -PowerMode DC -Subgroup $SubgroupSleep -Setting $StandbyIdle -Value $RestoreSleepDC
    Set-PowerSettingValue -PowerMode AC -Subgroup $SubgroupDisplay -Setting $VideoIdle -Value $RestoreDisplayAC
    Set-PowerSettingValue -PowerMode DC -Subgroup $SubgroupDisplay -Setting $VideoIdle -Value $RestoreDisplayDC

    if (Test-Path -LiteralPath $DisplayStatePath) {
        Remove-Item -LiteralPath $DisplayStatePath -Force
    }

    return [ordered]@{
        SleepAC = $RestoreSleepAC
        SleepDC = $RestoreSleepDC
        DisplayAC = $RestoreDisplayAC
        DisplayDC = $RestoreDisplayDC
    }
}

function Set-LidAction {
    param([uint32] $Value)

    Set-PowerSettingValue -PowerMode AC -Subgroup $SubgroupButtons -Setting $LidAction -Value $Value
    Set-PowerSettingValue -PowerMode DC -Subgroup $SubgroupButtons -Setting $LidAction -Value $Value
}

function Toggle-LidAction {
    $CurrentAC = Get-PowerSettingValue -PowerMode AC -Subgroup $SubgroupButtons -Setting $LidAction
    $CurrentDC = Get-PowerSettingValue -PowerMode DC -Subgroup $SubgroupButtons -Setting $LidAction

    if ($CurrentAC -eq $DoNothing -and $CurrentDC -eq $DoNothing) {
        $NextValue = $Sleep
    }
    else {
        $NextValue = $DoNothing
    }

    Set-LidAction -Value $NextValue
    powercfg /SETACTIVE SCHEME_CURRENT | Out-Null

    Write-Host ""
    Write-Host "Lid close action set to: $(Get-LidLabel -Value $NextValue)"
    Write-Host ""
}

function Toggle-DisplayDisabled {
    $Current = Get-DisplayState

    if (Test-DisplayDisabled -State $Current) {
        $Restored = Restore-DisplayDefaults
        powercfg /SETACTIVE SCHEME_CURRENT | Out-Null

        Write-Host ""
        Write-Host "Display and time-based sleep restored."
        Write-Host "Sleep: AC $(Format-Minutes -Seconds $Restored.SleepAC), battery $(Format-Minutes -Seconds $Restored.SleepDC)."
        Write-Host "Display: AC $(Format-Minutes -Seconds $Restored.DisplayAC), battery $(Format-Minutes -Seconds $Restored.DisplayDC)."
        Write-Host ""
        return
    }

    Set-DisplayDisabled -SaveCurrent
    powercfg /SETACTIVE SCHEME_CURRENT | Out-Null

    Write-Host ""
    Write-Host "Display always on."
    Write-Host "Time-based sleep disabled."
    Write-Host "Run adderall -d again to restore display and sleep timeouts."
    Write-Host ""
}

function Show-Status {
    $LidAC = Get-PowerSettingValue -PowerMode AC -Subgroup $SubgroupButtons -Setting $LidAction
    $LidDC = Get-PowerSettingValue -PowerMode DC -Subgroup $SubgroupButtons -Setting $LidAction
    $Display = Get-DisplayState

    Write-Host ""
    Write-Host "adderall status"
    Write-Host "Lid close: AC $(Get-LidLabel -Value $LidAC), battery $(Get-LidLabel -Value $LidDC)"
    Write-Host "Sleep timeout: AC $(Format-Minutes -Seconds $Display.SleepAC), battery $(Format-Minutes -Seconds $Display.SleepDC)"
    Write-Host "Display timeout: AC $(Format-Minutes -Seconds $Display.DisplayAC), battery $(Format-Minutes -Seconds $Display.DisplayDC)"
    Write-Host "Display state saved: $(if (Test-Path -LiteralPath $DisplayStatePath) { "Yes" } else { "No" })"
    Write-Host ""
}

function Reset-Adderall {
    $Restored = Restore-DisplayDefaults
    Set-LidAction -Value $Sleep
    powercfg /SETACTIVE SCHEME_CURRENT | Out-Null

    Write-Host ""
    Write-Host "adderall reset."
    Write-Host "Lid close action set to: Sleep"
    Write-Host "Sleep: AC $(Format-Minutes -Seconds $Restored.SleepAC), battery $(Format-Minutes -Seconds $Restored.SleepDC)."
    Write-Host "Display: AC $(Format-Minutes -Seconds $Restored.DisplayAC), battery $(Format-Minutes -Seconds $Restored.DisplayDC)."
    Write-Host ""
}

function Enable-All {
    Set-LidAction -Value $DoNothing
    Set-DisplayDisabled -SaveCurrent
    powercfg /SETACTIVE SCHEME_CURRENT | Out-Null

    Write-Host ""
    Write-Host "adderall all active."
    Write-Host "Lid close action set to: Do nothing"
    Write-Host "Display always on."
    Write-Host "Time-based sleep disabled."
    Write-Host ""
}

function Get-PowerShellPath {
    $Candidate = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"

    if (Test-Path -LiteralPath $Candidate) {
        return $Candidate
    }

    return "powershell.exe"
}

function Get-TrayProcess {
    if (Test-Path -LiteralPath $TrayPidPath) {
        $RawPid = Get-Content -LiteralPath $TrayPidPath -Raw -ErrorAction SilentlyContinue
        if (![string]::IsNullOrWhiteSpace($RawPid)) {
            try {
                $ParsedPid = [int]$RawPid.Trim()
                if ($ParsedPid -gt 0) {
                    $ProcessByPid = Get-Process -Id $ParsedPid -ErrorAction SilentlyContinue
                    if ($ProcessByPid) {
                        return $ProcessByPid
                    }
                }
            }
            catch {
            }
        }
    }

    $TrayProcess = Get-CimInstance -ClassName Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($TrayScriptPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 } |
        Select-Object -First 1

    if ($TrayProcess) {
        return Get-Process -Id $TrayProcess.ProcessId -ErrorAction SilentlyContinue
    }

    return $null
}

function Remove-TrayPidFile {
    if (Test-Path -LiteralPath $TrayPidPath) {
        Remove-Item -LiteralPath $TrayPidPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-TrayStartupEnabled {
    return (Test-Path -LiteralPath $TrayStartupShortcutPath)
}

function Enable-TrayStartup {
    $PowerShellPath = Get-PowerShellPath
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($TrayStartupShortcutPath)
    $Shortcut.TargetPath = $PowerShellPath
    $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$TrayScriptPath`""
    $Shortcut.WorkingDirectory = $PSScriptRoot
    $Shortcut.IconLocation = "$PowerShellPath,0"
    $Shortcut.Description = "adderall tray"
    $Shortcut.Save()
}

function Register-TrayLaunchShortcut {
    $PowerShellPath = Get-PowerShellPath
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($TrayLaunchShortcutPath)
    $Shortcut.TargetPath = $PowerShellPath
    $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$TrayScriptPath`""
    $Shortcut.WorkingDirectory = $PSScriptRoot
    $Shortcut.IconLocation = "$PowerShellPath,0"
    $Shortcut.Description = "Launch adderall tray"
    $Shortcut.Save()
}

function Disable-TrayStartup {
    if (Test-Path -LiteralPath $TrayStartupShortcutPath) {
        Remove-Item -LiteralPath $TrayStartupShortcutPath -Force
    }
}

function Show-TrayStatus {
    $TrayProcess = Get-TrayProcess
    $Running = if ($TrayProcess) { "Yes (PID $($TrayProcess.Id))" } else { "No" }
    $Startup = if (Test-TrayStartupEnabled) { "On" } else { "Off" }
    $LaunchShortcut = if (Test-Path -LiteralPath $TrayLaunchShortcutPath) { "On" } else { "Off" }

    Write-Host ""
    Write-Host "adderall tray status"
    Write-Host "Running: $Running"
    Write-Host "Start with Windows: $Startup"
    Write-Host "Launch shortcut: $LaunchShortcut"
    Write-Host ""
}

function Start-AdderallTray {
    if (!(Test-Path -LiteralPath $TrayScriptPath)) {
        throw "Tray script not found at $TrayScriptPath."
    }

    $TrayProcess = Get-TrayProcess
    if ($TrayProcess) {
        Write-Host ""
        Write-Host "adderall tray already running (PID $($TrayProcess.Id))."
        Write-Host ""
        return
    }

    Remove-TrayPidFile

    $PowerShellPath = Get-PowerShellPath
    $ArgumentList = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$TrayScriptPath`""
    Start-Process -FilePath $PowerShellPath -ArgumentList $ArgumentList -WindowStyle Hidden
    $TrayProcess = $null
    for ($Attempt = 0; $Attempt -lt 10; $Attempt++) {
        Start-Sleep -Milliseconds 250
        $TrayProcess = Get-TrayProcess
        if ($TrayProcess) {
            break
        }
    }

    Write-Host ""
    if ($TrayProcess) {
        Write-Host "adderall tray started (PID $($TrayProcess.Id))."
    }
    else {
        Write-Host "adderall tray launch requested."
    }
    Write-Host ""
}

function Stop-AdderallTray {
    $TrayProcess = Get-TrayProcess
    if (!$TrayProcess) {
        Remove-TrayPidFile
        Write-Host ""
        Write-Host "adderall tray is not running."
        Write-Host ""
        return
    }

    Stop-Process -Id $TrayProcess.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 200
    Remove-TrayPidFile

    Write-Host ""
    Write-Host "adderall tray stopped."
    Write-Host ""
}

function Handle-TrayCommand {
    param([string[]] $ExtraArguments)

    $SubCommand = ""
    if ($ExtraArguments -and $ExtraArguments.Count -gt 0) {
        $SubCommand = $ExtraArguments[0].ToLowerInvariant()
    }

    switch ($SubCommand) {
        "" { Start-AdderallTray }
        "start" { Start-AdderallTray }
        "stop" { Stop-AdderallTray }
        "status" { Show-TrayStatus }
        "shortcut" {
            Register-TrayLaunchShortcut
            Write-Host ""
            Write-Host "adderall tray launch shortcut registered."
            Write-Host "Path: $TrayLaunchShortcutPath"
            Write-Host ""
        }
        "startup" {
            if ($ExtraArguments.Count -lt 2) {
                Write-Host ""
                Write-Host "Usage: adderall tray startup on|off"
                Write-Host ""
                return
            }

            $StartupValue = $ExtraArguments[1].ToLowerInvariant()
            switch ($StartupValue) {
                "on" {
                    Enable-TrayStartup
                    Write-Host ""
                    Write-Host "adderall tray startup enabled."
                    Write-Host ""
                }
                "off" {
                    Disable-TrayStartup
                    Write-Host ""
                    Write-Host "adderall tray startup disabled."
                    Write-Host ""
                }
                default {
                    Write-Error "Unknown tray startup value '$StartupValue'. Use: on or off."
                    exit 1
                }
            }
        }
        default {
            Write-Error "Unknown tray command '$SubCommand'. Use: adderall tray, adderall tray stop, adderall tray status, adderall tray shortcut, or adderall tray startup on|off."
            exit 1
        }
    }
}

function Uninstall-Adderall {
    Stop-AdderallTray
    Reset-Adderall

    $ProfilePath = Join-Path $HOME "Documents\WindowsPowerShell\profile.ps1"
    $BeginMarker = "# >>> adderall >>>"
    $EndMarker = "# <<< adderall <<<"

    if (Test-Path -LiteralPath $ProfilePath) {
        $ProfileContent = Get-Content -LiteralPath $ProfilePath -Raw -ErrorAction SilentlyContinue

        if ($ProfileContent -match [regex]::Escape($BeginMarker)) {
            $Pattern = "(?s)\r?\n?$([regex]::Escape($BeginMarker)).*?$([regex]::Escape($EndMarker))\r?\n?"
            $UpdatedProfileContent = [regex]::Replace($ProfileContent, $Pattern, "")
            Set-Content -LiteralPath $ProfilePath -Value $UpdatedProfileContent -Encoding UTF8
        }
    }

    $CommandPath = Join-Path $PSScriptRoot "adderall.cmd"
    if (Test-Path -LiteralPath $CommandPath) {
        Remove-Item -LiteralPath $CommandPath -Force
    }

    $TrayScriptPath = Join-Path $PSScriptRoot "adderall-tray.ps1"
    if (Test-Path -LiteralPath $TrayScriptPath) {
        Remove-Item -LiteralPath $TrayScriptPath -Force
    }

    if (Test-Path -LiteralPath $TrayStartupShortcutPath) {
        Remove-Item -LiteralPath $TrayStartupShortcutPath -Force
    }

    if (Test-Path -LiteralPath $TrayLaunchShortcutPath) {
        Remove-Item -LiteralPath $TrayLaunchShortcutPath -Force
    }

    if (Test-Path -LiteralPath $TrayPidPath) {
        Remove-Item -LiteralPath $TrayPidPath -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $DisplayStatePath) {
        Remove-Item -LiteralPath $DisplayStatePath -Force
    }

    $Self = $PSCommandPath

    Write-Host "Removed adderall profile function, command shim, and tray integration."
    Write-Host "Open a new terminal for the uninstall to take effect."

    try {
        Remove-Item -LiteralPath $Self -Force
    }
    catch {
        Write-Warning "Could not remove $Self while it is running. Delete it manually if needed."
    }
}

$NormalizedCommand = if ([string]::IsNullOrWhiteSpace($Command)) { "" } else { $Command.ToLowerInvariant() }

if ($d) {
    Toggle-DisplayDisabled
    exit 0
}

switch ($NormalizedCommand) {
    "" { Toggle-LidAction }
    "lid" { Toggle-LidAction }
    "status" { Show-Status }
    "reset" { Reset-Adderall }
    "all" { Enable-All }
    "tray" { Handle-TrayCommand -ExtraArguments $Arguments }
    "uninstall" { Uninstall-Adderall }
    default {
        Write-Error "Unknown command '$Command'. Use: adderall, adderall -d, adderall status, adderall reset, adderall all, adderall tray, or adderall uninstall."
        exit 1
    }
}
'@ | Set-Content -LiteralPath $ScriptPath -Encoding UTF8

@"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ScriptPath" %*
"@ | Set-Content -LiteralPath $CommandPath -Encoding ASCII

@'
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$MainScriptPath = Join-Path $PSScriptRoot "adderall.ps1"
$PidPath = Join-Path $PSScriptRoot "adderall-tray.pid"
$StartupShortcutPath = Join-Path ([Environment]::GetFolderPath("Startup")) "adderall Tray.lnk"
$SubgroupButtons = "4f971e89-eebd-4455-a8de-9e59040e7347"
$LidAction = "5ca83367-6e45-459f-a27b-476b1d01c936"
$DoNothing = 0
$SubgroupSleep = "238c9fa8-0aad-41ed-83f4-97be242c8f20"
$StandbyIdle = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da"
$SubgroupDisplay = "7516b95f-f776-4464-8c53-06167f40cc99"
$VideoIdle = "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"
$MutexName = "Local\adderall-tray"

function Get-PowerSettingValue {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("AC", "DC")]
        [string] $PowerMode,

        [Parameter(Mandatory = $true)]
        [string] $Subgroup,

        [Parameter(Mandatory = $true)]
        [string] $Setting
    )

    $Query = powercfg /QH SCHEME_CURRENT $Subgroup $Setting
    $Pattern = "Current $PowerMode Power Setting Index:\s+0x([0-9a-fA-F]+)"
    $Match = $Query | Select-String -Pattern $Pattern

    if (!$Match) {
        throw "Could not read $PowerMode value for $Subgroup/$Setting."
    }

    return [Convert]::ToUInt32($Match.Matches[0].Groups[1].Value, 16)
}

function Get-LidDoNothing {
    $LidAC = Get-PowerSettingValue -PowerMode AC -Subgroup $SubgroupButtons -Setting $LidAction
    $LidDC = Get-PowerSettingValue -PowerMode DC -Subgroup $SubgroupButtons -Setting $LidAction
    return ($LidAC -eq $DoNothing -and $LidDC -eq $DoNothing)
}

function Get-DisplayState {
    return [ordered]@{
        SleepAC = Get-PowerSettingValue -PowerMode AC -Subgroup $SubgroupSleep -Setting $StandbyIdle
        SleepDC = Get-PowerSettingValue -PowerMode DC -Subgroup $SubgroupSleep -Setting $StandbyIdle
        DisplayAC = Get-PowerSettingValue -PowerMode AC -Subgroup $SubgroupDisplay -Setting $VideoIdle
        DisplayDC = Get-PowerSettingValue -PowerMode DC -Subgroup $SubgroupDisplay -Setting $VideoIdle
    }
}

function Test-DisplayDisabled {
    param([object] $State)
    return ($State.SleepAC -eq 0 -and $State.SleepDC -eq 0 -and $State.DisplayAC -eq 0 -and $State.DisplayDC -eq 0)
}

function Get-PowerShellPath {
    $Candidate = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $Candidate) {
        return $Candidate
    }

    return "powershell.exe"
}

function Enable-Startup {
    $PowerShellPath = Get-PowerShellPath
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($StartupShortcutPath)
    $Shortcut.TargetPath = $PowerShellPath
    $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$PSCommandPath`""
    $Shortcut.WorkingDirectory = $PSScriptRoot
    $Shortcut.IconLocation = "$PowerShellPath,0"
    $Shortcut.Description = "adderall tray"
    $Shortcut.Save()
}

function Disable-Startup {
    if (Test-Path -LiteralPath $StartupShortcutPath) {
        Remove-Item -LiteralPath $StartupShortcutPath -Force
    }
}

function Invoke-AdderallCommand {
    param(
        [string] $Command,
        [switch] $DisplayToggle
    )

    try {
        if ($DisplayToggle) {
            & $MainScriptPath -d | Out-Null
        }
        elseif ([string]::IsNullOrWhiteSpace($Command)) {
            & $MainScriptPath | Out-Null
        }
        else {
            & $MainScriptPath -Command $Command | Out-Null
        }

        return $true
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "adderall tray", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return $false
    }
}

function Get-TrayState {
    $DisplayState = Get-DisplayState

    return [ordered]@{
        LidDoNothing = Get-LidDoNothing
        DisplayDisabled = Test-DisplayDisabled -State $DisplayState
        StartupEnabled = (Test-Path -LiteralPath $StartupShortcutPath)
    }
}

$CreatedNew = $false
$Mutex = New-Object System.Threading.Mutex($true, $MutexName, [ref]$CreatedNew)
if (!$CreatedNew) {
    exit 0
}

$NotifyIcon = $null
$ContextMenu = $null

try {
    Set-Content -LiteralPath $PidPath -Value $PID -Encoding ASCII

    $LidItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $DisplayItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $AllItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $ResetItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $StartupItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $StatusItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $ExitItem = New-Object System.Windows.Forms.ToolStripMenuItem

    $LidItem.Text = "Lid close: Do nothing"
    $DisplayItem.Text = "Display always on"
    $AllItem.Text = "Enable all"
    $ResetItem.Text = "Reset"
    $StartupItem.Text = "Start with Windows"
    $StatusItem.Text = "Status"
    $ExitItem.Text = "Exit"

    $ContextMenu = New-Object System.Windows.Forms.ContextMenuStrip
    [void]$ContextMenu.Items.Add($LidItem)
    [void]$ContextMenu.Items.Add($DisplayItem)
    [void]$ContextMenu.Items.Add($AllItem)
    [void]$ContextMenu.Items.Add($ResetItem)
    [void]$ContextMenu.Items.Add($StartupItem)
    [void]$ContextMenu.Items.Add($StatusItem)
    [void]$ContextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$ContextMenu.Items.Add($ExitItem)

    $UpdateUi = {
        try {
            $State = Get-TrayState
            $LidItem.Checked = [bool]$State.LidDoNothing
            $DisplayItem.Checked = [bool]$State.DisplayDisabled
            $StartupItem.Checked = [bool]$State.StartupEnabled
            $NotifyIcon.Text = "adderall tray"
        }
        catch {
            $NotifyIcon.Text = "adderall tray (error)"
        }
    }

    $LidItem.add_Click({
        if (Invoke-AdderallCommand -Command "lid") {
            & $UpdateUi
        }
    })

    $DisplayItem.add_Click({
        if (Invoke-AdderallCommand -DisplayToggle) {
            & $UpdateUi
        }
    })

    $AllItem.add_Click({
        if (Invoke-AdderallCommand -Command "all") {
            & $UpdateUi
        }
    })

    $ResetItem.add_Click({
        if (Invoke-AdderallCommand -Command "reset") {
            & $UpdateUi
        }
    })

    $StartupItem.add_Click({
        try {
            if (Test-Path -LiteralPath $StartupShortcutPath) {
                Disable-Startup
            }
            else {
                Enable-Startup
            }

            & $UpdateUi
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "adderall tray", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $StatusItem.add_Click({
        try {
            $DisplayState = Get-DisplayState
            $StatusLines = @(
                "Lid close action: $(if (Get-LidDoNothing) { "Do nothing" } else { "Sleep or mixed" })",
                "Display always on: $(if (Test-DisplayDisabled -State $DisplayState) { "On" } else { "Off" })",
                "Sleep timeout: AC $($DisplayState.SleepAC)s, battery $($DisplayState.SleepDC)s",
                "Display timeout: AC $($DisplayState.DisplayAC)s, battery $($DisplayState.DisplayDC)s",
                "Start with Windows: $(if (Test-Path -LiteralPath $StartupShortcutPath) { "On" } else { "Off" })"
            )
            [System.Windows.Forms.MessageBox]::Show(($StatusLines -join [Environment]::NewLine), "adderall status", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "adderall tray", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $ExitItem.add_Click({
        $NotifyIcon.Visible = $false
        [System.Windows.Forms.Application]::Exit()
    })

    $ContextMenu.add_Opening({
        & $UpdateUi
    })

    $NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $NotifyIcon.Icon = [System.Drawing.SystemIcons]::Application
    $NotifyIcon.Text = "adderall tray"
    $NotifyIcon.Visible = $true
    $NotifyIcon.ContextMenuStrip = $ContextMenu

    $RefreshTimer = New-Object System.Windows.Forms.Timer
    $RefreshTimer.Interval = 15000
    $RefreshTimer.add_Tick({
        & $UpdateUi
    })
    $RefreshTimer.Start()

    & $UpdateUi
    [System.Windows.Forms.Application]::Run()

    $RefreshTimer.Stop()
    $RefreshTimer.Dispose()
}
finally {
    if ($NotifyIcon) {
        $NotifyIcon.Visible = $false
        $NotifyIcon.Dispose()
    }

    if (Test-Path -LiteralPath $PidPath) {
        Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
    }

    if ($Mutex) {
        $Mutex.ReleaseMutex() | Out-Null
        $Mutex.Dispose()
    }
}
'@ | Set-Content -LiteralPath $TrayScriptPath -Encoding UTF8

$ProfilePath = Join-Path $HOME "Documents\WindowsPowerShell\profile.ps1"
$ProfileDir = Split-Path -Parent $ProfilePath

if (!(Test-Path -LiteralPath $ProfileDir)) {
    New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
}

if (!(Test-Path -LiteralPath $ProfilePath)) {
    New-Item -ItemType File -Force -Path $ProfilePath | Out-Null
}

$BeginMarker = "# >>> adderall >>>"
$EndMarker = "# <<< adderall <<<"
$FunctionBlock = @"
$BeginMarker
function $CommandName {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ScriptPath" @args
}
$EndMarker
"@

$ProfileContent = Get-Content -LiteralPath $ProfilePath -Raw -ErrorAction SilentlyContinue

if ([string]::IsNullOrWhiteSpace($ProfileContent)) {
    Set-Content -LiteralPath $ProfilePath -Value $FunctionBlock -Encoding UTF8
}
elseif ($ProfileContent -match [regex]::Escape($BeginMarker)) {
    $Pattern = "(?s)$([regex]::Escape($BeginMarker)).*?$([regex]::Escape($EndMarker))"
    $UpdatedProfileContent = [regex]::Replace($ProfileContent, $Pattern, $FunctionBlock)
    Set-Content -LiteralPath $ProfilePath -Value $UpdatedProfileContent -Encoding UTF8
}
else {
    Add-Content -LiteralPath $ProfilePath -Value "`r`n$FunctionBlock"
}

try {
    $PowerShellPath = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (!(Test-Path -LiteralPath $PowerShellPath)) {
        $PowerShellPath = "powershell.exe"
    }

    $WshShell = New-Object -ComObject WScript.Shell
    $TrayLaunchShortcut = $WshShell.CreateShortcut($TrayLaunchShortcutPath)
    $TrayLaunchShortcut.TargetPath = $PowerShellPath
    $TrayLaunchShortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$TrayScriptPath`""
    $TrayLaunchShortcut.WorkingDirectory = $InstallDir
    $TrayLaunchShortcut.IconLocation = "$PowerShellPath,0"
    $TrayLaunchShortcut.Description = "Launch adderall tray"
    $TrayLaunchShortcut.Save()
}
catch {
    Write-Warning "Could not register tray launch shortcut: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Installed $AppName successfully."
Write-Host ""
Write-Host "Commands:"
Write-Host "    $CommandName           Toggle lid close only (sleep/display timeouts unchanged)"
Write-Host "    $CommandName -d        Toggle display always on and time-based sleep off"
Write-Host "    $CommandName status    Show current power settings"
Write-Host "    $CommandName reset     Restore normal defaults"
Write-Host "    $CommandName all       Set lid to Do nothing and disable display/sleep timeouts"
Write-Host "    $CommandName tray      Start tray widget"
Write-Host "    $CommandName tray stop Stop tray widget"
Write-Host "    $CommandName tray status Show tray runtime status"
Write-Host "    $CommandName tray shortcut Register tray launch shortcut"
Write-Host "    $CommandName tray startup on|off  Toggle tray start with Windows"
Write-Host "    $CommandName uninstall Remove adderall"
Write-Host ""
Write-Host "Tray launch shortcut:"
Write-Host "    $TrayLaunchShortcutPath"
Write-Host ""
