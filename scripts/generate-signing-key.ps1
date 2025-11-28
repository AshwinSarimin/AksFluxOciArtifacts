param(
  [Parameter(Mandatory = $true)][string] $keyVaultName,  
  [Parameter(Mandatory = $true)][string] $keyName,
  [Parameter(Mandatory = $false)][ValidateSet(2048, 4096)][int] $keySize = 2048,
  [Parameter(Mandatory = $false)][switch] $force
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

function Test-KeyVaultExists {
  param([string] $vaultName)

  $vault = az keyvault show --name $vaultName 2>$null
  return $LASTEXITCODE -eq 0
}

function Test-KeyExists {
  param(
    [string] $vaultName,
    [string] $name
  )

  $key = az keyvault key show --vault-name $vaultName --name $name 2>$null
  return $LASTEXITCODE -eq 0
}

function New-SigningKey {
  param(
    [string] $vaultName,
    [string] $name,
    [int] $size
  )

  Write-Host "$INFO Creating RSA signing key '$name' with size $size bits..." -ForegroundColor Cyan

  $key = az keyvault key create `
    --vault-name $vaultName `
    --name $name `
    --kty EC `
    --size $size `
    --protection software `
    --ops sign verify `
    --tags "purpose=cosign" "created=$(Get-Date -Format 'yyyy-MM-dd')" `
    --output json 2>&1

  if ($LASTEXITCODE -ne 0) {
    Write-Host "$CROSS Failed to create key:`n$key" -ForegroundColor Red
    return $null
  }

  return $key | ConvertFrom-Json
}

# Validate prerequisites
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Cosign Signing Key Generation" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Require-Command -Name az
Require-Command -Name cosign

# Check if Key Vault exists
Write-Host "$INFO Checking Key Vault '$KeyVaultName'..." -ForegroundColor Cyan

if (-not (Test-KeyVaultExists -vaultName $KeyVaultName)) {
  Write-Host "$CROSS Key Vault '$KeyVaultName' not found" -ForegroundColor Red
  Write-Host "Please ensure the Key Vault exists and you have access to it." -ForegroundColor Yellow
  exit 1
}

Write-Host "$CHECK Key Vault found" -ForegroundColor Green

# Check if key already exists
$keyExists = Test-KeyExists -vaultName $KeyVaultName -name $keyName

if ($keyExists) {
  if ($force) {
    Write-Host "$INFO Key '$keyName' already exists, creating new version..." -ForegroundColor Yellow
  } else {
    Write-Host "$INFO Key '$keyName' already exists in Key Vault '$KeyVaultName'" -ForegroundColor Yellow
    Write-Host "Use -Force parameter to recreate the key." -ForegroundColor Yellow

    # Output existing key details
    $existingKey = az keyvault key show `
      --vault-name $KeyVaultName `
      --name $keyName `
      --output json | ConvertFrom-Json

    Write-Host "`n$INFO Existing Key Details:" -ForegroundColor Cyan
    Write-Host "  Key ID: $($existingKey.key.kid)"
    Write-Host "  Key Type: $($existingKey.key.kty)"
    Write-Host "  Created: $($existingKey.attributes.created)"

    # Output the Key Vault reference for cosign
    $keyId = "azurekms://$KeyVaultName.vault.azure.net/$keyName"
    Write-Host "`n$CHECK Cosign Key Reference:" -ForegroundColor Green
    Write-Host "  $keyId" -ForegroundColor White
    Write-Host "`n##vso[task.setvariable variable=CosignKeyId;isOutput=true]$keyId"

    exit 0
  }
}

# Create the signing key
$newKey = New-SigningKey -vaultName $KeyVaultName -name $keyName -size $keySize

if ($null -eq $newKey) {
  exit 1
}

# Display key information
Write-Host "`n$CHECK Signing key created successfully!" -ForegroundColor Green
Write-Host "`n$INFO Key Details:" -ForegroundColor Cyan
Write-Host "  Key ID: $($newKey.key.kid)"
Write-Host "  Key Type: $($newKey.key.kty)"
Write-Host "  Operations: $($newKey.key.keyOps -join ', ')"
Write-Host "  Protection: $($newKey.attributes.recoveryLevel)"

# Test the key with cosign
$keyId = "azurekms://$KeyVaultName.vault.azure.net/$keyName"
Write-Host "`n$INFO Testing key with cosign..." -ForegroundColor Cyan
Write-Host "  Key Reference: $keyId"

# Verify cosign can access the key
$testOutput = cosign public-key --key "$keyId" 2>&1

if ($LASTEXITCODE -eq 0) {
  Write-Host "$CHECK Cosign can access the key successfully" -ForegroundColor Green
  Write-Host "`nPublic Key:" -ForegroundColor Cyan
  Write-Host $testOutput
} else {
  Write-Host "$CROSS Cosign cannot access the key" -ForegroundColor Red
  Write-Host "Error: $testOutput" -ForegroundColor Yellow
  Write-Host "`nPlease ensure:" -ForegroundColor Yellow
  Write-Host "  1. You have the required Key Vault permissions (Crypto User role or access policy)" -ForegroundColor Yellow
  Write-Host "  2. The managed identity or service principal has access to the Key Vault" -ForegroundColor Yellow
  exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Pipeline Variables" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Setting pipeline output variables:"
Write-Host "  CosignKeyId: $keyId"
Write-Host "  CosignKeyVault: $KeyVaultName"
Write-Host "  CosignKeyName: $keyName"

#Write-Host "##vso[task.setvariable variable=CosignKeyId;isOutput=true]$keyId"
#Write-Host "##vso[task.setvariable variable=CosignKeyVault;isOutput=true]$KeyVaultName"
#Write-Host "##vso[task.setvariable variable=CosignKeyName;isOutput=true]$keyName"

Write-Host "`n$CHECK Key generation completed successfully!" -ForegroundColor Green
Write-Host "`nUsage in scripts:" -ForegroundColor Cyan
Write-Host "  cosign sign --key `"$keyId`" <image-reference>" -ForegroundColor White
Write-Host "  cosign verify --key `"$keyId`" <image-reference>" -ForegroundColor White
