<#
.SYNOPSIS
    Flow count trigger wrapper that fires the outbound flow signal at a random interval
    between 2 and 4 minutes. Deploy this inside the VM to prove it is alive.
    If this doesn't fire in less than a configurable amount of minutes, the external watchdog will take action.
#>

param(
    [int]$MinIntervalMinutes = 2,
    [int]$MaxIntervalMinutes = 4,
    [int]$FlowsPerSecond = 200,
    [int]$DurationSeconds = 60,
    [string]$TargetHost = "168.63.129.16",
    [int]$Port = 53,
    [string]$LogPath = "C:\GuestSignal\flow-count-trigger.log"
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path -LiteralPath (Split-Path -Path $LogPath -Parent))) {
    New-Item -ItemType Directory -Path (Split-Path -Path $LogPath -Parent) -Force | Out-Null
}

function Write-Log {
    param([string]$Message)

    $line = "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] $Message"
    Write-Output $line
    Add-Content -Path $LogPath -Value $line
}

function Send-Signal {
    param(
        [int]$RatePerSecond,
        [int]$DurationSeconds,
        [string]$TargetHost,
        [int]$Port
    )

    $totalFlows = $RatePerSecond * $DurationSeconds
    Write-Log "Firing signal: $RatePerSecond UDP flows/second for $DurationSeconds seconds ($totalFlows total) to ${TargetHost}:$Port"

    for ($second = 1; $second -le $DurationSeconds; $second++) {
        $secondStart = Get-Date
        Write-Log "Starting second $second of $DurationSeconds"
        1..$RatePerSecond | ForEach-Object {
            try {
                $u = [System.Net.Sockets.UdpClient]::new()
                $payload = [byte[]](1..8)
                [void]$u.Send($payload, $payload.Length, $TargetHost, $Port)
                $u.Dispose()
            }
            catch {
                # Packet failures are fine for this flow signal.
            }
        }

        $elapsedMilliseconds = [int]((Get-Date) - $secondStart).TotalMilliseconds
        if ($elapsedMilliseconds -lt 1000 -and $second -lt $DurationSeconds) {
            Start-Sleep -Milliseconds (1000 - $elapsedMilliseconds)
        }
    }
    Write-Log "Signal sent."
}

Write-Log "=== Flow Count Trigger Started ==="
if ($PSBoundParameters.ContainsKey('MinIntervalMinutes') -and -not $PSBoundParameters.ContainsKey('MaxIntervalMinutes')) {
    $effectiveMinIntervalMinutes = $MinIntervalMinutes
    $effectiveMaxIntervalMinutes = $MinIntervalMinutes
} elseif ($PSBoundParameters.ContainsKey('MaxIntervalMinutes') -and -not $PSBoundParameters.ContainsKey('MinIntervalMinutes')) {
    $effectiveMinIntervalMinutes = $MaxIntervalMinutes
    $effectiveMaxIntervalMinutes = $MaxIntervalMinutes
} else {
    $effectiveMinIntervalMinutes = $MinIntervalMinutes
    $effectiveMaxIntervalMinutes = $MaxIntervalMinutes
}

if ($effectiveMinIntervalMinutes -gt $effectiveMaxIntervalMinutes) {
    throw "MinIntervalMinutes cannot be greater than MaxIntervalMinutes."
}

if ($effectiveMinIntervalMinutes -eq $effectiveMaxIntervalMinutes) {
    Write-Log "Interval: fixed at $effectiveMinIntervalMinutes minutes"
} else {
    Write-Log "Interval: $effectiveMinIntervalMinutes-$effectiveMaxIntervalMinutes minutes"
}
Write-Log "Target: ${TargetHost}:$Port (UDP) | Flows per second: $FlowsPerSecond | Duration: $DurationSeconds sec"
Write-Log "Log path: $LogPath"

while ($true) {
    if ($effectiveMinIntervalMinutes -eq $effectiveMaxIntervalMinutes) {
        $delayMinutes = $effectiveMinIntervalMinutes
    } else {
        $delayMinutes = Get-Random -Minimum $effectiveMinIntervalMinutes -Maximum ($effectiveMaxIntervalMinutes + 1)
    }
    $delaySeconds = $delayMinutes * 60
    $nextSignalTime = (Get-Date).AddSeconds($delaySeconds)
    Write-Log "Next signal scheduled for $($nextSignalTime.ToString('yyyy-MM-ddTHH:mm:ssK')) (in $delayMinutes minutes)."

    $remainingSeconds = $delaySeconds
    while ($remainingSeconds -gt 0) {
        $sleepSeconds = [Math]::Min(30, $remainingSeconds)
        Start-Sleep -Seconds $sleepSeconds
        $remainingSeconds -= $sleepSeconds

        if ($remainingSeconds -gt 0) {
            $remainingTime = [TimeSpan]::FromSeconds($remainingSeconds)
            $remainingStr = "{0}:{1:D2}:{2:D2}" -f [int]$remainingTime.TotalHours, $remainingTime.Minutes, $remainingTime.Seconds
            Write-Log "Next signal at $($nextSignalTime.ToString('yyyy-MM-ddTHH:mm:ssK')); time remaining: $remainingStr"
        }
    }

    Send-Signal -RatePerSecond $FlowsPerSecond -DurationSeconds $DurationSeconds -TargetHost $TargetHost -Port $Port
}
