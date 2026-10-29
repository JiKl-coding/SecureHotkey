# SecureHotkey

**Encrypted Auto-Type Manager for AutoHotkey v2**

SecureHotkey is a lightweight, Windows-only PowerShell tool for managing login profiles and generating **one central [AutoHotkey v2](https://www.autohotkey.com/) launcher**. Press a keyboard shortcut in the right application window to enter your username and password automatically—without storing your password as plain text in an `.ahk` file.

> [!IMPORTANT]
> SecureHotkey is **not affiliated with AutoHotkey**. The release package bundles an unmodified portable copy of AutoHotkey v2, so no AutoHotkey installation is required.

## Features

- 🔐 **Encrypted credentials:** Windows DPAPI via PowerShell's `ConvertFrom-SecureString`.
- ⌨️ **Custom hotkeys:** `Alt+F1`, `Ctrl+Alt+F1`, `Ctrl+Shift+K`, and more.
- 🪟 **Window-aware profiles:** Use the same hotkey for different applications based on window title and/or process name, or leave both empty to match any window.
- 📋 **Profile picker:** When several profiles match, a small menu lets you choose one (e.g. multiple accounts on one hotkey).
- 👤 **Flexible credentials:** Store a username and password, only a username, or only a password.
- 🧩 **Custom Auto-Type sequences:** Configure tabs, Enter presses, and delays.
- 🛠️ **Interactive manager:** Add, edit, enable/disable, list, or delete profiles.
- 🚀 **Windows startup integration:** Install a shortcut for the central launcher.
- 📁 **Single installation directory:** `C:\tools\SecureHotkey\` by default, configurable on first run.

## Requirements

- Windows 10 or 11 (x64)
- Windows PowerShell 5.1 or newer
- [AutoHotkey v2](https://www.autohotkey.com/) only when running from a repository clone; the release package includes it

## Quick start

1. Download `SecureHotkey-<version>.zip` from [Releases](../../releases) and extract it anywhere.
2. Double-click **`SecureHotkey.cmd`** to open the interactive manager.
3. Select **1 — Add profile** and enter your profile name, username (optional), whether to store a password, target window title and/or process name (both optional), shortcut, typing sequence, and password (entered through a hidden prompt).
4. Select **5 — Install Windows startup** to install a shortcut and start the launcher, or **6 — Start / reload launcher** to start it without configuring startup.
5. Focus the username field in the target application and press your configured hotkey.

You can also start the manager from PowerShell in the project folder:

```powershell
.\SecureHotkey.cmd
```

On first run, the manager asks for an installation directory (default `C:\tools\SecureHotkey\`; if you cannot write there, use e.g. `%LOCALAPPDATA%\SecureHotkey`). The choice is verified for write access and remembered in `HKCU\Software\SecureHotkey`. The manager creates and maintains its files there, even if you launch it from somewhere else, and copies the bundled `AutoHotkey64.exe` there. Run it as your **normal Windows user**, not as Administrator.

To use a different directory later, run `SecureHotkey.cmd -Root "D:\path\SecureHotkey"`. Existing profiles are not moved automatically; copy `profiles.json` and `credentials\` yourself if needed.

To upgrade, exit the running launcher (tray icon → Exit), extract the new release, and run `SecureHotkey.cmd` again.

## Example: Sophos Connect

| Setting | Example |
| --- | --- |
| Profile name | `Sophos` |
| Username | `your-username` |
| Window title | `Sophos Connect` |
| Process | `SophosConnect.exe` (optional; see Task Manager → Details) |
| Shortcut | `Alt+F1` |
| Sequence | `{USERNAME}{TAB}{PASSWORD}{ENTER}` |

With the Sophos Connect window active and its username input focused, the hotkey types the username, presses Tab, types the decrypted password, and presses Enter.

## Typing sequences

Choose a built-in template or define your own:

| Sequence | Behavior |
| --- | --- |
| `{USERNAME}{TAB}{PASSWORD}{ENTER}` | Standard two-field login |
| `{USERNAME}{ENTER}{DELAY 500}{PASSWORD}{ENTER}` | Two-step login with a pause |
| `{USERNAME}{TAB 3}{PASSWORD}{ENTER}` | Skip three tab stops |
| `{USERNAME}{TAB}{PASSWORD}` | Fill both fields without submitting |
| `{USERNAME}{TAB 2}{DELAY 300}{PASSWORD}{ENTER}` | Extra tabs and a pause |

Profiles that store only a username offer `{USERNAME}{TAB}`, `{USERNAME}{ENTER}`, and `{USERNAME}`; password-only profiles offer `{PASSWORD}{ENTER}`, `{PASSWORD}{TAB}`, and `{PASSWORD}`.

Supported tokens for custom sequences:

```text
{USERNAME}     Types the configured username
{PASSWORD}     Types the decrypted password
{TAB}          Presses Tab
{TAB 3}        Presses Tab three times (1–99)
{ENTER}        Presses Enter
{DELAY 300}    Waits 300 milliseconds (1–9999)
```

A sequence must contain `{USERNAME}` if (and only if) the profile stores a username, and `{PASSWORD}` if (and only if) it stores a password. Literal text and other tokens are not supported in this version.

## Hotkeys and window matching

Supported shortcuts combine at least one modifier (`Ctrl`, `Alt`, `Shift`, or `Win`) with a letter (`A`–`Z`) or function key (`F1`–`F12`). For example:

```text
Alt+F1
Ctrl+Alt+F1
Ctrl+Shift+K
```

Window titles are matched **case-insensitively by substring**, so choose a sufficiently distinctive title. Optionally, a profile can also require a **process name** (e.g. `SophosConnect.exe`, exact match, case-insensitive), which is much harder to spoof than a title. If both are set, both must match. Multiple profiles can share the same hotkey if their targets differ. If more than one profile matches the active window and shortcut, SecureHotkey shows a small menu to pick the profile (use the number keys or the mouse). In windows without a matching profile, the shortcut is not intercepted and reaches the application normally.

A profile with an **empty window title and process** matches any window. Profiles restricted by title or process take precedence over such "any window" profiles for the same shortcut. Use this with care: the hotkey will type into whatever window is active.

## Managing profiles

Launch `SecureHotkey.cmd` to access:

| Menu | Action |
| --- | --- |
| `1` | Add profile |
| `2` | Edit profile (name, username, window, process, shortcut, sequence, set/remove password, enable/disable); enter `-` to clear the username, window title, or process |
| `3` | Delete profile and its encrypted password |
| `4` | List profiles |
| `5` | Install Windows startup |
| `6` | Start / reload launcher |
| `0` | Exit |

After changing profiles, reload the launcher to apply your updates.

## Files and installation directory

Use `SecureHotkey.cmd` to start the PowerShell manager, `SecureHotkey.ps1`. The manager maintains the following files in its installation directory:

```text
C:\tools\SecureHotkey\   # or your chosen installation directory
├── manager.ps1       # Copy of the interactive profile manager
├── AutoHotkey64.exe  # Bundled portable AutoHotkey v2 runtime
├── AutoHotkey-license.txt
├── launcher.ahk      # Single generated AutoHotkey v2 launcher (decrypts on demand)
├── profiles.json     # Profile settings (no plaintext passwords)
└── credentials\
    ├── <profile-id>.enc
    └── ...
```

Windows startup is handled by a shortcut in your account's Startup folder (`shell:startup`) that runs `launcher.ahk` with the bundled `AutoHotkey64.exe`, or with the installed AutoHotkey if no bundled copy is present.

## Building a release

Pushing a tag (e.g. `v2.0.0`) runs the GitHub Actions workflow in `.github/workflows/release.yml`. It downloads the pinned official AutoHotkey v2 portable ZIP, verifies its SHA256 checksum, and publishes `SecureHotkey-<tag>.zip` as a release asset. To update AutoHotkey, change `AHK_VERSION` and `AHK_SHA256` in the workflow (the checksum is listed in the AutoHotkey release notes).

## Security model and limitations

SecureHotkey protects **credentials stored on disk**, but it does **not** make auto-typing immune to malware or compromised applications.

- Passwords are encrypted using Windows DPAPI, tied to the Windows user account that created them.
- A process running under that same Windows account can generally decrypt them too.
- At login time, the launcher decrypts the password directly via `CryptUnprotectData` (no PowerShell process); it exists briefly in AutoHotkey process memory, and native buffers are zeroed after use.
- Deleting a profile overwrites its `.enc` file with zeros before removal; on SSDs this does not guarantee physical erasure.
- The launcher verifies the target window between sequence actions, but cannot prevent every focus-change race during a single send operation.
- Window-title matching is not strong application identity verification; another window could present a matching title. Adding a process name helps, but a different program with the same executable name would still match. Profiles without a window title or process offer no window check at all.
- Global shortcuts can conflict with other software. Some elevated applications and secure-desktop dialogs may not work.
- Your organization's security policies may restrict automated sign-ins, particularly to VPN or company systems.

**Use test credentials first**, and consider a dedicated password manager if you need stronger protection against attacks occurring while your Windows session is unlocked.

## Project status

A small, practical utility built with **PowerShell and AutoHotkey v2**. The current version has not been verified on every Windows/application configuration; feedback and improvements are welcome.

## License

SecureHotkey is open-source software licensed under the [MIT License](LICENSE).

You are free to use, modify, and distribute this software, including for commercial purposes, provided that the original copyright and license notice are preserved.

See the [LICENSE](LICENSE) file for details.

The release package bundles [AutoHotkey](https://github.com/AutoHotkey/AutoHotkey) unmodified; it is licensed separately under the GNU GPL v2 (see `ahk/license.txt`).
