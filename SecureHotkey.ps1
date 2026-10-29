#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$Root = 'C:\tools\SecureHotkey'
$Store = Join-Path $Root 'credentials'
$Config = Join-Path $Root 'profiles.json'
$Launcher = Join-Path $Root 'launcher.ahk'
$AhkExe = Join-Path $Root 'AutoHotkey64.exe'
$Startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'SecureHotkey.lnk'

function Escape-Ahk([string]$s) { return '"' + $s.Replace('`','``').Replace('"','`"').Replace("`r",'').Replace("`n",'') + '"' }
function Save-Config($profiles) {
    $json = ConvertTo-Json -InputObject @($profiles) -Depth 6
    $temp = "$Config.tmp"
    [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $Config -Force
}
function Load-Config {
    if (!(Test-Path -LiteralPath $Config)) { return @() }
    $raw = Get-Content -LiteralPath $Config -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    return (ConvertFrom-Json -InputObject $raw)
}
function Ask([string]$label, [string]$default = '') {
    $suffix = if ($default) { " [$default]" } else { '' }
    $inputValue = Read-Host "$label$suffix"
    if ([string]::IsNullOrWhiteSpace($inputValue)) { return $default }
    return $inputValue.Trim()
}
function Confirm([string]$label, [bool]$default = $false) {
    $answer = (Read-Host "$label $(if($default){'[Y/n]'}else{'[y/N]'})").Trim().ToLowerInvariant()
    if (!$answer) { return $default }
    return $answer -in @('y','yes')
}
function Format-Shortcut([string]$ahk) {
    $names = @{ '^'='Ctrl'; '!'='Alt'; '+'='Shift'; '#'='Win' }
    $parts = @()
    $i = 0
    while ($i -lt $ahk.Length - 1 -and $names.ContainsKey([string]$ahk[$i])) { $parts += $names[[string]$ahk[$i]]; $i++ }
    $parts += $ahk.Substring($i)
    return ($parts -join '+')
}
function Ask-Shortcut([string]$default) {
    while ($true) {
        Write-Host 'Shortcut format: Ctrl+Alt+F1, Alt+F1, Ctrl+Shift+K (F1-F12 or letter A-Z).'
        $choice = Ask 'Shortcut' $default
        $parts = @($choice.Split('+') | ForEach-Object { $_.Trim().ToLowerInvariant() })
        $key = $parts[-1]
        $mods = @($parts | Select-Object -SkipLast 1)
        if ($parts.Count -ge 2 -and $parts.Count -le 4 -and ($key -match '^(f([1-9]|1[0-2])|[a-z])$') -and
            @($mods | Where-Object { $_ -notin @('ctrl','alt','shift','win') }).Count -eq 0 -and
            @($mods | Select-Object -Unique).Count -eq $mods.Count) {
            $prefix = ''
            if ('ctrl' -in $mods) { $prefix += '^' }
            if ('alt' -in $mods) { $prefix += '!' }
            if ('shift' -in $mods) { $prefix += '+' }
            if ('win' -in $mods) { $prefix += '#' }
            return $prefix + $key.ToUpperInvariant()
        }
        Write-Warning 'Invalid shortcut. At least one modifier is required.'
    }
}
function Validate-Sequence([string]$seq) {
    $remaining = $seq.ToUpperInvariant()
    while ($remaining.Length -gt 0) {
        if ($remaining -match '^\{(USERNAME|PASSWORD|ENTER|TAB(?: [1-9][0-9]?)?|DELAY [1-9][0-9]{0,3})\}') {
            $remaining = $remaining.Substring($Matches[0].Length)
        } else { return $false }
    }
    return ($seq.ToUpperInvariant().Contains('{PASSWORD}') -and $seq.ToUpperInvariant().Contains('{USERNAME}') -and $seq.Length -le 600)
}
function Ask-Sequence([string]$default) {
    $templates = @(
        '{USERNAME}{TAB}{PASSWORD}{ENTER}',
        '{USERNAME}{ENTER}{DELAY 500}{PASSWORD}{ENTER}',
        '{USERNAME}{TAB 3}{PASSWORD}{ENTER}',
        '{USERNAME}{TAB}{PASSWORD}',
        '{USERNAME}{TAB 2}{DELAY 300}{PASSWORD}{ENTER}'
    )
    while ($true) {
        Write-Host "`nSequences:"
        for ($i=0; $i -lt $templates.Count; $i++) { Write-Host " $($i+1)) $($templates[$i])" }
        Write-Host ' 6) Custom sequence'
        if ($default) { Write-Host " 7) Keep current: $default" }
        $choice = Ask 'Choice' $(if($default){'7'}else{'1'})
        if ($choice -eq '7' -and $default) { return $default }
        if ($choice -match '^[1-5]$') { return $templates[[int]$choice - 1] }
        if ($choice -eq '6') {
            Write-Host "`nCustom sequence reference:"
            Write-Host ' {USERNAME}   types the username'
            Write-Host ' {PASSWORD}   types the decrypted password'
            Write-Host ' {TAB}        presses Tab'
            Write-Host ' {TAB 3}      presses Tab three times (1-99)'
            Write-Host ' {ENTER}      presses Enter'
            Write-Host ' {DELAY 300}  waits 300 ms (1-9999)'
            Write-Host ' The sequence must contain both {USERNAME} and {PASSWORD}; no literal text.'
            $seq = (Read-Host 'Sequence').Trim().ToUpperInvariant()
            if (Validate-Sequence $seq) { return $seq }
            Write-Warning 'Invalid sequence.'
        }
    }
}
function Set-Password([string]$id) {
    $secret = Read-Host 'Password (hidden)' -AsSecureString
    if ($secret.Length -eq 0) { throw 'Password cannot be empty.' }
    $path = Join-Path $Store "$id.enc"
    $cipher = ConvertFrom-SecureString -SecureString $secret
    [IO.File]::WriteAllText($path, $cipher, (New-Object Text.UTF8Encoding($false)))
    $secret.Dispose()
}
function Select-Profile($profiles) {
    if (@($profiles).Count -eq 0) { Write-Warning 'No profiles yet.'; return -1 }
    for ($i=0; $i -lt @($profiles).Count; $i++) {
        $p = $profiles[$i]
        Write-Host (' {0}) {1} | {2} | {3} | {4}' -f ($i+1), $p.name, $p.window, $p.shortcut, $(if($p.enabled){'enabled'}else{'disabled'}))
    }
    $n = Read-Host 'Profile number (Enter = back)'
    if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le @($profiles).Count) { return ([int]$n - 1) }
    return -1
}
function New-Profile($profiles) {
    $name = Ask 'Profile name'
    if (!$name) { throw 'Profile name is required.' }
    $username = Ask 'Username'
    if (!$username) { throw 'Username is required.' }
    $window = Ask 'Window title (e.g. Sophos Connect; required)'
    if (!$window) { throw 'Window title is required for safety.' }
    $shortcut = Ask-Shortcut 'Alt+F1'
    $sequence = Ask-Sequence ''
    $id = [guid]::NewGuid().ToString('N')
    Set-Password $id
    $profile = [pscustomobject]@{ id=$id; name=$name; username=$username; window=$window; shortcut=$shortcut; sequence=$sequence; enabled=$true }
    return (@($profiles) + @($profile))
}
function Edit-Profile($profiles, [int]$index) {
    $p = $profiles[$index]
    Write-Host "`nEditing: $($p.name)"
    Write-Host ' 1) Name'; Write-Host ' 2) Username'; Write-Host ' 3) Window title'; Write-Host ' 4) Shortcut'; Write-Host ' 5) Sequence'; Write-Host ' 6) Change password'; Write-Host ' 7) Enable/disable'; Write-Host ' 0) Back'
    switch (Read-Host 'Choice') {
        '1' { $v=Ask 'Name' $p.name; if($v){$p.name=$v} }
        '2' { $v=Ask 'Username' $p.username; if($v){$p.username=$v} }
        '3' { $v=Ask 'Window title' $p.window; if($v){$p.window=$v} }
        '4' { $p.shortcut=Ask-Shortcut (Format-Shortcut $p.shortcut) }
        '5' { $p.sequence=Ask-Sequence $p.sequence }
        '6' { Set-Password $p.id }
        '7' { $p.enabled = -not $p.enabled }
    }
    return $profiles
}
function Render-Launcher($profiles) {
    $lines = [Collections.Generic.List[string]]::new()
    foreach($line in @(
        '#Requires AutoHotkey v2.0', '#SingleInstance Force', 'SetTitleMatchMode 2', 'profiles := []'
    )) { $lines.Add($line) }
    foreach($p in $profiles) {
        if (!$p.enabled) { continue }
        $fields = @((Escape-Ahk $p.id),(Escape-Ahk $p.username),(Escape-Ahk $p.window),(Escape-Ahk $p.shortcut),(Escape-Ahk $p.sequence))
        $lines.Add('profiles.Push(Map("id", ' + $fields[0] + ', "username", ' + $fields[1] + ', "window", ' + $fields[2] + ', "hotkey", ' + $fields[3] + ', "sequence", ' + $fields[4] + '))')
    }
    $runtime = @'
registered := Map()
; Hotkeys are active only in matching windows; elsewhere the keystroke passes through.
HotIf(HasMatchingProfile)
for p in profiles {
    if !registered.Has(p["hotkey"]) {
        registered[p["hotkey"]] := true
        Hotkey(p["hotkey"], HandleLogin, "On")
    }
}
HotIf()

HasMatchingProfile(hotkeyName) {
    global profiles
    try title := WinGetTitle("A")
    catch
        return false
    for p in profiles {
        if (p["hotkey"] = hotkeyName && InStr(title, p["window"], false))
            return true
    }
    return false
}

HandleLogin(hotkeyName) {
    global profiles
    matched := []
    hwnd := WinExist("A")
    if !hwnd
        return
    title := WinGetTitle("ahk_id " hwnd)
    for p in profiles {
        if (p["hotkey"] = hotkeyName && InStr(title, p["window"], false))
            matched.Push(p)
    }
    if matched.Length = 0
        return
    if matched.Length > 1 {
        MsgBox "Conflict: multiple profiles with the same shortcut match this window. Refine window titles in the manager.", "SecureHotkey"
        return
    }
    p := matched[1]
    if !WinActive("ahk_id " hwnd)
        return
    try {
        password := DecryptPassword(p["id"])
    } catch as err {
        MsgBox "Unable to decrypt password: " err.Message "`nAt line: " err.Line, "SecureHotkey"
        return
    }
    if !WinActive("ahk_id " hwnd) {
        password := ""
        return
    }
    seq := p["sequence"]
    pos := 1
    while RegExMatch(seq, "\{(USERNAME|PASSWORD|ENTER|TAB(?: [0-9]+)?|DELAY [0-9]+)\}", &m, pos) {
        if !WinActive("ahk_id " hwnd) {
            password := ""
            return
        }
        action := m[1]
        if action = "USERNAME"
            SendText p["username"]
        else if action = "PASSWORD"
            SendText password
        else if action = "ENTER"
            Send "{Enter}"
        else if SubStr(action, 1, 3) = "TAB" {
            parts := StrSplit(action, " ")
            count := parts.Length > 1 ? (parts[2] + 0) : 1
            Send "{Tab " count "}"
        } else if SubStr(action, 1, 5) = "DELAY" {
            Sleep (SubStr(action, 7) + 0)
        }
        pos := m.Pos + m.Len
    }
    password := ""
}

; Reads the DPAPI-protected SecureString generated by PowerShell
; ConvertFrom-SecureString. The .enc file contains a hexadecimal DATA_BLOB.
; Decryption happens inside this AHK process (no PowerShell console).
DecryptPassword(id) {
    path := A_ScriptDir "\credentials\" id ".enc"
    hex := Trim(FileRead(path, "UTF-8"))
    if !RegExMatch(hex, "i)^01000000[0-9a-f]+$") || Mod(StrLen(hex), 2)
        throw Error("Invalid encrypted password format")

    data := Buffer(StrLen(hex) // 2, 0)
    Loop data.Size {
        NumPut("UChar", ("0x" SubStr(hex, (A_Index - 1) * 2 + 1, 2)) + 0, data, A_Index - 1)
    }

    ; Windows DATA_BLOB = DWORD cbData + pointer pbData, aligned to pointer size.
    ptrOffset := A_PtrSize = 8 ? 8 : 4
    inBlob := Buffer(ptrOffset + A_PtrSize, 0)
    outBlob := Buffer(ptrOffset + A_PtrSize, 0)
    NumPut("UInt", data.Size, inBlob, 0)
    NumPut("Ptr", data.Ptr, inBlob, ptrOffset)

    success := DllCall("Crypt32\CryptUnprotectData", "Ptr", inBlob.Ptr,
        "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0,
        "UInt", 0, "Ptr", outBlob.Ptr, "Int")
    if !success
        throw Error("CryptUnprotectData failed (Win32 error " A_LastError ")")

    ptr := NumGet(outBlob, ptrOffset, "Ptr")
    byteCount := NumGet(outBlob, 0, "UInt")
    try {
        if !ptr || Mod(byteCount, 2)
            throw Error("Invalid decrypted UTF-16 data")
        return StrGet(ptr, byteCount // 2, "UTF-16")
    } finally {
        if ptr {
            DllCall("msvcrt\memset", "Ptr", ptr, "Int", 0, "UPtr", byteCount, "Ptr")
            DllCall("Kernel32\LocalFree", "Ptr", ptr, "Ptr")
        }
        DllCall("msvcrt\memset", "Ptr", data.Ptr, "Int", 0, "UPtr", data.Size, "Ptr")
    }
}
'@
    $lines.Add($runtime)
    [IO.File]::WriteAllText($Launcher, ($lines -join "`r`n"), (New-Object Text.UTF8Encoding($true)))
}
function Install-PortableAhk {
    $source = Join-Path $PSScriptRoot 'ahk'
    $exe = Join-Path $source 'AutoHotkey64.exe'
    if (!(Test-Path -LiteralPath $exe)) { return }
    if ((Test-Path -LiteralPath $AhkExe) -and (Get-FileHash -LiteralPath $exe).Hash -eq (Get-FileHash -LiteralPath $AhkExe).Hash) { return }
    try {
        Copy-Item -LiteralPath $exe -Destination $AhkExe -Force
        Copy-Item -LiteralPath (Join-Path $source 'license.txt') -Destination (Join-Path $Root 'AutoHotkey-license.txt') -Force -ErrorAction SilentlyContinue
    } catch { Write-Warning "Cannot update bundled AutoHotkey (stop the running launcher first): $($_.Exception.Message)" }
}
function Install-Startup {
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($Startup)
    if (Test-Path -LiteralPath $AhkExe) {
        $lnk.TargetPath = $AhkExe
        $lnk.Arguments = "`"$Launcher`""
    } else {
        $lnk.TargetPath = $Launcher
    }
    $lnk.WorkingDirectory = $Root
    $lnk.Description = 'SecureHotkey launcher'
    $lnk.Save()
}
function Restart-Launcher {
    if (Confirm 'Start/reload the launcher now?' $true) {
        try {
            if (Test-Path -LiteralPath $AhkExe) {
                Start-Process -FilePath $AhkExe -ArgumentList "`"$Launcher`"" -WorkingDirectory $Root | Out-Null
            } else {
                Start-Process -FilePath $Launcher | Out-Null
            }
            Write-Host 'Launcher started.'
        }
        catch { Write-Warning "Cannot start AutoHotkey (use the release package or install AutoHotkey v2): $($_.Exception.Message)" }
    }
}

