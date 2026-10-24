Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Add only apps you personally want to close. Use process names without .exe.
# Windows Search and other operating-system processes are intentionally excluded.
$script:AllowedProcessNames = @(
    'msedge',
    'RobloxPlayerBeta'
)

$protectedProcessNames = @(
    'System', 'Registry', 'Idle', 'smss', 'csrss', 'wininit', 'winlogon',
    'services', 'lsass', 'svchost', 'fontdrvhost', 'dwm', 'explorer',
    'StartMenuExperienceHost', 'ShellExperienceHost', 'SearchHost',
    'SearchIndexer', 'RuntimeBroker', 'taskhostw'
)

function Get-ProcessAnalysis {
    $signatureCache = @{}
    $rows = foreach ($process in @(Get-Process -ErrorAction SilentlyContinue | Sort-Object ProcessName)) {
        $path = ''
        try { $path = $process.MainModule.FileName } catch { }
        $name = $process.ProcessName
        $category = 'Unknown / review'
        $reason = 'Path or signature could not be verified'

        if ($path -match '(?i)\\Windows\\|\\System32\\|\\SysWOW64\\|\\WinSxS\\') {
            $category = 'Windows system'
            $reason = 'Located in a Windows system folder'
        }
        elseif ($name -match '(?i)amd|radeon|adrenalin|nvidia|nvcontainer|intel|igfx|arc') {
            $category = 'Graphics / hardware'
            $reason = 'Matches a common graphics or hardware process name'
        }
        elseif ($path) {
            try {
                if ($signatureCache.ContainsKey($path)) {
                    $signature = $signatureCache[$path]
                }
                else {
                    $signature = Get-AuthenticodeSignature -FilePath $path -ErrorAction Stop
                    $signatureCache[$path] = $signature
                }
                if ($signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -match '(?i)Microsoft') {
                    $category = 'Microsoft signed'
                    $reason = 'Valid Microsoft code signature'
                }
                else {
                    $category = 'Third-party / review'
                    $reason = 'Not a valid Microsoft signature'
                }
            }
            catch {
                $category = 'Third-party / review'
                $reason = 'Non-system executable path'
            }
        }

        [pscustomobject]@{
            Process = $name
            PID = $process.Id
            Category = $category
            Path = $path
            Reason = $reason
        }
    }
    return @($rows)
}

function Get-CatalogueAnalysis {
    $cataloguePath = Join-Path $PSScriptRoot 'catalogue_logiciels.csv'
    if (-not (Test-Path -LiteralPath $cataloguePath)) {
        throw "Catalog file not found: $cataloguePath"
    }
    $catalogue = Import-Csv -LiteralPath $cataloguePath
    foreach ($package in $catalogue) {
        [pscustomobject]@{
            PackageId = $package.PackageId
            CatalogueVersion = $package.Version
            Status = 'Catalog entry'
            WinGetResult = 'Use Find running catalog apps to check active processes'
        }
    }
}

