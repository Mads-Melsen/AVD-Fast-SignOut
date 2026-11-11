param([switch]$Worker, [int]$SessionId)

$id = [Diagnostics.Process]::GetCurrentProcess().SessionId
if ($id -le 0 -or ($Worker -and $id -ne $SessionId)) { return }

if (-not $Worker) {
    try {
        $args = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Worker -SessionId {1}' -f $PSCommandPath, $id
        Start-Process "$PSHOME\powershell.exe" -ArgumentList $args -WindowStyle Hidden -ErrorAction Stop | Out-Null
    } catch {
        & "$env:SystemRoot\System32\logoff.exe"
    }
    return
}

try {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Wts {
    [DllImport("wtsapi32.dll")] public static extern bool WTSDisconnectSession(IntPtr server, int session, bool wait);
    [DllImport("wtsapi32.dll")] public static extern bool WTSLogoffSession(IntPtr server, int session, bool wait);
}
'@
    if (-not [Wts]::WTSDisconnectSession([IntPtr]::Zero, $id, $false)) {
        & "$env:SystemRoot\System32\logoff.exe"
        return
    }
    Start-Sleep -Milliseconds 1500
    if (-not [Wts]::WTSLogoffSession([IntPtr]::Zero, $id, $false)) {
        & "$env:SystemRoot\System32\logoff.exe"
    }
} catch {
    & "$env:SystemRoot\System32\logoff.exe"
}
