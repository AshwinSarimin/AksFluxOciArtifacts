param fluxConfigName string
param clusterName string
param namespace string
param scope string
param ociRepository object = {}
param kustomizations object = {}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2025-05-01' existing = {
  name: clusterName
}

resource fluxAppConfig 'Microsoft.KubernetesConfiguration/fluxConfigurations@2023-05-01' = {
  name: fluxConfigName
  scope: aksCluster
  properties: union(
    {
      scope: scope
      namespace: namespace
      kustomizations: kustomizations
    },
    {
      sourceKind: 'OCIRepository'
      ociRepository: {
        url: ociRepository.url
        repositoryRef: {
          tag: ociRepository.tag
        }
        syncIntervalInSeconds: (contains(ociRepository, 'syncIntervalInSeconds')) ? ociRepository.syncIntervalInSeconds : 120
        useWorkloadIdentity: ociRepository.useWorkloadIdentity
        verify: {
          provider: ociRepository.verifyProvider
          verificationConfig: {
            'cosign.pub': ociRepository.cosignPublicKey
          }
        }
      }
    }
  )
}
