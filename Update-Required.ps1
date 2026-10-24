param(
    [Parameter(Mandatory = $true)]
    [string]$ApplicationPath
)

. (Join-Path $PSScriptRoot 'Update-Config.ps1')

function Show-UpdateMessage([string]$message, [string]$title) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($message, $title, 'OK', 'Information') | Out-Null
}

if ($script:UpdateManifestUrl -like 'https://example.com/*' -or -not (Test-Path -LiteralPath $ApplicationPath)) {
    exit 0
}

try {
    $manifest = Invoke-RestMethod -Uri $script:UpdateManifestUrl -TimeoutSec 10
    $latest = [version]$manifest.latestVersion
    $minimum = [version]$manifest.minimumRequiredVersion
}
catch {
    if ($script:RequireUpdate) {
        Show-UpdateMessage 'The update server could not be reached. The app will not start because an update check is required.' 'Update check failed'
        exit 1
    }
    exit 0
}

if ($script:AppVersion -ge $latest) { exit 0 }

Add-Type -AssemblyName System.Windows.Forms
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Update required'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(430, 150)
$form.FormBorderStyle = 'FixedDialog'
$form.ControlBox = $false
$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(18, 18)
$label.Size = New-Object System.Drawing.Size(394, 42)
$label.Text = "Version $($manifest.latestVersion) is available. This update is required before the app can continue."
$form.Controls.Add($label)
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(18, 70)
$progress.Size = New-Object System.Drawing.Size(394, 22)
$form.Controls.Add($progress)
$button = New-Object System.Windows.Forms.Button
$button.Location = New-Object System.Drawing.Point(300, 105)
$button.Size = New-Object System.Drawing.Size(112, 30)
$button.Text = 'Update now'
$form.Controls.Add($button)
$button.Add_Click({
    try {
        $tempPath = "$ApplicationPath.download"
        Invoke-WebRequest -Uri $manifest.downloadUrl -OutFile $tempPath -UseBasicParsing
        $hash = (Get-FileHash -LiteralPath $tempPath -Algorithm SHA256).Hash
        if ($hash -ne $manifest.sha256.ToUpperInvariant()) { throw 'Downloaded file checksum does not match the manifest.' }
        Move-Item -LiteralPath $tempPath -Destination $ApplicationPath -Force
        $form.Close()
        Start-Process -FilePath $ApplicationPath
    }
    catch {
        Show-UpdateMessage $_.Exception.Message 'Update failed'
    }
})
[void]$form.ShowDialog()
exit 1
