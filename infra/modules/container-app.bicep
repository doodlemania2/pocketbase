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

@description('Storage account name for Azure Files and Blob')
param storageAccountName string

@description('File share name for pb_data')
param fileShareName string

@description('Blob container name for Litestream backups')
param blobContainerName string

@description('PocketBase admin email')
@secure()
param pbAdminEmail string = ''

@description('PocketBase admin password')
@secure()
param pbAdminPassword string = ''

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

// Container Apps Environment
resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// Azure Files storage mount on the environment
var storageAccountKey = storageAccount.listKeys().keys[0].value
resource envStorage 'Microsoft.App/managedEnvironments/storages@2024-03-01' = {
  parent: environment
  name: 'pbdata'
  properties: {
    azureFile: {
      accountName: storageAccountName
      accountKey: storageAccountKey
      shareName: fileShareName
      accessMode: 'ReadWrite'
    }
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
      secrets: [
        { name: 'storage-key', value: storageAccountKey }
        { name: 'pb-admin-email', value: pbAdminEmail }
        { name: 'pb-admin-password', value: pbAdminPassword }
      ]
      ingress: {
        external: true
        targetPort: 8090
        transport: 'http'
        allowInsecure: false
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
          image: '${containerRegistryLoginServer}/pocketbase:latest'
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            { name: 'PB_HOST', value: '0.0.0.0' }
            { name: 'PB_PORT', value: '8090' }
            { name: 'LITESTREAM_REPLICA_URL', value: 'abs://${blobContainerName}' }
            { name: 'LITESTREAM_ACCESS_KEY_ID', value: storageAccountName }
            { name: 'LITESTREAM_SECRET_ACCESS_KEY', secretRef: 'storage-key' }
            { name: 'PB_ADMIN_EMAIL', secretRef: 'pb-admin-email' }
            { name: 'PB_ADMIN_PASSWORD', secretRef: 'pb-admin-password' }
          ]
          volumeMounts: [
            {
              volumeName: 'pbdata'
              mountPath: '/pb_data'
            }
          ]
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
      volumes: [
        {
          name: 'pbdata'
          storageName: envStorage.name
          storageType: 'AzureFile'
        }
      ]
    }
  }
  dependsOn: [
    acrRoleAssignment
    blobRoleAssignment
  ]
}

output fqdn string = containerApp.properties.configuration.ingress.fqdn
