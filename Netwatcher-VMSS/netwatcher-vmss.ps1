<#
.SYNOPSIS
Demonstrates how to enable Azure Netwatcher for all the VMs in some collection of VMs. In this case, uses an Azure VM Scale Set (VMSS)
Jointly developed by Jennifer Phuong and Evan Basalik

.PARAMETER rgName
Resource group under which the Azure Netwatcher is provisioned

.PARAMETER location
The regional location under which the resources should be provisioned

.PARAMETER VMSSName
Name of a VMSS with one or more VMs

.PARAMETER storageAccountName
The name of the Storage account that will be used/created to store the captured traces

.PARAMETER containerName
The name of the container that will be used/created to store the captured traces

.PARAMETER networkWatcherName
The name of the Network Watcher instance that will be used/created to capture the traces

.EXAMPLE
Takes the information about the VMSS and gets all the VMs and triggers captures on all of them
Start-NetworkWatcherOnMultipleVMs -rgName rgVMSSNW -location eastus -VMSSName vmssevanba -storageAccountName vmsstest -containerName networktraces -networkWatcherName nw


.NOTES
Sample scripts are not supported under any Microsoft standard support program or service. 
The sample scripts are provided AS IS without warranty of any kind. Microsoft disclaims all 
implied warranties including, without limitation, any implied warranties of merchantability
or of fitness for a particular purpose. The entire risk arising out of the use or performance
of the sample scripts and documentation remains with you. In no event shall Microsoft, its 
authors, or anyone else involved in the creation, production, or delivery of the scripts be 
liable for any damages whatsoever (including, without limitation, damages for loss of business
profits, business interruption, loss of business information, or other pecuniary loss) arising
out of the use of or inability to use the sample scripts or documentation, even if Microsoft 
has been advised of the possibility of such damages.
#>
function Start-NetworkWatcherOnMultipleVMs  (
    [parameter(Mandatory=$true)][string]$rgName,
    [parameter(Mandatory=$false)][string]$location,
    [parameter(Mandatory=$false)][string]$VMSSName,
    [parameter(Mandatory=$false)][string]$storageAccountName,
    [parameter(Mandatory=$false)][string]$containerName,
    [parameter(Mandatory=$false)][string]$networkWatcherName
)
{
    #Log in if necessary
    if ((Get-AzContext).count-eq 0)
    {
        Connect-AzAccount
    }

    #Validate that the Storage account exists and create if not
    $storageAccountName = $VMSSName + $storageAccountName
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
    Write-Host "Kicking off a packet capture for the entire VMSS - VM by VM"
    $VMs = Get-AzVmssVM -ResourceGroupName $rgName -VMScaleSetName $VMSSName
    foreach ($instance in $VMs) 
    {

        #Get VM from underlying VMSS
        $VM = Get-AzVmssVM -ResourceGroupName $rgName -VMScaleSetName $VMSSName -InstanceId $instance.InstanceId
        Write-Host "Starting on $($instance.Name)"

        #Run the packet capture with a unique packet capture name
        $packetCaptureName = "capture_vm_" + $VM.Name
        New-AzNetworkWatcherPacketCapture -NetworkWatcherName $networkWatcher.Name -ResourceGroupName $networkWatcher.ResourceGroupName -TargetVirtualMachineId $VM.Id -PacketCaptureName $packetCaptureName -StorageAccountId $storageAccount.id -TimeLimitInSeconds 120 -Filter $filter1, $filter2  -AsJob

        #Make a call back to Netwatcher to get current state of the packet capture
        $pc = Get-AzNetworkWatcherPacketCapture -NetworkWatcherName $networkWatcher.Name -ResourceGroupName $networkWatcher.ResourceGroupName -PacketCaptureName $packetCaptureName
        while ($pc.PacketCaptureStatus -eq "NotStarted") {
            Write-Warning "Packet capture not started yet - sleeping for 30 seconds"
            Start-Sleep 30

            #Make a call back to Netwatcher to get current state of the packet capture
            $pc = Get-AzNetworkWatcherPacketCapture -NetworkWatcherName $networkWatcher.Name -ResourceGroupName $networkWatcher.ResourceGroupName -PacketCaptureName $packetCaptureName
        }    

        if ($pc.ProvisioningState -eq "Succeeded")
        {
            Write-Host "Successfully started packet capture on VM$($instance)"
        }
        else {
            Write-Error "Failed to start packet capture on VM$($instance)"
            Write-Error $pc.PacketCaptureErrorText
        }
    }

    #Wait for all the packet captures to either finish of end up in a failed state
    while ((Get-AzNetworkWatcherPacketCapture -NetworkWatcherName $networkWatcher.Name -ResourceGroupName $networkWatcher.ResourceGroupName | Where-Object {$_.PacketCaptureStatus -eq "Running"}).count -ne 0) 
    {
        $runningCaptures = Get-AzNetworkWatcherPacketCapture -NetworkWatcherName $networkWatcher.Name -ResourceGroupName $networkWatcher.ResourceGroupName | Where-Object {$_.PacketCaptureStatus -eq "Running"}
        foreach ($capture in $runningCaptures) 
        {
            Write-Warning "Packet capture $($capture.Name) isn't done yet. Sleeping for 60 seconds"
        }
        Start-Sleep 60 
    }

    #Now that all the traces are done, remove them
    if ($pc.ProvisoningState -eq "Succeeded")
    {
        Write-Host "Packet capture $($pc.Name) is done. Removing..."
        Remove-AzNetworkWatcherPacketCapture -NetworkWatcherName $networkWatcher.Name -ResourceGroupName $networkWatcher.ResourceGroupName -PacketCaptureName $pc.Name
        $packetCaptures.Remove($pc)
        Write-Host "Packet capture removed"
        else 
        {
            Write-Warning "Packet capture $($pc.Name) isn't done yet. Sleeping for 60 seconds"
            Start-Sleep 60 
        }
    }
}
