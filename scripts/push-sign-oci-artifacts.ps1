param(
  [Parameter(Mandatory = $true)][string] $signingKeyName,
  [Parameter(Mandatory = $true)][string] $keyVaultName,
  [Parameter(Mandatory = $true)][string] $artifactFolder, # Path where pipeline artifacts (.tgz) are downloaded
  [Parameter(Mandatory = $true)][string] $repositoryFolder,
  [Parameter(Mandatory = $true)][string] $acrName,
  [Parameter(Mandatory = $true)][string] $buildNumber
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
  return "azurekms://$keyVaultName.vault.azure.net/$signingKeyName"
}

Require-Command -Name az
Require-Command -Name cosign

# Validate artifact path exists
if (-not (Test-Path -Path $artifactFolder -PathType Container)) {
  throw "Artifact path '$artifactFolder' does not exist."
}

# Validate prerequisites
Write-Host "`n==============================================="
Write-Host "Processing artifacts from: $artifactFolder"
Write-Host "Buildnumber: $buildNumber"
Write-Host "=================================================`n"


Write-Host "$INFO Logging into ACR '$acrName'..."
az acr login --name $acrName | Out-Null

# Find all .tgz files
$tgzFiles = Get-ChildItem -Path $artifactFolder -Filter "*.tgz" -Recurse -File
#if ($tgzFiles.Count -eq 0) {
#  Write-Host "$CROSS No .tgz files found in '$artifactFolder'."
#  exit 1
#}

#Write-Host "$CHECK Found $($tgzFiles.Count) artifact(s) to process."

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
  $repository = "$repositoryFolder/$artifactName"
  $fullRef = "$acrName.azurecr.io/$($repository):$($buildNumber)"

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
      $signRef = "$acrName.azurecr.io/$repository@$digest"
    }

    if (-not $digest) {
      Write-Warning "$INFO Digest not found in manifest fetch output."
      $signRef = "$acrName.azurecr.io/$($repository):$buildNumber"
    } else {
      $signRef = "$acrName.azurecr.io/$repository@$digest"
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
      BuildNumber = $buildNumber
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

Write-Host "`n$CHECK All artifacts pushed and signed successfully for buildnumber: $buildNumber" -ForegroundColor Green

# Output summary for pipeline consumption
$summaryJson = $processed | ConvertTo-Json -Depth 10 -Compress
"ProcessedArtifacts=$summaryJson" | Add-Content -Path $env:GITHUB_OUTPUT