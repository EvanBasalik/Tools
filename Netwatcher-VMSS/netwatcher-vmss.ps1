#Demonstrates how to enable Azure Netwatcher for all the VMs in an Azure VM Scale Set (VMSS)
#Jointly developed by Jennifer Phuong and Evan Basalik

#Azure services parameters
$rgName = "<resource group name>"
$location = "<region hosting the VMSS>"
$VMSSName = "<Underlying VMSS name>" 
$storageAccountName = $VMSSName + "<storage account to put the packet captures>"
$containerName = "networktraces"
$networkWatcherName = "<Network Watcher name>"

$rgName = "rgVMSSNW"
$location ="eastus"
$VMSSName = "vmssevanb"
$storageAccountName = $VMSSName + "vmsstest"
$containerName = "networktraces"
$networkWatcherName = "nw"

#Log in if necessary
if ((Get-AzContext).count-eq 0)
{
    Connect-AzAccount
}

#Validate that the Storage account exists and create if not
Write-Host "Creating/validating Storage Account $storageAccountName"
$storageAccount = Get-AzStorageAccount -ResourceGroupName $rgName | Where-Object {$_.StorageAccountName -eq $storageAccountName}
if (($storageAccount).count -eq 0)
{
    #Account didn't exist, create 
    Write-Host "Creating Storage Account $VMSSName$storageAccountName"
    $storageAccount = New-AzStorageAccount -StorageAccountName $storageAccountName -Location $Location -ResourceGroupName $rgName -SkuName Standard_GRS
}
else
{
    Write-Host "Storage Account exists"
}

#Validate that the container exists
Write-Host "Creating/validating container $containerName"
if ((Get-AzStorageContainer -Context $storageAccount.Context | Where-Object {$_.Name -eq $containerName}).count -eq 0)
{
    #Container didn't exist, create
    Write-Host "Creating container $containerName"
    New-AzStorageContainer -Name $containerName -Context $storageAccount.Context
}
else
{
    Write-Host "Container exists"
}

#Grab a pointer to the VMSS
Write-Host "Getting a pointer to the VMSS"
$VMSS = Get-AzVmss -VMScaleSetName $VMSSName -ResourceGroupName $rgName

#Add Network Watcher extension to the VMSS if necessary
Write-Host "Checking whether Network Watcher is already installed"
if (($VMSS.VirtualMachineProfile.ExtensionProfile.Extensions | Where-Object {$_.Publisher -eq "Microsoft.Azure.NetworkWatcher"}).Count -eq 0)
{
    Write-Host "Adding Network Watcher to VMSS instances"
    $nwExt = (Get-AzVMExtensionImage -Location $location -PublisherName Microsoft.Azure.NetworkWatcher -Type NetworkWatcherAgentWindows | Sort-Object -Descending Version)[0]
    Add-AzVmssExtension -VirtualMachineScaleSet $VMSS -Name "netwatcher" -Publisher $nwExt.PublisherName -AutoUpgradeMinorVersion $True -Type $nwExt.Type -TypeHandlerVersion $nwExt.Version.Substring(0,3)
    Update-AzVmss -VMScaleSetName $VMSSName -ResourceGroupName $rgName -VirtualMachineScaleSet $VMSS

    #Need to loop through and push new model to existing VMs
    Write-Host "Updating existing instances with the newly added extension"
    for ($i = 0; $i -lt $VMSS.Sku.Capacity; $i++) 
    {
        #Get VM from underlying VMSS
        Update-AzVmssInstance -ResourceGroupName $rgName -VMScaleSetName $VMSS.Name -InstanceId $i
    }
}
else 
{
    Write-Host "Network Watcher already installed"
}

#Get Network Watcher Object
Write-Host "Getting a pointer to Network Watcher"
$nw = Get-AzResource | Where-Object {$_.ResourceType -eq "Microsoft.Network/networkWatchers" -and $_.Location -eq $location }
$networkWatcher = Get-AzNetworkWatcher -Name $nw.Name -ResourceGroupName $nw.ResourceGroupName 
if (($networkWatcher).count -eq 0)
{
    $networkWatcher = New-AzNetworkWatcher -Name $networkWatcherName -ResourceGroupName $rgName -Location $location
}

#Filters that we can tune to the solution
Write-Host "Creating some packet filters"
$filter1 = New-AzPacketCaptureFilterConfig -Protocol TCP -RemoteIPAddress "1.1.1.1-255.255.255" -LocalIPAddress "10.0.0.3" -LocalPort "1-65535" -RemotePort "20;80;443"
$filter2 = New-AzPacketCaptureFilterConfig -Protocol UDP 

#Loop through and set up Network Watcher on each VM in the VMSS
[array]$packetCaptures = @()
Write-Host "Kicking off a packet capture for the entire VMSS - VM by VM"
$VMs = Get-AzVmssVM -ResourceGroupName $rgName -VMScaleSetName $VMSSName
foreach ($instance in $VMs) 
{

    #Get VM from underlying VMSS
    $VM = Get-AzVmssVM -ResourceGroupName $rgName -VMScaleSetName $VMSSName -InstanceId $instance.InstanceId
    Write-Host "Starting on $($instance.Name)"

    #Run the packet capture with a unique packet capture name
    $packetCaptureName = "capture_vm_" + $VM.Name
    New-AzNetworkWatcherPacketCapture -NetworkWatcherName $networkWatcher.Name -ResourceGroupName $networkWatcher.ResourceGroupName -TargetVirtualMachineId $VM.Id -PacketCaptureName $packetCaptureName -StorageAccountId $storageAccount.id -TimeLimitInSeconds 60 -Filter $filter1, $filter2  -AsJob

    #Make a call back to Netwatcher to get more details on the packet capture
    $pc = Get-AzNetworkWatcherPacketCapture -NetworkWatcherName $networkWatcher.Name -ResourceGroupName $networkWatcher.ResourceGroupName -PacketCaptureName $packetCaptureName
    $packetCaptures += $pc

    if ($pc.ProvisoningState -eq "Succeeded")
    {
        Write-Host "Successfully started packet capture on VM$($instance)"
    }
    else {
        Write-Error "Failed to start packet capture on VM$($instance)"
    }
}

#Wait for all the packet captures to either finish of end up in a failed state
$done = $false
while ($done -ne $true) 
{
    foreach ($pc in $packetCaptures) {

        #refresh the state
        $pc = Get-AzNetworkWatcherPacketCapture -NetworkWatcherName $networkWatcher.Name -ResourceGroupName $networkWatcher.ResourceGroupName -PacketCaptureName $pc.Name

        if ($pc.ProvisoningState -eq "Succeeded")
        {
            if ($pc.PacketCaptureStatus -eq "Stopped") 
            {
                Write-Host "Packet capture $($pc.Name) is done. Removing..."
                Remove-AzNetworkWatcherPacketCapture -NetworkWatcherName $networkWatcher.Name -ResourceGroupName $networkWatcher.ResourceGroupName -PacketCaptureName $pc.Name
                Write-Host "Packet capture removed"
            }
            else 
            {
                Write-Warning "Packet capture $($pc.Name) isn't done yet. Sleeping for 60 seconds"
                Start-Sleep 60 
            }
        }
    }
}