[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 65535)]
    [int]$Port,
    
    [Parameter(Mandatory = $false)]
    [string]$IPAddress = "0.0.0.0"
)

# Start transcript logging
$scriptPath = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptPath)) {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$transcriptBaseName = "UDPListener"
$transcriptFile = Join-Path $scriptPath "${transcriptBaseName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$maxLogSizeBytes = 1MB
$lastLogCheckTime = Get-Date

# Function to check and roll log file
function Test-AndRollLogFile {
    param([string]$CurrentLogFile)
    
    if (Test-Path $CurrentLogFile) {
        $fileInfo = Get-Item $CurrentLogFile
        if ($fileInfo.Length -ge $script:maxLogSizeBytes) {
            Write-Host "Log file reached $($fileInfo.Length) bytes, rolling to new file..." -ForegroundColor Yellow
            Stop-Transcript
            $script:transcriptFile = Join-Path $script:scriptPath "${script:transcriptBaseName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            Start-Transcript -Path $script:transcriptFile -Append
            Write-Host "New transcript file: $($script:transcriptFile)" -ForegroundColor Cyan
            return $true | Out-Null
        }
    }
    return $false | Out-Null
}

Start-Transcript -Path $transcriptFile -Append

Write-Host "Transcript logging to: $transcriptFile" -ForegroundColor Cyan
Write-Host "Log file will roll at $($maxLogSizeBytes / 1MB) MB" -ForegroundColor Cyan

# Setup Ctrl+C handler
$continueRunning = $true
[Console]::TreatControlCAsInput = $false
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    $continueRunning = $false
}

try {
    # Parse IP address
    $ipAddr = [System.Net.IPAddress]::Parse($IPAddress)
    $localEndpoint = New-Object System.Net.IPEndPoint($ipAddr, $Port)
    
    # Create UDP client and bind to the specified IP and port
    $udpClient = New-Object System.Net.Sockets.UdpClient $localEndpoint
    $remoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
    
    # Get local server name
    $serverName = $env:COMPUTERNAME
    
    Write-Host "UDP Listener started on $IPAddress`:$Port. Press Ctrl+C to stop." -ForegroundColor Green
    
    $packetCount = 0
    while ($continueRunning) {
        # Check if data is available (non-blocking check)
        if ($udpClient.Available -gt 0) {
            # Receive data
            $receivedBytes = $udpClient.Receive([ref]$remoteEndpoint)
            $receivedData = [System.Text.Encoding]::ASCII.GetString($receivedBytes)
            
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] Received from $($remoteEndpoint.Address):$($remoteEndpoint.Port)" -ForegroundColor Cyan
            Write-Host "Data: $receivedData" -ForegroundColor White
            
            # Send response with server name
            $responseMessage = "Server: $serverName"
            $responseBytes = [System.Text.Encoding]::ASCII.GetBytes($responseMessage)
            $bytesSent = $udpClient.Send($responseBytes, $responseBytes.Length, $remoteEndpoint)
            
            Write-Host "Sent response: $responseMessage ($bytesSent bytes)" -ForegroundColor Green
            
            # Check log file size every 10 packets
            $packetCount++
            if ($packetCount % 10 -eq 0) {
                Test-AndRollLogFile -CurrentLogFile $transcriptFile
            }
        }
        else {
            # Small sleep to prevent busy waiting
            Start-Sleep -Milliseconds 100
            
            # Also check log size periodically during idle time (every 10 seconds)
            $now = Get-Date
            if (($now - $lastLogCheckTime).TotalSeconds -ge 10) {
                Test-AndRollLogFile -CurrentLogFile $transcriptFile
                $lastLogCheckTime = $now
            }
        }
    }
}
catch {
    Write-Error "Error: $_"
    Write-Host "Exception details: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
}
finally {
    if ($udpClient) {
        $udpClient.Close()
        Write-Host "UDP Listener stopped." -ForegroundColor Yellow
    }
    Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue
    
    # Stop transcript
    Stop-Transcript
}