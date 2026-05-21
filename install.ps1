$ErrorActionPreference = "Stop"

$AppName = "adderall"
$CommandName = "adderall"

$InstallDir = Join-Path $env:LOCALAPPDATA $AppName
$ScriptPath = Join-Path $InstallDir "$AppName.ps1"
$CommandPath = Join-Path $InstallDir "$CommandName.cmd"

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

@'
param(
    [string] $Command,
    [switch] $d
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

function Uninstall-Adderall {
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

    if (Test-Path -LiteralPath $DisplayStatePath) {
        Remove-Item -LiteralPath $DisplayStatePath -Force
    }

    $Self = $PSCommandPath

    Write-Host "Removed adderall profile function and command shim."
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
    "uninstall" { Uninstall-Adderall }
    default {
        Write-Error "Unknown command '$Command'. Use: adderall, adderall -d, adderall status, adderall reset, adderall all, or adderall uninstall."
        exit 1
    }
}
'@ | Set-Content -LiteralPath $ScriptPath -Encoding UTF8

@"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ScriptPath" %*
"@ | Set-Content -LiteralPath $CommandPath -Encoding ASCII

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

Write-Host ""
Write-Host "Installed $AppName successfully."
Write-Host ""
Write-Host "Commands:"
Write-Host "    $CommandName           Toggle lid close between Sleep and Do nothing"
Write-Host "    $CommandName -d        Toggle display always on and time-based sleep off"
Write-Host "    $CommandName status    Show current power settings"
Write-Host "    $CommandName reset     Restore normal defaults"
Write-Host "    $CommandName all       Set lid to Do nothing and disable display/sleep timeouts"
Write-Host "    $CommandName uninstall Remove adderall"
Write-Host ""
