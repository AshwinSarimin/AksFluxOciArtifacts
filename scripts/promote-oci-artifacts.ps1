[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$resultsSummaryFilePath,
  [Parameter(Mandatory = $true)][string]$acrName,
  [Parameter(Mandatory = $true)][string]$environment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$CHECK = [char]0x2705   # ✅
$CROSS = [char]0x274C   # ❌
$INFO = [char]0x2139    # ℹ️

function Add-ArtifactTag {
    param(
        [string]$Registry,
        [string]$SourceReference,
        [string]$Repo,
        [string]$Tag
    )

    $targetTag = "$Registry/$($Repo):$Tag"

    Write-Host "Tagging: $targetTag"

    try {
        # Import the image with new tag using ORAS or direct registry API
        # Using az acr import is the safest way to retag within same registry
        az acr import `
            --name $Registry `
            --source "$SourceReference" `
            --image "$($Repo):$Tag" `
            --force 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Host "$CHECK Successfully tagged: $Tag"
            return $true
        } else {
            Write-Warning "$CROSS Failed to tag: $Tag"
            return $false
        }
    } catch {
        Write-Warning "$CROSS Error tagging $Tag : $_"
        return $false
    }
}

# Construct registry URL
$registryUrl = "$acrName.azurecr.io"

# Read result summary
if (-Not (Test-Path -Path $resultsSummaryFilePath)) {
    Write-Error "$CROSS Result summary file not found: $resultsSummaryFilePath"
    exit 1
}

$resultSummary = Get-Content -Path $resultsSummaryFilePath | ConvertFrom-Json


Write-Host "=== OCI Artifact Promotion ==="
Write-Host "Registry: $registryUrl"
Write-Host "Target Environment: $($environment)"
Write-Host "==============================`n"

Write-Host "$INFO Logging into ACR '$acrName'..."
az acr login --name $acrName | Out-Null

# Iterate over artifacts in the result summary
$successCount = 0
$failCount = 0

foreach ($artifact in $resultSummary) {
  $repository = $artifact.Repository
  $digest = $artifact.Digest
  $fullReference = $artifact.Reference

  Write-Host "`n-----------------------------------------------"
  Write-Host "Promoting Artifact:"
  Write-Host "  Repository: $repository"
  Write-Host "  Digest: $digest"
  Write-Host "  Full Reference: $fullReference"
  Write-Host "-------------------------------------------------`n"

  # Verify artifact exists
  Write-Host "Verifying artifact exists..."
  $manifestOutput = oras manifest fetch "$fullReference" --descriptor 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Error "Artifact with digest $digest not found in repository $repository"
    $failCount++
     continue
  }

  Write-Host "$CHECK Artifact found"

  # Add environment tag
  if (Add-ArtifactTag -Registry $acrName -SourceReference $fullReference -Repo $repository -Tag $environment) {
    Write-Host "$CHECK Successfully promoted to environment: $environment"
    $successCount++
  } else {
    Write-Warning "$CROSS Failed to promote to environment: $environment"
    $failCount++
    continue
  }
}

# Summary
Write-Host ""
Write-Host "=== Promotion Summary ==="

# Exit with appropriate code
exit $(if ($failCount -gt 0) { 1 } else { 0 })