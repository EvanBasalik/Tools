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
        [string]$Color = "White",
        [int]$Iteration = 0,
        [string]$EventType = "Info",
        [string]$RemoteIP = "",
        [int]$RemotePort = 0,
        [int]$BytesSent = 0
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    
    # Write to console with color
    $consoleMessage = "[$timestamp] "
    if ($Iteration -gt 0) {
        $consoleMessage += "[#$Iteration] "
    }
    $consoleMessage += $Message
    Write-Host $consoleMessage -ForegroundColor $Color
    
    # Write to log file in CSV format
    $logEntry = [PSCustomObject]@{
        Timestamp = $timestamp
        Iteration = $Iteration
        EventType = $EventType
        RemoteIP = $RemoteIP
        RemotePort = $RemotePort
        BytesSent = $BytesSent
        Message = $Message
    }
    $logEntry | Export-Csv -Path $LogFile -Append -NoTypeInformation
}

# Initialize log file with CSV header
$logEntry = [PSCustomObject]@{
    Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff")
    Iteration = 0
    EventType = "SessionStart"
    RemoteIP = $TargetIP
    RemotePort = $Port
    BytesSent = 0
    Message = "Session started - Message: $Message"
}
$logEntry | Export-Csv -Path $LogFile -NoTypeInformation

# Validate that Continuous and Iterations are not used together
if ($Continuous -and $PSBoundParameters.ContainsKey('Iterations')) {
    Write-Log "ERROR: Cannot use -Continuous and -Iterations parameters together. Please specify only one." -Color "Red" -EventType "Error"
    exit 1
}

# Determine iteration count
$iterationCount = 1
if ($Continuous) {
    $iterationCount = [int]::MaxValue
    Write-Log "Running continuously. Press Ctrl+C to stop." -Color "Yellow" -EventType "Info"
}
elseif ($PSBoundParameters.ContainsKey('Iterations')) {
    $iterationCount = $Iterations
    Write-Log "Running for $Iterations iteration(s)." -Color "Yellow" -EventType "Info"
}

Write-Log "Log file: $LogFile" -Color "Cyan" -EventType "Info"

# Create UDP client
$udpClient = New-Object System.Net.Sockets.UdpClient

try {
    for ($i = 1; $i -le $iterationCount; $i++) {
        # Convert message to bytes
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($Message)
        
        # Send the UDP packet
        $bytesSent = $udpClient.Send($bytes, $bytes.Length, $TargetIP, $Port)
        
        Write-Log "Sent $bytesSent bytes to $TargetIP`:$Port" -Iteration $i -EventType "Sent" -RemoteIP $TargetIP -RemotePort $Port -BytesSent $bytesSent
        
        # Wait for response with timeout
        $udpClient.Client.ReceiveTimeout = 2000  # 2 second timeout
        
        try {
            $remoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            $responseBytes = $udpClient.Receive([ref]$remoteEndpoint)
            $responseData = [System.Text.Encoding]::ASCII.GetString($responseBytes)
            
            Write-Log "Response received: $responseData" -Color "Green" -Iteration $i -EventType "Response" -RemoteIP $remoteEndpoint.Address -RemotePort $remoteEndpoint.Port -BytesSent $responseBytes.Length
        }
        catch [System.Net.Sockets.SocketException] {
            Write-Log "No response received (timeout)" -Color "Yellow" -Iteration $i -EventType "Timeout"
        }
        
        # Small delay between iterations (except for last one)
        if ($i -lt $iterationCount) {
            Start-Sleep -Milliseconds 1000
        }
    }
}
catch {
    Write-Log "ERROR: Failed to send UDP packet: $_" -Color "Red" -EventType "Error"
}
finally {
    # Clean up
    $udpClient.Close()
    Write-Log "UDP client closed. Session ended." -Color "Cyan" -EventType "SessionEnd"
}