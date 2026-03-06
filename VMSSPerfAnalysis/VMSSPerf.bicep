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
@description('Virtual network address prefix')
param vnetPrefix string = '10.0.0.0/16'
@description('Subnet prefix')
param subnetPrefix string = '10.0.0.0/24'
@description('Log Analytics workspace name')
param workspaceName string = '${vmssName}-law'
@description('Log Analytics shared key (supply via secure param or fetch prior to deploy)')
@secure()
param workspaceKey string

var vmSize = 'Standard_B2s'
var imagePublisher = 'Canonical'
var imageOffer = '0001-com-ubuntu-server-focal'
var imageSku = '20_04-lts-gen2'

resource law 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: workspaceName
  location: resourceGroup().location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: '${vmssName}-vnet'
  location: resourceGroup().location
  properties: {
    addressSpace: { addressPrefixes: [vnetPrefix] }
    subnets: [
      {
        name: 'subnet1'
        properties: { addressPrefix: subnetPrefix }
      }
    ]
  }
}

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2022-03-01' = {
  name: vmssName
  location: resourceGroup().location
  sku: { name: vmSize; capacity: instanceCount }
  properties: {
    upgradePolicy: { mode: 'Manual' }
    virtualMachineProfile: {
      storageProfile: {
        imageReference: {
          publisher: imagePublisher
          offer: imageOffer
          sku: imageSku
          version: 'latest'
        }
      }
      osProfile: {
        computerNamePrefix: vmssName
        adminUsername: adminUsername
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
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: '${vmssName}-nic'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: { subnet: { id: vnet.properties.subnets[0].id } }
                }
              ]
            }
          }
        ]
      }
    }
  }
}

/* Custom script extension: writes a helper script to /tmp, runs sysbench, and posts output to Log Analytics. */
resource vmssExtension 'Microsoft.Compute/virtualMachineScaleSets/extensions@2022-03-01' = {
  name: '${vmss.name}/sysbenchScript'
  parent: vmss
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    settings: { commandToExecute: '' }
    protectedSettings: {
      commandToExecute: join([
        '/bin/bash -c "',
        'cat > /tmp/sysbench-report.sh <<\'EOF\'\n',
        '#!/usr/bin/env bash\n',
        'set -euo pipefail\n',
        'workspaceId="', law.name, '"\n',
        'workspaceKey="', workspaceKey, '"\n',
        'duration=', sysbenchTime, '\n',
        'HOSTNAME=$(hostname)\n',
        'OUTPUT_FILE=/tmp/sysbench-${HOSTNAME}.log\n',
        'apt-get update -y\n',
        'apt-get install -y sysbench python3 python3-pip curl jq >/dev/null\n',
        'sysbench cpu --threads=$(nproc) --time=${duration} run > ${OUTPUT_FILE} 2>&1 || true\n',
        '\n',
        'payload=$(jq -Rs --arg host "${HOSTNAME}" \'{Host: $host, Output: .}\' < ${OUTPUT_FILE})\n',
        'dateString=$(date -u +"%a, %d %b %Y %H:%M:%S GMT")\n',
        'contentLength=$(printf "%s" "$payload" | wc -c)\n',
        'resourcePath="/api/logs"\n',
        'stringToSign="POST\\n${contentLength}\\napplication/json\\nx-ms-date:${dateString}\\n${resourcePath}"\n',
        'signature=$(python3 - <<PY\nimport sys, hmac, hashlib, base64\nkey = base64.b64decode(sys.argv[1])\nsig = hmac.new(key, sys.argv[2].encode("utf-8"), hashlib.sha256).digest()\nprint(base64.b64encode(sig).decode())\nPY\n"', workspaceKey, '" "', '$stringToSign', '" )\n',
        'authHeader="SharedKey ${workspaceId}:${signature}"\n',
        'url="https://${workspaceId}.ods.opinsights.azure.com${resourcePath}?api-version=2016-04-01"\n',
        'curl -s -S -H "Content-Type: application/json" -H "Authorization: ${authHeader}" -H "Log-Type: SysbenchPerf" -H "x-ms-date: ${dateString}" -d "$payload" "$url" || true\n',
        'EOF\n',
        'chmod +x /tmp/sysbench-report.sh\n',
        '/tmp/sysbench-report.sh\n',
        '"'
      ], '')
    }
  }
}

output workspaceCustomerId string = law.name
output vmssNameOut string = vmss.name
