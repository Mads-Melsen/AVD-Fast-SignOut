# AVD Fast Sign Out

A small **PowerShell 5.1** sign-out utility for **Azure Virtual Desktop (AVD)** that offers a confirmation dialog, optional **Fast Logoff**, silent operation (`-NoGUI`), and opt-in diagnostic logging. It can run directly as a `.ps1` file or be compiled separately with [PS2EXE](https://github.com/MScholtes/PS2EXE). **This repository contains source code only; no EXE is distributed.**

The program signs out **the current user session**. It is not a tool for logging off other users.

## Features

- **Normal Logoff by default** via Windows `logoff.exe`.
- Optional **Fast Logoff**: disconnect the current AVD session, then request normal Windows logoff from a same-user background worker.
- Windows-standard confirmation window with **Sign out** / **Cancel**.
- **Do not show this confirmation again** stored per user, with a documented reset command.
- **`-NoGUI`** for immediate sign-out without displaying or consulting the confirmation dialog.
- Optional per-run logging to `C:\Temp`.
- Safe, non-destructive preview mode.
- Compatible with launching from a Start Menu shortcut, Group Policy Preferences, or directly from PowerShell.

## Requirements

- Windows 10/11 or Windows Server supporting RDS sessions; intended for an interactive AVD user session.
- **Windows PowerShell 5.1** and .NET Framework Windows Forms (for the confirmation window).
- Run **as the signed-in user**, without elevation. Do not run as `SYSTEM` or from a non-interactive scheduled task.
- If enabled, logging needs write access to `C:\Temp`. Logging failure does not block sign-out.

## Quick start

Run in **Windows PowerShell 5.1**. Save any unsaved work before using a real sign-out command.

```powershell
# Safe preview: no disconnect or sign-out
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\src\AVDFastSignOut.ps1 -Mode Preview

# Normal Windows logoff (default) with confirmation
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\src\AVDFastSignOut.ps1

# Normal logoff without confirmation: immediate sign-out
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\src\AVDFastSignOut.ps1 -NoGUI

# Fast Logoff with diagnostics and no confirmation
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\src\AVDFastSignOut.ps1 -FastLogoff -NoGUI -EnableLogging

# Non-destructive smoke test for all three flags
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\src\AVDFastSignOut.ps1 -Mode Preview -FastLogoff -NoGUI -EnableLogging
```

### Command-line options

| Option | What it does |
|---|---|
| *(none)* | Normal logoff. Show confirmation unless the user previously opted out. No logging. |
| `-FastLogoff` | Disconnect the current session first, then request Windows logoff. |
| `-NoGUI` | Skip the dialog and **immediately start sign-out**. Takes precedence over the stored confirmation preference. |
| `-EnableLogging` | Create a log in `C:\Temp`. Off by default. |
| `-DisableLogging` | Force logging off, even if `-EnableLogging` was supplied. |
| `-Mode Preview` | **Never disconnects or logs off**. With GUI, shows a preview dialog; combined with `-NoGUI`, only performs validation/logging. |

`-NoGUI` and `-FastLogoff` are independent: `-NoGUI` **does not** enable Fast Logoff. To use both, pass both flags.

`-Mode Worker`, `-ExpectedSessionId`, and `-LogFile` are internal implementation details, **not** configuration options for user shortcuts.

## How it works

**Normal Logoff:** Confirmation (unless suppressed) → `logoff.exe` → Windows ends session → FSLogix performs its normal profile unload/VHDX detach.

**Fast Logoff:** Confirmation (unless suppressed) → separate same-user worker → `WTSDisconnectSession` → approximately 1.5-second delay → `WTSLogoffSession` → Windows and FSLogix finish normal session cleanup.

**Important:** A disconnected session is **not** proof that Windows logoff or FSLogix VHDX detach has completed. Fast Logoff improves the *perceived* sign-out time; it does not accelerate FSLogix. Users who immediately reconnect may encounter a session or profile cleanup race. Thoroughly validate behavior in your environment before enabling it widely.

See [How It Works](docs/How-It-Works.md) for full sequence, error handling, and verification steps.

## Confirmation preferences

When the user checks **Do not show this confirmation again** and selects **Sign out**, the application stores:

`HKCU\Software\AVDFastSignOut\SkipConfirmation` (`DWORD` = `1`)

To restore the confirmation:

```powershell
Remove-ItemProperty -Path 'HKCU:\Software\AVDFastSignOut' -Name 'SkipConfirmation' -ErrorAction SilentlyContinue
```

`-NoGUI` does not change this saved preference; it only bypasses confirmation for the current execution. Preview never saves the preference.

## Logging

Opt in with `-EnableLogging`. Each invocation writes a separate file in:

`C:\Temp\AVDFastSignOut_<user>_S<sessionId>_<timestamp>_<id>.log`

Logs contain basic user/session identifiers, selected behavior, and whether disconnect/logoff **requests** were accepted. They do **not** confirm FSLogix completion; use the host's FSLogix logs for that. Treat log files as operational data and retain them only as needed.

## Group Policy and Windows Start Menu

For GPO shortcuts and sample arguments, see [GPO Deployment](docs/GPO-Deployment.md). A separate deployment is not required if you run the PowerShell file directly.

## Optional PS2EXE build

Use PS2EXE only if you want to create your own `.exe` locally. The application works as a PowerShell script without compiling it.

```powershell
Install-Module ps2exe -Scope CurrentUser
Import-Module ps2exe

Invoke-ps2exe `
    -inputFile '.\src\AVDFastSignOut.ps1' `
    -outputFile '.\AVDFastSignOut.exe' `
    -noConsole `
    -STA `
    -x64 `
    -title 'AVD Fast Sign Out' `
    -description 'Azure Virtual Desktop session sign-out utility' `
    -product 'AVD Fast Sign Out' `
    -version '1.0.0.0'
```

You can add `-iconFile '.\your-icon.ico'` to use your own icon. No icon assets or EXE binaries are included here. Note: PS2EXE is a script packager, not a security boundary; the script source can be extracted from a generated executable.

## Security and limitations

- Always save unsaved work first, especially when using `-NoGUI`.
- A session disconnect is not a Windows logoff. A successful asynchronous API call is not a guarantee of completed cleanup.
- This application does not force-kill FSLogix or detach profile disks.
- The source is provided **as-is** and has not been executed in your AVD environment by this repository's publisher; validate with your own host pool, image, group policies, and FSLogix configuration.
- Because `-NoGUI` logs off immediately, avoid placing it on an easily clicked shortcut unless that behavior is intentional.

## Project layout

```text
AVD-Fast-SignOut/
├── src/AVDFastSignOut.ps1
├── docs/How-It-Works.md
├── docs/GPO-Deployment.md
├── README.md
├── LICENSE
└── .gitignore
```

## License

MIT. See [LICENSE](LICENSE).
