$resourceGroup = "ashwin-aks-rg"
$aksName = "ashwin-aks"
$acrName = "ashwinaks"
$keyVaultName = "ashwin-aks-kv"
$fluxIdentityName = "ashwin-aks-flux"
$environmentCode = "dev"
$signingKeyName = "oci-artifact-signing-key"

# Get Cosign public key from Key Vault
az keyvault key download `
  --vault-name $keyVaultName `
  --name $signingKeyName --file cosign-public-key.pem --encoding PEM

# Read the public key content and convert to base64
$publicKeyContent = Get-Content -Path "cosign-public-key.pem" -Raw
$cosignPublicKey = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($publicKeyContent))

# Bootstrap cluster
az deployment group create `
  --name main-BootstrapCluster `
  --resource-group "$resourceGroup" `
  --template-file ../bicep/bootstrapCluster/main.bicep `
  --verbose `
  --parameters `
      clusterName="$aksName" `
      environmentCode="$environmentCode" `
      fluxConfigName="cluster" `
      fluxConfigNamespace="flux-system" `
      fluxExtensionNamespace="flux-system" `
      kustomizationPath="./teknologi/$environmentCode" `
      fluxIdentityName="$fluxIdentityName" `
      ociRepositoryUrl="oci://$($acrName).azurecr.io/manifests/clusters" `
      cosignPublicKey="$cosignPublicKey"
