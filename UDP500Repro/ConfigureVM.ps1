param(
    [Parameter(Mandatory=$true)]
    [int]$Port
)

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Creating UDPListener directory... "
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

    Write-Host "Locating downloaded TCPListener.ps1 script..."
    $tcpListenerScriptPath = Get-ChildItem -Path 'C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension' `
        -Recurse `
        -Filter 'TCPListener.ps1' `
        -ErrorAction SilentlyContinue | 
        Select-Object -First 1 -ExpandProperty FullName

    if ($tcpListenerScriptPath) {
        Write-Host "Found script at: $tcpListenerScriptPath"
        Write-Host "Copying to C:\UDPListener..."
        Copy-Item $tcpListenerScriptPath -Destination 'C:\UDPListener\TCPListener.ps1' -Force
    }
    else {
        Write-Host "Warning: TCPListener.ps1 not found in extension directory" -ForegroundColor Yellow
    }

    Write-Host "Locating downloaded TCPSender.ps1 script..."
    $tcpSenderScriptPath = Get-ChildItem -Path 'C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension' `
        -Recurse `
        -Filter 'TCPSender.ps1' `
        -ErrorAction SilentlyContinue | 
        Select-Object -First 1 -ExpandProperty FullName

    if ($tcpSenderScriptPath) {
        Write-Host "Found script at: $tcpSenderScriptPath"
        Write-Host "Copying to C:\UDPListener..."
        Copy-Item $tcpSenderScriptPath -Destination 'C:\UDPListener\TCPSender.ps1' -Force
    }
    else {
        Write-Host "Warning: TCPSender.ps1 not found in extension directory" -ForegroundColor Yellow
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

    # Install winget using asheroto script
    Write-Host "Installing winget..."
    try {
        irm asheroto.com/winget | iex
        Write-Host "winget installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to install winget: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Install Windows Terminal
    Write-Host "Installing Windows Terminal..."
    try {
        $wingetPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
        if (Test-Path $wingetPath) {
            & $wingetPath install --id Microsoft.WindowsTerminal --silent --accept-package-agreements --accept-source-agreements
            Write-Host "Windows Terminal installed successfully." -ForegroundColor Green
        }
        else {
            Write-Host "winget not available, skipping Windows Terminal installation." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Failed to install Windows Terminal: $($_.Exception.Message)" -ForegroundColor Yellow
    }

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