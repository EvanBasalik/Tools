#Requires -Modules Az.Compute, Az.Network, Az.Monitor, Az.Resources

<#
.SYNOPSIS
    Deploys an Azure VM with a metric alert on Outbound Flows Maximum Creation Rate,
    then triggers the signal from inside the guest via Custom Script Extension.

.PARAMETER ResourceGroupName
    Name of the resource group to create/use.

.PARAMETER Location
    Azure region for all resources.

.PARAMETER VmName
    Name of the VM to create.

.PARAMETER AdminUsername
    Local admin username for the VM.

.PARAMETER AdminPassword
    Local admin password for the VM (SecureString).

.PARAMETER AlertEmail
    Email address to receive alert notifications.

.PARAMETER FlowThreshold
    Outbound flow count threshold to trigger the alert. Default: 400.
#>

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$Location,

    [string]$VmName = "signal-vm",

    [string]$AdminUsername = "azureadmin",

    [Parameter(Mandatory)]
    [SecureString]$AdminPassword,

    [Parameter(Mandatory)]
    [string]$AlertEmail,

    [int]$FlowThreshold = 400
)

$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
# 1. Resource Group
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Creating resource group '$ResourceGroupName' in '$Location'..." -ForegroundColor Cyan
New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force | Out-Null

# ─────────────────────────────────────────────────────────────────────────────
# 2. Network (VNet, Subnet, Public IP, NIC)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Creating network resources..." -ForegroundColor Cyan

$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.0.0.0/24"

$nsg = New-AzNetworkSecurityGroup `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -Name "$VmName-nsg" `
    -Force

$vnet = New-AzVirtualNetwork `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -Name "$VmName-vnet" `
    -AddressPrefix "10.0.0.0/16" `
    -Subnet $subnetConfig `
    -Force

$pip = New-AzPublicIpAddress `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -Name "$VmName-pip" `
    -AllocationMethod Static `
    -Sku Standard `
    -Force

$nic = New-AzNetworkInterface `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -Name "$VmName-nic" `
    -SubnetId $vnet.Subnets[0].Id `
    -PublicIpAddressId $pip.Id `
    -NetworkSecurityGroupId $nsg.Id `
    -Force

# ─────────────────────────────────────────────────────────────────────────────
# 3. Virtual Machine
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Creating VM '$VmName'..." -ForegroundColor Cyan

$cred = New-Object System.Management.Automation.PSCredential($AdminUsername, $AdminPassword)

$vmConfig = New-AzVMConfig -VMName $VmName -VMSize "Standard_D2s_v6" |
    Set-AzVMOperatingSystem -Windows -ComputerName $VmName -Credential $cred |
    Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" `
                        -Offer "WindowsServer" `
                        -Skus "2022-datacenter-azure-edition" `
                        -Version "latest" |
    Add-AzVMNetworkInterface -Id $nic.Id |
    Set-AzVMBootDiagnostic -Disable

New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig | Out-Null

$vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName
Write-Host "VM created: $($vm.Id)" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 4. Action Group
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Creating action group..." -ForegroundColor Cyan

$emailReceiver = New-AzActionGroupEmailReceiverObject `
    -Name "AlertEmail" `
    -EmailAddress $AlertEmail `
    -UseCommonAlertSchema $true

$actionGroup = New-AzActionGroup `
    -ResourceGroupName $ResourceGroupName `
    -Name "GuestSignalActionGroup" `
    -ShortName "GuestSig" `
    -Location "global" `
    -EmailReceiver $emailReceiver

$actionGroup = Update-AzActionGroup `
    -Name "GuestSignalActionGroup" `
    -ResourceGroupName $ResourceGroupName `
    -GroupShortName "GuestSig" `
    -EmailReceiver @($emailReceiver) `
    -Enabled

Write-Host "Action group created: $($actionGroup.Id)" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 5. Metric Alert Rule
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Creating metric alert rule (threshold: $FlowThreshold)..." -ForegroundColor Cyan

$condition = New-AzMetricAlertRuleV2Criteria `
    -MetricName "Outbound Flows" `
    -MetricNamespace "Microsoft.Compute/virtualMachines" `
    -TimeAggregation Maximum `
    -Operator GreaterThan `
    -Threshold $FlowThreshold

Add-AzMetricAlertRuleV2 `
    -ResourceGroupName $ResourceGroupName `
    -Name "GuestSignal-OutboundFlowBurst" `
    -WindowSize (New-TimeSpan -Minutes 1) `
    -Frequency (New-TimeSpan -Minutes 1) `
    -TargetResourceId $vm.Id `
    -Severity 2 `
    -Description "Fires when guest triggers an outbound flow count burst (1-minute window for 2-4 minute signal cadence)" `
    -Condition $condition `
    -ActionGroupId $actionGroup.Id `
    -AutoMitigate:$true

