$resourceGroup = "ashwin-aks-rg"
$aksName = "ashwin-aks"
$acrName = "ashwinaks"
$acrSku = "Basic"
$keyVaultName = "ashwin-aks-kv"
$fluxIdentityName = "ashwin-aks-flux"
$location = "westeurope"

$environmentCode = "dev"

az deployment group create `
  --name main-BootstrapCluster `
  --resource-group "$resourceGroup" `
  --template-file ../bicep/main.bicep `
  --verbose `
  --parameters `
      clusterName="$aksName" `
      environmentCode="$environmentCode" `
      fluxConfigName="cluster" `
      fluxConfigNamespace="flux-cluster-config" `
      fluxExtensionNamespace="flux-system" `
      kustomizationPath="./clusters/teknologi/$environmentCode" `
      fluxIdentityName="$fluxIdentityName" `
      ociRepositoryUrl="$($acrName).azurecr.io/manifests/clusters" `
      cosignPublicKey="$($env:COSIGN_PUBLIC_KEY)"
