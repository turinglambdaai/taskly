param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$Output
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

New-Item -ItemType Directory -Force -Path $Output | Out-Null
$msi = Get-ChildItem -LiteralPath (Join-Path $Repo 'dist') `
    -Filter 'taskly-*-windows-x64.msi' -File | Select-Object -First 1
if (-not $msi) { throw 'Taskly MSI was not produced' }

$installLog = Join-Path $Output 'msi-install.log'
$uninstallLog = Join-Path $Output 'msi-uninstall-on-failure.log'

function Invoke-TasklyMsi {
    param(
        [ValidateSet('i','x')][string]$Action,
        [string]$LogFile
    )
    $start = [System.Diagnostics.ProcessStartInfo]::new('msiexec.exe')
    $start.UseShellExecute = $false
    foreach ($argument in @("/$Action", $msi.FullName, '/qn', '/norestart', '/l*v', $LogFile)) {
        [void]$start.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::Start($start)
    try {
        if (-not $process.WaitForExit(180000)) {
            $process.Kill()
            throw "msiexec /$Action exceeded 180 seconds"
        }
        if ($process.ExitCode -ne 0) {
            throw "msiexec /$Action failed with exit code $($process.ExitCode); see $LogFile"
        }
    } finally {
        $process.Dispose()
    }
}

$installed = $false
$prepared = $false
try {
    Invoke-TasklyMsi -Action i -LogFile $installLog
    $installed = $true

    $shortcut = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Taskly\Taskly.lnk'
    if (-not (Test-Path -LiteralPath $shortcut -PathType Leaf)) {
        throw 'MSI did not create the Taskly Start menu shortcut'
    }
    # Exercise the normal end-user install location. Besides matching the real
    # first-run journey, this verifies the host's MSI-vs-portable detection,
    # which intentionally keys off Program Files. Resolve the executable from
    # the installed shortcut instead of duplicating WiX directory casing here.
    $shell = New-Object -ComObject WScript.Shell
    try {
        $executable = $shell.CreateShortcut($shortcut).TargetPath
    } finally {
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
    }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "MSI Start menu shortcut points to a missing executable: $executable"
    }
    $installRoot = Split-Path -Parent $executable
    $registration = Get-ItemProperty `
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', `
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.PSObject.Properties.Name -contains 'DisplayName' -and
            $_.DisplayName -eq 'Taskly'
        } | Select-Object -First 1
    if (-not $registration) { throw 'MSI did not register Taskly for uninstall' }

    $signature = Get-AuthenticodeSignature -LiteralPath $executable
    $record = [ordered]@{
        platform = 'windows'
        installer = 'msi'
        artifact = $msi.FullName
        artifactSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $msi.FullName).Hash.ToLowerInvariant()
        executable = $executable
        installRoot = $installRoot
        shortcut = $shortcut
        uninstallString = $registration.UninstallString
        publisherTrustStatus = [string]$signature.Status
        packageVerified = $true
        assertions = @(
            'development MSI installed silently into its normal Program Files directory',
            'installed executable exists',
            'Start menu shortcut exists',
            'Apps and Features uninstall registration exists',
            'publisher trust status was recorded without claiming production signing'
        )
    }
    $record | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $Output 'installed-app.json') -Encoding utf8
    $record | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $Output 'package.json') -Encoding utf8
    $prepared = $true
} finally {
    if ($installed -and -not $prepared) {
        try { Invoke-TasklyMsi -Action x -LogFile $uninstallLog } catch {}
    }
}
