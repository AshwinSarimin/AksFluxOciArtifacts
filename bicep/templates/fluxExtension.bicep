param clusterName string
param managedIdentityName string
param managedIdentityResourceGroupName string
param fluxExtensionNamespace string
param fluxControllersLogLevel string = 'error'

resource fluxManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: managedIdentityName
  scope: resourceGroup(managedIdentityResourceGroupName)
}

resource cluster 'Microsoft.ContainerService/managedClusters@2025-05-01' existing = {
  name: clusterName
}

// Flux v2 Extension
resource fluxExtension 'Microsoft.KubernetesConfiguration/extensions@2024-11-01' = {
  name: 'flux'
  scope: cluster
  properties: {
    extensionType: 'microsoft.flux'
    autoUpgradeMinorVersion: true
    releaseTrain: 'Stable'
    scope: {
      cluster: {
        releaseNamespace: fluxExtensionNamespace
      }
    }
    configurationProtectedSettings: {
      'workloadIdentity.enable': 'true'
      'workloadIdentity.azureClientId': fluxManagedIdentity.properties.clientId
      'helm-controller.detectDrift': 'true'
      'helm-controller.outOfMemoryWatch.enabled': 'true' 
      'helm-controller.outOfMemoryWatch.memoryThreshold' : '70'
      'helm-controller.outOfMemoryWatch.interval': '700ms'
      'helm-controller.log-level': fluxControllersLogLevel
      'source-controller.log-level': fluxControllersLogLevel
      'kustomize-controller.log-level': fluxControllersLogLevel
      'notification-controller.log-level': fluxControllersLogLevel
      'image-automation-controller.log-level': fluxControllersLogLevel
      'image-reflector-controller.log-level': fluxControllersLogLevel
    }
  }
}
