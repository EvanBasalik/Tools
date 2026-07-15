#Requires -Modules Az.Compute, Az.Monitor

<#
.SYNOPSIS
    Local watchdog that monitors the VM's outbound flow count signal.
    When a signal is detected, it treats that as proof the guest has
    finished its work and it is safe to reboot the VM.

.PARAMETER ResourceGroupName
    Resource group containing the VM.

.PARAMETER VmName
    Name of the VM to monitor.

.PARAMETER SubscriptionId
    Azure subscription ID. If omitted, uses the current Az context.

.PARAMETER TimeoutMinutes
    How long to wait before warning that no completion signal has been seen yet. Default: 10.

.PARAMETER FlowThreshold
    Minimum outbound flow count that counts as a valid signal. Default: 300.

.PARAMETER PollIntervalSeconds
    How often to check the metric. Default: 60.

.PARAMETER PostSignalWaitMinutes
    How long to wait after a signal before rebooting. Default: 5.

.PARAMETER MetricLagGraceMinutes
    Additional advisory wait time used only for no-signal reporting.
    Signal absence no longer triggers a reboot. Default: 5.

.PARAMETER MaxConsecutiveErrors
    Number of consecutive metric poll failures before logging an elevated warning. Default: 5.
#>

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$VmName,

    [string]$SubscriptionId,

    [int]$TimeoutMinutes = 10,
    [int]$FlowThreshold = 300,
    [int]$PollIntervalSeconds = 60,
    [int]$PostSignalWaitMinutes = 5,
    [int]$MetricLagGraceMinutes = 5,
    [int]$MaxConsecutiveErrors = 5,
    [switch]$DryRunReboot
)

$ErrorActionPreference = 'Stop'

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}

function Get-NextMinuteBoundaryUtc {
    $nowUtc = (Get-Date).ToUniversalTime()
    return [datetime]::new(
        $nowUtc.Year,
        $nowUtc.Month,
        $nowUtc.Day,
        $nowUtc.Hour,
        $nowUtc.Minute,
        0,
        [System.DateTimeKind]::Utc
    ).AddMinutes(1)
}

function Get-CurrentMinuteBoundaryUtc {
    $nowUtc = (Get-Date).ToUniversalTime()
    return [datetime]::new(
        $nowUtc.Year,
        $nowUtc.Month,
        $nowUtc.Day,
        $nowUtc.Hour,
        $nowUtc.Minute,
        0,
        [System.DateTimeKind]::Utc
    )
}

