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

// =========== //
// Variables   //
// =========== //

//var kubeletManagedIdentityName = '${tenant}-${region}-${environmentLetter}-mi-${instanceName}-kubelet'
//var fluxManagedIdentityName = '${tenant}-${region}-${environmentLetter}-mi-${instanceName}-flux'
//var istioManagedIdentityName = '${tenant}-${region}-${environmentLetter}-mi-${instanceName}-istio'

module fluxExtension '../templates/fluxExtension.bicep' = {
  name: 'fluxExtension-${clusterName}'
  params: {
    clusterName: clusterName
    managedIdentityName: fluxManagedIdentityName
    managedIdentityResourceGroupName: managedIdentitiesResourceGroupName
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
    ociRepository: {
      url: ociRepositoryUrl
      tag: environmentCode
      useWorkloadIdentity: true
      verifyProvider: 'cosign'
      cosignPublicKey: cosignPublicKey
    }
    kustomizations: {
      path: kustomizationPath
      syncIntervalInSeconds: 120
      prune: true
      dependsOn: kustomizationDependencies
    }
  }
  dependsOn: [
    fluxExtension
  ]
}
