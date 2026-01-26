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
$transcriptBaseName = "TCPListener"
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

# Create firewall rule for TCP port
Write-Host "Creating firewall rule for TCP port $Port..." -ForegroundColor Cyan
try {
    New-NetFirewallRule -DisplayName "Allow TCP $Port" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $Port `
        -Action Allow `
        -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Firewall rule created successfully." -ForegroundColor Green
}
catch {
    Write-Host "Warning: Could not create firewall rule: $($_.Exception.Message)" -ForegroundColor Yellow
}

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
    
    # Create TCP listener
    $tcpListener = New-Object System.Net.Sockets.TcpListener $localEndpoint
    $tcpListener.Start()
    
    # Get local server name
    $serverName = $env:COMPUTERNAME
    
    Write-Host "TCP Listener started on $IPAddress`:$Port. Press Ctrl+C to stop." -ForegroundColor Green
    
    $packetCount = 0
    while ($continueRunning) {
        # Check if a client is pending (non-blocking check)
        if ($tcpListener.Pending()) {
            # Accept the client connection
            $client = $tcpListener.AcceptTcpClient()
            $remoteEndpoint = $client.Client.RemoteEndPoint
            
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] Client connected from $($remoteEndpoint.Address):$($remoteEndpoint.Port)" -ForegroundColor Cyan
            
            try {
                # Get network stream
                $stream = $client.GetStream()
                $stream.ReadTimeout = 5000  # 5 second timeout
                
                # Read data from client
                $buffer = New-Object byte[] 1024
                $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
                
                if ($bytesRead -gt 0) {
                    $receivedData = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $bytesRead)
                    Write-Host "Data: $receivedData" -ForegroundColor White
                    
                    # Send response with server name
                    $responseMessage = "Server: $serverName"
                    $responseBytes = [System.Text.Encoding]::ASCII.GetBytes($responseMessage)
                    $stream.Write($responseBytes, 0, $responseBytes.Length)
                    
                    Write-Host "Sent response: $responseMessage ($($responseBytes.Length) bytes)" -ForegroundColor Green
                    
                    # Check log file size every 10 packets
                    $packetCount++
                    if ($packetCount % 10 -eq 0) {
                        Test-AndRollLogFile -CurrentLogFile $transcriptFile
                    }
                }
            }
            catch {
                Write-Host "Error handling client: $($_.Exception.Message)" -ForegroundColor Red
            }
            finally {
                # Close the client connection
                if ($stream) { $stream.Close() }
                if ($client) { $client.Close() }
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
    if ($tcpListener) {
        $tcpListener.Stop()
        Write-Host "TCP Listener stopped." -ForegroundColor Yellow
    }
    Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue
    
    # Stop transcript
    Stop-Transcript
}
