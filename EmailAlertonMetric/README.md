# Email Alert on Metric (Guest Signal via Outbound Flows)

Deploys an Azure VM with a metric alert that fires when the guest OS triggers a burst of outbound TCP flows. This provides a way to send external alerts from inside a Windows guest **without** any VM-level Azure configuration (no managed identity, no agent, no extensions beyond the one-time signal script).

## Overall Flow

1. **Deploy** the VM and metric alert with `Deploy-GuestSignalVM.ps1`
2. **Start the flow count trigger** inside the VM with `Start-FlowCountTrigger.ps1` (fires signal every 2–4 min by default)
3. **Run the watchdog** locally with `RebootLoopandMonitorFlowCount.ps1` (reboots + re-deploys after the completion signal is seen)

```
┌─────────────────────────┐         ┌──────────────────────┐
│  VM (Guest)             │         │  Local / Mgmt VM     │
│                         │         │                      │
│  Start-FlowCountTrigger │──signal─▶  RebootLoopandMonitorFlowCount │
│  (fires every 2-4 min)  │         │  (polls metric API)  │
│                         │◀─reboot─│                      │
└─────────────────────────┘         └──────────────────────┘
```

## How It Works

1. A metric alert watches the VM's `Outbound Flows` platform metric
2. Inside the guest, a script sends high-rate UDP packets to `168.63.129.16:53` (an Azure fabric endpoint), ensuring traffic actually leaves the guest stack
3. These outbound packets register as outbound flows in the Azure host fabric
4. When the rate exceeds the threshold, Azure Monitor fires the alert and sends an email

## Scripts

### Deploy-GuestSignalVM.ps1

Creates the VM, networking, action group, metric alert, and fires an initial signal.

```powershell
.\Deploy-GuestSignalVM.ps1 `
    -ResourceGroupName "rg-guest-signal" `
    -Location "eastus" `
    -AdminPassword (Read-Host -AsSecureString "VM Password") `
    -AlertEmail "you@example.com"
```

### Start-FlowCountTrigger.ps1

Runs **inside the VM** (deployed via Custom Script Extension or Run Command). Wraps the outbound flow signal in a loop that fires at a random interval between 2 and 4 minutes by default. This acts as a **flow count trigger** — proving the VM is alive and responsive.

```powershell
# Deploy via Run Command:
Invoke-AzVMRunCommand -ResourceGroupName "rg-guest-signal" -VMName "signal-vm" `
    -CommandId "RunPowerShellScript" `
    -ScriptPath ".\Start-FlowCountTrigger.ps1"
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| MinIntervalMinutes | 2 | Minimum delay between signals |
| MaxIntervalMinutes | 4 | Maximum delay between signals |
| FlowsPerSecond | 200 | Outbound UDP flow attempts per second during a burst |
| DurationSeconds | 60 | Burst duration in seconds |
| TargetHost | 168.63.129.16 | Outbound destination host |
| Port | 53 | Outbound destination port |

### RebootLoopandMonitorFlowCount.ps1

Runs **locally** (on the operator's machine or a management VM). Polls the Azure Monitor metrics API for the VM's `Outbound Flows` metric. When the signal is detected, that means the guest's work is done and it is safe to reboot. The script then:

1. Waits for the configured post-signal delay
2. Reboots the VM
3. Waits for the VM to report `PowerState/running` (up to 5 minutes)
4. Waits an additional 60 seconds for the OS to stabilize
5. Re-deploys the flow count trigger script via Run Command
6. Resumes watching

If no signal is present yet, it keeps waiting and reporting that reboot is still blocked.

```powershell
.\RebootLoopandMonitorFlowCount.ps1 `
    -ResourceGroupName "rg-guest-signal" `
    -VmName "signal-vm"
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| ResourceGroupName | *(required)* | Resource group containing the VM |
| VmName | *(required)* | Name of the VM to monitor |
| TimeoutMinutes | 10 | How long without a signal before escalating the waiting message |
| FlowThreshold | 300 | Minimum outbound flow count that counts as a valid signal |
| PollIntervalSeconds | 60 | How often to check the metric |
| PostSignalWaitMinutes | 5 | How long to wait after the signal before rebooting |

### Deploy-VMMetricAlertOnly.ps1

Creates/updates only the **action group + metric alert** on top of an existing VM.

```powershell
.\Deploy-VMMetricAlertOnly.ps1 `
    -ResourceGroupName "rgMetricAlert2" `
    -VmName "vmMetricAlert" `
    -AlertEmail "you@example.com" `
    -MetricName "Outbound Flows" `
    -Threshold 400
```

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| ResourceGroupName | Yes | — | Resource group containing the existing VM |
| VmName | Yes | — | Existing VM name |
| AlertEmail | Yes | — | Email destination for the action group |
| MetricName | Yes | — | Metric to monitor |
| Threshold | Yes | — | Threshold value for the metric |
| MetricNamespace | No | Microsoft.Compute/virtualMachines | Metric namespace |
| TimeAggregation | No | Maximum | Aggregation for evaluation |
| Operator | No | GreaterThan | Comparison operator |
| AlertName | No | GuestSignal-OutboundFlowBurst | Alert rule name |
| ActionGroupName | No | GuestSignalActionGroup | Action group name |
| ActionGroupShortName | No | GuestSig | Action group short name |
| Severity | No | 2 | Alert severity |
| WindowMinutes | No | 1 | Evaluation window |
| FrequencyMinutes | No | 1 | Evaluation frequency |
| AutoMitigate | No | True | Enable auto-resolve behavior |

## Re-firing the Signal Manually

```powershell
Invoke-AzVMRunCommand -ResourceGroupName "rg-guest-signal" -VMName "signal-vm" `
    -CommandId "RunPowerShellScript" `
    -ScriptString '$target="168.63.129.16";$port=53;$pps=200;$dur=60;$payload=[byte[]](1..8);for($s=1;$s -le $dur;$s++){ $t=Get-Date;1..$pps|%{try{$u=[System.Net.Sockets.UdpClient]::new();[void]$u.Send($payload,$payload.Length,$target,$port);$u.Dispose()}catch{}};$e=[int]((Get-Date)-$t).TotalMilliseconds;if($e -lt 1000 -and $s -lt $dur){Start-Sleep -Milliseconds (1000-$e)}}'
```

## Deploy-GuestSignalVM.ps1 Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| ResourceGroupName | Yes | — | Resource group to create/use |
| Location | Yes | — | Azure region |
| VmName | No | signal-vm | VM name |
| AdminUsername | No | azureadmin | Local admin user |
| AdminPassword | Yes | — | Local admin password |
| AlertEmail | Yes | — | Email for notifications |
| FlowThreshold | No | 400 | Flow rate to trigger alert |

## Prerequisites

- Az PowerShell modules: `Az.Compute`, `Az.Network`, `Az.Monitor`, `Az.Resources`
- An Azure subscription with permissions to create VMs and alert rules
