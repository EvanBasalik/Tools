$sourceRGName = "rgSource"
$destinationRGName = "rgDestination"

# Set the source and destination subscription IDs
$sourceSubscriptionId = "7f8d0493-273d-48e6-8b6c-e49971119f62"
$destinationSubscriptionId = "7f8d0493-273d-48e6-8b6c-e49971119f62"

# Set the source subscription context
Set-AzContext -SubscriptionId $sourceSubscriptionId
$sourceResourceGroup = Get-AzResourceGroup -Name $sourceRGName

# Set the destination subscription context
Set-AzContext -SubscriptionId $destinationSubscriptionId
$destinationResourceGroup = Get-AzResourceGroup -Name $destinationRGName

# Switch back to source subscription for resource listing
Set-AzContext -SubscriptionId $sourceSubscriptionId

$resources = Get-AzResource -ResourceGroupName $sourceRGName

Invoke-AzResourceAction -Action validateMoveResources `
  -ResourceId $sourceResourceGroup.ResourceId `
  -Parameters @{
  resources = $resources.ResourceId;  # Wrap in an @() array if providing a single resource ID string.
  targetResourceGroup = $destinationResourceGroup.ResourceId
  } -Force

# Move the resources to the destination resource group
Move-AzResource -DestinationSubscriptionId $destinationSubscriptionId -DestinationResourceGroupName $destinationRGName -ResourceId $resources.ResourceId -Force