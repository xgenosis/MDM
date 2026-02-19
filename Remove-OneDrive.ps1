#Requires -Version 5.1
<#
.SYNOPSIS
    Removes Microsoft OneDrive and blocks reinstallation.

.DESCRIPTION
    Kills the OneDrive process, runs the native uninstaller, removes
    leftover files and folders, removes scheduled tasks that reinstall
    OneDrive, and applies a registry policy to block it coming back.

.OUTPUTS
    C:\ProgramData\Debloat\RemoveOneDrive.log

.NOTES
    Must be run as Administrator.
    Tested on Windows 11.
#>

If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    Write-Output "Not running as Administrator. Relaunching elevated..."
    Start-Process powershell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit
}

$ErrorActionPreference = 'SilentlyContinue'

$DebloatFolder = "C:\ProgramData\Debloat"
If (!(Test-Path $DebloatFolder)) {
    New-Item -Path $DebloatFolder -ItemType Directory | Out-Null
}

Start-Transcript -Path "C:\ProgramData\Debloat\RemoveOneDrive.log"

############################################################################################################
#                                          Kill OneDrive Process                                           #
############################################################################################################

Write-Output "Stopping OneDrive process..."
Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Write-Output "OneDrive process stopped."

############################################################################################################
#                                            Run Uninstaller                                               #
############################################################################################################

$uninstallerPath = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"

if (Test-Path $uninstallerPath) {
    Write-Output "Running OneDrive uninstaller..."
    Start-Process $uninstallerPath -ArgumentList "/uninstall" -Wait
    Write-Output "Uninstaller completed."
} else {
    Write-Output "OneDrive uninstaller not found at expected path. Skipping."
}

############################################################################################################
#                                         Remove Leftover Files                                            #
############################################################################################################

Write-Output "Removing leftover OneDrive files..."

$pathsToRemove = @(
    "$env:LOCALAPPDATA\Microsoft\OneDrive"
    "$env:PROGRAMDATA\Microsoft OneDrive"
    "$env:SYSTEMDRIVE\OneDriveTemp"
    "$env:USERPROFILE\OneDrive"
)

foreach ($path in $pathsToRemove) {
    if (Test-Path $path) {
        Write-Output "Removing: $path"
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

############################################################################################################
#                                       Remove Scheduled Tasks                                             #
############################################################################################################

Write-Output "Removing OneDrive scheduled tasks..."
Get-ScheduledTask | Where-Object { $_.TaskName -like '*OneDrive*' } | ForEach-Object {
    Write-Output "Removing task: $($_.TaskName)"
    Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

############################################################################################################
#                                      Remove Registry Run Keys                                            #
############################################################################################################

Write-Output "Removing OneDrive registry run keys..."

$runKeys = @(
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
)

foreach ($key in $runKeys) {
    $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
    if ($props.PSObject.Properties.Name -contains 'OneDrive') {
        Remove-ItemProperty -Path $key -Name 'OneDrive' -ErrorAction SilentlyContinue
        Write-Output "Removed OneDrive run key from $key"
    }
}

############################################################################################################
#                                      Block OneDrive via Policy                                           #
############################################################################################################

Write-Output "Applying registry policy to block OneDrive..."

$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
If (!(Test-Path $policyPath)) {
    New-Item -Path $policyPath -Force | Out-Null
}
Set-ItemProperty -Path $policyPath -Name "DisableFileSyncNGSC" -Value 1
Write-Output "OneDrive policy applied."

############################################################################################################
#                                               Done                                                       #
############################################################################################################

Write-Output "OneDrive removal complete."
Stop-Transcript
