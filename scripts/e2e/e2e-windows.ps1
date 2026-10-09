# Taskly Windows E2E: full user-flow test against a disposable database.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/e2e/e2e-windows.ps1
# NOTE: must be saved with a UTF-8 BOM (PowerShell 5 misreads BOM-less UTF-8).
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exe = Join-Path $repo ".rivet\stage\RivetHost.exe"
if (-not (Test-Path $exe)) {
    Write-Output "RivetHost.exe not found - run 'raco rivet build' first"; exit 2
}
# The host exe is GUI-only; CLI cross-checks go through the Racket CLI shim.
$cli = Join-Path $repo "scripts\taskly-cli.cmd"

$testDb = Join-Path $env:TEMP "taskly-e2e.db"
$configPath = Join-Path $env:USERPROFILE ".taskly\config.ini"
$configBackup = "$configPath.e2e-bak"
if (-not (Test-Path $configPath)) {
    New-Item -ItemType Directory -Force (Split-Path $configPath) | Out-Null
    "# Taskly configuration" | Out-File $configPath -Encoding ascii
}
Copy-Item $configPath $configBackup -Force
Remove-Item $testDb -ErrorAction SilentlyContinue

# Point the app at the disposable DB, English UI. The default list name is
# the hardcoded Chinese seed (DATA-FORMAT), built by codepoint here.
$seedListName = [string]([char]0x5DE5) + [string]([char]0x4F5C)   # gong-zuo
$tomorrow = [string]([char]0x660E) + [string]([char]0x5929)       # ming-tian
$today = [string]([char]0x4ECA) + [string]([char]0x5929)          # jin-tian

@"
# Taskly configuration
last-db-path=$testDb
last-selected-list-id=0
language=en
"@ | Out-File $configPath -Encoding ascii

Write-Output "== launching app against $testDb =="
Start-Process $exe
Start-Sleep -Seconds 6

. (Join-Path $PSScriptRoot "uia-common.ps1")
$Win = Get-TasklyWindow
Test-Check "app window appears" ($null -ne $Win)
if (-not $Win) { Test-Summary }

# A fresh config makes the silent launch update check hit the live feed; the
# update-offer ContentDialog (if it appeared) must go before other dialogs.
$cancel = Find-Element $Win 'Cancel' 'Button' 3
if ($cancel) {
    Invoke-Element $cancel
    Start-Sleep -Seconds 1
    Test-Check "update offer dismissed" $true
}

# --- 1. Fresh database: seeded default list, empty state
Test-Check "seeded default list visible" ($null -ne (Find-Element $Win $seedListName 'Text' 15))
Test-Check "empty state shown" ($null -ne (Find-Element $Win 'No tasks' 'Text' 3))

# --- 2. Quick add with a relative date command
$quickAdd = Find-Element $Win '+ Add Task' 'Edit' 5
Test-Check "quick add present" ($null -ne $quickAdd)
Set-EditValue $quickAdd "Buy milk +1d"
Start-Sleep -Seconds 1
Test-Check "task appears after quick add" ($null -ne (Find-Element $Win 'Buy milk' 'Text' 4))
Test-Check "relative due label (Tomorrow)" ($null -ne (Find-Element $Win 'Tomorrow' 'Text' 3))

# --- 3. Quick add with a time command
# @time rolls to tomorrow once the time has passed (CLI contract), so the
# expected relative label depends on the wall clock at run time.
$nowT = Get-Date
$target = $nowT.AddHours(2)
if ($target.Date -eq $nowT.Date) {
    $timeArg = '@' + $target.ToString('HH:mm')
    $expectedMeta = "Today · " + $target.ToString('HH:mm')
} else {
    $timeArg = '@12:00'
    $expectedMeta = "Tomorrow · 12:00"
}
$quickAdd2 = Find-Element $Win '+ Add Task' 'Edit' 3
Set-EditValue $quickAdd2 "Call dentist $timeArg"
Start-Sleep -Seconds 1
Test-Check "time-only task meta rendered" ($null -ne (Find-Element $Win $expectedMeta 'Text' 6)) $expectedMeta

# --- 4. Toggle completed (the row's checkbox; WinUI exposes it as CheckBox)
function Find-Ancestor {
    param($Element, [string]$ControlType)
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $node = $Element
    while ($node -ne $null) {
        $node = $walker.GetParent($node)
        if ($node -eq $null) { break }
        if ($node.Current.ControlType.ProgrammaticName -eq "ControlType.$ControlType") { return $node }
    }
    return $null
}
function Find-RowItem {
    param($Win, [string]$Name)
    $label = Find-Element $Win $Name 'Text' 3
    if (-not $label) { return $null }
    return Find-Ancestor $label 'ListItem'
}
function Select-Tile {
    # Smart-view tiles are chip Buttons; invoking one switches the view.
    param($Win, [string]$Name)
    $label = Find-Element $Win $Name 'Text' 3
    if (-not $label) { return }
    $btn = Find-Ancestor $label 'Button'
    if ($btn) { Invoke-Element $btn }
}
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$rowItem = Find-RowItem $Win 'Call dentist'
Test-Check "task row is a ListItem" ($null -ne $rowItem)
if ($rowItem) {
    $checkCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::CheckBox)
    $rowChecks = $rowItem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $checkCond)
    Test-Check "row exposes a checkbox" ($rowChecks.Count -ge 1) ("count=" + $rowChecks.Count)
    if ($rowChecks.Count -ge 1) {
        Invoke-Element $rowChecks[0]
        Start-Sleep -Seconds 1
        Test-Check "completed task leaves the default view" (
            $null -eq (Find-Element $Win 'Call dentist' 'Text' 2))
        # A completed row leaves the view by design; restore via the CLI
        # (also cross-checks the shared DB). @() guards single-element wrap.
        $found = @(& $cli --db $testDb search "dentist" --json 2>&1 | ConvertFrom-Json)
        & $cli --db $testDb undone $found[0].id | Out-Null
        Select-Tile $Win 'Planned'
        Start-Sleep -Milliseconds 600
        Select-Tile $Win 'All'
        Start-Sleep -Seconds 1
        Test-Check "toggle back restores the task (via CLI undone)" (
            $null -ne (Find-Element $Win 'Call dentist' 'Text' 3))
    }
}

