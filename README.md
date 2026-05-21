# adderall

Amphetamine but for windows

## Install

Direct install from GitHub:

```powershell
irm https://raw.githubusercontent.com/ksgat/adderall/main/install.ps1 | iex
```

Local install (from this repo):

```powershell
.\install.ps1
```

After install, open a new PowerShell window so the `adderall` command is loaded from profile.
The installer also registers a Start Menu shortcut for launching the tray widget.

## Command Reference

`adderall` or `adderall lid`  
Toggle lid close action between `Sleep` and `Do nothing` (AC + battery). This does not change idle sleep/display timeouts.

`adderall -d`  
Toggle display always-on and time-based sleep off/on. When enabling, current timeout values are saved and restored when toggled back.

`adderall status`  
Show lid action, sleep timeout, display timeout, and whether a restore state file exists.

`adderall reset`  
Restore normal behavior: lid action to `Sleep`, and display/sleep timeouts from saved state (or defaults if none exists).

`adderall all`  
Enable everything at once: lid `Do nothing` + display/sleep timeouts set to `Never`.

`adderall tray` or `adderall tray start`  
Start the tray widget.

`adderall tray stop`  
Stop the tray widget.

`adderall tray status`  
Show if tray is running, whether tray startup is enabled, and whether the launch shortcut exists.

`adderall tray shortcut`  
Register or re-register the Start Menu shortcut that launches the tray.

`adderall tray startup on|off`  
Enable/disable tray auto-start at Windows sign-in.

`adderall uninstall`  
Reset settings, stop/remove tray integration, remove launch/startup shortcuts, remove command/profile hook, and remove installed files.

## Tray Widget

`adderall tray` starts a tray icon with quick actions:

- Lid close toggle
- Display always-on toggle
- Enable all
- Reset
- Start with Windows toggle
- Status popup
- Exit

## Installed Files

- `%LOCALAPPDATA%\adderall\adderall.ps1`
- `%LOCALAPPDATA%\adderall\adderall-tray.ps1`
- `%LOCALAPPDATA%\adderall\adderall.cmd`
- `%LOCALAPPDATA%\adderall\display-state.json` (created only after display/sleep toggles that save state)
- Start Menu launch shortcut: `%APPDATA%\Microsoft\Windows\Start Menu\Programs\adderall Tray.lnk`
- Startup link for tray (when enabled): `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\adderall Tray.lnk`
