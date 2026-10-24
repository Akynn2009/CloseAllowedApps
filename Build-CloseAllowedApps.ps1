$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Install-Module -Name ps2exe -Scope CurrentUser -Force
    Import-Module ps2exe
}

$source = Join-Path $root 'Close-AllowedApps.ps1'
$output = Join-Path $root 'CloseAllowedApps.exe'
Invoke-ps2exe -InputFile $source -OutputFile $output -STA -NoConsole -Title 'Close configured apps' -Product 'Close configured apps' -Version '1.0.0'
Write-Host "Built: $output"
