$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Install-Module -Name ps2exe -Scope CurrentUser -Force
    Import-Module ps2exe
}

$source = Join-Path $root 'Close-AllowedApps.ps1'
$output = Join-Path $root 'CloseAllowedApps.exe'
$catalogue = Join-Path $root 'catalogue_logiciels.csv'
Invoke-ps2exe -InputFile $source -OutputFile $output -STA -NoConsole -Title 'Close configured apps' -Product 'Close configured apps' -Version '1.0.0' -embedFiles @{'.\catalogue_logiciels.csv' = $catalogue}
Write-Host "Built: $output"
