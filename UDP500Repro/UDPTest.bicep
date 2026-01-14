param vmAdminUsername string = 'azureuser'

@secure()
param vmAdminPassword string

param sourceIPAddress string = '52.160.0.0/11'

param vmSize string = 'Standard_D2s_v3'

param location string = resourceGroup().location

param udpListenerPort int = 500

param udpListenerScriptUrl string = 'https://raw.githubusercontent.com/EvanBasalik/Tools/main/UDP500Repro/UDPListener.ps1'

param configureVMScriptUrl string = 'https://raw.githubusercontent.com/EvanBasalik/Tools/main/UDP500Repro/ConfigureVM.ps1'

// ...existing code remains the same until vmExtension...

resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = [for i in range(0, vmCount): {
    name: 'CustomScriptExtension'
    parent: vm[i]
    location: location
    properties: {
        publisher: 'Microsoft.Compute'
        type: 'CustomScriptExtension'
        typeHandlerVersion: '1.10'
        autoUpgradeMinorVersion: true
        settings: {
            fileUris: [
                udpListenerScriptUrl
                configureVMScriptUrl
            ]
        }
        protectedSettings: {
            commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File ConfigureVM.ps1 -Port ${udpListenerPort}'
        }
    }
}]

output loadBalancerPublicIP string = lbPublicIP.properties.ipAddress
output vm0PublicIP string = vmPublicIP[0].properties.ipAddress
output vm1PublicIP string = vmPublicIP[1].properties.ipAddress
