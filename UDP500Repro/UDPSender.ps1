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
    [int]$Iterations,
    
    [Parameter(Mandatory = $false)]
    [string]$LogFile = "UDPSender_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

# Function to write to both console and log file
function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logMessage = "[$timestamp] $Message"
    
    # Write to console with color
    Write-Host $Message -ForegroundColor $Color
    
    # Write to log file
    Add-Content -Path $LogFile -Value $logMessage
}

# Initialize log file
$logHeader = @"
=== UDP Sender Log ===
Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Target: ${TargetIP}:${Port}
Message: $Message
"@
Set-Content -Path $LogFile -Value $logHeader

# Validate that Continuous and Iterations are not used together
if ($Continuous -and $PSBoundParameters.ContainsKey('Iterations')) {
    Write-Log "ERROR: Cannot use -Continuous and -Iterations parameters together. Please specify only one." "Red"
    exit 1
}

# Determine iteration count
$iterationCount = 1
if ($Continuous) {
    $iterationCount = [int]::MaxValue
    Write-Log "Running continuously. Press Ctrl+C to stop." "Yellow"
}
elseif ($PSBoundParameters.ContainsKey('Iterations')) {
    $iterationCount = $Iterations
    Write-Log "Running for $Iterations iteration(s)." "Yellow"
}

Write-Log "Log file: $LogFile" "Cyan"

# Create UDP client
$udpClient = New-Object System.Net.Sockets.UdpClient

try {
    for ($i = 1; $i -le $iterationCount; $i++) {
        # Convert message to bytes
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($Message)
        
        # Send the UDP packet
        $bytesSent = $udpClient.Send($bytes, $bytes.Length, $TargetIP, $Port)
        
        Write-Log "[$i] Sent $bytesSent bytes to $TargetIP`:$Port"
        Write-Log "    Message: $Message"
        
        # Wait for response with timeout
        $udpClient.Client.ReceiveTimeout = 2000  # 2 second timeout
        
        try {
            $remoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            $responseBytes = $udpClient.Receive([ref]$remoteEndpoint)
            $responseData = [System.Text.Encoding]::ASCII.GetString($responseBytes)
            
            Write-Log "    Response from $($remoteEndpoint.Address):$($remoteEndpoint.Port): $responseData" "Green"
        }
        catch [System.Net.Sockets.SocketException] {
            Write-Log "    No response received (timeout)" "Yellow"
        }
        
        # Small delay between iterations (except for last one)
        if ($i -lt $iterationCount) {
            Start-Sleep -Milliseconds 1000
        }
    }
}
catch {
    Write-Error "Failed to send UDP packet: $_"
}Log "ERROR: Failed to send UDP packet: $_" "Red"
finally {
    # Clean up
    $udpClient.Close()
    Write-Log "UDP client closed. Session ended." "Cyan"
}