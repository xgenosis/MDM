# Remove-ISE.ps1
# Intune Platform Script – Removes PowerShell ISE and logs to C:\ProgramData\IntuneLogs\
# CREATED BY: Kain Harris
# DATE: 24/09/2025

$ErrorActionPreference = 'Stop'

# --- Logging setup ---
$LogRoot = 'C:\ProgramData\IntuneLogs'
$null = New-Item -Path $LogRoot -ItemType Directory -Force -ErrorAction SilentlyContinue
$LogFile = Join-Path $LogRoot 'Remove-ISE.log'
$Transcript = Join-Path $LogRoot 'Remove-ISE-Transcript.log'

function Write-Log {
    param([Parameter(Mandatory=$true)][string]$Message)
    $timestamp = Get-Date -Format o
    "$timestamp $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

# Start transcript (also appended so you have a rolling record)
try { Start-Transcript -Path $Transcript -Append -ErrorAction SilentlyContinue } catch {}

# --- Optional event log source (nice to have) ---
$EvtLog = 'Application'
$EvtSrc = 'Intune-ISE-Removal'
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($EvtSrc)) {
        New-EventLog -LogName $EvtLog -Source $EvtSrc -ErrorAction SilentlyContinue
    }
} catch {}

function Write-Event($msg, [System.Diagnostics.EventLogEntryType]$type = [System.Diagnostics.EventLogEntryType]::Information) {
    try { Write-EventLog -LogName $EvtLog -Source $EvtSrc -EntryType $type -EventId 1000 -Message $msg } catch {}
}

# --- Helper: try DISM fallback if the cmdlet path fails ---
function Invoke-DismRemoveCapability {
    param([Parameter(Mandatory=$true)][string]$CapabilityName)
    Write-Log "Attempting DISM removal for capability: $CapabilityName"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$env:SystemRoot\System32\Dism.exe"
    $psi.Arguments = "/Online /Remove-Capability /CapabilityName:$CapabilityName /Quiet /NoRestart"
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()
    Write-Log "DISM exit code: $($proc.ExitCode)"
    return $proc.ExitCode
}

# --- Main ---
try {
    Write-Log "=== Starting PowerShell ISE removal ==="
    $cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'Microsoft.Windows.PowerShell.ISE*' }

    if (-not $cap) {
        Write-Log "ISE capability not found on this OS; nothing to do."
        Write-Event "ISE capability not found; nothing to remove."
        exit 0
    }

    Write-Log "Detected capability: $($cap.Name)  State: $($cap.State)"

    if ($cap.State -ne 'Installed') {
        Write-Log "ISE is already not installed (State=$($cap.State)). No action required."
        Write-Event "ISE already not present (State=$($cap.State))."
        exit 0
    }

    # Try with the cmdlet first
    try {
        Write-Log "Removing ISE via Remove-WindowsCapability..."
        $null = Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop
    } catch {
        Write-Log "Remove-WindowsCapability error: $($_.Exception.Message)"
        Write-Log "Falling back to DISM..."
        $dismCode = Invoke-DismRemoveCapability -CapabilityName $cap.Name
        if ($dismCode -ne 0 -and $dismCode -ne 3010) {
            throw "DISM failed with exit code $dismCode"
        }
    }

    Start-Sleep -Seconds 3
    $post = Get-WindowsCapability -Online | Where-Object { $_.Name -eq $cap.Name }
    Write-Log "Post-removal state: $($post.State)"

    if ($post.State -eq 'NotPresent' -or $post.State -eq 'Removed') {
        Write-Log "ISE removal successful."
        Write-Event "PowerShell ISE removed successfully."
        # If a reboot is flagged, we still exit 0; Intune will track reboot policy separately.
        exit 0
    } elseif ($post.State -eq 'Installed') {
        Write-Log "ISE still Installed after removal attempts."
        Write-Event "ISE removal failed – still Installed." ([System.Diagnostics.EventLogEntryType]::Error)
        exit 1
    } else {
        Write-Log "Unexpected state after removal: $($post.State)"
        Write-Event "ISE removal uncertain – state $($post.State)." ([System.Diagnostics.EventLogEntryType]::Warning)
        exit 2
    }
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)"
    Write-Event "ISE removal fatal error: $($_.Exception.Message)" ([System.Diagnostics.EventLogEntryType]::Error)
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
