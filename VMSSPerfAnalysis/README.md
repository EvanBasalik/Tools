# VMSSPerfAnalysis

This folder contains a Bicep template and helper script to deploy a VM Scale Set that runs `sysbench` on each instance and sends results to an Azure Log Analytics workspace.

Files:
- `VMSSPerf.bicep` - Bicep template that creates VNet, Log Analytics workspace, VMSS, and a CustomScript extension to run sysbench and post results.
- `sysbench-report.sh` - Helper script to run sysbench and post to Log Analytics (useful for manual testing).

Quick deploy example:

```powershell
# create resource group
az group create -n my-rg -l eastus

# get Log Analytics workspace key (if using an existing workspace)
az monitor log-analytics workspace get-shared-keys -g my-rg -n my-workspace

# deploy template (supply your SSH public key and the workspace key)
az deployment group create -g my-rg --template-file VMSSPerfAnalysis\VMSSPerf.bicep --parameters adminSshKey="ssh-rsa AAAA..." workspaceKey="<WORKSPACE_KEY>"
```

Validation (dry-run):

```powershell
az deployment group validate -g my-rg --template-file VMSSPerfAnalysis\VMSSPerf.bicep --parameters adminSshKey="ssh-rsa AAAA..." workspaceKey="<WORKSPACE_KEY>"
```

Log query example:

```
SysbenchPerf_CL
| sort by TimeGenerated desc
| take 50
```

Notes:
- The template passes the Log Analytics shared key in `protectedSettings` for the extension so it does not appear in deployment history.
- Costs will be incurred for VMs and Log Analytics ingestion.
