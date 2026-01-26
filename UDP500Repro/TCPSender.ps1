param(
    [Parameter(Mandatory = $true)]
    [string]$TargetIP,
    
    [Parameter(Mandatory = $true)]
    [int]$Port,
    
    [Parameter(Mandatory = $false)]
    [string]$Message = "Test TCP packet",
    
    [Parameter(Mandatory = $false)]
    [switch]$Continuous,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Iterations,
    
    [Parameter(Mandatory = $false)]
    [string]$LogFile = "TCPSender_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
    
    # Check log file size and roll if necessary (1 MB = 1048576 bytes)
    if (Test-Path $LogFile) {
        $fileSize = (Get-Item $LogFile).Length
        if ($fileSize -ge 1048576) {
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($LogFile)
            $extension = [System.IO.Path]::GetExtension($LogFile)
            $directory = [System.IO.Path]::GetDirectoryName($LogFile)
            
            # If directory is empty (file has no path), use current directory
            if ([string]::IsNullOrEmpty($directory)) {
                $directory = Get-Location | Select-Object -ExpandProperty Path
            }
            
            # Remove existing timestamp from basename if present
            $baseName = $baseName -replace '_\d{8}_\d{6}$', ''
            
            $archivedLogFile = Join-Path $directory "$baseName`_$timestamp$extension"
            Move-Item -Path $LogFile -Destination $archivedLogFile -Force
            
            # Create new log file with CSV header
            $headerEntry = [PSCustomObject]@{
                Timestamp = $timestamp
                Iteration = 0
                EventType = "LogRolled"
                RemoteIP = ""
                RemotePort = 0
                BytesSent = 0
                Message = "Previous log archived to: $archivedLogFile"
            }
            $headerEntry | Export-Csv -Path $LogFile -NoTypeInformation
        }
    }
    
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

try {
    for ($i = 1; $i -le $iterationCount; $i++) {
        # Create TCP client for each iteration
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        
        try {
            # Connect to the server
            $tcpClient.Connect($TargetIP, $Port)
            
            # Get network stream
            $stream = $tcpClient.GetStream()
            
            # Convert message to bytes
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($Message)
            
            # Send the TCP packet
            $stream.Write($bytes, 0, $bytes.Length)
            
            Write-Log "Sent $($bytes.Length) bytes to $TargetIP`:$Port" -Iteration $i -EventType "Sent" -RemoteIP $TargetIP -RemotePort $Port -BytesSent $bytes.Length
            
            # Wait for response with timeout
            $stream.ReadTimeout = 2000  # 2 second timeout
            
            try {
                $buffer = New-Object byte[] 1024
                $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
                
                if ($bytesRead -gt 0) {
                    $responseData = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $bytesRead)
                    
                    Write-Log "Response received: $responseData" -Color "Green" -Iteration $i -EventType "Response" -RemoteIP $TargetIP -RemotePort $Port -BytesSent $bytesRead
                }
            }
            catch [System.IO.IOException] {
                Write-Log "No response received (timeout)" -Color "Yellow" -Iteration $i -EventType "Timeout"
            }
        }
        catch [System.Net.Sockets.SocketException] {
            Write-Log "Failed to connect to $TargetIP`:$Port - $($_.Exception.Message)" -Color "Red" -Iteration $i -EventType "Error"
        }
        finally {
            # Clean up connection
            if ($stream) { $stream.Close() }
            if ($tcpClient) { $tcpClient.Close() }
        }
        
        # Small delay between iterations (except for last one)
        if ($i -lt $iterationCount) {
            Start-Sleep -Milliseconds 1000
        }
    }
}
catch {
    Write-Log "ERROR: Failed to send TCP packet: $_" -Color "Red" -EventType "Error"
}
finally {
    Write-Log "TCP client closed. Session ended." -Color "Cyan" -EventType "SessionEnd"
}
