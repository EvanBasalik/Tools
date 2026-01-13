param vmAdminUsername string = 'azureuser'

param vmAdminPassword string = ''

param sourceIPAddress string = '52.177.6.198'

param vmSize string = 'Standard_D2s_v3'

param location string = resourceGroup().location

param udpListenerPort int = 500

param udpListenerScriptUrl string = 'https://raw.githubusercontent.com/EvanBasalik/Tools/main/UDP500Repro/UDPListener.ps1'

var vnetName = 'vnet-udp500'
var subnetName = 'subnet-backend'
var nsgName = 'nsg-udp500'
var nsgRestrictedName = 'nsg-udp500-restricted'
var lbName = 'lb-udp500'
var lbPublicIPName = 'pip-lb-udp500'
var vmCount = 2
var lbBackendPoolName = 'backendPool'
var lbProbeName = 'healthProbe'

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
    name: nsgName
    location: location
    properties: {
        securityRules: [
            {
                name: 'AllowUDP500'
                properties: {
                    protocol: 'Udp'
                    sourcePortRange: '*'
                    destinationPortRange: '500'
                    sourceAddressPrefix: '*'
                    destinationAddressPrefix: '*'
                    access: 'Allow'
                    priority: 100
                    direction: 'Inbound'
                }
            }
            {
                name: 'AllowRDP'
                properties: {
                    protocol: 'Tcp'
                    sourcePortRange: '*'
                    destinationPortRange: '3389'
                    sourceAddressPrefix: '*'
                    destinationAddressPrefix: '*'
                    access: 'Allow'
                    priority: 200
                    direction: 'Inbound'
                }
            }
        ]
    }
}

resource nsgRestricted 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
    name: nsgRestrictedName
    location: location
    properties: {
        securityRules: [
            {
                name: 'Allow500FromSource'
                properties: {
                    protocol: 'Udp'
                    sourcePortRange: '*'
                    destinationPortRange: '500'
                    sourceAddressPrefix: sourceIPAddress
                    destinationAddressPrefix: '*'
                    access: 'Allow'
                    priority: 100
                    direction: 'Inbound'
                }
            }
            {
                name: 'AllowTCP500FromSource'
                properties: {
                    protocol: 'Tcp'
                    sourcePortRange: '*'
                    destinationPortRange: '500'
                    sourceAddressPrefix: sourceIPAddress
                    destinationAddressPrefix: '*'
                    access: 'Allow'
                    priority: 110
                    direction: 'Inbound'
                }
            }
            {
                name: 'AllowRDP'
                properties: {
                    protocol: 'Tcp'
                    sourcePortRange: '*'
                    destinationPortRange: '3389'
                    sourceAddressPrefix: sourceIPAddress
                    destinationAddressPrefix: '*'
                    access: 'Allow'
                    priority: 200
                    direction: 'Inbound'
                }
            }
        ]
    }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
    name: vnetName
    location: location
    properties: {
        addressSpace: {
            addressPrefixes: ['10.0.0.0/16']
        }
        subnets: [
            {
                name: subnetName
                properties: {
                    addressPrefix: '10.0.1.0/24'
                    networkSecurityGroup: {
                        id: nsg.id
                    }
                }
            }
        ]
    }
}

resource lbPublicIP 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
    name: lbPublicIPName
    location: location
    sku: {
        name: 'Standard'
    }
    properties: {
        publicIPAllocationMethod: 'Static'
    }
}

resource vmPublicIP 'Microsoft.Network/publicIPAddresses@2023-05-01' = [for i in range(0, vmCount): {
    name: 'pip-vm${i}'
    location: location
    sku: {
        name: 'Standard'
    }
    properties: {
        publicIPAllocationMethod: 'Static'
    }
}]

