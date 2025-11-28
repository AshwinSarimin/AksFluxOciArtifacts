# AksFluxOciArtifacts







## GitHub Actions

To be able to deploy the Azure resources with GitHub Action, an user-assigned managed identity is used for federated credentials.

**Prerequisites**
- Azure CLI
- GitHub CLI: https://github.com/cli/cli/blob/trunk/docs/install_linux.md

```
(type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
	&& sudo mkdir -p -m 755 /etc/apt/keyrings \
        && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& sudo mkdir -p -m 755 /etc/apt/sources.list.d \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	&& sudo apt update \
	&& sudo apt install gh -y
```

**Managed identity**

Create a managed identity, for example:
```bash
az identity create --resource-group "ashwin-aks-rg" --name "ashwin-aks-deployment" -o json
```

Add the repository as federation to the managed identity:

```bash
# Variables
TENANT_ID="2a158a07-0057-4fd2-8303-84bf295283fe"
SUBSCRIPTION_ID="f6b50b84-d224-4b8d-9dda-64eba46c602a"
RESOURCE_GROUP_NAME="ashwin-aks-rg"
LOCATION="westeurope"
IDENTITY_NAME="ashwin-aks-deployment"
GH_USERNAME="AshwinSarimin"
GH_REPO_NAME="AksFluxOciArtifacts"

# Ensure you have Azure CLI installed and logged in
az login --tenant "$TENANT_ID" --use-device-code

# Login with ashwin.sarimin@teknologi.nl
az account set --subscription "$SUBSCRIPTION_ID"

# Create federated identity credentials
az identity federated-credential create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --identity-name "$IDENTITY_NAME" \
    --name "$GH_REPO_NAME-dev" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "repo:${GH_USERNAME}/${GH_REPO_NAME}:environment:dev" \
    --audiences "api://AzureADTokenExchange"

az identity federated-credential create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --identity-name "$IDENTITY_NAME" \
    --name "$GH_REPO_NAME-tst" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "repo:${GH_USERNAME}/${GH_REPO_NAME}:environment:tst" \
    --audiences "api://AzureADTokenExchange"

az identity federated-credential create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --identity-name "$IDENTITY_NAME" \
    --name "$GH_REPO_NAME-prd" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "repo:${GH_USERNAME}/${GH_REPO_NAME}:environment:prd" \
    --audiences "api://AzureADTokenExchange"

IDENTITY=$(az identity show \
    --name "$IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --output json)

# Output subscription id, client id and tenant id
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
CLIENT_ID=$(echo "$IDENTITY" | jq -r '.clientId')
TENANT_ID=$(echo "$IDENTITY" | jq -r '.tenantId')

# Create JSON output
OUTPUT=$(jq -n \
    --arg sub "$SUBSCRIPTION_ID" \
    --arg client "$CLIENT_ID" \
    --arg tenant "$TENANT_ID" \
    '{SUBSCRIPTION_ID: $sub, CLIENT_ID: $client, TENANT_ID: $tenant}')

echo "$OUTPUT"

# Login Github
gh auth login

# Set GitHub secrets for DEV
gh secret set SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --env "dev" --repo ${GH_USERNAME}/${GH_REPO_NAME}

gh secret set CLIENT_ID --body "$CLIENT_ID" --env "dev" --repo ${GH_USERNAME}/${GH_REPO_NAME}

gh secret set TENANT_ID --body "$TENANT_ID" --env "dev" --repo ${GH_USERNAME}/${GH_REPO_NAME}

# Set GitHub secrets for TST
gh secret set SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --env "tst" --repo ${GH_USERNAME}/${GH_REPO_NAME}

gh secret set CLIENT_ID --body "$CLIENT_ID" --env "tst" --repo ${GH_USERNAME}/${GH_REPO_NAME}

gh secret set TENANT_ID --body "$TENANT_ID" --env "tst" --repo ${GH_USERNAME}/${GH_REPO_NAME}

# Set GitHub secrets for PRD
gh secret set SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --env "prd" --repo ${GH_USERNAME}/${GH_REPO_NAME}

gh secret set CLIENT_ID --body "$CLIENT_ID" --env "prd" --repo ${GH_USERNAME}/${GH_REPO_NAME}

gh secret set TENANT_ID --body "$TENANT_ID" --env "prd" --repo ${GH_USERNAME}/${GH_REPO_NAME}
```

Needs Owner RBAC on Resource Group & KeyVault Administrator RBAC on KeyVault