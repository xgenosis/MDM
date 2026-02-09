<#
.SYNOPSIS
Removes the Copilot AppxPackage and logs results

.DESCRIPTION
Finds and removes any AppxPackage with "Copilot" in the name.
Logs output (success or failure) to C:\ProgramData\IntuneLogs\Remove-Copilot.log
Continues on error and logs all failures.
#>

# Define log folder and file
$LogFolder = "C:\ProgramData\IntuneLogs"
$LogPath   = Join-Path $LogFolder "Remove-Copilot.log"

# Ensure folder exists
if (!(Test-Path $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
}

# Start logging
"==== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Copilot Removal Script Started ====" | Out-File -FilePath $LogPath -Append

# Try to find packages
$Packages = Get-AppxPackage *Copilot* -ErrorAction SilentlyContinue

if ($Packages) {
    foreach ($pkg in $Packages) {
        "Found package: $($pkg.Name) - Attempting removal..." | Out-File -FilePath $LogPath -Append
        
        # Attempt removal, continue on error
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Continue -Verbose 4>&1 |
                ForEach-Object { $_.ToString() | Out-File -FilePath $LogPath -Append }
            
            "Completed attempt to remove: $($pkg.PackageFullName)" | Out-File -FilePath $LogPath -Append
        }
        catch {
            "Error removing $($pkg.PackageFullName): $_" | Out-File -FilePath $LogPath -Append
        }
    }
}
else {
    "No Copilot packages found." | Out-File -FilePath $LogPath -Append
}

"==== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Copilot Removal Script Finished ====" | Out-File -FilePath $LogPath -Append

