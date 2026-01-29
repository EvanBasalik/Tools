param(
    [Parameter(Mandatory=$true)]
    [int]$Port
)

$ErrorActionPreference = 'Stop'
$LogFile = 'C:\UDPListener\ConfigureVM.log'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logMessage -Force
    Write-Output $logMessage
}

try {
    # Ensure log directory exists
    New-Item -ItemType Directory -Path 'C:\UDPListener' -Force | Out-Null
    
    Write-Log "Starting ConfigureVM script with Port: $Port"
    New-Item -ItemType Directory -Path 'C:\UDPListener' -Force | Out-Null

    Write-Log "Getting private IP address from primary NIC..."
    $primaryNic = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1
    
    if (-not $primaryNic) {
        throw "Could not find active network adapter"
    }
    
    Write-Log "Primary NIC: $($primaryNic.Name) (ifIndex: $($primaryNic.ifIndex))"
    
    $privateIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $primaryNic.ifIndex | 
        Where-Object {$_.IPAddress -like '10.*'}).IPAddress
    
    if (-not $privateIP) {
        throw "Could not find private IP address starting with 10.* on primary NIC"
    }
    
    Write-Log "Private IP: $privateIP"

    Write-Log "Locating downloaded UDPListener.ps1 script..."
    $scriptPath = Get-ChildItem -Path 'C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension' `
        -Recurse `
        -Filter 'UDPListener.ps1' `
        -ErrorAction SilentlyContinue | 
        Select-Object -First 1 -ExpandProperty FullName

    if (-not $scriptPath) {
        throw "UDPListener.ps1 not found in extension directory"
    }

    Write-Log "Found script at: $scriptPath"
    Write-Log "Copying to C:\UDPListener..."
    Copy-Item $scriptPath -Destination 'C:\UDPListener\UDPListener.ps1' -Force

    Write-Log "Locating downloaded UDPSender.ps1 script..."
    $senderScriptPath = Get-ChildItem -Path 'C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension' `
        -Recurse `
        -Filter 'UDPSender.ps1' `
        -ErrorAction SilentlyContinue | 
        Select-Object -First 1 -ExpandProperty FullName

    if (-not $senderScriptPath) {
        throw "UDPSender.ps1 not found in extension directory"
    }

    Write-Log "Found script at: $senderScriptPath"
    Write-Log "Copying to C:\UDPListener..."
    Copy-Item $senderScriptPath -Destination 'C:\UDPListener\UDPSender.ps1' -Force

    Write-Log "Locating downloaded TCPListener.ps1 script..."
    $tcpListenerScriptPath = Get-ChildItem -Path 'C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension' `
        -Recurse `
        -Filter 'TCPListener.ps1' `
        -ErrorAction SilentlyContinue | 
        Select-Object -First 1 -ExpandProperty FullName

    if ($tcpListenerScriptPath) {
        Write-Log "Found script at: $tcpListenerScriptPath"
        Write-Log "Copying to C:\UDPListener..."
        Copy-Item $tcpListenerScriptPath -Destination 'C:\UDPListener\TCPListener.ps1' -Force
    }
    else {
        Write-Log "Warning: TCPListener.ps1 not found in extension directory" "WARN"
    }

    Write-Log "Locating downloaded TCPSender.ps1 script..."
    $tcpSenderScriptPath = Get-ChildItem -Path 'C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension' `
        -Recurse `
        -Filter 'TCPSender.ps1' `
        -ErrorAction SilentlyContinue | 
        Select-Object -First 1 -ExpandProperty FullName

    if ($tcpSenderScriptPath) {
        Write-Log "Found script at: $tcpSenderScriptPath"
        Write-Log "Copying to C:\UDPListener..."
        Copy-Item $tcpSenderScriptPath -Destination 'C:\UDPListener\TCPSender.ps1' -Force
    }
    else {
        Write-Log "Warning: TCPSender.ps1 not found in extension directory" "WARN"
    }

    # Write-Host "Creating scheduled task for UDP Listener..."
    # $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
    #     -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\UDPListener\UDPListener.ps1 -Port $Port -IPAddress $privateIP"
    
    # $trigger = New-ScheduledTaskTrigger -AtStartup
    
    # $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
    #     -LogonType ServiceAccount `
    #     -RunLevel Highest

    # $settings = New-ScheduledTaskSettingsSet -Disabled

    # Register-ScheduledTask -TaskName 'UDPListener' `
    #     -Action $action `
    #     -Trigger $trigger `
    #     -Principal $principal `
    #     -Settings $settings `
    #     -Force | Out-Null

    # Write-Host "UDPListener task created (disabled)."

    # Write-Host "Creating scheduled task for TCP Listener..."
    # $tcpAction = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
    #     -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\UDPListener\TCPListener.ps1 -Port $Port -IPAddress $privateIP"
    
    # $tcpTrigger = New-ScheduledTaskTrigger -AtStartup
    
    # $tcpPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
    #     -LogonType ServiceAccount `
    #     -RunLevel Highest

    # $tcpSettings = New-ScheduledTaskSettingsSet -Disabled

    # Register-ScheduledTask -TaskName 'TCPListener' `
    #     -Action $tcpAction `
    #     -Trigger $tcpTrigger `
    #     -Principal $tcpPrincipal `
    #     -Settings $tcpSettings `
    #     -Force | Out-Null

    # Write-Host "TCPListener task created (disabled)."

    # Create scheduled task to install winget and Windows Terminal (delayed start)
    Write-Log "Creating scheduled task for software installation (delayed 2 minutes after startup)..."
    $installScriptContent = @'
