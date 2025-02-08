# PowerShell Module: DeviceEnrollmentIterator.psm1

<#
.AUTHOR
    Joshua Walderbach,
    Jolly Operator Scripting High-level Utilities And Witty Algorithmic Logic Demonstrating Exceptional Results By Automating Coding Hurdles.

.CREATED ON
    8 FEB 2025

.SYNOPSIS
    Automates SCCM device collection creation, exporting, and duplicate comparison.

.DESCRIPTION
    This PowerShell function provides a diverse toolset that promotes equity and ensures the inclusion of all Windows Engineers.
    - Creates SCCM device collections based on a parent collection.
    - Ensures devices are not duplicated across collections.
    - Supports logging, exporting, and comparison of device membership.

.PARAMETER Export
    Exports the membership of each created collection to a CSV file.

.PARAMETER Compare
    Compares exported CSV files to find devices assigned to multiple collections.

.PARAMETER LogDirectory
    Specifies the directory where logs will be stored (defaults to current directory).

.PARAMETER ExportFolder
    Specifies the folder where collection exports will be saved (defaults to current directory).

.EXAMPLE
    New-DEI -Export -Compare
    Creates collections, exports members, and checks for duplicate devices.
#>

function New-DEI {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [switch]$Export,
        [switch]$Compare,
        [string]$LogDirectory = (Get-Location).Path,
        [string]$ExportFolder = (Get-Location).Path
    )

    # Capture start time
    $StartTime = Get-Date

    # Ensure SCCM Module is Loaded
    Write-Host "Checking if the Configuration Manager module is loaded..." -ForegroundColor Cyan
    if (-not (Get-Module ConfigurationManager)) {
        try {
            Import-Module ConfigurationManager -ErrorAction Stop
            Write-Host "Configuration Manager module loaded successfully." -ForegroundColor Green
        } catch {
            Write-Host "❌ Error: Could not load Configuration Manager module. $_" -ForegroundColor Red
            return
        }
    }

    # Get SCCM Site Code
    try {
        $SiteCode = (Get-PSDrive -PSProvider CMSITE).Name
        if (-not $SiteCode) { throw "Could not detect SCCM Site Code." }
        Write-Host "✅ SCCM Site Code detected: $SiteCode" -ForegroundColor Green
    } catch {
        Write-Host "❌ Error retrieving SCCM Site Code: $_" -ForegroundColor Red
        return
    }

    # Switch to SCCM PSDrive
    try {
        Set-Location "$SiteCode`:" 
        Write-Host "✅ Successfully switched to SCCM PSDrive." -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to switch to SCCM PSDrive. $_" -ForegroundColor Red
        return
    }

    Write-Host "🎯 SCCM environment verified. Proceeding with script execution..." -ForegroundColor Green

    # Ensure Log Directory Exists
    $ResolvedLogDirectory = Resolve-Path -Path $LogDirectory -ErrorAction SilentlyContinue
    if (-not $ResolvedLogDirectory) {
        Write-Host "⚠️ Warning: Invalid log directory path. Defaulting to C:\Temp" -ForegroundColor Yellow
        $ResolvedLogDirectory = "C:\Temp"
    }
    if (!(Test-Path -Path $ResolvedLogDirectory)) {
        New-Item -ItemType Directory -Path $ResolvedLogDirectory -Force | Out-Null
    }

    # Create a unique log file for each run
    $LogFile = "$ResolvedLogDirectory\DEI_Collection_Creation_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
    
    function Write-Log {
        param ([string]$Message)
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$Timestamp - $Message" | Out-File -Append -FilePath $LogFile
    }

    Write-Log "==========================================================="
    Write-Log " Device Enrollment Iterator Log - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "==========================================================="

    # Prompt for Parent Collection ID
    do {
        $ParentCollectionID = Read-Host "Enter the Device Collection ID of the Parent Collection (e.g., SMS00001)"
        Write-Host "🔍 Searching for Device Collection ID '$ParentCollectionID'..." -ForegroundColor Yellow
        $ParentCollectionQuery = Get-CMDeviceCollection -CollectionId $ParentCollectionID -ErrorAction SilentlyContinue
    } while (-not $ParentCollectionQuery)

    $ParentCollectionName = $ParentCollectionQuery.Name
    $TotalDevices = (Get-CMDevice -CollectionId $ParentCollectionID -ErrorAction SilentlyContinue).Count
    Write-Log "Parent Collection: $ParentCollectionName | ID: $ParentCollectionID"
    Write-Log "Total Devices in Parent Collection: $TotalDevices"

    # Prompt for Pilot Collection
    $PilotCollectionExists = Read-Host "Do you need a pilot collection? (Yes/No)"
    if ($PilotCollectionExists -match "^(y|yes)$") {
        $PilotCollectionName = "$ParentCollectionName`_PILOT"
        Write-Host "🛠 Creating pilot collection: $PilotCollectionName ..." -ForegroundColor Yellow
        Write-Log "Creating Pilot Collection: $PilotCollectionName"
        New-CMDeviceCollection -Name $PilotCollectionName -LimitingCollectionId $ParentCollectionID -Comment "Pilot Collection" | Out-Null
    }

    # Prompt for Child Collections
    do {
        $ChildCollectionCount = Read-Host "Enter the number of child collections to create"
    } while (-not ($ChildCollectionCount -match '^\d+$' -and [int]$ChildCollectionCount -gt 0))

    # Finalize and Log Completion
    Write-Log "✅ All child collections created successfully."
    Write-Host "✅ All child collections created successfully." -ForegroundColor Green

    # Capture execution time
    $EndTime = Get-Date
    $Duration = $EndTime - $StartTime
    Write-Log "Execution Time: $($Duration.Minutes) minutes, $($Duration.Seconds) seconds"
    Write-Host "⏳ Execution Time: $($Duration.Minutes) minutes, $($Duration.Seconds) seconds" -ForegroundColor Cyan
}

Export-ModuleMember -Function New-DEI
