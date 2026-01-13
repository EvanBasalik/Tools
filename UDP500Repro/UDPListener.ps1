[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 65535)]
    [int]$Port,
    
    [Parameter(Mandatory = $false)]
    [string]$IPAddress = "0.0.0.0"
)

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
        }
        else {
            # Small sleep to prevent busy waiting
            Start-Sleep -Milliseconds 100
        }
    }
}
catch {
    Write-Error "Error: $_"
}
finally {
    if ($udpClient) {
        $udpClient.Close()
        Write-Host "UDP Listener stopped." -ForegroundColor Yellow
    }
    Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue
}