Write-Host "Metric alert rule created." -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 6. Configure in-guest flow count trigger script + scheduled task
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Deploying flow count trigger script + scheduled task..." -ForegroundColor Cyan

$localFlowCountTriggerPath = Join-Path $PSScriptRoot "Start-FlowCountTrigger.ps1"
if (-not (Test-Path -LiteralPath $localFlowCountTriggerPath)) {
    throw "Required script not found: $localFlowCountTriggerPath"
}

$flowCountTriggerScript = Get-Content -Path $localFlowCountTriggerPath -Raw
$encodedFlowCountTriggerScript = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($flowCountTriggerScript))
$taskSetupScript = @"
`$scriptPath = 'C:\GuestSignal\Start-FlowCountTrigger.ps1'
`$logPath = 'C:\GuestSignal\flow-count-trigger.log'
New-Item -ItemType Directory -Path 'C:\GuestSignal' -Force | Out-Null
[System.IO.File]::WriteAllText(`$scriptPath, [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$encodedFlowCountTriggerScript')), [System.Text.Encoding]::Unicode)
if (Get-ScheduledTask -TaskName 'GuestSignalFlowCountTrigger' -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName 'GuestSignalFlowCountTrigger' -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName 'GuestSignalFlowCountTrigger' -Confirm:`$false
}
`$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File ""C:\GuestSignal\Start-FlowCountTrigger.ps1"" -MinIntervalMinutes 2 -MaxIntervalMinutes 4 -FlowsPerSecond 200 -DurationSeconds 60 -TargetHost 168.63.129.16 -Port 53 -LogPath ""C:\GuestSignal\flow-count-trigger.log""'
`$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName 'GuestSignalFlowCountTrigger' -Action `$action -Trigger `$trigger -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName 'GuestSignalFlowCountTrigger'
Get-ScheduledTask -TaskName 'GuestSignalFlowCountTrigger' | Select-Object TaskName, State
Get-Content -Path `$logPath -Tail 10 -ErrorAction SilentlyContinue
"@

Invoke-AzVMRunCommand `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VmName `
    -CommandId "RunPowerShellScript" `
    -ScriptString $taskSetupScript | Out-Null

Write-Host "Flow count trigger script + scheduled task configured." -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 7. Fire an immediate bootstrap signal via Custom Script Extension
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Deploying Custom Script Extension to fire bootstrap signal..." -ForegroundColor Cyan

$signalScript = @'
$target = "168.63.129.16"
$port   = 53
$flowsPerSecond = 200
$durationSeconds = 60
$payload = [byte[]](1..8)

Write-Output "Firing signal: $flowsPerSecond UDP flows/second for $durationSeconds seconds to ${target}:$port..."
for ($second = 1; $second -le $durationSeconds; $second++) {
    $secondStart = Get-Date
    1..$flowsPerSecond | ForEach-Object {
        try {
            $u = [System.Net.Sockets.UdpClient]::new()
            [void]$u.Send($payload, $payload.Length, $target, $port)
            $u.Dispose()
        } catch {
            # Packet failures are fine for this signal pattern.
        }
    }
    $elapsedMilliseconds = [int]((Get-Date) - $secondStart).TotalMilliseconds
    if ($elapsedMilliseconds -lt 1000 -and $second -lt $durationSeconds) {
        Start-Sleep -Milliseconds (1000 - $elapsedMilliseconds)
    }
}
Write-Output "Bootstrap signal sent at $(Get-Date -Format o)"
'@

$encodedSignalScript = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($signalScript))

Set-AzVMExtension `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VmName `
    -Name "FireGuestSignal" `
    -Publisher "Microsoft.Compute" `
    -ExtensionType "CustomScriptExtension" `
    -TypeHandlerVersion "1.10" `
    -Location $Location `
    -Settings @{} `
    -ProtectedSettings @{
        commandToExecute = "powershell -EncodedCommand $encodedSignalScript"
    } | Out-Null

Write-Host "`nDeployment complete." -ForegroundColor Green
Write-Host @"

Summary:
  VM:              $VmName ($Location)
  Alert:           GuestSignal-OutboundFlowBurst (Outbound Flows > $FlowThreshold)
  Action:          Email to $AlertEmail
  Guest script:    C:\GuestSignal\Start-FlowCountTrigger.ps1
  Scheduled task:  GuestSignalFlowCountTrigger (SYSTEM, AtStartup, starts immediately)
  Bootstrap CSE:   FireGuestSignal (200 outbound UDP flows/sec for 60s to 168.63.129.16:53)

The alert should fire within ~1-3 minutes of signal delivery.
"@
