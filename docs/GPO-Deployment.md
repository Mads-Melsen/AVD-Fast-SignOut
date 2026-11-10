# Deploy with Group Policy Preferences

This guide describes deploying the script or an **optional self-compiled executable** to AVD session hosts. No EXE is included in this repository.

## 1. Deploy files locally

Use **Computer Configuration > Preferences > Windows Settings > Folders / Files** to create a local directory and deploy the script (or your own compiled binary), for example:

- Script: `C:\Program Files\AVDFastSignOut\AVDFastSignOut.ps1`
- Optional EXE: `C:\Program Files\AVDFastSignOut\AVDFastSignOut.exe`

Confirm that computer accounts can read the deployment source and that your organization's AppLocker / WDAC policies permit execution. Do not grant ordinary users write permissions to the application directory.

## 2. Add a Start Menu shortcut

Configure **Computer Configuration > Preferences > Windows Settings > Shortcuts**.

For a compiled application:

| Setting | Value |
|---|---|
| Action | Update |
| Name | AVD Fast Sign Out |
| Location | All Users Programs |
| Target | `C:\Program Files\AVDFastSignOut\AVDFastSignOut.exe` |
| Arguments | See the examples below |

For a script-only installation:

| Setting | Value |
|---|---|
| Name | AVD Fast Sign Out |
| Target | `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` |
| Arguments | `-NoProfile -WindowStyle Hidden -STA -File "C:\Program Files\AVDFastSignOut\AVDFastSignOut.ps1"` |

Append the same switches **after** the `-File` script path, e.g. `-NoGUI -EnableLogging`.

Use a GPO in the scope of your AVD session hosts and test with a non-administrator user. Avoid running this tool as SYSTEM.

## 3. Choose shortcut arguments

| Desired behavior | Optional EXE shortcut Arguments |
|---|---|
| Normal Logoff with confirmation | *(empty)* |
| Normal Logoff with logging | `-EnableLogging` |
| Normal Logoff, immediate/no GUI | `-NoGUI` |
| Fast Logoff with confirmation | `-FastLogoff` |
| Fast Logoff, immediate/no GUI | `-FastLogoff -NoGUI` |
| Fast Logoff, no GUI and diagnostic logs | `-FastLogoff -NoGUI -EnableLogging` |
| Normal Logoff, explicitly no logs | `-DisableLogging` |

Logging is disabled by default. `-DisableLogging` overrides `-EnableLogging` if both are passed.

## 4. Optional PS2EXE compilation

Compiling is **not required**. If desired, run the following from the repository root in Windows PowerShell 5.1:

```powershell
Install-Module ps2exe -Scope CurrentUser
Import-Module ps2exe
Invoke-ps2exe -inputFile '.\src\AVDFastSignOut.ps1' -outputFile '.\AVDFastSignOut.exe' -noConsole -STA -x64 -title 'AVD Fast Sign Out' -version '1.0.0.0'
```

See the [PS2EXE project](https://github.com/MScholtes/PS2EXE) for its full command-line options.

## 5. Validation and rollback

1. Test `-Mode Preview -NoGUI -EnableLogging` to confirm basic startup without logging off.
2. Test normal logoff and verify session termination and FSLogix profile unload.
3. If Fast Logoff is needed, test rapid reconnects and application workloads with FSLogix before enabling it broadly.
4. To disable Fast Logoff, **remove `-FastLogoff`** from the GPO shortcut Arguments. No redeployment is needed.
5. To disable logs, remove `-EnableLogging` or add `-DisableLogging`.

Do not interpret an AVD disconnect alone as proof that the session is fully signed out or that the profile disk was detached.
