#Requires -Version 5.1
<#
.SYNOPSIS
    Sign out of the current Azure Virtual Desktop user session.
.DESCRIPTION
    Standard Windows logoff is the default. Optional -FastLogoff disconnects
    the current session first, then requests normal Windows logoff from a
    separate same-user worker. No FSLogix disks are forcibly unmounted.

    -NoGUI skips confirmation completely and signs out immediately.
    -EnableLogging writes diagnostics to C:\Temp.
    -Mode Preview is always non-destructive.
.NOTES
    Windows PowerShell 5.1. Run as the interactive user, without elevation.
    Source code is PS2EXE-compatible; compilation is optional.
.EXAMPLE
    .\AVDFastSignOut.ps1
.EXAMPLE
    .\AVDFastSignOut.ps1 -NoGUI
.EXAMPLE
    .\AVDFastSignOut.ps1 -NoGUI -FastLogoff -EnableLogging
.EXAMPLE
    .\AVDFastSignOut.ps1 -Mode Preview -EnableLogging
#>

[CmdletBinding()]
param(
    [switch]$FastLogoff,
    [switch]$NoGUI,
    [switch]$EnableLogging,
    [switch]$DisableLogging,
    [ValidateSet('GUI', 'Preview', 'Worker')]
    [string]$Mode = 'GUI',
    # Internal worker parameters. Do not set these in user shortcuts.
    [string]$LogFile = '',
    [int]$ExpectedSessionId = -1
)

$ErrorActionPreference = 'Stop'
$script:SourceScriptPath = $PSCommandPath
$script:RegistryPath = 'HKCU:\Software\AVDFastSignOut'
$script:LogDirectory = 'C:\Temp'
$script:DisconnectDelayMs = 1500
$script:LoggingEnabled = [bool]$EnableLogging -and -not [bool]$DisableLogging
$script:ActiveLogPath = ''
$script:ApplicationName = 'AVD Fast Sign Out'

function Get-CurrentSessionId {
    return [System.Diagnostics.Process]::GetCurrentProcess().SessionId
}