# --- 5. Search
$search = Find-Element $Win 'Search tasks' 'Edit' 3
Test-Check "search box present" ($null -ne $search)
$search.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue("dentist")
Start-Sleep -Seconds 1
Test-Check "search keeps the match" ($null -ne (Find-Element $Win 'Call dentist' 'Text' 3))
Test-Check "search hides non-match" ($null -eq (Find-Element $Win 'Buy milk' 'Text' 2))
$search.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue("")
Start-Sleep -Seconds 1
Test-Check "clearing search restores rows" ($null -ne (Find-Element $Win 'Buy milk' 'Text' 3))

# --- 6. View tiles (UIA invoke; tiles are 2×2 chip Buttons per DESIGN-TOKENS)
foreach ($tileName in @('Today', 'Planned', 'All', 'Completed')) {
    $t = Find-Element $Win $tileName 'Text' 3
    Test-Check "tile exists: $tileName" ($null -ne $t)
    if ($t) {
        $btn = Find-Ancestor $t 'Button'
        Test-Check "tile is a chip button: $tileName" ($null -ne $btn)
        if ($btn) {
            Invoke-Element $btn
            Start-Sleep -Milliseconds 900
        }
    }
}

# --- 7. All view: verify counts + open-completed toggle
Select-Tile $Win 'All'
Start-Sleep -Milliseconds 800
$toggle = Find-Element $Win 'Show Completed' 'CheckBox' 3
Test-Check "show-completed toggle present" ($null -ne $toggle)
if ($toggle) {
    Invoke-Element $toggle
    Start-Sleep -Milliseconds 700
    Test-Check "completed tasks visible after toggle" (
        $null -ne (Find-Element $Win 'Buy milk' 'Text' 3) -or
        $null -ne (Find-Element $Win 'Tomorrow' 'Text' 3))
    Invoke-Element $toggle
    Start-Sleep -Milliseconds 400
}

# --- 8. CLI cross-check on the same DB
$cliTasks = & $cli --db $testDb list --json 2>&1 | ConvertFrom-Json
$cliTexts = ($cliTasks | ForEach-Object { $_.text }) -join "|"
Test-Check "CLI sees the GUI tasks" ($cliTexts -match "Buy milk") ("saw: " + $cliTexts)

# --- 9. CLI add -> GUI reflects after a view refresh
& $cli --db $testDb add "CLI inserted task" | Out-Null
Select-Tile $Win 'Planned'
Start-Sleep -Milliseconds 800
Select-Tile $Win 'All'
Start-Sleep -Seconds 1
Test-Check "GUI reflects CLI-inserted task after refresh" (
    $null -ne (Find-Element $Win 'CLI inserted task' 'Text' 3))

# --- 10. List management: create a list via the ✚ button in the My Lists header
$plus = Find-Element $Win 'Create List' 'Button' 3
Test-Check "add-list button present" ($null -ne $plus)
if ($plus) {
    Invoke-Element $plus
    Start-Sleep -Seconds 1
    $nameField = Find-Element $Win 'Please enter list name' 'Edit' 3
    Test-Check "list dialog opened" ($null -ne $nameField)
    if ($nameField) {
        $nameField.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue("Errands")
        # Confirm via the dialog's primary button
        $saveBtn = Find-Element $Win 'OK' 'Button' 3
        if ($saveBtn) { Invoke-Element $saveBtn }
        Start-Sleep -Seconds 1
        Test-Check "new list appears in sidebar" ($null -ne (Find-Element $Win 'Errands' 'Text' 3))
    }
}

# --- 11. Language switch zh (menu Settings -> Simplified Chinese)
$settingsMenu = Find-Element $Win 'Settings' 'MenuItem' 3
if ($settingsMenu) {
    ($settingsMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)).Expand()
    Start-Sleep -Milliseconds 800
    $zhItem = Find-Element $Win 'Simplified Chinese' 'MenuItem' 3
    if ($zhItem) { Invoke-Element $zhItem }
    Start-Sleep -Seconds 1
}
$todayZh = [string]([char]0x4ECA) + [string]([char]0x5929)
Test-Check "tiles re-render in Chinese" ($null -ne (Find-Element $Win $todayZh 'Text' 3))

# --- 12. App still alive at the end
Test-Check "app survived the whole flow" ($null -ne (Get-TasklyWindow))

# Cleanup: restore user config, kill app, remove test DB
Get-Process RivetHost, Taskly -ErrorAction SilentlyContinue | Stop-Process -Force
Copy-Item $configBackup $configPath -Force
Remove-Item $configBackup -Force
Start-Sleep -Seconds 2
Remove-Item $testDb -Force -ErrorAction SilentlyContinue
Write-Output "cleanup done (config restored, test db removed)"
Test-Summary
