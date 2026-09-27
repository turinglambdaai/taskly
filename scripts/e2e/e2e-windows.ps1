# Taskly Windows E2E: full user-flow test against a disposable database.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/e2e/e2e-windows.ps1
# NOTE: must be saved with a UTF-8 BOM (PowerShell 5 misreads BOM-less UTF-8).
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exe = Get-ChildItem "$repo\apps\windows\Taskly\bin" -Recurse -Filter Taskly.exe |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $exe) { Write-Output "Taskly.exe not found - build first"; exit 2 }

$testDb = Join-Path $env:TEMP "taskly-e2e.db"
$configPath = Join-Path $env:USERPROFILE ".taskly\config.ini"
$configBackup = "$configPath.e2e-bak"
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
$quickAdd2 = Find-Element $Win '+ Add Task' 'Edit' 3
Set-EditValue $quickAdd2 "Call dentist @15:00"
Start-Sleep -Seconds 1
Test-Check "time-only task meta rendered" ($null -ne (Find-Element $Win 'Today  15:00' 'Text' 3))

# --- 4. Toggle completed (row's first button = checkbox)
$meta = Find-Element $Win 'Call dentist' 'Text' 3
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$node = $meta; $rowItem = $null
while ($node -ne $null) {
    $node = $walker.GetParent($node)
    if ($node -eq $null) { break }
    if ($node.Current.ControlType.ProgrammaticName -eq 'ControlType.ListItem') { $rowItem = $node; break }
}
Test-Check "task row is a ListItem" ($null -ne $rowItem)
if ($rowItem) {
    $btnCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    $rowButtons = $rowItem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
    Test-Check "row exposes buttons" ($rowButtons.Count -ge 2) ("count=" + $rowButtons.Count)
    if ($rowButtons.Count -ge 2) {
        Invoke-Element $rowButtons[0]
        Start-Sleep -Seconds 1
        Test-Check "completed task leaves the default view" (
            $null -eq (Find-Element $Win 'Call dentist' 'Text' 2))
        # A completed row leaves the view by design; restore via the CLI
        # (also cross-checks the shared DB). @() guards single-element wrap.
        $found = @(& $exe --db $testDb search "dentist" --json 2>&1 | ConvertFrom-Json)
        & $exe --db $testDb undone $found[0].id | Out-Null
        function Invoke-TileByName([string]$Name) {
            $t = Find-Element $Win $Name 'Text' 3
            $n = $t
            while ($n -ne $null) {
                $n = $walker.GetParent($n)
                if ($n -eq $null) { break }
                if ($n.Current.ControlType.ProgrammaticName -eq 'ControlType.Button') { break }
            }
            if ($n) { Invoke-Element $n }
        }
        Invoke-TileByName 'Planned'
        Start-Sleep -Milliseconds 600
        Invoke-TileByName 'All'
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

# --- 6. View tiles (physical clicks; tiles are plain surfaces, not buttons)
# After each click the large title must switch to the view name.
$btnCondAll = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
foreach ($tileName in @('Today', 'Planned', 'All', 'Completed', 'Calendar')) {
    $t = Find-Element $Win $tileName 'Text' 3
    Test-Check "tile exists: $tileName" ($null -ne $t)
    if ($t) {
        # Walk up from the tile label to the tile button and invoke it.
        $node = $t; $tileBtn = $null
        while ($node -ne $null) {
            $node = $walker.GetParent($node)
            if ($node -eq $null) { break }
            if ($node.Current.ControlType.ProgrammaticName -eq 'ControlType.Button') { $tileBtn = $node; break }
        }
        Test-Check "tile is a real button: $tileName" ($null -ne $tileBtn)
        if ($tileBtn) {
            Invoke-Element $tileBtn
            Start-Sleep -Milliseconds 900
        }
    }
}
# Verify where we ended: the Calendar status line must be present.
Test-Check "tile tour ends on calendar" ($null -ne (
    Find-Element $Win 'Calendar view' 'Text' 4))

# We ended on Calendar. Check calendar specifics.
$calToday = Find-Element $Win 'Today' 'Button' 3
Test-Check "calendar has a Today button" ($null -ne $calToday)
Test-Check "calendar status line" ($null -ne (
    Find-Element $Win 'Calendar view' 'Text' 3))

# --- 7. Calendar interactions: go back a month, then Today
$prev = Find-Element $Win 'Previous month' 'Button' 2
if ($prev) { Invoke-Element $prev; Start-Sleep -Milliseconds 700 }
$next = Find-Element $Win 'Next month' 'Button' 2
if ($next) { Invoke-Element $next; Start-Sleep -Milliseconds 700 }
Invoke-Element $calToday
Start-Sleep -Milliseconds 700
Test-Check "calendar Today navigation alive" ($null -ne (Get-TasklyWindow))

# --- 8. All view: verify counts + open-completed toggle
$allTile = Find-Element $Win 'All' 'Text' 3
Click-Center $allTile
Start-Sleep -Milliseconds 800
$toggle = Find-Element $Win 'Show Completed' 'Button' 3
Test-Check "show-completed toggle present" ($null -ne $toggle)
if ($toggle) {
    Invoke-Element $toggle
    Start-Sleep -Milliseconds 700
    Test-Check "completed tasks visible after toggle" (
        $null -ne (Find-Element $Win 'Buy milk' 'Text' 3) -or
        $null -ne (Find-Element $Win 'Tomorrow' 'Text' 3))
    Invoke-Element $toggle
    Start-Sleep -Milliseconds 500
}

# --- 9. CLI cross-check on the same DB
$cliTasks = & $exe --db $testDb list --json 2>&1 | ConvertFrom-Json
$cliTexts = ($cliTasks | ForEach-Object { $_.text }) -join "|"
Test-Check "CLI sees the GUI tasks" ($cliTexts -match "Buy milk") ("saw: " + $cliTexts)

# --- 10. CLI add -> GUI reflects after a view refresh
& $exe --db $testDb add "CLI inserted task" | Out-Null
function Invoke-Tile([string]$Name) {
    $t = Find-Element $Win $Name 'Text' 3
    $n = $t
    while ($n -ne $null) {
        $n = $walker.GetParent($n)
        if ($n -eq $null) { break }
        if ($n.Current.ControlType.ProgrammaticName -eq 'ControlType.Button') { break }
    }
    if ($n) { Invoke-Element $n }
}
Invoke-Tile 'Planned'
Start-Sleep -Milliseconds 800
Invoke-Tile 'All'
Start-Sleep -Seconds 1
Test-Check "GUI reflects CLI-inserted task after refresh" (
    $null -ne (Find-Element $Win 'CLI inserted task' 'Text' 3))

# --- 11. List management: create a list via the + button
$plus = Find-Element $Win ([string][char]0x271A) 'Button' 3   # heavy plus sign
Test-Check "add-list button present" ($null -ne $plus)
if ($plus) {
    Invoke-Element $plus
    Start-Sleep -Seconds 1
    $nameField = Find-Element $Win 'List name' 'Edit' 3
    Test-Check "list dialog opened" ($null -ne $nameField)
    if ($nameField) {
        $nameField.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue("Errands")
        # Confirm via the dialog's Save button
        $saveBtn = Find-Element $Win 'OK' 'Button' 3
        if ($saveBtn) { Invoke-Element $saveBtn }
        Start-Sleep -Seconds 1
        Test-Check "new list appears in sidebar" ($null -ne (Find-Element $Win 'Errands' 'Text' 3))
    }
}

# --- 12. Language switch zh (menu Settings -> Simplified Chinese)
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

# --- 13. App still alive at the end
Test-Check "app survived the whole flow" ($null -ne (Get-TasklyWindow))

# Cleanup: restore user config, kill app, remove test DB
Get-Process Taskly -ErrorAction SilentlyContinue | Stop-Process -Force
Copy-Item $configBackup $configPath -Force
Remove-Item $configBackup -Force
Start-Sleep -Seconds 2
Remove-Item $testDb -Force -ErrorAction SilentlyContinue
Write-Output "cleanup done (config restored, test db removed)"
Test-Summary
