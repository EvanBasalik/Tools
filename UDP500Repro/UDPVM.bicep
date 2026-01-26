param vmAdminUsername string = 'azureuser'

@secure()
param vmAdminPassword string

param sourceIPAddress string

param vmSize string

param location string = resourceGroup().location

param udpListenerPort int = 500

param udpListenerScriptUrl string

param udpSenderScriptUrl string

param configureVMScriptUrl string

param vmCount int

var vnetName = 'vnet-udp'
var subnetName = 'subnet-backend'
var nsgName = 'nsg-udp'
var lbName = 'lb-udp'
var lbPublicIPName = 'pip-lb-udp'
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
                    destinationPortRange: '${udpListenerPort}'
                    sourceAddressPrefix: sourceIPAddress
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
                name: 'UDPListenerRule'
                properties: {
                    frontendIPConfiguration: {
                        id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'LoadBalancerFrontEnd')
                    }
                    backendAddressPool: {
                        id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, lbBackendPoolName)
                    }
                    protocol: 'Udp'
                    frontendPort: udpListenerPort
                    backendPort: udpListenerPort
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
                    protocol: 'Tcp'
                    port: 3389
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

resource availabilitySet 'Microsoft.Compute/availabilitySets@2023-03-01' = {
    name: 'avset-udp-${resourceGroup().name}'
    location: location
    sku: {
        name: 'Aligned'
    }
    properties: {
        platformFaultDomainCount: 2
        platformUpdateDomainCount: 5
        proximityPlacementGroup: {
            id: proximityPlacementGroup.id
        }
    }
}

resource proximityPlacementGroup 'Microsoft.Compute/proximityPlacementGroups@2023-03-01' = {
    name: 'ppg-udp'
    location: location
    properties: {
        proximityPlacementGroupType: 'Standard'
    }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = [for i in range(0, vmCount): {
    name: 'vm-udp500-${i}-${resourceGroup().name}'
    location: location
    properties: {
        availabilitySet: {
            id: availabilitySet.id
        }
        proximityPlacementGroup: {
            id: proximityPlacementGroup.id
        }
        hardwareProfile: {
            vmSize: vmSize
        }
        osProfile: {
            computerName: 'vm-udp-${i}'
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
                configureVMScriptUrl
                udpSenderScriptUrl
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
