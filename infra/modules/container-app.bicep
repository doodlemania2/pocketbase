@description('Name of the Container Apps environment')
param environmentName string

@description('Name of the Container App')
param appName string

@description('Name of the managed identity')
param identityName string

@description('Location for resources')
param location string

@description('Tags for resources')
param tags object = {}

@description('ACR login server')
param containerRegistryLoginServer string

@description('ACR name')
param containerRegistryName string

@description('Storage account name for Litestream blob backups')
param storageAccountName string

@description('Blob container name for Litestream backups')
param blobContainerName string

@description('PocketBase admin email')
@secure()
param pbAdminEmail string = ''

@description('PocketBase admin password')
@secure()
param pbAdminPassword string = ''

@description('Resource ID of the shared Log Analytics workspace')
param logAnalyticsWorkspaceId string

@description('Customer ID (GUID) of the shared Log Analytics workspace')
param logAnalyticsCustomerId string

@description('Connection string for the shared Application Insights instance')
@secure()
param appInsightsConnectionString string

@description('Custom domain (e.g., auth.example.com). Leave empty to skip binding/managed cert.')
param customDomain string = ''

@description('Phase 2 flag: bind the managed certificate. Run first deploy with this false to add the hostname (which the cert provisioning requires), then re-run with true to issue + bind the cert.')
param bindCertificate bool = false

@description('Container image reference. Defaults to a placeholder; azd deploy replaces with the real image after build.')
param containerImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

// Reference the shared Log Analytics workspace (cross-RG) to fetch its shared key for Container Apps env wiring
resource sharedLaw 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(logAnalyticsWorkspaceId, '/'))
  scope: resourceGroup(split(logAnalyticsWorkspaceId, '/')[4])
}

// Managed Identity
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

// Reference existing resources
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: containerRegistryName
}

// RBAC: Storage Blob Data Contributor for Litestream backups
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
resource blobRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, identity.id, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC: ACR Pull for container image access
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
resource acrRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, identity.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Container Apps Environment - logs stream to the shared central Log Analytics workspace
resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: sharedLaw.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// Azure Files storage mount removed — SQLite locking is unreliable over SMB-mounted Azure Files.
// /pb_data lives on the container's ephemeral writable layer; durability is provided by Litestream
// replication to the blob container (restored on every container start via entrypoint.sh).
var storageAccountKey = storageAccount.listKeys().keys[0].value

// Free Azure-managed TLS certificate for the custom domain (Phase 2 only).
// Container Apps requires the hostname to be present on a container app in the environment
// BEFORE the managed cert can be created, so this is gated behind `bindCertificate`.
// Phase 1 deploys the hostname with bindingType='Disabled' (no cert). Phase 2 sets
// bindCertificate=true to create the cert and switch the binding to SniEnabled.
resource managedCert 'Microsoft.App/managedEnvironments/managedCertificates@2024-03-01' = if (!empty(customDomain) && bindCertificate) {
  parent: environment
  name: empty(customDomain) ? 'placeholder' : replace(customDomain, '.', '-')
  location: location
  properties: {
    subjectName: customDomain
    domainControlValidation: 'CNAME'
  }
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  tags: union(tags, {
    'azd-service-name': 'pocketbase'
  })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: concat([
        { name: 'storage-key', value: storageAccountKey }
        { name: 'appinsights-connection-string', value: appInsightsConnectionString }
      ], empty(pbAdminEmail) ? [] : [
        { name: 'pb-admin-email', value: pbAdminEmail }
      ], empty(pbAdminPassword) ? [] : [
        { name: 'pb-admin-password', value: pbAdminPassword }
      ])
      ingress: {
        external: true
        targetPort: 8090
        transport: 'http'
        allowInsecure: false
        customDomains: empty(customDomain) ? [] : [
          bindCertificate ? {
            name: customDomain
            bindingType: 'SniEnabled'
            certificateId: managedCert.id
          } : {
            name: customDomain
            bindingType: 'Disabled'
          }
        ]
      }
      registries: [
        {
          server: containerRegistryLoginServer
          identity: identity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'pocketbase'
          image: containerImage
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: concat([
            { name: 'PB_HOST', value: '0.0.0.0' }
            { name: 'PB_PORT', value: '8090' }
            { name: 'LITESTREAM_REPLICA_URL', value: 'abs://${blobContainerName}' }
            { name: 'LITESTREAM_AZURE_ACCOUNT_NAME', value: storageAccountName }
            { name: 'LITESTREAM_AZURE_ACCOUNT_KEY', secretRef: 'storage-key' }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', secretRef: 'appinsights-connection-string' }
          ], empty(pbAdminEmail) ? [] : [
            { name: 'PB_ADMIN_EMAIL', secretRef: 'pb-admin-email' }
          ], empty(pbAdminPassword) ? [] : [
            { name: 'PB_ADMIN_PASSWORD', secretRef: 'pb-admin-password' }
          ])
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/api/health'
                port: 8090
              }
              initialDelaySeconds: 5
              periodSeconds: 3
              failureThreshold: 30  // Allow up to ~90s for Litestream restore + PocketBase bootstrap
              timeoutSeconds: 3
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/api/health'
                port: 8090
              }
              initialDelaySeconds: 0
              periodSeconds: 30
              failureThreshold: 3
              timeoutSeconds: 5
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/api/health'
                port: 8090
              }
              initialDelaySeconds: 0
              periodSeconds: 10
              failureThreshold: 3
              timeoutSeconds: 5
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1  // SQLite is single-writer — do not scale beyond 1
      }
      // Give the entrypoint enough time on SIGTERM to drain pocketbase, let
      // SQLite checkpoint the WAL, then have Litestream replicate the final
      // frames to the blob replica before the container is killed. Default is
      // 30s which is tight; 60s gives comfortable headroom.
      terminationGracePeriodSeconds: 60
    }
  }
  dependsOn: [
    acrRoleAssignment
    blobRoleAssignment
  ]
}

output fqdn string = containerApp.properties.configuration.ingress.fqdn
output customDomainVerificationId string = containerApp.properties.customDomainVerificationId
