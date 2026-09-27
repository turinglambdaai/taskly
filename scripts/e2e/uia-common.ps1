# Taskly E2E UIA helpers (Windows). Source this file, then call the funcs.
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

$script:Failures = 0
$script:Passes = 0

function Get-TasklyWindow {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, 'Taskly')
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
}

function Find-Element {
    param($Win, [string]$Name, [string]$Type = $null, [int]$TimeoutSec = 5)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ($Type) {
            $ctlType = [System.Windows.Automation.ControlType]::$Type
            $cond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ctlType)
            $all = $Win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
            foreach ($e in $all) {
                if ($e.Current.Name -eq $Name) { return $e }
            }
        } else {
            $cond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NameProperty, $Name)
            $e = $Win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
            if ($e) { return $e }
        }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

function Find-ByCodes {
    # Name match by codepoints — immune to script-encoding issues.
    param($Win, [int[]]$Codes, [string]$Type = $null, [int]$TimeoutSec = 5)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ($Type) {
            $ctlType = [System.Windows.Automation.ControlType]::$Type
            $cond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ctlType)
            $all = $Win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
            foreach ($e in $all) {
                $n = $e.Current.Name
                if ($n -and $n.Length -eq $Codes.Count) {
                    $match = $true
                    for ($i = 0; $i -lt $Codes.Count; $i++) {
                        if ([int][char]$n[$i] -ne $Codes[$i]) { $match = $false; break }
                    }
                    if ($match) { return $e }
                }
            }
        }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

function Invoke-Element {
    # Menu items expose Toggle/SelectionItem instead of Invoke; try in order.
    param($Element)
    foreach ($pt in @([System.Windows.Automation.InvokePattern]::Pattern,
                      [System.Windows.Automation.TogglePattern]::Pattern,
                      [System.Windows.Automation.SelectionItemPattern]::Pattern)) {
        try {
            $pattern = $Element.GetCurrentPattern($pt)
            if ($pattern -is [System.Windows.Automation.TogglePattern]) {
                $pattern.Toggle()
            } elseif ($pattern -is [System.Windows.Automation.SelectionItemPattern]) {
                $pattern.Select()
            } else {
                $pattern.Invoke()
            }
            return
        } catch {
            continue
        }
    }
    throw "no supported pattern on element"
}

function Set-EditValue {
    # Types into an Edit and presses Enter (quick add / search semantics).
    param($EditElement, [string]$Text)
    $vp = $EditElement.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $vp.SetValue($Text)
    $EditElement.SetFocus()
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
}

function Click-Center {
    # Physical click on an element's center (tappable tiles etc).
    param($Element)
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class E2EClick {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
"@
    $r = $Element.Current.BoundingRectangle
    [E2EClick]::SetCursorPos([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)) | Out-Null
    Start-Sleep -Milliseconds 120
    [E2EClick]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    [E2EClick]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

function Test-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) {
        $script:Passes++
        Write-Output ("PASS  " + $Name + $(if ($Detail) { "  [$Detail]" }))
    } else {
        $script:Failures++
        Write-Output ("FAIL  " + $Name + $(if ($Detail) { "  [$Detail]" }))
    }
}

function Test-Summary {
    Write-Output ("---- " + $script:Passes + " passed, " + $script:Failures + " failed ----")
    exit $(if ($script:Failures -gt 0) { 1 } else { 0 })
}
