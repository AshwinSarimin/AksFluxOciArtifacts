<#
.SYNOPSIS
    Builds Flux OCI artifacts from specified folders and saves them as tgz files.

.DESCRIPTION
    This script builds Flux OCI artifacts from one or more source folders using the 'flux build artifact' command.
    Each folder is processed individually and the resulting artifact is saved to the destination folder as a .tgz file.

    The script requires the following tools to be available in PATH:
    - az (Azure CLI)
    - flux (Flux CLI)
    - git

.PARAMETER FoldersToSync
    Comma-separated list of folder paths to build as OCI artifacts.
    Example: "./folder1,./folder2,folder3"

.PARAMETER DestinationFolder
    The destination folder where the built .tgz artifacts will be saved.
    If the folder doesn't exist, it will be created automatically.

.EXAMPLE
    .\create-oci-artifacts.ps1 -FoldersToSync "./charts/app1,./charts/app2" -DestinationFolder "./artifacts"

.NOTES
    Author: AKS Platform Team
    Version: 1.0
#>
param(
  [Parameter(Mandatory = $true)]
  [string] $FoldersToSync,
  [Parameter(Mandatory = $true)]
  [string] $DestinationFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Command {
  param([string] $Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' not found in PATH."
  }
}

Require-Command -Name az
Require-Command -Name flux
Require-Command -Name git

# Normalize folders
$folders = $FoldersToSync -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

if (-not $folders -or $folders.Count -eq 0) {
  throw "No folders specified to sync."
}

Write-Host "Preparing to build $($folders.Count) folder(s)."

# Create destination folder if it doesn't exist
if (-not (Test-Path -Path $DestinationFolder -PathType Container)) {
  Write-Host "Creating destination folder at '$DestinationFolder'."
  New-Item -ItemType Directory -Path $DestinationFolder | Out-Null
}

$failed = @()

foreach ($folder in $folders) {
  if (-not (Test-Path -Path $folder -PathType Container)) {
    Write-Warning "Folder '$folder' does not exist. Skipping."
    continue
  }

  # Strip leading ./ or .\ (only once) for artifact naming
  $artifactFolder = $folder -replace '^[.][\\/]', ''
  $destination = Join-Path -Path $DestinationFolder -ChildPath "$artifactFolder.tgz"

  Write-Host "`nBuilding artifact for folder '$folder'..."

  # Perform push and capture output for digest extraction
  $buildOutput = flux build artifact `
    --path "$folder" `
    --output "$destination" | Out-Null

  if ($LASTEXITCODE -ne 0) {
    Write-Warning "❌ Build failed for '$folder'."
    $failed += $folder
    continue
  } else {
    Write-Host "✅ Build succeeded for '$folder'."
  }

  Write-Host "Successfully build '$folder'."
}

if ($failed.Count -gt 0) {
  Write-Error "Completed with failures in folder(s): $($failed -join ', ')"
  exit 1
}

Write-Host "`nAll folders processed successfully."
