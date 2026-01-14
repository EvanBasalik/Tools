param(
    [Parameter(Mandatory=$true)]
    [int]$Port
)

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Creating firewall rule for UDP port $Port..."
    New-NetFirewallRule -DisplayName "Allow UDP $Port" `
        -Direction Inbound `
        -Protocol UDP `
        -LocalPort $Port `
        -Action Allow `
        -ErrorAction SilentlyContinue

    Write-Host "Creating UDPListener directory..."
    New-Item -ItemType Directory -Path 'C:\UDPListener' -Force | Out-Null

    Write-Host "Getting private IP address..."
    $privateIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Ethernet*' | 
        Where-Object {$_.IPAddress -like '10.*'}).IPAddress
    
    if (-not $privateIP) {
        throw "Could not find private IP address starting with 10.*"
    }
    
    Write-Host "Private IP: $privateIP"

    Write-Host "Locating downloaded UDPListener.ps1 script..."
    $scriptPath = Get-ChildItem -Path 'C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension' `
        -Recurse `
        -Filter 'UDPListener.ps1' `
        -ErrorAction SilentlyContinue | 
        Select-Object -First 1 -ExpandProperty FullName

    if (-not $scriptPath) {
        throw "UDPListener.ps1 not found in extension directory"
    }

    Write-Host "Found script at: $scriptPath"
    Write-Host "Copying to C:\UDPListener..."
    Copy-Item $scriptPath -Destination 'C:\UDPListener\UDPListener.ps1' -Force

    Write-Host "Locating downloaded UDPSender.ps1 script..."
    $senderScriptPath = Get-ChildItem -Path 'C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension' `
        -Recurse `
        -Filter 'UDPSender.ps1' `
        -ErrorAction SilentlyContinue | 
        Select-Object -First 1 -ExpandProperty FullName

    if (-not $senderScriptPath) {
        throw "UDPSender.ps1 not found in extension directory"
    }

    Write-Host "Found script at: $senderScriptPath"
    Write-Host "Copying to C:\UDPListener..."
    Copy-Item $senderScriptPath -Destination 'C:\UDPListener\UDPSender.ps1' -Force

    Write-Host "Creating scheduled task..."
    $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\UDPListener\UDPListener.ps1 -Port $Port -IPAddress $privateIP"
    
    $trigger = New-ScheduledTaskTrigger -AtStartup
    
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
        -LogonType ServiceAccount `
        -RunLevel Highest

    Register-ScheduledTask -TaskName 'UDPListener' `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Force | Out-Null

    Write-Host "Starting UDPListener task..."
    Start-ScheduledTask -TaskName 'UDPListener'

    Write-Host "Configuration completed successfully!"
    exit 0
}
catch {
    Write-Error "Configuration failed: $_"
    Write-Error $_.Exception.Message
    Write-Error $_.ScriptStackTrace
    exit 1
}

finally {
    Write-Host "Exiting ConfigureVM script."
}