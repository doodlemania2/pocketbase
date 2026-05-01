targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment (e.g., dev, staging, prod)')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('PocketBase admin email for initial superuser')
@secure()
param pbAdminEmail string = ''

@description('PocketBase admin password for initial superuser')
@secure()
param pbAdminPassword string = ''

var abbrs = {
  resourceGroup: 'rg'
  containerAppsEnvironment: 'cae'
  containerApp: 'ca'
  containerRegistry: 'cr'
  storageAccount: 'st'
  managedIdentity: 'id'
}

var resourceToken = uniqueString(subscription().subscriptionId, environmentName, location)
var tags = {
  'azd-env-name': environmentName
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: '${abbrs.resourceGroup}-${environmentName}'
  location: location
  tags: tags
}

module acr 'modules/acr.bicep' = {
  name: 'acr'
  scope: rg
  params: {
    name: '${abbrs.containerRegistry}${resourceToken}'
    location: location
    tags: tags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    name: '${abbrs.storageAccount}${resourceToken}'
    location: location
    tags: tags
  }
}

module containerApp 'modules/container-app.bicep' = {
  name: 'container-app'
  scope: rg
  params: {
    environmentName: '${abbrs.containerAppsEnvironment}-${environmentName}'
    appName: '${abbrs.containerApp}-${environmentName}'
    identityName: '${abbrs.managedIdentity}-${environmentName}'
    location: location
    tags: tags
    containerRegistryLoginServer: acr.outputs.loginServer
    containerRegistryName: acr.outputs.name
    storageAccountName: storage.outputs.storageAccountName
    fileShareName: storage.outputs.fileShareName
    blobContainerName: storage.outputs.blobContainerName
    pbAdminEmail: pbAdminEmail
    pbAdminPassword: pbAdminPassword
  }
}

output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = acr.outputs.name
output AZURE_CONTAINER_APP_FQDN string = containerApp.outputs.fqdn
output AZURE_RESOURCE_GROUP string = rg.name
