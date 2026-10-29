#Requires -Version 5.1
param([string]$Root)
$ErrorActionPreference = 'Stop'
$RegKey = 'HKCU:\Software\SecureHotkey'
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
    $items = ConvertFrom-Json -InputObject $raw
    # Profiles created before v3 have no process property.
    foreach ($p in $items) {
        if ($p.PSObject.Properties.Name -notcontains 'process') { $p | Add-Member -NotePropertyName process -NotePropertyValue '' }
    }
    return $items
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
# A sequence must type exactly the values the profile stores (username and/or password).
function Validate-Sequence([string]$seq, [bool]$hasUser, [bool]$hasPass) {
    $seq = $seq.ToUpperInvariant()
    if ($seq.Length -gt 600) { return $false }
    $remaining = $seq
    while ($remaining.Length -gt 0) {
        if ($remaining -match '^\{(USERNAME|PASSWORD|ENTER|TAB(?: [1-9][0-9]?)?|DELAY [1-9][0-9]{0,3})\}') {
            $remaining = $remaining.Substring($Matches[0].Length)
        } else { return $false }
    }
    return ($seq.Contains('{USERNAME}') -eq $hasUser) -and ($seq.Contains('{PASSWORD}') -eq $hasPass) -and ($hasUser -or $hasPass)
}
function Ask-Sequence([string]$default, [bool]$hasUser, [bool]$hasPass) {
    $templates = if ($hasUser -and $hasPass) { @(
        '{USERNAME}{TAB}{PASSWORD}{ENTER}',
        '{USERNAME}{ENTER}{DELAY 500}{PASSWORD}{ENTER}',
        '{USERNAME}{TAB 3}{PASSWORD}{ENTER}',
        '{USERNAME}{TAB}{PASSWORD}',
        '{USERNAME}{TAB 2}{DELAY 300}{PASSWORD}{ENTER}'
    ) } elseif ($hasUser) { @('{USERNAME}{TAB}', '{USERNAME}{ENTER}', '{USERNAME}') }
    else { @('{PASSWORD}{ENTER}', '{PASSWORD}{TAB}', '{PASSWORD}') }
    $custom = [string]($templates.Count + 1)
    $keep = [string]($templates.Count + 2)
    if ($default -and !(Validate-Sequence $default $hasUser $hasPass)) { $default = '' }
    while ($true) {
        Write-Host "`nSequences:"
        for ($i=0; $i -lt $templates.Count; $i++) { Write-Host " $($i+1)) $($templates[$i])" }
        Write-Host " $custom) Custom sequence"
        if ($default) { Write-Host " $keep) Keep current: $default" }
        $choice = Ask 'Choice' $(if($default){$keep}else{'1'})
        if ($choice -eq $keep -and $default) { return $default }
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $templates.Count) { return $templates[[int]$choice - 1] }
        if ($choice -eq $custom) {
            Write-Host "`nCustom sequence reference:"
            Write-Host ' {USERNAME}   types the username'
            Write-Host ' {PASSWORD}   types the decrypted password'
            Write-Host ' {TAB}        presses Tab'
            Write-Host ' {TAB 3}      presses Tab three times (1-99)'
            Write-Host ' {ENTER}      presses Enter'
            Write-Host ' {DELAY 300}  waits 300 ms (1-9999)'
            $required = @(@(if($hasUser){'{USERNAME}'}) + @(if($hasPass){'{PASSWORD}'})) -join ' and '
            Write-Host " The sequence must contain $required (and nothing the profile does not store); no literal text."
            $seq = (Read-Host 'Sequence').Trim().ToUpperInvariant()
            if (Validate-Sequence $seq $hasUser $hasPass) { return $seq }
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
function Test-Password([string]$id) { return (Test-Path -LiteralPath (Join-Path $Store "$id.enc")) }
function Remove-Password([string]$id) {
    $encPath = Join-Path $Store "$id.enc"
    if (Test-Path -LiteralPath $encPath) {
        [IO.File]::WriteAllBytes($encPath, (New-Object byte[] (Get-Item -LiteralPath $encPath).Length))
        Remove-Item -LiteralPath $encPath
    }
}
function Confirm-AnyWindow {
    Write-Warning 'Without a window title or process the hotkey types into ANY active window (more specific profiles take precedence).'
    return (Confirm 'Continue?')
}
function Ask-Process([string]$default, [string]$hint) {
    while ($true) {
        $v = Ask "Process name, e.g. SophosConnect.exe; see Task Manager > Details ($hint)" $default
        if (!$v -or $v -eq '-') { return $v }
        if ($v -match '^[^\\/:*?"<>|]+$') { return $(if ($v -match '\.exe$') { $v } else { "$v.exe" }) }
        Write-Warning 'Invalid process name.'
    }
}
function Format-Target($p) {
    $target = @(@($p.window, $p.process) | Where-Object { $_ }) -join ' @ '
    if ($target) { return $target } else { return '(any window)' }
}
function Select-Profile($profiles) {
    if (@($profiles).Count -eq 0) { Write-Warning 'No profiles yet.'; return -1 }
    for ($i=0; $i -lt @($profiles).Count; $i++) {
        $p = $profiles[$i]
        $fields = @(@(if($p.username){'username'}) + @(if(Test-Password $p.id){'password'})) -join '+'
        Write-Host (' {0}) {1} | {2} | {3} | {4} | {5}' -f ($i+1), $p.name, (Format-Target $p), (Format-Shortcut $p.shortcut), $fields, $(if($p.enabled){'enabled'}else{'disabled'}))
    }
    $n = Read-Host 'Profile number (Enter = back)'
    if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le @($profiles).Count) { return ([int]$n - 1) }
    return -1
}
function New-Profile($profiles) {
    $name = Ask 'Profile name'
    if (!$name) { throw 'Profile name is required.' }
    $username = Ask 'Username (Enter = none)'
    $withPassword = Confirm 'Store a password?' $true
    if (!$username -and !$withPassword) { throw 'A profile needs a username, a password, or both.' }
    $window = Ask 'Window title, e.g. Sophos Connect (Enter = any title)'
    $process = Ask-Process '' 'Enter = any process'
    if ($process -eq '-') { $process = '' }
    if (!$window -and !$process -and !(Confirm-AnyWindow)) { throw 'Cancelled.' }
    $shortcut = Ask-Shortcut 'Alt+F1'
    $sequence = Ask-Sequence '' ([bool]$username) $withPassword
    $id = [guid]::NewGuid().ToString('N')
    if ($withPassword) { Set-Password $id }
    $profile = [pscustomobject]@{ id=$id; name=$name; username=$username; window=$window; process=$process; shortcut=$shortcut; sequence=$sequence; enabled=$true }
    return (@($profiles) + @($profile))
}
function Edit-Profile($profiles, [int]$index) {
    $p = $profiles[$index]
    Write-Host "`nEditing: $($p.name)"
    Write-Host ' 1) Name'; Write-Host ' 2) Username'; Write-Host ' 3) Window title'; Write-Host ' 4) Process'; Write-Host ' 5) Shortcut'; Write-Host ' 6) Sequence'; Write-Host ' 7) Set/change password'; Write-Host ' 8) Remove password'; Write-Host ' 9) Enable/disable'; Write-Host ' 0) Back'
    switch (Read-Host 'Choice') {
        '1' { $v=Ask 'Name' $p.name; if($v){$p.name=$v} }
        '2' {
            $v = Ask 'Username (- = none)' $p.username
            if ($v -eq '-') {
                if (!(Test-Password $p.id)) { throw 'Cannot remove the username from a profile without a password.' }
                $p.username = ''
            } elseif ($v) { $p.username = $v }
        }
        '3' {
            $v = Ask 'Window title (- = any title)' $p.window
            if ($v -eq '-') { if ($p.process -or (Confirm-AnyWindow)) { $p.window = '' } } elseif ($v) { $p.window = $v }
        }
        '4' {
            $v = Ask-Process $p.process '- = any process'
            if ($v -eq '-') { if ($p.window -or (Confirm-AnyWindow)) { $p.process = '' } } elseif ($v) { $p.process = $v }
        }
        '5' { $p.shortcut=Ask-Shortcut (Format-Shortcut $p.shortcut) }
        '6' { $p.sequence=Ask-Sequence $p.sequence ([bool]$p.username) (Test-Password $p.id) }
        '7' { Set-Password $p.id }
        '8' {
            if (!$p.username) { throw 'Cannot remove the password from a profile without a username.' }
            if (Confirm 'Really remove the stored password?') { Remove-Password $p.id }
        }
        '9' { $p.enabled = -not $p.enabled }
    }
    $hasUser = [bool]$p.username
    $hasPass = Test-Password $p.id
    if (!(Validate-Sequence $p.sequence $hasUser $hasPass)) {
        Write-Warning 'The sequence no longer matches the stored username/password; choose a new one.'
        $p.sequence = Ask-Sequence '' $hasUser $hasPass
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
        $map = [ordered]@{ id=$p.id; name=$p.name; username=$p.username; window=$p.window; process=$p.process; hotkey=$p.shortcut; sequence=$p.sequence }
        $pairs = foreach ($k in $map.Keys) { '"' + $k + '", ' + (Escape-Ahk $map[$k]) }
        $lines.Add('profiles.Push(Map(' + ($pairs -join ', ') + '))')
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

; Profiles restricted by window title and/or process take precedence over "any window" profiles.
FindProfiles(hotkeyName, target) {
    global profiles
    try title := WinGetTitle(target)
    catch
        return []
    proc := ""
    try proc := WinGetProcessName(target)
    specific := []
    generic := []
    for p in profiles {
        if p["hotkey"] != hotkeyName
            continue
        if p["window"] = "" && p["process"] = ""
            generic.Push(p)
        else if (p["window"] = "" || InStr(title, p["window"], false)) && (p["process"] = "" || p["process"] = proc)
            specific.Push(p)
    }
    return specific.Length ? specific : generic
}

HasMatchingProfile(hotkeyName) => FindProfiles(hotkeyName, "A").Length > 0

HandleLogin(hotkeyName) {
    hwnd := WinExist("A")
    if !hwnd
        return
    matched := FindProfiles(hotkeyName, "ahk_id " hwnd)
    if matched.Length = 0
        return
    if matched.Length = 1 {
        TypeLogin(matched[1], hwnd)
        return
    }
    ; Numbered labels keep duplicate profile names distinct and provide keyboard accelerators.
    picker := Menu()
    for p in matched
        picker.Add("&" A_Index " " StrReplace(p["name"], "&", "&&"), TypeLogin.Bind(p, hwnd))
    picker.Show()
}

TypeLogin(p, hwnd, *) {
    if !WinActive("ahk_id " hwnd) {
        try WinActivate("ahk_id " hwnd)
        if !WinWaitActive("ahk_id " hwnd, , 1)
            return
    }
    password := ""
    if InStr(p["sequence"], "{PASSWORD}") {
        try {
            password := DecryptPassword(p["id"])
        } catch as err {
            MsgBox "Unable to decrypt password: " err.Message "`nAt line: " err.Line, "SecureHotkey"
            return
        }
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
function Test-WritableDir([string]$path) {
    try {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        $probe = Join-Path $path ([guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllText($probe, '')
        Remove-Item -LiteralPath $probe
        return $true
    } catch { Write-Warning "Cannot write to ${path}: $($_.Exception.Message)"; return $false }
}
function Resolve-Root([string]$requested) {
    $saved = (Get-ItemProperty -Path $RegKey -Name InstallDir -ErrorAction SilentlyContinue).InstallDir
    $path = if ($requested) { $requested } else { $saved }
    while ($true) {
        if (!$path) {
            Write-Host 'Choose the installation directory for profiles, encrypted passwords and the launcher.'
            Write-Host "If C:\tools is not writable, use e.g. $env:LOCALAPPDATA\SecureHotkey"
            $path = Ask 'Installation directory' 'C:\tools\SecureHotkey'
        }
        $path = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($path.Trim('"')))
        if (Test-WritableDir $path) { break }
        $path = ''
    }
    if ($path -ne $saved) {
        if (!(Test-Path $RegKey)) { New-Item -Path $RegKey | Out-Null }
        Set-ItemProperty -Path $RegKey -Name InstallDir -Value $path
        if ($saved) { Write-Warning "Installation directory changed from $saved. Existing profiles were not moved." }
    }
    return $path
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

$Root = Resolve-Root $Root
$Store = Join-Path $Root 'credentials'
$Config = Join-Path $Root 'profiles.json'
$Launcher = Join-Path $Root 'launcher.ahk'
$AhkExe = Join-Path $Root 'AutoHotkey64.exe'
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
                    Remove-Password $id
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
            $conflicts = @($profiles | Where-Object enabled | Group-Object { "$($_.shortcut)|$("$($_.window)|$($_.process)".ToLowerInvariant())" } | Where-Object Count -gt 1)
            if ($conflicts.Count -gt 0) { Write-Warning 'Note: some enabled profiles share a shortcut and target; the launcher will show a menu to pick one.' }
            Save-Config $profiles
            Render-Launcher $profiles
            Write-Host 'Saved. Reload the launcher to apply changes.' -ForegroundColor Green
            Restart-Launcher
        }
    } catch { Write-Warning $_.Exception.Message; $profiles = @(Load-Config) }
}
