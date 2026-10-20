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

    # Regression: a task entered in 生活 must stay in 生活, not the
    # database's first/default list 工作. These are the shipped default
    # list names, from racket/taskly/model.rkt. The disposable acceptance
    # profile guarantees default-list id 1 and the new 生活 list id 2.
    $createList = Wait-Until 'create-list control' { Find-ById $window 'create-list' }
    $createList.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $nameInput = Wait-Until 'new-list input' { Find-ById $window 'prompt-input' }
    $nameInput.GetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern).SetValue('生活')
    $confirm = Wait-Until 'new-list confirmation' { Find-ByName $window 'OK' }
    $confirm.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()

    function Select-TaskList {
        param([int]$ListId, [string]$Name)
        # WinUI's inner Grid is not a ControlView automation peer (verified
        # against the failing packaged Windows screenshot). Resolve the
        # displayed TextBlock instead, then select its ListViewItem parent.
        $label = Wait-Until ("visible list: {0}" -f $Name) {
            $found = Find-ById $window ("list-name-{0}" -f $ListId)
            if ($null -eq $found) { $found = Find-ByName $window $Name }
            return $found
        }
        $item = $label
        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        while ($null -ne $item -and
               $item.Current.ControlType -ne [System.Windows.Automation.ControlType]::ListItem) {
            $item = $walker.GetParent($item)
        }
        if ($null -eq $item) { throw ("no selectable list item for {0}" -f $Name) }
        $item.GetCurrentPattern(
            [System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    }

    $paneTitle = Wait-Until 'active view label' {
        Find-ById $window 'current-view-title'
    }
    Select-TaskList 2 '生活'
    [void](Wait-Until '生活 view selected' {
        if ($paneTitle.Current.Name -eq '生活') { return $true }
        return $false
    })
    $plainTask = 'Life-only task without due date or notes'
    $quickAdd.GetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern).SetValue($plainTask)
    $quickAdd.SetFocus()
    # Exercise the actual Enter key, not only the plus-button click.
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')

    $titleText = Wait-Until 'task saved under 生活' {
        Find-ByName $window $plainTask
    }
    # Layout assertions use the text and native checkbox peers: a Grid
    # itself is not reliably exposed in WinUI UIA's ControlView.
    $plainCheck = Wait-Until 'new task checkbox' {
        Find-ById $window 'task-complete-2'
    }
    # Both elements share the row's first Grid row; the title must
    # visually align with the native checkbox for a metadata-free task.
    $checkBoxBounds = $plainCheck.Current.BoundingRectangle
    $titleBounds = $titleText.Current.BoundingRectangle
    $centerDiff = [Math]::Abs(
        ($checkBoxBounds.Top + $checkBoxBounds.Height / 2) -
        ($titleBounds.Top + $titleBounds.Height / 2))
    $limit = [Math]::Max(8.0, $checkBoxBounds.Height / 4)
    if ($centerDiff -gt $limit) {
        throw ("plain task title and checkbox are misaligned by {0:N1}px" -f $centerDiff)
    }

    $taskList = Wait-Until 'extended task list' {
        Find-ById $window 'task-list'
    }
    $selection = $taskList.GetCurrentPattern(
        [System.Windows.Automation.SelectionPattern]::Pattern)
    if (-not $selection.Current.CanSelectMultiple) {
        throw 'Windows task list must support Ctrl/Shift multi-selection'
    }

    Select-TaskList 1 '工作'
    [void](Wait-Until '工作 view selected' {
        if ($paneTitle.Current.Name -eq '工作') { return $true }
        return $false
    })
    [void](Wait-Until '生活 task absent from 工作' {
        if ($null -eq (Find-ByName $window $plainTask)) { return $true }
        return $false
    })
    Select-TaskList 2 '生活'
    [void](Wait-Until '生活 task remains in 生活' {
        if ($paneTitle.Current.Name -eq '生活' -and
            $null -ne (Find-ByName $window $plainTask)) { return $true }
        return $false
    })

    # Search is global, even while 生活 is selected. A result must
    # display its owning list, never appear as an unlabeled local row.
    $searchBox = Wait-Until 'search box' { Find-ById $window 'task-search' }
    $searchBox.GetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern).SetValue($plainTask)
    $owner = Wait-Until 'search result list owner' {
        Find-ById $window 'task-owner-2'
    }
    if ($owner.Current.Name -ne '生活') {
        throw ("search result claims wrong owner: {0}" -f $owner.Current.Name)
    }
    $searchBox.GetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern).SetValue('')
    [void](Wait-Until 'search cleared' {
        if ($null -eq (Find-ById $window 'task-owner-2')) { return $true }
        return $false
    })

    # Native multi-selection must drive real batch completion, not only
    # report a selection capability through UI Automation.
    $secondLife = 'Second Life batch task'
    $quickAdd.GetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern).SetValue($secondLife)
    $quickAdd.SetFocus()
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    [void](Wait-Until 'second task saved under 生活' {
        Find-ByName $window $secondLife
    })
    function Select-TaskForBatch {
        param([string]$Title, [bool]$Append)
        $label = Wait-Until ("task label: {0}" -f $Title) {
            Find-ByName $window $Title
        }
        $item = $label
        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        while ($null -ne $item -and
               $item.Current.ControlType -ne [System.Windows.Automation.ControlType]::ListItem) {
            $item = $walker.GetParent($item)
        }
        if ($null -eq $item) { throw ("missing task row for {0}" -f $Title) }
        $pattern = $item.GetCurrentPattern(
            [System.Windows.Automation.SelectionItemPattern]::Pattern)
        if ($Append) { $pattern.AddToSelection() } else { $pattern.Select() }
    }
    Select-TaskForBatch $plainTask $false
    Select-TaskForBatch $secondLife $true
    $batchComplete = Wait-Until 'multi-selection action bar' {
        Find-ById $window 'bulk-complete'
    }
    $batchSchedule = Wait-Until 'multi-selection scheduling action' {
        Find-ById $window 'bulk-schedule'
    }
    if (-not $batchSchedule.Current.IsEnabled) {
        throw 'batch scheduling is disabled for two selected tasks'
    }
    $batchComplete.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    [void](Wait-Until 'both selected tasks completed by a single command' {
        if ($null -eq (Find-ByName $window $plainTask) -and
            $null -eq (Find-ByName $window $secondLife)) { return $true }
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
        actions = @('set:quick-add', 'invoke:quick-add-submit', 'toggle:task-complete-1', 'create-list:生活', 'select-list:2', 'enter:quick-add', 'select-list:1', 'select-list:2')
        assertions = @(
            'packaged WinUI window activated',
            'stable UI Automation identifiers exposed',
            'RPC-created task appeared',
            'changed Event removed the completed task from the active view',
            'new task submitted by Enter is owned by 生活, not 工作',
            'task checkbox and plain-text title are vertically aligned',
            'Windows task list exposes native multiple selection',
            'view switches preserve task list ownership',
            'global search shows the real owning list for every task',
            'Ctrl/Shift multi-selection completes two tasks in one command',
            'batch scheduling is visible and enabled when multiple tasks are selected',
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
