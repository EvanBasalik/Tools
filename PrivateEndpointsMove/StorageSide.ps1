param(
    [string]$Location = "eastus",
    [string]$Prefix = "evanbamystorageacct",
    [int]$StorageAccountCount = 800,
    [string]$ResourceGroupName = "RGPEMoveStorage" 
)

# Login and select subscription as needed
$context = Get-AzContext  

if (!$context)   
{  
    Connect-AzAccount  
}   
else   
{  
    Write-Host " Already connected"  
}  
# Set-AzContext -SubscriptionId "<your-subscription-id>"

for ($i = 1; $i -le $StorageAccountCount; $i++) {
    $suffix = if ($i -lt 10) { "0$i" } else { "$i" }
    $storageAccountName = "$Prefix$suffix"

    # Check if storage account exists
    $sa = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $sa) {
        Write-Host "Creating storage account: $storageAccountName"
        New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $ResourceGroupName `
            -Location $Location -SkuName Standard_LRS -Kind StorageV2
    } else {
        Write-Host "Storage account $storageAccountName already exists. Skipping."
    }

    # Check if lock exists
    $lockName = "$storageAccountName-lock"
    $lock = Get-AzResourceLock -ResourceGroupName $ResourceGroupName `
        -ResourceName $storageAccountName -ResourceType "Microsoft.Storage/storageAccounts" -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $lockName }
    if (-not $lock) {
        Write-Host "Creating lock: $lockName"
        New-AzResourceLock -LockName $lockName -LockLevel CanNotDelete `
            -ResourceName $storageAccountName -ResourceType "Microsoft.Storage/storageAccounts" `
            -ResourceGroupName $ResourceGroupName `
            -Notes "Lock to prevent accidental deletion of storage account." `
            -Confirm:$false -Force
    } else {
        Write-Host "Lock $lockName already exists. Skipping."
    }
}
