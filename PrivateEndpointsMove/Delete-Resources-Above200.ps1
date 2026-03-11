param(
    [string]$Prefix = "evanbamystorageacct",
    [string]$ResourceGroupName = "RGPEMoveStorage",
    [string]$TopicsResourceGroupName = "RGPEMoveStorage",
    [int]$Start = 201,
    [int]$End = 800,
    [switch]$WhatIf
)

# Ensure we're connected to Azure
$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Connect-AzAccount | Out-Null
}

# Fetch all Event Grid system topics once to avoid 600 repeated API calls
$guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
Write-Host "Fetching Event Grid system topics from resource group '$TopicsResourceGroupName'..."
$allTopics = Get-AzResource -ResourceGroupName $TopicsResourceGroupName -ResourceType "Microsoft.EventGrid/systemTopics" -ErrorAction SilentlyContinue
Write-Host "Found $($allTopics.Count) Event Grid system topic(s) total."

for ($i = $Start; $i -le $End; $i++) {
    $suffix = if ($i -lt 10) { "0$i" } else { "$i" }
    $resourceName = "$Prefix$suffix"

    # Delete Event Grid system topic(s) named as "<storageAccountName>-<guid>"
    # Use a single regex match to avoid fragile StartsWith+Substring logic
    $topicPattern = "^$([regex]::Escape($resourceName))-$guidPattern`$"
    $matchingTopics = $allTopics | Where-Object { $_.Name -match $topicPattern }
    if ($matchingTopics) {
        foreach ($topic in $matchingTopics) {
            if ($WhatIf) {
                Write-Host "Would remove Event Grid system topic: $($topic.Name)"
            } else {
                Write-Host "Removing Event Grid system topic: $($topic.Name)"
                Remove-AzResource -ResourceId $topic.ResourceId -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        Write-Host "No Event Grid system topic found for: $resourceName"
    }

    # First remove any resource lock named "$resourceName-lock" (locks prevent deletion)
    $lockName = "$resourceName-lock"
    $locks = Get-AzResourceLock -ResourceGroupName $ResourceGroupName -ResourceName $resourceName -ResourceType "Microsoft.Storage/storageAccounts" -ErrorAction SilentlyContinue
    if ($locks) {
        foreach ($lock in $locks) {
            if ($lock.Name -eq $lockName) {
                if ($WhatIf) {
                    Write-Host "Would remove lock: $lockName on $resourceName"
                } else {
                    Write-Host "Removing lock: $lockName on $resourceName"
                    Remove-AzResourceLock -LockName $lockName -ResourceGroupName $ResourceGroupName -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    # Then remove storage account if it exists
    $sa = Get-AzStorageAccount -Name $resourceName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if ($sa) {
        if ($WhatIf) {
            Write-Host "Would remove storage account: $resourceName"
        } else {
            Write-Host "Removing storage account: $resourceName"
            Remove-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $resourceName -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "Storage account not found: $resourceName"
    }
}

# Re-apply locks for the remaining storage accounts (1..Start-1) to ensure protection
for ($j = 1; $j -lt $Start; $j++) {
    $sfx = if ($j -lt 10) { "0$j" } else { "$j" }
    $existingName = "$Prefix$sfx"

    $sa = Get-AzStorageAccount -Name $existingName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if ($sa) {
        $lockName = "$existingName-lock"
        $existingLock = Get-AzResourceLock -ResourceGroupName $ResourceGroupName -ResourceName $existingName -ResourceType "Microsoft.Storage/storageAccounts" -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $lockName }
        if (-not $existingLock) {
            if ($WhatIf) {
                Write-Host "Would create lock: $lockName on $existingName"
            } else {
                Write-Host "Creating lock: $lockName on $existingName"
                New-AzResourceLock -LockName $lockName -LockLevel CanNotDelete -ResourceName $existingName -ResourceType "Microsoft.Storage/storageAccounts" -ResourceGroupName $ResourceGroupName -Notes "Lock to prevent accidental deletion of storage account." -Confirm:$false -Force -ErrorAction SilentlyContinue
            }
        } else {
            Write-Host "Lock already present: $lockName on $existingName"
        }
    } else {
        Write-Host "Skipping lock for missing storage account: $existingName"
    }
}

Write-Host "Done. Processed resources $Start through $End and ensured locks for remaining accounts 1..$($Start - 1)."
