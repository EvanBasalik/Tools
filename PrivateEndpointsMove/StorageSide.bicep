@description('Location for all resources')
param location string = resourceGroup().location

@description('Prefix for storage account names (must be 3-18 chars, lowercase, numbers only)')
param prefix string = 'evanbamystorageacct'

@description('Number of storage accounts to create')
param storageAccountCount int = 60

var storageAccounts = [for i in range(1, storageAccountCount): {
    name: '${prefix}${i < 10 ? '0${i}' : i}'
}]

resource storageAccountsRes 'Microsoft.Storage/storageAccounts@2022-09-01' = [for sa in storageAccounts: {
    name: sa.name
    location: location
    sku: {
        name: 'Standard_LRS'
    }
    kind: 'StorageV2'
    properties: {}
}]

// Add a resource lock for each storage account
resource storageAccountLocks 'Microsoft.Authorization/locks@2020-05-01' = [for (sa, idx) in storageAccounts: {
    name: '${sa.name}-lock'
    scope: storageAccountsRes[idx]
    properties: {
       level: 'CanNotDelete'
        notes: 'Lock to prevent accidental deletion of storage account.'
    }
}]
