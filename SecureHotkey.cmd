@echo off
rem Starts the interactive SecureHotkey manager (SecureHotkey.ps1). Optional: -Root "<install directory>"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SecureHotkey.ps1" %*
exit /b %errorlevel%