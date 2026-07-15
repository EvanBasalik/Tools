#Requires -Modules Az.Compute, Az.Accounts

param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$VmName,

    [string]$LogPath = 'C:\GuestSignal\flow-count-trigger.log',
    [string]$CursorPath = (Join-Path $env:TEMP 'GuestSignal-flow.cursor.json'),
    [int]$TailLines = 200,
    [int]$PollSeconds = 30,
    [switch]$ResetCursor,
    [switch]$ShowHeartbeat,
    [int]$RunCommandBusyMaxRetries = 6,
    [int]$RunCommandBusyRetrySeconds = 10
)

$ErrorActionPreference = 'Stop'

function Get-Cursor {
    if (-not (Test-Path -LiteralPath $CursorPath)) {
        $nowUtc = [DateTime]::UtcNow
        @{ LastSeenUtc = $nowUtc.ToString('o') } |
            ConvertTo-Json |
            Set-Content -LiteralPath $CursorPath -NoNewline
        return $nowUtc
    }

    try {
        return [datetime]::Parse((Get-Content -LiteralPath $CursorPath -Raw | ConvertFrom-Json).LastSeenUtc).ToUniversalTime()
    } catch {
        $nowUtc = [DateTime]::UtcNow
        @{ LastSeenUtc = $nowUtc.ToString('o') } |
            ConvertTo-Json |
            Set-Content -LiteralPath $CursorPath -NoNewline
        return $nowUtc
    }
}

function Set-Cursor {
    param([datetime]$ValueUtc)

    @{ LastSeenUtc = $ValueUtc.ToString('o') } |
        ConvertTo-Json |
        Set-Content -LiteralPath $CursorPath -NoNewline
}

function Get-VmLogTail {
    $script = "Get-Content -Path '$LogPath' -Tail $TailLines -ErrorAction SilentlyContinue"
    for ($attempt = 1; $attempt -le $RunCommandBusyMaxRetries; $attempt++) {
        try {
            $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -Name $VmName -CommandId 'RunPowerShellScript' -ScriptString $script
            return (($result.Value | ForEach-Object { $_.Message }) -join "`n")
        } catch {
            $msg = $_.Exception.Message
            if ($msg -match 'execution is in progress|409|Conflict') {
                if ($attempt -lt $RunCommandBusyMaxRetries) {
                    if ($ShowHeartbeat) {
                        Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] RunCommand busy; retrying in $RunCommandBusyRetrySeconds s (attempt $attempt/$RunCommandBusyMaxRetries)..." -ForegroundColor DarkYellow
                    }
                    Start-Sleep -Seconds $RunCommandBusyRetrySeconds
                    continue
                }
            }
            throw
        }
    }
}

function Write-NewLogLines {
    param(
        [string]$Text,
        [datetime]$SinceUtc
    )

    $latestUtc = $SinceUtc
    $newCount = 0
    $newLines = @()
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^\[(?<ts>[^\]]+)\]') {
            try {
                $tsUtc = [datetime]::Parse($Matches.ts).ToUniversalTime()
            } catch {
                continue
            }

            if ($tsUtc -gt $SinceUtc) {
                $newLines += $line
                $newCount++
                if ($tsUtc -gt $latestUtc) {
                    $latestUtc = $tsUtc
                }
            }
        }
    }

    return [pscustomobject]@{
        LatestUtc = $latestUtc
        NewCount  = $newCount
        Lines     = $newLines
    }
}

Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

$lastSeenUtc = Get-Cursor
if ($ResetCursor) {
    $lastSeenUtc = [DateTime]::UtcNow
    Set-Cursor -ValueUtc $lastSeenUtc
}

Write-Host "Monitoring ${VmName}:$LogPath (cursor: $CursorPath)" -ForegroundColor Cyan
if ($ResetCursor) {
    Write-Host "Cursor reset to $($lastSeenUtc.ToString('o'))" -ForegroundColor Yellow
}

while ($true) {
    try {
        $tail = Get-VmLogTail
        $result = Write-NewLogLines -Text $tail -SinceUtc $lastSeenUtc
        foreach ($line in $result.Lines) {
            Write-Host $line
        }
        if ($result.LatestUtc -gt $lastSeenUtc) {
            $lastSeenUtc = $result.LatestUtc
            Set-Cursor -ValueUtc $lastSeenUtc
        } elseif ($ShowHeartbeat) {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] No new log lines. Last seen: $($lastSeenUtc.ToString('o'))" -ForegroundColor DarkGray
        }
    } catch {
        Write-Warning "Log poll failed: $_"
    }

    Start-Sleep -Seconds $PollSeconds
}
