$resourceGroup = "ashwin-aks-rg"
$aksName = "ashwin-aks"
$acrName = "ashwinaks"
$acrSku = "Basic"
$keyVaultName = "ashwin-aks-kv"
$location = "westeurope"

# Create resource group
az group create --name "$resourceGroup" --location "$location"

# Create ACR
az acr create `
  --resource-group "$resourceGroup" `
  --name "$acrName" `
  --sku "$acrSku" `
  --admin-enabled false

# Create Key Vault
az keyvault create `
  --name "$keyVaultName" `
  --resource-group "$resourceGroup" `
  --location "$location" `
  --sku standard

# Create AKS cluster
az aks create `
  --resource-group "$resourceGroup" `
  --name "$aksName" `
  --enable-managed-identity `
  --attach-acr "$acrName" `
  --generate-ssh-keys


#but it would install the Kubernetes extension for Azure CLI, which is required for managing Kubernetes extensions on AKS clusters.
#az extension add --name k8s-extension

#This will create the flux extension in the default namespace "kube-system"
#Installs the Flux GitOps extension on your AKS cluster
az k8s-extension create `
  --resource-group "$resourceGroup" `
  --cluster-name "$aksName" `
  --name "flux-extension" `
  --extension-type "microsoft.flux" `
  --cluster-type managedClusters

az deployment group create `
  --name main-fluxConfiguration `
  --resource-group "$resourceGroup" `
  --template-file ../bicep/main.bicep `
  --verbose `
  --parameters `
      clusterName="$aksName" `
      environmentCode="dev" `
      fluxConfigName="cluster" `
      fluxConfigNamespace="ns-flux-cluster-config" `
      kustomizationPath="./clusters/teknologi/dev" `
      kustomizationType="config" `
      #managedIdentitiesResourceGroupName="$($clusterSettings.region.managedIdentitiesResourceGroupName)" `
      #fluxExtensionNamespace="$($clusterSettings.env.fluxExtensionNamespace)" `
      ociRepositoryUrl="$($acrName).azurecr.io/manifests/clusters" `
      cosignPublicKey="$($env:COSIGN_PUBLIC_KEY)"