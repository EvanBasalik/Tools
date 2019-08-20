#Demonstrates how to enable Azure Netwatcher for all the VMs in an Azure VM Scale Set (VMSS)
#Jointly developed by Jennifer Phuong and Evan Basalik

Azure services parameters
$rgName = "<resource group name>"
$location = "<region hosting the VMSS>"
$VMSSName = "<Underlying VMSS name>" 
$storageAccountName = "<storage account to put the packet captures>"
$VMSS = Get-AzureRmVmss -VMScaleSetName $VMSSName -ResourceGroupName $rgName

#Add Network Watcher extension to the VMSS
Add-AzureRmVmssExtension -VirtualMachineScaleSet $VMSS -Name "networkWatcherAgent" -Publisher "Microsoft.Azure.NetworkWatcher" -Type "NetworkWatcherAgentWindows" -TypeHandlerVersion "1.4" -AutoUpgradeMinorVersion $True

#Get VM from underlying VMSS
$VM1 = Get-AzureRmVmssVM -ResourceGroupName $rgName -VMScaleSetName "<name of VMSS>" -InstanceId "0"
$VM2 = Get-AzureRmVmssVM -ResourceGroupName $rgName -VMScaleSetName "<name of VMSS>" -InstanceId "1"

#Get Network Watcher Object
$nw = Get-AzureRmResource | Where-Object { $_.ResourceType -eq "Microsoft.Network/networkWatchers" -and $_.Location -eq $location } 
$networkWatcher = Get-AzureRmNetworkWatcher -Name $nw.Name -ResourceGroupName $nw.ResourceGroupName 
$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $rgName  -Name $storageAccountName

#Filters that we can tune to the solution
$filter1 = New-AzureRmPacketCaptureFilterConfig -Protocol TCP -RemoteIPAddress "1.1.1.1-255.255.255" -LocalIPAddress "10.0.0.3" -LocalPort "1-65535" -RemotePort "20;80;443"
$filter2 = New-AzureRmPacketCaptureFilterConfig -Protocol UDP 

#Run the packet capture with a unique packet capture name
$packet = New-AzureRmNetworkWatcherPacketCapture -NetworkWatcher $networkWatcher -TargetVirtualMachineId $vm2.Id -PacketCaptureName "<packet capture name>" -StorageAccountId $storageAccount.id -TimeLimitInSeconds 60 -Filter $filter1, $filter2
