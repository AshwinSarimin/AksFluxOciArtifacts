$resourceGroup = "ashwin-aks-rg"
$aksName = "ashwin-aks"
$acrName = "ashwinaks"
$acrSku = "Basic"
$keyVaultName = "ashwin-aks-kv"
$fluxIdentityName = "ashwin-aks-flux"
$location = "westeurope"

$environmentCode

az deployment group create `
  --name main-fluxConfiguration `
  --resource-group "$resourceGroup" `
  --template-file ../bicep/main.bicep `
  --verbose `
  --parameters `
      clusterName="$aksName" `
      environmentCode="$environmentCode" `
      fluxConfigName="cluster" `
      fluxConfigNamespace="ns-flux-cluster-config" `
      kustomizationPath="./clusters/teknologi/dev" `
      kustomizationType="config" `
      fluxIdentityName="$fluxIdentityName" `
      #managedIdentitiesResourceGroupName="$($clusterSettings.region.managedIdentitiesResourceGroupName)" `
      #fluxExtensionNamespace="$($clusterSettings.env.fluxExtensionNamespace)" `
      ociRepositoryUrl="$($acrName).azurecr.io/manifests/clusters" `
      cosignPublicKey="$($env:COSIGN_PUBLIC_KEY)"
