<#
.SYNOPSIS
Retrieves the FQDN of devices and performs various actions on them.

.DESCRIPTION
This function retrieves the FQDN of devices based on their NetBIOS names, checks if they are online, updates the hosts file, tests WSMAN response, and optionally initiates a PowerShell session.

.PARAMETER Name
A single or an array of NetBIOS names.

.EXAMPLE
Get-DeviceFQDN -Name Device01

.EXAMPLE
Get-DeviceFQDN -Name Device01, Device02, Device03

.PARAMETER Session
A switch parameter to initiate a PowerShell session.

.EXAMPLE
Get-DeviceFQDN -Name Device01 -Session

.PARAMETER Clear
A switch parameter to clear the hosts file.

.EXAMPLE
Get-DeviceFQDN -Clear

.NOTES 
#>

function Get-DeviceFQDN {
    # Define parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter(Mandatory = $false)]
        [switch]$Session,

        [Parameter(Mandatory = $false)]
        [switch]$Clear
    )
    
    # Define site configuration variables
    $SiteCode = ""
    $ProviderMachineName = ""

    # Setup some characters to use in Write-Hosts
    $checkMark = [char]::ConvertFromUtf32(0x2705)
    $crossSymbol = [char]::ConvertFromUtf32(0x274C)
    $clockSymbol = [char](9203)
    
    # Clear the hosts file if specified -Clear parameter
    if ($Clear) {
        $confirmation = Read-Host "Do you want to clear the HOSTS file? (Y/N)"
        if ($confirmation -eq "Y" -or $confirmation -eq "y") {
            Write-Host $clockSymbol -ForegroundColor Yellow -NoNewline
            Write-Host " Clearing HOSTS file of all entries..."
            Clear-Content -Path "C:\Windows\System32\drivers\etc\hosts"
        }
        else {
            Write-Host "Operation canceled."
        }
    }
    
    # Check if the user has write permission to the HOSTS file
    $hostsFile = "C:\Windows\System32\drivers\etc\hosts"
    $security = Get-Acl -Path $hostsFile
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $accessRules = $security.Access | Where-Object { $_.IdentityReference -eq $currentUser -and $_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Write }
    if (-not $accessRules) {
        Write-Host $crossSymbol -ForegroundColor Red -NoNewline
        Write-Host "You do not have permission to write to the HOSTS file. To correct this, run PowerShell as an administrator and try again."
        Exit
    }
    
    # Check if the ConfigurationManager.psd1 module path exists
    $configManagerModulePath = Join-Path $ENV:SMS_ADMIN_UI_PATH "..\ConfigurationManager.psd1"
    if (-not (Test-Path -Path $configManagerModulePath -PathType Leaf)) {
        Write-Host $crossSymbol -ForegroundColor Red -NoNewline
        Write-Host "Microsoft Endpoint Configuration Manager is not installed. Please install it first."
        Exit
    }
    else {
        # Define customization options
        $initParams = @{}
        #$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
        #$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

        # Import ConfigurationManager.psd1 module if not already imported
        if ($null -eq (Get-Module ConfigurationManager)) {
            Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams
            Write-Host $checkMark -ForegroundColor Green -NoNewline
            Write-Host " Imported $configManagerModulePath."
        }
    }
    
    # Connect to the site's drive if not already connected
    if ($null -eq (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
    }
    
    # Set the current location to be the site code
    Set-Location "$($SiteCode):\" @initParams
    
    $measure = Measure-Command {
        foreach ($deviceName in $Name) {
            # Retrieve the ResourceID of the device
            $resourceId = Get-CMDevice -Name $deviceName | Select-Object -ExpandProperty ResourceID
            # Query the DNSDomain for the device
            $dnsSuffix = Get-CimInstance -ComputerName $ProviderMachineName -Namespace "root\SMS\site_$SiteCode" -Query "SELECT DNSDomain FROM SMS_G_System_NETWORK_ADAPTER_CONFIGURATION WHERE ResourceID = '$ResourceId'" | Select-Object -ExpandProperty DNSDomain
            # Construct the FQDN
            $fqdn = $deviceName + "." + $dnsSuffix
            # Test if FQDN is online or offline
            $ping = Test-Connection -ComputerName $fqdn -Count 1 -Quiet
            if ($ping) {
                Write-Host $checkMark -ForegroundColor Green -NoNewline
                Write-Host " $fqdn is online"
                # Get the IP address of the FQDN
                $ip = [System.Net.Dns]::GetHostAddresses($fqdn) | Select-Object -ExpandProperty IPAddressToString
                Write-Host $checkMark -ForegroundColor Green -NoNewline
                Write-Host " $fqdn resolves to $ip"
                # Update the hosts file with the device's IP address and NetBIOS name if not already present
                $hostsFile = "C:\Windows\System32\drivers\etc\hosts"
                if (-not (Select-String -Path $hostsFile -Pattern "$ip\s+$deviceName ")) {
                    Add-Content -Path $hostsFile -Value "$ip`t$deviceName " -ErrorAction Stop
                    Write-Host $checkMark -ForegroundColor Green -NoNewline
                    Write-Host " $ip $deviceName  added to HOSTS"
                }
                else {
                    Write-Host $crossSymbol -ForegroundColor Red -NoNewline
                    Write-Host " $ip $deviceName  already found in HOSTS, use -Clear to reset HOSTS"
                }
                # Test WSMAN response on the device
                try {
                    Test-WSMan -ComputerName $deviceName -ErrorAction Stop | Out-Null
                    Write-Host $checkMark -ForegroundColor Green -NoNewline
                    Write-Host " WSMAN is responding on $deviceName"
                }
                catch {
                    Write-Host $crossSymbol -ForegroundColor Red -NoNewline
                    Write-Host " WSMAN is not responding on $deviceName, run [WinRm /qc] on remote device first!"
                }
                # Initiate a PowerShell session if specified by the Session parameter
                if ($Session) {
                    Write-Host $clockSymbol -ForegroundColor Yellow -NoNewline
                    Write-Host " Attempting interactive session with $FQDN..."
                    Enter-PSSession -ComputerName $deviceName
                }
            }
            else {
                Write-Host $crossSymbol -ForegroundColor Red -NoNewline
                Write-Host " $fqdn is not online"
            }
        }
        Set-Location "C:\Temp"
    }
 
    # Calculate and display the time taken to run the function
    $executionTime = $measure.TotalSeconds
    $roundedTime = [math]::Round($executionTime, 0)
    Write-Host $checkMark -ForegroundColor Green -NoNewline
    Write-Host "That took $roundedTime seconds to complete."
}
