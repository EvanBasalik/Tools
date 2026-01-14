param(
    [Parameter(Mandatory = $true)]
    [string]$TargetIP,
    
    [Parameter(Mandatory = $true)]
    [int]$Port,
    
    [Parameter(Mandatory = $false)]
    [string]$Message = "Test UDP packet",
    
    [Parameter(Mandatory = $false)]
    [switch]$Continuous,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Iterations
)

# Validate that Continuous and Iterations are not used together
if ($Continuous -and $PSBoundParameters.ContainsKey('Iterations')) {
    Write-Error "Cannot use -Continuous and -Iterations parameters together. Please specify only one."
    exit 1
}

# Determine iteration count
$iterationCount = 1
if ($Continuous) {
    $iterationCount = [int]::MaxValue
    Write-Host "Running continuously. Press Ctrl+C to stop." -ForegroundColor Yellow
}
elseif ($PSBoundParameters.ContainsKey('Iterations')) {
    $iterationCount = $Iterations
    Write-Host "Running for $Iterations iteration(s)." -ForegroundColor Yellow
}

# Create UDP client
$udpClient = New-Object System.Net.Sockets.UdpClient

try {
    for ($i = 1; $i -le $iterationCount; $i++) {
        # Convert message to bytes
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($Message)
        
        # Send the UDP packet
        $bytesSent = $udpClient.Send($bytes, $bytes.Length, $TargetIP, $Port)
        
        Write-Host "[$i] Sent $bytesSent bytes to $TargetIP`:$Port"
        Write-Host "    Message: $Message"
        
        # Wait for response with timeout
        $udpClient.Client.ReceiveTimeout = 2000  # 2 second timeout
        
        try {
            $remoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            $responseBytes = $udpClient.Receive([ref]$remoteEndpoint)
            $responseData = [System.Text.Encoding]::ASCII.GetString($responseBytes)
            
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            Write-Host "    [$timestamp] Response from $($remoteEndpoint.Address):$($remoteEndpoint.Port): $responseData" -ForegroundColor Green
        }
        catch [System.Net.Sockets.SocketException] {
            Write-Host "    No response received (timeout)" -ForegroundColor Yellow
        }
        
        # Small delay between iterations (except for last one)
        if ($i -lt $iterationCount) {
            Start-Sleep -Milliseconds 1000
        }
    }
}
catch {
    Write-Error "Failed to send UDP packet: $_"
}
finally {
    # Clean up
    $udpClient.Close()
}