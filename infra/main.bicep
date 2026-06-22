targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment (e.g., dev, staging, prod)')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string = 'westus'

@description('PocketBase admin email for initial superuser')
@secure()
param pbAdminEmail string = ''

@description('PocketBase admin password for initial superuser')
@secure()
param pbAdminPassword string = ''

@description('Resource group hosting the shared Log Analytics workspace and Application Insights instance. Required when reusing central observability across RGs.')
param sharedObservabilityResourceGroup string

@description('Name of the shared Log Analytics workspace (cross-RG existing reference)')
param sharedLogAnalyticsWorkspaceName string

@description('Name of the shared Application Insights instance (cross-RG existing reference)')
param sharedApplicationInsightsName string

@description('Resource group name for this deployment. Defaults to rg-<environmentName>.')
param resourceGroupName string = 'rg-${environmentName}'

@description('Storage account name (3-24 chars, lowercase alphanumeric only). Defaults to a deterministic name derived from the resource token.')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'st${uniqueString(subscription().subscriptionId, environmentName, location)}'

@description('Custom domain to bind to the Container App ingress (leave empty on first deploy to obtain the verification ID, then add DNS records and redeploy with this set). Example: auth.example.com')
param customDomain string = ''

@description('Phase 2 flag for managed cert. Deploy once with this false to add the hostname, then re-run with true to issue the cert and switch to SniEnabled.')
param bindCertificate bool = false

@description('Container image reference. Leave default; azd deploy replaces it with the freshly built image after the first provision.')
param containerImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

@description('WebAuthn relying-party ID (passkey effective domain, e.g. stfoafrisco.org). Decoupled from AppURL so passkeys can be scoped to a parent domain. Empty = fall back to the AppURL hostname at runtime.')
param webauthnRpId string = ''

@description('Comma-separated allowed WebAuthn origins (e.g. https://app.stfoafrisco.org). Empty = fall back to the AppURL origin at runtime.')
param webauthnRpOrigins string = ''

var abbrs = {
  containerAppsEnvironment: 'cae'
  containerApp: 'ca'
  containerRegistry: 'cr'
  managedIdentity: 'id'
  virtualNetwork: 'vnet'
  subnet: 'snet-aca'
}

var resourceToken = uniqueString(subscription().subscriptionId, environmentName, location)
var tags = {
  'azd-env-name': environmentName
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// Reference shared central observability resources (cross-RG)
resource sharedLaw 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: sharedLogAnalyticsWorkspaceName
  scope: resourceGroup(sharedObservabilityResourceGroup)
}

resource sharedAppInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: sharedApplicationInsightsName
  scope: resourceGroup(sharedObservabilityResourceGroup)
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

module network 'modules/network.bicep' = {
  name: 'network'
  scope: rg
  params: {
    vnetName: '${abbrs.virtualNetwork}-${environmentName}'
    subnetName: abbrs.subnet
    location: location
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    name: storageAccountName
    location: location
    tags: tags
    subnetId: network.outputs.subnetId
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
    subnetId: network.outputs.subnetId
    pbAdminEmail: pbAdminEmail
    pbAdminPassword: pbAdminPassword
    logAnalyticsWorkspaceId: sharedLaw.id
    logAnalyticsCustomerId: sharedLaw.properties.customerId
    appInsightsConnectionString: sharedAppInsights.properties.ConnectionString
    customDomain: customDomain
    bindCertificate: bindCertificate
    containerImage: containerImage
    webauthnRpId: webauthnRpId
    webauthnRpOrigins: webauthnRpOrigins
  }
}

output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = acr.outputs.name
output AZURE_CONTAINER_APP_FQDN string = containerApp.outputs.fqdn
output AZURE_CONTAINER_APP_CUSTOM_DOMAIN_VERIFICATION_ID string = containerApp.outputs.customDomainVerificationId
output AZURE_RESOURCE_GROUP string = rg.name
