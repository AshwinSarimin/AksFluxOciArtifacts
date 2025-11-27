<#
.SYNOPSIS
    Pushes Flux OCI artifacts to Azure Container Registry and signs them using Cosign with Azure Key Vault.

.DESCRIPTION
    This script processes .tgz artifact files from a specified folder, pushes them to Azure Container Registry (ACR)
    using ORAS, and signs them with Cosign using an Azure Key Vault signing key. Each artifact is tagged with
    build-specific metadata and verified after signing.

    The script requires the following tools to be available in PATH:
    - az (Azure CLI)
    - cosign (Sigstore Cosign)
    - oras (OCI Registry As Storage)
    - git

.PARAMETER sharedConfig
  JSON string containing platform-wide shared configurations.
  Includes shared keyVault configurations.

.PARAMETER ArtifactFolder
  Path to the folder containing the .tgz artifact files to be pushed.
  The folder must exist and contain at least one .tgz file.

.PARAMETER AcrName
    Name of the Azure Container Registry where artifacts will be pushed.
    Example: "myacr" (without .azurecr.io suffix)

.PARAMETER RepositoryFolder
    Base repository path in ACR where artifacts will be stored.
    The full path will be: {RepositoryFolder}/{Region}/{ArtifactName}

.PARAMETER BuildNumber
    Build number or version tag to apply to the pushed artifacts.
    This will be used as the artifact tag in ACR.

.PARAMETER Region
    Azure region identifier for multi-region deployments.
    Valid values: 'weu' (West Europe), 'neu' (North Europe)

.PARAMETER KeyVaultName
    Name of the Azure Key Vault containing the signing key.
    Example: "my-keyvault"

.PARAMETER SigningKeyName
    Name of the signing key stored in Azure Key Vault.
    Used to sign artifacts with Cosign.

.EXAMPLE
    .\push-and-sign-artifact.ps1 `
        -ArtifactFolder "./artifacts" `
        -AcrName "myacr" `
        -RepositoryFolder "flux/platform" `
        -BuildNumber "1.0.0" `
        -Region "weu" `
        -KeyVaultName "my-keyvault" `
        -SigningKeyName "signing-key"

.OUTPUTS
    Sets Azure DevOps pipeline variable 'ProcessedArtifacts' with JSON summary of processed artifacts.

#>
param(
  [Parameter(Mandatory = $true)][string] $SigningKeyName,
  [Parameter(Mandatory = $true)][string] $sharedConfig,
  [Parameter(Mandatory = $true)][string] $region,
  [Parameter(Mandatory = $true)][string] $ArtifactFolder, # Path where pipeline artifacts (.tgz) are downloaded
  [Parameter(Mandatory = $true)][string] $RepositoryFolder,
  [Parameter(Mandatory = $true)][string] $AcrName,
  [Parameter(Mandatory = $true)][string] $BuildNumber
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$CHECK = [char]0x2705   # ✅
$CROSS = [char]0x274C   # ❌
$INFO = [char]0x2139    # ℹ️

function Require-Command {
  param([string] $Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' not found in PATH."
  }
}

function Get-KeyIdentifier {
  # Get latest version
  return "azurekms://$KeyVaultName.vault.azure.net/$SigningKeyName"
}

Require-Command -Name az
Require-Command -Name cosign

try {
  $sharedConfigObj = $sharedConfig | ConvertFrom-Json
}
catch {
  Write-Error "Failed to parse JSON parameters: $($_.Exception.Message)"
  throw
}

$KeyVaultName = $sharedConfigObj.regions | Where-Object { $_.name -eq $region } | Select-Object -ExpandProperty sharedKeyVaultName

$KeyVaultName

# Validate artifact path exists
if (-not (Test-Path -Path $ArtifactFolder -PathType Container)) {
  throw "Artifact path '$ArtifactFolder' does not exist."
}

# Validate prerequisites
Write-Host "`n==============================================="
Write-Host "Processing artifacts from: $ArtifactFolder"
Write-Host "Buildnumber: $BuildNumber"
Write-Host "=================================================`n"


Write-Host "$INFO Logging into ACR '$AcrName'..."
az acr login --name $AcrName | Out-Null

# Find all .tgz files
$tgzFiles = Get-ChildItem -Path $ArtifactFolder -Filter "*.tgz" -Recurse -File

if ($tgzFiles.Count -eq 0) {
  Write-Host "$CROSS No .tgz files found in '$ArtifactFolder'."
  exit 1
}

Write-Host "$CHECK Found $($tgzFiles.Count) artifact(s) to process."

$keyIdentifier = Get-KeyIdentifier
Write-Host "$INFO Using Key Identifier: $keyIdentifier"

$failed = @()
$processed = @()