function Get-CatalogueRunningProcesses {
    $cataloguePath = Join-Path $PSScriptRoot 'catalogue_logiciels.csv'
    $catalogue = @(Import-Csv -LiteralPath $cataloguePath)
    $aliases = @{
        'Microsoft.Edge' = 'msedge'
        'Roblox.Roblox' = 'RobloxPlayerBeta'
    }
    $lookup = @{}
    foreach ($package in $catalogue) {
        $packageId = [string]$package.PackageId
        $packageInfo = [pscustomobject]@{
            PackageId = $packageId
            Version = $package.Version
        }
        $keys = @($packageId -split '[^a-zA-Z0-9]' | Where-Object { $_.Length -ge 5 })
        if ($aliases.ContainsKey($packageId)) { $keys += $aliases[$packageId] }
        foreach ($key in $keys) {
            $normalizedKey = ([string]$key -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
            if ($normalizedKey) {
                if (-not $lookup.ContainsKey($normalizedKey)) { $lookup[$normalizedKey] = @() }
                $lookup[$normalizedKey] += $packageInfo
            }
        }
    }
    $processes = @(Get-Process -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        if ($protectedProcessNames -contains $process.ProcessName) { continue }
        $processKey = ($process.ProcessName -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
        if ($lookup.ContainsKey($processKey)) {
            foreach ($package in @($lookup[$processKey])) {
                [pscustomobject]@{
                    Process = $process.ProcessName
                    PID = $process.Id
                    PackageId = $package.PackageId
                    Version = $package.Version
                }
            }
        }
    }
}

$script:AllowedProcessNames = @(
    $script:AllowedProcessNames |
        ForEach-Object { ([string]$_).Trim() -replace '\.exe$', '' } |
        Where-Object { $_ } |
        Select-Object -Unique
)

$unsafeNames = @($script:AllowedProcessNames | Where-Object { $protectedProcessNames -contains $_ })
if ($unsafeNames.Count -gt 0) {
    [System.Windows.Forms.MessageBox]::Show(
        "The configured list includes protected Windows processes: $($unsafeNames -join ', ').`nRemove them from the list before continuing.",
        'Unsafe process selection',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    return
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Close configured apps'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(470, 300)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$intro = New-Object System.Windows.Forms.Label
$intro.Location = New-Object System.Drawing.Point(16, 14)
$intro.Size = New-Object System.Drawing.Size(438, 46)
$intro.Text = 'Force-stops only the apps listed below. Unsaved work will be lost. Windows system processes are not targets.'
$form.Controls.Add($intro)

$appList = New-Object System.Windows.Forms.ListBox
$appList.Location = New-Object System.Drawing.Point(16, 68)
$appList.Size = New-Object System.Drawing.Size(438, 145)
$form.Controls.Add($appList)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Location = New-Object System.Drawing.Point(16, 230)
$refreshButton.Size = New-Object System.Drawing.Size(125, 34)
$refreshButton.Text = 'Refresh status'
$form.Controls.Add($refreshButton)

$analyzeButton = New-Object System.Windows.Forms.Button
$analyzeButton.Location = New-Object System.Drawing.Point(151, 230)
$analyzeButton.Size = New-Object System.Drawing.Size(125, 34)
$analyzeButton.Text = 'Analyze PC'
$form.Controls.Add($analyzeButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Location = New-Object System.Drawing.Point(329, 230)
$closeButton.Size = New-Object System.Drawing.Size(125, 34)
$closeButton.Text = 'Close listed apps'
$form.Controls.Add($closeButton)

$refreshList = {
    $appList.Items.Clear()
    foreach ($name in $script:AllowedProcessNames) {
        $running = @(Get-Process -Name $name -ErrorAction SilentlyContinue).Count
        [void]$appList.Items.Add(("{0}.exe - {1} running" -f $name, $running))
    }
    if ($script:AllowedProcessNames.Count -eq 0) {
        [void]$appList.Items.Add('No apps configured. Edit $AllowedProcessNames in this script.')
    }
}

$refreshButton.Add_Click($refreshList)
$analyzeButton.Add_Click({
    $analysisForm = New-Object System.Windows.Forms.Form
    $analysisForm.Text = 'Running process analyzer'
    $analysisForm.StartPosition = 'CenterParent'
    $analysisForm.ClientSize = New-Object System.Drawing.Size(980, 520)
    $analysisForm.FormBorderStyle = 'Sizable'

    $note = New-Object System.Windows.Forms.Label
    $note.Location = New-Object System.Drawing.Point(12, 10)
    $note.Size = New-Object System.Drawing.Size(760, 34)
    $note.Text = 'Preparing process analysis...'
    $analysisForm.Controls.Add($note)

    $processProgress = New-Object System.Windows.Forms.ProgressBar
    $processProgress.Location = New-Object System.Drawing.Point(780, 10)
    $processProgress.Size = New-Object System.Drawing.Size(182, 24)
    $processProgress.Style = 'Marquee'
    $processProgress.MarqueeAnimationSpeed = 25
    $analysisForm.Controls.Add($processProgress)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(12, 58)
    $grid.Size = New-Object System.Drawing.Size(950, 397)
    $grid.Anchor = 'Top,Bottom,Left,Right'
    $grid.AllowUserToAddRows = $false
    $grid.ReadOnly = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.AutoGenerateColumns = $false
    $grid.Columns.Add((New-Object System.Windows.Forms.DataGridViewCheckBoxColumn -Property @{Name='Select'; HeaderText='Stop'; Width=45})) | Out-Null
    foreach ($column in @(
        @{Name='Process'; HeaderText='Process'; Width=150},
        @{Name='PID'; HeaderText='PID'; Width=65},
        @{Name='Category'; HeaderText='Category'; Width=145},
        @{Name='Reason'; HeaderText='Why'; Width=230},
        @{Name='Path'; HeaderText='Executable path'; Width=500}
    )) {
        $grid.Columns.Add((New-Object System.Windows.Forms.DataGridViewTextBoxColumn -Property $column)) | Out-Null
    }
    $analysisForm.Controls.Add($grid)
    $grid.Visible = $false

    $scanButton = New-Object System.Windows.Forms.Button
    $scanButton.Location = New-Object System.Drawing.Point(12, 470)
    $scanButton.Size = New-Object System.Drawing.Size(110, 32)
    $scanButton.Anchor = 'Bottom,Left'
    $scanButton.Text = 'Scan again'
    $analysisForm.Controls.Add($scanButton)

    $stopSelectedButton = New-Object System.Windows.Forms.Button
    $stopSelectedButton.Location = New-Object System.Drawing.Point(820, 470)
    $stopSelectedButton.Size = New-Object System.Drawing.Size(142, 32)
    $stopSelectedButton.Anchor = 'Bottom,Right'
    $stopSelectedButton.Text = 'Force stop selected'
    $analysisForm.Controls.Add($stopSelectedButton)

    $catalogueButton = New-Object System.Windows.Forms.Button
    $catalogueButton.Location = New-Object System.Drawing.Point(130, 470)
    $catalogueButton.Size = New-Object System.Drawing.Size(145, 32)
    $catalogueButton.Anchor = 'Bottom,Left'
    $catalogueButton.Text = 'Analyze CSV catalog'
    $analysisForm.Controls.Add($catalogueButton)

    $catalogueButton.Add_Click({
        $catalogueForm = New-Object System.Windows.Forms.Form
        $catalogueForm.Text = 'CSV software catalog analysis'
        $catalogueForm.StartPosition = 'CenterParent'
        $catalogueForm.ClientSize = New-Object System.Drawing.Size(900, 600)
        $catalogueForm.FormBorderStyle = 'Sizable'

        $catalogueStatus = New-Object System.Windows.Forms.Label
        $catalogueStatus.Location = New-Object System.Drawing.Point(12, 12)
        $catalogueStatus.Size = New-Object System.Drawing.Size(700, 24)
        $catalogueStatus.Text = 'Scanning CSV and taking one WinGet inventory snapshot...'
        $catalogueForm.Controls.Add($catalogueStatus)

        $catalogueProgress = New-Object System.Windows.Forms.ProgressBar
        $catalogueProgress.Location = New-Object System.Drawing.Point(720, 12)
        $catalogueProgress.Size = New-Object System.Drawing.Size(168, 24)
        $catalogueProgress.Style = 'Marquee'
        $catalogueProgress.MarqueeAnimationSpeed = 25
        $catalogueForm.Controls.Add($catalogueProgress)

        $catalogueGrid = New-Object System.Windows.Forms.DataGridView
        $catalogueGrid.Location = New-Object System.Drawing.Point(12, 48)
        $catalogueGrid.Size = New-Object System.Drawing.Size(876, 484)
        $catalogueGrid.Anchor = 'Top,Bottom,Left,Right'
        $catalogueGrid.ReadOnly = $true
        $catalogueGrid.AllowUserToAddRows = $false
        $catalogueGrid.AutoGenerateColumns = $false
        foreach ($column in @(
            @{Name='PackageId'; HeaderText='Package ID'; Width=310},
            @{Name='CatalogueVersion'; HeaderText='Catalog version'; Width=115},
            @{Name='Status'; HeaderText='Status'; Width=110},
            @{Name='WinGetResult'; HeaderText='WinGet inventory match'; Width=500}
        )) {
            $catalogueGrid.Columns.Add((New-Object System.Windows.Forms.DataGridViewTextBoxColumn -Property $column)) | Out-Null
        }
        $catalogueForm.Controls.Add($catalogueGrid)

        $runningButton = New-Object System.Windows.Forms.Button
        $runningButton.Location = New-Object System.Drawing.Point(12, 545)
        $runningButton.Size = New-Object System.Drawing.Size(190, 32)
        $runningButton.Anchor = 'Bottom,Left'
        $runningButton.Text = 'Find running catalog apps'
        $catalogueForm.Controls.Add($runningButton)

        $runningButton.Add_Click({
            $matches = @(Get-CatalogueRunningProcesses)
            if ($matches.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show('No running process could be matched confidently to a catalog package. Matching uses executable names and known aliases.', 'No catalog apps found') | Out-Null
                return
            }

            $runningForm = New-Object System.Windows.Forms.Form
            $runningForm.Text = 'Running catalog apps'
            $runningForm.StartPosition = 'CenterParent'
            $runningForm.ClientSize = New-Object System.Drawing.Size(760, 360)
            $runningForm.FormBorderStyle = 'Sizable'

            $runningGrid = New-Object System.Windows.Forms.DataGridView
            $runningGrid.Location = New-Object System.Drawing.Point(12, 12)
            $runningGrid.Size = New-Object System.Drawing.Size(736, 292)
            $runningGrid.Anchor = 'Top,Bottom,Left,Right'
            $runningGrid.AllowUserToAddRows = $false
            $runningGrid.AutoGenerateColumns = $false
            $runningGrid.SelectionMode = 'FullRowSelect'
            $runningGrid.Columns.Add((New-Object System.Windows.Forms.DataGridViewCheckBoxColumn -Property @{Name='Select'; HeaderText='Stop'; Width=50})) | Out-Null
            foreach ($column in @(
                @{Name='Process'; HeaderText='Process'; Width=180},
                @{Name='PID'; HeaderText='PID'; Width=70},
                @{Name='PackageId'; HeaderText='Catalog package'; Width=300},
                @{Name='Version'; HeaderText='Version'; Width=110}
            )) {
                $runningGrid.Columns.Add((New-Object System.Windows.Forms.DataGridViewTextBoxColumn -Property $column)) | Out-Null
            }
            foreach ($match in $matches) {
                $index = $runningGrid.Rows.Add($false, $match.Process, $match.PID, $match.PackageId, $match.Version)
                $runningGrid.Rows[$index].Tag = $match
            }
            $runningForm.Controls.Add($runningGrid)

            $forceButton = New-Object System.Windows.Forms.Button
            $forceButton.Location = New-Object System.Drawing.Point(590, 320)
            $forceButton.Size = New-Object System.Drawing.Size(158, 32)
            $forceButton.Anchor = 'Bottom,Right'
            $forceButton.Text = 'Force stop selected'
            $runningForm.Controls.Add($forceButton)
            $forceButton.Add_Click({
                $selectedRows = @($runningGrid.Rows | Where-Object { $_.Cells['Select'].Value -eq $true })
                if ($selectedRows.Count -eq 0) {
                    [System.Windows.Forms.MessageBox]::Show('Select one or more running catalog apps first.', 'Nothing selected') | Out-Null
                    return
                }
                $names = @($selectedRows | ForEach-Object { '{0} (PID {1})' -f $_.Tag.Process, $_.Tag.PID })
                $answer = [System.Windows.Forms.MessageBox]::Show(
                    "Force stop these catalog apps?`n`n$($names -join "`n")`n`nUnsaved work may be lost.",
                    'Confirm force stop',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
                $stopped = 0
                foreach ($row in $selectedRows) {
                    try { Stop-Process -Id ([int]$row.Tag.PID) -Force -ErrorAction Stop; $stopped++ } catch { }
                }
                [System.Windows.Forms.MessageBox]::Show("Force stopped: $stopped", 'Complete') | Out-Null
                $runningForm.Close()
            }.GetNewClosure())
            [void]$runningForm.ShowDialog($catalogueForm)
        }.GetNewClosure())

        $worker = New-Object System.ComponentModel.BackgroundWorker
        $worker.WorkerReportsProgress = $false
        $worker.add_DoWork({
            param($sender, $eventArgs)
            try {
                $catalogueRows = @(Get-CatalogueAnalysis)
                $eventArgs.Result = ConvertTo-Json -InputObject $catalogueRows -Compress -Depth 4
            }
            catch {
                $eventArgs.Result = $_.Exception.Message
            }
        }.GetNewClosure())
        $worker.add_RunWorkerCompleted({
            param($sender, $eventArgs)
            $catalogueProgress.Style = 'Continuous'
            $catalogueProgress.Value = 100
            if ($eventArgs.Result -is [string]) {
                $catalogueStatus.Text = 'Scan failed.'
                [System.Windows.Forms.MessageBox]::Show($eventArgs.Result, 'Catalog scan failed') | Out-Null
                return
            }
            $catalogueRows = @(ConvertFrom-Json -InputObject ([string]$eventArgs.Result) | ForEach-Object { $_ })
            while ($catalogueRows.Count -eq 1 -and $catalogueRows[0] -is [array]) {
                $catalogueRows = @($catalogueRows[0])
            }
            $validCatalogueRows = @($catalogueRows | Where-Object { $_ -and $_.PSObject.Properties['PackageId'] })
            if ($validCatalogueRows.Count -eq 0) {
                $cataloguePath = Join-Path $PSScriptRoot 'catalogue_logiciels.csv'
                $catalogueRows = @(Import-Csv -LiteralPath $cataloguePath | ForEach-Object {
                    [pscustomobject]@{
                        PackageId = $_.PackageId
                        CatalogueVersion = $_.Version
                        Status = 'Not checked'
                        WinGetResult = 'CSV entry loaded; WinGet result unavailable'
                    }
                })
            }
            else {
                $catalogueRows = $validCatalogueRows
            }
            $catalogueGrid.Rows.Clear()
            foreach ($row in $catalogueRows) {
                $index = $catalogueGrid.Rows.Add($row.PackageId, $row.CatalogueVersion, $row.Status, $row.WinGetResult)
                if ($row.Status -eq 'Installed') {
                    $catalogueGrid.Rows[$index].DefaultCellStyle.BackColor = [System.Drawing.Color]::Honeydew
                }
            }
            $catalogueStatus.Text = "Catalog loaded: $($catalogueRows.Count) entries. Use the running-apps button to find active matches."
        }.GetNewClosure())
        $catalogueForm.Add_Shown({
            if (-not $worker.IsBusy) { $worker.RunWorkerAsync() }
        }.GetNewClosure())
        $catalogueForm.Add_FormClosing({
            if ($worker.IsBusy) {
                $_.Cancel = $true
                $catalogueStatus.Text = 'Scan is still running. Please wait for it to finish.'
            }
        }.GetNewClosure())
        [void]$catalogueForm.ShowDialog($analysisForm)
    })

    $loadingForm = New-Object System.Windows.Forms.Form
    $loadingForm.Text = 'Analyzing PC'
    $loadingForm.StartPosition = 'CenterParent'
    $loadingForm.ClientSize = New-Object System.Drawing.Size(430, 125)
    $loadingForm.FormBorderStyle = 'FixedDialog'
    $loadingForm.ControlBox = $false

    $loadingTitle = New-Object System.Windows.Forms.Label
    $loadingTitle.Location = New-Object System.Drawing.Point(18, 16)
    $loadingTitle.Size = New-Object System.Drawing.Size(394, 24)
    $loadingTitle.Text = 'Analyzing running programs...'
    $loadingForm.Controls.Add($loadingTitle)

    $loadingProgress = New-Object System.Windows.Forms.ProgressBar
    $loadingProgress.Location = New-Object System.Drawing.Point(18, 48)
    $loadingProgress.Size = New-Object System.Drawing.Size(394, 24)
    $loadingProgress.Style = 'Marquee'
    $loadingProgress.MarqueeAnimationSpeed = 25
    $loadingForm.Controls.Add($loadingProgress)

    $loadingDetail = New-Object System.Windows.Forms.Label
    $loadingDetail.Location = New-Object System.Drawing.Point(18, 82)
    $loadingDetail.Size = New-Object System.Drawing.Size(394, 24)
    $loadingDetail.Text = 'Checking processes and signatures...'
    $loadingForm.Controls.Add($loadingDetail)

    $scanWorker = $null
    $scanState = @{
        Grid = $grid
        Note = $note
        ProcessProgress = $processProgress
        ScanButton = $scanButton
        StopSelectedButton = $stopSelectedButton
        CatalogueButton = $catalogueButton
        LoadingForm = $loadingForm
        LoadingProgress = $loadingProgress
        LoadingDetail = $loadingDetail
    }
    $global:AnalyzerState = $scanState
    $global:ProcessScanJson = '[]'
    $scan = {
        if ($scanWorker -and $scanWorker.IsBusy) { return }
        $global:AnalyzerState.Grid.Rows.Clear()
        $global:AnalyzerState.Grid.Visible = $false
        $global:AnalyzerState.ProcessProgress.Visible = $true
        $global:AnalyzerState.ProcessProgress.Style = 'Marquee'
        $global:AnalyzerState.ScanButton.Enabled = $false
        $global:AnalyzerState.StopSelectedButton.Enabled = $false
        $global:AnalyzerState.CatalogueButton.Enabled = $false
        $global:AnalyzerState.Note.Text = 'Analyzing processes and checking signatures...'

        $scanWorker = New-Object System.ComponentModel.BackgroundWorker
        $scanWorker.add_DoWork({
            param($sender, $eventArgs)
            try {
                $rows = @(Get-ProcessAnalysis)
                $global:ProcessScanJson = ConvertTo-Json -InputObject $rows -Compress -Depth 4
                $eventArgs.Result = $null
            }
            catch {
                $eventArgs.Result = $_.Exception.Message
            }
        }.GetNewClosure())
        $scanWorker.add_RunWorkerCompleted({
            param($sender, $eventArgs)
            $global:AnalyzerState.ScanButton.Enabled = $true
            $global:AnalyzerState.StopSelectedButton.Enabled = $true
            $global:AnalyzerState.CatalogueButton.Enabled = $true
            $global:AnalyzerState.LoadingProgress.Style = 'Continuous'
            $global:AnalyzerState.LoadingProgress.Value = 100
            $global:AnalyzerState.LoadingDetail.Text = 'Analysis complete: 100%'
            $global:AnalyzerState.ProcessProgress.Style = 'Continuous'
            $global:AnalyzerState.ProcessProgress.Value = 100
            if ($eventArgs.Result -is [string]) {
                $global:AnalyzerState.Note.Text = 'Process scan failed.'
                $global:AnalyzerState.LoadingDetail.Text = 'Analysis failed.'
                [System.Windows.Forms.MessageBox]::Show($eventArgs.Result, 'Process scan failed') | Out-Null
                $global:AnalyzerState.LoadingForm.Close()
                return
            }
            $processResults = @(ConvertFrom-Json -InputObject $global:ProcessScanJson | ForEach-Object { $_ })
            $validResults = @($processResults | Where-Object { $_ -and $_.PSObject.Properties['Process'] })
            if ($validResults.Count -eq 0) {
                $processResults = @(Get-Process -ErrorAction SilentlyContinue | Sort-Object ProcessName | ForEach-Object {
                    [pscustomobject]@{
                        Process = $_.ProcessName
                        PID = $_.Id
                        Category = 'Unknown / review'
                        Reason = 'Basic process listing; detailed scan data unavailable'
                        Path = ''
                    }
                })
            }
            else {
                $processResults = $validResults
            }
            foreach ($row in $processResults) {
                $index = $global:AnalyzerState.Grid.Rows.Add($false, $row.Process, $row.PID, $row.Category, $row.Reason, $row.Path)
                $global:AnalyzerState.Grid.Rows[$index].Tag = $row
                if ($row.Category -eq 'Windows system' -or $protectedProcessNames -contains $row.Process) {
                    $global:AnalyzerState.Grid.Rows[$index].Cells['Select'].ReadOnly = $true
                    $global:AnalyzerState.Grid.Rows[$index].Cells['Select'].Value = $false
                    $global:AnalyzerState.Grid.Rows[$index].DefaultCellStyle.BackColor = [System.Drawing.Color]::Gainsboro
                }
            }
            $global:AnalyzerState.Grid.Visible = $true
            $global:AnalyzerState.Note.Text = "Process scan complete: $($processResults.Count) running processes reviewed."
            $global:AnalyzerState.LoadingForm.Close()
        }.GetNewClosure())
        $scanWorker.RunWorkerAsync()
    }
    $scan = $scan.GetNewClosure()

    $scanButton.Add_Click($scan.GetNewClosure())
    $stopSelectedButton.Add_Click({
        $selected = @($grid.Rows | Where-Object { $_.Cells['Select'].Value -eq $true -and $_.Tag.Category -ne 'Windows system' -and $protectedProcessNames -notcontains $_.Tag.Process })
        if ($selected.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('Select one or more non-system processes first.', 'Nothing selected') | Out-Null
            return
        }
        $names = @($selected | ForEach-Object { '{0} (PID {1})' -f $_.Tag.Process, $_.Tag.PID })
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "Force stop these selected processes?`n`n$($names -join "`n")`n`nUnsaved work may be lost.",
            'Confirm selected force stop',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $stopped = 0
        foreach ($row in $selected) {
            try { Stop-Process -Id ([int]$row.Tag.PID) -Force -ErrorAction Stop; $stopped++ } catch { }
        }
        [System.Windows.Forms.MessageBox]::Show("Force stopped: $stopped", 'Complete') | Out-Null
        & $scan
    })

    $loadingForm.Add_Shown({ & $scan }.GetNewClosure())
    [void]$loadingForm.ShowDialog($form)
    [void]$analysisForm.ShowDialog($form)
})
$closeButton.Add_Click({
    if ($script:AllowedProcessNames.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('No apps are configured.', 'Nothing to close') | Out-Null
        return
    }

    $answer = [System.Windows.Forms.MessageBox]::Show(
        ("FORCE STOP all running processes named {0}?`n`nThis closes them immediately and unsaved work may be lost." -f ($script:AllowedProcessNames -join ', ')),
        'Confirm force stop',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $stopped = 0
    $failed = 0
    foreach ($name in $script:AllowedProcessNames) {
        foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                $stopped++
            }
            catch {
                # A process may exit during enumeration or require higher rights.
                $failed++
            }
        }
    }

    [System.Windows.Forms.MessageBox]::Show(
        "Processes stopped: $stopped`nCould not stop: $failed`n`nSome protected processes may require permissions this tool does not request.",
        'Force stop complete',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    & $refreshList
})

& $refreshList
[void]$form.ShowDialog()