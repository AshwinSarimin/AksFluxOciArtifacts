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

$folders

#if (-not $folders -or $folders.Count -eq 0) {
#  throw "No folders specified to sync."
#}

#Write-Host "Preparing to build $($folders.Count) folder(s)."

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