foreach ($tgzFile in $tgzFiles) {
  Write-Host "`n========================================"
  Write-Host "Processing: $($tgzFile.Name)"
  Write-Host "========================================"

  # Extract artifact name from filename (remove .tgz extension)
  $artifactName = $tgzFile.BaseName

  # Build repository path
  $repository = "$RepositoryFolder/$Region/$artifactName"
  $fullRef = "$AcrName.azurecr.io/$($repository):$($BuildNumber)"

  Write-Host "$INFO Pushing $($tgzFile.Name) as '$fullRef'..."

  try {
    # Get git info for metadata
    $shortSha = (git rev-parse --short HEAD 2>$null) ?? "unknown"
    $fullSha  = (git rev-parse HEAD 2>$null) ?? "unknown"
    $branch   = (git branch --show-current 2>$null) ?? "unknown"
    $sourceUrl = (git config --get remote.origin.url 2>$null) ?? "unknown"

    # Convert to relative path for ORAS
    $relativePath = Resolve-Path -Path $tgzFile.FullName -Relative

    # Push artifact to ACR using ORAS
    # Note: ORAS automatically handles authentication via az acr login
    $pushOutput = oras push `
      "$fullRef" `
      "$($relativePath):application/gzip" `
      --annotation "org.opencontainers.image.title=$artifactName" `
      --annotation "org.opencontainers.image.revision=$fullSha" `
      --annotation "org.opencontainers.image.source=$sourceUrl" `
      --annotation "org.opencontainers.image.version=$shortSha" `
      --annotation "org.opencontainers.image.created=$(Get-Date -Format o)" | Out-Null

    if ($LASTEXITCODE -ne 0) {
      Write-Host "$CROSS ORAS push failed for '$($tgzFile.Name)':`n$pushOutput"
      $failed += $tgzFile.Name
      continue
    } else {
      Write-Host "$CHECK ORAS push succeeded for '$($tgzFile.Name)'"
    }

    # Get the digest of the pushed artifact
    $manifestOutput = oras manifest fetch "$fullRef" --descriptor

    if ($LASTEXITCODE -ne 0) {
      Write-Warning "$CROSS Failed to fetch manifest descriptor for '$($tgzFile.Name)'"
      $signRef = $fullRef
      $digest = $null
    } else {
      $manifestJson = $manifestOutput | ConvertFrom-Json
      $digest = $manifestJson.digest
      $signRef = "$AcrName.azurecr.io/$repository@$digest"
    }

    if (-not $digest) {
      Write-Warning "$INFO Digest not found in manifest fetch output."
      $signRef = "$AcrName.azurecr.io/$($repository):$BuildNumber"
    } else {
      $signRef = "$AcrName.azurecr.io/$repository@$digest"
    }

    Write-Host "Signing artifact with cosign..."

    # Sign with cosign using Azure Key Vault
    $signOutput = cosign sign --key "$keyIdentifier" "$signRef" --yes 2>&1

    if ($LASTEXITCODE -ne 0) {
      Write-Host "$CROSS Signing failed for '$($tgzFile.Name)':`n$signOutput" -ForegroundColor Red
      $failed += $tgzFile.Name
      continue
    } else {
      Write-Host "$CHECK Cosign signing succeeded for '$($tgzFile.Name)'"
    }

    # Verify signature
    Write-Host "$INFO Verifying signature..."
    $verifyOutput = cosign verify --key "$keyIdentifier" "$signRef" 2>&1

    if ($LASTEXITCODE -eq 0) {
      Write-Host "$CHECK Cosign verification OK" -ForegroundColor Green
    } else {
      Write-Host "$CROSS Cosign verification FAILED" -ForegroundColor Red
      Write-Host $verifyOutput
      $failed += $tgzFile.Name
      continue
    }

    $processed += @{
      FileName = $tgzFile.Name
      ArtifactName = $artifactName
      Digest = $digest
      Reference = $signRef
      BuildNumber = $BuildNumber
      Region = $Region
      Repository = $repository
    }

    Write-Host "$CHECK Successfully pushed and signed '$($tgzFile.Name)'" -ForegroundColor Green

  } catch {
    Write-Host "$CROSS Error processing '$($tgzFile.Name)': $_" -ForegroundColor Red
    $failed += $tgzFile.Name
  }
}

Write-Host "`n========================================"
Write-Host "SUMMARY"
Write-Host "========================================`n"

if ($processed.Count -gt 0) {
  Write-Host "$CHECK Successfully processed artifacts:" -ForegroundColor Green
  foreach ($item in $processed) {
    Write-Host "  - $($item.FileName) -> $($item.Reference)"
  }
}

if ($failed.Count -gt 0) {
  Write-Host "`n$CROSS Failed artifacts:" -ForegroundColor Red
  foreach ($failedItem in $failed) {
    Write-Host "  - $failedItem"
  }
  exit 1
}

Write-Host "`n$CHECK All artifacts pushed and signed successfully for buildnumber: $BuildNumber" -ForegroundColor Green

# Output summary for pipeline consumption
$summaryJson = $processed | ConvertTo-Json -Depth 10 -Compress
Write-Host "##vso[task.setvariable variable=ProcessedArtifacts;isOutput=true]$summaryJson"