function Get-LatestFlowRate {
    param(
        [string]$VmResourceId,
        [datetime]$MonitorStartTimeUtc
    )

    $endTime = Get-CurrentMinuteBoundaryUtc
    $startTime = $MonitorStartTimeUtc

    if ($startTime -ge $endTime) {
        return 0
    }

    $metric = Get-AzMetric `
        -ResourceId $VmResourceId `
        -MetricName "Outbound Flows" `
        -MetricNamespace "Microsoft.Compute/virtualMachines" `
        -StartTime $startTime `
        -EndTime $endTime `
        -TimeGrain 00:01:00 `
        -AggregationType Maximum

    $maxValue = ($metric.Data | Where-Object { $null -ne $_.Maximum } |
        Measure-Object -Property Maximum -Maximum).Maximum

    return [double]($maxValue ?? 0)
}

function Start-FlowCountTriggerOnVm {
    param([string]$ResourceGroupName, [string]$VmName)

    Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] Deploying flow count trigger script to VM..." -ForegroundColor Cyan

    $flowCountTriggerScript = Get-Content -Path (Join-Path $PSScriptRoot "Start-FlowCountTrigger.ps1") -Raw
    $encodedFlowCountTriggerScript = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($flowCountTriggerScript))
    $script = @"
`$scriptPath = 'C:\GuestSignal\Start-FlowCountTrigger.ps1'
`$logPath = 'C:\GuestSignal\flow-count-trigger.log'
New-Item -ItemType Directory -Path 'C:\GuestSignal' -Force | Out-Null
[System.IO.File]::WriteAllText(`$scriptPath, [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$encodedFlowCountTriggerScript')), [System.Text.Encoding]::Unicode)
if (Get-ScheduledTask -TaskName 'GuestSignalFlowCountTrigger' -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName 'GuestSignalFlowCountTrigger' -Confirm:`$false
}
`$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File ""C:\GuestSignal\Start-FlowCountTrigger.ps1"" -MinIntervalMinutes 2 -MaxIntervalMinutes 4 -FlowsPerSecond 200 -DurationSeconds 60 -TargetHost 168.63.129.16 -Port 53 -LogPath ""C:\GuestSignal\flow-count-trigger.log""'
`$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName 'GuestSignalFlowCountTrigger' -Action `$action -Trigger `$trigger -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName 'GuestSignalFlowCountTrigger'
Start-Sleep -Seconds 5
Get-ScheduledTask -TaskName 'GuestSignalFlowCountTrigger' | Select-Object TaskName, State
Get-Content -Path `$logPath -Tail 10 -ErrorAction SilentlyContinue
"@

    Invoke-AzVMRunCommand `
        -ResourceGroupName $ResourceGroupName `
        -VMName $VmName `
        -CommandId "RunPowerShellScript" `
        -ScriptString $script | Out-Null

    Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] Flow count trigger script deployed." -ForegroundColor Green
}

function Restart-AndRecover {
    param(
        [string]$ResourceGroupName,
        [string]$VmName,
        [switch]$DryRunReboot
    )

    Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] Reboot approved for VM '$VmName' because the completion signal was observed." -ForegroundColor Yellow

    if ($DryRunReboot) {
        Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] DRY RUN: would reboot VM '$VmName' but skipping the actual restart." -ForegroundColor Yellow
        return
    }

    Restart-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName | Out-Null

    Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] VM reboot initiated. Waiting for VM to be ready..." -ForegroundColor Yellow

    # Wait for VM to report running
    $maxWait = 300  # 5 minutes max
    $elapsed = 0
    do {
        Start-Sleep -Seconds 15
        $elapsed += 15
        $status = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName -Status).Statuses |
            Where-Object { $_.Code -like "PowerState/*" }
        Write-Host "  VM state: $($status.DisplayStatus) ($elapsed`s elapsed)"
    } while ($status.Code -ne "PowerState/running" -and $elapsed -lt $maxWait)

    if ($status.Code -ne "PowerState/running") {
        Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] VM did not come back within $maxWait seconds." -ForegroundColor Red
        return
    }

    # Give the OS a moment to fully boot
    Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] VM is running. Waiting 60s for OS to stabilize..." -ForegroundColor Cyan
    Start-Sleep -Seconds 60

    # Re-deploy the flow count trigger
    Start-FlowCountTriggerOnVm -ResourceGroupName $ResourceGroupName -VmName $VmName
}

# ─────────────────────────────────────────────────────────────────────────────
# Resolve and cache VM resource ID (avoids Get-AzVM on every poll cycle)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Resolving VM resource ID..." -ForegroundColor Cyan
$vmResourceId = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName).Id
Write-Host "VM ID: $vmResourceId" -ForegroundColor Cyan

# ─────────────────────────────────────────────────────────────────────────────
# Ensure VM is running before starting the watch loop
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Checking VM power state..." -ForegroundColor Cyan
$vmStatus = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName -Status).Statuses |
    Where-Object { $_.Code -like "PowerState/*" }

