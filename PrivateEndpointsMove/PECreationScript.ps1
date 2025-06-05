# Variables - customize these before running
$unique_id = "evanba"                  # Unique identifier for the storage accounts
$resource_group = "RGPEMovePESide"           # Resource group for private endpoints
$vnet_name = "myVnet"                         # VNet for private endpoints
$subnet_name = "private-endpoints-subnet"     # Subnet for private endpoints
$location = "eastus"                          # Location for resources
$target_subscription = "7f8d0493-273d-48e6-8b6c-e49971119f62" # Subscription for private endpoints
$source_subscription = "7f8d0493-273d-48e6-8b6c-e49971119f62" # Subscription where storage accounts exist
$links_to_create = 15                          # Number of cross-subscription private endpoints to create

# Login and set subscriptions
#az login

# Loop through storage accounts and create private endpoints
for ($i = 1; $i -le $links_to_create; $i++) {
    if ($i -le 9) {
        $sa = "$($unique_id)mystorageacct0$($i)"
    } else {
        $sa = "($unique_id)mystorageacct$($i)"
    }

    Write-Host "Processing storage account: $sa"

    # Get storage account resource ID from source subscription
    $storage_id = az storage account show `
        --name $sa `
        --subscription $source_subscription `
        --query id -o tsv

    # Create private endpoint in target subscription
    az account set --subscription $target_subscription

    $peName = "$($sa)-pe"
    $peExists = az network private-endpoint show `
        --name $peName `
        --resource-group $resource_group `
        --subscription $target_subscription `
        --query "name" -o tsv 2>$null

    if ($peExists) {
        Write-Host "Private endpoint $peName already exists. Skipping creation."
        Exit-PSSession
    }

    az network private-endpoint create `
        --name $peName  `
        --resource-group $resource_group `
        --vnet-name $vnet_name `
        --subnet $subnet_name `
        --private-connection-resource-id $storage_id `
        --group-id "blob" `
        --connection-name "$($sa)-pe-conn" `
        --location $location

    # Optionally, approve the connection if required
}