$LogFile = "C:\UDPListener\SoftwareInstall.log"
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logMessage -Force
}

Write-Log "Starting software installation..."

# Install winget using asheroto script
Write-Log "Installing winget..."
try {
    irm asheroto.com/winget | iex
    Write-Log "winget installed successfully."
}
catch {
    Write-Log "Failed to install winget: $($_.Exception.Message)" "ERROR"
}

# Install Windows Terminal
Write-Log "Installing Windows Terminal..."
try {
    $wingetPath = "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
    $wingetExe = Get-Item $wingetPath -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    
    if (-not $wingetExe) {
        $wingetPath = "C:\Windows\System32\WindowsApps\winget.exe"
        if (Test-Path $wingetPath) {
            $wingetExe = $wingetPath
        }
    }
    
    if ($wingetExe) {
        Write-Log "Found winget at: $wingetExe"
        & $wingetExe install --id Microsoft.WindowsTerminal --silent --accept-package-agreements --accept-source-agreements
        Write-Log "Windows Terminal installed successfully."
    }
    else {
        Write-Log "winget not available, skipping Windows Terminal installation." "WARN"
    }
}
catch {
    Write-Log "Failed to install Windows Terminal: $($_.Exception.Message)" "ERROR"
}

Write-Log "Software installation completed."
'@
    
    $installScriptPath = 'C:\UDPListener\InstallSoftware.ps1'
    Set-Content -Path $installScriptPath -Value $installScriptContent -Force
    Write-Log "Created installation script at: $installScriptPath"
    
    $installAction = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File $installScriptPath"
    
    $installTrigger = New-ScheduledTaskTrigger -AtStartup
    $installTrigger.Delay = 'PT2M'  # 2 minute delay
    
    $installPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
        -LogonType ServiceAccount `
        -RunLevel Highest
    
    $installSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    
    Register-ScheduledTask -TaskName 'InstallSoftware' `
        -Action $installAction `
        -Trigger $installTrigger `
        -Principal $installPrincipal `
        -Settings $installSettings `
        -Force | Out-Null
    
    Write-Log "InstallSoftware scheduled task created with 2-minute delay."

    Write-Log "Configuration completed successfully!"
    exit 0
}
catch {
    $errorMsg = "Configuration failed: $_ | $($_.Exception.Message) | $($_.ScriptStackTrace)"
    Write-Log $errorMsg "ERROR"
    Write-Error $errorMsg
    exit 1
}

finally {
    Write-Log "Exiting ConfigureVM script."
}