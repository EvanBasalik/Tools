#Requires -Modules Az.Compute, Az.Monitor

<#
.SYNOPSIS
    Creates or updates a metric alert and action group for an existing VM.

.PARAMETER ResourceGroupName
    Resource group containing the target VM.

.PARAMETER VmName
    Name of the existing target VM.

.PARAMETER AlertEmail
    Email address for alert notifications.

.PARAMETER MetricName
    Metric to monitor (for example, "Outbound Flows").

.PARAMETER Threshold
    Numeric threshold value for the metric alert.
#>

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$VmName,

    [Parameter(Mandatory)]
    [string]$AlertEmail,

    [Parameter(Mandatory)]
    [string]$MetricName,

    [Parameter(Mandatory)]
    [double]$Threshold,

    [string]$SubscriptionId,
    [string]$MetricNamespace = "Microsoft.Compute/virtualMachines",
    [ValidateSet("Maximum", "Minimum", "Average", "Total", "Count")]
    [string]$TimeAggregation = "Maximum",
    [ValidateSet("GreaterThan", "GreaterThanOrEqual", "LessThan", "LessThanOrEqual", "Equals", "NotEquals")]
    [string]$Operator = "GreaterThan",
    [string]$AlertName = "GuestSignal-OutboundFlowBurst",
    [string]$ActionGroupName = "GuestSignalActionGroup",
    [string]$ActionGroupShortName = "GuestSig",
    [int]$Severity = 2,
    [int]$WindowMinutes = 1,
    [int]$FrequencyMinutes = 1,
    [bool]$AutoMitigate = $true
)

$ErrorActionPreference = "Stop"

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}

Write-Host "Resolving VM '$VmName' in resource group '$ResourceGroupName'..." -ForegroundColor Cyan
$vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName

Write-Host "Creating/updating action group '$ActionGroupName'..." -ForegroundColor Cyan
$emailReceiver = New-AzActionGroupEmailReceiverObject `
    -Name "AlertEmail" `
    -EmailAddress $AlertEmail `
    -UseCommonAlertSchema $true

$actionGroup = Get-AzActionGroup -ResourceGroupName $ResourceGroupName -Name $ActionGroupName -ErrorAction SilentlyContinue
if ($actionGroup) {
    Update-AzActionGroup `
        -Name $ActionGroupName `
        -ResourceGroupName $ResourceGroupName `
        -GroupShortName $ActionGroupShortName `
        -EmailReceiver @($emailReceiver) `
        -Enabled | Out-Null
} else {
    New-AzActionGroup `
        -ResourceGroupName $ResourceGroupName `
        -Name $ActionGroupName `
        -ShortName $ActionGroupShortName `
        -Location "global" `
        -EmailReceiver $emailReceiver | Out-Null

    Update-AzActionGroup `
        -Name $ActionGroupName `
        -ResourceGroupName $ResourceGroupName `
        -GroupShortName $ActionGroupShortName `
        -EmailReceiver @($emailReceiver) `
        -Enabled | Out-Null
}

$actionGroup = Get-AzActionGroup -ResourceGroupName $ResourceGroupName -Name $ActionGroupName
Write-Host "Action group ready: $($actionGroup.Id)" -ForegroundColor Green

Write-Host "Creating/updating metric alert '$AlertName' on '$MetricName' ($Operator $Threshold)..." -ForegroundColor Cyan
$condition = New-AzMetricAlertRuleV2Criteria `
    -MetricName $MetricName `
    -MetricNamespace $MetricNamespace `
    -TimeAggregation $TimeAggregation `
    -Operator $Operator `
    -Threshold $Threshold

Add-AzMetricAlertRuleV2 `
    -ResourceGroupName $ResourceGroupName `
    -Name $AlertName `
    -WindowSize (New-TimeSpan -Minutes $WindowMinutes) `
    -Frequency (New-TimeSpan -Minutes $FrequencyMinutes) `
    -TargetResourceId $vm.Id `
    -Severity $Severity `
    -Description "Metric alert for VM '$VmName' on '$MetricName' ($Operator $Threshold)" `
    -Condition $condition `
    -ActionGroupId $actionGroup.Id `
    -AutoMitigate:$AutoMitigate | Out-Null

$rule = Get-AzMetricAlertRuleV2 -ResourceGroupName $ResourceGroupName -Name $AlertName

Write-Host "`nAlert deployment complete." -ForegroundColor Green
Write-Host @"
Summary:
  VM:            $VmName
  Alert rule:    $($rule.Name)
  Metric:        $MetricName
  Operator:      $Operator
  Threshold:     $Threshold
  Aggregation:   $TimeAggregation
  Window/Freq:   ${WindowMinutes}m / ${FrequencyMinutes}m
  Action group:  $ActionGroupName
  Email:         $AlertEmail
  AutoMitigate:  $($rule.AutoMitigate)
"@
