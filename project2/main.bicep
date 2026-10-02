// project2: a single, secure-by-default Storage Account.
// Deployed by .github/workflows/deploy-bicep.yml with GitHub OIDC (no client secret).

@description('Globally unique name: 3-24 lowercase letters and numbers.')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'storagegithubaction'

@description('Azure region. Defaults to the resource group region.')
param location string = resourceGroup().location

@description('Tags applied to every resource.')
param tags object = {
  project: 'github-actions-project2'
  managedBy: 'bicep'
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

output storageAccountId string = storageAccount.id
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
