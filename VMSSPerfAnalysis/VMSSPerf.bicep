@description('Name for the VMSS')
param vmssName string = 'sysbench-vmss'

@description('Admin username for VM instances')
param adminUsername string = 'azureuser'

@description('SSH public key for admin user')
param adminSshKey string

@description('Number of VM instances in the scale set')
param instanceCount int = 10

@description('Sysbench run duration in seconds')
param sysbenchTime int = 30

@description('VM size for the VMSS instances')
param vmSize string = 'Standard_D2s_v3'

@description('Virtual network address prefix')
param vnetPrefix string = '10.0.0.0/16'

@description('Subnet prefix')
param subnetPrefix string = '10.0.0.0/24'

@description('Log Analytics workspace name')
param workspaceName string = '${vmssName}-law'

@description('Azure region for all resources')
param location string = resourceGroup().location

var imagePublisher = 'Canonical'
var imageOffer = '0001-com-ubuntu-server-focal'
var imageSku = '20_04-lts-gen2'

resource law 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource natPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${vmssName}-nat-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource natGateway 'Microsoft.Network/natGateways@2023-09-01' = {
  name: '${vmssName}-nat'
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

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${vmssName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetPrefix
      ]
    }
    subnets: [
      {
        name: 'subnet1'
        properties: {
          addressPrefix: subnetPrefix
          natGateway: {
            id: natGateway.id
          }
        }
      }
    ]
  }
}

var workspaceKey = listKeys(law.id, law.apiVersion).primarySharedKey
var workspaceCustomerId = reference(law.id, law.apiVersion).customerId

var cloudInitScript = concat(
  '#!/bin/bash\n',
  'set -euxo pipefail\n',
  '\n',
  'workspaceId="', workspaceCustomerId, '"\n',
  'workspaceKey="', workspaceKey, '"\n',
  'duration="', string(sysbenchTime), '"\n',
  'hostName=$(hostname)\n',
  'outputFile=/var/log/sysbench-$hostName.log\n',
  '\n',
  'export DEBIAN_FRONTEND=noninteractive\n',
  'apt-get update -y\n',
  'apt-get install -y sysbench python3 curl\n',
  'sysbench cpu --threads=$(nproc) --time=$duration run > $outputFile 2>&1 || true\n',
  '\n',
  'payload=$(python3 - <<PY\n',
  'import json, socket\n',
  'h = socket.gethostname()\n',
  'p = f"/var/log/sysbench-{h}.log"\n',
  'with open(p, "r", errors="ignore") as f:\n',
  '    print(json.dumps({"Host": h, "Output": f.read()}))\n',
  'PY\n',
  ')\n',
  'dateString=$(date -u +"%a, %d %b %Y %H:%M:%S GMT")\n',
  'contentLength=$(printf "%s" "$payload" | wc -c)\n',
  'resourcePath="/api/logs"\n',
  'stringToSign="POST\\n$contentLength\\napplication/json\\nx-ms-date:$dateString\\n$resourcePath"\n',
  '\n',
  'signature=$(python3 -c "import base64,hmac,hashlib,sys;print(base64.b64encode(hmac.new(base64.b64decode(sys.argv[1]),sys.argv[2].encode(),hashlib.sha256).digest()).decode())" "$workspaceKey" "$stringToSign")\n',
  '\n',
  'authHeader="SharedKey $workspaceId:$signature"\n',
  'url="https://$workspaceId.ods.opinsights.azure.com$resourcePath?api-version=2016-04-01"\n',
  '\n',
  'curl -sS -X POST \\\n',
  '  -H "Content-Type: application/json" \\\n',
  '  -H "Authorization: $authHeader" \\\n',
  '  -H "Log-Type: SysbenchPerf" \\\n',
  '  -H "x-ms-date: $dateString" \\\n',
  '  -d "$payload" \\\n',
  '  "$url" || true\n'
)

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = {
  name: vmssName
  location: location
  sku: {
    name: vmSize
    tier: 'Standard'
    capacity: instanceCount
  }
  properties: {
    singlePlacementGroup: false
    overprovision: false
    upgradePolicy: {
      mode: 'Manual'
    }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: vmssName
        adminUsername: adminUsername
        customData: base64(cloudInitScript)
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${adminUsername}/.ssh/authorized_keys'
                keyData: adminSshKey
              }
            ]
          }
        }
      }
      storageProfile: {
        imageReference: {
          publisher: imagePublisher
          offer: imageOffer
          sku: imageSku
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'StandardSSD_LRS'
          }
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: '${vmssName}-nic'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: vnet.properties.subnets[0].id
                    }
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}

output workspaceNameOut string = law.name
output workspaceIdOut string = law.properties.customerId
output vmssNameOut string = vmss.name
