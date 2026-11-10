# How AVD Fast Sign Out Works

## Normal Logoff

1. User launches the script (or a separately compiled executable).
2. Unless `-NoGUI` is supplied or the user has previously opted out, the confirmation dialog appears.
3. The application launches `logoff.exe` with **no session ID**, targeting only the current user session.
4. Windows performs the standard session logoff; FSLogix unloads the user profile and detaches its VHD(X) according to the host configuration.
5. The remote client disconnects as session logoff completes.

The exact duration depends on running applications and host/profile configuration.

## Fast Logoff

1. User launches with `-FastLogoff`, optionally also `-NoGUI`.
2. After confirmation (or immediately with `-NoGUI`), a separate worker is launched in the **same user session**.
3. The worker validates its session ID, then calls `WTSDisconnectSession` on the current session (with `wait=false`).
4. If the disconnect request is accepted, the worker waits approximately **1,500 ms**.
5. The worker calls `WTSLogoffSession` (also with `wait=false`) to request **normal Windows logoff**.
6. Windows and FSLogix continue their ordinary teardown, including profile unload and VHD(X) detach.

If disconnect fails, the worker still requests Windows logoff. If the logoff API fails, it falls back to `logoff.exe`. If the worker cannot start, the parent requests standard Windows logoff instead.

This is intentionally **disconnect-then-logoff**, not forced termination. FSLogix cleanup is owned by Windows/FSLogix rather than the application.

### Why the user experiences a faster exit

The AVD client can disconnect before Windows has fully completed its sign-out. The user's perceived duration may therefore be much shorter than the **actual** logoff duration.

### Quick reconnect caveat

An immediate reconnect can occur before the previous logoff and FSLogix profile detach are complete. Depending on AVD authorization, session routing, and profile state, the new login may be delayed or fail. The tool does not guarantee rapid reconnect success or the completion time of FSLogix cleanup.

## Confirmation behavior

- Default: dialog shown unless a previous confirmed choice has set `SkipConfirmation=1`.
- `-NoGUI`: no dialog, regardless of the saved preference; it does not write the preference.
- `-Mode Preview`: never triggers session disconnect or logoff; it never persists a confirmation preference.
- Registry: `HKCU\Software\AVDFastSignOut\SkipConfirmation`.

## Diagnostics

With `-EnableLogging`, inspect `C:\Temp\AVDFastSignOut_*.log`. These logs cover **requests** and their return values, not Windows sign-out completion.

To verify actual completion on a test host, correlate the timestamps with:

- `Microsoft-Windows-TerminalServices-LocalSessionManager/Operational` (session disconnect and logoff events).
- `C:\ProgramData\FSLogix\Logs\Profile\Profile-YYYYMMDD.log` for `UnloadProfile successful`, `Detached vhd(x)`, and `Logoff_Complete`.
- A subsequent successful login and access to existing profile files.

## Relevant API documentation

- [WTSDisconnectSession](https://learn.microsoft.com/en-us/windows/win32/api/wtsapi32/nf-wtsapi32-wtsdisconnectsession)
- [WTSLogoffSession](https://learn.microsoft.com/en-us/windows/win32/api/wtsapi32/nf-wtsapi32-wtslogoffsession)
