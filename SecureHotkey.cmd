@echo off
rem AutoHotkey tool (SecureHotkey.ps1). Bez menu: SecureHotkey.cmd build | run | release
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SecureHotkey.ps1" %*
exit /b %errorlevel%