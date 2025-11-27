// =========== //
// Parameters  //
// =========== //

//param instanceName string
//param tenant string
//param region string
param clusterName string
param environmentCode string
param fluxConfigName string
param fluxConfigNamespace string
param kustomizationPath string
param kustomizationType string
param kustomizationDependencies array = []
param fluxConfigScope string = 'cluster'
//param managedIdentitiesResourceGroupName string
//param fluxExtensionNamespace string

param ociRepositoryUrl string
param cosignPublicKey string

// =========== //
// Variables   //
// =========== //

//var kubeletManagedIdentityName = '${tenant}-${region}-${environmentLetter}-mi-${instanceName}-kubelet'
//var fluxManagedIdentityName = '${tenant}-${region}-${environmentLetter}-mi-${instanceName}-flux'
//var istioManagedIdentityName = '${tenant}-${region}-${environmentLetter}-mi-${instanceName}-istio'


module fluxConfiguration './templates/fluxConfiguration.bicep' = {
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
      '${kustomizationType}': {
        path: kustomizationPath
        syncIntervalInSeconds: 120
        prune: true
        dependsOn: kustomizationDependencies
      }
    }
  }
}
