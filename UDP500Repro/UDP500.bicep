param vmAdminUsername string = 'azureuser'

@secure()
param vmAdminPassword string

param vmSize string = 'Standard_D2s_v3'

param location string = resourceGroup().location

var vnetName = 'vnet-udp500'
var subnetName = 'subnet-backend'
var nsgName = 'nsg-udp500'
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
                    protocol: 'Udp'
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
            fileUris: ['https://raw.githubusercontent.com/microsoft/ntttcp/master/NTttcp.exe']
            commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -Command "Invoke-WebRequest -Uri \'https://raw.githubusercontent.com/microsoft/ntttcp/master/NTttcp.exe\' -OutFile \'C:\\ntttcp.exe\'; New-NetFirewallRule -DisplayName \'Allow UDP 500\' -Direction Inbound -Protocol UDP -LocalPort 500 -Action Allow; Start-Process -FilePath \'C:\\ntttcp.exe\' -ArgumentList \'-r\', \'-m\', \'1,*,0.0.0.0:500\', \'-u\' -NoNewWindow"'
        }
    }
}]

output loadBalancerPublicIP string = lbPublicIP.properties.ipAddress