if ($vmStatus.Code -ne "PowerState/running") {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] VM is '$($vmStatus.DisplayStatus)'. Starting VM..." -ForegroundColor Yellow
    Start-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName | Out-Null

    $maxWait = 300
    $waited = 0
    do {
        Start-Sleep -Seconds 15
        $waited += 15
        $vmStatus = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName -Status).Statuses |
            Where-Object { $_.Code -like "PowerState/*" }
        Write-Host "  VM state: $($vmStatus.DisplayStatus) ($waited`s elapsed)"
    } while ($vmStatus.Code -ne "PowerState/running" -and $waited -lt $maxWait)

    if ($vmStatus.Code -ne "PowerState/running") {
        throw "VM '$VmName' did not reach running state within $maxWait seconds."
    }

    Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] VM is running. Waiting 60s for OS to stabilize..." -ForegroundColor Cyan
    Start-Sleep -Seconds 60
    Start-FlowCountTriggerOnVm -ResourceGroupName $ResourceGroupName -VmName $VmName
} else {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] VM is already running." -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Watch Loop
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "=== Watchdog Started ===" -ForegroundColor Green
Write-Host "VM:                  $VmName"
Write-Host "No-signal warning:   $TimeoutMinutes minutes"
Write-Host "Flow threshold:      $FlowThreshold"
Write-Host "Poll interval:       $PollIntervalSeconds seconds"
Write-Host "Post-signal wait:    $PostSignalWaitMinutes minutes before reboot"
Write-Host "Max consec. errors:  $MaxConsecutiveErrors"
Write-Host "Dry-run reboot:      $DryRunReboot"
Write-Host ""

$monitorStartTimeUtc = Get-NextMinuteBoundaryUtc
$watchStartTime = Get-Date
$consecutiveErrors = 0

while ($true) {
    try {
        if ((Get-Date).ToUniversalTime() -lt $monitorStartTimeUtc) {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] Waiting for fresh monitoring window starting at $($monitorStartTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssK'))..." -ForegroundColor Cyan
            Start-Sleep -Seconds $PollIntervalSeconds
            continue
        }

        $rate = Get-LatestFlowRate `
            -VmResourceId $vmResourceId `
            -MonitorStartTimeUtc $monitorStartTimeUtc

        $consecutiveErrors = 0  # reset on successful poll

        if ($rate -ge $FlowThreshold) {
            $signalDetectedAt = Get-Date
            Write-Host "[$($signalDetectedAt.ToString('yyyy-MM-ddTHH:mm:ssK'))] Signal detected (rate: $rate). Guest work is complete and reboot is now allowed." -ForegroundColor Green
            if ($DryRunReboot) {
                $wouldRebootAt = $signalDetectedAt.AddMinutes($PostSignalWaitMinutes)
                Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] DRY RUN: would reboot at $($wouldRebootAt.ToString('yyyy-MM-ddTHH:mm:ssK')) after the completion signal." -ForegroundColor Yellow
                $watchStartTime = Get-Date
                $monitorStartTimeUtc = Get-NextMinuteBoundaryUtc
            } else {
                Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] Waiting $PostSignalWaitMinutes minutes before rebooting..." -ForegroundColor Cyan
                Start-Sleep -Seconds ($PostSignalWaitMinutes * 60)
                Restart-AndRecover -ResourceGroupName $ResourceGroupName -VmName $VmName -DryRunReboot:$DryRunReboot
                $watchStartTime = Get-Date
                $monitorStartTimeUtc = Get-NextMinuteBoundaryUtc
            }
        } else {
            $elapsed = (Get-Date) - $watchStartTime
            $totalAdvisoryWindow = $TimeoutMinutes + $MetricLagGraceMinutes

            if ($elapsed.TotalMinutes -lt $TimeoutMinutes) {
                Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] No completion signal yet (rate: $rate). Waiting for guest work to finish before rebooting." -ForegroundColor Yellow
            } elseif ($elapsed.TotalMinutes -lt $totalAdvisoryWindow) {
                Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] Still waiting for a completion signal after $([math]::Round($elapsed.TotalMinutes, 1)) min. Reboot remains blocked until a signal is detected." -ForegroundColor DarkYellow
            } else {
                Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] Extended wait: no completion signal after $([math]::Round($elapsed.TotalMinutes, 1)) min. Continuing to wait because reboot requires a signal." -ForegroundColor DarkYellow
            }
        }
    } catch {
        $consecutiveErrors++
        Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] Error polling metric ($consecutiveErrors/$MaxConsecutiveErrors): $_" -ForegroundColor Red

        if ($consecutiveErrors -ge $MaxConsecutiveErrors) {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] $MaxConsecutiveErrors consecutive poll failures. Continuing to wait because reboot still requires a completion signal." -ForegroundColor Red
            $consecutiveErrors = 0
        }
    }

    Start-Sleep -Seconds $PollIntervalSeconds
}
