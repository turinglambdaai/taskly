$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$output = Join-Path $repo '.rivet\acceptance\windows'
$executable = Get-ChildItem -LiteralPath (Join-Path $repo 'dist') `
    -Filter RivetHost.exe -File -Recurse |
    Where-Object { $_.FullName -match 'taskly-windows-[^\\]+\\RivetHost\.exe$' } |
    Select-Object -First 1
if (-not $executable) { throw 'packaged Taskly executable was not found' }

New-Item -ItemType Directory -Force -Path $output | Out-Null
$testHome = Join-Path $output ("home-{0}" -f $PID)
$tasklyHome = Join-Path $testHome '.taskly'
New-Item -ItemType Directory -Force -Path $tasklyHome | Out-Null
$epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
@"
# Taskly acceptance profile
language = en
close-to-tray = 0
last-selected-list-id = 0
last-update-check = $epoch
"@ | Set-Content -LiteralPath (Join-Path $tasklyHome 'config.ini') -Encoding utf8

function Wait-Until {
    param([string]$Description, [scriptblock]$Probe, [int]$TimeoutSeconds = 30)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $value = & $Probe
        if ($null -ne $value -and $value -ne $false) { return $value }
        Start-Sleep -Milliseconds 100
    }
    throw "timed out waiting for $Description"
}

function Find-ById {
    param($Root, [string]$AutomationId)
    $condition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
        $AutomationId)
    $Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

function Find-ByName {
    param($Root, [string]$Name)
    $condition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    $Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

function Capture-Screen {
    param([string]$Path)
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$oldHome = $env:HOME
$oldProfile = $env:USERPROFILE
$process = $null
try {
    $env:HOME = $testHome
    $env:USERPROFILE = $testHome
    $process = Start-Process -FilePath $executable.FullName -PassThru `
        -RedirectStandardOutput (Join-Path $output 'application.stdout.log') `
        -RedirectStandardError (Join-Path $output 'application.stderr.log')

    $desktop = [System.Windows.Automation.AutomationElement]::RootElement
    $window = Wait-Until 'Taskly window' {
        $condition = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
            $process.Id)
        $desktop.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
    }
    $quickAdd = Wait-Until 'quick-add field' { Find-ById $window 'quick-add' }
    $submit = Wait-Until 'quick-add submit button' { Find-ById $window 'quick-add-submit' }
    $quickAdd.GetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern).SetValue('Acceptance task')
    $submit.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    [void](Wait-Until 'RPC-created task row' { Find-ByName $window 'Acceptance task' })

    $checkbox = Wait-Until 'task completion control' {
        Find-ById $window 'task-complete-1'
    }
    $checkbox.GetCurrentPattern(
        [System.Windows.Automation.TogglePattern]::Pattern).Toggle()
    [void](Wait-Until 'changed Event reflected in the active view' {
        if ($null -eq (Find-ByName $window 'Acceptance task')) { return $true }
        return $false
    })

    $nodes = $window.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    $snapshot = for ($index = 0; $index -lt [Math]::Min($nodes.Count, 500); $index++) {
        $node = $nodes[$index]
        [ordered]@{
            name = $node.Current.Name
            controlType = $node.Current.ControlType.ProgrammaticName
            automationId = $node.Current.AutomationId
        }
    }
    $snapshot | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath (Join-Path $output 'accessibility.json') -Encoding utf8
    Capture-Screen (Join-Path $output 'screen.png')

    $window.GetCurrentPattern(
        [System.Windows.Automation.WindowPattern]::Pattern).Close()
    [void](Wait-Until 'orderly process exit' {
        $process.Refresh()
        if ($process.HasExited) { return $true }
        return $false
    } 15)

    [ordered]@{
        platform = 'windows'
        artifact = $executable.FullName
        actions = @('set:quick-add', 'invoke:quick-add-submit', 'toggle:task-complete-1')
        assertions = @(
            'packaged WinUI window activated',
            'stable UI Automation identifiers exposed',
            'RPC-created task appeared',
            'changed Event removed the completed task from the active view',
            'native window close stopped the process'
        )
    } | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $output 'interaction-trace.json') -Encoding utf8
} finally {
    try { Capture-Screen (Join-Path $output 'screen-final.png') } catch {}
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit()
    }
    if ($process) { $process.Dispose() }
    $env:HOME = $oldHome
    $env:USERPROFILE = $oldProfile
}
