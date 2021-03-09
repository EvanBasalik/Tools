$resourceGroupName = "rgAppGW"
$applicationGateway = "test1"
$VNET = "AppGWvnet"
$newSubnet = "test2"

#authentication
$Context = Get-AzContext
if ($Context -eq $null)
{
    Write-Error "Please authenticate to Azure using Login-AzAccount cmdlet and then run this script"
    exit
}

#stop the Application Gateway
$appgw=Get-AzApplicationGateway -Name $applicationGateway -ResourceGroupName $resourceGroupName
Stop-AzApplicationGateway -ApplicationGateway $appgw

#repoint the Application Gateway to another subnet
$vnet=Get-AzVirtualNetwork -Name $VNET -ResourceGroupName $resourceGroupName
$newSubnet=Get-AzVirtualNetworkSubnetConfig -Name $newSubnet -VirtualNetwork $VNET
Set-AzApplicationGatewayIPConfiguration -ApplicationGateway $appgw -Name appGatewayIpConfig -Subnet $newSubnet
Set-AzApplicationGateway -ApplicationGateway $appgw

#restart the Application Gateway
Start-AzApplicationGateway -ApplicationGateway $appgw 
