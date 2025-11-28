// =========== //
// Parameters  //
// =========== //

param clusterName string
param environmentCode string
param fluxConfigName string
param fluxConfigNamespace string
param fluxExtensionNamespace string
param kustomizationPath string
param kustomizationDependencies array = []
param fluxIdentityName string
param fluxConfigScope string = 'cluster'
param ociRepositoryUrl string
param cosignPublicKey string
param useOciRepository bool = true
param configSubstitution bool = false
param kustomizationType string = 'config'
//Storage account for AzureBlob source
param storageAccount object = {}
param storageAccountContainerName string = ''
param kubeletManagedIdentity object = {}

// =========== //
// Variables   //
// =========== //

module fluxExtension '../templates/fluxExtension.bicep' = {
  name: 'fluxExtension-${clusterName}'
  params: {
    clusterName: clusterName
    managedIdentityName: fluxIdentityName
    fluxExtensionNamespace: fluxExtensionNamespace
  }
}

module fluxConfiguration '../templates/fluxConfiguration.bicep' = {
  name: 'fluxConfiguration-${fluxConfigName}'
  params: {
    fluxConfigName: fluxConfigName
    clusterName: clusterName
    namespace: fluxConfigNamespace
    scope: fluxConfigScope
    source: useOciRepository ? 'OCIRepository' : 'AzureBlob'
    azureBlob: !useOciRepository ? {
      blobUrl: storageAccount.properties.primaryEndpoints.blob
      containerName: storageAccountContainerName
      managedIdentity: {
        clientId: kubeletManagedIdentity.properties.clientId
      }
    } : {}
    ociRepository: useOciRepository ? {
      url: ociRepositoryUrl
      tag: environmentCode
      useWorkloadIdentity: true
      verifyProvider: 'cosign'
      cosignPublicKey: cosignPublicKey
    } : {}
    kustomizations: configSubstitution
      ? {
          'config-substitutions': {
            path: '${kustomizationPath}/config-substitutions'
            syncIntervalInSeconds: 120
            prune: true
          }
          '${kustomizationType}': {
            dependsOn: union(
              [
                'config-substitutions'
              ],
              kustomizationDependencies
            )
            path: kustomizationPath
            syncIntervalInSeconds: 120
            prune: true
            postBuild: {
              substituteFrom: [
                {
                  kind: 'ConfigMap'
                  name: 'config-substitution-values'
                  optional: true
                }
              ]
            }
          }
        }
      : {
          '${kustomizationType}': {
            path: kustomizationPath
            syncIntervalInSeconds: 120
            prune: true
            dependsOn: kustomizationDependencies
          }
        }
  }
  dependsOn: [
    fluxExtension
  ]
}
