$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$output = Join-Path $repo '.rivet\acceptance\windows'
$installRecordPath = Join-Path $output 'installed-app.json'
$installRecord = if (Test-Path -LiteralPath $installRecordPath) {
    Get-Content -LiteralPath $installRecordPath -Raw | ConvertFrom-Json
} else { $null }
$executable = if ($installRecord) {
    Get-Item -LiteralPath ([string]$installRecord.executable)
} else {
    Get-ChildItem -LiteralPath (Join-Path $repo 'dist') `
        -Filter RivetHost.exe -File -Recurse |
        Where-Object { $_.FullName -match 'taskly-windows-[^\\]+\\RivetHost\.exe$' } |
        Select-Object -First 1
}
if (-not $executable) { throw 'packaged Taskly executable was not found' }
$expectedInstallFlavor = if ($installRecord) { 'msi' } else { 'zip' }

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
    param([string]$Description, [scriptblock]$Probe, [int]$TimeoutSeconds = 60)
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
$restartProcess = $null
$scenarioComplete = $false
try {
    $env:HOME = $testHome
    $env:USERPROFILE = $testHome
    $process = Start-Process -FilePath $executable.FullName -PassThru `
        -RedirectStandardOutput (Join-Path $output 'application.stdout.log') `
        -RedirectStandardError (Join-Path $output 'application.stderr.log')

    $desktop = [System.Windows.Automation.AutomationElement]::RootElement
    $window = Wait-Until 'Taskly window' {
        # An early process exit is a startup failure, not slow UI automation.
        $process.Refresh()
        if ($process.HasExited) {
            throw ('Taskly exited before creating a window (PID {0}, exit code {1})' -f $process.Id, $process.ExitCode)
        }
        $condition = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
            $process.Id)
        $desktop.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
    }
    $windowBounds = $window.Current.BoundingRectangle
    $screen = [System.Windows.Forms.Screen]::FromHandle(
        [IntPtr]$window.Current.NativeWindowHandle)
    $workArea = $screen.WorkingArea
    $edgeTolerance = 2
    if ($windowBounds.Left -lt ($workArea.Left - $edgeTolerance) -or
        $windowBounds.Top -lt ($workArea.Top - $edgeTolerance) -or
        $windowBounds.Right -gt ($workArea.Right + $edgeTolerance) -or
        $windowBounds.Bottom -gt ($workArea.Bottom + $edgeTolerance)) {
        throw ('Taskly window {0} is outside monitor work area {1}' -f
            $windowBounds, $workArea)
    }
    $quickAdd = Wait-Until 'quick-add field' { Find-ById $window 'quick-add' }
    $submit = Wait-Until 'quick-add submit button' { Find-ById $window 'quick-add-submit' }
    # The native window becomes automatable before the embedded backend has
    # opened its database. Clicking during that interval intentionally keeps
    # the draft unsent, so wait for the product's real readiness signal.
    [void](Wait-Until 'database connection' { Find-ByName $window 'Database Connected' })
    [void](Wait-Until "$expectedInstallFlavor install flavor persisted" {
        if ((Get-Content -LiteralPath (Join-Path $tasklyHome 'config.ini') -Raw) `
                -match "(?m)^install-flavor = $expectedInstallFlavor$") { return $true }
        return $false
    })
    [void](Wait-Until 'actionable first-run empty state' {
        Find-ByName $window 'Add your first task above — try “Plan tomorrow”'
    })
    foreach ($view in @('today', 'planned', 'all', 'completed')) {
        $count = Wait-Until ("visible zero count for {0}" -f $view) {
            $candidate = Find-ById $window ("smart-count-{0}" -f $view)
            if ($null -ne $candidate -and $candidate.Current.Name -eq '0') {
                return $candidate
            }
            return $null
        }
    }
    $quickAdd.GetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern).SetValue('Acceptance task')
    $submit.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    [void](Wait-Until 'quick-add submission' {
        $quickAdd.GetCurrentPattern(
            [System.Windows.Automation.ValuePattern]::Pattern).Current.Value -eq ''
    })
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

    # Task details must expand in place. A modal PromptAsync text box is not
    # acceptable here because it cannot edit notes/date/time and breaks the
    # Reminders-style Return/Esc flow.
    $taskInfo = Wait-Until 'inline task details button' {
        Find-ById $window 'task-info-2'
    }
    $taskInfo.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $inlineTitle = Wait-Until 'inline task title editor' {
        Find-ById $window 'inline-task-title-2'
    }
    if ($null -ne (Find-ById $window 'prompt-input')) {
        throw 'task details opened the legacy PromptAsync dialog'
    }
    $inlineTitle.GetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern).SetValue('Cancelled inline draft')
    $inlineTitle.SetFocus()
    [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
    [void](Wait-Until 'Escape cancelled inline task draft' {
        if ($null -eq (Find-ById $window 'inline-task-title-2') -and
            $null -ne (Find-ByName $window $plainTask)) { return $true }
        return $false
    })
    $taskInfo = Wait-Until 'reopen inline task details after cancel' {
        Find-ById $window 'task-info-2'
    }
    $taskInfo.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $inlineTitle = Wait-Until 'inline task title editor after cancel' {
        Find-ById $window 'inline-task-title-2'
    }
    $inlineNotes = Wait-Until 'inline task notes editor' {
        Find-ById $window 'inline-task-notes-2'
    }
    $inlineDate = Wait-Until 'inline task date editor' {
        Find-ById $window 'inline-task-date-2'
    }
    $inlineTime = Wait-Until 'inline task time editor' {
        Find-ById $window 'inline-task-time-2'
    }
    $inlineDateMenu = Wait-Until 'compact inline date action' {
        Find-ById $window 'inline-task-date-menu-2'
    }
    $inlineList = Wait-Until 'compact inline list action' {
        Find-ById $window 'inline-task-list-2'
    }
    $inlineSave = Wait-Until 'visible inline save action' {
        Find-ById $window 'inline-task-save-2'
    }
    $inlineCancel = Wait-Until 'visible inline cancel action' {
        Find-ById $window 'inline-task-cancel-2'
    }
    $compactHeightLimit = [Math]::Max(
        $inlineTitle.Current.BoundingRectangle.Height,
        $inlineNotes.Current.BoundingRectangle.Height) * 1.25
    foreach ($control in @($inlineDateMenu, $inlineDate, $inlineTime, $inlineList)) {
        if ($control.Current.IsOffscreen -or
            $control.Current.BoundingRectangle.Height -gt $compactHeightLimit) {
            throw 'inline task secondary actions are not visible and compact'
        }
        if ([string]::IsNullOrWhiteSpace($control.Current.Name)) {
            throw 'inline task secondary action is missing an accessible name'
        }
    }
    if ($inlineNotes.Current.BoundingRectangle.Top -lt
            $inlineTitle.Current.BoundingRectangle.Top -or
        $inlineDateMenu.Current.BoundingRectangle.Top -lt
            $inlineNotes.Current.BoundingRectangle.Top) {
        throw 'inline task editor hierarchy must be title, notes, then details'
    }

    $inlineDateMenu.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $inlineCalendar = Wait-Until 'native inline calendar picker' {
        Find-ById $window 'inline-task-calendar-2'
    }
    if ($inlineCalendar.Current.IsOffscreen) {
        throw 'inline task calendar picker opened offscreen'
    }
    [System.Windows.Forms.SendKeys]::SendWait('{ESC}')

    # The visual order and keyboard order are identical: title first, quieter
    # notes second, then the date/time/list action line.
    $inlineTitle.SetFocus()
    foreach ($expectedFocus in @(
            'inline-task-notes-2',
            'inline-task-date-menu-2',
            'inline-task-date-2',
            'inline-task-time-2',
            'inline-task-list-2')) {
        [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
        [void](Wait-Until ("inline editor Tab reaches {0}" -f $expectedFocus) {
            $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
            if ($null -ne $focused -and
                $focused.Current.AutomationId -eq $expectedFocus) {
                return $true
            }
            return $false
        })
    }
    $inlineTitle.SetFocus()
    $editedPlainTask = 'Life-only task edited inline'
    $editedNotes = 'Inline notes survive a changed-event refresh'
    $inlineTitle.GetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern).SetValue($editedPlainTask)
    $inlineNotes.GetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern).SetValue($editedNotes)
    $inlineDate.GetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern).SetValue('2099-12-31')
    $inlineTime.GetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern).SetValue('10:30')
    $inlineSave.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    [void](Wait-Until 'inline task edit persisted' {
        if ($null -ne (Find-ByName $window $editedPlainTask) -and
            $null -ne (Find-ById $window 'task-notes-2')) { return $true }
        return $false
    })
    $plainTask = $editedPlainTask

    # Reopen after the backend changed-event rebuild and verify every field
    # was read back from persistence, not merely retained in the visual tree.
    $taskInfo = Wait-Until 'reopen inline task details' {
        Find-ById $window 'task-info-2'
    }
    $taskInfo.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $persistedNotes = Wait-Until 'persisted inline notes' {
        Find-ById $window 'inline-task-notes-2'
    }
    $persistedDate = Wait-Until 'persisted inline date' {
        Find-ById $window 'inline-task-date-2'
    }
    $persistedTime = Wait-Until 'persisted inline time' {
        Find-ById $window 'inline-task-time-2'
    }
    if ($persistedNotes.GetCurrentPattern(
            [System.Windows.Automation.ValuePattern]::Pattern).Current.Value -ne $editedNotes -or
        $persistedDate.GetCurrentPattern(
            [System.Windows.Automation.ValuePattern]::Pattern).Current.Value -ne '2099-12-31' -or
        $persistedTime.GetCurrentPattern(
            [System.Windows.Automation.ValuePattern]::Pattern).Current.Value -ne '10:30') {
        throw 'inline task details were not persisted across the backend refresh'
    }
    $persistedCancel = Wait-Until 'persisted editor cancel action' {
        Find-ById $window 'inline-task-cancel-2'
    }
    $persistedCancel.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    [void](Wait-Until 'visible Cancel closed the unchanged editor' {
        if ($null -eq (Find-ById $window 'inline-task-title-2')) { return $true }
        return $false
    })

    $taskInfo = Wait-Until 'reopen for Return keyboard commit' {
        Find-ById $window 'task-info-2'
    }
    $taskInfo.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $returnEditor = Wait-Until 'title editor for Return commit' {
        Find-ById $window 'inline-task-title-2'
    }
    $returnTitle = 'Life-only task saved with Return'
    $returnEditor.GetCurrentPattern(
        [System.Windows.Automation.ValuePattern]::Pattern).SetValue($returnTitle)
    $returnEditor.SetFocus()
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    [void](Wait-Until 'Return committed the inline task draft' {
        if ($null -ne (Find-ByName $window $returnTitle)) { return $true }
        return $false
    })
    $plainTask = $returnTitle

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
    # Keep the golden-path task incomplete so the cold restart verifies the
    # same list and state the user saved. Batch behavior gets two dedicated
    # fixtures instead of consuming the persistence fixture.
    $batchNames = @('Batch completion task one', 'Batch completion task two')
    foreach ($title in $batchNames) {
        $quickAdd.GetCurrentPattern(
            [System.Windows.Automation.ValuePattern]::Pattern).SetValue($title)
        $quickAdd.SetFocus()
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
        [void](Wait-Until ("batch task saved under 生活: {0}" -f $title) {
            Find-ByName $window $title
        })
    }
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
    Select-TaskForBatch $batchNames[0] $false
    Select-TaskForBatch $batchNames[1] $true
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
        if ($null -eq (Find-ByName $window $batchNames[0]) -and
            $null -eq (Find-ByName $window $batchNames[1])) { return $true }
        return $false
    })

    # A batch deletion must be fully reversible without giving tasks
    # replacement IDs (including their list ownership and due metadata).
    $undoName1 = 'Undo safety task one'
    $undoName2 = 'Undo safety task two'
    foreach ($title in @($undoName1, $undoName2)) {
        $quickAdd.GetCurrentPattern(
            [System.Windows.Automation.ValuePattern]::Pattern).SetValue($title)
        $quickAdd.SetFocus()
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
        [void](Wait-Until ("saved task: {0}" -f $title) {
            Find-ByName $window $title
        })
    }
    Select-TaskForBatch $undoName1 $false
    Select-TaskForBatch $undoName2 $true
    $deleteBatch = Wait-Until 'bulk-delete action' {
        Find-ById $window 'bulk-delete'
    }
    $deleteBatch.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $undo = Wait-Until 'undo-delete action' {
        $item = Find-ById $window 'undo-delete'
        if ($null -ne $item -and
            -not $item.Current.IsOffscreen) { return $item }
        return $null
    }
    $undo.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    foreach ($title in @($undoName1, $undoName2)) {
        [void](Wait-Until ("task restored without backend delete: {0}" -f $title) {
            Find-ByName $window $title
        })
    }

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

    # A backend changed event proves an RPC round trip; a cold application
    # restart additionally proves the installed host reopens the same data.
    $restartProcess = Start-Process -FilePath $executable.FullName -PassThru `
        -RedirectStandardOutput (Join-Path $output 'application-restart.stdout.log') `
        -RedirectStandardError (Join-Path $output 'application-restart.stderr.log')
    $window = Wait-Until 'Taskly window after restart' {
        $restartProcess.Refresh()
        if ($restartProcess.HasExited) {
            throw "Taskly exited before restart verification (exit $($restartProcess.ExitCode))"
        }
        $condition = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
            $restartProcess.Id)
        $desktop.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
    }
    [void](Wait-Until 'database connection after restart' {
        Find-ByName $window 'Database Connected'
    })
    Select-TaskList 2 '生活'
    [void](Wait-Until 'saved task after restart' { Find-ByName $window $returnTitle })
    $restartInfo = Wait-Until 'saved task details after restart' {
        Find-ById $window 'task-info-2'
    }
    $restartInfo.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $restartDate = Wait-Until 'saved task date after restart' {
        Find-ById $window 'inline-task-date-2'
    }
    $restartTime = Wait-Until 'saved task time after restart' {
        Find-ById $window 'inline-task-time-2'
    }
    if ($restartDate.GetCurrentPattern(
            [System.Windows.Automation.ValuePattern]::Pattern).Current.Value -ne '2099-12-31' -or
        $restartTime.GetCurrentPattern(
            [System.Windows.Automation.ValuePattern]::Pattern).Current.Value -ne '10:30') {
        throw 'task date/time did not survive a cold installed-app restart'
    }
    [ordered]@{
        platform = 'windows'
        assertions = @('task title, date, and time survive a cold installed-app restart')
    } | ConvertTo-Json | Set-Content -LiteralPath `
        (Join-Path $output 'persistence-restart.json') -Encoding utf8
    $window.GetCurrentPattern(
        [System.Windows.Automation.WindowPattern]::Pattern).Close()
    [void](Wait-Until 'restarted process exit' {
        $restartProcess.Refresh()
        if ($restartProcess.HasExited) { return $true }
        return $false
    } 15)

    [ordered]@{
        platform = 'windows'
        artifact = $executable.FullName
        actions = @('set:quick-add', 'invoke:quick-add-submit', 'toggle:task-complete-1', 'create-list:生活', 'select-list:2', 'enter:quick-add', 'inline:escape-cancel-task-2', 'inline:tab-order-task-2', 'inline:edit-task-2', 'select-list:1', 'select-list:2')
        assertions = @(
            'packaged WinUI window activated',
            'initial window is fully visible inside the current monitor work area',
            'fresh profile exposes an actionable first-task empty state',
            'stable UI Automation identifiers exposed',
            'RPC-created task appeared',
            'changed Event removed the completed task from the active view',
            'new task submitted by Enter is owned by 生活, not 工作',
            'task checkbox and plain-text title are vertically aligned',
            'Windows task list exposes native multiple selection',
            'Escape cancels a focused inline draft without mutating the task',
            'inline task editor exposes compact accessible date/time/list actions with predictable Tab order',
            'calendar action exposes a native date grid above visible Save and Cancel actions',
            'visible Save and Return both persist title, notes, date, and time; visible Cancel closes without mutation',
            'task title, date, and time survive a cold installed-app restart',
            'view switches preserve task list ownership',
            'global search shows the real owning list for every task',
            'Ctrl/Shift multi-selection completes two tasks in one command',
            'bulk deletion undo restores original rows before backend mutation',
            'batch scheduling is visible and enabled when multiple tasks are selected',
            'native window close stopped the process and restart verification exited cleanly'
        )
    } | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $output 'interaction-trace.json') -Encoding utf8
    $scenarioComplete = $true
} finally {
    # Archive process state even on a failed or timed-out launch.
    if ($process) {
        try {
            $process.Refresh()
            [ordered]@{
                pid = $process.Id
                exitedBeforeCleanup = $process.HasExited
                exitCode = if ($process.HasExited) { $process.ExitCode } else { $null }
                mainWindowHandle = [int64]$process.MainWindowHandle
                mainWindowTitle = $process.MainWindowTitle
                executable = $executable.FullName
            } | ConvertTo-Json -Depth 3 |
                Set-Content -LiteralPath (Join-Path $output 'launch-diagnostic.json') -Encoding utf8
        } catch {}
    }
    try { Capture-Screen (Join-Path $output 'screen-final.png') } catch {}
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit()
    }
    if ($restartProcess -and -not $restartProcess.HasExited) {
        Stop-Process -Id $restartProcess.Id -Force -ErrorAction SilentlyContinue
        $restartProcess.WaitForExit()
    }
    if ($process) { $process.Dispose() }
    if ($restartProcess) { $restartProcess.Dispose() }
    $env:HOME = $oldHome
    $env:USERPROFILE = $oldProfile

    if ($installRecord) {
        $uninstallLog = Join-Path $output 'msi-uninstall.log'
        $start = [System.Diagnostics.ProcessStartInfo]::new('msiexec.exe')
        $start.UseShellExecute = $false
        foreach ($argument in @('/x', [string]$installRecord.artifact,
                                 '/qn', '/norestart', '/l*v', $uninstallLog)) {
            [void]$start.ArgumentList.Add($argument)
        }
        $uninstall = [System.Diagnostics.Process]::Start($start)
        try {
            if (-not $uninstall.WaitForExit(180000)) {
                $uninstall.Kill()
                throw 'MSI uninstall exceeded 180 seconds'
            }
            if ($uninstall.ExitCode -ne 0) {
                throw "MSI uninstall failed with exit code $($uninstall.ExitCode)"
            }
        } finally {
            $uninstall.Dispose()
        }

        $binaryRemoved = -not (Test-Path -LiteralPath ([string]$installRecord.executable))
        $shortcutRemoved = -not (Test-Path -LiteralPath ([string]$installRecord.shortcut))
        $dataPreserved = Test-Path -LiteralPath (Join-Path $tasklyHome 'tasks.db')
        [ordered]@{
            installer = 'msi'
            binaryRemoved = $binaryRemoved
            shortcutRemoved = $shortcutRemoved
            dataPreserved = $dataPreserved
        } | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $output 'install-lifecycle.json') -Encoding utf8
        if (-not $binaryRemoved) { throw 'MSI uninstall left the installed executable behind' }
        if (-not $shortcutRemoved) { throw 'MSI uninstall left the Start menu shortcut behind' }
        if ($scenarioComplete -and -not $dataPreserved) {
            throw 'MSI uninstall removed the disposable Taskly data unexpectedly'
        }
    }
}