function New-LogFile {
    if (-not [System.IO.Directory]::Exists($script:LogDirectory)) {
        [System.IO.Directory]::CreateDirectory($script:LogDirectory) | Out-Null
    }

    $userName = ($env:USERNAME -replace '[^a-zA-Z0-9_-]', '_')
    if ([string]::IsNullOrWhiteSpace($userName)) { $userName = 'User' }
    $sessionId = Get-CurrentSessionId
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $token = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $name = "AVDFastSignOut_${userName}_S${sessionId}_${timestamp}_${token}.log"
    $path = Join-Path $script:LogDirectory $name
    [System.IO.File]::WriteAllText($path, '', (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    if (-not $script:LoggingEnabled -or [string]::IsNullOrWhiteSpace($script:ActiveLogPath)) {
        return
    }

    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $line = "[$timestamp] [$Level] $Message`r`n"
        [System.IO.File]::AppendAllText(
            $script:ActiveLogPath,
            $line,
            (New-Object System.Text.UTF8Encoding($false))
        )
    }
    catch {
        # Logging failure must never block normal logoff.
        $script:LoggingEnabled = $false
    }
}

function Invoke-NormalLogoff {
    # No session ID: logoff.exe targets the current user's session.
    Write-Log 'Starting standard Windows logoff for the current session.'
    $logoffExe = Join-Path $env:SystemRoot 'System32\logoff.exe'
    Start-Process -FilePath $logoffExe -WindowStyle Hidden -ErrorAction Stop | Out-Null
    Write-Log 'logoff.exe started. Windows/FSLogix completion is not confirmed.'
}

function Start-FastLogoffWorker {
    param([Parameter(Mandatory)][int]$SessionId)

    $processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $processName = [System.IO.Path]::GetFileNameWithoutExtension($processPath)
    $workerArguments = ('-Mode Worker -ExpectedSessionId {0}' -f $SessionId)

    if ($script:LoggingEnabled -and $script:ActiveLogPath) {
        $workerArguments += (' -EnableLogging -LogFile "{0}"' -f $script:ActiveLogPath)
    }

    if ($processName -match '^(powershell|powershell_ise|pwsh)$') {
        if (-not $script:SourceScriptPath) {
            throw 'Unable to determine the source PowerShell script path.'
        }
        # Script invoked directly: run the same .ps1 again with worker arguments.
        $arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "{0}" {1}' -f $script:SourceScriptPath, $workerArguments)
    }
    else {
        # Compiled with PS2EXE: run the same executable with worker arguments.
        $arguments = $workerArguments
    }

    Write-Log "Starting background worker. Executable=$processPath SessionId=$SessionId"
    $worker = Start-Process -FilePath $processPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -ErrorAction Stop
    if ($null -eq $worker) { throw 'The background worker could not be launched.' }
}

function Invoke-FastLogoffWorker {
    if ($ExpectedSessionId -le 0) {
        throw 'An expected interactive session ID is required.'
    }

    # Validate the worker's log path. Never create or truncate a file in worker mode.
    if ($script:LoggingEnabled -and $LogFile) {
        try {
            $candidate = [System.IO.Path]::GetFullPath($LogFile)
            $parent = [System.IO.Path]::GetFullPath((Split-Path -Path $candidate -Parent))
            $allowed = [System.IO.Path]::GetFullPath($script:LogDirectory)
            if (($parent -ieq $allowed) -and [System.IO.File]::Exists($candidate) -and
                ([System.IO.Path]::GetFileName($candidate) -like 'AVDFastSignOut_*.log')) {
                $script:ActiveLogPath = $candidate
            }
            else { $script:LoggingEnabled = $false }
        }
        catch { $script:LoggingEnabled = $false }
    }
    else { $script:LoggingEnabled = $false }

    $sessionId = Get-CurrentSessionId
    if ($sessionId -ne $ExpectedSessionId) {
        Write-Log "Session mismatch: Expected=$ExpectedSessionId Actual=$sessionId. No action taken." 'ERROR'
        return
    }

    Write-Log "Worker started. Computer=$env:COMPUTERNAME User=$env:USERNAME SessionId=$sessionId PID=$PID"

    if (-not ('AVDFastSignOutNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AVDFastSignOutNative
{
    [DllImport("wtsapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool WTSDisconnectSession(IntPtr hServer, int sessionId, bool wait);

    [DllImport("wtsapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool WTSLogoffSession(IntPtr hServer, int sessionId, bool wait);
}
'@
    }

    $serverHandle = [IntPtr]::Zero
    Write-Log 'Requesting disconnect for current session.'
    $disconnected = [AVDFastSignOutNative]::WTSDisconnectSession($serverHandle, $sessionId, $false)
    $disconnectError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()

    if ($disconnected) {
        Write-Log 'Disconnect request accepted. Waiting before standard logoff.'
        Start-Sleep -Milliseconds $script:DisconnectDelayMs
    }
    else {
        Write-Log "Disconnect failed. Win32Error=$disconnectError. Continuing to logoff." 'WARN'
    }

    Write-Log 'Requesting Windows logoff. FSLogix is handled by Windows.'
    $loggedOff = [AVDFastSignOutNative]::WTSLogoffSession($serverHandle, $sessionId, $false)
    $logoffError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()

    if ($loggedOff) {
        Write-Log 'Windows accepted the logoff request. Actual completion is not confirmed.'
    }
    else {
        Write-Log "WTSLogoffSession failed. Win32Error=$logoffError. Trying logoff.exe." 'WARN'
        Invoke-NormalLogoff
    }
}

function Show-Confirmation {
    param([switch]$Preview)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $script:ApplicationName
    $form.ClientSize = [System.Drawing.Size]::new(455, 184)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowIcon = $false
    $form.TopMost = $true
    $form.Font = [System.Drawing.Font]::new('Segoe UI', 10)
    # Use the operating system's default window and control theme.

    $message = New-Object System.Windows.Forms.Label
    $message.Text = 'Are you sure you want to sign out of AVD?'
    $message.Location = [System.Drawing.Point]::new(18, 20)
    $message.Size = [System.Drawing.Size]::new(420, 25)

    $note = New-Object System.Windows.Forms.Label
    $note.Text = if ($Preview) {
        'PREVIEW MODE: Your session will not be disconnected.'
    } else {
        'Please save your work before signing out.'
    }
    $note.Location = [System.Drawing.Point]::new(18, 52)
    $note.Size = [System.Drawing.Size]::new(420, 25)

    $checkbox = New-Object System.Windows.Forms.CheckBox
    $checkbox.Text = 'Do not show this confirmation again'
    $checkbox.Location = [System.Drawing.Point]::new(18, 94)
    $checkbox.Size = [System.Drawing.Size]::new(410, 24)
    $checkbox.Enabled = -not [bool]$Preview

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Location = [System.Drawing.Point]::new(238, 135)
    $cancel.Size = [System.Drawing.Size]::new(94, 32)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $confirm = New-Object System.Windows.Forms.Button
    $confirm.Text = if ($Preview) { 'Preview' } else { 'Sign out' }
    $confirm.Location = [System.Drawing.Point]::new(343, 135)
    $confirm.Size = [System.Drawing.Size]::new(94, 32)
    $confirm.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $form.Controls.AddRange(@($message, $note, $checkbox, $cancel, $confirm))
    $form.AcceptButton = $confirm
    $form.CancelButton = $cancel

    try {
        $result = $form.ShowDialog()
        return [pscustomobject]@{
            Confirmed      = ($result -eq [System.Windows.Forms.DialogResult]::OK)
            RememberChoice = $checkbox.Checked
        }
    }
    finally { $form.Dispose() }
}

if ($Mode -eq 'Worker') {
    try { Invoke-FastLogoffWorker }
    catch {
        Write-Log "Worker error: $($_.Exception.Message)" 'ERROR'
        if ((Get-CurrentSessionId) -eq $ExpectedSessionId -and $ExpectedSessionId -gt 0) {
            try { Invoke-NormalLogoff }
            catch { Write-Log "Worker fallback error: $($_.Exception.Message)" 'ERROR' }
        }
    }
    return
}

try {
    if ($script:LoggingEnabled) {
        try { $script:ActiveLogPath = New-LogFile }
        catch { $script:LoggingEnabled = $false }
    }

    $sessionId = Get-CurrentSessionId
    $method = if ($FastLogoff) { 'Fast' } else { 'Normal' }
    Write-Log "Start. Version=1.0 Mode=$Mode Method=$method NoGUI=$NoGUI Computer=$env:COMPUTERNAME User=$env:USERNAME SessionId=$sessionId PID=$PID"

    if ($sessionId -le 0) {
        throw 'Run this application inside an interactive user session, not as SYSTEM or in Session 0.'
    }

    if ($Mode -eq 'Preview') {
        # Preview is non-destructive even when -NoGUI or -FastLogoff is specified.
        Write-Log "Preview mode. FastLogoff=$FastLogoff NoGUI=$NoGUI. No session action taken."
        if (-not $NoGUI) {
            $previewResult = Show-Confirmation -Preview
            Write-Log "Preview dialog completed. Confirmed=$($previewResult.Confirmed)."
        }
        return
    }

    if ($NoGUI) {
        # Explicitly bypass both the dialog and the stored user preference.
        Write-Log 'NoGUI specified. Confirmation bypassed; immediate sign-out requested.'
    }
    else {
        $skipConfirmation = $false
        $preference = Get-ItemProperty -Path $script:RegistryPath -Name 'SkipConfirmation' -ErrorAction SilentlyContinue
        if ($preference -and $preference.SkipConfirmation -eq 1) { $skipConfirmation = $true }
        Write-Log "SkipConfirmation=$skipConfirmation"

        if (-not $skipConfirmation) {
            $result = Show-Confirmation
            if (-not $result.Confirmed) {
                Write-Log 'User cancelled. No sign-out requested.'
                return
            }
            Write-Log 'User confirmed sign-out.'

            if ($result.RememberChoice) {
                New-Item -Path $script:RegistryPath -Force | Out-Null
                New-ItemProperty -Path $script:RegistryPath -Name 'SkipConfirmation' -Value 1 -PropertyType DWord -Force | Out-Null
                Write-Log 'Saved per-user SkipConfirmation=1.'
            }
        }
        else { Write-Log 'Confirmation skipped due to stored user preference.' }
    }

    if ($FastLogoff) {
        Write-Log 'Fast Logoff enabled. Launching worker.'
        try { Start-FastLogoffWorker -SessionId $sessionId }
        catch {
            Write-Log "Worker launch failed: $($_.Exception.Message). Falling back to normal logoff." 'WARN'
            Invoke-NormalLogoff
        }
    }
    else {
        Write-Log 'Normal Logoff selected.'
        Invoke-NormalLogoff
    }
}
catch {
    Write-Log "Error: $($_.Exception.Message)" 'ERROR'
    if ($NoGUI) {
        Write-Error -Message "AVD Fast Sign Out: $($_.Exception.Message)" -ErrorAction Continue
    }
    else {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "Sign out could not be started.`r`n$($_.Exception.Message)",
            $script:ApplicationName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}
