# AVD Fast Sign Out

PowerShell 5.1 utility for signing out the current **Azure Virtual Desktop (AVD)** session. Supports standard Windows logoff, optional **Fast Logoff**, confirmation preferences, unattended execution, and opt-in diagnostics.

**Source only.** Run the `.ps1` directly or package it with [PS2EXE](https://github.com/MScholtes/PS2EXE).

## Requirements

- Windows PowerShell 5.1 and an interactive AVD/RDS user session.
- Windows Forms for the optional confirmation dialog.
- Run in the signed-in user's context; elevation is not required.
- Write access to the user profile for optional logging.

## Usage

```powershell
# Standard logoff with confirmation
.\src\AVDFastSignOut.ps1

# Standard logoff, no dialog
.\src\AVDFastSignOut.ps1 -NoGUI

# Disconnect, confirm session state, then log off
.\src\AVDFastSignOut.ps1 -FastLogoff

# Fast Logoff with custom disconnect timeout and diagnostics
.\src\AVDFastSignOut.ps1 -FastLogoff -NoGUI -EnableLogging -DisconnectTimeoutSeconds 10

# Non-destructive check
.\src\AVDFastSignOut.ps1 -Mode Preview -EnableLogging
```

| Parameter | Behavior |
|---|---|
| `-FastLogoff` | Disconnect the session before initiating Windows logoff. |
| `-NoGUI` | Bypass confirmation; does not enable Fast Logoff. |
| `-EnableLogging` | Write a per-run diagnostic log to `%LOCALAPPDATA%\AVDFastSignOut\Logs`. |
| `-DisconnectTimeoutSeconds` | Fast Logoff session-state wait limit; default `8`, range `1`–`30` seconds. |
| `-DisableLogging` | Disable logging; overrides `-EnableLogging`. |
| `-Mode Preview` | Run without disconnecting or logging off. |

Without arguments, the application uses standard Windows logoff with confirmation and logging disabled.

## Execution flow

| Standard Logoff | Fast Logoff |
|---|---|
| Optional confirmation | Optional confirmation |
| Execute `logoff.exe` | Launch a worker in the same user session |
| Windows terminates the session | `WTSDisconnectSession` disconnects the client |
| FSLogix handles profile unload and VHDX detach | Poll `WTSConnectState` until `WTSDisconnected`, then call `WTSLogoffSession` |
| Connection closes as logoff completes | Windows and FSLogix finish logoff after disconnect |

Fast Logoff reduces **perceived disconnect time**, not Windows or FSLogix cleanup time. Session state is polled every 200 ms, up to the configured timeout. On timeout/query failure, normal logoff is still requested. An accepted disconnect/logoff request does not confirm completed profile cleanup. Rapid reconnection should be validated in the target environment.

## Configuration and diagnostics

The confirmation opt-out is stored per user:

`HKCU\Software\AVDFastSignOut\SkipConfirmation` (`DWORD = 1`)

Reset the preference:

```powershell
Remove-ItemProperty -Path 'HKCU:\Software\AVDFastSignOut' -Name SkipConfirmation -ErrorAction SilentlyContinue
```

With `-EnableLogging`, logs are written to:

`%LOCALAPPDATA%\AVDFastSignOut\Logs\AVDFastSignOut_<user>_S<sessionId>_<timestamp>_<id>.log`

Logs record invocation context, selected mode, disconnect/logoff requests, and errors. For completed profile operations, use the FSLogix Profile logs on the session host.

## Deployment

Deploy the source or your own packaged executable locally to session hosts. Use Group Policy Preferences to create a Start Menu shortcut, with optional switches in the shortcut's **Arguments** field.

See [GPO Deployment](docs/GPO-Deployment.md) for configuration examples and [How It Works](docs/How-It-Works.md) for the implementation details.

### Optional PS2EXE build

```powershell
Install-Module ps2exe -Scope CurrentUser
Import-Module ps2exe

Invoke-ps2exe `
    -inputFile '.\src\AVDFastSignOut.ps1' `
    -outputFile '.\AVDFastSignOut.exe' `
    -noConsole -STA -x64 `
    -title 'AVD Fast Sign Out' `
    -version '1.1.0.0'
```

No compiled binaries are distributed in this repository.

## License

MIT. See [LICENSE](LICENSE).
