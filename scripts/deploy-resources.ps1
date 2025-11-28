$resourceGroup = "ashwin-aks-rg"
$aksName = "ashwin-aks"
$acrName = "ashwinaks"
$acrSku = "Basic"
$keyVaultName = "ashwin-aks-kv"
$fluxIdentityName = "ashwin-aks-flux"
$location = "westeurope"

<#
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
  --enable-workload-identity `
  --enable-oidc-issuer `
  --attach-acr "$acrName" #`
  #--generate-ssh-keys
  #--enable-managed-identity


# Create Flux managed identity
az identity create `
  --resource-group $resourceGroup `
  --name $fluxIdentityName `
  -o json


# Assign roles to the Flux
az role assignment create `
   --role "AcrPull" `
   --scope $(az acr show --name $acrName --resource-group $resourceGroup --query "id" -o tsv) `
   --assignee-object-id $(az identity show --resource-group $resourceGroup --name $fluxIdentityName --query "principalId" -o tsv)

#>
# Create federation for flux identity and flux source controller
az identity federated-credential create `
  --name "flux-source-controller" `
  --identity-name $fluxIdentityName `
  --resource-group $resourceGroup `
  --issuer $(az aks show --name $aksName --resource-group $resourceGroup --query "oidcIssuerProfile.issuerUrl" --output tsv) `
  --subject "system:serviceaccount:flux-system:source-controller" `
  --audiences "api://AzureADTokenExchange"





<######################################>
<##THIS WILL BE DONE WITH BICEP
#but it would install the Kubernetes extension for Azure CLI, which is required for managing Kubernetes extensions on AKS clusters.
#az extension add --name k8s-extension
#This will create the flux extension in the default namespace "kube-system"
#Installs the Flux GitOps extension on your AKS cluster

$workloadIdentityClientId = az identity show --resource-group $resourceGroup --name $fluxIdentityName --query "clientId" -o tsv
az k8s-extension create `
  --resource-group "$resourceGroup" `
  --cluster-name "$aksName" `
  --name "flux-extension" `
  --extension-type "microsoft.flux" `
  --cluster-type managedClusters `
  --config-protected-settings "workloadIdentity.enable=true" "workloadIdentity.azureClientId=$workloadIdentityClientId"
<######################################>
