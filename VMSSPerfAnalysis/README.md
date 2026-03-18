# VMSSPerfAnalysis

Deploys a Linux VM Scale Set and runs `sysbench` on each instance via cloud-init. Each instance posts its output to a Log Analytics custom table (`SysbenchPerf_CL`).

## Files
- `VMSSPerf.bicep`: VMSS + VNet + NAT + Log Analytics deployment.
- `sysbench-report.sh`: standalone helper script for manual testing on a VM.

## Validate
```powershell
az group create -n vmssperf-test-rg -l eastus
$ssh = Get-Content "$HOME\.ssh\vmssperf_test.pub" -Raw
az deployment group validate -g vmssperf-test-rg --template-file VMSSPerfAnalysis\VMSSPerf.bicep --parameters adminSshKey="$ssh"
```

## Deploy
```powershell
$rg = 'vmssperf-rg'
az group create -n $rg -l eastus
$ssh = Get-Content "$HOME\.ssh\vmssperf_test.pub" -Raw
az deployment group create -g $rg --template-file VMSSPerfAnalysis\VMSSPerf.bicep --parameters adminSshKey="$ssh" instanceCount=10 sysbenchTime=30
```

## Query Results
```powershell
$workspaceId = az monitor log-analytics workspace show -g vmssperf-rg -n sysbench-vmss-law --query customerId -o tsv
az monitor log-analytics query -w $workspaceId --analytics-query "SysbenchPerf_CL | sort by TimeGenerated desc | take 20"
```
