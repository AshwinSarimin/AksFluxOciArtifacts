<#
.SYNOPSIS
    Promotes OCI artifacts in Azure Container Registry across environments.

.DESCRIPTION
    This script promotes existing OCI artifacts (container images, Helm charts, etc.)
    from one environment to another by adding environment-specific tags.
    It preserves the original artifact digest to ensure consistency.

.PARAMETER ResultSummaryFilePath
    The file path to the JSON result summary containing artifact details.

.PARAMETER RegistryName
    The name of the Azure Container Registry (without .azurecr.io)

.PARAMETER Environment
    The environment tag (e.g., "dev")

.EXAMPLE
    .\promote-oci-artifacts.ps1 -ResultSummaryFilePath "C:\artifacts\result-summary.json" -RegistryName "myacr" -Environment "dev"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResultSummaryFilePath,

    [Parameter(Mandatory = $true)]
    [string]$RegistryName,

    [Parameter(Mandatory = $true)]
    [ValidateSet("dev", "tst", "prd")]
    [string]$Environment
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
$registryUrl = "$RegistryName.azurecr.io"

# Read result summary
if (-Not (Test-Path -Path $ResultSummaryFilePath)) {
    Write-Error "$CROSS Result summary file not found: $ResultSummaryFilePath"
    exit 1
}

$resultSummary = Get-Content -Path $ResultSummaryFilePath | ConvertFrom-Json


Write-Host "=== OCI Artifact Promotion ==="
Write-Host "Registry: $registryUrl"
Write-Host "Target Environment: $($Environment)"
Write-Host "==============================`n"

Write-Host "$INFO Logging into ACR '$RegistryName'..."
az acr login --name $RegistryName | Out-Null

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
  if (Add-ArtifactTag -Registry $RegistryName -SourceReference $fullReference -Repo $repository -Tag $Environment) {
    Write-Host "$CHECK Successfully promoted to environment: $Environment"
    $successCount++
  } else {
    Write-Warning "$CROSS Failed to promote to environment: $Environment"
    $failCount++
    continue
  }
}

# Summary
Write-Host ""
Write-Host "=== Promotion Summary ==="

# Exit with appropriate code
exit $(if ($failCount -gt 0) { 1 } else { 0 })