New-Item -ItemType Directory -Path $Store -Force | Out-Null
# Install the manager itself in the canonical directory for future administration.
if ([IO.Path]::GetFullPath($PSCommandPath) -ine [IO.Path]::GetFullPath((Join-Path $Root 'manager.ps1'))) {
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $Root 'manager.ps1') -Force
}
Install-PortableAhk
if (Test-Path -LiteralPath $Startup) { Install-Startup }
# Legacy decrypt.ps1 is no longer used. Leave it untouched to avoid deleting user files.
$profiles = @(Load-Config)
if (!(Test-Path $Config)) { Save-Config $profiles }
Render-Launcher $profiles

while ($true) {
    Write-Host "`n=== SecureHotkey Manager ===" -ForegroundColor Cyan
    Write-Host "Directory: $Root"
    Write-Host ' 1) Add profile'
    Write-Host ' 2) Edit profile'
    Write-Host ' 3) Delete profile'
    Write-Host ' 4) List profiles'
    Write-Host ' 5) Install Windows startup'
    Write-Host ' 6) Start / reload launcher'
    Write-Host ' 0) Exit'
    $choice = Read-Host 'Choice'
    $changed = $false
    try {
        switch ($choice) {
            '1' { $profiles = @(New-Profile $profiles); $changed = $true }
            '2' { $idx = Select-Profile $profiles; if($idx -ge 0){ $profiles = @(Edit-Profile $profiles $idx); $changed = $true } }
            '3' { $idx = Select-Profile $profiles; if($idx -ge 0 -and (Confirm "Really delete $($profiles[$idx].name) including its encrypted password?")) {
                    $id=$profiles[$idx].id
                    $profiles = @($profiles | Where-Object { $_.id -ne $id })
                    $encPath = Join-Path $Store "$id.enc"
                    if (Test-Path -LiteralPath $encPath) {
                        [IO.File]::WriteAllBytes($encPath, (New-Object byte[] (Get-Item -LiteralPath $encPath).Length))
                        Remove-Item -LiteralPath $encPath
                    }
                    $changed = $true
                }
            }
            '4' { $null = Select-Profile $profiles }
            '5' { Install-Startup; Write-Host "Startup shortcut created: $Startup"; Restart-Launcher }
            '6' { Restart-Launcher }
            '0' { return }
            default { Write-Warning 'Unknown option.' }
        }
        if ($changed) {
            # Prevent overlaps with same shortcut and window matcher.
            $conflicts = @($profiles | Where-Object enabled | Group-Object { "$($_.shortcut)|$($_.window.ToLowerInvariant())" } | Where-Object Count -gt 1)
            if ($conflicts.Count -gt 0) { Write-Warning 'Warning: some enabled profiles share a shortcut and window title. Ambiguous matches will be blocked.' }
            Save-Config $profiles
            Render-Launcher $profiles
            Write-Host 'Saved. Reload the launcher to apply changes.' -ForegroundColor Green
            Restart-Launcher
        }
    } catch { Write-Warning $_.Exception.Message; $profiles = @(Load-Config) }
}
