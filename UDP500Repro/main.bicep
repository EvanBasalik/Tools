targetScope = 'subscription'

@description('Name of the resource group to create')
param resourceGroupName string

@description('Location for the resource group and resources')
param location string = 'westus2'

@description('Admin username for VMs')
param vmAdminUsername string = 'azureuser'

@description('Admin password for VMs')
@secure()
param vmAdminPassword string

@description('Source IP address range for NSG rules')
param sourceIPAddress string = '52.160.0.0/11'

@description('VM size')
param vmSize string = 'Standard_D2s_v3'

@description('UDP listener port')
param udpListenerPort int = 500

@description('URL to the UDP listener PowerShell script')
param udpListenerScriptUrl string = 'https://raw.githubusercontent.com/EvanBasalik/Tools/main/UDP500Repro/UDPListener.ps1'

@description('URL to the VM configuration PowerShell script')
param configureVMScriptUrl string = 'https://raw.githubusercontent.com/EvanBasalik/Tools/main/UDP500Repro/ConfigureVM.ps1'

// Create the resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

// Deploy the UDP test resources into the resource group
module udpTestResources './udptest.bicep' = {
  name: 'udptest-deployment'
  scope: rg
  params: {
    vmAdminUsername: vmAdminUsername
    vmAdminPassword: vmAdminPassword
    sourceIPAddress: sourceIPAddress
    vmSize: vmSize
    location: location
    udpListenerPort: udpListenerPort
    udpListenerScriptUrl: udpListenerScriptUrl
    configureVMScriptUrl: configureVMScriptUrl
  }
}

output resourceGroupName string = rg.name
output loadBalancerPublicIP string = udpTestResources.outputs.loadBalancerPublicIP
output vm0PublicIP string = udpTestResources.outputs.vm0PublicIP
output vm1PublicIP string = udpTestResources.outputs.vm1PublicIP