resource lb 'Microsoft.Network/loadBalancers@2023-05-01' = {
    name: lbName
    location: location
    sku: {
        name: 'Standard'
    }
    properties: {
        frontendIPConfigurations: [
            {
                name: 'LoadBalancerFrontEnd'
                properties: {
                    publicIPAddress: {
                        id: lbPublicIP.id
                    }
                }
            }
        ]
        backendAddressPools: [
            {
                name: lbBackendPoolName
            }
        ]
        loadBalancingRules: [
            {
                name: 'UDP500Rule'
                properties: {
                    frontendIPConfiguration: {
                        id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'LoadBalancerFrontEnd')
                    }
                    backendAddressPool: {
                        id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, lbBackendPoolName)
                    }
                    protocol: 'Udp'
                    frontendPort: 500
                    backendPort: 500
                    enableFloatingIP: false
                    idleTimeoutInMinutes: 4
                    probe: {
                        id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, lbProbeName)
                    }
                }
            }
        ]
        probes: [
            {
                name: lbProbeName
                properties: {
                    protocol: 'TCP'
                    port: 500
                    intervalInSeconds: 5
                    numberOfProbes: 2
                }
            }
        ]
    }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-05-01' = [for i in range(0, vmCount): {
    name: 'nic-vm${i}'
    location: location
    properties: {
        ipConfigurations: [
            {
                name: 'ipconfig1'
                properties: {
                    privateIPAllocationMethod: 'Dynamic'
                    subnet: {
                        id: '${vnet.id}/subnets/${subnetName}'
                    }
                    publicIPAddress: {
                        id: vmPublicIP[i].id
                    }
                    loadBalancerBackendAddressPools: [
                        {
                            id: '${lb.id}/backendAddressPools/${lbBackendPoolName}'
                        }
                    ]
                }
            }
        ]
    }
}]

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = [for i in range(0, vmCount): {
    name: 'vm-udp500-${i}'
    location: location
    properties: {
        hardwareProfile: {
            vmSize: vmSize
        }
        osProfile: {
            computerName: 'vm-udp500-${i}'
            adminUsername: vmAdminUsername
            adminPassword: vmAdminPassword
            windowsConfiguration: {
                provisionVMAgent: true
                enableAutomaticUpdates: true
            }
        }
        storageProfile: {
            imageReference: {
                publisher: 'MicrosoftWindowsServer'
                offer: 'WindowsServer'
                sku: '2022-Datacenter'
                version: 'latest'
            }
            osDisk: {
                createOption: 'FromImage'
                managedDisk: {
                    storageAccountType: 'Premium_LRS'
                }
            }
        }
        networkProfile: {
            networkInterfaces: [
                {
                    id: nic[i].id
                }
            ]
        }
    }
}]

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
            ]
        }
        protectedSettings: {
            commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -Command "New-NetFirewallRule -DisplayName \'Allow UDP ${udpListenerPort}\' -Direction Inbound -Protocol UDP -LocalPort ${udpListenerPort} -Action Allow -ErrorAction SilentlyContinue; $privateIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias \'Ethernet*\' | Where-Object {$_.IPAddress -like \'10.*\'}).IPAddress; New-Item -ItemType Directory -Path \'C:\\UDPListener\' -Force; $scriptPath = \'C:\\Packages\\Plugins\\Microsoft.Compute.CustomScriptExtension\\*\\Downloads\\0\\UDPListener.ps1\'; if (Test-Path $scriptPath) { Copy-Item $scriptPath -Destination \'C:\\UDPListener\\UDPListener.ps1\' -Force; $action = New-ScheduledTaskAction -Execute \'PowerShell.exe\' -Argument \"-NoProfile -ExecutionPolicy Bypass -File C:\\UDPListener\\UDPListener.ps1 -Port ${udpListenerPort} -IPAddress $privateIP\"; $trigger = New-ScheduledTaskTrigger -AtStartup; $principal = New-ScheduledTaskPrincipal -UserId \'SYSTEM\' -LogonType ServiceAccount -RunLevel Highest; Register-ScheduledTask -TaskName \'UDPListener\' -Action $action -Trigger $trigger -Principal $principal -Force; Start-ScheduledTask -TaskName \'UDPListener\' }"'
        }
    }
}]

output loadBalancerPublicIP string = lbPublicIP.properties.ipAddress
output vm0PublicIP string = vmPublicIP[0].properties.ipAddress
output vm1PublicIP string = vmPublicIP[1].properties.ipAddress
