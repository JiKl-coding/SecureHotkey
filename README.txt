SecureHotkey v2 — Windows + AutoHotkey v2 + PowerShell 5.1+

INSTALLATION
1. Install AutoHotkey v2: https://www.autohotkey.com/
2. Run manager.ps1 in PowerShell under your normal Windows user account (not as administrator).
   Example: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\manager.ps1
3. Choose 1 (Add profile). Enter a profile name, window title, shortcut, sequence, and password.
4. Choose 5 (Install Windows startup) to create a Startup shortcut and start the launcher.
5. Focus the username input in the target window and press your chosen shortcut.

FILES
The managed files live in C:\tools\SecureHotkey\. The manager may initially be run from elsewhere;
a copy of manager.ps1 is placed in the managed directory. Profiles are in profiles.json;
encrypted passwords are in credentials\. Password encryption uses Windows DPAPI and
is bound to the Windows account used to create each password.

MANAGING PROFILES
Open C:\tools\SecureHotkey\manager.ps1 to add, edit, disable, list, or delete profiles.
After a change, reload the launcher when prompted.

SECURITY AND LIMITATIONS
- Window titles are matched by case-insensitive substring. Choose distinctive titles.
- The same shortcut can be used in different windows. Ambiguous matches are blocked.
- Other applications may compete for global shortcuts.
- During auto-typing, the password exists in memory and passes through a local
  PowerShell process's standard output.
- Another process running as your Windows user can typically decrypt the password.
- Your workplace security policy may prohibit automated sign-ins.
- Secure-desktop UAC dialogs and some elevated applications are not supported.
- The launcher checks focus between sequence actions; it cannot guarantee safety
  if focus switches during a single send action.
- Test with non-sensitive credentials before using real accounts.
