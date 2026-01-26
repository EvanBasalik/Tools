//netstat -aon | findstr ":500" | findstr "LISTENING" to check for UDP listener process
//az deployment sub create --location westus2 --template-file ./main.bicep to deploy via CLI

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
param sourceIPAddress string = '52.160.0.0/11, 20.98.114.205'

@description('VM size')
param vmSize string = 'Standard_F4s'

@description('UDP listener port')
param udpListenerPort int = 500

@description('Number of VMs to deploy')
param vmCount int = 2

@description('URL to the UDP listener PowerShell script')
param udpListenerScriptUrl string = 'https://raw.githubusercontent.com/EvanBasalik/Tools/main/UDP500Repro/UDPListener.ps1'

@description('URL to the UDP sender PowerShell script')
param udpSenderScriptUrl string = 'https://raw.githubusercontent.com/EvanBasalik/Tools/main/UDP500Repro/UDPSender.ps1'


@description('URL to the VM configuration PowerShell script')
param configureVMScriptUrl string = 'https://raw.githubusercontent.com/EvanBasalik/Tools/main/UDP500Repro/ConfigureVM.ps1'

// Create the resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

// Deploy the UDP test resources into the resource group
module udpTestResources './UDPVM.bicep' = {
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
    udpSenderScriptUrl: udpSenderScriptUrl
    configureVMScriptUrl: configureVMScriptUrl
    vmCount: vmCount
  }
}

output resourceGroupName string = rg.name
output loadBalancerPublicIP string = udpTestResources.outputs.loadBalancerPublicIP
output vm0PublicIP string = udpTestResources.outputs.vm0PublicIP
output vm1PublicIP string = udpTestResources.outputs.vm1PublicIP
