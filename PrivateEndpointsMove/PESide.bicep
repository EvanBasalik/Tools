// Parameters
param location string = resourceGroup().location
param vnetName string = 'myVnet'
param subnet1Name string = 'subnet1'
param subnet2Name string = 'private-endpoints-subnet'
param subnet1Prefix string = '10.0.1.0/24'
param subnet2Prefix string = '10.0.2.0/24'
param vnetAddressPrefix string = '10.0.0.0/16'

// NAT Gateway parameters
param natGatewayName string = 'myNatGateway'
param natPublicIpName string = 'myNatPublicIp'

// VNet with two subnets
resource vnet 'Microsoft.Network/virtualNetworks@2022-07-01' = {
    name: vnetName
    location: location
    properties: {
        addressSpace: {
            addressPrefixes: [
                vnetAddressPrefix
            ]
        }
        subnets: [
            {
                name: subnet1Name
                properties: {
                    addressPrefix: subnet1Prefix
                }
            }
            {
                name: subnet2Name
                properties: {
                    addressPrefix: subnet2Prefix
                }
            }
        ]
    }
}

// Public IP for NAT Gateway
resource natPublicIp 'Microsoft.Network/publicIPAddresses@2022-07-01' = {
    name: natPublicIpName
    location: location
    sku: {
        name: 'Standard'
    }
    properties: {
        publicIPAllocationMethod: 'Static'
    }
}

resource natGateway 'Microsoft.Network/natGateways@2022-07-01' = {
    name: natGatewayName
    location: location
    sku: {
        name: 'Standard'
    }
    properties: {
        publicIpAddresses: [
            {
                id: natPublicIp.id
            }
        ]
    }
}

// Associate NAT Gateway with subnet1 in the VNet
resource subnet1WithNat 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' = {
    name: '${vnet.name}/${subnet1Name}'
    properties: {
        addressPrefix: subnet1Prefix
        natGateway: {
            id: natGateway.id
        }
    }
    dependsOn: [
        vnet
        natGateway
    ]
}


