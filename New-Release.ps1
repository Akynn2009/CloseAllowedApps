param(
    [Parameter(Mandatory = $true)]
    [version]$Version
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$source = Join-Path $root 'Close-AllowedApps.ps1'
$build = Join-Path $root 'Build-CloseAllowedApps.ps1'
$manifest = Join-Path $root 'update-manifest.json'
$exe = Join-Path $root 'CloseAllowedApps.exe'

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    Import-Module ps2exe -ErrorAction Stop
}

$sourceText = Get-Content -LiteralPath $source -Raw
$sourceText = [regex]::Replace($sourceText, "\$script:AppVersion = \[version\]'[^']+'", "`$script:AppVersion = [version]'$Version'", 1)
Set-Content -LiteralPath $source -Value $sourceText -Encoding UTF8

$buildText = Get-Content -LiteralPath $build -Raw
$buildText = [regex]::Replace($buildText, "-Version '[^']+'", "-Version '$Version'", 1)
Set-Content -LiteralPath $build -Value $buildText -Encoding UTF8

$catalogue = Join-Path $root 'catalogue_logiciels.csv'
Invoke-ps2exe -InputFile $source -OutputFile $exe -STA -NoConsole -Title 'Close configured apps' -Product 'Close configured apps' -Version ([string]$Version) -embedFiles @{'.\catalogue_logiciels.csv' = $catalogue}
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash

$manifestObject = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
$manifestObject.latestVersion = [string]$Version
$manifestObject.minimumRequiredVersion = [string]$Version
$manifestObject.downloadUrl = "https://github.com/Akynn2009/CloseAllowedApps/releases/download/v$Version/CloseAllowedApps.exe"
$manifestObject.sha256 = $hash
$manifestObject | ConvertTo-Json | Set-Content -LiteralPath $manifest -Encoding UTF8

Write-Host "Release prepared: v$Version"
Write-Host "EXE SHA-256: $hash"
Write-Host "Next: git commit, push, tag v$Version, and create the GitHub release."
